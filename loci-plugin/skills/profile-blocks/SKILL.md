---
description: Profile basic blocks of changed functions — per-block timing, happy-path self-time, baseline storage
disable-model-invocation: true
---

# LOCI Block-Level Profiling

## 1. RECOMPILE FOR CORTEX-M4

- Identify the source file that was just modified and the compile command from session context
  (`loci-plugin/state/loci-context.json` → compilation_history / last compile action)

**Incremental sub-path (preferred):** If a `.o` for this source already exists in `.loci-build/cortex-m4/`:
  1. Save it as `.o.prev`
  2. Recompile only the changed translation unit with `-c`:
     ```
     arm-none-eabi-g++ -mcpu=cortex-m4 -mthumb -O2 <flags> -c <source> -o .loci-build/cortex-m4/<basename>.o
     ```
  3. Continue to step 2 using `.o.prev` and the new `.o`

**Full path:** Recompile the full ELF targeting ARM Cortex-M4:
  ```
  arm-none-eabi-g++ -mcpu=cortex-m4 -mthumb -O2 <flags> -o <binary> <source>
  ```
- If the last compile command exists in session context, re-run it with `-mcpu=cortex-m4 -mthumb` added/replaced
- Otherwise use the defaults above
- Save the previous ELF (if it exists) as `<binary>.prev` before recompiling for diff in step 2

## 2. DETECT CHANGED FUNCTIONS

- If a previous ELF exists (`<binary>.prev`), run:
  ```
  ${LOCI_SLICER} diff-elfs --elf-path <binary>.prev --comparing-elf-path <binary> --arch cortex-m4
  ```
- From the diff output, collect all function names with status `modified` or `added`
- If no previous ELF exists, use `$ARGUMENTS` or the function(s) in the edited source file

## 3. EXTRACT BLOCKS

- Run:
  ```
  ${LOCI_SLICER} slice-elf --elf-path <binary> --output-types blocks,asm --arch cortex-m4
  ```
- From the `blocks` CSV output, filter rows belonging to the changed functions
- From the `asm` output, get per-function assembly for reference

## 4. BUILD BLOCK-LEVEL CSV

- For each changed function, split its assembly into basic blocks using the blocks CSV from step 3 for block boundaries and addresses
- Build a CSV with header: `function_name,assembly_code`
- Each row is one basic block. Use block ID format: `<function_name>::<block_address>`
- Each block contains multiple assembly lines — join them with literal `\n` so the block stays on a single CSV row, and quote the assembly_code field
- Example:
  ```
  function_name,assembly_code
  process_frame::0x1000,"push {r4-r7, lr}\nldr r3, [r0]\nmov r1, #0"
  process_frame::0x1010,"cmp r0, #0\nbeq 0x1030"
  process_frame::0x1020,"add r0, r1\nstr r0, [sp]\nadd r2, r2, #1"
  process_frame::0x1030,"pop {r4-r7, pc}"
  ```

## 5. SEND TO TIMING BACKEND

- Call `mcp__loci-plugin__get_assembly_block_exec_behavior` with:
  - **csv_text**: the block-level CSV from step 4
  - **architecture**: `cortex-m4`

## 6. ANALYZE RESULTS — HAPPY PATH SELF-TIME

- Receive per-block timing: each block ID maps to `{execution_time_ns, std_dev_ns, energy_ws}`
- Reconstruct the control flow graph from block addresses and branch targets in the assembly:
  - Parse branch instructions (`b`, `beq`, `bne`, `bgt`, `blt`, `bge`, `ble`, `bx`, `bl`, `blx`, `cbz`, `cbnz`) and their target addresses
  - Map each block to its successors (fall-through + branch target)
- Identify the **happy path**: the fall-through execution path that avoids error handling, exception branches, and unlikely paths
  - The happy path follows fall-through (sequential) block order by default
  - Branches to error labels, exception handlers, or backward jumps to retry loops are excluded
- For each block on the happy path:
  - If the block contains a **call instruction** (`bl`, `blx`): it contributes callee time — track separately
  - If the block is **pure computation** (no calls): add its time to self-time
- Calculate:
  - **Self function time** = sum of happy-path blocks with no function calls
  - **Callee time** = sum of happy-path blocks that contain `bl`/`blx` calls
  - **Total happy-path time** = self-time + callee time
- Report: self-time, total time, callee overhead, energy, and per-block breakdown table

## 7. STORE BASELINE

- Read existing baselines from `loci-plugin/state/loci-baselines.json`
- Write entry with key format: `<binary_path>::<function_name>::cortex-m4::blocks`
- Value:
  ```json
  {
    "self_time_ns": <number>,
    "total_time_ns": <number>,
    "callee_time_ns": <number>,
    "std_dev_ns": <number>,
    "energy_ws": <number>,
    "block_count": <number>,
    "happy_path_blocks": <number>,
    "architecture": "cortex-m4",
    "timestamp": "<ISO 8601>"
  }
  ```
- If a baseline already exists for this key, compare and report the delta (regression or improvement) for self-time, total time, and energy
- Write the updated baselines file back to `loci-plugin/state/loci-baselines.json`
