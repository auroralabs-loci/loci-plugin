---
name: analyze
description: Analyze function  based on compiled assembly code to provide execution insights
disable-model-invocation: true
---

# LOCI Timing Analysis

1. Compile the target file with appropriate flags for the architecture
2. Extract assembly: call mcp__loci-slicer__extract_assembly with:
   - elf_path: <compiled binary>
   - functions: ["$ARGUMENTS"]
   If slicer unavailable, fallback: `objdump -d <binary> | sed -n '/<function>/,/^$/p'`
3. Call mcp__loci-mcp__get_assembly_block_timings_per_function with:
   - function_name, assembly_code (from step 2), architecture
4. Report timing in microseconds with standard deviation

Architecture is auto-detected by the slicer. Supported: cortex-a53, cortex-m4, tc399.