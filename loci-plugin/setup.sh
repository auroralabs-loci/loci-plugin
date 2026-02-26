#!/bin/bash
# LOCI MCP Plugin - C++ Setup Script

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  LOCI MCP Plugin for Claude Code${NC}"
echo -e "${BLUE}  SW Execution-Aware Analysis${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# 1. Check dependencies
echo -n "Checking dependencies... "
MISSING=()
command -v jq >/dev/null 2>&1 || MISSING+=("jq")
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo -e "${RED}MISSING${NC}"
  echo "  Please install: ${MISSING[*]}"
  exit 1
fi
echo -e "${GREEN}OK${NC}"

# 2. Check C++ toolchain
echo -n "Checking C++ compiler... "
if command -v g++ >/dev/null 2>&1; then
  echo -e "${GREEN}g++ $(g++ --version | head -1)${NC}"
elif command -v clang++ >/dev/null 2>&1; then
  echo -e "${GREEN}clang++ $(clang++ --version | head -1)${NC}"
else
  echo -e "${YELLOW}No C++ compiler found (g++/clang++)${NC}"
fi

# 3. Permissions
echo -n "Setting permissions... "
chmod +x "${PLUGIN_DIR}/hooks/"*.sh
chmod +x "${PLUGIN_DIR}/lib/"*.sh
chmod +x "${PLUGIN_DIR}/lib/"*.py
echo -e "${GREEN}OK${NC}"

# 4. Create state directories
echo -n "Creating state directories... "
mkdir -p "${PLUGIN_DIR}/state/queue"
mkdir -p "${PLUGIN_DIR}/state/sessions"
mkdir -p "${PLUGIN_DIR}/state/analysis-queue"
[ -f "${PLUGIN_DIR}/state/loci-baselines.json" ] || echo '{}' > "${PLUGIN_DIR}/state/loci-baselines.json"
echo -e "${GREEN}OK${NC}"

# 5. Detect project
echo -n "Detecting  project... "
PROJECT_INFO=$("${PLUGIN_DIR}/lib/detect-project.sh" "$(pwd)" 2>/dev/null || echo '{}')
COMPILER=$(echo "$PROJECT_INFO" | jq -r '.compiler // "unknown"')
BUILD_SYS=$(echo "$PROJECT_INFO" | jq -r '.build_system // "unknown"')
ARCH=$(echo "$PROJECT_INFO" | jq -r '.architecture // "unknown"')
NUM_SRC=$(echo "$PROJECT_INFO" | jq '.source_files | length')
NUM_BIN=$(echo "$PROJECT_INFO" | jq '.binaries | length')
NUM_ASM=$(echo "$PROJECT_INFO" | jq '.asm_files | length')
echo -e "${GREEN}OK${NC}"
echo "  Compiler:   $COMPILER"
echo "  Build:      $BUILD_SYS"
echo "  Arch:       $ARCH"
echo "  Sources:    $NUM_SRC files"
echo "  Binaries:   $NUM_BIN found"
echo "  Assembly:   $NUM_ASM files"

# 6. Validate hooks.json
echo -n "Validating hooks... "
if jq empty "${PLUGIN_DIR}/hooks/hooks.json" 2>/dev/null; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}INVALID hooks/hooks.json${NC}"
  exit 1
fi

# 7. Check .mcp.json
echo -n "Checking LOCI MCP server config... "
PROJECT_ROOT="$(cd "${PLUGIN_DIR}/../../.." && pwd)"
if [ -f "${PROJECT_ROOT}/.mcp.json" ]; then
  MCP_URL=$(jq -r '.mcpServers["loci-mcp"].url // empty' "${PROJECT_ROOT}/.mcp.json" 2>/dev/null)
  if [ -n "$MCP_URL" ]; then
    echo -e "${GREEN}${MCP_URL}${NC}"
  else
    echo -e "${YELLOW}loci-mcp not found in .mcp.json${NC}"
  fi
else
  echo -e "${YELLOW}.mcp.json not found${NC}"
  echo "  Creating .mcp.json with LOCI MCP server..."
  echo '{
  "mcpServers": {
    "loci-mcp": {
      "type": "http",
      "url": "https://dev.local.mcp.loci-dev.net/mcp"
    }
  }
}' > "${PROJECT_ROOT}/.mcp.json"
  echo -e "  ${GREEN}Created${NC}"
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "The plugin will automatically:"
echo "  - Capture C++ compilations (g++/clang++ flags, -O levels, -march)"
echo "  - Track binary artifacts and source-to-binary relationships"
echo "  - Monitor assembly file changes and binary diffs"
echo "  - Stream context to LOCI MCP for execution-aware analysis"
echo "  - Inject performance/regression warnings into Claude's context"
echo ""
echo "Restart Claude Code to activate."
echo ""
