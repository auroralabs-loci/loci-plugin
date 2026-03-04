# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LOCI is a Claude Code plugin that adds execution-aware C++ analysis for embedded systems. It has two sides:

- **Local** — shell hooks + a Python bridge daemon that capture build actions, run heuristic analysis, and inject warnings into Claude's context
- **Remote** — an SSE-based MCP server that predicts execution time (ns), energy (Ws), and std deviation for assembly on embedded hardware (Cortex-A53, Cortex-M4, TriCore TC399)

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
→ Queue JSON to state/queue/ → Bridge daemon (loci_bridge.py) picks up
→ Runs CppAnalyzer heuristics → Writes warnings to state/loci-warnings.json
→ Stop hook injects warnings back into Claude's context
```

### Key Components

| Component | File | Role |
|-----------|------|------|
| Action capture | `hooks/capture-action.sh` | Intercepts all tool uses, classifies C++ actions |
| Session lifecycle | `hooks/session-lifecycle.sh` | Starts/stops bridge daemon, manages session manifests |
| Stop analysis | `hooks/stop-analysis.sh` | Blocks Claude on critical warnings |
| Bridge daemon | `lib/loci_bridge.py` | Async background daemon — polls queue, runs heuristics, writes state |
| Asm Analyze CLI | `lib/asm_analyze.py` | ELF binary analysis (assembly extraction, symbol maps, diffs) |
| Task tracker | `lib/task_tracker.py` | Execution graph tracking and querying |
| Project detection | `lib/detect-project.sh` | Auto-detects compiler, build system, architecture |
| Hook definitions | `hooks/hooks.json` | Declares all hook events; paths use `${CLAUDE_PLUGIN_ROOT}` variable |
| Plugin metadata | `.claude-plugin/plugin.json` | Plugin version, MCP server URL |

### Hook Events

Hooks are registered in `hooks/hooks.json` and resolved to absolute paths by `setup.sh`:

- **SessionStart/SessionEnd** — lifecycle via `session-lifecycle.sh`
- **PreToolUse** (Bash, Write/Edit, Task, MCP calls) — `capture-action.sh` injects warnings
- **PostToolUse** (Bash, Write/Edit, MCP calls) — `capture-action.sh` classifies and queues actions
- **Stop** — `stop-analysis.sh` surfaces critical warnings + agent prompt runs regression checks

### Action Classification

`capture-action.sh` classifies tool uses into types: `cpp_compile`, `cpp_build`, `cpp_link`, `binary_analysis`, `assembly`, `performance_profiling`, `cpp_source_modification`, `assembly_modification`, `build_config_modification`, `version_control`, `shell_command`.

### State Directory (`state/`)

All runtime state lives in `state/` (gitignored). Key files:

- `queue/*.json` — transient action queue (hooks write, bridge consumes)
- `loci-warnings.json` — active heuristic warnings injected into Claude context
- `loci-baselines.json` — persistent timing baselines for regression detection
- `loci-context.json` — session action timeline
- `bridge.log` / `hook-errors.log` — debugging logs

### Skills (Slash Commands)

Source templates in `skills/*/SKILL.md`, installed to `.claude/commands/` by setup:

- `/loci/analyze` — compile → extract assembly → measure execution time/energy
- `/loci/slice` — extract assembly blocks and symbols from ELF
- `/loci/exec-behavior` — batch MCP timing call with CSV
- `/loci/profile-blocks` — block-level profiling with regression detection


Architecture mapping: `cortex-a53` → `aarch64`, `cortex-m4` → `cortexm`, `tc399` → `tricore`.

## Debugging & Monitoring

```bash
cat state/loci-warnings.json | jq .          # Active warnings
tail -20 state/bridge.log                     # Bridge daemon log
cat state/hook-errors.log                     # Hook failures
python3 scripts/monitor-hooks.py              # Real-time hook metrics
python3 lib/task_tracker.py --state-dir state --status   # Execution graph
```

## Code Conventions

- **Shell scripts**: kebab-case (`capture-action.sh`), use `set +e` for graceful degradation
- **Python files**: snake_case (`loci_bridge.py`), Python 3.12 via uv-managed venv
- **JSON keys**: snake_case (`action_type`, `compiler_flags`)
- **State files**: kebab-case (`loci-warnings.json`)
- Hook scripts read JSON from stdin and must handle missing dependencies (jq, etc.) gracefully

## Extension Points

- **Custom heuristics**: Add patterns to `CppAnalyzer.PERF_PATTERNS` or `COMPILE_WARNINGS` in `lib/loci_bridge.py`
- **Custom action types**: Add cases to `classify_action()` in `hooks/capture-action.sh`
- **Custom skills**: Create `skills/<name>/SKILL.md`, reference `${LOCI_SLICER}` for slicer CLI

## Git Workflow

- Main branch: `production`
- Plugin version tracked in `.claude-plugin/plugin.json` (currently 1.2.1)
- Marketplace listing in `.claude-plugin/marketplace.json`
- `state/`, `.venv/`, `.claude/`, `__pycache__/`, `*.log`, `*.pid` are gitignored
