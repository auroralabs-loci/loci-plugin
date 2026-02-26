# LOCI Plugin Installation

Add the LOCI plugin to a C++ project for execution-aware timing analysis and ELF binary slicing, all from within Claude Code.

## What you get

Two MCP servers working together:

- **loci-mcp** (remote, SSE) — predicts execution time for assembly functions on embedded targets (Cortex-A53, Cortex-M4, TriCore TC399)
- **loci-slicer** (local, stdio) — parses ELF binaries to extract symbols, disassembly, basic blocks, callgraphs, and binary diffs

The slicer feeds assembly to the timing backend in exactly the right format. No more manual `objdump` + copy-paste.

## Prerequisites

- Python 3.8+
- `jq`
- A C++ compiler (`g++` or `clang++`)
- A cross-compiler for your target architecture (e.g., `aarch64-linux-gnu-g++` for Cortex-A53, `arm-none-eabi-g++` for Cortex-M4)
- The `asmslicer` wheel file (provided by AuroraLabs, e.g. `loci_service_asmslicer-*.whl`)

## 1. Install the plugin

The plugin lives at `.claude/plugins/loci-plugin/` — three directories below the project root. `setup.sh` uses this depth to find the project root and write config files there.

From your project root:

```bash
mkdir -p .claude/plugins
cp -r /path/to/loci-plugin/loci-plugin .claude/plugins/loci-plugin
```

Your project should look like this before setup:

```
my-project/
├── .claude/
│   └── plugins/
│       └── loci-plugin/
│           ├── setup.sh
│           ├── hooks/
│           ├── lib/
│           ├── skills/
│           ├── slicer-wheels/    ← put wheel here
│           └── ...
├── src/
│   └── main.cpp
└── ...
```

## 2. Add the asmslicer wheel

Copy the wheel into the `slicer-wheels/` directory:

```bash
cp loci_service_asmslicer-*.whl .claude/plugins/loci-plugin/slicer-wheels/
```

If you don't have the wheel, the plugin still works — you just won't have the slicer tools. The remote timing backend (loci-mcp) works independently.

## 3. Run setup

```bash
.claude/plugins/loci-plugin/setup.sh
```

This will:
1. Check dependencies (jq, python3, compiler)
2. If wheels are present: create a Python venv and install the slicer
3. Detect your project (compiler, build system, sources, binaries)
4. Create `.mcp.json` at the project root with MCP server entries
5. Register hooks in `.claude/settings.json` (with absolute paths)
6. Install slash commands (`/analyze`, `/slice`) into `.claude/commands/`

Expected output (without wheel — slicer disabled, timing backend still works):

```
=========================================
  LOCI MCP Plugin for Claude Code
  SW Execution-Aware Analysis
=========================================

Checking dependencies... OK
Checking C++ compiler... g++ (Ubuntu 13.3.0) 13.3.0
Setting permissions... OK
Creating state directories... OK
Setting up slicer environment... no wheels in slicer-wheels/ — slicer disabled
Detecting  project... OK
  Compiler:   g++
  Build:      direct
  Sources:    3 files
  Binaries:   1 found
  Assembly:   2 files
Validating hooks... OK
Checking LOCI MCP server config... Created
Registering hooks... OK
Installing slash commands... OK (2 commands: analyze, slice)

Setup complete!
```

If you have the wheel, the slicer line shows `OK` and an additional `Adding loci-slicer to .mcp.json... OK` appears.

## 4. Verify what setup created

After setup, your project root should have these new files:

```
my-project/
├── .mcp.json                      ← MCP server config (Claude Code reads this)
├── .claude/
│   ├── settings.json              ← hooks registered here (absolute paths)
│   ├── commands/
│   │   ├── analyze.md             ← /analyze slash command
│   │   └── slice.md               ← /slice slash command
│   └── plugins/
│       └── loci-plugin/           ← plugin source (unchanged)
└── ...
```

Check `.mcp.json`:
```bash
cat .mcp.json | jq .
```

You should see at least the `loci-mcp` SSE server. If the slicer wheel was installed, you'll also see `loci-slicer` with absolute paths to the venv Python and server script.

## 5. Launch Claude Code

```bash
claude
```

Verify everything is connected:
- `/mcp` — should list `loci-mcp` (and `loci-slicer` if the wheel was installed)
- Type `/` and look for `analyze` and `slice` in the command list

---

## Using the plugin

### Example project

Say you have this `main.cpp`:

```cpp
int calculate(int x) {
  int n = x;
  n ^= 0xffff;
  n *= n + 20;
  n -= 0x1000;
  n ^= 0x2000;
  return n;
}

int main(int argc, char* argv[]) {
  int a = calculate(argc + 5);
  int b = calculate(argc + a);
  int c = calculate(argc + b);
  int x = a + b + c;
  return x < 0x2000 ? 1 : 0;
}
```

### Scenario 1: Timing analysis with `/analyze`

The fastest path from source to timing prediction. Just tell Claude what function to analyze:

```
> /analyze calculate
```

Claude will:
1. Compile `main.cpp` for the target architecture
2. Call `mcp__loci-slicer__extract_assembly` on the binary to get `calculate`'s assembly
3. Pass the assembly to `mcp__loci-mcp__get_assembly_block_exec_behavior`
4. Report the predicted execution time in microseconds with standard deviation

