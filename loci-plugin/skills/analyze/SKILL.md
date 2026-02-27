---
name: analyze
description: Analyze function  based on compiled assembly code to provide execution insights
disable-model-invocation: true
---

# LOCI Timing Analysis

1. Compile the target file with appropriate flags for the architecture
2. Extract assembly: `${LOCI_SLICER} extract-assembly --elf-path <binary> --functions <func>`
   If slicer unavailable, fallback: `objdump -d <binary> | sed -n '/<function>/,/^$/p'`
3. Call mcp__loci-plugin__get_assembly_block_exec_behavior with:
   - csv_text: timing_csv from step 2's JSON output
   - architecture: timing_architecture from step 2's JSON output
4. Report execution time and standard deviation in microseconds, and energy consumption in Watt-seconds (energy_ws)

Architecture is auto-detected by the slicer. Supported: cortex-a53, cortex-m4, tc399.
