# Bestow — Fresh Implementation Specification

Status: Draft 0.4
Target client: Ascension Conquest of Azeroth, WoW 3.3.5 (`Interface: 30300`)

## 1. Purpose

Bestow coordinates mutually exclusive class buffs across a party or raid.

The addon must answer four questions:

1. Which buff effects does each player actually know?
2. Which raid-wide Greater effect should each provider maintain?
3. Which individual targets should receive a different single-target effect?
4. Does the target already have an equal or better equivalent effect?

The implementation starts fresh. BuffReminders and PallyPower are reference
material for behavior and lessons learned, not foundations that constrain the
new architecture.

## 2. Confirmed game behavior

- CoA providers are **classes**, not specializations.
- Recipient specialization is useful for determining which effects the
  recipient values.
- A provider class may know several mutually exclusive buff families.
- A caster normally maintains only one exclusive configured family on a
  particular target. Catalogued `independent` families do not consume that
  slot.
- Greater and single-target variants of a family are functionally identical;
  only their targeting scope differs.
- Greater variants affect the entire raid. They establish the caster's default
  family for every recipient rather than being assigned by subgroup.
- A single-target cast can replace that caster's Greater default with a
  different family on one recipient.
- Multiple players of the same provider class must be assigned independently.
- Different spell families can provide equivalent effects.
- Spell families can have multiple ranks.
- An existing equal or stronger equivalent effect must suppress a reminder.
- Provider effectiveness is derived from exact spell-effect magnitude,
  verified rank/talent modifiers, and the recipient specialization's stat
  weights. Curated class/family priority tiers remain a fallback only while
  numeric effect data is incomplete or for benefits that cannot be expressed
  as supported stats.
- Earthen Endurance is an independent Primalist family: it can be assigned and
  maintained alongside that Primalist's normal mutually-exclusive family,
  including as a second Greater assignment.
- Other unique class buffs that do not participate in this shared-effect
  system remain outside the version-one flow.

## 3. Items requiring in-game validation

These must remain configurable or diagnostic until confirmed:

- Whether verified talents should change ordering within a curated provider
  tier for Guardian Honor, Reaper Rite of Power, or other improved families.
- Exact duration and range for each family.
- Whether every class token is stable and English across client locales.
- Unresolved, missing, or duplicate spell/aura IDs in the imported catalog.

## 4. Terminology

### Effect category

A gameplay benefit shared by otherwise unrelated spell families.

Initial categories:

| Key | Full label | Compact label |
|---|---|---|
| `strength` | Strength | `Str` |
| `stamina` | Stamina | `Stam` |
| `agility` | Agility | `Agi` |
| `intellect` | Intellect | `Int` |
| `spirit` | Spirit | `Spirit` |
| `attackPower` | Attack Power | `AP` |
| `spellPower` | Spell Power | `SP` |
| `percentStats` | All Stats | `All Stats` |
| `manaRegen` | Mana Regeneration | `MP5` |
| `costReduction` | Resource Cost Reduction | `Cost` |
| `armorStats` | Stats + Armor | `Stats+` |

Each category also defines a canonical display icon. The effect category owns
the compact label; provider-specific spell names never leak into space-limited
assignment cells or cast rows.

MP5 and resource-cost reduction are separate compatibility groups and may
coexist. A compound family can satisfy multiple groups with one aura and one
cast. `Devotion of Grace` is the initial compound case: it fills both
`manaRegen` and `costReduction`. The solver represents both cells but consumes
only one Sun Cleric buff slot and emits only one cast action.

Templar's All Stats family uses different single and raid-wide names:
`Gift of Fervor` is the individual 10% Stats cast and
`Greater Crusader's Oath` is its Greater counterpart.

`armorStats` is a Mark-of-the-Wild-style composite category. Its families
grant flat primary stats plus armor; they are not armor-only effects. Numeric
valuation expands the flat amount into Strength, Agility, Stamina, Intellect,
and Spirit before applying recipient stat weights. Armor contributes only
through an explicit survivability adjustment.

### Provider class

The CoA class that owns a spell family, such as Guardian, Reaper, or Sun
Cleric. Provider identity never comes from specialization.

### Spell family

A provider-specific single/Greater pair that supplies an effect category.

Examples:

- `strength + Guardian → Honor / Greater Honor`
- `strength + Reaper → Rite of Power / Greater Rite of Power`
- `strength + Knight of Xoroth → Mark of Korth'azz / Greater Mark of Korth'azz`

### Capability

A spell family the local client has verified in its spellbook, including the
highest known single and Greater ranks.

### Greater assignment

One raid-wide effect category assigned to one named provider player.

### Individual override

A single-target effect category assigned by a provider to one named recipient.
It supersedes that provider's Greater assignment for that recipient.

### Assignment

The desired responsibility for a provider to supply an effect to a recipient.
Assignment is configuration state; it is not proof that the aura is currently
active.

### Coverage

The best active aura value found for an effect category on a unit, regardless
of which class supplied it.

### External coverage

Observed coverage from an aura source that is not the coordinated provider for
that recipient/category cell. External coverage may satisfy or outperform the
assignment, but observation alone never rewrites a manual assignment.

## 5. Product requirements

### 5.1 Provider discovery

- Scan the local spellbook rather than assuming abilities from class or level.
- Resolve live roster class with `UnitClass(unit)`. Use the second return value
  as the class token and the first as the localized/display name.
- Enumerate client class tokens from `CLASS_SORT_ORDER`, then immediately
  discard `HERO` and every vanilla token. Only the bundled CoA token registry
  below participates in roster, specialization, preference, capability, or
  assignment logic.
- Enumerate CoA specs with `C_ClassInfo.GetAllSpecs(classToken)` and
  `C_ClassInfo.GetSpecInfo(classToken, specIndex)`. Resolve advertised spec IDs
  with `C_ClassInfo.GetSpecInfoByID(specID)` when available.
- Resolve class colors through `CUSTOM_CLASS_COLORS[classToken]`, then
  `RAID_CLASS_COLORS[classToken]`, then a neutral fallback.
- Normalize harmless class-name differences such as spaces, underscores, and
  capitalization.
- Keep explicit aliases where the internal token and displayed provider name
  differ. Known CoA mappings include `TINKER → Tinkerer`,
  `SPIRITMAGE → Runemaster`, `WILDWALKER → Primalist`,
  `PROPHET → Venomancer`, `FLESHWARDEN → Knight of Xoroth`,
  `MONK → Templar`, and `DEMONHUNTER → Felsworn`.
- Treat `HERO` as a generic Ascension fallback, not a provider class. If a CoA
  unit unexpectedly reports `HERO`, accept an explicit `Class` field from
  `C_ClassInfo` spec metadata or an addon capability advertisement, but do not
  infer class from the human-readable spec name or infer castability without
  spellbook/addon evidence.
- Never infer provider class from specialization name.
- Broadcast only capabilities verified on the local client.
- For a player without the addon, create a provisional capability set from
  their observed CoA class and the catalog. Assume the highest-priority family
  for planning until one of their tracked auras is observed.
- Non-addon players cannot receive addon instructions, but may appear as
  provisional providers in the matrix. Once their aura is observed, use the
  observed family as their effective Greater/default choice and recalculate
  the remaining assignments.
- Auras from players without the addon always count as coverage.

The following registry was dumped from the target CoA client. Provider display
aliases preserve the class names used by the buff catalog. Spec annotations
use `T` for tank, `H` for healer, `M` for melee DPS, and `D` when the client
sets none of those flags; the remaining words are the reported primary stats.

