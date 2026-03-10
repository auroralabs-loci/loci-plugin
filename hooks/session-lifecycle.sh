#!/bin/bash
# LOCI MCP Plugin - Session Lifecycle Hook
# Handles SessionStart and SessionEnd to manage LOCI context windows.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${PLUGIN_DIR}/state"
SESSIONS_DIR="${STATE_DIR}/sessions"

mkdir -p "$STATE_DIR" "$SESSIONS_DIR"

INPUT=$(cat)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$HOOK_EVENT" in
  SessionStart)
    SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

    # Create session manifest
    SESSION_FILE="${SESSIONS_DIR}/${SESSION_ID}.json"
    jq -n \
      --arg sid "$SESSION_ID" \
      --arg cwd "$CWD" \
      --arg ts "$TIMESTAMP" \
      --arg source "$SOURCE" \
      '{
        session_id: $sid,
        started_at: $ts,
        source: $source,
        cwd: $cwd,
        status: "active",
        actions_count: 0,
        files_modified: [],
        files_read: [],
        commands_executed: [],
        loci_analyses: [],
        execution_context: {
          project_type: null,
          language_stack: [],
          build_system: null,
          detected_at: null
        }
      }' > "$SESSION_FILE"

    # Auto-detect project context
    DETECTED_CONTEXT=$("${PLUGIN_DIR}/lib/detect-project.sh" "$CWD" 2>/dev/null || echo '{}')
    if [ "$DETECTED_CONTEXT" != "{}" ]; then
      jq --argjson ctx "$DETECTED_CONTEXT" '.execution_context = $ctx' "$SESSION_FILE" > "${SESSION_FILE}.tmp"
      mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    fi

    # Inject detected project context for Claude
    ARCH_INFO=""
    LOCI_COMPATIBLE="false"
    LOCI_TARGET=""
    DETECTED_ARCH=""
    if [ "$DETECTED_CONTEXT" != "{}" ]; then
      ARCH_INFO=$(echo "$DETECTED_CONTEXT" | jq -r '"Target: \(.architecture // "unknown"), Compiler: \(.compiler // "unknown"), Build: \(.build_system // "unknown")"' 2>/dev/null || echo "")
      LOCI_COMPATIBLE=$(echo "$DETECTED_CONTEXT" | jq -r '.loci_compatible // false' 2>/dev/null || echo "false")
      LOCI_TARGET=$(echo "$DETECTED_CONTEXT" | jq -r '.loci_target // empty' 2>/dev/null || echo "")
      DETECTED_ARCH=$(echo "$DETECTED_CONTEXT" | jq -r '.architecture // "unknown"' 2>/dev/null || echo "unknown")
    fi

    LOCI_ASM_ANALYZE="${PLUGIN_DIR}/lib/asm_analyze.py"

    # Extract ELF files and build compiler from detection
    ELF_FILES=""
    BUILD_COMPILER=""
    if [ "$DETECTED_CONTEXT" != "{}" ]; then
      ELF_FILES=$(echo "$DETECTED_CONTEXT" | jq -r '.elf_files // [] | map(select(. != null)) | join(", ")' 2>/dev/null || echo "")
      BUILD_COMPILER=$(echo "$DETECTED_CONTEXT" | jq -r '.build_compiler // empty' 2>/dev/null || echo "")
    fi

    if [ "$LOCI_COMPATIBLE" = "true" ] && [ -n "$LOCI_TARGET" ]; then
      # Provide execution-aware context to Claude
      cat <<LOCI_CONTEXT
LOCI execution-aware plugin active. Session ${SESSION_ID:0:8}.
${ARCH_INFO:+$ARCH_INFO}
LOCI target: ${LOCI_TARGET}
${BUILD_COMPILER:+Build compiler (from project config): ${BUILD_COMPILER}}
${ELF_FILES:+Existing ELF/object files found: ${ELF_FILES}}

## IMPORTANT: Use asm_analyze.py for ALL binary/ELF analysis
NEVER use objdump, readelf, nm, tiarmobjdump, or other disassembly tools.
ALWAYS use the LOCI asm-analyze CLI instead — it extracts assembly in the exact format needed for LOCI timing predictions.

asm-analyze CLI: ${LOCI_ASM_ANALYZE}
Run it from the plugin's .venv: ${PLUGIN_DIR}/.venv/bin/python3 ${LOCI_ASM_ANALYZE}

## How to analyze with LOCI (in priority order)