You can also ask for it conversationally:

```
> Cross-compile main.cpp for Cortex-M4 and tell me how long calculate() takes to execute
```

### Scenario 2: Explore an ELF binary with `/slice`

Use the `/slice` skill to inspect a binary without running timing analysis:

```
> /slice main
```

Claude will call the slicer to list symbols, show disassembly, and present the structure of the binary. You can ask for specific outputs:

```
> /slice main — show me the callgraph and basic blocks
```

### Scenario 3: Extract assembly for specific functions

Call the slicer tool directly when you need precise control:

```
> Use extract_assembly to get the assembly for calculate and main from ./main
```

Claude calls `mcp__loci-slicer__extract_assembly` with:
```json
{
  "elf_path": "./main",
  "functions": ["calculate", "main"]
}
```

The response includes:
- Per-function assembly in objdump format
- Start addresses, sizes, instruction counts
- `timing_csv` — a pre-formatted CSV ready to pass straight to the timing backend
- `timing_architecture` — the mapped architecture name for the timing backend

### Scenario 4: Compare two binaries

After making changes and recompiling, diff the old and new binaries:

```
> Diff ./main_v1 against ./main_v2 to see what changed
```

Claude calls `mcp__loci-slicer__diff_elfs` and shows you which symbols were added, removed, or modified, with similarity ratios for modified functions.

### Scenario 5: Full pipeline — optimize and measure

This is where the plugin really shines. Ask Claude to optimize a function and measure the impact:

```
> The calculate function in main.cpp is too slow for our Cortex-M4 target.
> Optimize it and show me the before/after timing comparison.
```

Claude will:
1. Compile the original, extract assembly via the slicer, measure baseline timing
2. Analyze the assembly for optimization opportunities
3. Modify the C++ source
4. Recompile, extract assembly again, measure new timing
5. Diff the two binaries to show exactly what changed
6. Report the timing improvement

### Scenario 6: List symbols from a third-party binary

You can point the slicer at any ELF, not just binaries you compiled:

```
> What functions are in /path/to/firmware.elf?
```

Claude calls `mcp__loci-slicer__extract_symbols` and returns the full symbol table with names, demangled names, addresses, and sizes.

---

## Architecture support

The slicer auto-detects architecture from the ELF binary. You can also specify it explicitly. Either naming convention works:

| Slicer name | Timing backend name | Typical compiler flag |
|-------------|--------------------|-----------------------|
| `aarch64`   | `cortex-a53`       | `-march=armv8-a`      |
| `cortexm`   | `cortex-m4`        | `-mcpu=cortex-m4`     |
| `tricore`   | `tc399`            | `-mcpu=tc39xx`        |

When you use `extract_assembly`, the response includes `timing_architecture` already mapped to the timing backend name, so the handoff is seamless.

## Available slicer tools

| Tool | What it does |
|------|-------------|
| `slice_elf` | Full analysis — pick any combination of: asm, symbols, blocks, segments, callgraph, elfinfo |
| `extract_assembly` | Per-function assembly formatted for the timing backend, with ready-to-use `timing_csv` |
| `extract_symbols` | Symbol map: name, demangled name, address, size, namespace |
| `diff_elfs` | Binary diff: added/removed/modified symbols with similarity ratios |

## Troubleshooting

**Setup ended early / no `.mcp.json` created** — Older versions of `setup.sh` could crash silently during the slicer venv step if `pip` or `venv` failed. Make sure you have the latest `setup.sh`. It should always complete all steps regardless of whether the slicer wheel is present.

**No MCP servers in `/mcp`** — Check that `.mcp.json` exists at your project root (not inside `.claude/`):
```bash
cat .mcp.json
```
If it's missing, re-run `setup.sh`. If it exists, restart Claude Code (`claude` must be started from the project root).

**No slash commands (`/analyze`, `/slice`)** — Check that `.claude/commands/` has the command files:
```bash
ls .claude/commands/
```
If empty, re-run `setup.sh`. It copies them from the plugin's `skills/` directory.

**Hooks not firing** — Check `.claude/settings.json` exists and contains hook entries:
```bash
cat .claude/settings.json | jq '.hooks | keys'
```
Should show `["PostToolUse", "PreToolUse", "SessionEnd", "SessionStart", "Stop"]`.

**"no wheels in slicer-wheels/"** during setup — Drop the `.whl` file in `slicer-wheels/` and re-run `setup.sh`. The timing backend still works without the slicer.

**"venv creation failed"** — `python3 -m venv` failed. Check that `python3-venv` is installed:
```bash
sudo apt install python3-venv  # Ubuntu/Debian
```

**"wheel installed but import failed"** — The wheel may be for a different Python version or platform. Check with:
```bash
.claude/plugins/loci-plugin/.venv/bin/python -c "from loci.service.asmslicer import asmslicer; print('OK')"
```

**Slicer tools don't appear in Claude Code** — Check that `.mcp.json` at the project root has the `loci-slicer` entry with correct absolute paths. Restart Claude Code after any `.mcp.json` changes.

**"ELF file not found"** — The slicer needs an absolute path or a path relative to Claude Code's working directory. Use the full path when in doubt.

**Timing backend unreachable** — The `loci-mcp` server is remote (SSE). Check network access to the URL in `.mcp.json`. The slicer works entirely offline.
