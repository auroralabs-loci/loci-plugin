cmake_minimum_required(VERSION 3.10)
project(LOCIBuildConfigExample VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================================
# ANTI-PATTERN: Debug flags used everywhere
# ============================================================================
# LOCI DETECTS: Missing optimization level
# This is the problematic configuration that LOCI will flag
set(CMAKE_CXX_FLAGS "-g -O0 -Wall")

# LOCI DETECTS: -O0 means no optimization at all!
# LOCI DETECTS: -g flag even though not explicitly debug build
message(STATUS "LOCI: Current build configuration is NOT optimized")
message(STATUS "LOCI: Detected flags: ${CMAKE_CXX_FLAGS}")
message(STATUS "LOCI: Will suggest -O2 or -O3 for release")

# ============================================================================
# ANTI-PATTERN: No architecture-specific optimization
# ============================================================================
# LOCI DETECTS: Missing -march flag
# The binary won't use CPU-specific instructions (AVX, SSE)

# ============================================================================
# The improved configuration below is what LOCI will help you create
# ============================================================================
# After Claude Code fixes this, it should look like:
#
# # CORRECT: Separate debug and release builds
# set(CMAKE_CXX_FLAGS_DEBUG "-g -O0 -Wall -Wextra -Wpedantic")
# set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -DNDEBUG -Wall")
#
# # CORRECT: Add platform-specific optimizations
# if(UNIX AND NOT APPLE)
#     set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
# endif()
#
# if(APPLE)
#     set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
# endif()

# ============================================================================
# Create example executable
# ============================================================================
add_executable(build_config_example main.cpp)

# ============================================================================
# LOCI Insights for this configuration
# ============================================================================
# When you build this project, LOCI will:
#
# 1. Capture the compilation command
# 2. Extract flags: -g, -O0, -Wall
# 3. Analyze in CppAnalyzer:
#    ✗ Optimization level: NONE (-O0)
#    ✗ Architecture optimizations: MISSING
#    ✗ Debug flags in what should be optimized build
#
# 4. Generate warning: "No optimization flag — consider -O2/-O3"
#
# 5. Track in execution graph what flags were used
#
# 6. After you fix CMakeLists.txt, LOCI will:
#    - Capture new compilation with proper flags
#    - Compare: "-O0" → "-O3" = IMPROVEMENT
#    - Note binary size and performance implications

message("")
message("═" CHARACTER 70)
message("LOCI BUILD CONFIGURATION ANALYSIS")
message("═" CHARACTER 70)
message("")
message("ISSUES DETECTED:")
message("  1. No optimization flags (-O2 or -O3)")
message("  2. Debug symbols included (-g)")
message("  3. No CPU architecture flags (-march=native)")
message("")
message("IMPACT:")
message("  • Binary runs ~10x slower than optimized")
message("  • Binary is ~2x larger than necessary")
message("  • No CPU-specific instructions (AVX, SSE)")
message("")
message("SUGGESTED FIXES:")
message("  • For debug: set(CMAKE_CXX_FLAGS_DEBUG \"-g -O0\")")
message("  • For release: set(CMAKE_CXX_FLAGS_RELEASE \"-O3 -march=native\")")
message("  • Use: cmake -DCMAKE_BUILD_TYPE=Release")
message("")
message("LOCI WILL VERIFY:")
message("  ✓ Optimization levels are appropriate")
message("  ✓ Debug symbols match build type")
message("  ✓ Architecture flags are set")
message("")
message("═" CHARACTER 70)
message("")
