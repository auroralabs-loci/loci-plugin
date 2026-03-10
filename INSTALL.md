# LOCI Plugin — Installation Guide

## Overview

The LOCI plugin adds execution-aware C++ analysis to Claude Code. It has two sides:

- **Local side** — hooks and a bundled ELF asm-analyze CLI that run entirely on your machine.
- **Remote side** — an MCP server (SSE) that predicts execution time, standard deviation, and energy consumption for assembly functions on embedded targets (Cortex-A53, Cortex-M4, TriCore TC399).

Running `setup.sh` wires these together into your project in one step.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| `jq` | Installed automatically if missing (Homebrew / apt / dnf) |
| `binutils` | Installed automatically (`objdump` is needed for ELF disassembly) |
| `uv` | Installed automatically (Homebrew or `astral.sh/uv`); manages the Python venv |
| Python 3.12 | Managed by `uv` — no system Python required |
| `g++` or `clang++` | Detected but **not** installed; must already be present |
| Cross-compiler | For embedded targets (e.g., `arm-none-eabi-g++` for Cortex-M4); not installed by setup |

---

## What gets installed

### 1. System packages

`jq`, `binutils`, and `uv` are installed automatically if not found, using whatever package manager is available on the host (`brew`, `apt-get`, or `dnf`).

### 2. Python virtual environment — `loci-plugin/.venv/`

A Python 3.12 venv is created and the following packages are installed from `loci-plugin/asm-analyze-wheels/` and PyPI:

| Package | Source | Purpose |
|---------|--------|---------|
| `loci_service_asm_analyze` | bundled `.whl` | Core ELF analysis library (assembly extraction, symbol maps, binary diffs, timing CSV output) |
| `unicorn` | PyPI | CPU emulation engine used internally by asm-analyze |
| *(undeclared deps)* | PyPI | Detected by import probing and installed automatically |

The venv is hash-checked against the bundled wheel on every `setup.sh` run — if the wheel hasn't changed the venv is reused as-is.

If no `.whl` is found in `asm-analyze-wheels/`, the venv step is skipped. The remote timing backend still works without asm-analyze.

### 3. State directories — `loci-plugin/state/`

| Path | Purpose |
|------|---------|
| `state/sessions/` | Per-session manifests (written at `SessionStart` / `SessionEnd`) |
| `state/loci-baselines.json` | Timing baselines per function, used for regression detection across sessions |

Runtime files created during normal operation (not by setup):

| File | Written by | Purpose |
|------|-----------|---------|
| `state/loci-warnings.json` | Hook scripts | Active warnings surfaced to Claude's context |
| `state/loci-actions.log` | Hook scripts | Append-only line-delimited JSON audit trail |
| `state/hook-errors.log` | Hook scripts | Hook script failures |

### 4. Claude Code hooks — `.claude/settings.json`

Hooks are merged into (or written to) `<project-root>/.claude/settings.json` with absolute paths:

| Event | Trigger | Script | Behaviour |
|-------|---------|--------|-----------|
| `SessionStart` | Always | `session-lifecycle.sh` | Writes session manifest, detects project context |
| `SessionEnd` | Always | `session-lifecycle.sh` | Generates session summary |
| `PreToolUse` | `Bash` | `capture-action.sh` | Classifies action type |
| `PreToolUse` | `Write` / `Edit` | `capture-action.sh` | Classifies action type |
| `PreToolUse` | `Task`, MCP calls | `capture-action.sh` | Classifies action type |
| `PostToolUse` | `Bash`, `Write`, `Edit`, MCP | `capture-action.sh` | Logs classified action, tracks compilation artifacts |
| `Stop` | Always | `stop-analysis.sh` | Surfaces critical warnings; blocks Claude if any are active |
| `Stop` | Always | Agent prompt | Runs timing regression check against stored baselines |

### 5. Slash commands — `.claude/commands/`

Installed from `loci-plugin/skills/*/SKILL.md` with the asm-analyze CLI path substituted in at install time:

| Command | Purpose |
|---------|---------|
| `/loci/exec-trace` | Full pipeline: compile → extract assembly → measure execution time and energy |
| `/loci/slice` | Extract assembly blocks and symbols from an ELF binary |
| `/loci/exec-behavior` | Call the timing MCP tool directly with a CSV of assembly blocks |
| `/loci/profile-blocks` | Profile individual basic blocks for hotspot identification |

### 6. LOCI context — `.claude/CLAUDE.md`

Copied from `loci-plugin/CLAUDE.md`. Provides Claude with architecture documentation, data-flow diagrams, heuristic tables, and CLI references so it understands the plugin's internals.

---

## File layout after installation

```
<project-root>/
├── .mcp.json                      ← MCP server config (Claude Code reads this)
└── .claude/
    ├── settings.json              ← hooks merged here (absolute paths)
    ├── CLAUDE.md                  ← LOCI architecture context for Claude
    └── commands/
        ├── exec-trace.md          ← /loci/exec-trace slash command
        ├── slice.md               ← /loci/slice slash command
        ├── exec-behavior.md       ← /loci/exec-behavior slash command
        └── profile-blocks.md      ← /loci/profile-blocks slash command

loci-plugin/
├── .venv/                         ← Python 3.12 venv (asm-analyze + deps)
├── state/                         ← runtime state (queue, logs, baselines)
├── hooks/                         ← shell hook scripts called by Claude Code
├── lib/                           ← asm-analyze CLI, utilities
├── skills/                        ← slash command source templates
├── asm-analyze-wheels/            ← bundled asm-analyze wheel
└── config/loci.json               ← plugin configuration
```

---

## Installation steps

### 1. Place the plugin

The plugin must sit three directories below the project root so `setup.sh` can locate the project root automatically.

```
<project-root>/
└── .claude/
    └── plugins/
        └── loci-plugin/    ← plugin lives here
            ├── setup.sh
            └── ...
```

### 2. Add the asm-analyze wheel (optional)

Copy the provided `.whl` file into `asm-analyze-wheels/`:

```bash
cp loci_service_asmslicer-*.whl .claude/plugins/loci-plugin/asm-analyze-wheels/
```

If you skip this, all slash commands and the timing backend still work — only local ELF analysis (assembly extraction, symbol maps, binary diffs) requires asm-analyze.

### 3. Run setup

```bash
.claude/plugins/loci-plugin/setup.sh
```

### 4. Restart Claude Code and authorize the MCP server

1. Restart Claude Code.
2. Open any project file and start a conversation.
3. Claude will prompt you to approve the `loci-plugin` MCP server — click **Allow**.

---

## Verification

```bash
# Hooks registered
cat .claude/settings.json | jq '.hooks | keys'
# → ["PostToolUse", "PreToolUse", "SessionEnd", "SessionStart", "Stop"]

# MCP server configured
cat .mcp.json | jq .

# Slash commands installed
ls .claude/commands/

# asm-analyze venv works
.claude/plugins/loci-plugin/.venv/bin/python \
  -c "from loci.service.asmslicer import asmslicer; print('OK')"
```

Inside Claude Code:
- `/mcp` — should list `loci-plugin`
- Type `/loci` and look for `analyze`, `slice`, `exec-behavior`, `profile-blocks`

---

## Troubleshooting

**No `.mcp.json` created** — Re-run `setup.sh`. It should always complete all steps regardless of asm-analyze wheel availability.

**No MCP servers in `/mcp`** — Verify `.mcp.json` is at the project root (not inside `.claude/`):
```bash
cat .mcp.json
```
If missing, re-run setup. If present, restart Claude Code from the project root.

**No slash commands** — Check `.claude/commands/` is populated. Re-run `setup.sh` if empty.

**Hooks not firing** — Confirm `.claude/settings.json` has hook entries:
```bash
cat .claude/settings.json | jq '.hooks | keys'
```
Should show all five hook events.

**"no wheels in asm-analyze-wheels/"** — Drop the `.whl` file into `asm-analyze-wheels/` and re-run setup.

**asm-analyze venv creation failed** — Check the log:
```bash
cat loci-plugin/state/asm-analyze-setup.log
```

**Timing backend unreachable** — The MCP server is remote (SSE). Check network access to the URL in `.mcp.json`. asm-analyze works entirely offline.
