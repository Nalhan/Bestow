# Stat-weight acquisition and buff valuation

Status: Implemented baseline
Source inspected: `https://coa.bisbeard.com/`  
Initial inspection date: 2026-07-23

## Purpose

Bestow should rank mutually exclusive buffs from their expected value to the
recipient, not from a hand-authored category order alone. The calculation uses:

1. the recipient specialization's stat weights;
2. the exact stats granted by the provider's known spell rank and verified
   talent modifiers;
3. explicit adjustments for survivability, utility, or effects that ordinary
   item stat weights do not represent well.

The website is a build-time data source only. The WoW addon must never contact
BisBeard at runtime.

## BisBeard source discovery

BisBeard currently ships its CoA defaults in a public, content-hashed
JavaScript module named:

```text
https://coa.bisbeard.com/assets/specRoles-<hash>.js
```

The hash changes when the site deploys. Never permanently depend on the
observed filename.

Refresh procedure:

1. Download `https://coa.bisbeard.com/`.
2. Search the returned HTML and referenced first-party entry bundle for:

   ```regex
   assets/specRoles-[A-Za-z0-9_-]+\.js
   ```

3. Resolve the match against `https://coa.bisbeard.com/`.
4. Download the module to a temporary `.mjs` file.
5. Record:
   - retrieval time in UTC;
   - resolved source URL;
   - SHA-256 of the downloaded module.
6. Dynamically import the local module in an offline extraction script.
7. Inspect its exports rather than relying on minified variable or export
   names. Select the exported object for which:
   - keys have the form `Class|Spec`;
   - values contain `role`, `anchors`, `anchorWeights`, and `weights`;
   - the expected CoA dataset currently contains 70 entries.
8. Export the selected records to stable Lua/JSON/CSV owned by Bestow.

The current bundle also exports the site's supported-stat list. The importer
records that list in source metadata and preserves supported optional fields
such as `mp5` in the review CSV even when all default profiles omit a value.

Bestow automates these steps with:

```text
node scripts/extract_bisbeard_weights.mjs
```

The command generates:

- `Data/StatWeights.lua`, the 70-profile runtime snapshot keyed by spec ID;
- `docs/bisbeard_stat_weights.csv`, the review/edit interchange table;
- `docs/bisbeard_stat_weights_source.json`, the resolved URLs, retrieval time,
  profile count, and SHA-256.

If dynamic import stops working, a parser may extract the same object from the
module text, but this is a fallback because minified local variable names are
not a stable contract.

## Current record shape

A BisBeard record currently resembles:

```js
"Guardian|Gladiator": {
  role: "melee",
  anchors: ["attackPower"],
  anchorWeights: {
    attackPower: 1
  },
  weights: {
    strength: 2.464,
    agility: 0.592,
    attackPower: 1,
    critRating: 0.764,
    hasteRating: 0.6
  }
}
```

Weights are relative values within a specialization. They are not buff scores
and must not be copied directly into the assignment solver.

## Validation and aliases

Every refresh must fail visibly rather than silently changing defaults when:

- the profile count is not 70;
- a Bestow spec is unmatched;
- two source profiles map to one Bestow spec;
- a required weight is not numeric;
- a source profile has no normalization anchor;
- an unexpected class/spec rename is found.

Known source-to-Bestow aliases:

| BisBeard | Bestow |
|---|---|
| `Bloodmage` | `Blood Mage` / `SONOFARUGAL` |
| `Tinker` | `Tinkerer` / `TINKER` |
| `Venomancer|Rotweaver` | `Venomancer|Rot` / spec ID `54` |

After aliases are applied, join source data to Bestow by numeric spec ID in
the generated artifact. Runtime code must use spec ID, not display text, as
the primary identity.

Generate a review report containing:

- added, removed, and renamed profiles;
- every changed stat weight;
- changes to roles or anchors;
- unmatched source and Bestow records;
- the previous and new source hashes.

Do not overwrite bundled production weights until this report has been
reviewed.

## Spell-effect magnitude data

Each spell family/rank must describe the actual benefit it grants. Provider
priority tiers are insufficient for numeric valuation.

Recommended shape:

```lua
effect = {
  kind = "stats",
  stats = {
    strength = 72,
  },
}
```

Multi-stat effects list every component:

