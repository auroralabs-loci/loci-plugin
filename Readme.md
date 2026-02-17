# LOCI MCP Plugin for C++ Execution-Aware Analysis

Transform Claude Code into a performance-aware C++ development assistant that understands compiled binaries and execution behavior.

## Overview

The LOCI MCP Plugin captures your entire C++ engineering workflow — from compilation flags to binary artifacts — and streams contextual insights to the AuroraLabs LOCI MCP server for binary-level performance analysis, regression detection, and optimization recommendations.

### Key Features

✨ **Execution-Aware Analysis**
- Captures compilation commands, flags, and optimization levels
- Tracks binary artifacts and assembly files
- Monitors performance profiling, debugging, and static analysis
- Builds execution dependency graphs for regression detection

🎯 **Proactive Guidance**
- Real-time performance pattern detection (virtual dispatch, heap allocation in loops, etc.)
- Compilation warnings (missing optimization flags, unsafe casts)
- Memory safety checks (large stack arrays, unsafe operations)
- Pre-action warnings injected before code modifications

📊 **Comprehensive Tracking**
- Full session lifecycle management
- Hot file detection (identify performance-critical code)
- Session diffing for regression analysis
- Execution graph visualization

## Installation

### Prerequisites

- **Claude Code** >= 1.0.0
- **jq** (JSON query tool)
- **C++ Compiler** (g++, clang++, or gcc)

### Quick Start

1. **Clone the plugin:**
   ```bash
   git clone https://github.com/auroralabs/loci-plugin.git
   cd loci-plugin
   ```

2. **Install dependencies:**
   ```bash
   # macOS
   brew install jq

   # Linux (Ubuntu/Debian)
   sudo apt-get install jq

   # Linux (Alpine)
   apk add jq
   ```

3. **Run the setup script:**
   ```bash
   ./loci-mcp/setup.sh
   ```

4. **Configure your project:**
   - Edit `loci-mcp/config/loci.json` with your LOCI MCP server details
   - Set `project_id` and `org_id` (obtain from AuroraLabs)
   - Verify the MCP server URL is correct

5. **Verify installation:**
   ```bash
   # Check if hooks are registered
   ls -la loci-mcp/hooks/

   # Verify configuration
   cat loci-mcp/config/loci.json
   ```

## Configuration

### MCP Server Setup

The plugin requires connection to the AuroraLabs LOCI MCP server. Configure it in `loci-mcp/config/loci.json`:

```json
{
  "mcp_server_url": "https://dev.mcp.loci-dev.net/mcp",
  "mcp_server_name": "loci-mcp",
  "project_id": "your-project-id",
  "org_id": "your-org-id",
  "poll_interval": 2.0,
  "batch_size": 10,
  "analysis_timeout": 30.0,
  "enabled": true
}
```

**Parameters:**
- `mcp_server_url`: LOCI MCP server endpoint
- `project_id`: Project identifier (required for tracking)
- `org_id`: Organization identifier (required for tracking)
- `poll_interval`: How often to check for queued actions (seconds)
- `batch_size`: Max actions to process per poll cycle
- `analysis_timeout`: Max time to wait for analysis (seconds)
- `enabled`: Enable/disable plugin (true/false)

### Using the Configuration Wizard

For easier setup, run the interactive configuration wizard:

```bash
./loci-mcp/scripts/configure.sh
```

This will guide you through:
1. Validating required tools
2. Setting up MCP server connection
3. Detecting your C++ project environment
4. Testing the connection

## Usage

### Automatic Integration

Once installed, the plugin automatically:
- ✅ Captures all Claude Code tool uses (Bash, Write, Edit, Task, etc.)
- ✅ Classifies actions (C++ compilation, binary analysis, profiling, etc.)
- ✅ Injects warnings before code modifications
- ✅ Queues important actions for LOCI server analysis
- ✅ Tracks session metadata and execution graphs

### When LOCI Activates

Claude Code will automatically use LOCI insights when:

**Performance Optimization**
```
User: "Optimize this C++ function for speed"
→ LOCI captures baseline, analyzes after changes, compares
```

**Binary Analysis**
```
User: "Why is this executable 5MB?"
→ LOCI analyzes binary structure and provides insights
```

**Memory Issues**
```
User: "This code has memory leaks"
→ LOCI suggests profiling tools and analysis patterns
```