| CoA token | Provider display name | Specializations |
|---|---|---|
| `BARBARIAN` | Barbarian | `1 Headhunting [D Agility]`, `2 Brutality [M Agility]`, `3 Ancestry [M Agility]` |
| `WITCHDOCTOR` | Witch Doctor | `4 Shadowhunting [D Agility]`, `5 Voodoo [D Intellect Spirit]`, `6 Brewing [H Spirit]` |
| `DEMONHUNTER` | Felsworn | `7 Infernal [D Intellect Spirit]`, `8 Slayer [M Agility]`, `9 Tyrant [T Agility Stamina]` |
| `WITCHHUNTER` | Witch Hunter | `10 Boltslinger [D Agility Intellect]`, `11 Houndmaster [D Agility Intellect]`, `12 Inquisition [M Agility Intellect]`, `97 Black Knight [T Agility Stamina]` |
| `STORMBRINGER` | Stormbringer | `13 Wind [D Intellect]`, `14 Maelstrom [D Intellect]`, `15 Lightning [D Intellect]` |
| `FLESHWARDEN` | Knight of Xoroth | `16 Hellfire [M Strength Intellect]`, `17 Defiance [T Strength Stamina]`, `18 War [M Strength]` |
| `GUARDIAN` | Guardian | `19 Gladiator [M Strength]`, `20 Inspiration [M Strength]`, `21 Vanguard [T Strength Stamina]` |
| `MONK` | Templar | `22 Oathkeeper [T Agility Stamina]`, `23 Zealot [M Agility]`, `24 Crusader [M Agility]` |
| `SONOFARUGAL` | Blood Mage | `25 Fleshweaver [D Spirit]`, `26 Sanguine [D Spirit Stamina]`, `27 Accursed [M Agility]`, `99 Eternal [T Agility Stamina]` |
| `RANGER` | Ranger | `28 Archery [D Agility]`, `29 Farstrider [D Agility]`, `30 Brigand [M Agility]` |
| `CHRONOMANCER` | Chronomancer | `31 Time [H Spirit]`, `32 Infinite [D Spirit]`, `33 Artificer [D Spirit]` |
| `NECROMANCER` | Necromancer | `34 Death [D Intellect]`, `35 Animation [D Intellect]`, `36 Rime [D Intellect]` |
| `PYROMANCER` | Pyromancer | `37 Flameweaving [H Spirit]`, `38 Incineration [D Intellect]`, `39 Draconic [D Intellect]` |
| `CULTIST` | Cultist | `40 Heretic [H Intellect Strength]`, `41 Corruption [D Intellect]`, `42 Godblade [M Strength]`, `96 Dreadnought [T Strength Stamina]` |
| `STARCALLER` | Starcaller | `43 Moon Priest [H Intellect]`, `44 Sentinel [D Intellect]`, `45 Warden [M Intellect]`, `100 Moon Guard [T Intellect Stamina]` |
| `SUNCLERIC` | Sun Cleric | `46 Piety [D Intellect]`, `47 Valkyrie [M Strength]`, `48 Seraphim [T Strength Stamina]`, `98 Blessings [H Intellect]` |
| `TINKER` | Tinkerer | `49 Demolition [D Agility Intellect]`, `50 Mechanics [D Agility Intellect]`, `51 Invention [H Intellect]` |
| `PROPHET` | Venomancer | `52 Fortitude [T Intellect Stamina]`, `53 Stalking [M Intellect]`, `54 Rot [D Intellect]`, `101 Vizier [H Intellect]` |
| `REAPER` | Reaper | `55 Soul [M Strength]`, `56 Harvest [M Strength]`, `57 Domination [T Strength Stamina]` |
| `WILDWALKER` | Primalist | `58 Grovekeeper [D Strength Intellect]`, `59 Wildwalker [M Strength]`, `60 Mountain King [T Strength Stamina]`, `95 Geomancy [D Intellect]` |
| `SPIRITMAGE` | Runemaster | `61 Engravement [M Agility]`, `62 Glyphic [D Intellect Spirit]`, `63 Riftblade [M Agility]` |

The eleven vanilla tokens returned by the shared client registry are ignored
completely. `HERO` never participates as a provider; a unit reporting `HERO`
is admitted only when explicit client/addon metadata resolves it to one of the
CoA tokens above.

Blood Mage uses the internal client token `SONOFARUGAL`. The legacy display
names `Son of Arugal` and `Bloodmage` resolve to the same class.

### 5.2 Spell and rank discovery

- Spellbook data is authoritative for castability.
- Spell IDs are preferred identity; localized spell names are fallback
  identity.
- Scan every spellbook slot and parse the spell ID from its link.
- Select the highest known rank from the configured rank order.
- Do not treat entries in WeakAuras' global spell cache as known spells.
- WeakAuras cache search remains a diagnostic/import tool only.
- Passive spells and unrelated duplicate-name spells must be excluded.
- Single and Greater variants are discovered independently.
- A capability may temporarily contain only a single or only a Greater spell.

### 5.3 Aura equivalence and value

- Scan active auras by category, not only by the assigned spell name.
- Single and Greater variants of the same family resolve to the same coverage
  identity and effect magnitude. Cast form never changes value.
- Match straight and typographic apostrophes safely.
- Prefer spell ID matching when the client exposes aura spell IDs reliably.
- Each known rank stores its exact stat deltas or a typed percentage-effect
  descriptor. Verified talents modify those effects explicitly.
- Compare equivalent families using their calculated recipient-specific
  utility. Exact equal utility counts as equivalent coverage; greater utility
  is stronger coverage.
- Curated provider tiers are used only when one or both effects lack verified
  magnitude data. The fallback must be surfaced diagnostically.
- Tooltip-derived magnitudes are build-time catalog data and require in-game
  verification; the addon does not parse tooltips during assignment.
- Expiring coverage becomes actionable only inside the configured refresh
  threshold.
- The UI must distinguish:
  - our active effect;
  - equivalent effect from another provider;
  - stronger effect from another provider;
  - missing effect;
  - expiring effect.

### 5.4 Raid-wide Greater assignments

- Each provider player receives zero or one Greater category.
- A category normally receives at most one provider.
- A Greater assignment is raid-wide, not per class, spec, subgroup, or target.
- Greater choice is derived from the provider's final recipient assignments,
  not maintained as an unrelated second source of truth.
- A category-header bulk edit creates the corresponding recipient cell
  selections; those explicit selections take precedence over computed cells.
- Invalid manual assignments are ignored and surfaced diagnostically; they do
  not block recalculation.
- Automatic assignments recalculate when:
  - roster changes;
  - capability advertisements change;
  - recipient specs change;
  - preferences change;
  - manual assignments change;
  - an observed non-addon provider aura reveals their chosen family.
- After per-recipient responsibilities are resolved, each provider's Greater
  category is the category assigned to that provider for the greatest number
  of recipients. Ties use category demand, curated provider priority, stable
  category key, then stable provider identity.
- Assignments that differ from that modal Greater category become individual
  casts.
- Recalculation is allowed to churn assignments whenever the objective
  improves. Assignment stability is only a final tie-break, not a threshold
  that preserves a worse solution.

### 5.5 Individual overrides

- Overrides are stored by provider identity and recipient identity.
- Only categories the provider can cast as a single-target spell are valid.
- Runtime state distinguishes computed assignments from explicit manual
  provider selections, but the normal UI does not need to label them
  differently.
- Mouse wheel over a recipient row cycles valid local single-target categories.
- Cycling to the provider's Greater category clears that caster-side individual
  override for the recipient.
- Overrides survive reloads during the same group session and are cleared when
  the group fully disbands.
- In a raid, automatic individual overrides default to disabled.
- In a party, automatic overrides optimize the composition using recipient
  preferences.
- Raid individual overrides are configured manually in version one.

### 5.6 Recipient preferences

- Preferences are keyed by numeric specialization ID when available.
- Each spec provides stat weights plus explicit family/spell bonus points
  for survivability or utility that ordinary item weights do not capture.
- The resolved effect utilities are normalized to integer scores from `0` to
  `100`; the score provides both ordering and eligibility.
- Class and role profiles are fallbacks when exact spec data is unavailable.
- A global category order is only the final deterministic tie-break.
- Users can edit preferences.
- Per-player manual overrides always beat spec preferences.
- Addon users advertise only explicit current-spec category overrides; every
  client calculates the reviewed source score locally.
- For a recipient without an advertised preference, the coordinator applies
  its configured spec/class/role template.
- Unknown specs must not block assignments.
- Preference configuration must be exportable/importable.

Suggested lookup order:

1. explicit recipient/category provider selection;
2. recipient-advertised current-spec preference;
3. coordinator user-defined exact spec preference;
4. bundled exact spec preference;
5. coordinator user-defined class/role preference;
6. bundled class/role preference;
7. global fallback order.

`0` means no modeled value. Positive scores are ordered directly. Automatic
individual assignments use an initial incremental-value threshold of `25`;
manual assignments may bypass it.

#### Bundled stat-weight seed

Version one ships reviewed source weights and a calculated preference entry
for every CoA spec. BisBeard's public `specRoles` application module is the
initial external source. Acquisition, aliases, validation, effect-magnitude
storage, normalization, and review are defined in
[`STAT_WEIGHT_WORKFLOW.md`](STAT_WEIGHT_WORKFLOW.md).

The previous role/primary-stat seed remains only as a fallback for missing or
rejected source data. A source refresh never silently overwrites the last
reviewed bundled snapshot or user edits.

