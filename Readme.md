# LOCI MCP Plugin for Claude Code

Gives Claude Code execution-aware C++ analysis by capturing your build workflow and providing assembly-level timing predictions for embedded targets.

## What it does

The plugin has two sides:

**Local (hooks + bridge)** — hooks into Claude Code to capture every compilation, binary analysis, profiling command, and source edit. A local Python bridge (`loci_bridge.py`) runs heuristic analysis and injects performance/safety warnings back into Claude's context before it touches your code.

**Remote (LOCI MCP server)** — Claude Code connects directly to the AuroraLabs LOCI MCP server, which predicts execution time in nanoseconds for assembly blocks on specific embedded hardware. Claude extracts assembly from your binaries using `objdump` or `readelf`, sends it to LOCI, and gets back timing predictions with standard deviation.

---

## MCP Tools

The LOCI server (v1.25.0) exposes two tools. Claude calls them as `mcp__loci-plugin__<name>`.

### `get_assembly_block_exec_behavior`

Provides execution behavior (time and energy consumption) for one or more assembly blocks.

| Parameter | Type | Description |
|-----------|------|-------------|
| `csv_text` | string | CSV with columns `function_name` and `assembly_code` |
| `architecture` | string | Target architecture (see below) |

**Returns:** Predicted `execution_time_ns`, `std_dev_ns`, and `energy_ws` (estimated energy in Watt-seconds/Joules) per function

**Example `csv_text`:**
```
function_name,assembly_code
process_frame,"push {r4-r7, lr}\n ldr r3, [r0]\n ..."
update_state,"push {r4, lr}\n vmov.f32 s0, #0\n ..."
```

---

### Supported Architectures

| Value | Hardware |
|-------|----------|
| `cortex-a53` | ARM Cortex-A53 — embedded Linux, application cores |
| `cortex-m4` | ARM Cortex-M4 — microcontrollers, RTOS |
| `tc399` | Infineon AURIX TC399 — automotive |

---

## Installation

### Prerequisites

| Tool | Purpose |
|------|---------|
| `jq` | JSON processing in hook scripts |
| `python3` | Local bridge process |
| `g++` or `clang++` | C++ compiler (for project detection) |

**Install jq:**
```bash
brew install jq          # macOS
sudo apt-get install jq  # Ubuntu/Debian
apk add jq               # Alpine
```

### Setup

```bash
git clone https://github.com/auroralabs/loci-plugin.git
cd loci-plugin
./loci-plugin/setup.sh
```

`setup.sh` will:
- Verify `jq` and `python3` are installed
- Set execute permissions on all scripts
- Create state directories (`state/queue/`, `state/sessions/`, `state/analysis-queue/`)
- Detect your C++ project (compiler, build system, architecture, source files)
- Create `.mcp.json` at the project root if it doesn't exist, pointing to the LOCI server

After setup, **restart Claude Code** to activate the hooks.

---

## Configuration

There are two separate config files:

### `.mcp.json` — Claude Code's MCP connection (project root)

Created automatically by `setup.sh`. Tells Claude Code where to find the LOCI server:

```json
{
  "mcpServers": {
    "loci-plugin": {
      "url": "https://dev.local.mcp.loci-dev.net/mcp"
    }
  }
}
```

### `loci-plugin/config/loci.json` — Local bridge settings (auto-created by `configure.sh`)

Controls the local `loci_bridge.py` process:

```json
{
  "mcp_server_url": "https://dev.local.mcp.loci-dev.net/mcp",
  "mcp_server_name": "loci-plugin",
  "poll_interval": 2.0,
  "batch_size": 10,
  "analysis_timeout": 30.0,
  "enabled": true
}
```

| Parameter | Description |
|-----------|-------------|
| `mcp_server_url` | Recorded in session context and logged at bridge startup; the bridge itself makes no outbound HTTP calls |
| `mcp_server_name` | Must match the server name registered in `.mcp.json` |
| `poll_interval` | Seconds between queue-processing cycles (default: `2.0`) |
| `batch_size` | Max actions to process per cycle (default: `10`) |
| `analysis_timeout` | Reserved for future use |
| `enabled` | Enable/disable the plugin (default: `true`) |

### Interactive wizard

An interactive setup wizard is also available:

```bash
./loci-plugin/scripts/configure.sh
```

---

## How it works

### Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Claude Code                           │
│  (calls mcp__loci-plugin__ tools; receives hook warnings)       │
└──────┬───────────────────────────────────────┬───────────────┘
       │ Hook Events                           │ MCP / SSE
       ▼                                       ▼
┌────────────────────────┐   ┌────────────────────────────────┐
│  hooks/hooks.json      │   │  LOCI MCP Server (remote)      │
│  ├─ SessionStart/End   │   │  └─ get_assembly_block_exec    │
│  ├─ PreToolUse         │   │       _behavior                │
│  ├─ PostToolUse        │   │                                │
│  └─ Stop               │   │  Targets: cortex-a53,          │
└──────┬─────────────────┘   │  cortex-m4, tc399              │
       │                     └────────────────────────────────┘
       ▼