**Build Problems**
```
User: "Fix the compilation error"
→ LOCI analyzes compiler flags and suggests optimizations
```

### Manual Tool Access

Query LOCI data directly using the MCP tools:

```bash
# Check current session status
mcp__loci-mcp__get_session_context

# Get performance insights
mcp__loci-mcp__analyze_performance

# Compare execution graphs
mcp__loci-mcp__compare_sessions
```

## Example Workflows

### Workflow 1: Optimizing a Hot Function

```
1. User: "This function is called 1000x per frame, optimize it"
2. LOCI captures the baseline compilation
3. Claude analyzes the code with heuristics:
   - Detects virtual dispatch in hot path
   - Identifies unnecessary heap allocation
   - Suggests loop unrolling opportunity
4. Claude applies optimizations
5. LOCI captures new compilation, performs regression analysis
6. Claude shows: "10% faster, 8% smaller binary"
```

### Workflow 2: Memory Leak Investigation

```
1. User: "Memory usage grows over time"
2. Claude suggests: valgrind, addresssanitizer profiling
3. LOCI captures profiling commands
4. Claude analyzes results with LOCI insights
5. LOCI detects: heap allocation in loop, missing cleanup
6. Claude provides fix with explanation
```

### Workflow 3: Build System Configuration

```
1. User: "CMakeLists.txt is too complex"
2. LOCI detects: -O0 used, debug symbols in release build
3. Claude suggests: separate debug/release configs
4. LOCI validates: new build produces optimal flags
```

## Monitoring & Debugging

### View Plugin Status

```bash
# Check session state
cat loci-mcp/state/loci-context.json

# View active warnings
cat loci-mcp/state/loci-warnings.json

# Check performance metrics
cat loci-mcp/state/loci-metrics.json
```

### View Execution Graph

```bash
# Print execution tree for current session
python3 loci-mcp/lib/task_tracker.py --state-dir loci-mcp/state --graph

# Show statistics
python3 loci-mcp/lib/task_tracker.py --state-dir loci-mcp/state --status

# Identify hot files
python3 loci-mcp/lib/task_tracker.py --state-dir loci-mcp/state --hot-files

# Compare two sessions
python3 loci-mcp/lib/task_tracker.py --state-dir loci-mcp/state \
  --diff session1_id session2_id
```

### View Action Log

```bash
# All captured actions
tail -f loci-mcp/state/loci-actions.log

# Filter by action type
grep "cpp_compile" loci-mcp/state/loci-actions.log

# View with pretty-printing
cat loci-mcp/state/loci-actions.log | jq .
```

### Performance Monitoring

```bash
# Check hook execution overhead
python3 loci-mcp/scripts/monitor-hooks.py

# View bridge process stats
ps aux | grep loci_bridge.py

# Check for errors
cat loci-mcp/state/bridge.log
```

## Troubleshooting

### Problem: LOCI warnings not appearing

**Solution:**
1. Check if plugin is enabled: `cat loci-mcp/config/loci.json | jq .enabled`
2. Verify hooks are registered: `ls -la loci-mcp/state/`
3. Check bridge is running: `ps aux | grep loci_bridge`
4. Review bridge log: `tail -20 loci-mcp/state/bridge.log`

### Problem: MCP server connection failed

**Solution:**
1. Verify server URL: `cat loci-mcp/config/loci.json | jq .mcp_server_url`
2. Test connectivity: `curl -I https://dev.mcp.loci-dev.net/mcp`
3. Check credentials: `cat loci-mcp/config/loci.json | jq '.project_id, .org_id'`
4. Run configuration wizard: `./loci-mcp/scripts/configure.sh`

### Problem: No actions being captured

**Solution:**
1. Verify hook events are firing: `tail -f loci-mcp/state/loci-actions.log`
2. Check if jq is installed: `which jq`
3. Verify permissions: `ls -la loci-mcp/state/`
4. Review hook system logs in Claude Code settings

### Problem: High hook overhead