### 5.7 Multiple providers and value priority

- Providers are identified by player identity, not class.
- Multiple players of the same class advertise separate capabilities.
- Higher calculated recipient utility is preferred. Curated provider
  effectiveness is a fallback when numeric comparison is unavailable.
- Assignment optimization applies this objective order:
  1. satisfy hard validity and uniqueness constraints;
  2. cover higher-demand/relevance categories;
  3. maximize total recipient preference value;
  4. maximize calculated effect utility and then fallback provider
     effectiveness where required;
  5. minimize assignment churn only between otherwise equal solutions;
  6. use stable category and provider identity ordering for exact ties.
- A weaker provider may be assigned a different category if that produces
  better total coverage.

### 5.8 Reminder behavior

- The addon must never recommend a cast that cannot improve coverage.
- The compact header remains visible by default. Covered recipient rows are
  available on hover and show duration.
- Covered rows use neutral styling, not the same styling as a locally
  completed cast.
- Missing/expiring effects may be emphasized, but no repeated chat messages or
  sounds occur unless enabled explicitly.
- Dead recipients remain visible when actionable, but are desaturated and
  marked `DEAD` in red. Offline, phased, out-of-range, or otherwise invalid
  recipients are skipped by the queue and retain a visible deferred indicator.
- Combat lockdown must never cause protected-action errors.
- The default refresh threshold is five minutes.

## 6. Assignment algorithm

### 6.1 Inputs

- Current roster.
- Provider capabilities.
- Exact provider effect magnitudes, rank/talent modifiers, and fallback
  effectiveness tiers.
- Existing active coverage.
- Recipient class/spec/role.
- Recipient stat weights, survivability/utility adjustments, normalized
  scores, and preference-data version.
- Manual category-header bulk selections.
- Manual recipient/category provider selections.

### 6.2 Greater assignment constraints

- A provider has at most one derived Greater category.
- A category has at most one derived Greater provider automatically.
- The provider must know the category's Greater spell.
- A category-header bulk selection fixes the affected recipient cells before
  Greater categories are derived; it does not bypass capability or uniqueness
  constraints.

### 6.3 Demand score

For each candidate family and eligible recipient, calculate utility from the
family's realized stat deltas multiplied by that spec's stat weights, normalize
the measurable value to `0..100`, then apply explicit bonus points.

Category demand is the sum of the best available normalized utility for its
eligible recipients. Zero contributes nothing. Exact ties use stable category
and identity ordering.

### 6.4 Initial implementation

Use a deterministic matrix solver:

1. Lock valid manual recipient/category provider selections.
2. In a party, resolve each recipient's remaining desired categories by
   normalized utility and allow computed individual differences.
3. In a raid, compute raid-wide category/provider coverage first and populate
   recipients from those Greater defaults; only explicit cell selections may
   create individual differences.
4. Assign at most one provider to each recipient/category cell.
5. Enforce one family per provider/recipient pair.
6. Prefer the provider/rank with the highest calculated recipient utility
   unless using that provider elsewhere produces better total coverage and
   utility. Use curated tiers only when numeric data is unavailable.
7. Derive each provider's Greater category from the modal count of their final
   recipient assignments.
8. Mark every non-modal provider/recipient assignment as an individual cast.
9. Apply stable identity tie-breaks and return the complete result atomically.

The first implementation may use deterministic weighted greedy matching if its
result is validated against representative party and raid fixtures.

### 6.5 Future implementation

Replace greedy matching with maximum-weight bipartite matching if testing shows
greedy assignments lose meaningful total value.

The edge score combines normalized recipient utility, category demand, and
fallback provider ordering when numeric effect data is incomplete. The
underlying raw utility and every adjustment remain auditable data.

Changing algorithms must not change the data model or communications format.

### 6.6 Party override selection

For each party recipient:

1. Honor explicit manual provider selections.
2. Read the recipient's normalized family utilities.
3. Allocate available providers across positive-value cells while enforcing
   one family per provider/recipient pair and one provider per cell.
4. When a provider is selected for a category other than their derived Greater
   category, create an individual cast assignment.
5. If selecting a provider displaces another provider from the cell, re-run
   that displaced provider against the recipient's next-highest positive-gain,
   unoccupied category; assign nothing if no threshold-qualified improvement
   remains.
6. Suppress casts whose active coverage is equal or stronger.

Here, `assign nothing` means no individual responsibility for that displaced
provider. Their raid-wide aura may still be observed as external/ambient
coverage, but it does not create a duplicate matrix occupant or reminder.

## 7. Data model

The catalog should be declarative and separate from runtime state.

```lua
Categories = {
  strength = {
    label = "Strength",
    shortLabel = "Str",
    icon = "Interface\\Icons\\...",
    variants = {
      honor = {
        providerClass = "Guardian",
        single = {
          names = {"Honor"},
          rankIDs = {300856, 301228, 301229, 301230, 301231, 301232},
        },
        greater = {
          names = {"Greater Honor"},
          rankIDs = {680280},
        },
        effectsByRank = {
          -- Schema example only; 12 is not a verified Honor value.
          [300856] = {kind = "stats", stats = {strength = 12}},
          -- Remaining verified rank values.
        },
        talentRule = "guardianHonor",
        fallbackPriorityTier = 1,
      },
    },
  },
}
```

Runtime capability:

```lua
Capability = {
  category = "strength",
  family = "honor",
  providerClass = "Guardian",
  singleSpellID = 301232,
  greaterSpellID = 680280,
  -- Schema example only; 72 is not a verified Honor value.
  resolvedEffect = {kind = "stats", stats = {strength = 72}},
  effectVerification = "verified",
  fallbackPriorityTier = 1,
  verifiedTalentState = "unknown",
}
```

Generated tooltip-derived magnitudes live in `Data/Effects.lua`, keyed by
spell ID. The typed fields preserve flat primary stats, percentage stats,
Attack Power, Spell Power, Armor, MP5, resource-cost reduction, individual
resistances, and all-resistance bonuses independently. Runtime scoring consumes
these fields; it never reparses tooltip prose.

BisBeard weights price ordinary throughput stats and list MP5 as an available
field without recommending a default value. Bestow exposes MP5 as a
player-configurable, zero-default supplemental weight. It separately stores
curated per-spec family/spell bonus points for resource-cost reduction, Armor,
resistances, nonlinear synergy, and other utility not represented by weights.
Bonus points are explicit, versioned review data. Unreviewed entries default
to zero; Stamina families currently use a reviewed stock value of `10`, while
resource-cost-reduction families use `20`.

MP5 families additionally use a stock value of `10` for all specializations of
Necromancer, Pyromancer, Cultist, Starcaller, Sun Cleric, Tinkerer, Runemaster,
Primalist, Venomancer, Chronomancer, Stormbringer, Witch Doctor, and Witch
Hunter. Devotion of Grace combines both components for a stock value of `30`
for mana users and `20` for other classes.

Any exact buff rank that also grants Arcane, Fire, Frost, Nature, Shadow, or
all resistances receives an additional `2` stock bonus points. This component
is applied from the structured spell effect, so it stacks with Stamina,
cost-reduction, MP5, or other family adjustments.

Roster member:

```lua
RosterMember = {
  guid = "...",
  name = "Player",
  unit = "raid7",
  className = "Guardian",
  classToken = "...",
  specName = "Seraphim",
  role = nil,
  subgroup = 2,
  online = true,
  dead = false,
}
```

Manual cell selections:

```lua
ManualSelections = {
  ["Recipient-GUID"] = {
    strength = {
      providerGUID = "Provider-GUID",
      editorGUID = "Leader-GUID",
    },
  },
}
```

Derived authoritative result:

```lua
AssignmentResult = {
  cells = {
    ["Recipient-GUID"] = {
      strength = {
        providerGUID = "Provider-GUID",
        delivery = "greater", -- or "individual"
      },
    },
  },
  greaterByProvider = {
    ["Provider-GUID"] = "strength",
  },
  coordinatorEpoch = 7,
  revision = 42,
}
```

The final matrix and `greaterByProvider` are committed atomically. Individual
casts are derived wherever a provider's cell category differs from that
provider's modal Greater category.

## 8. Communications protocol

### 8.1 General

- Use a new addon prefix unrelated to PallyPower or BuffReminders.
- Include a protocol version.
- Keep every message below the 3.3.5 addon-message size limit.
- Split capability payloads when required.
- Ignore unknown message types and newer incompatible versions safely.
- Player names in messages must use a consistent realm-normalization policy.
- GUIDs are preferred for override targets when reliably available.

