---
description: Create annotated CFG (Control Flow Graphs) in text format optimised for LLM analysis on compiled assembly code to provide execution insights
disable-model-invocation: true
---

# LOCI Timing Analysis

the LOCI_ASM_ANALYZE is in lib/asm_analyze.py

you need to run it from within the .venv that is in the loci-plugin root directory

For example, to generate annotated CFG for a function called `apply_filter` from `filter.elf`:
```
loci-plugin/.venv/bin/python3 loci-plugin/lib/asm_analyze.py extract-cfg \
  --elf-path filter.elf \
  --functions apply_filter
```
The output is in a text format optimized for LLM analysis. Use it in step 5.

## Incremental Path (preferred)

If a previous `.o` exists in `.loci-build/aarch64/`, use incremental compilation:

1. Save the existing `.o` as `.o.prev`
2. Compile only the changed source with `-c`:
   ```
   aarch64-linux-gnu-g++ -O2 -march=armv8-a -c <source> -o .loci-build/aarch64/<basename>.o
   ```
3. Diff `.o.prev` vs `.o` to find changed functions:
   ```
   ${LOCI_ASM_ANALYZE} diff-elfs --elf-path .o.prev --comparing-elf-path .o --arch aarch64
   ```
4. Generate CFG's (Control Flow Graphs) for only `modified`/`added` functions:
   ```
   ${LOCI_ASM_ANALYZE} extract-cfg --elf-path .o --functions <changed_funcs> --arch aarch64
   ```
   The output is in a text format optimized for LLM analysis. Use it in step 5.
5. Report change analysis based on the generated graphs.

If no `.o` exists yet, fall through to full compilation.

## Full Compilation Path

1. Cross-compile the target file for aarch64:
   ```
   aarch64-linux-gnu-g++ -O2 -march=armv8-a -o <binary> <source>
   ```
2. Extract annotated CFG's for analysis:
   ```
   ${LOCI_ASM_ANALYZE} extract-cfg --elf-path <binary> --functions <func>
   ```
   The output is in a text format optimized for LLM analysis. Use it in step 3.
3. Report analysis for selected functions based on the generated CFG's
