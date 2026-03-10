# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Tool Instructions (read this first)

### Binary/ELF analysis — ALWAYS use asm_analyze.py

When you need to disassemble, inspect symbols, or analyze ELF/object files, **always use `lib/asm_analyze.py`** instead of `objdump`, `readelf`, `nm`, `tiarmobjdump`, or any other disassembly tool. asm_analyze.py extracts assembly in the exact format needed for LOCI timing predictions.

```bash
# Run from the plugin's .venv:
.venv/bin/python3 lib/asm_analyze.py extract-assembly --elf-path <file> [--functions fn1,fn2]
.venv/bin/python3 lib/asm_analyze.py extract-symbols --elf-path <file>
.venv/bin/python3 lib/asm_analyze.py diff-elfs --elf-path <old> --comparing-elf-path <new>
.venv/bin/python3 lib/asm_analyze.py slice-elf --elf-path <file> [--output-types asm,symbols,blocks]
.venv/bin/python3 lib/asm_analyze.py extract-cfg --elf-path <file> --functions fn1,fn2
```

**Architecture is auto-detected from the ELF.** You do not need to specify `--arch` unless the file has no ELF header info. If you do need to specify it, accepted values are:
- **aarch64** group: `aarch64`, `arm64`, `cortex-a53`, `armv8-a`
- **cortexm** group: `cortexm`, `cortex-m`, `cortex-m4`, `armv7e-m`, `thumb`
- **tricore** group: `tricore`, `tc399`, `tc3xx`

### Feeding results into the MCP tool

The `extract-assembly` output JSON contains two fields that map directly to the MCP tool parameters:
- `timing_csv` → use as `csv_text`
- `timing_architecture` → use as `architecture`

```
mcp__loci-plugin__get_assembly_block_exec_behavior(
  csv_text = <timing_csv from extract-assembly>,
  architecture = <timing_architecture from extract-assembly>
)
```

Do NOT guess the `architecture` value — always use `timing_architecture` from the asm_analyze output.

### Analyzing existing project builds

When a project already has compiled binaries (.elf, .out, .o, .axf files):
1. **Use the existing artifacts** — run asm_analyze.py directly on them
2. **Use the project's own build system** if you need to recompile — look at Makefiles, CMakeLists.txt, build scripts, or IDE project files
3. **Cross-compile as last resort** — only if there is no build system and no compiled artifacts

The project may use vendor compilers (TI armcl/tiarmclang, IAR iccarm, Keil armcc) — these produce standard ELF files that asm_analyze.py handles normally.

## Project Overview

LOCI is a Claude Code plugin that adds execution-aware C++ analysis for embedded systems. It has two sides:

- **Local** — shell hooks that capture build actions, classify C++ engineering events, and manage session context
- **Remote** — an SSE-based MCP server backed by a Large Code Language Model (LCLM) trained on real hardware execution traces (cycle-accurate SW/HW trace data from physical Cortex-A53, Cortex-M4, and TriCore TC399 boards). Predicts execution time (ns), energy (Ws), and std deviation for assembly blocks — reflecting real silicon behavior, not simulation

## Setup & Installation

```bash
./setup.sh                        # One-command install (deps, venv, hooks, slash commands)
./scripts/configure.sh            # Interactive config wizard (MCP URL, thresholds)
```

Setup installs jq, binutils, uv automatically. Creates `.venv/` with Python 3.12 and the bundled `loci_service_asmslicer` wheel. Registers hooks into `<project-root>/.claude/settings.json`.

## Architecture

### Data Flow

```
Claude tool use → Hook fires (capture-action.sh) → Classify action type
→ Log action to state/loci-actions.log → Track compilation artifacts
→ Stop hook surfaces any active warnings from state/loci-warnings.json
```

### Key Components

| Component | File | Role |
|-----------|------|------|
| Action capture | `hooks/capture-action.sh` | Intercepts all tool uses, classifies C++ actions, steers toward asm_analyze.py |
| Session lifecycle | `hooks/session-lifecycle.sh` | Manages session manifests and project detection |
| Stop analysis | `hooks/stop-analysis.sh` | Surfaces active warnings at end of response |
| Asm Analyze CLI | `lib/asm_analyze.py` | ELF binary analysis (assembly extraction, symbol maps, blocks, diffs, CFG) |
| Project detection | `lib/detect-project.sh` | Auto-detects compiler, build system, architecture, ELF files |
| Task tracker | `lib/task_tracker.py` | Execution graph tracking and querying |
| Hook definitions | `hooks/hooks.json` | Declares all hook events; paths use `${CLAUDE_PLUGIN_ROOT}` variable |

### Hook Events

Hooks are registered in `hooks/hooks.json` and resolved to absolute paths by `setup.sh`:

- **SessionStart/SessionEnd** — lifecycle via `session-lifecycle.sh`
- **PreToolUse** (Bash, Write/Edit, Task, MCP calls) — `capture-action.sh` classifies actions, steers toward asm_analyze.py for binary analysis
- **PostToolUse** (Bash, Write/Edit, MCP calls) — `capture-action.sh` logs and tracks compilation artifacts
- **Stop** — `stop-analysis.sh` surfaces active warnings

### Action Classification

`capture-action.sh` classifies tool uses into types: `cpp_compile`, `cpp_build`, `cpp_link`, `binary_analysis`, `assembly`, `performance_profiling`, `cpp_source_modification`, `assembly_modification`, `build_config_modification`, `version_control`, `shell_command`.

### State Directory (`state/`)

All runtime state lives in `state/` (gitignored). Key files:

- `loci-warnings.json` — active warnings surfaced to Claude context
- `loci-baselines.json` — persistent timing baselines for regression detection
- `loci-actions.log` — action log (all classified tool uses)
- `hook-errors.log` — hook failure debugging

### Skills (Slash Commands)

Source templates in `skills/*/SKILL.md`:

- `/loci/exec-trace` — compile → extract assembly → measure execution time/energy
- `/loci/control-flow` — generate annotated CFGs for LLM analysis

## Debugging & Monitoring

```bash
cat state/loci-warnings.json | jq .          # Active warnings
cat state/hook-errors.log                     # Hook failures
python3 scripts/monitor-hooks.py              # Real-time hook metrics
python3 lib/task_tracker.py --state-dir state --status   # Execution graph
```

## Code Conventions

- **Shell scripts**: kebab-case (`capture-action.sh`), use `set +e` for graceful degradation
- **Python files**: snake_case (`asm_analyze.py`), Python 3.12 via uv-managed venv
- **JSON keys**: snake_case (`action_type`, `compiler_flags`)
- **State files**: kebab-case (`loci-warnings.json`)
- Hook scripts read JSON from stdin and must handle missing dependencies (jq, etc.) gracefully

## Extension Points

- **Custom action types**: Add cases to `classify_action()` in `hooks/capture-action.sh`
- **Custom skills**: Create `skills/<name>/SKILL.md`, reference `${LOCI_SLICER}` for slicer CLI

## Git Workflow

- Main branch: `production`
- Plugin version tracked in `.claude-plugin/plugin.json`
- Marketplace listing in `.claude-plugin/marketplace.json`
- `state/`, `.venv/`, `.claude/`, `__pycache__/`, `*.log`, `*.pid` are gitignored
