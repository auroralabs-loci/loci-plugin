#!/bin/bash
# LOCI MCP Plugin - Interactive Configuration Wizard
# Guides users through setup with validation and testing

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${PLUGIN_DIR}/config/loci.json"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   LOCI MCP Plugin Configuration Wizard                     ║${NC}"
echo -e "${BLUE}║   Configure execution-aware C++ analysis                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# Step 1: Verify Required Tools
# ============================================================================

echo -e "${YELLOW}Step 1: Verifying required tools...${NC}"
echo ""

MISSING_TOOLS=()

# Check jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗${NC} jq not found"
    MISSING_TOOLS+=("jq")
else
    echo -e "${GREEN}✓${NC} jq installed"
fi

# Check C++ compiler
if command -v g++ &> /dev/null; then
    echo -e "${GREEN}✓${NC} g++ found"
    COMPILER="g++"
elif command -v clang++ &> /dev/null; then
    echo -e "${GREEN}✓${NC} clang++ found"
    COMPILER="clang++"
else
    echo -e "${RED}✗${NC} No C++ compiler found (g++ or clang++ required)"
    MISSING_TOOLS+=("c++ compiler")
    COMPILER="unknown"
fi

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗${NC} python3 not found"
    MISSING_TOOLS+=("python3")
else
    echo -e "${GREEN}✓${NC} python3 installed"
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Missing tools: ${MISSING_TOOLS[*]}${NC}"
    echo ""
    echo "Install with:"
    echo "  macOS:  brew install jq"
    echo "  Ubuntu: sudo apt-get install jq"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""

# ============================================================================
# Step 2: Configure MCP Server Connection
# ============================================================================

echo -e "${YELLOW}Step 2: Configure LOCI MCP server connection${NC}"
echo ""

# Get or use default values
MCP_URL="${LOCI_MCP_URL:-https://dev.mcp.loci-dev.net/mcp}"

# MCP Server URL
read -p "MCP Server URL [$MCP_URL]: " -r input
MCP_URL="${input:-$MCP_URL}"

echo ""

# ============================================================================
# Step 3: Detect Project Context
# ============================================================================

echo -e "${YELLOW}Step 3: Detecting C++ project context...${NC}"
echo ""

CWD="$(pwd)"
PROJECT_CONTEXT=$("${PLUGIN_DIR}/lib/detect-project.sh" "$CWD" 2>/dev/null || echo '{}')

if [ "$PROJECT_CONTEXT" = "{}" ]; then
    echo -e "${YELLOW}!${NC} Could not auto-detect project context"
    echo "  This may be a non-C++ project or the first setup"
else
    echo -e "${GREEN}✓${NC} Project context detected"
    echo "$PROJECT_CONTEXT" | jq '.compiler, .build_system, .architecture' | sed 's/^/  /'
fi

echo ""

# ============================================================================
# Step 4: Tuning Configuration
# ============================================================================

echo -e "${YELLOW}Step 4: Performance tuning (optional)${NC}"
echo ""

POLL_INTERVAL="2.0"
BATCH_SIZE="10"
ANALYSIS_TIMEOUT="30.0"
REGRESSION_THRESHOLD="0.10"

read -p "Poll interval in seconds [$POLL_INTERVAL]: " -r input
POLL_INTERVAL="${input:-$POLL_INTERVAL}"

read -p "Batch size for analysis [$BATCH_SIZE]: " -r input
BATCH_SIZE="${input:-$BATCH_SIZE}"

read -p "Analysis timeout in seconds [$ANALYSIS_TIMEOUT]: " -r input
ANALYSIS_TIMEOUT="${input:-$ANALYSIS_TIMEOUT}"

read -p "Regression threshold (0.10 = block if >10% slower) [$REGRESSION_THRESHOLD]: " -r input
REGRESSION_THRESHOLD="${input:-$REGRESSION_THRESHOLD}"

echo ""

# ============================================================================
# Step 5: Test Connection
# ============================================================================

echo -e "${YELLOW}Step 5: Testing MCP server connection...${NC}"
echo ""