### 8.2 Message types

- `HELLO`: protocol version and addon version.
- `REQ`: request current provider state.
- `CAP_BEGIN`: capability revision and chunk count.
- `CAP`: chunked provider capability payload.
- `CAP_END`: completes and atomically installs a capability revision.
- `EDIT`: authorized request to change one cell, reset one cell, change one
  provider's own recipient family, or perform a category-header bulk edit.
- `TX`: coordinator-committed assignment transaction containing epoch,
  revision, explicit-selection changes, and the resulting derived assignment
  diff.
- `STATE_BEGIN`: begins a complete authoritative current-session snapshot.
- `STATE`: chunked explicit selections plus derived matrix/Greater state.
- `STATE_END`: atomically installs the completed session revision.
- `PREF`: revisioned current-spec normalized scores and preference-data version
  advertised by that recipient.
- `WEIGHTS`: recipient-owned current-spec stat-weight deltas, bundled-source
  fingerprint, revision, checksum, and explicit reset tombstone.
- `BONUS`: recipient-owned per-family effective bonus-point delta or reset
  tombstone for the current specialization.
- `LEAVE`: optional provider state removal.

### 8.3 Authority

- In a raid, the raid leader and assistants may make category-header bulk edits
  and individual provider selections for any recipient.
- In a party, every addon user may edit the shared assignment state.
- Every provider may always change their own recipient overrides.
- Each player is authoritative for their own advertised preference scores and
  adjustment overrides.
- Each player is authoritative for their own advertised stat weights. A
  recipient's compatible advertisement applies only when scoring that
  recipient; clients use bundled defaults for non-addon players and
  incompatible or missing advertisements.
- Changes are immediately authoritative; there is no assignment lock or
  accept/decline handshake.
- A player whose assignment is changed remotely receives a clear, non-spammy
  notification identifying the editor, recipient, and new effect.
- A provider may change the assignment back, subject to the same authority and
  revision rules.
- One coordinator serializes automatic recalculation and shared mutations:
  raid leader first, then assistant by stable identity, then another addon user
  by stable identity. In a party, use stable identity election among addon
  users while allowing everyone to submit edits.
- Non-coordinator clients may calculate previews, but the coordinator's
  revisioned result is authoritative. Coordinator handoff increments an epoch
  so revisions from the prior coordinator cannot overwrite current state.
- Unauthorized messages are ignored.
- Assignment messages include coordinator epoch and monotonically increasing
  revisions.
- Newer revisions replace older revisions.
- Selection removal is communicated explicitly as a tombstone/reset state;
  absence from a delta message must never be interpreted as removal.
- On joining, reloading, reconnecting, or receiving `REQ`, each addon user
  advertises their complete local capability revision.
- On joining, reloading, reconnecting, coordinator handoff, or receiving
  `REQ`, the coordinator sends a complete revisioned state snapshot.
- Complete snapshots are installed atomically so clients never display a
  mixture of old and new assignment state.
- The coordinator broadcasts each committed automatic or manual transaction so
  clients with temporarily different roster/spec observations converge.

### 8.4 Partial-addon groups

- Addon users advertise verified spellbook capabilities.
- Non-addon users receive provisional catalog capabilities based on their
  resolved CoA class and may be shown as expected providers, but cannot receive
  addon instructions or acknowledge assignments.
- Until a tracked aura is observed, assume a non-addon player will provide the
  highest-priority useful family available to their class.
- Once observed, their active family replaces that assumption and the
  coordinator recalculates other responsibilities around it.
- Their active auras always contribute coverage.
- The UI clearly identifies provisional responsibility and uncoordinated
  external coverage.

## 9. UI specification

### 9.1 Compact cast panel

Visible by default.

Contains:

- one prominent out-of-combat `Buff Next` secure-action button;
- one fixed local Greater secure-action button available in combat when the
  Greater spell was known and prepared before combat;
- a remaining-action count and next effect/recipient preview;
- local raid-wide Greater assignment;
- one recipient row for every player assigned to the local provider, including
  players expected to receive the provider's Greater default;
- effect label rather than provider-specific spell name;
- remaining duration;
- missing/covered/stronger/expiring state;
- class-colored recipient names and spec names when known.

Click behavior:

- Each `Buff Next` click casts exactly one spell.
- Out of combat, the same button is prepared for the next required action
  after cast/aura state is confirmed.
- Greater and recipient rows are directly clickable out of combat.
- Secure attributes update only out of combat.
- In combat, the dynamic `Buff Next` action is disabled because it cannot
  safely advance to a new spell/unit.
- A separately prepared Greater button and fixed per-recipient secure buttons
  remain clickable in combat. Their spell/unit attributes, positions, and row
  identities are frozen from the last valid out-of-combat snapshot.
- Aura state, duration, dead/offline/range hints, and missing/covered styling
  continue to update through an unprotected visual layer without changing the
  secure action.

The panel/header remains visible when fully covered. Covered recipient rows
are shown by default and display their durations. A recipient whose assignment
matches the local Greater is still shown; their row casts the equivalent
single-target form when that form exists. A Greater-only family leaves those
rows visible as status-only controls.

Queue priority:

1. missing assigned Greater coverage;
2. missing manual individual assignments;
3. missing computed party individual assignments;
4. expiring manual individual assignments;
5. expiring Greater coverage;
6. expiring computed party individual assignments.

Missing coverage always outranks a refresh. Dead, offline, phased,
out-of-range, and otherwise invalid targets are skipped without losing their
place; their individual row remains visible with a deferred-state indicator.
The queue advances only after the expected aura is observed.

#### Collapsible recipient stack

- The header and local Greater/`Buff Next` button remain visible.
- Default behavior is `Always expanded` so the complete local responsibility
  and group buff state remain visible.
- Optional `Hover` behavior expands individual recipient rows while the
  pointer is over the header, Greater button, or expanded stack.
- The stack collapses after a short configurable delay when the pointer leaves
  the entire region. Moving between the header and rows must not flicker.
- Missing, expiring, and manually overridden recipient rows automatically
  reveal themselves.
- After successful coverage, an automatically revealed row remains briefly to
  show confirmation/duration and then collapses.
- The protected combat stack is pre-created and pre-positioned out of combat.
  When combat begins, a secure state driver may reveal that frozen stack
  without insecure code calling `Show`, `Hide`, `SetPoint`, or `SetAttribute`
  on protected frames.
- Combat uses the last prepared recipient ordering. Roster or assignment
  changes are displayed as pending and applied to secure rows after combat.
- The collapsed header continues to show a summary such as
  `2 missing · 1 expiring`.

Configuration modes:

- `Hover`.
- `Always expanded` is the default.
- `Always collapsed`.

Additional settings:

- collapse delay;
- expand upward or downward;
- reveal missing buffs;
- reveal expiring buffs;
- expiration threshold;
- hide-after-buff delay;
- show covered recipients on hover;
- always show manual overrides;
- show the prepared combat recipient stack;
- show missing/expiring rows during combat.

#### Smart-button combat constraints

- WoW requires one hardware click per protected spell cast.
- The addon cannot cast the entire queue from one click.
- Out of combat, it may update the smart button's spell and recipient between
  clicks.
- During combat, the dynamic `Buff Next` button is visually disabled and
  cannot advance.
- The fixed Greater button and fixed recipient buttons may execute their
  preconfigured actions in combat. Every action uses native secure
  `type="spell"`, `spell`, and `unit` attributes rather than cursor-targeting
  macros.
- Protected frames are created, anchored, sized, assigned stable unit tokens,
  and given spell attributes before combat. Combat visibility changes use
  validated secure state drivers only.
- Insecure `PreClick`/`PostClick` handlers must not clear or restore protected
  attributes during combat. Native unit-targeted spell actions handle failed
  range/target checks without leaving a targeting cursor.
- The visual row may report that its frozen secure target is stale, dead,
  offline, or out of range, but it must not retarget itself until combat ends.
- The header identifies that combat actions are using the prepared snapshot.
- Missing and expiring coverage continues to update as an aura watch.
- Failed, interrupted, or out-of-range actions remain queued until the
  expected aura is observed.

### 9.2 Assignment panel

The primary assignment view is a matrix:

- rows are every player in the current group;
- columns are every configured effect category;
- each category header shows the provider whose Greater cast is the default for
  that category, when one exists;
- a cell tinted with that provider's assignment color means the header's
  Greater/default provider supplies that recipient;
