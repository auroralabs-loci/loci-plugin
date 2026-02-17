cmake_minimum_required(VERSION 3.10)
project(LOCIPerformanceExample VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# LOCI will analyze these flags
# Notice: No optimization flag by default (LOCI detects and warns)
# You can enable with: cmake -DCMAKE_BUILD_TYPE=Release

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug)
endif()

# Debug flags
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0 -Wall -Wextra")

# Release flags - LOCI will recognize these as optimized
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -march=native -Wall -DNDEBUG")

# Create example executable
add_executable(entities_example
    entities.cpp
)

# Compilation options that LOCI tracks:
# - g++ / clang++: Detected automatically
# - Optimization level: -O0, -O2, -O3 (LOCI analyzes impact)
# - March flag: Controls CPU-specific instructions
# - Standard: C++ version

# LOCI Insight: This project will trigger warnings about:
# ✓ Virtual dispatch in hot path
# ✓ Heap allocation in loop
# ✓ Large stack array
# ✓ Debug build settings (if building with -O0)

message(STATUS "LOCI: Building with flags: ${CMAKE_CXX_FLAGS}")
message(STATUS "LOCI: Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "LOCI: Will detect performance anti-patterns in this project")
