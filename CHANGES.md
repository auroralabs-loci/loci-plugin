# LOCI MCP Plugin Changelog

## Version 1.2.0 - February 2026

### ASM Slicer — Local ELF Binary Analysis

Added `loci-slicer`, a local stdio MCP server wrapping the `asmslicer` library. This enables Claude to inspect ELF binaries directly without manual `objdump` workflows.

**New slicer tools (local, no network):**
- **`slice_elf`** — Full binary analysis: pick any combination of asm, symbols, blocks, segments, callgraph, elfinfo
- **`extract_assembly`** — Per-function disassembly formatted for the timing backend, with ready-to-use `timing_csv` and `timing_architecture`
- **`extract_symbols`** — Symbol map: name, demangled name, address, size, namespace
- **`diff_elfs`** — Binary diff: added/removed/modified symbols with similarity ratios

**New file:** `loci-plugin/lib/slicer_mcp_server.py` (600+ lines)

### Unified MCP Tool API

Consolidated the two timing tools into a single tool:
- **Removed:** `get_assembly_block_timings` (batch) and `get_assembly_block_timings_per_function` (single)
- **Added:** `get_assembly_block_exec_behavior` — accepts a CSV of `(function_name, assembly_code)` and a target architecture, returns `execution_time_ns`, `std_dev_ns`, and `energy_ws` (estimated energy in Watt-seconds/Joules) per function

All references updated across CLAUDE.md, Readme.md, hooks, skills, and the regression checker prompt.

### Setup Overhaul (`setup.sh`)

- **Slicer install with retry**: Refactored into `install_slicer()` function that detects and installs undeclared wheel dependencies automatically (up to 5 rounds), and rebuilds the venv from scratch on failure
- **Hook registration** (new step 8): Automatically registers hooks into `.claude/settings.json` with absolute paths resolved from `hooks.json`
- **Slash command installation** (new step 9): Copies skill definitions to `.claude/commands/` so `/analyze` and `/slice` are available immediately
- **LOCI context installation** (new step 10): Copies `CLAUDE.md` into `.claude/` for Claude context
- **MCP type updated**: Changed from implicit SSE to explicit `"type": "http"` in `.mcp.json`
- **Better error reporting**: Slicer setup failures now log to `state/slicer-setup.log` with the last error shown inline

### Hook Robustness (`capture-action.sh`)

- **Fixed large-input crash**: Action record building now pipes `$INPUT` through stdin instead of `--argjson`, avoiding shell argument size limits and special-character parsing issues
- **Safer regex extraction**: `extract_files` jq expressions wrapped in `try` to prevent crashes on non-matching inputs
- **Input validation**: `FILES_INVOLVED` and `COMPILER_FLAGS` are validated as JSON before being passed to `--argjson`, falling back to `[]` on failure

### New Skill: `/slice`

- **`skills/slice/SKILL.md`** — Slash command for ELF binary exploration. Runs the slicer and presents symbols, disassembly, blocks, callgraph, and binary diffs

### Updated Skill: `/analyze`

- Updated to use `get_assembly_block_exec_behavior` with CSV format
- Uses `timing_csv` and `timing_architecture` from slicer output for seamless handoff

### New Documentation

- **`INSTALL.md`** — End-to-end installation guide covering prerequisites, plugin placement, wheel setup, running `setup.sh`, verification, usage scenarios, architecture support, slicer tool reference, and troubleshooting

### Other Changes

- **Removed** `loci-plugin/.mcp.json` — MCP config is now generated at the project root by `setup.sh`, not shipped inside the plugin
- **Version**: `plugin.json` set to `1.2.0`
- **Regression checker** (`hooks.json`): Updated agent prompt to call `get_assembly_block_exec_behavior` instead of `get_assembly_block_timings`
- **Slicer API update** (`slicer_mcp_server.py`): Updated from dict-based `asmslicer.process(args)` to keyword-based `asmslicer.process(**kwargs)` with per-output-type file paths via `OUTPUT_TYPE_TO_KWARG` mapping

---

## Version 1.1.1 - February 2026

### MCP Server Changes (server v1.25.0)

The LOCI MCP server makes Claude software-execution aware by using the generated binary and enables benchmarking of execution behavior across code changes.

**New tools:**
- **`get_assembly_block_exec_behavior`** — Provides execution behavior (time and energy consumption) for one or more assembly blocks. Accepts a CSV of `(function_name, assembly_code)` and a target architecture, returns predicted `execution_time_ns`, `std_dev_ns`, and `energy_ws` (estimated energy in Watt-seconds/Joules derived from an architecture-dependent energy constant). Useful for comparing performance between code versions, identifying high-cost functions, and getting hardware-aware estimations without running on real hardware. Supported architectures: `cortex-a53`, `cortex-m4`, `tc399`.