- a cell containing a class-colored player name is an individual assignment
  supplied by that named provider;
- an empty cell means no coordinated provider is capable or useful;
- duplicate provider classes remain separate player identities;
- the table supports forty rows and all categories through scrolling;
- users may transpose the axes.

Each category header is also a bulk editor. Its provider-only dropdown uses
the same tiered ordering as a cell dropdown. Selecting a provider assigns that
provider to the category for every eligible recipient, atomically recalculates
displaced responsibilities, and therefore normally makes that category the
provider's derived Greater choice. It does not write a separate Greater value
that can drift away from the matrix.

The matrix displays desired responsibility. Actual aura coverage is a separate
status overlay and never silently replaces the configured provider.

Each recipient/category cell has zero or one responsible provider. Redundant
providers are not valid occupants of the same cell. When a provider is moved
into an occupied cell, the previous provider is displaced and recalculated
against the recipient's next-highest useful, unoccupied category. If no useful
category remains, that provider receives no assignment for that recipient.

Each cell is also an override editor. Its dropdown contains:

- every group player capable of providing the category, including the
  currently optimal provider;
- the provider class and resolved spell family;
- whether the choice uses their Greater default or requires an individual
  single-target override.

There is no `Automatic` or `No coordinated provider` item in the provider
dropdown. The optimizer's current choice populates the cell by default.
Selecting another provider creates a manual override. A separate
`Reset to optimal` cell action clears the manual selection and immediately
re-runs the optimizer.

Dropdown providers are sorted by calculated utility for the cell's recipient,
highest first. Non-selectable dividers may separate meaningful utility bands
or fallback-only provider tiers. Equal-utility entries sort by:

1. verified talent bonus;
2. highest known rank;
3. stable provider identity.

Selecting a provider performs one atomic assignment transaction:

1. assign that provider/category to the recipient;
2. create the required single-target override when it differs from the
   provider's Greater category;
3. resolve the one-buff-per-provider/recipient constraint;
4. recalculate the provider previously responsible for the cell;
5. broadcast one revisioned transaction;
6. refresh every matrix and the selected caster's personal button stack.

Impossible candidates are disabled with an explanation. Selecting a weaker
provider is permitted as an explicit responsibility override, but equal or
stronger active external coverage suppresses a useless cast reminder.

Cell presentation includes:

- provider name colored by provider class;
- header/tint treatment for Greater coverage versus a named individual
  provider;
- missing, expiring, covered, or stronger-external-coverage state;
- duration where attributable;
- tooltip with provider class, recipient spec, resolved spell/rank,
  assignment source, calculated utility, stat deltas, fallback tier when used,
  and active aura source.

Automatic and manual assignments use the same blue assigned-state treatment;
the interface does not rely on separate automatic/manual colors. Tooltips and
diagnostics may still identify whether a selection is computed or explicit.

The matrix and caster-side mouse-wheel controls edit the same authoritative
override state:

```text
matrix dropdown or caster-row scroll
                 |
                 v
      provider/recipient override
                 |
        +--------+--------+
        |        |        |
      comms    matrix   cast queue
```

Interaction and consistency:

- raid leader/assistant, party-wide, and own-provider authority is enforced;
- matrix editing is disabled during combat;
- override deltas broadcast immediately;
- full snapshots repair missed deltas and initialize new/reloaded clients;
- provider departure removes that provider from computed cells;
- recipient specialization changes trigger recalculation;
- GUID is preferred for recipient identity, with normalized full name fallback;
- incomplete snapshots display a synchronization indicator;
- external aura coverage is shown separately and does not become an assignment
  merely because it was observed.

### 9.3 Personal override panel

Rows show every recipient:

- class-colored name;
- spec name when available;
- current effective effect category;
- Greater-default or individual state;
- current coverage source;
- duration.

Interaction:

- mouse wheel cycles valid local single-target categories;
- one option explicitly retains the raid-wide Greater default;
- tooltip shows the resolved spell and why the current choice was selected;
- a remotely assigned change updates the row immediately and produces a clear,
  non-spammy notification.

#### Equivalent-provider priority strip

While a recipient row is hovered or its override is being changed with the
mouse wheel, display a temporary horizontal strip of every group provider that
can supply the currently highlighted effect category.

The strip provides immediate answers to:

- which equivalent spell families are available;
- which provider is most effective;
- which provider is currently assigned;
- where the local caster ranks among the alternatives.

Each capable provider receives a separate icon, even when multiple players of
the same class resolve to the same spell icon. A small duplicate indicator or
tooltip disambiguates identical icons; provider identity is never collapsed
away.

Ordering:

1. calculated recipient-specific utility, strongest first;
2. verified talent improvement descending when not already represented in the
   resolved effect;
3. highest known rank descending;
4. fallback provider tier when numeric data is unavailable;
5. provider player name ascending.

Meaningful utility bands or fallback effectiveness tiers are separated by a
snapped one-physical-pixel divider or slightly larger snapped gap.

Icon content:

- concrete provider-specific spell icon;
- resolved highest known rank in the tooltip;
- provider player name and class;
- spell-family name;
- calculated recipient utility, resolved stat deltas, and any fallback tier;
- Greater-default or individual-override source;
- availability, range, and coverage information when known.

Border semantics:

- every icon retains the standard sharp one-pixel black structural border;
- an assigned provider receives a one-pixel blue assignment ring regardless of
  whether the assignment was computed or explicitly selected;
- the local caster's applicable family receives a sharp one-pixel white
  identity ring, whether assigned or not;
- when the local caster is also assigned, both markers remain visible as
  separate snapped rings rather than replacing one another;
- the currently wheel-highlighted candidate receives a separate selection
  treatment, such as a one-pixel interior highlight or pointer, so selection,
  assignment, and local identity cannot be confused;
- unavailable/dead/offline providers are desaturated but remain visible when
  useful for explaining an existing assignment.

Recommended ring order from outside to inside:

1. black structural border;
2. white local-caster identity ring when applicable;
3. colored assignment ring when applicable;
4. icon texture.

If only one state ring is present, the unused ring position is omitted and the
remaining elements stay pixel-snapped. The total icon footprint must not
change as states toggle; reserve the maximum ring area in layout calculations.

Behavior:

- the strip appears on row hover, initial wheel input, keyboard focus, or
  opening the corresponding matrix-cell dropdown;
- wheel movement updates the highlighted category and strip immediately;
- the strip is informational until the user commits the override;
- committing an override updates assignment rings on every client;
- cancelling restores the prior highlight and assignment state;
- the strip closes with the same delayed-leave behavior as the recipient stack
  so moving the pointer from the row to an icon does not dismiss it;
- in combat the strip may display current precomputed information, but it
  cannot commit an edit or rebuild protected casting buttons.

### 9.4 Preference editor

- Search/filter by class and spec.
- Display source stat weights and source version/hash.
- Edit category multipliers and additive bonuses on a `0..100` result preview.
- Show exact/reference buff deltas, base utility, adjustments, adjusted utility,
  and normalized score.
- Edit the automatic individual-gain threshold.
- Reset a spec to bundled defaults.
- Copy preferences between specs.
- Import/export serialized profiles.
- Display unknown specs discovered in the current roster.

### 9.5 Diagnostics

Provide a copyable text window containing:

- detected class/spec/role;
- spellbook capabilities and ranks;
- provider advertisements;
- Greater assignments;
- individual overrides;
- current coverage, resolved effect magnitudes, calculated utilities, and any
  fallback effectiveness tiers;
- protocol/addon versions;
- unresolved catalog entries.

Suggested commands:

- `/cb whoami`
- `/cb capabilities`
- `/cb assignments`
- `/cb dump`
- `/cb reset`

### 9.6 Visual design system

The interface should be functional and readable first, with a restrained,
consistent visual language:

- semitransparent black panel backgrounds;
- opaque, sharp one-physical-pixel black borders;
- one-pixel separators where structure is required;
- limited accent colors reserved for assignment and coverage state;
- no soft backdrop borders, gradients, oversized glows, or blurred scaling;
- compact spacing without crowding labels, durations, or click targets.

Suggested base tokens:

