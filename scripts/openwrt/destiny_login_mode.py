"""Destiny login mode — deprecated wrapper around apply_overrides.py.

Prefer:
  py -3 scripts/openwrt/apply_overrides.py --mode login
  py -3 scripts/openwrt/apply_overrides.py --mode login --full
  py -3 scripts/openwrt/apply_overrides.py --mode normal
  py -3 scripts/openwrt/apply_overrides.py --mode status
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APPLY_OVERRIDES = Path(__file__).resolve().parent / "apply_overrides.py"


def main() -> int:
    parser = argparse.ArgumentParser(description="Deprecated: use apply_overrides.py")
    parser.add_argument("mode", choices=("login", "normal", "status"))
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--tunnel", choices=("awg1", "awg2"), default=None)
    args = parser.parse_args()

    cmd = [sys.executable, str(APPLY_OVERRIDES), "--mode", args.mode]
    if args.full:
        cmd.append("--full")
    if args.tunnel:
        cmd.extend(["--tunnel", args.tunnel])

    print("NOTE: destiny_login_mode.py is deprecated; use apply_overrides.py directly.")
    return subprocess.call(cmd, cwd=str(ROOT))


if __name__ == "__main__":
    raise SystemExit(main())
