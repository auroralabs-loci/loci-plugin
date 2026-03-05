# LOCI Plugin for Claude Code

Ground your AI coding agent with execution awareness. No instrumentation. No runtime required.

## The Problem

AI coding agents are in your stack — but they're operating without execution awareness. They ship async logic that works in theory but blocks in production, generate massive diffs with fabricated performance claims, and miss security edge cases invisible to standard review. Each incorrect first-pass drives more cycles, corrections, and retries — indefinitely.

## What LOCI Does

LOCI adds the missing layer: **execution awareness**. It gives your AI agent bounded, evidence-based constraints grounded in predictions based on real measurements from compiled binaries — eliminating hallucinated performance claims and overconfident patches.

**Remote (LOCI MCP server)** — Claude connects directly to the LOCI server to predict execution time (ns) and energy (Watt-seconds) for assembly blocks on real embedded hardware.


## How It Works

1. **Plan and Think with LOCI** — LOCI skills are provided to the AI coding agent during engineering planning and thinking
2. **Execution Awareness** — From binary analysis, the agent reasons about how code behaves under real software runs and workloads
3. **Ground Your Agent** — The agent receives bounded, evidence-based constraints of execution behaviout — eliminating hallucinated performance claims

## Installation

**Prerequisites:** `jq`, `python3`, a C++ compiler

```bash
git clone https://github.com/auroralabs/loci-plugin.git
cd loci-plugin
./loci-plugin/setup.sh
```

Restart Claude Code after setup to activate the hooks.

## MCP Tool

Claude calls `mcp__loci-plugin__get_assembly_block_exec_behavior` with:

| Parameter | Type | Description |
|-----------|------|-------------|
| `csv_text` | string | CSV with columns `function_name` and `assembly_code` |
| `architecture` | string | `aarch64`, `armv7e-m`, or `tc3xx` |

**Returns:** `execution_time_ns`, `std_dev_ns`, `energy_ws` per function

**Supported targets:**

| Value | Hardware |
|-------|----------|
| `aarch64` | ARM aarch64 — embedded Linux |
| `armv7e-m` | ARM armv7e-m — microcontrollers, RTOS |
| `tc3xx` | Infineon AURIX tc3xx — automotive |



## Configuration

`setup.sh` creates `.mcp.json` at the project root automatically. Bridge settings live in `loci-plugin/config/loci.json` (poll interval, batch size, enable/disable).

Interactive wizard: `./loci-plugin/scripts/configure.sh`

## Monitoring & debugging

```bash
cat loci-plugin/state/loci-warnings.json | jq .   # active warnings
cat loci-plugin/state/hook-errors.log              # hook failures

python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --status
python3 loci-plugin/lib/task_tracker.py --state-dir loci-plugin/state --hot-files
python3 loci-plugin/scripts/monitor-hooks.py
```

## Troubleshooting

**Warnings not appearing:** Check `state/loci-warnings.json` exists and contains active warnings

**MCP connection failed:** The server uses SSE — test with `curl -H "Accept: text/event-stream" <url>`, not `curl -I`

**No actions captured:** Verify `jq` is installed and hooks are registered in Claude Code settings

## Extending

- **Custom action types:** Edit `classify_action()` in `hooks/capture-action.sh`

---

[AuroraLabs](https://www.auroralabs.com/) · [Claude Code docs](https://claude.ai/code) · [MCP spec](https://modelcontextprotocol.io/)
