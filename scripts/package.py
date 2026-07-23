#!/usr/bin/env python3
"""Build a deterministic Bestow release ZIP."""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADDON_NAME = "Bestow"
RUNTIME_DIRS = ("Data", "Libs", "UI")
RUNTIME_FILES = (
    "Bestow.toc",
    "Core.lua",
    "Spellbook.lua",
    "Roster.lua",
    "Auras.lua",
    "Assignments.lua",
    "Comms.lua",
    "README.md",
    "LICENSE",
)


def replace_version(toc: Path, version: str) -> None:
    text = toc.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"^## Version:.*$", f"## Version: {version}", text, count=1, flags=re.MULTILINE
    )
    if count != 1:
        raise RuntimeError("Bestow.toc has no unique Version metadata line")
    toc.write_text(updated, encoding="utf-8", newline="\n")


def build(version: str) -> tuple[Path, Path]:
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    archive = output / f"{ADDON_NAME}-{version}.zip"
    checksum = archive.with_suffix(archive.suffix + ".sha256")

    with tempfile.TemporaryDirectory(prefix="bestow-release-") as temporary:
        staged = Path(temporary) / ADDON_NAME
        staged.mkdir()

        for name in RUNTIME_FILES:
            shutil.copy2(ROOT / name, staged / name)
        for name in RUNTIME_DIRS:
            shutil.copytree(ROOT / name, staged / name)

        replace_version(staged / "Bestow.toc", version)

        with zipfile.ZipFile(
            archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as bundle:
            for path in sorted(staged.rglob("*")):
                if path.is_file():
                    arcname = path.relative_to(staged.parent).as_posix()
                    info = zipfile.ZipInfo(arcname, date_time=(2020, 1, 1, 0, 0, 0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = 0o644 << 16
                    bundle.writestr(info, path.read_bytes(), compresslevel=9)

    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum.write_text(f"{digest}  {archive.name}\n", encoding="ascii", newline="\n")
    return archive, checksum


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    arguments = parser.parse_args()
    archive, checksum = build(arguments.version)
    print(archive)
    print(checksum)


if __name__ == "__main__":
    main()
