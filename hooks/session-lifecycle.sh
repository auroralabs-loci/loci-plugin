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

    # Start the LOCI bridge if not running
    BRIDGE_PID_FILE="${STATE_DIR}/bridge.pid"
    if [ ! -f "$BRIDGE_PID_FILE" ] || ! kill -0 "$(cat "$BRIDGE_PID_FILE")" 2>/dev/null; then
      python3 "${PLUGIN_DIR}/lib/loci_bridge.py" --state-dir "$STATE_DIR" --session "$SESSION_ID" </dev/null >/dev/null 2>&1 &
      echo $! > "$BRIDGE_PID_FILE"
    fi

    # Provide session context to Claude
    echo "LOCI execution-aware monitoring active for session ${SESSION_ID:0:8}..."
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