┌──────────────────────────────────────────────────────────────┐
│  capture-action.sh                                           │
│  ├─ Classify action (cpp_compile, binary_analysis, etc.)    │
│  ├─ Extract compiler flags, output binary, -O level         │
│  ├─ PreToolUse: inject active warnings into Claude context  │
│  └─ PostToolUse: queue actions for bridge + analysis        │
└──────────────────────┬───────────────────────────────────────┘
                       │ queue/  (local JSON files)
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  loci_bridge.py  (local async process)                       │
│  ├─ CppAnalyzer: detect perf patterns, unsafe casts,        │
│  │   large stack arrays, bad compiler flags                 │
│  ├─ Writes loci-warnings.json  → picked up by PreToolUse   │
│  ├─ Writes loci-context.json   → session action timeline   │
│  └─ Writes loci-metrics.json   → bridge stats              │
└──────────────────────────────────────────────────────────────┘
```

> `loci_bridge.py` is a **local-only** process. It performs heuristic analysis and manages state files. The LOCI MCP server is called directly by Claude Code, not by the bridge.

### Hook events

| Hook | Trigger | What it does |
|------|---------|--------------|
| `SessionStart` | Session opens | Creates session manifest, detects C++ project context, starts `loci_bridge.py` |
| `PreToolUse` | Before Bash / Write / Edit / Task | Injects active LOCI warnings into Claude's context for the files about to be touched |
| `PostToolUse` | After Bash / Write / Edit | Classifies the action, extracts C++ context, queues it for bridge analysis |
| `SessionEnd` | Session closes | Marks session complete, generates and queues summary |
| `Stop` | Claude finishes responding | Reports critical warnings; can block Claude from continuing if critical issues are found |

### Action types captured

The hook classifies every tool use into one of these types:

**Bash commands:**
`cpp_compile`, `cpp_build`, `cpp_link`, `binary_analysis`, `assembly`, `performance_profiling`, `debugging`, `static_analysis`, `binary_execution`, `binary_diff`, `dependency_install`, `cpp_test`, `version_control`, `shell_command`

**File operations (Write / Edit):**
`cpp_source_modification`, `assembly_modification`, `build_config_modification`, `linker_config_modification`, `config_modification`, `documentation`, `file_modification`

**Read operations:**
`binary_inspection`, `cpp_code_analysis`, `code_analysis`

**Other:**
`agent_delegation`, `loci_mcp_tool`, `mcp_tool_call`

### Local heuristics (CppAnalyzer)

The bridge flags these patterns without a server roundtrip:

| Pattern | Severity | Category |
|---------|----------|----------|
| `virtual` in hot-path function name (update/tick/render/process) | warning | performance |
| Heap allocation (`new`, `malloc`, `push_back`) inside a loop | warning | memory |
| `std::endl` (flushes buffer on every call) | info | performance |
| `try`/`catch`/`throw` inside a loop | warning | performance |
| `reinterpret_cast` or `const_cast` | warning | safety |
| Stack array larger than 10,000 elements | warning | memory |
| Source file larger than 8,000 characters | info | complexity |
| No `-O` flag on compile command | warning | performance |
| `-g -O0` together (debug build) | info | performance |
| No `-march` flag (no CPU-specific instructions) | info | optimization |

---

## Usage examples

### Time a function on Cortex-M4

```
User: "How long does process_sensor_data() take on Cortex-M4?"

Claude:
1. Compiles with: g++ -O2 -mcpu=cortex-m4 -o sensor sensor.cpp
   (LOCI hook captures flags and output binary)
2. Extracts assembly: objdump -d sensor | sed -n '/<process_sensor_data>/,/^$/p'
3. Calls mcp__loci-plugin__get_assembly_block_exec_behavior:
     csv_text: "function_name,assembly_code\nprocess_sensor_data,\"<extracted asm>\""
     architecture: "cortex-m4"
4. LOCI returns: execution_time_ns=1240, std_dev_ns=85, energy_ws=0.00012
5. Reports: "~1.24 µs ± 85 ns on Cortex-M4"
```

### Compare -O2 vs -O3 on Cortex-A53

```
User: "Does -O3 help my DSP loop on Cortex-A53?"

Claude:
1. Compiles with -O2, extracts assembly for the loop function
2. Calls get_assembly_block_exec_behavior → 920 ns baseline
3. Recompiles with -O3 -march=cortex-a53, extracts new assembly
4. Calls get_assembly_block_exec_behavior → 660 ns
5. Reports: "-O3 + -march saves 260 ns (28%) on Cortex-A53"
```

### Batch timing across all changed functions

```
User: "Did the refactor slow anything down?"

Claude:
1. Identifies functions that changed (via git diff + objdump)
2. Builds CSV of all changed functions with their new assembly
3. Calls get_assembly_block_exec_behavior with architecture: "tc399"
4. Compares against baseline timing from before the refactor
5. Flags: "update_matrix() regressed by 340 ns on tc399"
```

---

## Monitoring & debugging

### Check plugin state

```bash
# Active warnings
cat loci-plugin/state/loci-warnings.json | jq .

