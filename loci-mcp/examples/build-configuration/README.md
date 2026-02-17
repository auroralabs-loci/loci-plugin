# LOCI Example: Build Configuration Optimization

This example shows how LOCI helps optimize CMakeLists.txt and build system configuration.

## Scenario

Your project's build system isn't properly configured:
- Debug flags in release builds
- Suboptimal compiler optimization
- Missing architecture-specific flags
- Inconsistent configuration across targets

## What LOCI Detects

1. **Compilation Flags**:
   - Missing `-O2` or `-O3` in release builds
   - Debug symbols (`-g`) in optimized builds
   - Wrong flags for the use case

2. **Build System Issues**:
   - Unnecessary dependencies
   - Inefficient build configuration
   - Platform-specific problems

3. **Compiler Support**:
   - Available optimization levels
   - CPU architecture flags
   - Standard library options

## Running the Example

### Step 1: Examine Current Configuration

```bash
cd examples/build-configuration
cat CMakeLists.txt  # See problematic configuration
```

### Step 2: Ask Claude Code

```
"Optimize this CMakeLists.txt for performance. Currently it's using -O0 in
release builds and including debug symbols. Fix the configuration."
```

### Step 3: LOCI Guides the Optimization

LOCI will:
1. Capture the initial build configuration
2. Detect suboptimal flags (analyzing via CppAnalyzer)
3. Suggest configuration improvements
4. Help validate the new configuration

### Step 4: See the Results

```bash
# Check what compilation flags LOCI captured
cat ../../state/loci-actions.log | jq 'select(.action_type == "cpp_build") | .cpp_context.compiler_flags'

# View the optimization timeline
cat ../../state/loci-warnings.json | jq '.warnings[] | select(.category == "optimization")'
```

## Build Configuration Anti-Patterns

### Problem 1: Debug in Release

```cmake
# WRONG: Debug flags in release build
set(CMAKE_CXX_FLAGS_RELEASE "-g -O0")  # -O0 means no optimization!
# LOCI DETECTS: Missing optimization, debug in release
```

### Problem 2: No Architecture Optimization

```cmake
# WRONG: Generic build, no CPU-specific features
set(CMAKE_CXX_FLAGS "-Wall")
# LOCI DETECTS: No -march flag, missing vectorization potential
```

### Problem 3: Inconsistent Configurations

```cmake
# WRONG: Different flags for different targets
target_compile_options(target1 PRIVATE -O2)
target_compile_options(target2 PRIVATE -O0)  # Why the difference?
```

## Correct Configuration

```cmake
# CORRECT: Separate debug and release
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0 -Wall")
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -DNDEBUG -Wall")

# CORRECT: Consistent platform-specific settings
if(APPLE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
elseif(UNIX)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
endif()
```

## LOCI Detection Flow

```
1. cmake -DCMAKE_BUILD_TYPE=Release  (or Debug)
   ↓
2. capture-action.sh intercepts build command
   ↓
3. Extracts compiler flags: -O3, -march=native, etc.
   ↓
4. CppAnalyzer checks:
   - Is optimization level appropriate?
   - Are debug symbols in release?
   - Missing important flags?
   ↓
5. Generates warnings with explanations
   ↓
6. Claude modifies CMakeLists.txt
   ↓
7. LOCI captures new build, compares flags
   ↓
8. Shows improvement: "Fixed -O0 → -O3"
```

## Build System Checks

LOCI examines:

### Optimization Levels
- `-O0`: Development builds (slow, small)
- `-O2`: Balanced (reasonable, safe)
- `-O3`: Aggressive (fast, larger)
- `-Os`: Size optimized (embedded)
- `-Ofast`: Unsafe optimizations (benchmarks only)

### Debugging
- `-g`: Include debug symbols
- `-DNDEBUG`: Remove assertions
- Compatibility with optimization

### Architecture
- `-march=native`: CPU-specific instructions
- `-march=x86-64`: Generic compatibility
- `-mtune=...`: Tuning options

### Warnings
- `-Wall`: Most common warnings
- `-Wextra`: Additional warnings
- `-Werror`: Treat warnings as errors

## Multi-Target Configuration

Example: Library + Benchmarks

```cmake
# Library: balance performance and debug
add_library(mylib mylib.cpp)
target_compile_options(mylib PRIVATE -O2 -g)

# Benchmark: full speed
add_executable(bench benchmark.cpp)
target_compile_options(bench PRIVATE -O3 -march=native -DNDEBUG)

# Unit tests: focus on correctness
add_executable(tests tests.cpp)
target_compile_options(tests PRIVATE -O0 -g -Wall -Wextra)
```

LOCI understands these differences and validates them appropriately.

## Platform-Specific Optimization

```cmake
# Linux
if(UNIX AND NOT APPLE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
endif()

# macOS
if(APPLE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
    # Apple Silicon specific
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
        # ARM-specific optimizations
    endif()
endif()

# Windows
if(WIN32)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /O2 /arch:AVX2")
endif()
```

LOCI tracks detected architecture and verifies configuration matches.

## Learning Points

- ✓ How CMake build configuration affects binary
- ✓ Optimization level tradeoffs
- ✓ Debug symbols in builds
- ✓ Platform-specific compilation
- ✓ Validation of build configuration
- ✓ Integration with build systems

## Further Optimization

After fixing the configuration, ask Claude Code:
```
"Now that the build configuration is optimized, profile the compiled binary
to find runtime optimization opportunities."
```

This chains into the performance-optimization example.