### 1. If ELF/object files already exist — use them directly
The project may already have compiled .elf, .out, .o, or .axf files from its own build system.
asm_analyze.py auto-detects architecture from the ELF — no need to specify --arch:
  ${LOCI_ASM_ANALYZE} extract-assembly --elf-path <file>
  ${LOCI_ASM_ANALYZE} extract-symbols --elf-path <file>
  ${LOCI_ASM_ANALYZE} diff-elfs --elf-path <old> --comparing-elf-path <new>

### 2. If you need to compile — use the project's own build system first
Look at the project's Makefile, CMakeLists.txt, build scripts, or IDE project files to understand how it builds.
Use the project's own compiler and flags. Do NOT cross-compile with a different toolchain unless the project has no build system.

### 3. Cross-compile as last resort (no existing build)
Only if the project has no build system and no compiled artifacts:
| Architecture | Compiler | Flags |
|---|---|---|
| aarch64 | aarch64-linux-gnu-g++ | -O2 -march=armv8-a |
| cortexm | arm-none-eabi-g++ | -O2 -mcpu=cortex-m4 -mthumb |
| tricore | tricore-elf-g++ | -O2 |

## Feeding asm_analyze output into the MCP tool
The extract-assembly command outputs JSON with two key fields:
- **timing_csv** — CSV text ready for the MCP tool's csv_text parameter
- **timing_architecture** — architecture string ready for the MCP tool's architecture parameter

Call mcp__loci-plugin__get_assembly_block_exec_behavior with:
  csv_text = the timing_csv value from extract-assembly output
  architecture = the timing_architecture value from extract-assembly output

## Partial processing with .o files
You do NOT need a fully linked binary. Compile individual source files with -c to produce .o object files, then:
- Extract assembly from the .o: ${LOCI_ASM_ANALYZE} extract-assembly --elf-path file.o --functions func_name
- Diff two .o files to find changed functions: ${LOCI_ASM_ANALYZE} diff-elfs --elf-path old.o --comparing-elf-path new.o
- Only measure changed/added functions — skip unchanged code entirely
This makes analysis fast and incremental: compile one file, slice the .o, measure only what changed.

## How LOCI works
LOCI predictions come from a Large Code Language Model (LCLM) trained on real hardware execution traces — cycle-accurate SW/HW trace data collected from physical boards (Cortex-A53, Cortex-M4, TriCore TC399) at assembly-block granularity. These are not heuristics or simulator estimates — they reflect measured behavior of real silicon. The std_dev returned with each prediction quantifies the model's confidence based on how well the input assembly matches its training distribution.

## Mindset
Every line of C++, C, or Rust is an instruction sequence with real hardware consequences. Variable sizes, memory lifetimes, call ordering — they all show up in the assembly. Think about what the hardware actually does with every line you write.
LOCI_CONTEXT
    else
      cat <<LOCI_NOTICE
LOCI plugin active but project targets \`${DETECTED_ARCH}\` which is not a native LOCI target. LOCI supports three architectures:
- **aarch64** (Cortex-A53 / ARMv8-A 64-bit) — cross-compile with aarch64-linux-gnu-g++
- **cortexm** (Cortex-M4 / ARMv7E-M Thumb2) — cross-compile with arm-none-eabi-g++
- **tricore** (TriCore TC399 / TC3xx) — cross-compile with tricore-elf-g++

IMPORTANT: Always use asm_analyze.py (not objdump/readelf) for binary analysis:
  ${LOCI_ASM_ANALYZE} extract-assembly --elf-path <file>
It auto-detects architecture. Output includes timing_csv and timing_architecture for the MCP tool.
LOCI_NOTICE
    fi
    ;;

  SessionEnd)
    SESSION_FILE="${SESSIONS_DIR}/${SESSION_ID}.json"
    if [ -f "$SESSION_FILE" ]; then
      jq --arg ts "$TIMESTAMP" '.status = "completed" | .ended_at = $ts' "$SESSION_FILE" > "${SESSION_FILE}.tmp"
      mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

      # Generate session summary
      SUMMARY=$("${PLUGIN_DIR}/lib/generate-summary.sh" "$SESSION_FILE" 2>/dev/null || echo "")
      if [ -n "$SUMMARY" ]; then
        SUMMARY_FILE="${SESSIONS_DIR}/${SESSION_ID}-summary.json"
        echo "$SUMMARY" > "$SUMMARY_FILE"
      fi
    fi
    ;;
esac

exit 0
