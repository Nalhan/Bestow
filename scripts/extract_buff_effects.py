#!/usr/bin/env python3
"""Extract Bestow catalog tooltips and measurable effects from SpellDumper."""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Data" / "Catalog.lua"
RAW_OUTPUT = ROOT / "docs" / "buff_spell_tooltips.csv"
VALUE_OUTPUT = ROOT / "docs" / "buff_effect_values.csv"

VALUE_FIELDS = [
    "strength",
    "agility",
    "stamina",
    "intellect",
    "spirit",
    "attack_power",
    "spell_power",
    "armor",
    "all_stats_flat",
    "all_stats_percent",
    "mana_per_5",
    "resource_cost_reduction_percent",
    "arcane_resistance",
    "fire_resistance",
    "frost_resistance",
    "nature_resistance",
    "shadow_resistance",
]


@dataclass(frozen=True)
class CatalogSpell:
    category: str
    family: str
    provider: str
    form: str
    rank_index: int
    spell_id: int


def split_arguments(source: str) -> list[str]:
    arguments: list[str] = []
    start = 0
    depth = 0
    quote = False
    escaped = False
    for index, char in enumerate(source):
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = False
        elif char == '"':
            quote = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif char == "," and depth == 0:
            arguments.append(source[start:index].strip())
            start = index + 1
    arguments.append(source[start:].strip())
    return arguments


def parse_id_list(argument: str) -> list[int]:
    if argument == "nil":
        return []
    return [int(value) for value in re.findall(r"\d+", argument)]


def parse_catalog(source: str) -> list[CatalogSpell]:
    category = ""
    in_variants = False
    spells: list[CatalogSpell] = []
    for line in source.splitlines():
        category_match = re.match(r"^  ([A-Za-z]\w*) = \{$", line)
        if category_match:
            category = category_match.group(1)
            in_variants = False
            continue
        if category and re.match(r"^\s+variants=\{$", line):
            in_variants = True
            continue
        if not in_variants:
            continue
        family_match = re.match(r'^\s{6}([A-Za-z]\w*)=Family\((.*)\),$', line)
        if not family_match:
            if re.match(r"^    },$", line):
                in_variants = False
            continue
        family, raw_arguments = family_match.groups()
        arguments = split_arguments(raw_arguments)
        if len(arguments) < 5:
            raise ValueError(f"Could not parse catalog family: {line}")
        provider_match = re.fullmatch(r'"([^"]+)"', arguments[0])
        if not provider_match:
            continue
        provider = provider_match.group(1)
        for form, ids in (
            ("single", parse_id_list(arguments[3])),
            ("greater", parse_id_list(arguments[4])),
        ):
            for rank_index, spell_id in enumerate(ids, 1):
                spells.append(
                    CatalogSpell(
                        category=category,
                        family=family,
                        provider=provider,
                        form=form,
                        rank_index=rank_index,
                        spell_id=spell_id,
                    )
                )
    return spells


def lua_unescape(value: str) -> str:
    replacements = {
        "n": "\n",
        "r": "\r",
        "t": "\t",
        '"': '"',
        "\\": "\\",
    }
    output: list[str] = []
    index = 0
    while index < len(value):
        if value[index] == "\\" and index + 1 < len(value):
            escaped = value[index + 1]
            output.append(replacements.get(escaped, escaped))
            index += 2
        else:
            output.append(value[index])
            index += 1
    return "".join(output)


