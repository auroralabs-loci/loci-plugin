#!/usr/bin/env python3
"""LOCI Slicer MCP Server — stdio transport.

Wraps the asmslicer library to provide ELF binary analysis tools
via the Model Context Protocol. Intended to run as a local stdio
MCP server bundled with the LOCI plugin.

Tools:
  slice_elf          — Full ELF analysis (asm, symbols, blocks, segments, callgraph, elfinfo)
  extract_assembly   — Per-function assembly in timing-backend-ready format
  extract_symbols    — Symbol map from an ELF
  diff_elfs          — Compare two ELF binaries
"""

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

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import (
    TextContent,
    Tool,
)

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


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------
server = Server("loci-slicer")


@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="slice_elf",
            description=(
                "Full ELF binary analysis. Runs the LOCI asmslicer and returns "
                "requested output types: asm (disassembly), symbols (symbol map), "
                "blocks (basic blocks), segments, callgraph, elfinfo."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "elf_path": {
                        "type": "string",
                        "description": "Absolute path to the ELF binary",
                    },
                    "architecture": {
                        "type": "string",
                        "description": (
                            'Target architecture: "aarch64", "cortexm", "tricore" '
                            "(or timing names: cortex-a53, cortex-m4, tc399). "
                            "Auto-detected if omitted."
                        ),
                    },
                    "output_types": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": (
                            'Subset of ["asm","symbols","blocks","segments","callgraph","elfinfo"]. '
                            'Default: ["asm","symbols"]'
                        ),
                    },
                    "filter_functions": {
                        "type": "boolean",
                        "description": "Filter compiler-generated functions. Default: false",
                    },
                },
                "required": ["elf_path"],
            },
        ),
        Tool(
            name="extract_assembly",
            description=(
                "Extract per-function assembly from an ELF binary in the exact format "
                "the LOCI timing backend expects. Returns assembly, metadata, and a "
                "pre-formatted timing_csv for direct pass-through to "
                "mcp__loci-mcp__get_assembly_block_exec_behavior."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "elf_path": {
                        "type": "string",
                        "description": "Absolute path to the ELF binary",
                    },
                    "functions": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Function names to extract (mangled or demangled)",
                    },
                    "architecture": {
                        "type": "string",
                        "description": "Target architecture. Auto-detected if omitted.",
                    },
                },
                "required": ["elf_path", "functions"],
            },
        ),
        Tool(
            name="extract_symbols",
            description="Extract the symbol map from an ELF binary.",
            inputSchema={
                "type": "object",
                "properties": {
                    "elf_path": {
                        "type": "string",
                        "description": "Absolute path to the ELF binary",
                    },
                    "architecture": {
                        "type": "string",
                        "description": "Target architecture. Auto-detected if omitted.",
                    },
                },
                "required": ["elf_path"],
            },
        ),
        Tool(
            name="diff_elfs",
            description="Compare two ELF binaries and report added, removed, and modified symbols.",
            inputSchema={
                "type": "object",
                "properties": {
                    "elf_path": {
                        "type": "string",
                        "description": "Absolute path to the base ELF binary",
                    },
                    "comparing_elf_path": {
                        "type": "string",
                        "description": "Absolute path to the changed ELF binary",
                    },
                    "architecture": {
                        "type": "string",
                        "description": "Target architecture. Auto-detected if omitted.",
                    },
                },
                "required": ["elf_path", "comparing_elf_path"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[TextContent]:
    try:
        if name == "slice_elf":
            return await _slice_elf(arguments)
        elif name == "extract_assembly":
            return await _extract_assembly(arguments)
        elif name == "extract_symbols":
            return await _extract_symbols(arguments)
        elif name == "diff_elfs":
            return await _diff_elfs(arguments)
        else:
            return [TextContent(
                type="text",
                text=json.dumps({"error": f"Unknown tool: {name}"}),
            )]
    except Exception as e:
        return [TextContent(
            type="text",
            text=json.dumps({
                "error": str(e),
                "traceback": traceback.format_exc(),
            }),
        )]


# ---------------------------------------------------------------------------
# Tool implementations
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


async def _slice_elf(args: dict) -> list[TextContent]:
    elf_path = args["elf_path"]
    arch = resolve_arch(args.get("architecture"))
    output_types = args.get("output_types", ["asm", "symbols"])
    filter_funcs = args.get("filter_functions", False)

    # Validate output_types
    invalid = set(output_types) - VALID_OUTPUT_TYPES
    if invalid:
        return [TextContent(
            type="text",
            text=json.dumps({"error": f"Invalid output_types: {sorted(invalid)}. Valid: {sorted(VALID_OUTPUT_TYPES)}"}),
        )]

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
            if filter_funcs:
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

    return [TextContent(type="text", text=json.dumps(output, indent=2))]


async def _extract_assembly(args: dict) -> list[TextContent]:
    elf_path = args["elf_path"]
    requested_funcs = args["functions"]
    arch = resolve_arch(args.get("architecture"))

    result = run_slicer(elf_path, arch)
    detected_arch = result["arch"]
    files = result["files"]

    asm_text = files.get("asm")
    if not asm_text:
        return [TextContent(
            type="text",
            text=json.dumps({"error": "No assembly output produced by slicer"}),
        )]

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
    for query in requested_funcs:
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

    # Build timing CSV
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

    return [TextContent(type="text", text=json.dumps(output, indent=2))]


async def _extract_symbols(args: dict) -> list[TextContent]:
    elf_path = args["elf_path"]
    arch = resolve_arch(args.get("architecture"))

    result = run_slicer(elf_path, arch)
    files = result["files"]

    symmap_text = files.get("symmap")
    if not symmap_text:
        return [TextContent(
            type="text",
            text=json.dumps({"error": "No symbol map output produced by slicer"}),
        )]

    symbols = parse_symbols(symmap_text)

    output = {
        "architecture": result["arch"],
        "symbols": symbols,
    }

    return [TextContent(type="text", text=json.dumps(output, indent=2))]


async def _diff_elfs(args: dict) -> list[TextContent]:
    from loci.service.asmslicer import asmslicer

    elf_path = args["elf_path"]
    comparing_elf_path = args["comparing_elf_path"]
    arch = resolve_arch(args.get("architecture"))

    # Validate both files exist
    if not Path(elf_path).is_file():
        return [TextContent(
            type="text",
            text=json.dumps({"error": f"Base ELF not found: {elf_path}"}),
        )]
    if not Path(comparing_elf_path).is_file():
        return [TextContent(
            type="text",
            text=json.dumps({"error": f"Comparing ELF not found: {comparing_elf_path}"}),
        )]

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

    output = {
        "diff": diff_entries,
        "summary": summary,
    }

    return [TextContent(type="text", text=json.dumps(output, indent=2))]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
