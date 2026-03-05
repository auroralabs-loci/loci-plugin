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
_auto_install() {
  local pkg="$1"
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    brew install "$pkg"
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y "$pkg"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "$pkg"
  else
    return 1
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo -e "${YELLOW}jq not found — installing...${NC}"
  if ! _auto_install jq || ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}Failed to install jq. Please install it manually.${NC}"
    exit 1
  fi
  echo -e "${GREEN}jq installed${NC}"
fi

echo -e "${YELLOW}Installing binutils...${NC}"
_auto_install binutils
echo -e "${GREEN}binutils installed${NC}"

if ! command -v uv >/dev/null 2>&1; then
  echo -e "${YELLOW}uv not found — installing...${NC}"
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    brew install uv
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo -e "${RED}Failed to install uv. Please install it manually.${NC}"
    exit 1
  fi
  echo -e "${GREEN}uv installed${NC}"
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

# 4b. Set up asm-analyze environment
VENV_DIR="${PLUGIN_DIR}/.venv"
WHEEL_DIR="${PLUGIN_DIR}/asm-analyze-wheels"
ASM_ANALYZE_AVAILABLE=false
ASM_ANALYZE_LOG="${PLUGIN_DIR}/state/asm-analyze-setup.log"

install_asm_analyze() {
  : > "$ASM_ANALYZE_LOG"

  # Neutralize any globally-configured private package registries (e.g. GCP Artifact Registry)
  # that would block waiting for credentials. All deps come from the local wheel or PyPI.
  export UV_EXTRA_INDEX_URL=""
  export UV_INDEX_URL="https://pypi.org/simple/"

  if [ ! -d "$VENV_DIR" ]; then
    uv venv "$VENV_DIR" >> "$ASM_ANALYZE_LOG" 2>&1 || return 1
  fi

  VIRTUAL_ENV="$VENV_DIR" uv pip install loci_service_asmslicer --find-links "${WHEEL_DIR}" --no-index >> "$ASM_ANALYZE_LOG" 2>&1 || return 1
  VIRTUAL_ENV="$VENV_DIR" uv pip install unicorn >> "$ASM_ANALYZE_LOG" 2>&1 || true

  # The wheel may have undeclared dependencies — detect and install them
  for _attempt in 1 2 3 4 5; do
    MISSING=$("${VENV_DIR}/bin/python" -c "from loci.service.asmslicer import asmslicer" 2>&1 \
      | grep "ModuleNotFoundError" | head -1 \
      | sed "s/.*No module named '\([^']*\)'.*/\1/")
    if [ -z "$MISSING" ]; then
      return 0
    fi
    echo "Installing undeclared dependency: ${MISSING}" >> "$ASM_ANALYZE_LOG"
    VIRTUAL_ENV="$VENV_DIR" uv pip install "$MISSING" >> "$ASM_ANALYZE_LOG" 2>&1 || return 1
  done

  # Final verify after all deps installed
  "${VENV_DIR}/bin/python" -c "from loci.service.asmslicer import asmslicer" 2>>"$ASM_ANALYZE_LOG" || return 1
}