### Bug Fixes

- **MCP Server URL** — Updated `mcp_server_url` in `loci-mcp/config/loci.json` and `loci-mcp/setup.sh` to use the local development endpoint (`dev.local.mcp.loci-dev.net`) instead of the previous generic dev endpoint

### Documentation Updates

- Replaced "Manual Tool Access" section in `README.md` with a full MCP Tools Reference covering both new tools, their parameters, and output format
- Updated all example workflows to reflect assembly timing prediction use cases
- Added supported architectures table
- Clarified in `loci.json` (via `_comment` field) that `.mcp.json` at the project root is the entry point for Claude Code's direct MCP connection, while `loci.json` configures the local hook bridge

---

# LOCI MCP Plugin Enhancements

## Summary

Comprehensive improvements to documentation, error handling, configuration, testing, and monitoring.

## New Files Added

### Documentation
- **README.md** - Comprehensive plugin documentation
  - Installation and quick start guide
  - Configuration instructions with examples
  - Usage patterns and workflows
  - Troubleshooting section
  - Architecture diagrams
  - File structure overview
  - Advanced usage guide

- **CHANGES.md** - This file documenting all improvements

### Configuration & Setup
- **loci-mcp/scripts/configure.sh** - Interactive configuration wizard
  - Validates required tools (jq, compiler, python3)
  - Sets up MCP server connection
  - Auto-detects C++ project context
  - Tests connectivity to LOCI server
  - Initializes state directory
  - Provides next steps guidance

- **loci-mcp/scripts/monitor-hooks.py** - Performance monitoring tool
  - Tracks bridge process status (memory, CPU)
  - Analyzes hook activity and performance
  - Monitors warning generation
  - Tracks C++ compilation statistics
  - Estimates hook overhead
  - Provides watch mode for continuous monitoring
  - JSON output support for CI/CD integration

### Examples

#### Performance Optimization Example
- **loci-mcp/examples/performance-optimization/README.md** - Workflow guide
- **loci-mcp/examples/performance-optimization/entities.cpp** - Example code with performance anti-patterns
- **loci-mcp/examples/performance-optimization/CMakeLists.txt** - Build configuration

#### Memory Debugging Example
- **loci-mcp/examples/memory-debugging/README.md** - Memory issue detection guide
- **loci-mcp/examples/memory-debugging/memory_leak.cpp** - Code examples with memory issues
- **loci-mcp/examples/memory-debugging/CMakeLists.txt** - Build with sanitizer support

#### Build Configuration Example
- **loci-mcp/examples/build-configuration/README.md** - Optimization guide
- **loci-mcp/examples/build-configuration/CMakeLists.txt** - Problematic configuration
- **loci-mcp/examples/build-configuration/main.cpp** - Performance comparison code

## Enhanced Files

### Error Handling Improvements

**loci-mcp/hooks/capture-action.sh**
- Added graceful degradation when jq is not installed
- Input validation before processing
- Error logging to hook-errors.log
- Better error handling in JSON operations
- Improved jq error suppression
- Safer PID file reading
- Better error messages in logs
- Graceful exit even on errors

Changes:
- Added error logging function with timestamps
- Check for jq availability with graceful fallback
- Validate input is not empty
- Wrap jq operations with error handling
- Improved file write operations
- Better signal handling for bridge process
- Safer file operations throughout

## Feature Additions

### 1. Interactive Configuration Wizard

**Usage:**
```bash
./loci-mcp/scripts/configure.sh
```

**Features:**
- ✅ Validates all required dependencies
- ✅ Guides through MCP server setup
- ✅ Auto-detects C++ project environment
- ✅ Tests server connectivity
- ✅ Creates state directories
- ✅ Saves configuration
- ✅ Shows next steps

### 2. Performance Monitoring

**Usage:**
```bash
# One-time status report
python3 loci-mcp/scripts/monitor-hooks.py

# Continuous monitoring
python3 loci-mcp/scripts/monitor-hooks.py --watch --interval 5

# JSON output for CI/CD
python3 loci-mcp/scripts/monitor-hooks.py --json
```

**Metrics Tracked:**
- Bridge process status and resource usage
- Hook activity statistics
- Hook overhead estimation
- C++ compilation tracking
- Warning generation statistics
- Performance metrics

### 3. Example Workflows

Three complete example projects demonstrating:

1. **Performance Optimization**
   - Virtual dispatch in hot loops
   - Heap allocation patterns
   - Compiler flag optimization
   - Before/after comparison