if command -v curl &> /dev/null; then
    if timeout 5 curl -s -I "$MCP_URL" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} MCP server is reachable"
    else
        echo -e "${YELLOW}!${NC} Could not reach MCP server at $MCP_URL"
        echo "  Check the URL and network connection"
    fi
else
    echo -e "${YELLOW}!${NC} curl not available, skipping connection test"
fi

echo ""

# ============================================================================
# Step 6: Save Configuration
# ============================================================================

echo -e "${YELLOW}Step 6: Saving configuration...${NC}"
echo ""

# Create config directory if needed
mkdir -p "$(dirname "$CONFIG_FILE")"

# Build configuration JSON
CONFIG_JSON=$(jq -n \
  --arg url "$MCP_URL" \
  --arg poll "$POLL_INTERVAL" \
  --argjson batch "$BATCH_SIZE" \
  --arg timeout "$ANALYSIS_TIMEOUT" \
  --arg threshold "$REGRESSION_THRESHOLD" \
  '{
    "mcp_server_url": $url,
    "mcp_server_name": "loci-plugin",
    "poll_interval": ($poll | tonumber),
    "batch_size": ($batch | tonumber),
    "analysis_timeout": ($timeout | tonumber),
    "regression_threshold": ($threshold | tonumber),
    "enabled": true,
    "_comment": "The LOCI MCP server is configured in .mcp.json at project root. Claude Code connects to it directly."
  }')

echo "$CONFIG_JSON" > "$CONFIG_FILE"
echo -e "${GREEN}✓${NC} Configuration saved to $CONFIG_FILE"

echo ""
echo -e "${GREEN}Configuration Summary:${NC}"
echo "  MCP Server: $MCP_URL"
echo "  Poll Interval: ${POLL_INTERVAL}s"
echo "  Batch Size: $BATCH_SIZE"
echo "  Timeout: ${ANALYSIS_TIMEOUT}s"
echo "  Regression Threshold: $(echo "$REGRESSION_THRESHOLD * 100" | bc)%"

echo ""

# ============================================================================
# Step 7: Initialize State Directory
# ============================================================================

echo -e "${YELLOW}Step 7: Initializing state directory...${NC}"
echo ""

STATE_DIR="${PLUGIN_DIR}/state"
mkdir -p "$STATE_DIR"

# Initialize state files
jq -n '{"warnings": []}' > "${STATE_DIR}/loci-warnings.json"
[ -f "${STATE_DIR}/loci-baselines.json" ] || jq -n '{}' > "${STATE_DIR}/loci-baselines.json"

echo -e "${GREEN}✓${NC} State directory initialized at $STATE_DIR"

echo ""

# ============================================================================
# Step 8: Show Next Steps
# ============================================================================

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Configuration Complete!                                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo "Next steps:"
echo ""
echo "1. Install the plugin in Claude Code:"
echo "   - Use Claude Code's plugin installation UI"
echo "   - Point to: $(pwd)"
echo ""
echo "2. Start a C++ coding session:"
echo "   - Claude Code will automatically capture your workflow"
echo "   - LOCI will provide performance insights"
echo ""
echo "3. Monitor plugin activity:"
echo "   python3 ${PLUGIN_DIR}/scripts/monitor-hooks.py"
echo ""
echo "4. View execution graph:"
echo "   python3 ${PLUGIN_DIR}/lib/task_tracker.py --state-dir ${STATE_DIR} --graph"
echo ""
echo "5. Check for issues:"
echo "   cat ${STATE_DIR}/hook-errors.log"
echo ""

echo "Documentation: ${PLUGIN_DIR}/../../README.md"
echo ""

read -p "Would you like to open the README now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v less &> /dev/null; then
        less "${PLUGIN_DIR}/../../README.md"
    elif command -v cat &> /dev/null; then
        cat "${PLUGIN_DIR}/../../README.md" | head -100
    fi
fi

echo ""
echo -e "${GREEN}Setup complete! Happy optimizing! 🚀${NC}"