echo -n "Setting up asm-analyze environment... "
if ls "${WHEEL_DIR}"/*.whl 1>/dev/null 2>&1; then
  # Fast-path: skip install if venv already works for current wheel
  WHEEL_HASH=$(md5 -q "${WHEEL_DIR}"/*.whl 2>/dev/null || md5sum "${WHEEL_DIR}"/*.whl 2>/dev/null | awk '{print $1}')
  MARKER_FILE="${VENV_DIR}/.loci-wheel-hash"
  if [ -f "$MARKER_FILE" ] && [ "$(cat "$MARKER_FILE" 2>/dev/null)" = "$WHEEL_HASH" ] \
      && "${VENV_DIR}/bin/python" -c "from loci.service.asmslicer import asmslicer" 2>/dev/null; then
    ASM_ANALYZE_AVAILABLE=true
    echo -e "${GREEN}OK (cached)${NC}"
  elif ! install_asm_analyze; then
    # Stale or broken venv — nuke and retry once
    rm -rf "$VENV_DIR"
    if install_asm_analyze; then
      ASM_ANALYZE_AVAILABLE=true
      echo -e "${GREEN}OK (rebuilt venv)${NC}"
    else
      echo -e "${YELLOW}FAILED${NC}"
      echo -e "  ${YELLOW}See details: cat ${ASM_ANALYZE_LOG}${NC}"
      LAST_ERR=$(grep -iE '(error|no matching|not a supported|incompatible)' "$ASM_ANALYZE_LOG" | tail -1)
      if [ -n "$LAST_ERR" ]; then
        echo -e "  ${YELLOW}${LAST_ERR}${NC}"
      fi
    fi
  else
    ASM_ANALYZE_AVAILABLE=true
    echo "$WHEEL_HASH" > "$MARKER_FILE"
    echo -e "${GREEN}OK${NC}"
  fi
else
  echo -e "${YELLOW}no wheels in asm-analyze-wheels/ — asm-analyze disabled${NC}"
fi

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



# 7b. Detect venv Python path (cross-platform) for asm-analyze CLI
LOCI_ASM_ANALYZE_CMD=""
if [ "$ASM_ANALYZE_AVAILABLE" = true ]; then
  if [ -x "${VENV_DIR}/bin/python" ]; then
    VENV_PYTHON="${VENV_DIR}/bin/python"
  elif [ -x "${VENV_DIR}/Scripts/python.exe" ]; then
    VENV_PYTHON="${VENV_DIR}/Scripts/python.exe"
  else
    VENV_PYTHON=""
  fi
  if [ -n "$VENV_PYTHON" ]; then
    LOCI_ASM_ANALYZE_CMD="${VENV_PYTHON} ${PLUGIN_DIR}/lib/asm_analyze.py"
  fi
fi

# 8. Register hooks with Claude Code
echo -n "Registering hooks... "
PROJECT_ROOT="$(cd "${PLUGIN_DIR}/../../.." && pwd)"
SETTINGS_FILE="${PROJECT_ROOT}/.claude/settings.json"
mkdir -p "${PROJECT_ROOT}/.claude"

if [ -f "$SETTINGS_FILE" ] && grep -q "capture-action.sh" "$SETTINGS_FILE" 2>/dev/null; then
  echo -e "${GREEN}already registered${NC}"
else
  # Replace plugin root variable with absolute path using jq
  HOOKS_CONFIG=$(jq --arg pd "${PLUGIN_DIR}" '
    def replace_plugin_root:
      if type == "string" then
        gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $pd) |
        gsub("\\$CLAUDE_PLUGIN_ROOT"; $pd)
      elif type == "array" then map(replace_plugin_root)
      elif type == "object" then to_entries | map(.value |= replace_plugin_root) | from_entries
      else .
      end;
    replace_plugin_root
  ' "${PLUGIN_DIR}/hooks/hooks.json")

  if [ -f "$SETTINGS_FILE" ]; then
    # Merge hooks into existing settings.json
    HOOKS_ONLY=$(echo "$HOOKS_CONFIG" | jq '.hooks')
    if jq --argjson hooks "$HOOKS_ONLY" '. + {hooks: $hooks}' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" 2>/dev/null; then
      mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
      echo -e "${GREEN}OK (merged into existing settings.json)${NC}"
    else
      rm -f "${SETTINGS_FILE}.tmp"
      echo -e "${YELLOW}FAILED to merge — add hooks manually${NC}"
    fi
  else
    echo "$HOOKS_CONFIG" > "$SETTINGS_FILE"
    echo -e "${GREEN}OK${NC}"
  fi
fi

# 9. Install slash commands
echo -n "Installing slash commands... "
COMMANDS_DIR="${PROJECT_ROOT}/.claude/commands"
mkdir -p "$COMMANDS_DIR"
CMD_COUNT=0
for skill_dir in "${PLUGIN_DIR}/skills"/*/; do
  if [ -f "${skill_dir}SKILL.md" ]; then
    skill_name=$(basename "$skill_dir")
    if [ -n "$LOCI_ASM_ANALYZE_CMD" ]; then
      sed "s|\${LOCI_ASM_ANALYZE}|${LOCI_ASM_ANALYZE_CMD}|g" "${skill_dir}SKILL.md" > "${COMMANDS_DIR}/${skill_name}.md"
    else
      sed 's|\${LOCI_ASM_ANALYZE}|# asm-analyze unavailable|g' "${skill_dir}SKILL.md" > "${COMMANDS_DIR}/${skill_name}.md"
    fi
    CMD_COUNT=$((CMD_COUNT + 1))
  fi
done
echo -e "${GREEN}OK (${CMD_COUNT} commands: $(ls "${COMMANDS_DIR}"/*.md 2>/dev/null | xargs -I{} basename {} .md | paste -sd', '))${NC}"

# 10. Install LOCI context for Claude (optional)
if [ -f "${PLUGIN_DIR}/CLAUDE.md" ]; then
  echo -n "Installing LOCI context... "
  cp "${PLUGIN_DIR}/CLAUDE.md" "${PROJECT_ROOT}/.claude/CLAUDE.md"
  echo -e "${GREEN}OK${NC}"
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
if [ "$ASM_ANALYZE_AVAILABLE" = true ]; then
echo "  - Analyze ELF binaries locally via bundled asm-analyze CLI (symbols, assembly, blocks, diff)"
fi
echo ""
echo "Slash commands: /loci/analyze"
echo ""
echo "Restart Claude Code to activate."
echo ""
echo -e "${YELLOW}IMPORTANT: Authorize the LOCI MCP server in Claude Code${NC}"
echo "  1. Restart Claude Code"
echo "  2. Open any project file and start a conversation"
echo "  3. Claude will prompt you to approve the 'loci-plugin' MCP server"
echo "  4. Click 'Allow' to grant access"
echo ""
