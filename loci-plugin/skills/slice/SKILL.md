---
name: slice
description: Analyze ELF binary structure — symbols, assembly, basic blocks, callgraph, diff
disable-model-invocation: true
---

# LOCI Binary Slicer

1. Identify the ELF binary from "$ARGUMENTS" or the most recently compiled binary in the project
2. Call mcp__loci-slicer__extract_symbols to list available functions
3. Call mcp__loci-slicer__slice_elf with the ELF path and requested output_types:
   - For disassembly: output_types ["asm"]
   - For full analysis: output_types ["asm", "symbols", "blocks", "segments", "callgraph", "elfinfo"]
   - For specific outputs: select from the list above
4. For binary comparison (if two ELFs provided): call mcp__loci-slicer__diff_elfs with elf_path and comparing_elf_path
5. Present the results organized by output type

Architecture is auto-detected. Supported: aarch64 (cortex-a53), cortexm (cortex-m4), tricore (tc399).
