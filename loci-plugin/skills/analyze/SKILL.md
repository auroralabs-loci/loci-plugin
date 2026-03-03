---
description: Analyze function  based on compiled assembly code to provide execution insights
disable-model-invocation: true
---

# LOCI Timing Analysis

the LOCI_SLICER is in lib/slicer_cli.py

you need to run it from within the .venv that is in the loci-plugin root directory

For example, to extract assembly for a function called `apply_filter` from `filter.elf`:
```
loci-plugin/.venv/bin/python3 loci-plugin/lib/slicer_cli.py extract-assembly \
  --elf-path filter.elf \
  --functions apply_filter
```
The output is JSON. Use the `timing_csv` and `timing_architecture` fields from it in step 3.

## Incremental Path (preferred)

If a previous `.o` exists in `.loci-build/cortex-a53/`, use incremental compilation:

1. Save the existing `.o` as `.o.prev`
2. Compile only the changed source with `-c`:
   ```
   aarch64-linux-gnu-g++ -O2 -march=armv8-a -c <source> -o .loci-build/cortex-a53/<basename>.o
   ```
3. Diff `.o.prev` vs `.o` to find changed functions:
   ```
   ${LOCI_SLICER} diff-elfs --elf-path .o.prev --comparing-elf-path .o --arch cortex-a53
   ```
4. Extract assembly for only `modified`/`added` functions:
   ```
   ${LOCI_SLICER} extract-assembly --elf-path .o --functions <changed_funcs> --arch cortex-a53
   ```
5. Skip to step 3 (MCP call) below.

If no `.o` exists yet, fall through to full compilation.

## Full Compilation Path

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