```lua
effect = {
  kind = "stats",
  stats = {
    strength = 24,
    agility = 24,
    stamina = 24,
    intellect = 24,
    spirit = 24,
  },
}
```

Mark-style `Stats + Armor` effects store both components independently. A
tooltip such as “all primary stats by 12 and armor by 285” realizes a delta of
12 Strength, Agility, Stamina, Intellect, and Spirit, plus 285 Armor. Each
applicable stat delta uses the recipient's corresponding stat weight. Armor
has no invented BisBeard weight; it contributes only through a documented
spec/category survivability adjustment.

Percentage effects must not be represented as invented flat values:

```lua
effect = {
  kind = "percentStats",
  percent = 0.10,
  stats = {"strength", "agility", "stamina", "intellect", "spirit"},
}
```

Their realized deltas are calculated from the recipient's applicable
pre-buff/base stats when those values are available. Until they are available,
use an explicitly versioned reference-stat profile and mark the result as
estimated.

Store effect data per castable rank when ranks differ. Single and Greater
forms share effect data when they are functionally identical. Talent changes
are represented as modifiers applied to the base effect:

```lua
talentModifiers = {
  guardianHonor = {
    multiplier = 1.15,
  },
}
```

Tooltip-derived values must be verified in game. Record the spell ID, rank,
unmodified magnitude, talent assumptions, and verification status.

### Catalog tooltip dump

Run `/bestow tooltips` out of combat. Bestow queries every configured spell ID
through the 3.3.5 client tooltip API and opens a selected, copyable TSV. Save
that text as UTF-8 and generate the review artifacts with:

```text
python scripts/extract_buff_effects.py --tooltip-tsv <path>
```

The script writes:

- `docs/buff_spell_tooltips.csv`, preserving the raw tooltip evidence;
- `docs/buff_effect_values.csv`, containing parsed measurable components and
  explicit review status;
- `Data/Effects.lua`, the generated spell-ID-to-effect table consumed by the
  addon.

Rows that cannot be parsed remain `needs_review`; no value may be inferred
merely from a family name or curated provider tier.

## Utility calculation

For recipient spec `s` and a resolved family/rank `f`, first determine every
realized stat delta:

```text
baseUtility(s, f) =
  sum over stats x (
    realizedDelta(f, x) * statWeight(s, x)
  )
```

Bestow normalizes the measurable tooltip-derived value:

```text
baseScore(s, f) =
  round(100 * baseUtility(s, f) / maxUtility(s))
```

Finally, it applies an explicit family- or spell-level point adjustment:

```text
score(s, f) =
  clamp(baseScore(s, f) + bonusPoints(s, f), 0, 100)
```

`Data/BonusPoints.lua` owns these adjustments. Every special-effect family
has an explicit `bonusPoints` field. It may define a common value and numeric
spec-ID overrides; exact spell-ID entries can override the family value.
Unreviewed entries default to zero. The reviewed stock adjustment is currently
`10` for every Stamina family and `20` for every resource-cost-reduction
family.

Examples of adjustments:

- tanks may receive a Stamina multiplier greater than `1.0`;
- non-tanks may receive a smaller Stamina bonus so survivability is useful
  without outranking primary throughput;
- MP5 receives a player-configured linear weight because BisBeard exposes the
  field without a recommended default;
- resource-cost reduction, Armor, and resistance components may receive
  explicit curated per-spec utility adjustments when ordinary item stat
  weights do not price them;
- resistance or secondary utility may use a documented bonus when no
  compatible BisBeard weight exists.

Adjustments are data, keyed by spec ID and family/spell. They must never be hidden
inside solver code.

Special components are itemized independently in `Data/Effects.lua`. MP5's
linear contribution comes from the recipient's configured weight. For example,
Devotion of Grace combines that MP5 contribution with any separately curated
resource-cost-reduction adjustment. A versioned per-spec/family synergy bonus
may be added only when testing shows that the combination is materially
non-linear. Its default is zero, and every non-zero value requires a review
note.

## Conversion to Bestow's 0–100 scale

Raw BisBeard weights are anchor-relative. Bestow exposes a normalized score:

```text
baseScore(s, f) =
  round(100 * baseUtility(s, f) / maxUtility(s))

score(s, f) =
  clamp(baseScore(s, f) + bonusPoints(s, f), 0, 100)
```

