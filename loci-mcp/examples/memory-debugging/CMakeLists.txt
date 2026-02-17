cmake_minimum_required(VERSION 3.10)
project(LOCIMemoryExample VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# For memory debugging, we want debug symbols and proper flags
set(CMAKE_CXX_FLAGS "-g -O0 -Wall -Wextra -Wpedantic")

# Optional: AddressSanitizer for runtime detection
option(ENABLE_ASAN "Enable AddressSanitizer" OFF)
if(ENABLE_ASAN)
    # LOCI will detect this flag and adjust analysis
    add_compile_options(-fsanitize=address -fsanitize=undefined)
    add_link_options(-fsanitize=address -fsanitize=undefined)
    message(STATUS "LOCI: AddressSanitizer enabled")
endif()

# Optional: Memory Sanitizer
option(ENABLE_MSAN "Enable MemorySanitizer" OFF)
if(ENABLE_MSAN)
    add_compile_options(-fsanitize=memory)
    add_link_options(-fsanitize=memory)
    message(STATUS "LOCI: MemorySanitizer enabled")
endif()

add_executable(memory_example memory_leak.cpp)

message(STATUS "LOCI: Memory debugging example")
message(STATUS "LOCI: Compilation flags: ${CMAKE_CXX_FLAGS}")
message(STATUS "LOCI: Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "LOCI will detect:")
message(STATUS "  - Memory leaks")
message(STATUS "  - Use-after-free")
message(STATUS "  - Unsafe casts")
message(STATUS "  - Large stack arrays")
message(STATUS "  - Unmatched allocations")
