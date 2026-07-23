#!/usr/bin/env python3
"""Validate Bestow's TOC and release-facing repository structure."""

from __future__ import annotations

import re
import sys
import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "Bestow.toc"
STAT_WEIGHTS = ROOT / "Data" / "StatWeights.lua"
STAT_WEIGHTS_CSV = ROOT / "docs" / "bisbeard_stat_weights.csv"
STAT_SOURCE = ROOT / "docs" / "bisbeard_stat_weights_source.json"


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

    stat_text = STAT_WEIGHTS.read_text(encoding="utf-8")
    profile_ids = re.findall(r"^\s*\[(\d+)\]\s*=\s*\{$", stat_text, re.MULTILINE)
    if len(profile_ids) != 70 or len(set(profile_ids)) != 70:
        fail(f"Data/StatWeights.lua must contain 70 unique spec profiles, found {len(set(profile_ids))}")
    if not re.search(r'sha256="[0-9a-f]{64}"', stat_text):
        fail("Data/StatWeights.lua is missing valid source SHA-256 metadata")
    with STAT_WEIGHTS_CSV.open(encoding="utf-8", newline="") as handle:
        csv_rows = list(csv.DictReader(handle))
    if len(csv_rows) != 70 or {int(row["spec_id"]) for row in csv_rows} != {int(value) for value in profile_ids}:
        fail("BisBeard CSV profiles do not match Data/StatWeights.lua")
    source = json.loads(STAT_SOURCE.read_text(encoding="utf-8"))
    if source.get("profileCount") != 70 or not re.fullmatch(r"[0-9a-f]{64}", source.get("sha256", "")):
        fail("BisBeard source metadata is invalid")
    if source["sha256"] not in stat_text or source.get("moduleURL", "") not in stat_text:
        fail("BisBeard source metadata does not match Data/StatWeights.lua")

    print(
        f"Bestow validation passed: {len(runtime_entries)} TOC entries, "
        f"{len(referenced_lua)} Lua files, {len(profile_ids)} stat-weight profiles"
    )


if __name__ == "__main__":
    main()
