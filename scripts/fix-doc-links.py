#!/usr/bin/env python3
"""Remove outer backticks around markdown links with relative targets."""

from __future__ import annotations

import re
from pathlib import Path

PATTERN = re.compile(r"`(\[[^\]]+\]\((?:\.\./|\./)[^)]+\))`")


def main() -> int:
    root = Path(__file__).resolve().parents[1] / "docs"
    fixed = 0
    for path in root.rglob("*.md"):
        text = path.read_text(encoding="utf-8")
        updated = PATTERN.sub(r"\1", text)
        if updated != text:
            path.write_text(updated, encoding="utf-8")
            print(f"fixed {path.relative_to(root.parent)} ({len(PATTERN.findall(text))} links)")
            fixed += 1
    print(f"done: {fixed} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
