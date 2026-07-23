#!/usr/bin/env python3
"""Validate Bestow's TOC and release-facing repository structure."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "Bestow.toc"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if not TOC.is_file():
        fail("Bestow.toc is missing")

    text = TOC.read_text(encoding="utf-8")
    metadata: dict[str, str] = {}
    runtime_entries: list[str] = []

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("##"):
            match = re.match(r"^##\s*([^:]+):\s*(.*)$", line)
            if match:
                metadata[match.group(1).strip()] = match.group(2).strip()
            continue
        runtime_entries.append(line.replace("\\", "/"))

    if metadata.get("Interface") != "30300":
        fail("TOC Interface must be 30300")
    if metadata.get("Title") != "Bestow":
        fail("TOC Title must be Bestow")
    if not metadata.get("Version"):
        fail("TOC Version is missing")

    missing = [entry for entry in runtime_entries if not (ROOT / entry).is_file()]
    if missing:
        fail("TOC references missing files: " + ", ".join(missing))

    referenced_lua = {entry for entry in runtime_entries if entry.endswith(".lua")}
    runtime_lua = {
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*.lua")
        if ".git" not in path.parts
    }
    unreferenced = sorted(runtime_lua - referenced_lua)
    if unreferenced:
        fail("Lua files are not loaded by the TOC: " + ", ".join(unreferenced))

    forbidden = [ROOT / "WTF", ROOT / "Errors", ROOT / "Cache"]
    present = [path.name for path in forbidden if path.exists()]
    if present:
        fail("Client data must not be in the addon repository: " + ", ".join(present))

    print(
        f"Bestow validation passed: {len(runtime_entries)} TOC entries, "
        f"{len(referenced_lua)} Lua files"
    )


if __name__ == "__main__":
    main()
