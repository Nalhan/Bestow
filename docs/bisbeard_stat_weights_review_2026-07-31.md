# BisBeard stat-weight refresh review — 2026-07-31

## Source

- Previous module: `specRoles-BPB3x4OJ.js`
- Previous SHA-256: `1daa6608eeb0d66efeb5340f57d6174f9fbf7ded91f36b967fce6cbabb1aee44`
- Current module: `specRoles-DwjsUehu.js`
- Current SHA-256: `d21bce8620eb34ca7871b8f876323ff79b9d03c6570aaf164a4c11163a0b4716`
- Profiles: 70 before and after
- Changed profiles: 13
- Changed weight fields: 42
- Added, removed, or renamed profiles: none
- Role changes: none

## MP5 source finding

The current BisBeard bundle exports `mp5` in its 42-field supported-stat list,
but none of the 70 CoA default profile `weights` objects supplies an MP5 value.
Bestow therefore preserves an empty `mp5` column in the source review CSV and
exposes MP5 as a supplemental configurable weight with a default of zero.

## Weight changes

| Spec ID | Profile | Changes |
|---:|---|---|
| 2 | Barbarian / Brutality | Agility `1.537 → 2.195` |
| 4 | Witch Doctor / Shadowhunting | Agility `2.037 → 2`; Armor Penetration `0.3 → 0`; Haste `0.6 → 0.5`; Intellect `1.194 → 1.2`; Spell Damage `0.75 → 0.2`; Spell Power `0.75 → 0.2`; Weapon DPS added at `0` |
| 5 | Witch Doctor / Voodoo | Spirit `0.625 → 1.504` |
| 7 | Felsworn / Infernal | Spirit `0.398 → 0.517` |
| 21 | Guardian / Vanguard | Agility `1.308 → 1`; Stamina `1.365 → 3`; Strength `2.354 → 2` |
| 28 | Ranger / Archery | Ranged DPS `14 → 0` |
| 29 | Ranger / Farstrider | Ranged DPS `14 → 0` |
| 36 | Necromancer / Rime | Crit `0.93 → 0.9`; Intellect `0.417 → 0.415` |
| 51 | Tinker / Invention | Ranged DPS added at `14` |
| 60 | Primalist / Mountain King | Agility `1.503 → 0.8`; Armor removed (`0.3`); Armor Penetration removed (`0.15`); Crit `0.35 → 0.5`; Defense `1.05 → 1.5`; Dodge `0.9 → 1.2`; Expertise `0.5 → 1.5`; Haste `0.35 → 1.5`; Hit `0.5 → 1.1`; Intellect removed (`0.065`); Parry `0.9 → 2`; Spell Damage removed (`1`); Spell Power `1 → 0.5`; Stamina `1.2 → 2`; Strength `2.548 → 4`; Weapon DPS `14 → 10` |
| 61 | Runemaster / Engravement | Armor Penetration `0.3 → 0`; Crit `0.641 → 0.2`; Ranged DPS added at `0` |
| 63 | Runemaster / Riftblade | Armor Penetration `0.3 → 0`; Crit `0.772 → 0.2`; Ranged DPS added at `0` |
| 95 | Primalist / Geomancy | Armor Penetration `0.5 → 0.6`; Intellect `0.397 → 1` |

## Bestow impact

- The generated runtime and CSV snapshots now use the current source.
- Existing user overrides remain stored by spec ID and stat key. They continue
  to override the refreshed default until reset.
- The changed source fingerprint intentionally causes clients on different
  snapshots to reject each other's stat-weight deltas and fall back to their
  own bundled defaults.
- MP5 contributes `effect.manaPer5 × configured mp5 weight` to raw utility.
  Its zero default preserves the prior fallback behavior until a player opts in.
