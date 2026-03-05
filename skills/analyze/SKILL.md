---
description: Analyze function  based on compiled assembly code to provide execution insights
disable-model-invocation: true
---

# LOCI Timing Analysis

the LOCI_ASM_ANALYZE is in lib/asm_analyze.py

you need to run it from within the .venv that is in the loci-plugin root directory

For example, to extract assembly for a function called `apply_filter` from `filter.elf`:
```
loci-plugin/.venv/bin/python3 loci-plugin/lib/asm_analyze.py extract-assembly \
  --elf-path filter.elf \
  --functions apply_filter
```
The output is JSON. Use the `timing_csv` and `timing_architecture` fields from it in step 3.

## Step 0: Resolve Architecture and Toolchain

Determine which LOCI target architecture and compiler to use:

1. **User's own compilation** — if the user already compiled targeting a LOCI architecture (aarch64, armv7e-m, tc3xx), reuse their binary. Skip directly to assembly extraction (step 2 of the full compilation path).
2. **`state/pending-regression-check.json`** — if it exists and contains an `architecture` field, use that architecture.
3. **No context** — ask the user which target, or default to aarch64.

### Cross-compilation defaults

Use these defaults only when the user has no existing build:

| Architecture | Compiler | Flags | Build dir |
|---|---|---|---|
| aarch64 | `aarch64-linux-gnu-g++` | `-O2 -march=armv8-a` | `.loci-build/aarch64/` |
| cortexm | `arm-none-eabi-g++` | `-O2 -mcpu=cortex-m4 -mthumb` | `.loci-build/cortexm/` |
| tricore | `tricore-elf-g++` | `-O2 -mcpu=tc3xx` | `.loci-build/tricore/` |

In all steps below, replace `<arch>`, `<compiler>`, and `<flags>` with values from the resolved architecture.

## Incremental Path (preferred)

If a previous `.o` exists in `.loci-build/<arch>/`, use incremental compilation:

1. Save the existing `.o` as `.o.prev`
2. Compile only the changed source with `-c`:
   ```
   <compiler> <flags> -c <source> -o .loci-build/<arch>/<basename>.o
   ```
3. Diff `.o.prev` vs `.o` to find changed functions:
   ```
   ${LOCI_ASM_ANALYZE} diff-elfs --elf-path .o.prev --comparing-elf-path .o --arch <arch>
   ```
4. Extract assembly for only `modified`/`added` functions:
   ```
   ${LOCI_ASM_ANALYZE} extract-assembly --elf-path .o --functions <changed_funcs> --arch <arch>
   ```
5. Skip to step 3 (MCP call) below.

If no `.o` exists yet, fall through to full compilation.

## Full Compilation Path

1. Cross-compile the target file for the resolved architecture:
   ```
   <compiler> <flags> -o <binary> <source>
   ```
2. Extract assembly with per-block granularity:
   ```
   ${LOCI_ASM_ANALYZE} extract-assembly --elf-path <binary> --functions <func> --blocks blocks.csv
   ```
   The JSON output contains `timing_csv` (per-block rows like `calculate_0x718,...`) and `timing_architecture`.
   If asm-analyze unavailable, fallback: `objdump -d <binary> | sed -n '/<function>/,/^$/p'`
3. Call `mcp__loci-plugin__get_assembly_block_exec_behavior` with:
   - `csv_text`: the `timing_csv` value from step 2's JSON output
   - `architecture`: the `timing_architecture` value from step 2's JSON output
4. Report execution time and standard deviation in microseconds, and energy consumption in Watt-seconds (`energy_ws`)