`maxUtility(s)` is the greatest base utility among the tracked,
reference-rank buff families evaluated for that spec. Clamp the result to
`0..100`.

Keep the following values in generated data for auditing:

- source stat weights;
- realized/reference stat deltas;
- base utility;
- bonus points;
- normalized score.

Provider effectiveness is recipient-dependent after this change. A family is
not globally stronger merely because its class previously occupied a higher
curated tier.

## Assignment threshold

The individual-buff threshold applies to incremental normalized value, not
merely the destination buff's absolute score:

```text
individualGain =
  score(recipient, proposedIndividual)
  - score(recipient, providerGreaterDefault)
```

Create an automatic individual assignment only when:

```text
individualGain >= individualAssignmentThreshold
```

The initial threshold remains `25`. Missing coverage still outranks refreshing
existing coverage. Manual assignments may intentionally bypass the automatic
gain threshold.

When active equivalent coverage exists, compare the proposed assignment to
the best observed coverage and suppress the cast unless it produces a
positive, threshold-qualified improvement.

## Update cadence

BisBeard extraction is a maintainer operation, not an addon startup task.
Refresh it:

- before a tagged Bestow release;
- after BisBeard announces stat-weight corrections;
- after CoA balance or spell-rank changes;
- when validation detects new class/spec metadata.

The source is public application data, not a documented API. Extraction
failures must leave the last reviewed snapshot intact.

## Runtime implementation notes

`Data/Scoring.lua` computes both the raw and normalized values. Flat primary
stats, Attack Power, Spell Power, Armor, flat All Stats, and percentage All
Stats are currently measurable. Generic Attack Power uses the greater of the
melee/ranged Attack Power weights so hybrid profiles are not double-counted;
Spell Power does the same across spell-damage and healing aliases.

Percentage All Stats uses the recipient unit's base stats when the client
exposes them. A documented 100-per-primary-stat reference profile is used when
unit data is unavailable, and diagnostics marks that result as estimated.

MP5 is exposed as a supplemental stat weight because BisBeard lists the
field but currently omits it from every default CoA profile. Its default is
zero, and a configured value contributes `manaPer5 * mp5Weight` to raw utility.
Separately, MP5 buff families receive 10 stock bonus points for every
specialization of the mana-using classes listed in `Data/BonusPoints.lua`.
This class bonus is editable per family. A spell with both MP5 and cost
reduction, such as Devotion of Grace, combines the component adjustments.
Any spell rank containing a specific resistance or all-resistances effect
receives another `2` stock bonus points, derived directly from its structured
effect fields.
Resource-cost reduction, resistance, and other effects without a compatible
weight remain represented in the effect table and are valued through
`Data/BonusPoints.lua`. Until a non-zero weight or bonus is configured, the
legacy spec preference is retained as a safe assignment fallback.

The in-game Bestow options include a child `Stat Weights` panel for the
player's current specialization. It displays the bundled BisBeard value beside
each editable effective value. SavedVariables store only deviations under
`statWeightOverrides[specID]`; matching the bundled value removes the override.
Edited rows are orange and expose both per-row Reset and Reset All controls.
Changing or resetting a value invalidates normalized-score caches and rebuilds
assignments immediately.

The same options page includes a `Buff Scores` view. It displays the current
specialization's single and Greater results as `base + bonus = final` for every
family in the selected category. Hovering a family displays the spell tooltip
for its highest known Greater rank, or its highest Single rank when no Greater
form exists. The editable bonus field is prepopulated from the stock
family/spell adjustment. SavedVariables store only per-spec,
per-family deviations under `bonusPointOverrides[specID]`; matching or
resetting to stock removes the override. Bonus deltas and reset tombstones are
advertised with the recipient's group state.

In a group, each Bestow user advertises only the overrides for their current
specialization. The compact `W` message contains the specialization ID, the
first eight hexadecimal characters of the bundled-source SHA-256, a local
revision, an Adler-32 checksum, a fixed-order stat bitmask, and four-decimal
scaled base-36 override values. A zero mask is an explicit reset tombstone. Receivers
apply valid overrides only when scoring buffs for the sending player; they do
not apply one player's settings to other characters with the same
specialization. Missing or incompatible advertisements fall back to the local
bundled BisBeard profile.
