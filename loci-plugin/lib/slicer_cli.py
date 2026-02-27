#!/usr/bin/env python3
"""LOCI Slicer CLI — local ELF binary analysis tool.

Wraps the asmslicer library to provide ELF binary analysis from the
command line. Intended to be called by Claude via Bash, replacing the
former MCP server interface.

Subcommands:
  slice-elf          — Full ELF analysis (asm, symbols, blocks, segments, callgraph, elfinfo)
  extract-assembly   — Per-function assembly in timing-backend-ready format
  extract-symbols    — Symbol map from an ELF
  diff-elfs          — Compare two ELF binaries
  blocks-to-timing   — Transform blocks CSV to timing-backend CSV format
"""

import argparse
import csv
import io
import json
import logging
import os
import re
import sys
import tempfile
import traceback
from pathlib import Path

# ---------------------------------------------------------------------------
# Architecture mapping between slicer and timing backend
# ---------------------------------------------------------------------------
SLICER_TO_TIMING = {
    "aarch64": "cortex-a53",
    "cortexm": "cortex-m4",
    "tricore": "tc399",
}
TIMING_TO_SLICER = {v: k for k, v in SLICER_TO_TIMING.items()}

# Accepted architecture aliases (user input → slicer canonical name)
ARCH_ALIASES = {
    "aarch64": "aarch64",
    "arm64": "aarch64",
    "cortex-a53": "aarch64",
    "cortexm": "cortexm",
    "cortex-m": "cortexm",
    "cortex-m4": "cortexm",
    "thumb": "cortexm",
    "tricore": "tricore",
    "tc399": "tricore",
}


def resolve_arch(arch_input: str | None) -> str | None:
    """Resolve a user-provided architecture string to slicer canonical name."""
    if arch_input is None:
        return None
    return ARCH_ALIASES.get(arch_input.lower().strip())


def timing_arch(slicer_arch: str) -> str:
    """Map slicer architecture name to timing backend name."""
    return SLICER_TO_TIMING.get(slicer_arch, slicer_arch)


# ---------------------------------------------------------------------------
# Output type mappings
# ---------------------------------------------------------------------------
VALID_OUTPUT_TYPES = {"asm", "symbols", "blocks", "segments", "callgraph", "elfinfo"}

# Map output_type names to slicer output file stems
OUTPUT_TYPE_TO_STEM = {
    "asm": "asm",
    "symbols": "symmap",
    "blocks": "blocks",
    "segments": "segments",
    "callgraph": "callgraph",
    "elfinfo": "elfinfo",
}

# Map output_type names to asmslicer.process() keyword argument names
OUTPUT_TYPE_TO_KWARG = {
    "asm": "out_asm_file",
    "symbols": "out_sym_map_file",
    "blocks": "blocks_file_path",
    "segments": "output_file_path",
    "callgraph": "out_plot_file",
    "elfinfo": "out_elfinfo_file",
}


# ---------------------------------------------------------------------------
# Asmslicer wrapper
# ---------------------------------------------------------------------------
def run_slicer(elf_path: str, architecture: str | None = None) -> dict:
    """Run asmslicer.process() and return {arch, files} with raw output content.

    Returns dict with:
        arch: detected/specified architecture (slicer canonical name)
        files: dict mapping output type to file content string
    """
    from loci.service.asmslicer import asmslicer

    elf = Path(elf_path)
    if not elf.is_file():
        raise FileNotFoundError(f"ELF file not found: {elf_path}")

    with tempfile.TemporaryDirectory(prefix="loci-slicer-") as tmpdir:
        kwargs = {
            "elf_file_path": str(elf),
            "log": logging.getLogger("loci.slicer"),
        }
        if architecture:
            kwargs["architecture"] = architecture

        # Set individual output file paths for all output types
        for otype, kwarg in OUTPUT_TYPE_TO_KWARG.items():
            stem = OUTPUT_TYPE_TO_STEM[otype]
            kwargs[kwarg] = os.path.join(tmpdir, f"{stem}.csv")

        asmslicer.process(**kwargs)

        # Read all generated output files
        files = {}
        for f in Path(tmpdir).iterdir():
            if f.is_file():
                files[f.stem] = f.read_text()

        # Detect architecture from elfinfo if not specified
        detected_arch = architecture
        if not detected_arch and "elfinfo" in files:
            elfinfo = files["elfinfo"]
            for arch_key in SLICER_TO_TIMING:
                if arch_key.lower() in elfinfo.lower():
                    detected_arch = arch_key
                    break

        return {"arch": detected_arch, "files": files}


