---
name: analyze
description: Analyze C++ function timing on embedded targets
disable-model-invocation: true
---

# LOCI Timing Analysis

1. Compile the target file with appropriate flags for the architecture
2. Extract assembly using objdump: `objdump -d <binary> | sed -n '/<function>/,/^$/p'`
3. Call mcp__loci-mcp__get_assembly_block_timings_per_function with:
   - function_name: "$ARGUMENTS"
   - assembly_code: <extracted assembly>
   - architecture: cortex-m4 (or ask user)
4. Report timing in microseconds with standard deviation