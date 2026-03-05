#!/usr/bin/env python3
"""
LOCI Hook Performance Monitor
=============================
Tracks hook overhead, LOCI server performance, and provides system health metrics.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any
import re


class HookMonitor:
    def __init__(self, state_dir: Path):
        self.state_dir = state_dir
        self.actions_log = state_dir / "loci-actions.log"

    def get_hook_stats(self) -> Dict[str, Any]:
        """Analyze hook activity from action log."""
        stats = {
            "total_actions": 0,
            "actions_by_type": {},
            "actions_by_tool": {},
            "last_action_ago_seconds": 0,
        }

        if not self.actions_log.exists():
            return stats

        try:
            with open(self.actions_log) as f:
                lines = f.readlines()
                if not lines:
                    return stats

                last_action_time = None
                for line in lines:
                    try:
                        action = json.loads(line.strip())
                        stats["total_actions"] += 1

                        # Count by type
                        action_type = action.get("action_type", "unknown")
                        stats["actions_by_type"][action_type] = (
                            stats["actions_by_type"].get(action_type, 0) + 1
                        )

                        # Count by tool
                        tool = action.get("tool_name", "unknown")
                        stats["actions_by_tool"][tool] = (
                            stats["actions_by_tool"].get(tool, 0) + 1
                        )

                        # Track last action time
                        if "timestamp" in action:
                            last_action_time = action["timestamp"]
                    except json.JSONDecodeError:
                        continue

                # Calculate time since last action
                if last_action_time:
                    try:
                        last_dt = datetime.fromisoformat(last_action_time.replace('Z', '+00:00'))
                        now = datetime.now(timezone.utc)
                        stats["last_action_ago_seconds"] = int((now - last_dt).total_seconds())
                    except Exception:
                        pass

        except Exception as e:
            print(f"Error reading action log: {e}")

        return stats

    def get_warning_stats(self) -> Dict[str, Any]:
        """Get warning statistics."""
        stats = {
            "total_warnings": 0,
            "active_warnings": 0,
            "warnings_by_severity": {},
            "warnings_by_category": {},
        }

        warnings_file = self.state_dir / "loci-warnings.json"
        if not warnings_file.exists():
            return stats

        try:
            with open(warnings_file) as f:
                data = json.load(f)
                warnings = data.get("warnings", [])

                stats["total_warnings"] = len(warnings)
                for warning in warnings:
                    if warning.get("active", True):
                        stats["active_warnings"] += 1

                    severity = warning.get("severity", "unknown")
                    stats["warnings_by_severity"][severity] = (
                        stats["warnings_by_severity"].get(severity, 0) + 1
                    )

                    category = warning.get("category", "unknown")
                    stats["warnings_by_category"][category] = (
                        stats["warnings_by_category"].get(category, 0) + 1
                    )
        except Exception as e:
            print(f"Error reading warnings: {e}")

        return stats

    def get_compilation_stats(self) -> Dict[str, Any]:
        """Get C++ compilation statistics."""
        stats = {
            "total_compilations": 0,
            "unique_binaries": 0,
            "unique_source_files": 0,
            "optimization_levels": {},
        }

        if not self.actions_log.exists():
            return stats

        binaries = set()
        source_files = set()
        compilations = 0

        try:
            with open(self.actions_log) as f:
                for line in f:
                    try:
                        action = json.loads(line.strip())
                        if action.get("action_type") in ("cpp_compile", "cpp_build", "cpp_link"):
                            compilations += 1

                            cpp_context = action.get("cpp_context", {})

                            # Track binaries
                            output = cpp_context.get("output_binary", "")
                            if output:
                                binaries.add(output)

                            # Track source files
                            for f in action.get("files_involved", []):
                                if any(f.endswith(ext) for ext in ['.cpp', '.cxx', '.cc', '.c', '.hpp', '.h']):
                                    source_files.add(f)

                            # Track optimization levels
                            opt = cpp_context.get("optimization_level", "none")
                            stats["optimization_levels"][opt] = (
                                stats["optimization_levels"].get(opt, 0) + 1
                            )
                    except json.JSONDecodeError:
                        continue

            stats["total_compilations"] = compilations
            stats["unique_binaries"] = len(binaries)
            stats["unique_source_files"] = len(source_files)

        except Exception as e:
            print(f"Error reading compilation stats: {e}")

        return stats

    def get_hook_overhead(self) -> Dict[str, Any]:
        """Estimate hook execution overhead."""
        overhead = {
            "estimated_total_ms": 0,
            "per_action_ms": 0,
            "hook_frequency": "unknown",
        }

        hook_stats = self.get_hook_stats()

        if hook_stats["total_actions"] > 0:
            # Rough estimation: each hook takes 5-50ms depending on complexity
            # Async hooks average 5ms, sync hooks average 20ms
            async_actions = (
                hook_stats["actions_by_type"].get("agent_delegation", 0) +
                hook_stats["actions_by_type"].get("loci_mcp_tool", 0) * 0.5
            )
            sync_actions = hook_stats["total_actions"] - async_actions

            overhead["estimated_total_ms"] = int(async_actions * 5 + sync_actions * 20)
            overhead["per_action_ms"] = round(
                overhead["estimated_total_ms"] / hook_stats["total_actions"], 2
            )

            # Categorize overhead
            if overhead["per_action_ms"] < 10:
                overhead["hook_frequency"] = "Low (< 10ms/action)"
            elif overhead["per_action_ms"] < 30:
                overhead["hook_frequency"] = "Moderate (10-30ms/action)"
            else:
                overhead["hook_frequency"] = "High (> 30ms/action)"

        return overhead

    def print_status(self):
        """Print formatted status report."""
        print("\n" + "=" * 70)
        print("LOCI HOOK PERFORMANCE MONITOR")
        print("=" * 70 + "\n")

        # Hook Activity
        print("HOOK ACTIVITY")
        print("-" * 70)
        hook_stats = self.get_hook_stats()
        print(f"  Total Actions:     {hook_stats['total_actions']}")
        print(f"  Last Action:       {hook_stats['last_action_ago_seconds']}s ago")
        print()

        if hook_stats["actions_by_tool"]:
            print("  Actions by Tool:")
            for tool, count in sorted(hook_stats["actions_by_tool"].items(), key=lambda x: x[1], reverse=True)[:5]:
                print(f"    {tool:20s}: {count:4d}")
        print()

        if hook_stats["actions_by_type"]:
            print("  Top Action Types:")
            for atype, count in sorted(hook_stats["actions_by_type"].items(), key=lambda x: x[1], reverse=True)[:5]:
                print(f"    {atype:30s}: {count:4d}")
        print()

        # Hook Overhead
        print("PERFORMANCE")
        print("-" * 70)
        overhead = self.get_hook_overhead()
        print(f"  Hook Overhead:     {overhead['hook_frequency']}")
        print(f"  Estimated Total:   {overhead['estimated_total_ms']}ms")
        print(f"  Per Action:        {overhead['per_action_ms']}ms")
        print()

        # C++ Analysis
        print("C++ COMPILATION")
        print("-" * 70)
        comp_stats = self.get_compilation_stats()
        print(f"  Total Compilations: {comp_stats['total_compilations']}")
        print(f"  Unique Binaries:    {comp_stats['unique_binaries']}")
        print(f"  Source Files:       {comp_stats['unique_source_files']}")
        if comp_stats["optimization_levels"]:
            print(f"  Optimization Levels:")
            for opt, count in sorted(comp_stats["optimization_levels"].items(), key=lambda x: x[1], reverse=True):
                print(f"    {opt or 'none':10s}: {count:3d}")
        print()

        # Warnings
        print("ANALYSIS INSIGHTS")
        print("-" * 70)
        warn_stats = self.get_warning_stats()
        print(f"  Total Warnings:    {warn_stats['total_warnings']}")
        print(f"  Active Warnings:   {warn_stats['active_warnings']}")
        if warn_stats["warnings_by_severity"]:
            print(f"  By Severity:")
            for sev, count in sorted(warn_stats["warnings_by_severity"].items(), key=lambda x: x[1], reverse=True):
                print(f"    {sev:10s}: {count:3d}")
        if warn_stats["warnings_by_category"]:
            print(f"  By Category:")
            for cat, count in sorted(warn_stats["warnings_by_category"].items(), key=lambda x: x[1], reverse=True)[:5]:
                print(f"    {cat:20s}: {count:3d}")
        print()

        print("=" * 70 + "\n")

    def watch_mode(self, interval: int = 5):
        """Continuous monitoring mode."""
        try:
            while True:
                os.system("clear" if os.name == "posix" else "cls")
                self.print_status()
                print(f"Auto-refreshing every {interval}s (Ctrl+C to stop)\n")
                import time
                time.sleep(interval)
        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
            sys.exit(0)


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="LOCI Hook Performance Monitor"
    )
    parser.add_argument(
        "--state-dir",
        type=Path,
        help="State directory (auto-detected if not specified)",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Continuous monitoring mode",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=5,
        help="Refresh interval in watch mode (seconds)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON",
    )

    args = parser.parse_args()

    # Auto-detect state directory
    if args.state_dir:
        state_dir = args.state_dir
    else:
        # Find the state directory relative to this script
        script_dir = Path(__file__).parent.parent
        state_dir = script_dir / "state"

    if not state_dir.exists():
        print(f"Error: State directory not found: {state_dir}")
        print("Run: ./loci-plugin/scripts/configure.sh")
        sys.exit(1)

    monitor = HookMonitor(state_dir)

    if args.json:
        # Output all stats as JSON
        output = {
            "hooks": monitor.get_hook_stats(),
            "overhead": monitor.get_hook_overhead(),
            "warnings": monitor.get_warning_stats(),
            "compilation": monitor.get_compilation_stats(),
        }
        print(json.dumps(output, indent=2))
    elif args.watch:
        monitor.watch_mode(args.interval)
    else:
        monitor.print_status()


if __name__ == "__main__":
    main()