**Solution:**
1. Check performance metrics: `python3 loci-mcp/scripts/monitor-hooks.py`
2. Reduce batch size: `jq '.batch_size = 5' loci-mcp/config/loci.json > .tmp && mv .tmp loci-mcp/config/loci.json`
3. Increase poll interval: `jq '.poll_interval = 5' loci-mcp/config/loci.json > .tmp && mv .tmp loci-mcp/config/loci.json`
4. Make problematic hooks async (edit `loci-mcp/hooks.json`)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              Claude Code                            │
│  (receives LOCI warnings & insights)                │
└────────────────┬────────────────────────────────────┘
                 │ Hook Events
                 ▼
┌─────────────────────────────────────────────────────┐
│         Hook System (hooks.json)                    │
│  ├─ SessionStart/End: Lifecycle                    │
│  ├─ PreToolUse: Warning injection                  │
│  ├─ PostToolUse: Action capture                    │
│  └─ Stop: Final analysis                           │
└────────────────┬────────────────────────────────────┘
                 │ JSON Actions
                 ▼
┌─────────────────────────────────────────────────────┐
│    capture-action.sh (Action Classifier)           │
│  ├─ Classify action type (15+ types)              │
│  ├─ Extract C++ context                           │
│  ├─ Queue for analysis                            │
│  └─ Inject warnings                               │
└────────────────┬────────────────────────────────────┘
                 │ Queue Files
                 ▼
┌─────────────────────────────────────────────────────┐
│    loci_bridge.py (C++ Analyzer)                   │
│  ├─ CppAnalyzer: Local heuristics                 │
│  ├─ TaskTracker: Execution graphs                 │
│  ├─ Warning generation                            │
│  └─ Metrics collection                            │
└────────────────┬────────────────────────────────────┘
                 │ HTTP/SSE
                 ▼
┌─────────────────────────────────────────────────────┐
│    LOCI MCP Server (AuroraLabs)                     │
│  ├─ Binary analysis                               │
│  ├─ Performance profiling                         │
│  ├─ Regression detection                          │
│  └─ Power analysis                                │
└─────────────────────────────────────────────────────┘
```

## File Structure

```
loci-plugin/
├── README.md                          # This file
├── loci-mcp/
│   ├── manifest.json                 # Plugin metadata
│   ├── hooks.json                    # Claude Code hook configuration
│   ├── setup.sh                      # Installation script
│   ├── config/
│   │   └── loci.json                 # Runtime configuration
│   ├── hooks/
│   │   ├── capture-action.sh         # Main action capture hook
│   │   ├── session-lifecycle.sh      # Session start/end hook
│   │   └── stop-analysis.sh          # Shutdown hook
│   ├── lib/
│   │   ├── loci_bridge.py            # Core bridge & analyzer
│   │   ├── task_tracker.py           # Execution graph builder
│   │   ├── detect-project.sh         # Project context detection
│   │   └── generate-summary.sh       # Session summary generator
│   ├── scripts/
│   │   ├── configure.sh              # Interactive configuration wizard
│   │   └── monitor-hooks.py          # Performance monitoring
│   ├── state/                        # Runtime state (auto-created)
│   │   ├── loci-context.json        # Current session context
│   │   ├── loci-warnings.json       # Active warnings
│   │   ├── loci-metrics.json        # Performance metrics
│   │   ├── loci-actions.log         # Action log
│   │   └── bridge.log               # Bridge process log
│   └── examples/
│       ├── performance-optimization/ # Optimize hot function
│       ├── memory-debugging/         # Find memory leaks
│       └── build-configuration/      # Configure build system
```

## Advanced Usage

### Custom Action Classification

Edit `loci-mcp/hooks/capture-action.sh` to add custom action types for your project.

### Custom Heuristics

Extend `loci-mcp/lib/loci_bridge.py` CppAnalyzer class to add domain-specific analysis rules.

### Integration with CI/CD

Export LOCI data to your CI/CD pipeline:
```bash
python3 loci-mcp/lib/task_tracker.py --state-dir loci-mcp/state --export > loci-report.json
```

## Support & Contribution

- **Issues**: Report bugs or feature requests
- **Documentation**: Contributing documentation improvements
- **Code**: Submit PRs for enhancements
- **Questions**: Check examples directory or troubleshooting guide

## License

MIT License - See LICENSE file for details

## Links

- [AuroraLabs LOCI](https://www.auroralabs.com/)
- [Claude Code Documentation](https://claude.com/claude-code)
- [MCP Specification](https://modelcontextprotocol.io/)

---

**Ready to optimize?** Start with: `./loci-mcp/scripts/configure.sh`
