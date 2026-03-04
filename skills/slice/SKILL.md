---
name: slice
description: Analyze ELF binary structure — symbols, assembly, basic blocks, callgraph, diff
disable-model-invocation: true
---

# LOCI Binary Slicer

1. Identify the ELF binary from "$ARGUMENTS" or the most recently compiled binary in the project. The slicer also supports `.o` object files for per-translation-unit analysis.
2. Run: `${LOCI_SLICER} extract-symbols --elf-path <binary>`
3. Run: `${LOCI_SLICER} slice-elf --elf-path <binary> --output-types <types>`
   - For disassembly: `--output-types asm`
   - For full analysis: `--output-types asm,symbols,blocks,segments,callgraph,elfinfo`
   - For specific outputs: select from the list above
4. For binary comparison (if two ELFs provided): `${LOCI_SLICER} diff-elfs --elf-path <base> --comparing-elf-path <changed>`
5. Present the results organized by output type

Architecture is auto-detected. Override with `--arch`. Supported: `aarch64`, `cortexm`, `tricore`.
