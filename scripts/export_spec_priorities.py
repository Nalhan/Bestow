#!/usr/bin/env python3
"""Export provisional per-spec buff utility scores for collaborative review."""

from __future__ import annotations

import csv
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Data" / "Classes.lua"
OUTPUT = ROOT / "docs" / "spec_buff_priorities_baseline.csv"

CATEGORIES = [
    "strength",
    "stamina",
    "agility",
    "intellect",
    "spirit",
    "attack_power",
    "spell_power",
    "all_stats",
    "mana",
    "armor_stats",
]

STAT_CATEGORY = {
    "Strength": "strength",
    "Stamina": "stamina",
    "Agility": "agility",
    "Intellect": "intellect",
    "Spirit": "spirit",
}

ROLE_NAME = {
    "T": "Tank",
    "H": "Healer",
    "M": "Melee DPS",
    "D": "Damage",
}


def parse_specs(source: str) -> list[dict[str, object]]:
    class_pattern = re.compile(
        r'^\s*([A-Z]+)\s*=\s*\{name\s*=\s*"([^"]+)".*?specs\s*=\s*\{(.*?)\}\}\s*,?\s*$',
        re.MULTILINE | re.DOTALL,
    )
    spec_pattern = re.compile(r'\{(\d+),"([^"]+)","([DMHT])",\{([^}]*)\}\}')
    specs: list[dict[str, object]] = []

    for class_match in class_pattern.finditer(source):
        class_token, class_name, spec_block = class_match.groups()
        for spec_match in spec_pattern.finditer(spec_block):
            spec_id, spec_name, role_flag, raw_stats = spec_match.groups()
            stats = re.findall(r'"([^"]+)"', raw_stats)
            specs.append(
                {
                    "spec_id": int(spec_id),
                    "class_token": class_token,
                    "class_name": class_name,
                    "spec_name": spec_name,
                    "role": ROLE_NAME[role_flag],
                    "role_flag": role_flag,
                    "stats": stats,
                }
            )

    return sorted(specs, key=lambda spec: int(spec["spec_id"]))


def score_spec(spec: dict[str, object]) -> dict[str, int]:
    stats = list(spec["stats"])
    role = str(spec["role_flag"])
    scores = {category: 0 for category in CATEGORIES}

    # All Stats was explicitly established as universally top-tier.
    scores["all_stats"] = 100

    # Preserve the source stat ordering and avoid equal positive scores.
    for index, stat in enumerate(stats):
        scores[STAT_CATEGORY[stat]] = 95 - index

    physical = role == "M" or "Strength" in stats or "Agility" in stats
    magical = role == "H" or "Intellect" in stats or "Spirit" in stats

    if role == "T":
        scores["stamina"] = max(scores["stamina"], 98)
        scores["armor_stats"] = 92

    if physical:
        scores["attack_power"] = 90
    if magical:
        # Keep hybrid AP/SP scores distinct pending spec-by-spec review.
        scores["spell_power"] = 89 if physical else 90

    if role == "H":
        scores["mana"] = 93
        if scores["spirit"] == 0:
            scores["spirit"] = 45
    elif magical:
        scores["mana"] = 45

    if role != "T" and scores["stamina"] == 0:
        scores["stamina"] = 40
    if role != "T":
        scores["armor_stats"] = 10

    if "Spirit" in stats and scores["intellect"] == 0:
        scores["intellect"] = 44
    if "Intellect" in stats and role != "H" and scores["spirit"] == 0:
        scores["spirit"] = 15

    return scores


def main() -> None:
    specs = parse_specs(SOURCE.read_text(encoding="utf-8"))
    if len(specs) != 70:
        raise SystemExit(f"Expected 70 CoA specs, found {len(specs)}")

    fieldnames = [
        "spec_id",
        "class_token",
        "class_name",
        "spec_name",
        "role",
        "primary_stats",
        *CATEGORIES,
        "individual_assignment_threshold",
        "review_status",
        "notes",
    ]

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for spec in specs:
            row = {
                "spec_id": spec["spec_id"],
                "class_token": spec["class_token"],
                "class_name": spec["class_name"],
                "spec_name": spec["spec_name"],
                "role": spec["role"],
                "primary_stats": " / ".join(spec["stats"]),
                **score_spec(spec),
                "individual_assignment_threshold": 25,
                "review_status": "Needs review",
                "notes": "",
            }
            writer.writerow(row)

    print(f"Wrote {len(specs)} specs to {OUTPUT}")


if __name__ == "__main__":
    main()
