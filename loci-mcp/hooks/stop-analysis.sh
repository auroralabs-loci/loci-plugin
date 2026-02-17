#!/bin/bash
# LOCI MCP Plugin - Stop Analysis Hook
# Runs when Claude finishes responding. Provides a final summary of
# execution-aware insights gathered during the response.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${PLUGIN_DIR}/state"
WARNINGS_FILE="${STATE_DIR}/loci-warnings.json"
METRICS_FILE="${STATE_DIR}/loci-metrics.json"

# Check for any active critical warnings
if [ -f "$WARNINGS_FILE" ]; then
  CRITICAL_COUNT=$(jq '[.warnings[]? | select(.severity == "critical" and .active == true)] | length' "$WARNINGS_FILE" 2>/dev/null || echo 0)
  WARNING_COUNT=$(jq '[.warnings[]? | select(.severity == "warning" and .active == true)] | length' "$WARNINGS_FILE" 2>/dev/null || echo 0)

  if [ "$CRITICAL_COUNT" -gt 0 ]; then
    CRITICAL_MSGS=$(jq -r '[.warnings[] | select(.severity == "critical" and .active == true) | "- \(.category): \(.message)"] | join("\n")' "$WARNINGS_FILE" 2>/dev/null)

    jq -n --arg msgs "$CRITICAL_MSGS" --argjson count "$CRITICAL_COUNT" '{
      continue: false,
      stopReason: ("LOCI found " + ($count | tostring) + " critical issue(s) that should be addressed"),
      systemMessage: ("LOCI Execution Analysis - Critical Issues:\n" + $msgs)
    }'
    exit 0
  fi

  if [ "$WARNING_COUNT" -gt 0 ]; then
    WARNING_MSGS=$(jq -r '[.warnings[] | select(.severity == "warning" and .active == true) | "- [\(.category)] \(.message)"] | join("\n")' "$WARNINGS_FILE" 2>/dev/null)

    # Don't block, just inject context
    jq -n --arg msgs "$WARNING_MSGS" --argjson count "$WARNING_COUNT" '{
      systemMessage: ("LOCI detected " + ($count | tostring) + " warning(s):\n" + $msgs)
    }'
    exit 0
  fi
fi

# No issues found
exit 0
