# Changelog

## 0.3.0-alpha

### Recipient-owned scoring

- Synchronize each player's current-spec stat-weight overrides through compact,
  checksummed addon messages.
- Apply advertised weights only when scoring buffs for that player, with safe
  fallback to bundled defaults for missing or incompatible advertisements.
- Add `mp5` as a configurable, zero-default stat weight.
- Add a Buff Scores options view with live Single/Greater formulas, highest-rank
  spell tooltips, and synchronized per-family bonus-point overrides.

### Scoring data

- Refresh all 70 BisBeard profiles from the July 31 source snapshot.
- Add stock bonuses of 10 for Stamina, 20 for resource-cost reduction, and 10
  for pure MP5 buffs on mana-using classes.
- Add 2 additional points to spell ranks carrying a resistance effect.
- Remove 15 unattainable spell ranks found by the Single-versus-Greater audit.
- Classify Toxic Pheromones only as Spell Power and Beetle Pheromones only as
  Stats + Armor.

### Interface and tooling

- Add configurable compact-panel scale and width, group-buff indicators,
  improved icon framing, and direct configuration access.
- Expand diagnostics and the alpha test plan for synchronized valuation.
- Harden generated-data validation and deterministic release packaging.
