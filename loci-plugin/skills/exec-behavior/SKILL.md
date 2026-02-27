---
description: Batch analysis of execution behavior (timing, deviation, energy) for one or more compiled functions
disable-model-invocation: true
---

# LOCI Batch Execution Behavior Analysis

Analyze one or more functions from a compiled binary. "$ARGUMENTS" contains the target file path and optionally a comma-separated list of function names to analyze (e.g., `/exec-behavior src/dsp.cpp process_sample,apply_filter`). If no functions are listed, analyze all non-trivial functions in the binary.

## Steps

1. **Compile** the target file with appropriate flags for the architecture:
   ```
   arm-none-eabi-gcc -O2 -march=cortex-m4 -c <source> -o <output.o>
   ```
   Ask the user for the architecture if not obvious from the project. Supported: `cortex-a53`, `cortex-m4`, `tc399`.

2. **Extract assembly** for each function using objdump:
   ```
   objdump -d <binary> | sed -n '/<function_name>/,/^$/p'
   ```
   If no specific functions were requested, list all functions with `objdump -t <binary>` and select the user-defined ones (skip compiler-generated symbols).

3. **Build the CSV input** with one row per function — no header row:
   ```
   function_name_1,<assembly block 1>
   function_name_2,<assembly block 2>
   ```
   Each assembly block is the full objdump output for that function (hex addresses, opcodes, mnemonics).

4. **Call the batch MCP tool**:
   ```
   mcp__loci-mcp__get_assembly_block_exec_behavior
   ```
   Parameters:
   - `input_csv`: the CSV built in step 3
   - `architecture`: the target architecture (e.g., `cortex-m4`)

5. **Report results** in a table:

   | Function | Exec Time | Std Dev | Energy |
   |----------|-----------|---------|--------|
   | name     | X.XX us   | Y.YY us | Z.ZZ uWs |

   - Convert `execution_time_ns` and `std_dev_ns` from nanoseconds to microseconds (divide by 1000).
   - Convert `energy_ws` from Watt-seconds to micro-Watt-seconds if the value is very small, otherwise keep Watt-seconds. Choose the unit that avoids excessive leading zeros.
   - Highlight the slowest and most energy-intensive functions.
   - If any function shows high std deviation relative to its execution time (>25%), flag it as having variable execution behavior.