# ---------------------------------------------------------------------------
# Assembly parsing helpers
# ---------------------------------------------------------------------------
FUNC_HEADER_RE = re.compile(r"^([0-9a-fA-F]+)\s+<(.+?)>:\s*$", re.MULTILINE)


def parse_functions_from_asm(asm_text: str) -> dict:
    """Parse objdump-style assembly into per-function blocks.

    Returns dict: {function_name: {"assembly": str, "start_address": str, "instructions": list}}
    """
    functions = {}
    headers = list(FUNC_HEADER_RE.finditer(asm_text))

    for i, match in enumerate(headers):
        addr = match.group(1)
        name = match.group(2)
        start = match.end()
        end = headers[i + 1].start() if i + 1 < len(headers) else len(asm_text)
        body = asm_text[start:end].rstrip("\n")

        # Filter out empty function bodies
        lines = [ln for ln in body.split("\n") if ln.strip()]
        if not lines:
            continue

        functions[name] = {
            "assembly": "\n".join(lines),
            "start_address": f"0x{addr}",
            "instructions": lines,
        }

    return functions


def parse_symbols(symmap_text: str) -> list:
    """Parse symmap CSV into list of symbol dicts."""
    symbols = []
    reader = csv.DictReader(io.StringIO(symmap_text))
    for row in reader:
        symbols.append({
            "name": row.get("name", ""),
            "long_name": row.get("long_name", ""),
            "start_address": row.get("start_address", ""),
            "size": int(row.get("size", 0)) if row.get("size", "").isdigit() else 0,
            "namespace": row.get("namespace", ""),
        })
    return symbols


def match_function(query: str, sym_name: str, sym_long_name: str) -> bool:
    """Check if a query matches a symbol's name or long_name.

    Supports exact match and prefix match (ignoring parameter lists).
    """
    if query == sym_name or query == sym_long_name:
        return True
    # Match demangled name without params: "calculate" matches "calculate(int)"
    if sym_long_name.startswith(query + "("):
        return True
    # Match short name without params
    if sym_name.startswith(query + "("):
        return True
    return False


def parse_blocks_to_timing_csv(blocks_text: str,
                                functions: list[str] | None = None) -> str:
    """Parse blocks CSV and produce timing-format CSV.

    Blocks CSV columns: s1.name, s1.long_name, r.from_addr, r.to_addr,
                        r.asm, db.block_ids, r.src_location

    Output CSV: function_name, assembly_code
        function_name = {s1.long_name}_{r.from_addr}
        assembly_code = r.asm (as-is)
    """
    reader = csv.DictReader(io.StringIO(blocks_text))

    csv_buf = io.StringIO()
    writer = csv.writer(csv_buf)
    writer.writerow(["function_name", "assembly_code"])

    for row in reader:
        long_name = row.get("s1.long_name", "")
        from_addr = row.get("r.from_addr", "")
        asm = row.get("r.asm", "")

        if not long_name or not asm:
            continue

        # Filter by function names if specified
        if functions:
            short_name = row.get("s1.name", "")
            if not any(match_function(f, short_name, long_name)
                       for f in functions):
                continue

        function_name = f"{long_name}_{from_addr}"
        writer.writerow([function_name, asm])

    return csv_buf.getvalue()