def parse_lua_fields(block: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for match in re.finditer(r'\["([^"]+)"\]\s*=\s*"((?:\\.|[^"])*)"', block):
        fields[match.group(1)] = lua_unescape(match.group(2))
    spell_match = re.search(r'\["spellID"\]\s*=\s*(\d+)', block)
    if spell_match:
        fields["spellID"] = spell_match.group(1)
    fields["isTrainer"] = str(
        bool(re.search(r'\["isTrainer"\]\s*=\s*true', block))
    ).lower()
    return fields


def parse_spell_dumper(source: str) -> dict[int, dict[str, str]]:
    entries: dict[int, dict[str, str]] = {}
    candidate: list[str] | None = None
    for line in source.splitlines():
        if line.strip() == "{":
            candidate = []
            continue
        if candidate is None:
            continue
        if re.match(r"^\s*\}, -- \[\d+\]\s*$", line):
            fields = parse_lua_fields("\n".join(candidate))
            if "spellID" in fields:
                spell_id = int(fields["spellID"])
                previous = entries.get(spell_id)
                score = (fields.get("isTrainer") == "true", len(fields.get("tooltipStr", "")))
                previous_score = (
                    previous is not None and previous.get("isTrainer") == "true",
                    len(previous.get("tooltipStr", "")) if previous else 0,
                )
                if previous is None or score > previous_score:
                    entries[spell_id] = fields
            candidate = None
            continue
        candidate.append(line)
    return entries


def parse_tooltip_tsv(path: Path) -> dict[int, dict[str, str]]:
    entries: dict[int, dict[str, str]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            raw_id = row.get("spellID", "")
            if not raw_id.isdigit():
                continue
            spell_id = int(raw_id)
            entry = {
                "spellID": raw_id,
                "name": row.get("resolvedName", ""),
                "tooltipStr": row.get("tooltip", ""),
                "isTrainer": "false",
            }
            previous = entries.get(spell_id)
            if previous is None or len(entry["tooltipStr"]) > len(
                previous.get("tooltipStr", "")
            ):
                entries[spell_id] = entry
    return entries


def clean_tooltip(value: str) -> str:
    value = re.sub(r"\|c[0-9A-Fa-f]{8}", "", value)
    value = value.replace("|r", "").replace("|n", " ")
    value = re.sub(r"\|T.*?\|t", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def number(pattern: str, text: str) -> str:
    match = re.search(pattern, text, re.IGNORECASE)
    return match.group(1).replace(",", "") if match else ""


def parse_values(tooltip: str) -> dict[str, str]:
    text = clean_tooltip(tooltip)
    values = {field: "" for field in VALUE_FIELDS}
    patterns = {
        "strength": r"\bstrength\s*(?:of [^.]+? )?by\s+([\d,]+)",
        "agility": r"\b(?:agility|agilty)\s*(?:of [^.]+? )?by\s+([\d,]+)",
        "stamina": r"\bstamina\s*(?:of [^.]+? )?by\s+([\d,]+)",
        "intellect": r"\bintellect\s*(?:of [^.]+? )?by\s+([\d,]+)",
        "spirit": r"\bspirit\s*(?:of [^.]+? )?by\s+([\d,]+)",
        "attack_power": r"\battack power\s+by\s+([\d,]+)",
        "spell_power": r"\bspell power\s+by\s+([\d,]+)",
        "armor": r"\barmor\s+by\s+([\d,]+)",
        "mana_per_5": r"([\d,]+)\s+mana\s+(?:every|per)\s+5\s+sec",
        "resource_cost_reduction_percent": (
            r"\breduc(?:e|es|ing)\s+(?:their |the target'?s )?resource costs?"
            r"\s+by\s+([\d,]+)%"
        ),
        "arcane_resistance": r"\barcane resistance\s+by\s+([\d,]+)",
        "fire_resistance": r"\bfire resistance\s+by\s+([\d,]+)",
        "frost_resistance": r"\bfrost resistance\s+by\s+([\d,]+)",
        "nature_resistance": r"\bnature resistance\s+by\s+([\d,]+)",
        "shadow_resistance": r"\bshadow resistance\s+by\s+([\d,]+)",
    }
    for field, pattern in patterns.items():
        values[field] = number(pattern, text)

    all_stats = re.search(
        r"\b(?:all (?:primary )?|total )stats\s+by\s+([\d,]+)(%)?",
        text,
        re.IGNORECASE,
    )
    if all_stats:
        field = "all_stats_percent" if all_stats.group(2) else "all_stats_flat"
        values[field] = all_stats.group(1).replace(",", "")
    else:
        listed_stats = re.search(
            r"\bstrength,\s*agility,\s*stamina,\s*intellect(?:,| and)"
            r"\s*spirit\s+by\s+([\d,]+)(%)?",
            text,
            re.IGNORECASE,
        )
        if listed_stats:
            field = "all_stats_percent" if listed_stats.group(2) else "all_stats_flat"
            values[field] = listed_stats.group(1).replace(",", "")

    return values


def effect_summary(values: dict[str, str]) -> str:
    labels = {
        "strength": "Strength",
        "agility": "Agility",
        "stamina": "Stamina",
        "intellect": "Intellect",
        "spirit": "Spirit",
        "attack_power": "AP",
        "spell_power": "SP",
        "armor": "Armor",
        "all_stats_flat": "All Stats",
        "all_stats_percent": "All Stats",
        "mana_per_5": "MP5",
        "resource_cost_reduction_percent": "Resource Cost",
        "arcane_resistance": "Arcane Resist",
        "fire_resistance": "Fire Resist",
        "frost_resistance": "Frost Resist",
        "nature_resistance": "Nature Resist",
        "shadow_resistance": "Shadow Resist",
    }
    parts = []
    for field in VALUE_FIELDS:
        if values[field]:
            suffix = "%" if field in {
                "all_stats_percent",
                "resource_cost_reduction_percent",
            } else ""
            parts.append(f"{labels[field]} {values[field]}{suffix}")
    return "; ".join(parts)


def locate_saved_variables(explicit: Path | None) -> Path:
    if explicit:
        return explicit.resolve()
    client = ROOT.parents[2]
    candidates = list(client.glob("WTF/Account/*/SavedVariables/SpellDumper.lua"))
    if not candidates:
        raise FileNotFoundError("No SpellDumper.lua found under WTF/Account")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def write_tables(
    catalog_spells: list[CatalogSpell],
    dump_entries: dict[int, dict[str, str]],
    dump_source: str,
) -> tuple[int, int]:
    raw_fields = [
        "category",
        "family",
        "provider",
        "form",
        "rank_index",
        "spell_id",
        "resolved_name",
        "tooltip",
        "dump_source",
    ]
    value_fields = [
        "category",
        "family",
        "provider",
        "form",
        "rank_index",
        "spell_id",
        "resolved_name",
        *VALUE_FIELDS,
        "effect_summary",
        "parse_status",
        "verification_status",
        "notes",
    ]
    found = 0
    parsed = 0
    with RAW_OUTPUT.open("w", encoding="utf-8-sig", newline="") as raw_handle, (
        VALUE_OUTPUT.open("w", encoding="utf-8-sig", newline="")
    ) as value_handle:
        raw_writer = csv.DictWriter(raw_handle, fieldnames=raw_fields)
        value_writer = csv.DictWriter(value_handle, fieldnames=value_fields)
        raw_writer.writeheader()
        value_writer.writeheader()
        for spell in catalog_spells:
            entry = dump_entries.get(spell.spell_id, {})
            tooltip = clean_tooltip(entry.get("tooltipStr", ""))
            name = entry.get("name", "")
            if entry:
                found += 1
            values = parse_values(tooltip)
            summary = effect_summary(values)
            if summary:
                parsed += 1
            raw_writer.writerow(
                {
                    **spell.__dict__,
                    "resolved_name": name,
                    "tooltip": tooltip,
                    "dump_source": dump_source if entry else "",
                }
            )
            value_writer.writerow(
                {
                    **spell.__dict__,
                    "resolved_name": name,
                    **values,
                    "effect_summary": summary,
                    "parse_status": (
                        "parsed" if summary else ("needs_review" if entry else "missing_tooltip")
                    ),
                    "verification_status": "tooltip_unverified" if entry else "missing",
                    "notes": "",
                }
            )
    return found, parsed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--saved-variables",
        type=Path,
        help="Path to WTF/Account/<account>/SavedVariables/SpellDumper.lua",
    )
    parser.add_argument(
        "--tooltip-tsv",
        type=Path,
        help="TSV copied from Bestow's /bestow tooltips window",
    )
    args = parser.parse_args()

    catalog_spells = parse_catalog(CATALOG.read_text(encoding="utf-8"))
    if args.tooltip_tsv:
        source_path = args.tooltip_tsv.resolve()
        dump_entries = parse_tooltip_tsv(source_path)
    else:
        source_path = locate_saved_variables(args.saved_variables)
        dump_entries = parse_spell_dumper(
            source_path.read_text(encoding="utf-8", errors="replace")
        )
    found, parsed = write_tables(catalog_spells, dump_entries, source_path.name)
    total = len(catalog_spells)
    unique_ids = len({spell.spell_id for spell in catalog_spells})
    print(f"Catalog mappings: {total}")
    print(f"Unique curated spell IDs: {unique_ids}")
    print(f"Tooltips found: {found}/{total}")
    print(f"Measurable effects parsed: {parsed}/{total}")
    print(f"Wrote {RAW_OUTPUT}")
    print(f"Wrote {VALUE_OUTPUT}")


if __name__ == "__main__":
    main()
