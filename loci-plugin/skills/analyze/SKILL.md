---
description: Analyze function  based on compiled assembly code to provide execution insights
disable-model-invocation: true
---

# LOCI Timing Analysis

1. Compile the target file with appropriate flags for the architecture
2. Extract assembly using objdump: `objdump -d <binary> | sed -n '/<function>/,/^$/p'`
3. Call mcp__loci-mcp__get_assembly_block_exec_behavior_per_function with:
   - function_name: "$ARGUMENTS"
   - assembly_code: <extracted assembly>
   - architecture: cortex-m4 (or ask user)
4. Report execution time and standard deviation in microseconds, and energy consumption in Watt-seconds (energy_ws)