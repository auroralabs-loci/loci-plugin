#!/bin/bash
# LOCI MCP Plugin - C++ Action Capture Hook
# Intercepts Claude Code tool uses in C++ engineering workflows.
# Classifies actions for LOCI binary-level execution-aware analysis.
# Receives JSON on stdin from Claude Code hook system.

set +e

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${PLUGIN_DIR}/state"
LOG_FILE="${STATE_DIR}/loci-actions.log"
ERROR_LOG="${STATE_DIR}/hook-errors.log"

mkdir -p "$STATE_DIR"

# Error handling function
log_error() {
    local msg="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] ERROR: $msg" >> "$ERROR_LOG" 2>/dev/null || true
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    log_error "jq not found in PATH - hook will not capture actions"
    # Graceful degradation: allow hook to complete without jq
    exit 0
fi

# Read hook input from stdin with error handling
if ! INPUT=$(cat 2>/dev/null); then
    log_error "Failed to read input from stdin"
    exit 0
fi

# Validate input is not empty
if [ -z "$INPUT" ]; then
    log_error "Received empty input"
    exit 0
fi

# Extract fields with error handling
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Validate minimum required fields
if [ -z "$TOOL_NAME" ]; then
    log_error "Missing TOOL_NAME in hook input"
    exit 0
fi

# Build the action record with error handling
# Pipe $INPUT through stdin instead of --argjson to avoid shell argument
# parsing issues with large or special-character-containing JSON.
if ! ACTION_RECORD=$(echo "$INPUT" | jq \
  --arg event "$HOOK_EVENT" \
  --arg session "$SESSION_ID" \
  --arg tool "$TOOL_NAME" \
  --arg cwd "$CWD" \
  --arg ts "$TIMESTAMP" \
  '{
    event: $event,
    session_id: $session,
    tool_name: $tool,
    cwd: $cwd,
    timestamp: $ts,
    tool_input: (.tool_input // {}),
    tool_response: (.tool_response // null)
  }' 2>/dev/null); then
    log_error "Failed to build action record for tool: $TOOL_NAME"
    exit 0
fi

# ---------------------------------------------------------------
# C++ focused action classification
# ---------------------------------------------------------------
classify_action() {
  local tool="$1"
  local input="$2"

  case "$tool" in
    Bash)
      local cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

      # C++ compilation (g++, clang++, gcc, clang)
      if echo "$cmd" | grep -qiE '(g\+\+|clang\+\+|gcc|clang|cc)\s'; then
        echo "cpp_compile"
      # Build systems (cmake, make, ninja, bazel)
      elif echo "$cmd" | grep -qiE '(cmake|make|ninja|meson|bazel|scons)\s'; then
        echo "cpp_build"
      # Linking
      elif echo "$cmd" | grep -qiE '(ld|lld|gold)\s'; then
        echo "cpp_link"
      # Binary analysis & disassembly — LOCI core domain
      elif echo "$cmd" | grep -qiE '(objdump|readelf|nm|strings|ldd|otool|dwarfdump|c\+\+filt|tiarmobjdump|tiarmreadelf|armofd|armdis|ielfdump)\s'; then
        echo "binary_analysis"
      # Assembly
      elif echo "$cmd" | grep -qiE '(nasm|as|yasm)\s'; then
        echo "assembly"
      # Performance profiling
      elif echo "$cmd" | grep -qiE '(perf|valgrind|gprof|callgrind|cachegrind|massif|heaptrack|vtune|nsys|ncu)\s'; then
        echo "performance_profiling"
      # Debugging
      elif echo "$cmd" | grep -qiE '(gdb|lldb|addr2line)\s'; then
        echo "debugging"
      # Static analysis
      elif echo "$cmd" | grep -qiE '(cppcheck|clang-tidy|scan-build|coverity|pvs-studio|iwyu)\s'; then
        echo "static_analysis"
      # Running a compiled binary (./binary_name)
      elif echo "$cmd" | grep -qiE '^\./[a-zA-Z_]'; then
        echo "binary_execution"
      # Diff on asm/binary files
      elif echo "$cmd" | grep -qiE 'diff.*\.(asm|s|o|bin)'; then
        echo "binary_diff"
      # LOCI asm-analyze CLI
      elif echo "$cmd" | grep -qiE 'asm_analyze\.py'; then
        echo "loci_asm_analyze_tool"
      # Package management
      elif echo "$cmd" | grep -qiE '(conan|vcpkg|apt|brew)\s+install'; then
        echo "dependency_install"
      # Testing frameworks
      elif echo "$cmd" | grep -qiE '(ctest|gtest|catch2|doctest|boost.test)'; then
        echo "cpp_test"
      # Version control
      elif echo "$cmd" | grep -qiE '(git|gh)\s'; then
        echo "version_control"
      else
        echo "shell_command"
      fi
      ;;
    Write|Edit)
      local file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

      # C++ source and header files
      if echo "$file" | grep -qiE '\.(cpp|cxx|cc|c\+\+|c|hpp|hxx|h|hh|inl|tpp)$'; then
        echo "cpp_source_modification"
      # Assembly files
      elif echo "$file" | grep -qiE '\.(asm|s|S)$'; then
        echo "assembly_modification"
      # Build config (CMakeLists, Makefile, etc.)
      elif echo "$file" | grep -qiE '(CMakeLists\.txt|Makefile|\.cmake|meson\.build|BUILD|\.bazel|conanfile)'; then
        echo "build_config_modification"
      # Linker scripts
      elif echo "$file" | grep -qiE '\.(ld|lds|map|def)$'; then
        echo "linker_config_modification"
      # General config
      elif echo "$file" | grep -qiE '\.(json|yaml|yml|toml|ini|cfg)$'; then
        echo "config_modification"
      elif echo "$file" | grep -qiE '\.(md|txt|rst)$'; then
        echo "documentation"
      else
        echo "file_modification"
      fi
      ;;
    Read|Glob|Grep)
      local target=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.pattern // .tool_input.path // empty')
      if echo "$target" | grep -qiE '\.(asm|s|S|o|so|a|bin|elf)'; then
        echo "binary_inspection"
      elif echo "$target" | grep -qiE '\.(cpp|cxx|cc|c|hpp|hxx|h|hh)'; then
        echo "cpp_code_analysis"
      else
        echo "code_analysis"
      fi
      ;;
    Task)
      echo "agent_delegation"
      ;;
    *)
      if echo "$tool" | grep -q "^mcp__loci-plugin__"; then
        echo "loci_mcp_tool"
      elif echo "$tool" | grep -q "^mcp__"; then
        echo "mcp_tool_call"
      else
        echo "other"
      fi
      ;;
  esac
}