# Session action timeline
cat loci-plugin/state/loci-context.json | jq .

# Bridge metrics
cat loci-plugin/state/loci-metrics.json | jq .

# All captured actions (live tail)
tail -f loci-plugin/state/loci-actions.log

# Hook errors
cat loci-plugin/state/hook-errors.log

# Bridge process log
tail -20 loci-plugin/state/bridge.log
```

### Session analysis CLI

```bash
# Current session stats
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --status

# Print execution graph tree
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --graph

# Show most-touched files
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --hot-files

# Diff two sessions
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --diff <session_a> <session_b>

# Export session as JSON (for CI/CD)
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --export > loci-report.json
```

### Hook performance monitoring

```bash
# One-time report
python3 loci-plugin/scripts/monitor-hooks.py

# Continuous (every 5 s)
python3 loci-plugin/scripts/monitor-hooks.py --watch --interval 5

# JSON output (for CI/CD)
python3 loci-plugin/scripts/monitor-hooks.py --json

# Bridge process resource usage
ps aux | grep loci_bridge.py
```

---

## Troubleshooting

### LOCI warnings not appearing

1. Check plugin is enabled: `cat loci-plugin/config/loci.json | jq .enabled`
2. Check bridge is running: `ps aux | grep loci_bridge`
3. Check bridge log: `tail -20 loci-plugin/state/bridge.log`
4. Check hook errors: `cat loci-plugin/state/hook-errors.log`

### MCP server connection failed

The server uses SSE — a plain `curl -I` will fail. Test correctly:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Accept: application/json, text/event-stream" \
  https://dev.local.mcp.loci-dev.net/mcp
# Expected: 200
```

Also verify:
- `.mcp.json` exists at the project root with the correct URL

### No actions being captured

1. Verify hooks are firing: `tail -f loci-plugin/state/loci-actions.log`
2. Check `jq` is installed: `which jq`
3. Check state dir permissions: `ls -la loci-plugin/state/`
4. Review Claude Code hook logs in Claude Code settings

### High hook overhead

```bash
# Diagnose
python3 loci-plugin/scripts/monitor-hooks.py

# Reduce bridge load
jq '.batch_size = 5 | .poll_interval = 5' \
  loci-plugin/config/loci.json > .tmp && mv .tmp loci-plugin/config/loci.json
```

---

## File structure

```
loci-plugin/
├── README.md
├── CHANGES.md
└── loci-plugin/
    ├── .claude-plugin/
    │   └── plugin.json            # Plugin manifest (name, version, author)
    ├── .mcp.json                  # Claude Code MCP server registration
    ├── setup.sh                   # Installation script
    ├── config/
    │   └── loci.json              # Local bridge configuration
    ├── hooks/
    │   ├── hooks.json             # Claude Code hook registration
    │   ├── capture-action.sh      # Action classifier + warning injector
    │   ├── session-lifecycle.sh   # SessionStart / SessionEnd handler
    │   └── stop-analysis.sh       # Stop hook — surfaces critical warnings
    ├── lib/
    │   ├── loci_bridge.py         # Local async C++ analyzer
    │   ├── task_tracker.py        # Session graph + CLI
    │   ├── detect-project.sh      # C++ project auto-detection
    │   └── generate-summary.sh    # Session summary generator
    ├── scripts/
    │   ├── configure.sh           # Interactive configuration wizard
    │   └── monitor-hooks.py       # Hook performance monitor
    ├── skills/
    │   └── analyze/
    │       └── SKILL.md           # /loci-plugin:analyze skill
    └── state/                     # Runtime state (auto-created)
        ├── loci-warnings.json     # Active heuristic warnings
        ├── loci-context.json      # Session action timeline
        ├── loci-metrics.json      # Bridge metrics
        ├── loci-actions.log       # All captured actions
        ├── bridge.log             # Bridge process log
        ├── hook-errors.log        # Hook script errors
        ├── queue/                 # Actions waiting for bridge
        ├── analysis-queue/        # High-priority actions (compile/binary)
        └── sessions/              # Per-session manifests
```

---

## Advanced

### Add custom action types

Edit `loci-plugin/hooks/capture-action.sh` — add branches to the `classify_action()` function for any tool patterns specific to your project.

### Add custom heuristics

Extend the `CppAnalyzer` class in `loci-plugin/lib/loci_bridge.py` — add entries to `PERF_PATTERNS` or `COMPILE_WARNINGS` for domain-specific rules.

---

## Links

- [AuroraLabs](https://www.auroralabs.com/)
- [Claude Code documentation](https://claude.ai/code)
- [MCP specification](https://modelcontextprotocol.io/)

---

**Get started:** `./loci-plugin/setup.sh`

**Test locally:** `claude --plugin-dir ./loci-plugin`
