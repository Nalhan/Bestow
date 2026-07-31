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
CORE = ROOT / "Core.lua"
PACKAGE_JSON = ROOT / "package.json"
STAT_WEIGHTS = ROOT / "Data" / "StatWeights.lua"
STAT_WEIGHTS_CSV = ROOT / "docs" / "bisbeard_stat_weights.csv"
STAT_SOURCE = ROOT / "docs" / "bisbeard_stat_weights_source.json"
BONUS_POINTS = ROOT / "Data" / "BonusPoints.lua"
CATALOG = ROOT / "Data" / "Catalog.lua"
EFFECTS = ROOT / "Data" / "Effects.lua"
BUFF_EFFECT_VALUES = ROOT / "docs" / "buff_effect_values.csv"


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
    version = metadata["Version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        fail(f"TOC Version is not release-shaped: {version}")
    core_text = CORE.read_text(encoding="utf-8")
    core_version = re.search(
        r'^CBC\.version\s*=\s*"([^"]+)"$', core_text, re.MULTILINE
    )
    if not core_version or core_version.group(1) != version:
        fail("Core.lua and Bestow.toc versions do not match")
    package_metadata = json.loads(PACKAGE_JSON.read_text(encoding="utf-8"))
    if package_metadata.get("version") != version:
        fail("package.json and Bestow.toc versions do not match")

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

    # Perform Lua syntax & structural linting on all loaded Lua files
    from check_lua import check_file
    failed_syntax = [path for path in sorted(referenced_lua) if not check_file(ROOT / path)]
    if failed_syntax:
        fail("Lua syntax linting failed on: " + ", ".join(failed_syntax))

    import subprocess
    import shutil
    luacheck_bin = shutil.which("luacheck") or shutil.which("luacheck.cmd") or "luacheck"
    try:
        proc = subprocess.run([luacheck_bin, "."], cwd=ROOT, capture_output=True, text=True)
        if proc.stdout and proc.stdout.strip():
            print("--- Luacheck Report ---")
            print(proc.stdout.strip())
            print("-----------------------")
        if proc.returncode != 0 and "0 errors" not in proc.stdout:
            fail(f"Luacheck found errors:\n{proc.stdout}")
    except Exception as exc:
        print(f"Luacheck execution skipped: {exc}")

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
        reader = csv.DictReader(handle)
        csv_rows = list(reader)
        csv_fields = set(reader.fieldnames or [])
    if len(csv_rows) != 70 or {int(row["spec_id"]) for row in csv_rows} != {int(value) for value in profile_ids}:
        fail("BisBeard CSV profiles do not match Data/StatWeights.lua")
    if "mp5" not in csv_fields:
        fail("BisBeard CSV must preserve the source-supported mp5 field")
    source = json.loads(STAT_SOURCE.read_text(encoding="utf-8"))
    if source.get("profileCount") != 70 or not re.fullmatch(r"[0-9a-f]{64}", source.get("sha256", "")):
        fail("BisBeard source metadata is invalid")
    if source["sha256"] not in stat_text or source.get("moduleURL", "") not in stat_text:
        fail("BisBeard source metadata does not match Data/StatWeights.lua")
    if "mp5" not in source.get("availableStats", []):
        fail("BisBeard source metadata does not declare source-supported mp5")

    bonus_text = BONUS_POINTS.read_text(encoding="utf-8")
    mana_block = re.search(
        r"CBC\.ManaUserClasses\s*=\s*\{(.*?)^\}",
        bonus_text,
        re.MULTILINE | re.DOTALL,
    )
    mana_classes = set(
        re.findall(r"^\s*([A-Z]+)\s*=\s*true", mana_block.group(1) if mana_block else "", re.MULTILINE)
    )
    expected_mana_classes = {
        "NECROMANCER", "PYROMANCER", "CULTIST", "STARCALLER", "SUNCLERIC",
        "TINKER", "SPIRITMAGE", "WILDWALKER", "PROPHET", "CHRONOMANCER",
        "STORMBRINGER", "WITCHDOCTOR", "WITCHHUNTER",
    }
    if mana_classes != expected_mana_classes:
        fail("Mana-user class defaults do not match the reviewed class list")
    for family in (
        "enduringShout", "foulMandate", "riteOfResolve",
        "markOfRivendare", "sanguinaryOffering",
    ):
        if not re.search(
            rf"^\s*{family}\s*=\s*\{{[^}}]*bonusPoints\s*=\s*10[^}}]*\}}",
            bonus_text,
            re.MULTILINE,
        ):
            fail(f"Stamina family {family} must grant 10 stock bonus points")
    for family in ("etchingOfTheMagi", "resourcefulWuju", "markOfZeliek"):
        if not re.search(
            rf"^\s*{family}\s*=\s*\{{[^}}]*bonusPoints\s*=\s*20[^}}]*\}}",
            bonus_text,
            re.MULTILINE,
        ):
            fail(f"Cost-reduction family {family} must grant 20 stock bonus points")
    for family in (
        "whispersOfYshaarj", "groveInstinct", "sealOfAlar",
        "callOfTheWind", "manaModule",
    ):
        if not re.search(
            rf"^\s*{family}\s*=\s*\{{[^}}]*manaUserBonusPoints\s*=\s*10[^}}]*\}}",
            bonus_text,
            re.MULTILINE,
        ):
            fail(f"MP5 family {family} must grant mana-user classes 10 stock bonus points")
    if not re.search(
        r"^\s*devotionOfGrace\s*=\s*\{[^}]*bonusPoints\s*=\s*20[^}]*manaUserBonusPoints\s*=\s*30[^}]*\}",
        bonus_text,
        re.MULTILINE,
    ):
        fail("Devotion of Grace must combine 20 cost-reduction and 10 MP5 bonus points")
    if not re.search(
        r"CBC\.ResistanceEffectBonusPoints\s*=\s*2\b",
        bonus_text,
    ):
        fail("Resistance-bearing buff ranks must receive 2 additional stock bonus points")

    catalog_text = CATALOG.read_text(encoding="utf-8")
    effects_text = EFFECTS.read_text(encoding="utf-8")
    removed_unattainable_ids = {
        300924, 523484, 561143, 561391, 572816, 575044, 707340, 707677,
        707678, 802830, 802831, 802832, 802833, 802834, 803664,
    }
    for spell_id in removed_unattainable_ids:
        pattern = rf"\b{spell_id}\b"
        if re.search(pattern, catalog_text) or re.search(pattern, effects_text):
            fail(f"Removed unattainable spell ID {spell_id} returned to runtime data")

    with BUFF_EFFECT_VALUES.open(encoding="utf-8-sig", newline="") as handle:
        effect_rows = list(csv.DictReader(handle))
    from extract_buff_effects import parse_catalog
    catalog_mappings = {
        (
            spell.category, spell.family, spell.form,
            spell.rank_index, spell.spell_id,
        )
        for spell in parse_catalog(catalog_text)
    }
    effect_mappings = {
        (
            row["category"], row["family"], row["form"],
            int(row["rank_index"]), int(row["spell_id"]),
        )
        for row in effect_rows
    }
    if effect_mappings != catalog_mappings:
        fail("Generated buff-effect review rows do not match Data/Catalog.lua")
    effect_ids = {
        int(value)
        for value in re.findall(r"^\s*\[(\d+)\]\s*=", effects_text, re.MULTILINE)
    }
    reviewed_effect_ids = {int(row["spell_id"]) for row in effect_rows}
    if effect_ids != reviewed_effect_ids:
        fail("Data/Effects.lua IDs do not match the generated buff-effect review")
    if any(
        row["category"] == "spirit" and row["family"] == "toxicPheromones"
        for row in effect_rows
    ):
        fail("Toxic Pheromones must be categorized only as Spell Power")
    if any(
        row["category"] == "attackPower" and row["family"] == "beetlePheromones"
        for row in effect_rows
    ):
        fail("Beetle Pheromones must be categorized only as Stats + Armor")

    measurable_fields = (
        "strength", "agility", "stamina", "intellect", "spirit",
        "attack_power", "spell_power", "armor", "all_stats_flat",
        "all_stats_percent", "mana_per_5", "resource_cost_reduction_percent",
        "arcane_resistance", "fire_resistance", "frost_resistance",
        "nature_resistance", "shadow_resistance", "all_resistances",
    )
    effect_groups: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in effect_rows:
        effect_groups.setdefault((row["category"], row["family"]), []).append(row)
    for (category, family), rows in effect_groups.items():
        greater_rows = [row for row in rows if row["form"] == "greater"]
        if not greater_rows:
            continue
        greater_max = {
            field: max(float(row[field] or 0) for row in greater_rows)
            for field in measurable_fields
        }
        for row in (candidate for candidate in rows if candidate["form"] == "single"):
            for field in measurable_fields:
                single_value = float(row[field] or 0)
                if single_value > greater_max[field]:
                    fail(
                        f"{category}/{family} Single spell {row['spell_id']} has "
                        f"{field}={single_value:g}, above Greater={greater_max[field]:g}"
                    )

    print(
        f"Bestow validation passed: {len(runtime_entries)} TOC entries, "
        f"{len(referenced_lua)} Lua files, {len(profile_ids)} stat-weight profiles"
    )


if __name__ == "__main__":
    main()