ACTION_TYPE=$(classify_action "$TOOL_NAME" "$INPUT")

# ---------------------------------------------------------------
# Extract file paths and binary artifacts
# ---------------------------------------------------------------
extract_files() {
  local input="$1"
  echo "$input" | jq -r '
    [
      .tool_input.file_path,
      .tool_input.path,
      (try (.tool_input.command // "" | capture("(?<f>[/~.][^ \"]+\\.[a-zA-Z0-9]+)") | .f)),
      (try (.tool_input.command // "" | capture("-o\\s+(?<f>[^ \"]+)") | .f))
    ] | map(select(. != null and . != "")) | unique | .[]
  ' 2>/dev/null || true
}

FILES_INVOLVED=$(extract_files "$INPUT" | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null) || true
# Ensure FILES_INVOLVED is valid JSON for --argjson
if [ -z "$FILES_INVOLVED" ] || ! echo "$FILES_INVOLVED" | jq empty 2>/dev/null; then
  FILES_INVOLVED='[]'
fi

# ---------------------------------------------------------------
# Extract C++ compiler context for LOCI
# ---------------------------------------------------------------
COMPILER_FLAGS='[]'
OUTPUT_BINARY=""
OPTIMIZATION_LEVEL=""

if [ "$ACTION_TYPE" = "cpp_compile" ] || [ "$ACTION_TYPE" = "cpp_build" ] || [ "$ACTION_TYPE" = "cpp_link" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

  # Extract compiler flags
  COMPILER_FLAGS=$(echo "$CMD" | grep -oE '\-[Og][0-3sg]?|\-march=[^ ]+|\-std=[^ ]+|\-W[a-z-]+|\-f[a-z-]+|\-m[a-z0-9]+|\-l[a-z]+|\-D[A-Z_]+' 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))' || echo '[]')

  # Output binary
  OUTPUT_BINARY=$(echo "$CMD" | grep -oE '\-o\s+[^ ]+' | sed 's/-o *//' 2>/dev/null || true)

  # Optimization level (critical for LOCI binary analysis)
  OPTIMIZATION_LEVEL=$(echo "$CMD" | grep -oE '\-O[0-3sg]' | head -1 || true)
fi

# Ensure COMPILER_FLAGS is valid JSON for --argjson
if [ -z "$COMPILER_FLAGS" ] || ! echo "$COMPILER_FLAGS" | jq empty 2>/dev/null; then
  COMPILER_FLAGS='[]'
fi

# Enrich the action record with C++ classification
if ! ENRICHED_RECORD=$(echo "$ACTION_RECORD" | jq \
  --arg action_type "$ACTION_TYPE" \
  --argjson files "$FILES_INVOLVED" \
  --argjson compiler_flags "$COMPILER_FLAGS" \
  --arg output_binary "$OUTPUT_BINARY" \
  --arg optimization_level "$OPTIMIZATION_LEVEL" \
  '. + {
    action_type: $action_type,
    files_involved: $files,
    cpp_context: {
      compiler_flags: $compiler_flags,
      output_binary: $output_binary,
      optimization_level: $optimization_level
    }
  }' 2>/dev/null); then
    log_error "Failed to enrich record (action_type=$ACTION_TYPE files=$FILES_INVOLVED compiler_flags=$COMPILER_FLAGS)"
    ENRICHED_RECORD="$ACTION_RECORD"
fi

# Write to action log with error handling
if ! echo "$ENRICHED_RECORD" >> "$LOG_FILE" 2>/dev/null; then
    log_error "Failed to write to action log"
fi

# ---------------------------------------------------------------
# PreToolUse: steer Claude toward asm_analyze.py for binary analysis
# ---------------------------------------------------------------
if [ "$HOOK_EVENT" = "PreToolUse" ] && [ "$ACTION_TYPE" = "binary_analysis" ]; then
  LOCI_ASM_ANALYZE="${PLUGIN_DIR}/lib/asm_analyze.py"
  VENV_PYTHON="${PLUGIN_DIR}/.venv/bin/python3"
  if [ -f "$LOCI_ASM_ANALYZE" ]; then
    jq -n --arg asm_cmd "${VENV_PYTHON} ${LOCI_ASM_ANALYZE}" '{
      decision: "block",
      reason: ("Use LOCI asm-analyze instead of objdump/readelf/nm for binary analysis.\nasm-analyze extracts assembly in the exact format needed for LOCI timing predictions and auto-detects architecture from the ELF.\n\nCommands:\n  " + $asm_cmd + " extract-assembly --elf-path <file> [--functions fn1,fn2]\n  " + $asm_cmd + " extract-symbols --elf-path <file>\n  " + $asm_cmd + " diff-elfs --elf-path <old> --comparing-elf-path <new>\n\nThe output JSON includes timing_csv and timing_architecture — use those directly for the MCP tool call.")
    }'
    exit 0
  fi
fi

# For PostToolUse: track binary-producing actions
if [ "$HOOK_EVENT" = "PostToolUse" ]; then
  # Write pending regression check when a compile produced an architecture-targeted binary
  if [ "$ACTION_TYPE" = "cpp_compile" ] || [ "$ACTION_TYPE" = "cpp_build" ]; then
    ARCH_FLAG=$(echo "$COMPILER_FLAGS" | jq -r '.[] | select(startswith("-march=") or startswith("-mcpu="))' 2>/dev/null | head -1 || true)
    if [ -n "$OUTPUT_BINARY" ] && [ -n "$ARCH_FLAG" ]; then
      ARCH_VALUE=$(echo "$ARCH_FLAG" | sed 's/-m[a-z]*=//')
      jq -n \
        --arg binary "$OUTPUT_BINARY" \
        --arg arch "$ARCH_VALUE" \
        --arg ts "$TIMESTAMP" \
        '{binary_path: $binary, architecture: $arch, timestamp: $ts}' \
        > "${STATE_DIR}/pending-regression-check.json" 2>/dev/null || true
    fi
  fi
fi

# Graceful exit - even if there were errors, don't fail the hook
exit 0