# ---------------------------------------------------------------------------
# Subcommand implementations
# ---------------------------------------------------------------------------
def slice_elf(elf_path: str, architecture: str | None = None,
              output_types: list[str] | None = None,
              filter_functions: bool = False) -> dict:
    output_types = output_types or ["asm", "symbols"]

    # Validate output_types
    invalid = set(output_types) - VALID_OUTPUT_TYPES
    if invalid:
        return {"error": f"Invalid output_types: {sorted(invalid)}. Valid: {sorted(VALID_OUTPUT_TYPES)}"}

    arch = resolve_arch(architecture)
    result = run_slicer(elf_path, arch)
    detected_arch = result["arch"]
    files = result["files"]

    output = {}
    for otype in output_types:
        stem = OUTPUT_TYPE_TO_STEM.get(otype, otype)
        content = files.get(stem)
        if content is None:
            output[otype] = None
            continue

        if otype == "asm":
            funcs = parse_functions_from_asm(content)
            if filter_functions:
                funcs = {
                    k: v for k, v in funcs.items()
                    if not k.startswith("_") or k.startswith("_Z")
                }
            output[otype] = {
                fname: {
                    "assembly": fdata["assembly"],
                    "start_address": fdata["start_address"],
                    "instruction_count": len(fdata["instructions"]),
                }
                for fname, fdata in funcs.items()
            }
        elif otype == "symbols":
            output[otype] = parse_symbols(content)
        else:
            # Return raw text for blocks, segments, callgraph, elfinfo
            output[otype] = content

    output["architecture"] = detected_arch
    output["timing_architecture"] = timing_arch(detected_arch) if detected_arch else None

    return output


def extract_assembly(elf_path: str, functions: list[str],
                     architecture: str | None = None,
                     blocks_file: str | None = None) -> dict:
    arch = resolve_arch(architecture)
    result = run_slicer(elf_path, arch)
    detected_arch = result["arch"]
    files = result["files"]

    asm_text = files.get("asm")
    if not asm_text:
        return {"error": "No assembly output produced by slicer"}

    all_funcs = parse_functions_from_asm(asm_text)

    # Build symbol lookup for name matching
    symmap_text = files.get("symmap", "")
    symbols = parse_symbols(symmap_text) if symmap_text else []

    # Build a mapping from asm function name to symbol info
    sym_lookup = {}
    for sym in symbols:
        sym_lookup[sym["name"]] = sym
        if sym["long_name"]:
            sym_lookup[sym["long_name"]] = sym

    # Match requested functions
    matched = {}
    for query in functions:
        # Try direct match in asm functions first
        if query in all_funcs:
            matched[query] = all_funcs[query]
            continue

        # Try matching via symbol names
        found = False
        for asm_name, asm_data in all_funcs.items():
            # Check against symbol lookup
            sym = sym_lookup.get(asm_name, {})
            sym_name = sym.get("name", asm_name) if sym else asm_name
            sym_long = sym.get("long_name", "") if sym else ""
            if match_function(query, sym_name, sym_long):
                matched[query] = asm_data
                found = True
                break
            # Also try direct asm_name match
            if match_function(query, asm_name, asm_name):
                matched[query] = asm_data
                found = True
                break

        if not found:
            matched[query] = {"error": f"Function '{query}' not found in ELF"}

    # Write blocks CSV to file if requested
    blocks_text = files.get("blocks", "")
    if blocks_file and blocks_text:
        Path(blocks_file).write_text(blocks_text)

    # Build output
    functions_out = {}
    csv_rows = []
    for fname, fdata in matched.items():
        if "error" in fdata:
            functions_out[fname] = fdata
            continue

        asm = fdata["assembly"]
        instruction_count = len(fdata["instructions"])
        # Calculate size from instruction count (approximate: varies by arch)
        size = instruction_count * 4  # ARM/AArch64 = 4 bytes, Tricore = 4 bytes

        functions_out[fname] = {
            "assembly": asm,
            "start_address": fdata["start_address"],
            "size": size,
            "instruction_count": instruction_count,
        }
        # CSV row: quote the assembly for proper CSV formatting
        csv_rows.append((fname, asm))

    # Build timing CSV — prefer per-block granularity when blocks available
    if blocks_file and blocks_text:
        timing_csv = parse_blocks_to_timing_csv(blocks_text, functions)
    else:
        csv_buf = io.StringIO()
        writer = csv.writer(csv_buf)
        writer.writerow(["function_name", "assembly_code"])
        for fname, asm in csv_rows:
            writer.writerow([fname, asm])
        timing_csv = csv_buf.getvalue()

    output = {
        "architecture": detected_arch,
        "timing_architecture": timing_arch(detected_arch) if detected_arch else None,
        "functions": functions_out,
        "timing_csv": timing_csv,
    }
    if blocks_file and blocks_text:
        output["blocks_file"] = blocks_file

    return output


