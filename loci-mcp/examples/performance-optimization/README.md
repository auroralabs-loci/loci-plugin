# LOCI Example: Performance Optimization

This example demonstrates how LOCI can help optimize a performance-critical C++ function.

## Scenario

You're working on a game engine with a hot function called `process_entities()` that's executed 1000+ times per frame. It's using virtual function calls in a tight loop, which can hurt performance.

## Initial Code

The `entities.cpp` file contains a basic entity processing function with a virtual dispatch in a hot loop:

```cpp
void process_entities() {
    for (int i = 0; i < entities.size(); i++) {
        entities[i]->update();  // Virtual call in hot loop
    }
}
```

## What LOCI Detects

When you ask Claude Code to optimize this:

1. **Local Heuristics** (capture-action.sh):
   - Detects virtual dispatch in function named "update()"
   - Suggests this is a likely hot-path issue
   - Warns: "Virtual dispatch in likely hot-path function"

2. **Compilation Context** (loci_bridge.py):
   - Captures compilation flags
   - Checks for optimization levels (-O2, -O3)
   - Tracks binary artifacts produced

3. **Performance Patterns** (CppAnalyzer):
   - Scans for common anti-patterns
   - Suggests loop optimization techniques
   - Provides estimated impact

## Running the Example

### Step 1: Setup

```bash
cd examples/performance-optimization
ls -la  # View the code files
```

### Step 2: Ask Claude Code to Optimize

```
"This process_entities() function is called 1000x per frame and is a bottleneck.
Analyze it and optimize it for performance."
```

### Step 3: LOCI Provides Insights

LOCI will:
1. Capture the baseline compilation
2. Analyze the code with heuristics
3. Suggest optimizations (devirtualization, cache-friendly layout, etc.)
4. Claude applies optimizations
5. LOCI captures new compilation and compares

### Step 4: View Results

```bash
# Check what LOCI captured
cat ../../state/loci-warnings.json | jq '.warnings[] | select(.category == "performance")'

# View execution graph
python3 ../../lib/task_tracker.py --state-dir ../../state --graph

# See optimization timeline
cat ../../state/loci-actions.log | grep cpp_
```

## Expected Optimizations

Claude Code will likely suggest:

1. **Devirtualization** - Use static cast or template specialization
2. **Cache Friendliness** - Arrange data for better memory locality
3. **Compiler Flags** - Enable -O3, -march=native
4. **SIMD** - Vectorize the loop if possible

## Key Files

- `entities.cpp` - Initial implementation with performance issues
- `entities_optimized.cpp` - Optimized version
- `CMakeLists.txt` - Build configuration
- `benchmark.cpp` - Performance comparison

## Learning Points

This example teaches:
- ✓ How LOCI detects performance anti-patterns
- ✓ How to use binary-level insights for optimization
- ✓ How to compare before/after performance
- ✓ Understanding compilation impact on performance
- ✓ Integration with Claude Code workflow

## Further Reading

- See main README.md for workflow explanation
- Check troubleshooting section if LOCI doesn't activate
- Review loci_bridge.py to understand heuristic detection
