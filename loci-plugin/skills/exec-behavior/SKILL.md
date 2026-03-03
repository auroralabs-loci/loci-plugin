---
description: Batch analysis of execution behavior (timing, deviation, energy) for one or more compiled functions
disable-model-invocation: true
---

# LOCI Batch Execution Behavior Analysis

Analyze one or more functions from a compiled binary. "$ARGUMENTS" contains the target file path and optionally a comma-separated list of function names to analyze (e.g., `/exec-behavior src/dsp.cpp process_sample,apply_filter`). If no functions are listed, analyze all non-trivial functions in the binary.

## Step 0: Incremental Path (preferred)

If a previous `.o` exists in `.loci-build/aarch64/`, use incremental compilation to analyze only changed functions:

1. **Save the previous `.o`** (if it exists) as `.o.prev`
2. **Compile only the relevant source** to `.o` with `-c`:
   ```
   aarch64-linux-gnu-g++ -O2 -march=armv8-a -c <source> -o .loci-build/aarch64/<basename>.o
   ```
3. **Diff** `.o.prev` vs `.o` to find changed functions:
   ```
   ${LOCI_SLICER} diff-elfs --elf-path .o.prev --comparing-elf-path .o --arch aarch64
   ```
   Only `modified` and `added` functions need analysis.
4. **Extract assembly** for changed functions only:
   ```
   ${LOCI_SLICER} extract-assembly --elf-path .o --functions <changed_funcs> --arch aarch64
   ```
5. Skip to **Step 3** (MCP call) below.

If no `.o` exists yet, fall through to full compilation in Step 1.

## Steps

1. **Cross-compile** the target file for aarch64:
   ```
   aarch64-linux-gnu-g++ -O2 -march=armv8-a -o <output> <source>
   ```

2. **Extract assembly** with per-block granularity using the slicer:
   ```
   ${LOCI_SLICER} extract-assembly --elf-path <binary> --functions <funcs> --blocks blocks.csv
   ```
   The JSON output contains `timing_csv` (per-block rows like `calculate_0x718,...`) and `timing_architecture`.

   If no specific functions were requested, first run `${LOCI_SLICER} extract-symbols --elf-path <binary>` to list symbols, then select the user-defined ones.

   For standalone block transform (e.g., from a previously saved blocks CSV):
   ```
   ${LOCI_SLICER} blocks-to-timing --blocks blocks.csv --functions <funcs>
   ```

3. **Call the batch MCP tool**:
   ```
   mcp__loci-plugin__get_assembly_block_exec_behavior
   ```
   Parameters:
   - `csv_text`: the `timing_csv` value from step 2's JSON output (or stdout from `blocks-to-timing`)
   - `architecture`: the `timing_architecture` value from step 2's JSON output

4. **Report results** in a table:

   | Function | Exec Time | Std Dev | Energy |
   |----------|-----------|---------|--------|
   | name     | X.XX us   | Y.YY us | Z.ZZ uWs |

   - Convert `execution_time_ns` and `std_dev_ns` from nanoseconds to microseconds (divide by 1000).
   - Convert `energy_ws` from Watt-seconds to micro-Watt-seconds if the value is very small, otherwise keep Watt-seconds. Choose the unit that avoids excessive leading zeros.
   - Highlight the slowest and most energy-intensive functions.
   - If any function shows high std deviation relative to its execution time (>25%), flag it as having variable execution behavior.