def extract_symbols(elf_path: str, architecture: str | None = None) -> dict:
    arch = resolve_arch(architecture)
    result = run_slicer(elf_path, arch)
    files = result["files"]

    symmap_text = files.get("symmap")
    if not symmap_text:
        return {"error": "No symbol map output produced by slicer"}

    symbols = parse_symbols(symmap_text)

    return {
        "architecture": result["arch"],
        "symbols": symbols,
    }


def diff_elfs(elf_path: str, comparing_elf_path: str,
              architecture: str | None = None) -> dict:
    from loci.service.asmslicer import asmslicer

    arch = resolve_arch(architecture)

    # Validate both files exist
    if not Path(elf_path).is_file():
        return {"error": f"Base ELF not found: {elf_path}"}
    if not Path(comparing_elf_path).is_file():
        return {"error": f"Comparing ELF not found: {comparing_elf_path}"}

    with tempfile.TemporaryDirectory(prefix="loci-slicer-diff-") as tmpdir:
        diff_kwargs = {
            "elf_file_path": elf_path,
            "comparing_elf_file_path": comparing_elf_path,
            "compare_out": tmpdir,
            "log": logging.getLogger("loci.slicer"),
        }
        if arch:
            diff_kwargs["architecture"] = arch

        asmslicer.process(**diff_kwargs)

        # Read diff output
        files = {}
        for f in Path(tmpdir).iterdir():
            if f.is_file():
                files[f.stem] = f.read_text()

    # Parse diff CSV if available
    diff_text = files.get("diff", "")
    diff_entries = []
    summary = {"added": 0, "removed": 0, "modified": 0, "unchanged": 0}

    if diff_text:
        reader = csv.DictReader(io.StringIO(diff_text))
        for row in reader:
            status = row.get("status", "").lower()
            entry = {
                "status": status,
                "symbol": row.get("symbol", ""),
                "stt_type": row.get("stt_type", ""),
                "similarity_ratio": float(row.get("similarity_ratio", 0))
                if row.get("similarity_ratio", "").replace(".", "").isdigit()
                else 0.0,
                "reason": row.get("reason", ""),
            }
            diff_entries.append(entry)
            if status in summary:
                summary[status] += 1

    return {
        "diff": diff_entries,
        "summary": summary,
    }