```lua
Theme = {
  panelBackground = {0, 0, 0, 0.78},
  rowBackground = {0, 0, 0, 0.55},
  raisedBackground = {0.06, 0.06, 0.06, 0.88},
  border = {0, 0, 0, 1},
  separator = {0, 0, 0, 0.9},
  text = {0.92, 0.92, 0.92, 1},
  mutedText = {0.58, 0.58, 0.58, 1},
  hover = {1, 1, 1, 0.07},
  missing = {0.95, 0.24, 0.20, 1},
  expiring = {1.00, 0.68, 0.15, 1},
  assigned = {0.30, 0.72, 1.00, 1},
  coveredExternal = {0.42, 0.68, 0.92, 1},
  dead = {1.00, 0.20, 0.20, 1},
}
```

Exact colors remain subject to contrast testing. Class color is applied to
player names, not entire cell backgrounds.

#### Information density and screen real estate

The interface must remain practical in a forty-player raid. Density comes from
icons, compact labels, alignment, and progressive disclosure—not illegibly
small fonts.

Default compact visual grammar:

```text
[effect icon] ClassColoredName   Stam   28m
```

Show only information needed to identify and act:

- effect icon;
- class-colored recipient or provider name;
- compact category label;
- duration or missing state;
- assignment/coverage border markers.

Do not repeat:

- full spell names already represented by an icon/category;
- words such as `Greater`, `Assignment`, `Provider`, or `Remaining` on every
  row;
- class names when class color and tooltip already communicate them;
- identical category text in every matrix cell when it is present in the
  column header.

Names:

- use CoA class colors for player names;
- fall back to neutral text when a custom class color is unavailable;
- truncate names at a snapped width with an ellipsis;
- preserve the full normalized name, class, and spec in the tooltip;
- never reduce name font size per row to make a long name fit.

Icons and labels:

- icons are the primary rapid-recognition element;
- compact labels remain visible where ambiguity would otherwise result;
- icon-only mode is allowed for expert users but tooltips remain mandatory;
- category headers use the canonical effect icon and compact label;
- provider spell icons appear only where comparing equivalent provider
  families is useful, such as the priority strip and dropdown;
- durations use compact forms such as `29m`, `4:32`, or `18s`.

Minimum legibility:

- compact rows target approximately 20–24 physical pixels high;
- primary icons target approximately 16–20 physical pixels;
- no interactive target is reduced below a reliably clickable snapped size;
- fonts use a fixed readable size selected for the current density mode;
- the addon never continuously scales text or icons to squeeze in another
  column.

Adaptive density:

- solo/party defaults may show icons, compact labels, names, and durations;
- raid defaults automatically switch to compact rows and matrix cells;
- users can choose `Compact`, `Standard`, or `Comfortable`;
- density changes rerun the shared pixel-perfect layout;
- reducing window width introduces horizontal scrolling or hides optional
  detail columns before shrinking essential content.

Progressive disclosure:

- collapsed headers show aggregate counts and the next action;
- covered recipient rows remain hidden unless hovered/configured otherwise;
- hover reveals the full recipient stack and equivalent-provider strip;
- tooltips carry full spell names, ranks, classes, specs, values, and reasons;
- clicking/selecting a matrix cell may open a detail inspector without making
  every cell permanently verbose.

Large-group performance:

- matrix rows and cells are virtualized; create only the visible viewport plus
  a small reuse buffer;
- scrolling rebinds existing visual cells instead of creating hundreds of new
  frames;
- secure cast buttons are pooled and configured out of combat;
- category headers remain fixed while recipient rows scroll;
- optional filters show only missing, overridden, or unassigned recipients.

Readability safeguards:

- class color identifies player identity; it does not encode assignment state;
- assignment and coverage continue to use borders/icons/text labels;
- icons never become the only accessible explanation of an effect;
- abbreviations are canonical and localized rather than generated by
  truncating full labels;
- semitransparent backgrounds maintain enough opacity for text contrast over
  bright game scenes.

#### Physical-pixel definition

One UI coordinate is not necessarily one physical display pixel. The shared
pixel routine calculates:

```text
physicalPixelInFrameUnits = 1 / frame:GetEffectiveScale()
```

All addon root frames should inherit from `UIParent` without arbitrary nested
`SetScale` calls. User-facing addon scale changes should update dimensions and
then rerun pixel snapping rather than scaling an already-rendered frame tree.

When a deliberately scaled child is unavoidable, its own effective scale is
used for dimensions drawn inside it. Point offsets are snapped in the
coordinate space of the relative frame.

#### Snapping contract

The addon exposes one shared routine:

```lua
local floor, ceil = math.floor, math.ceil

function Pixel:Size(frame)
  local scale = frame and frame:GetEffectiveScale()
    or UIParent:GetEffectiveScale()
  return 1 / scale
end

function Pixel:Snap(value, frame)
  local scale = frame and frame:GetEffectiveScale()
    or UIParent:GetEffectiveScale()
  local pixels = value * scale
  if pixels >= 0 then
    pixels = floor(pixels + 0.5)
  else
    pixels = ceil(pixels - 0.5)
  end
  return pixels / scale
end
```

Production helpers should include:

- `Pixel:SnapPoint(frame, point, relativeFrame, relativePoint, x, y)`
- `Pixel:SetSize(frame, width, height)`
- `Pixel:SetWidth(frame, width)`
- `Pixel:SetHeight(frame, height)`
- `Pixel:CreateBorder(frame)`
- `Pixel:CreateBackground(frame, colorToken)`
- `Pixel:Register(frame, layoutCallback)`
- `Pixel:RefreshAll()`

Rules:

- every width, height, and point offset is snapped;
- negative offsets use symmetric nearest-pixel rounding;
- layout code never adds an unsnapped fractional offset after snapping;
- adjacent frames derive shared edges from the same snapped coordinate rather
  than rounding independently;
- row heights and column widths are snapped before cumulative positioning;
- scroll offsets are snapped before applying them;
- animation endpoints are snapped when the animation finishes;
- a frame is laid out only after its final parent and effective scale are known.

#### Border construction

Do not depend on `BackdropTemplate` edge scaling for critical one-pixel
borders. Construct borders from four solid-color textures:

- top and bottom textures have height `Pixel:Size(frame)`;
- left and right textures have width `Pixel:Size(frame)`;
- all four textures are anchored inside the frame's snapped bounds;
- corner overlap is intentional and exactly one physical pixel;
- the background is a separate solid-color texture inset only when the design
  requires it.

Borders must not be created by:

- scaling a one-pixel image;
- using a two-sided texture with filtered sampling;
- applying fractional frame scale;
- placing lines on independently rounded half-pixel coordinates.

The border helper owns the textures and updates them whenever effective scale
changes.

#### Scale and display changes

Recalculate the physical-pixel unit and rerun registered layouts after:

- addon initialization;
- `DISPLAY_SIZE_CHANGED`;
- `UI_SCALE_CHANGED` when available on the client;
- fullscreen/windowed-mode changes;
- the addon's own scale setting changes;
- a frame is reparented to a differently scaled parent.

The refresh is deferred until the client has applied the new screen/UI scale,
then coalesced so a display change produces one relayout rather than one per
event.

#### Typography and icons

- Use `LibSharedMedia-3.0` as the global font registry.
- Expose one global addon font selection and apply it through shared FontObjects
  rather than setting font paths independently on every FontString.
- `FontManager` updates all shared FontObjects and requests one coalesced
  pixel-perfect relayout when the selected font changes.
- Use the stock client font `Fonts\\FRIZQT__.TTF` as the default.
- Register the stock default under a namespaced media key such as
  `CoA Buff: Default`; do not replace or shadow another addon's media key.
- If selected media disappears, fall back safely to the stock client font.
- Use a crisp client font with an outline only when contrast requires it.
- Avoid fractional font-object scaling.
- Numeric durations use a consistent width or alignment so rows do not shift.
- Icons use snapped square dimensions.
- Icon crops and texcoords are shared across the addon.
- Status colors supplement labels/icons; color alone never carries meaning.
- Text must remain readable against the semitransparent background over both
  bright and dark game scenes.

##### Stock default and external fonts

- Do not package Expressway or another third-party font by default.
- Use `Fonts\\FRIZQT__.TTF`, supplied by the game client, as the release
  default.
- Fonts registered by other addons through LibSharedMedia, including
  Expressway when available, remain user-selectable.
- Saved font choices reference the LibSharedMedia key rather than another
  addon's file path.
- If an externally registered font becomes unavailable, revert to
  `CoA Buff: Default` without an error.
- For locales whose glyphs are absent from a selected external font,
  automatically use a locale-capable stock client font.

#### Menus, tables, and hover stacks

- Dropdowns use the same black background and one-pixel border treatment.
- Effectiveness dividers are one physical pixel and labeled; they are not
  selectable menu entries.
