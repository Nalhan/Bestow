# Stat-weight acquisition and buff valuation

Status: Design workflow  
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
8. Export the selected records to stable JSON/CSV owned by Bestow.

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
| `Bloodmage` | `Son of Arugal` / `SONOFARUGAL` |
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

## Utility calculation

For recipient spec `s` and a resolved family/rank `f`, first determine every
realized stat delta:

```text
baseUtility(s, f) =
  sum over stats x (
    realizedDelta(f, x) * statWeight(s, x)
  )
```

Then apply explicit category/spec adjustments:

```text
adjustedUtility(s, f) =
  baseUtility(s, f)
  * categoryMultiplier(s, category(f))
  + categoryBonus(s, category(f))
```

Defaults are multiplier `1.0` and bonus `0`.

Examples of adjustments:

- tanks may receive a Stamina multiplier greater than `1.0`;
- non-tanks may receive a smaller Stamina bonus so survivability is useful
  without outranking primary throughput;
- mana-efficiency effects may need a curated bonus when MP5 does not fully
  describe their benefit;
- resistance or secondary utility may use a documented bonus when no
  compatible BisBeard weight exists.

Adjustments are data, keyed by spec ID and category. They must never be hidden
inside solver code.

## Conversion to Bestow's 0–100 scale

Raw BisBeard weights are anchor-relative. Bestow exposes a normalized score:

```text
score(s, f) =
  round(100 * adjustedUtility(s, f) / maxUtility(s))
```

`maxUtility(s)` is the greatest adjusted utility among the tracked,
reference-rank buff families evaluated for that spec. Clamp the result to
`0..100`.

Keep the following values in generated data for auditing:

- source stat weights;
- realized/reference stat deltas;
- base utility;
- multiplier and bonus;
- adjusted utility;
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
