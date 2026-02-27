---
description: Analyze function  based on compiled assembly code to provide execution insights
disable-model-invocation: true
---

# LOCI Timing Analysis

1. Cross-compile the target file for aarch64:
   ```
   aarch64-linux-gnu-g++ -O2 -march=armv8-a -o <binary> <source>
   ```
2. Extract assembly with per-block granularity:
   ```
   ${LOCI_SLICER} extract-assembly --elf-path <binary> --functions <func> --blocks blocks.csv
   ```
   The JSON output contains `timing_csv` (per-block rows like `calculate_0x718,...`) and `timing_architecture`.
   If slicer unavailable, fallback: `objdump -d <binary> | sed -n '/<function>/,/^$/p'`
3. Call `mcp__loci-plugin__get_assembly_block_exec_behavior` with:
   - `csv_text`: the `timing_csv` value from step 2's JSON output
   - `architecture`: `cortex-a53`
4. Report execution time and standard deviation in microseconds, and energy consumption in Watt-seconds (`energy_ws`)