- Matrix grid lines are one physical pixel and share coordinates to avoid
  doubled or blurred borders.
- Hover expansion does not rescale rows. It only changes visibility/layout
  using already-snapped dimensions.
- Expanded recipient rows align exactly with the persistent header/Greater
  button.
- Missing rows may use a one-pixel state accent in addition to the black outer
  border; the state accent must not replace the structural border.
- Equivalent-provider icons reserve a fixed snapped footprint for structural,
  local-identity, assignment, and selection rings so state changes never resize
  or shift the strip.

#### Visual configuration

Expose:

- panel opacity;
- addon layout scale;
- global LibSharedMedia font;
- font size;
- compact/comfortable row density;
- compact labels or full labels;
- expert icon-only mode;
- icon visibility;
- class-colored names;
- duration visibility;
- colorblind-friendly status palette.

The one-pixel structural border remains one physical pixel at every supported
layout scale and is not user-configurable in thickness.

## 10. Architecture

### 10.1 Library policy

The addon is self-contained. It must never depend on WeakAuras, ElvUI,
PallyPower, BuffReminders, or another installed addon to supply a library.
Required libraries are embedded under `Libs/` and loaded through `LibStub`, so
compatible newer copies already present in the client may be reused safely.

Every embedded library must:

- be verified on the target Ascension 3.3.5 client;
- have its exact version/revision recorded;
- include its upstream license and attribution;
- be loaded in a deterministic order;
- be smoke-tested both with and without other Ace-based addons enabled;
- be updated deliberately rather than copied opportunistically from whichever
  installed addon happens to contain it.

#### Required embedded libraries

| Library | Purpose |
|---|---|
| `LibStub` | Versioned library loading and coexistence with other addons. |
| `CallbackHandler-1.0` | Callback foundation required by Ace and talent libraries. |
| `AceAddon-3.0` | Addon/module lifecycle and clear module ownership. |
| `AceEvent-3.0` | Event registration and module-scoped event cleanup. |
| `AceTimer-3.0` | Hover-collapse delays, deferred pixel relayout, and throttled UI work. |
| `AceBucket-3.0` | Coalescing noisy roster, aura, talent, and display events. |
| `AceDB-3.0` | Versioned account/profile/character saved-variable organization. |
| `AceComm-3.0` | Versioned addon-channel transport and message fragmentation. |
| `ChatThrottleLib` | Traffic throttling used by AceComm to avoid addon-channel flooding. |
| `AceSerializer-3.0` | Safe transport representation for capability, assignment, and override payloads. |
| `LibSharedMedia-3.0` | Global font registration, selection, and interoperability with user-provided media. |

AceComm owns transport-level fragmentation below the client message limit.
The application protocol still owns revisions, authorization, validation, and
atomic snapshot replacement.

Deserialized data is untrusted input. Every message is schema-validated,
bounded in size/count, checked for a supported protocol version, and rejected
if sender authority is insufficient.

#### Specialization library

Use a small `SpecializationProvider` adapter with client-native CoA APIs first,
addon self-advertisement second, and an embedded CoA-verified
`LibGroupTalents-1.0`/`LibTalentQuery-1.0` fallback for remote units.

Requirements:

- provider class continues to come from `UnitClass`;
- specialization data influences recipient preference only;
- discover the local spec ID with `GetSpecialization`/
  `GetSpecializationInfo` when those Ascension shims are available;
- resolve CoA spec metadata through `C_ClassInfo.GetSpecInfoByID`, or enumerate
  it with `C_ClassInfo.GetAllSpecs` and `C_ClassInfo.GetSpecInfo`;
- derive role from CoA spec metadata flags such as `Tank` and `Healer` when the
  normal role API returns nil;
- when neither `Tank` nor `Healer` is set, use `DAMAGER`; `MeleeDPS` refines
  preference seeding but is not a separate group role;
- addon users self-advertise spec ID and name so remote clients do not need to
  inspect them to apply preferences;
- the addon references `LibGroupTalents-1.0` through `LibStub`, never through
  `WeakAuras.LGT`;
- a LibGroupTalents result such as `Seraphim` is matched against the enumerated
  CoA spec catalog and is valid even when role is unavailable;
- missing, delayed, or failed talent data falls back to class/role/global
  preferences;
- failure of the talent library cannot disable buff discovery, assignments,
  communications, or casting;
- the exact library revision must be tested against CoA custom talent trees and
  dual-spec changes before release.

This is a soft functional dependency: it is embedded for normal operation, but
the core remains usable if specialization detection fails.

#### Optional integrations

| Library | Policy |
|---|---|
| `LibDataBroker-1.1` | Optional launcher/status object. Never required to open the addon. |
| `LibDBIcon-1.0` | Optional minimap launcher controlled by a setting. |
| `LibDeflate` | Optional only for compact preference/catalog export strings; not required for live comms. |

Optional libraries are embedded only if their feature ships enabled in version
1. Otherwise, add them when the feature is implemented rather than carrying
unused code.

#### Libraries deliberately not used

- `AceGUI-3.0`: the interface is custom-built to satisfy the pixel-perfect
  visual system, dense matrix, secure-button, and hover-stack requirements.
- `AceConfigDialog-3.0`: a stock options renderer would create a second visual
  language. Options data may be structured internally, but rendering remains
  custom.
- `AceConsole-3.0`: the small command surface can use native slash-command
  registration.
- roster libraries: native party/raid APIs plus the addon's roster model are
  sufficient.
- range libraries: use the resolved spell with `IsSpellInRange` where the
  client supports it.
- aura-duration libraries: use the target client's `UnitBuff` results and
  explicit catalog fallbacks only when validated.
- WeakAuras spell cache: diagnostic/import source only, never a runtime
  dependency or proof that a spell is known.

#### Proposed embedded load order

```text
Libs/LibStub/LibStub.lua
Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua
Libs/AceAddon-3.0/AceAddon-3.0.lua
Libs/AceEvent-3.0/AceEvent-3.0.lua
Libs/AceTimer-3.0/AceTimer-3.0.lua
Libs/AceBucket-3.0/AceBucket-3.0.lua
Libs/AceDB-3.0/AceDB-3.0.lua
Libs/AceComm-3.0/ChatThrottleLib.lua
Libs/AceComm-3.0/AceComm-3.0.lua
Libs/AceSerializer-3.0/AceSerializer-3.0.lua
Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua
Libs/LibTalentQuery-1.0/LibTalentQuery-1.0.lua
Libs/LibGroupTalents-1.0/LibGroupTalents-1.0.lua
```

Use a single `embeds.xml` or `Libs.xml` manifest so the main TOC remains
readable. Optional integrations load after the required core and before addon
modules.

### 10.2 Module architecture

Recommended modules:

```text
Bestow.toc
Core.lua
Catalog.lua
PixelPerfect.lua
FontManager.lua
Spellbook.lua
Roster.lua
Specializations.lua
Auras.lua
Preferences.lua
Assignments.lua
Comms.lua
SecureCasting.lua
UI/Compact.lua
UI/Assignments.lua
UI/Preferences.lua
UI/Diagnostics.lua
```

Responsibilities:

- `Catalog`: static categories, families, IDs, priority tiers, aliases.
- `PixelPerfect`: physical-pixel measurement, snapping, shared backgrounds,
  borders, and display-scale relayout.
- `FontManager`: LibSharedMedia registration, global font selection, font
  object updates, locale fallback, and relayout after font-metric changes.
- `Spellbook`: local known-spell and highest-rank discovery.
- `Roster`: unit/GUID/name/class/spec state.
- `Auras`: category-equivalence and coverage evaluation.
- `Preferences`: bundled and user-edited recipient priorities.
- `Assignments`: pure deterministic assignment calculations.
- `Comms`: versioned capability/manual-state synchronization.
- `SecureCasting`: out-of-combat preparation of dynamic actions and frozen
  combat-safe Greater/recipient actions.
- `UI`: presentation and interaction only.

Assignment calculations should be pure functions where practical so they can be
tested outside the game client.

## 11. Saved-variable strategy

- Use one namespaced saved-variable root.
- Include a schema version.
- Separate account-wide preferences from character-specific panel state.
- Keep session assignments in a reload-safe session record keyed by a group
  fingerprint and player GUIDs where possible.
- Clear that session record when the player fully leaves/disbands the group.
- Do not carry player-specific assignments into a later group, even when the
  same names reappear.
- Store category/family keys, never localized spell names.
- Do not persist computed assignments outside the reload-safe current-session
  record.
