# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install and initialize
./loci-plugin/setup.sh

# Interactive configuration wizard
./loci-plugin/scripts/configure.sh

# Session analysis CLI
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --status
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --graph
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --hot-files
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --diff <session_a> <session_b>
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --export > report.json

# Hook performance monitor
python3 loci-plugin/scripts/monitor-hooks.py
python3 loci-plugin/scripts/monitor-hooks.py --watch --interval 5
python3 loci-plugin/scripts/monitor-hooks.py --json

# Debug state
cat loci-plugin/state/loci-warnings.json | jq .
cat loci-plugin/state/loci-context.json | jq .
tail -f loci-plugin/state/loci-actions.log
tail -20 loci-plugin/state/bridge.log
cat loci-plugin/state/hook-errors.log

# Validate hook registration
jq empty loci-plugin/hooks.json && echo "Valid"
ps aux | grep loci_bridge.py
```

There is no test suite. Validate changes manually by checking `hook-errors.log` and running the monitoring commands above.

## Architecture

The system has two independent sides that don't communicate with each other:

**Local side (hooks → capture-action.sh → loci_bridge.py)**
Claude Code fires shell hooks at `SessionStart`, `PreToolUse`, `PostToolUse`, and `Stop`. All hooks funnel through `capture-action.sh`, which classifies the tool use into an action type (e.g., `cpp_compile`, `binary_analysis`, `cpp_source_modification`), extracts C++ context (compiler flags, output binary, optimization level), and writes a JSON file to `state/queue/`. It also sends `SIGUSR1` to the bridge to wake it immediately. On `PreToolUse`, the hook injects any active warnings from `state/loci-warnings.json` into Claude's context for the files about to be touched — this is the only mechanism for warnings to appear in Claude's responses.

`loci_bridge.py` runs as a persistent background daemon (started by `session-lifecycle.sh` at `SessionStart`, PID stored in `state/bridge.pid`). It wakes on `SIGUSR1` or every `poll_interval` seconds, reads up to `batch_size` queue files, updates the session timeline in `state/loci-context.json`, runs `CppAnalyzer` heuristics against file contents and compiler flags, and writes results to `state/loci-warnings.json` and `state/loci-metrics.json`. The bridge makes **no outbound HTTP calls** — it is purely local.

**Remote side (Claude Code → LOCI MCP server directly)**
Claude Code connects to the LOCI MCP server via SSE (configured in `.mcp.json` at the project root). Claude calls `mcp__loci-plugin__get_assembly_block_exec_behavior` directly — the bridge is not involved. The bridge does capture these MCP calls as `loci_mcp_tool` actions for the session timeline.

### Data flow for a typical C++ optimization task

```
Claude compiles a binary
  → PreToolUse: warn about known issues in files being touched
  → Bash executes
  → PostToolUse: classify as cpp_compile, extract -O2 -march=cortex-m4, queue JSON
  → bridge wakes, updates file timeline, checks for missing -O / -march / debug flags
  → Claude runs objdump on the binary
  → PostToolUse: classify as binary_analysis, queue JSON
  → Claude calls mcp__loci-plugin__get_assembly_block_exec_behavior
  → LOCI server returns execution_time_ns, std_dev_ns, energy_ws
  → Claude reports timing, energy consumption, and optimizes
```

### State files

| File | Written by | Read by | Purpose |
|------|-----------|---------|---------|
| `state/loci-warnings.json` | `loci_bridge.py` | `capture-action.sh` (PreToolUse, Stop) | Active heuristic warnings (max 50) |
| `state/loci-context.json` | `loci_bridge.py` | monitoring tools | Session action timeline + file relationships |
| `state/loci-metrics.json` | `loci_bridge.py` | `monitor-hooks.py` | Bridge throughput stats |
| `state/loci-actions.log` | `capture-action.sh` | `task_tracker.py`, `generate-summary.sh` | Append-only line-delimited JSON audit trail |
| `state/bridge.log` | `loci_bridge.py` | humans | Python logging output |
| `state/hook-errors.log` | `capture-action.sh` | humans | Hook script failures |
| `state/bridge.pid` | `session-lifecycle.sh` | `capture-action.sh` | Running bridge PID for SIGUSR1 signaling |
| `state/queue/*.json` | `capture-action.sh` | `loci_bridge.py` | Actions pending bridge analysis (deleted after processing) |
| `state/sessions/{id}.json` | `session-lifecycle.sh` | `generate-summary.sh` | Per-session manifest |

### CppAnalyzer heuristics (in loci_bridge.py)

The bridge scans source code and compile flags for these patterns — no server roundtrip:

| Trigger | Severity | Category |
|---------|----------|----------|
| `virtual` in function named `update`/`tick`/`render`/`process` | warning | performance |
| Heap alloc (`new`/`malloc`/`push_back`) inside a loop | warning | memory |
| `std::endl` usage | info | performance |
| `try`/`catch`/`throw` inside a loop | warning | performance |
| `reinterpret_cast` or `const_cast` | warning | safety |
| Stack array > 10,000 elements | warning | memory |
| Source file > 8,000 characters | info | complexity |
| No `-O` flag on compile command | warning | performance |
| `-g -O0` together | info | performance |
| No `-march` flag | info | optimization |
| `rm -rf` in shell command | **critical** | safety |

Critical warnings cause the `Stop` hook to return `"continue": false`, blocking Claude from continuing until acknowledged.

### Extending the system

**Add a custom action type**: Edit `classify_action()` in `loci-plugin/hooks/capture-action.sh`. Add an `elif` branch matching your command pattern and return a new action type string.

**Add a custom heuristic**: Add entries to `CppAnalyzer.PERF_PATTERNS` (regex on source) or `COMPILE_WARNINGS` (flags check) in `loci-plugin/lib/loci_bridge.py`. Each entry needs: `pattern`/`check`, `severity`, `category`, `message`.

### Configuration

Two separate configs must stay consistent:
- **`.mcp.json`** (project root) — Claude Code's MCP connection URL; created by `setup.sh`
- **`loci-plugin/config/loci.json`** — Bridge settings; `mcp_server_name` must match the server name in `.mcp.json`

### MCP server tools

Supported architectures: `cortex-a53`, `cortex-m4`, `tc399`.

- `mcp__loci-plugin__get_assembly_block_exec_behavior` — Accepts a CSV of `(function_name, assembly_code)` and a target architecture, returns predicted `execution_time_ns`, `std_dev_ns`, and `energy_ws` per function. `energy_ws` is estimated energy in Watt-seconds (Joules), derived from execution_time_ns and an architecture-dependent energy constant (nanojoules per nanosecond).

The typical workflow when asked to analyze a function: compile with the target architecture flag (e.g., `-march=cortex-m4`), extract its assembly via the slicer (or `objdump -d`), call `get_assembly_block_exec_behavior`.
