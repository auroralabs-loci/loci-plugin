# LOCI Example: Memory Debugging

This example demonstrates how LOCI helps diagnose memory leaks and safety issues.

## Scenario

Your application is experiencing memory growth over time. LOCI helps identify:
- Memory leaks (allocations without cleanup)
- Use-after-free bugs
- Buffer overflows
- Unsafe memory patterns

## What LOCI Detects

1. **Code Patterns** (CppAnalyzer heuristics):
   - Unsafe casts: `reinterpret_cast`, `const_cast` with `mutable`
   - Large stack arrays (stack overflow risk)
   - Unmatched new/delete patterns

2. **Profiling Integration**:
   - Valgrind output analysis
   - AddressSanitizer reports
   - Memory growth patterns

3. **Compilation Context**:
   - Whether debug symbols are present (-g flag)
   - Whether sanitizers are enabled
   - Optimization level impact on memory layout

## Running the Example

### Step 1: View the Code

```bash
cd examples/memory-debugging
cat memory_leak.cpp  # See the problematic code
```

### Step 2: Compile and Profile

Ask Claude Code:
```
"This application has a memory leak. Use Valgrind to find it and fix it."
```

LOCI will:
1. Detect compilation for profiling (valgrind usage)
2. Capture the valgrind command execution
3. Analyze the output for leak patterns
4. Suggest fixes

### Step 3: Review LOCI Insights

```bash
# Check memory-related warnings
cat ../../state/loci-warnings.json | jq '.warnings[] | select(.category == "memory")'

# View profiling commands captured
cat ../../state/loci-actions.log | grep performance_profiling
```

### Step 4: Compile with Sanitizers

For easier detection, ask Claude Code:
```
"Rebuild with AddressSanitizer to catch memory errors at runtime"
```

LOCI will track:
- Compiler flags: `-fsanitize=address`
- Binary artifacts with debug info
- Sanitizer output

## Memory Issues This Example Demonstrates

1. **Memory Leak**
   ```cpp
   int* ptr = new int(42);
   // ptr never deleted - memory leak
   ```

2. **Use-After-Free**
   ```cpp
   delete ptr;
   ptr->value = 5;  // Use after free!
   ```

3. **Large Stack Array**
   ```cpp
   char buffer[50000];  // Large stack allocation risk
   ```

4. **Unsafe Cast**
   ```cpp
   float* f = reinterpret_cast<float*>(&i);  // Dangerous
   ```

## LOCI Detection Flow

```
1. User requests memory debugging
   ↓
2. LOCI suggests profiling tool (valgrind, ASAN)
   ↓
3. Claude compiles with appropriate flags
   ↓
4. LOCI captures compilation: flags, binary name
   ↓
5. Claude runs profiler
   ↓
6. LOCI captures profiling output
   ↓
7. Claude analyzes with LOCI heuristics
   ↓
8. LOCI reports likely memory issues
   ↓
9. Claude suggests fixes
   ↓
10. LOCI validates fix by recompilation
```

## Build & Debug

```bash
# Compile normally
cmake -B build
cd build
make

# Run with Valgrind
valgrind --leak-check=full ./memory_example

# Or compile with AddressSanitizer
cmake -DENABLE_ASAN=ON -B build_asan
cd build_asan
make
./memory_example  # Catches errors at runtime
```

## Expected LOCI Insights

- ✓ "Unsafe cast detected"
- ✓ "Large stack array (>10000 bytes)"
- ✓ "Memory leak detected by Valgrind"
- ✓ "Use-after-free pattern"
- ✓ Optimization level for profiling

## Learning Points

- How to use profiling tools effectively
- Integration with sanitizers
- Heap vs stack allocation tradeoffs
- Safe C++ memory management patterns