- Provide migrations for every schema change.
- Provide a safe reset that preserves exported preference text.

## 12. Performance requirements

- Do not rescan the spellbook per category; build one known-spell index.
- Cache normalized aura-family lookup tables.
- Scan each unit's auras once per refresh.
- Throttle roster and aura events.
- Recalculate assignments only when inputs change.
- Avoid allocations in frequent aura update loops.
- Never perform all-pairs provider/recipient scans every frame.
- UI duration text can refresh every one or two seconds.

## 13. Error handling

- Missing or failed remote specialization data must degrade to
  class/role/global preferences; WeakAuras presence is irrelevant.
- Missing spell IDs must not prevent spell-name discovery.
- Unknown class/spec names are shown diagnostically and use fallback behavior.
- Malformed communications are ignored without Lua errors.
- Partial capability chunks expire rather than replacing good state.
- Protected attributes are never changed during combat.
- Roster unit-token churn must not cast on the wrong player.
- Stale providers are removed when they leave the group.

## 14. Initial catalog scope

The fresh implementation imports the ten existing category tables and known
rank IDs from `BuffReminders/CoA/Data.lua`.

Before a catalog entry is considered complete, verify:

- provider is a class;
- exact single name;
- exact Greater name;
- every rank ID in ascending rank order;
- actual buff aura name/ID;
- exact stat/effect magnitude per rank and verification status;
- fallback effectiveness tier used only when magnitude data is incomplete;
- duration;
- talent modifiers;
- whether single and Greater are both castable;
- whether the family is exclusive with the provider's other families.

Known unresolved examples include spell-cache false positives, missing single
or Greater variants, and unrelated duplicate-name spell IDs.

## 15. Testing strategy

### 15.1 Pure logic tests

- Exact effect-magnitude and talent-modifier resolution.
- Per-spec stat-weight utility calculations and `0..100` normalization.
- Survivability multiplier/bonus adjustments.
- Fallback provider-tier ordering when numeric data is missing.
- Stable tie breaking.
- Multiple providers of the same class.
- Independent and exclusive assignments coexisting for one provider/recipient.
- Manual assignment locking.
- Invalid manual assignment handling.
- One-category-per-provider constraint.
- One-provider-per-recipient/category-cell constraint.
- Displaced-provider reassignment to the next threshold-qualified category.
- Modal Greater selection from final recipient assignment counts.
- Recipient stat-weight/adjustment fallback order.
- Zero-value categories contribute no demand.
- Resetting an explicit selection to the computed optimum.
- Equal/stronger/lower coverage decisions.
- Protocol encode/decode and malformed payloads.

### 15.2 In-game solo tests

- Load with every non-Blizzard addon disabled.
- Load with common Ace-based addons enabled and verify library coexistence.
- Verify the embedded library revision set and license files in the packaged
  addon.
- Simulate unavailable specialization data and verify class/global fallbacks.
- Class detection.
- Spec detection absent/present.
- Highest-rank discovery.
- Single/Greater discovery.
- Reload persistence.
- Group-session assignment persistence and disband cleanup.
- Combat lockdown with every cast control disabled.
- Combat aura-watch updates for newly missing/expiring recipients.
- Compact panel durations.
- Pixel-perfect borders at every supported UI scale and resolution.
- Display-mode and UI-scale changes while panels are visible.
- Global LibSharedMedia font changes update every addon panel consistently.
- Missing selected media falls back without errors or unreadable text.
- Locale fallback supplies every required glyph.

### 15.3 Two-client tests

- Capability synchronization.
- Leader authority.
- Assistant authority.
- Party-wide edit authority.
- Remote assignment notification and provider reversal.
- Coordinator epoch/revision handoff.
- Category-header bulk-assignment synchronization.
- Individual override synchronization.
- Duplicate provider class.
- Addon/non-addon mixed group.
- Disconnect/reconnect.

### 15.4 Party tests

- Automatic per-recipient optimization.
- Greater default plus individual replacement.
- Greater selection by total assignment count.
- Existing external equivalent effects.
- Non-addon provisional provider followed by observed-aura recalculation.
- Dead/out-of-range/offline targets.
- Roster reorder without wrong secure targets.

### 15.5 Raid tests

- Greater reaches every subgroup.
- Multiple raid-wide effects coexist.
- Full forty-player scrolling.
- Assignment convergence on every client.
- Communication chunking.
- Raid leader/assistant changes.
- Combat transitions into monitoring-only mode.

### 15.6 Visual acceptance tests

Render or capture every primary panel at:

- 100%, 90%, 80%, and 70% client UI scale where supported;
- 1920×1080;
- 2560×1440;
- 3440×1440;
- one low-resolution 4:3 or 5:4 mode supported by the client;
- windowed and fullscreen modes.

At 100% image inspection:

- every structural border occupies exactly one physical pixel;
- horizontal and vertical borders have equal apparent weight;
- no edge alternates between one and two pixels;
- no border becomes gray from texture filtering;
- matrix intersections do not produce unintended two-pixel seams;
- text and icons remain aligned to snapped row bounds;
- hover expansion does not shift the persistent header;
- equivalent-provider icons remain in deterministic priority order;
- black structural, white local-caster, colored assignment, and selection
  markers remain individually recognizable in every valid combination;
- adding/removing an icon marker does not resize or shift the priority strip;
- compact rows retain readable names, category labels, durations, and icons
  without overlap;
- long player names truncate consistently without changing font size;
- a forty-player matrix remains navigable without covering an unreasonable
  portion of the screen;
- compact, standard, and comfortable density modes preserve the same
  assignment meaning;
- semitransparent backgrounds preserve readable contrast over bright and dark
  scenes.
- The stock default remains readable in compact rows and dense matrix cells.

## 16. Acceptance criteria for version 1

- The packaged addon is self-contained and loads without WeakAuras or any other
  third-party addon installed.
- Required embedded libraries have pinned revisions, included licenses, and no
  duplicate-library conflicts in the target client.
- One LibSharedMedia global font setting controls every addon panel.
- Every packaged font has documented redistribution/application-embedding
  rights and included attribution.
- Failure of specialization detection degrades preferences without disabling
  core buff coordination.
- No vanilla class or Paladin blessing logic participates in decisions.
- Every configured provider resolves through CoA class plus verified spellbook
  capability.
- Greater assignments are raid-wide.
- Each provider has at most one Greater assignment.
- Individual single-target overrides work and persist.
- Session overrides survive reload during the same group and clear after the
  group disbands.
- Multiple same-class providers work.
- Highest known ranks are cast.
- Equal/stronger equivalent auras suppress reminders.
- Automatic assignment preserves configured relevance and curated provider
  priority.
- Recipient spec preferences are editable.
- All assignment changes synchronize with authority checks.
- Compact and assignment panels work for a forty-player raid.
- No protected-action errors occur in combat.
- The prepared Greater and fixed recipient cast controls remain clickable in
  combat without protected-action errors; dynamic `Buff Next` remains
  unavailable while aura monitoring stays live.
- The diagnostics dump is sufficient to report missing spell/class/spec data.
- All addon panels use the shared pixel-perfect routine.
- Structural borders remain one physical pixel at supported resolutions,
  client UI scales, and addon layout scales.
- Panels use the shared semitransparent-black visual tokens and remain readable
  against representative game backgrounds.

## 17. Explicit non-goals for version 1

- Reusing PallyPower's vanilla class/blessing matrix.
- Depending on WeakAuras for normal operation.
- Sending instructions to or expecting acknowledgements from players who do
  not run the addon; their provisional responsibility is planning state only.
- Automatically changing assignments during combat.
- Encounter-specific automatic profiles.
- Perfect talent-aware in-tier ordering before the relevant talent APIs are
  verified.
- Unique non-equivalent class buffs outside the shared mutually exclusive
  family system.
- Pets as buff recipients.
- Battleground and arena groups.
- Assignment templates that persist across group sessions.
- Reagent tracking; the tracked CoA Greater families do not require reagents.

## 18. Implementation sequence

1. Create the clean addon scaffold and catalog schema.
2. Import and validate current category/family data.
3. Implement one-pass spellbook capability discovery.
4. Implement aura equivalence and coverage.
5. Implement roster/class/spec discovery.
6. Implement pure Greater and party-override assignment functions.
7. Add versioned communications and authority.
8. Add the compact secure cast panel.
9. Add the raid-wide assignment panel.
10. Add individual overrides and preference editing.
11. Add diagnostics and export.
12. Complete two-client, party, and raid acceptance tests.