2. **Memory Debugging**
   - Memory leak detection
   - Use-after-free patterns
   - Unsafe casts
   - Large stack arrays
   - Sanitizer integration

3. **Build Configuration**
   - Optimization level tuning
   - Debug vs release builds
   - Architecture-specific flags
   - Multi-target configuration

### 4. Improved Error Handling

**capture-action.sh enhancements:**
- Graceful fallback when required tools are missing
- Error logging for debugging
- Better input validation
- Safer JSON operations
- Improved bridge signaling

## File Structure

```
loci-plugin/
├── README.md                          ✨ NEW - Main documentation
├── CHANGES.md                         ✨ NEW - This file
├── loci-mcp/
│   ├── scripts/
│   │   ├── configure.sh              ✨ NEW - Configuration wizard
│   │   └── monitor-hooks.py          ✨ NEW - Performance monitor
│   ├── hooks/
│   │   ├── capture-action.sh         🔧 IMPROVED - Better error handling
│   │   ├── session-lifecycle.sh      (unchanged)
│   │   └── stop-analysis.sh          (unchanged)
│   ├── examples/
│   │   ├── performance-optimization/ ✨ NEW
│   │   ├── memory-debugging/         ✨ NEW
│   │   └── build-configuration/      ✨ NEW
│   ├── lib/
│   │   ├── loci_bridge.py            (unchanged)
│   │   ├── task_tracker.py           (unchanged)
│   │   ├── detect-project.sh         (unchanged)
│   │   └── generate-summary.sh       (unchanged)
│   └── config/
│       └── loci.json                 (unchanged)
```

## Quick Start

### For Users

1. **Initial Setup:**
   ```bash
   ./loci-mcp/scripts/configure.sh
   ```

2. **Monitor Performance:**
   ```bash
   python3 loci-mcp/scripts/monitor-hooks.py
   ```

3. **View Documentation:**
   - README.md - Full guide
   - examples/ - Working examples

### For Developers

1. **Check Configuration:**
   ```bash
   cat loci-mcp/config/loci.json
   ```

2. **Review Errors:**
   ```bash
   tail -f loci-mcp/state/hook-errors.log
   ```

3. **Analyze Performance:**
   ```bash
   python3 loci-mcp/scripts/monitor-hooks.py --json
   ```

## Testing

Each example includes:
- Working C++ code with known issues
- Build configuration
- Expected LOCI detection
- Step-by-step guide
- Learning objectives

To test:
```bash
cd loci-mcp/examples/<example-name>
cmake -B build
cd build
make  # LOCI captures this
```

## Documentation Quality

- ✅ Installation guide with prerequisites
- ✅ Configuration wizard with validation
- ✅ Troubleshooting section with solutions
- ✅ Architecture diagram and data flow
- ✅ Multiple working examples
- ✅ Performance monitoring guide
- ✅ Advanced usage section
- ✅ File structure reference

## Backward Compatibility

- ✅ All changes are additive
- ✅ No breaking changes to existing functionality
- ✅ Enhanced error handling doesn't affect normal operation
- ✅ New scripts are optional utilities
- ✅ Examples are standalone

## Future Enhancements

Recommended next steps:
1. Add test suite with automated validation
2. Create CI/CD integration examples
3. Build GUI configuration tool
4. Add performance dashboard
5. Create VS Code integration
6. Add GitHub Actions workflow examples

## Summary of Improvements

| Category | Before | After |
|----------|--------|-------|
| Documentation | ❌ Missing | ✅ Comprehensive |
| Configuration | ❌ Manual | ✅ Wizard-based |
| Error Handling | ⚠️ Limited | ✅ Robust |
| Monitoring | ❌ None | ✅ Full metrics |
| Examples | ❌ None | ✅ 3 complete projects |
| Testing | ❌ None | ✅ Example workflows |
| Troubleshooting | ❌ None | ✅ Common issues covered |

## Migration Guide

If upgrading from older version:

1. **Backup your state directory:**
   ```bash
   cp -r loci-mcp/state loci-mcp/state.backup
   ```

2. **Run new configuration wizard:**
   ```bash
   ./loci-mcp/scripts/configure.sh
   ```

3. **Review README.md for new features**

4. **Try monitoring:**
   ```bash
   python3 loci-mcp/scripts/monitor-hooks.py
   ```

## Support

- Check README.md troubleshooting section
- Review example projects
- Check hook-errors.log for issues
- Run monitor-hooks.py to verify health

---

**Version**: 1.1.0
**Date**: February 2025
**Status**: Production Ready
