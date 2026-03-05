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

    # Resolve venv Python (cross-platform)
    if [ -x "${PLUGIN_DIR}/.venv/bin/python" ]; then
      VENV_PYTHON="${PLUGIN_DIR}/.venv/bin/python"
    elif [ -x "${PLUGIN_DIR}/.venv/Scripts/python.exe" ]; then
      VENV_PYTHON="${PLUGIN_DIR}/.venv/Scripts/python.exe"
    else
      VENV_PYTHON="python3"
    fi

    # Start the LOCI bridge if not running
    BRIDGE_PID_FILE="${STATE_DIR}/bridge.pid"
    if [ ! -f "$BRIDGE_PID_FILE" ] || ! kill -0 "$(cat "$BRIDGE_PID_FILE")" 2>/dev/null; then
      "$VENV_PYTHON" "${PLUGIN_DIR}/lib/loci_bridge.py" --state-dir "$STATE_DIR" --session "$SESSION_ID" </dev/null >/dev/null 2>&1 &
      echo $! > "$BRIDGE_PID_FILE"
    fi

    # Inject detected project context for Claude
    ARCH_INFO=""
    if [ "$DETECTED_CONTEXT" != "{}" ]; then
      ARCH_INFO=$(echo "$DETECTED_CONTEXT" | jq -r '"Target: \(.architecture // "unknown"), Compiler: \(.compiler // "unknown"), Build: \(.build_system // "unknown")"' 2>/dev/null || echo "")
    fi

    LOCI_ASM_ANALYZE="${VENV_PYTHON} ${PLUGIN_DIR}/lib/asm_analyze.py"

    # Provide execution-aware context to Claude
    cat <<LOCI_CONTEXT
LOCI execution-aware plugin active. Session ${SESSION_ID:0:8}.
${ARCH_INFO:+$ARCH_INFO}

## When to use LOCI
- After writing/modifying C, C++, or Rust code: compile and measure execution time
- After compilation: extract assembly and call mcp__loci-plugin__get_assembly_block_exec_behavior
- When optimizing: compare before/after timing to detect regressions

## Partial processing with .o files
You do NOT need a fully linked binary. Compile individual source files with -c to produce .o object files, then:
- Extract assembly from the .o: ${LOCI_ASM_ANALYZE} extract-assembly --elf-path file.o --functions func_name --arch aarch64
- Diff two .o files to find changed functions: ${LOCI_ASM_ANALYZE} diff-elfs --elf-path old.o --comparing-elf-path new.o --arch aarch64
- Only measure changed/added functions — skip unchanged code entirely
This makes analysis fast and incremental: compile one file, slice the .o, measure only what changed.

## Mindset
Every line of C++ , C or RUST is an instruction sequence with real hardware consequences. Variable sizes, memory lifetimes, call ordering — they all show up in the assembly. Think about what the hardware actually does with every line you write.

## Available tools
- /loci/analyze — full workflow: compile, extract assembly, measure (execution time in ns, and energy in Ws)
- ${LOCI_ASM_ANALYZE} — ELF/object file slicer (extract-assembly, diff-elfs, slice-elf)
- mcp__loci-plugin__get_assembly_block_exec_behavior — timing/energy predictions
LOCI_CONTEXT
    ;;

  SessionEnd)
    SESSION_FILE="${SESSIONS_DIR}/${SESSION_ID}.json"
    if [ -f "$SESSION_FILE" ]; then
      jq --arg ts "$TIMESTAMP" '.status = "completed" | .ended_at = $ts' "$SESSION_FILE" > "${SESSION_FILE}.tmp"
      mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

      # Generate session summary for LOCI
      SUMMARY=$("${PLUGIN_DIR}/lib/generate-summary.sh" "$SESSION_FILE" 2>/dev/null || echo "")
      if [ -n "$SUMMARY" ]; then
        SUMMARY_FILE="${SESSIONS_DIR}/${SESSION_ID}-summary.json"
        echo "$SUMMARY" > "$SUMMARY_FILE"

        # Queue final summary for LOCI analysis
        QUEUE_DIR="${STATE_DIR}/queue"
        mkdir -p "$QUEUE_DIR"
        jq -n \
          --arg sid "$SESSION_ID" \
          --arg ts "$TIMESTAMP" \
          --argjson summary "$SUMMARY" \
          '{
            type: "session_complete",
            session_id: $sid,
            timestamp: $ts,
            summary: $summary
          }' > "${QUEUE_DIR}/${TIMESTAMP//[:.]/-}_session_end.json"
      fi
    fi
    ;;
esac

exit 0
