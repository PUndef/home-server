"""Single entrypoint for local helper scripts in this repository.

Usage:
  python start.py
  python start.py list
  python start.py run <script-name> [script-args...]
  python start.py <script-name> [script-args...]
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent


@dataclass(frozen=True)
class ScriptSpec:
    name: str
    relative_path: str
    description: str
    usage: str
    example: str

    @property
    def path(self) -> Path:
        return ROOT / self.relative_path


SCRIPTS = [
    ScriptSpec(
        name="check_stack",
        relative_path="scripts/openwrt/check_stack.py",
        description="OpenWrt routing stack health check via SSH.",
        usage="python start.py check_stack",
        example="python start.py check_stack",
    ),
    ScriptSpec(
        name="openwrt_exec",
        relative_path="scripts/openwrt/openwrt_exec.py",
        description="Run an arbitrary command on OpenWrt over SSH.",
        usage="python start.py openwrt_exec \"<command>\"",
        example="python start.py openwrt_exec \"uci show pbr | head\"",
    ),
    ScriptSpec(
        name="trace_traffic",
        relative_path="scripts/openwrt/trace_traffic.py",
        description="Trace traffic path through pbr/podkop/zapret.",
        usage="python start.py trace_traffic <domain-or-ip> [domain-or-ip...]",
        example="python start.py trace_traffic gitlab.kpb.lt api.openai.com",
    ),
]

SCRIPTS_BY_NAME = {item.name: item for item in SCRIPTS}


def print_scripts() -> None:
    print("Available scripts:")
    for item in SCRIPTS:
        print(f"- {item.name}")
        print(f"  File: {item.relative_path}")
        print(f"  Description: {item.description}")
        print(f"  Usage: {item.usage}")
        print(f"  Example: {item.example}")


def run_script(name: str, args: list[str]) -> int:
    item = SCRIPTS_BY_NAME.get(name)
    if item is None:
        print(f"Unknown script: {name}")
        print("Hint: python start.py list")
        return 2

    if not item.path.exists():
        print(f"File not found: {item.path}")
        return 2

    cmd = [sys.executable, str(item.path), *args]
    print(f"Running: {' '.join(cmd)}")
    return subprocess.call(cmd, cwd=ROOT)


def run_interactive_menu() -> int:
    print_scripts()
    print("\nType a script name to run (or Enter to exit):")
    selected = input("> ").strip()
    if not selected:
        return 0

    item = SCRIPTS_BY_NAME.get(selected)
    if item is None:
        print(f"Unknown script: {selected}")
        return 2

    print("Type arguments in one line (or Enter for none):")
    arg_line = input("> ").strip()
    args = arg_line.split() if arg_line else []
    return run_script(selected, args)


def main() -> int:
    if len(sys.argv) == 1:
        return run_interactive_menu()

    command = sys.argv[1]
    rest = sys.argv[2:]

    if command in {"list", "--list"}:
        print_scripts()
        return 0

    if command == "run":
        if not rest:
            print("Usage: python start.py run <script-name> [script-args...]")
            return 2
        return run_script(rest[0], rest[1:])

    if command in {"help", "--help", "-h"}:
        print(__doc__)
        print()
        print_scripts()
        return 0

    return run_script(command, rest)


if __name__ == "__main__":
    raise SystemExit(main())