def blocks_to_timing(blocks_file: str,
                     functions: list[str] | None = None) -> None:
    """Read blocks CSV and print timing-format CSV to stdout."""
    blocks_path = Path(blocks_file)
    if not blocks_path.is_file():
        print(json.dumps({"error": f"Blocks file not found: {blocks_file}"}))
        sys.exit(1)

    blocks_text = blocks_path.read_text()
    timing_csv = parse_blocks_to_timing_csv(blocks_text, functions)
    print(timing_csv, end="")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        prog="slicer_cli",
        description="LOCI Slicer — local ELF binary analysis tool",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # slice-elf
    p_slice = subparsers.add_parser(
        "slice-elf",
        help="Full ELF analysis (asm, symbols, blocks, segments, callgraph, elfinfo)",
    )
    p_slice.add_argument("--elf-path", required=True, help="Path to the ELF binary")
    p_slice.add_argument("--arch", default=None, help="Target architecture (auto-detected if omitted)")
    p_slice.add_argument("--output-types", default="asm,symbols",
                         help="Comma-separated output types (default: asm,symbols)")
    p_slice.add_argument("--filter-functions", action="store_true",
                         help="Filter compiler-generated functions")

    # extract-assembly
    p_extract = subparsers.add_parser(
        "extract-assembly",
        help="Per-function assembly in timing-backend-ready format",
    )
    p_extract.add_argument("--elf-path", required=True, help="Path to the ELF binary")
    p_extract.add_argument("--functions", required=True,
                           help="Comma-separated function names to extract")
    p_extract.add_argument("--arch", default=None, help="Target architecture (auto-detected if omitted)")
    p_extract.add_argument("--blocks", default=None, metavar="FILE",
                           help="Write basic blocks CSV to this file")

    # extract-symbols
    p_symbols = subparsers.add_parser(
        "extract-symbols",
        help="Extract symbol map from an ELF binary",
    )
    p_symbols.add_argument("--elf-path", required=True, help="Path to the ELF binary")
    p_symbols.add_argument("--arch", default=None, help="Target architecture (auto-detected if omitted)")

    # diff-elfs
    p_diff = subparsers.add_parser(
        "diff-elfs",
        help="Compare two ELF binaries",
    )
    p_diff.add_argument("--elf-path", required=True, help="Path to the base ELF binary")
    p_diff.add_argument("--comparing-elf-path", required=True, help="Path to the changed ELF binary")
    p_diff.add_argument("--arch", default=None, help="Target architecture (auto-detected if omitted)")

    # blocks-to-timing
    p_blocks = subparsers.add_parser(
        "blocks-to-timing",
        help="Transform blocks CSV to timing-backend CSV format",
    )
    p_blocks.add_argument("--blocks", required=True, metavar="FILE",
                          help="Path to blocks CSV file")
    p_blocks.add_argument("--functions", default=None,
                          help="Comma-separated function names to filter")

    args = parser.parse_args()

    try:
        if args.command == "blocks-to-timing":
            funcs = ([f.strip() for f in args.functions.split(",")]
                     if args.functions else None)
            blocks_to_timing(blocks_file=args.blocks, functions=funcs)
            sys.exit(0)

        if args.command == "slice-elf":
            output_types = [t.strip() for t in args.output_types.split(",")]
            result = slice_elf(
                elf_path=args.elf_path,
                architecture=args.arch,
                output_types=output_types,
                filter_functions=args.filter_functions,
            )
        elif args.command == "extract-assembly":
            functions = [f.strip() for f in args.functions.split(",")]
            result = extract_assembly(
                elf_path=args.elf_path,
                functions=functions,
                architecture=args.arch,
                blocks_file=args.blocks,
            )
        elif args.command == "extract-symbols":
            result = extract_symbols(
                elf_path=args.elf_path,
                architecture=args.arch,
            )
        elif args.command == "diff-elfs":
            result = diff_elfs(
                elf_path=args.elf_path,
                comparing_elf_path=args.comparing_elf_path,
                architecture=args.arch,
            )
        else:
            result = {"error": f"Unknown command: {args.command}"}

        print(json.dumps(result, indent=2))
        sys.exit(1 if "error" in result else 0)

    except Exception as e:
        print(json.dumps({
            "error": str(e),
            "traceback": traceback.format_exc(),
        }))
        sys.exit(1)


if __name__ == "__main__":
    main()
