# Bestow alpha testing

The client must be fully restarted once after adding this new addon folder.
`/reload` cannot discover addon filenames that were not present at process
start.

Disable the old `BuffReminders` CoA port while testing so both addons do not
recommend or cast competing buffs.

## First load

1. Enable `Bestow` at character selection.
2. Log in out of combat.
3. Run `/bestow rescan`.
4. Run `/bestow dump` and copy the diagnostic text if capabilities are missing.
5. Open `/bestow assignments` in a party or raid.

The compact panel is visible by default. `A` opens the assignment matrix and
`D` opens diagnostics.

Run `/bestow config` to switch the recipient stack between Hover, Always
expanded, and Always collapsed; configure automatic missing/expiring rows;
toggle specialization names; or choose the global LibSharedMedia font.

## Interaction

- Click the large compact button repeatedly to perform the next available
  action. The queue advances only after the expected aura is observed.
- Mouse-wheel a recipient row to cycle only the local caster's available
  effect families.
- In the assignment matrix, left-click a header or cell to select a provider.
- Right-click a header or cell to reset its explicit selection.
- In combat, buttons intentionally perform no casts; the panel remains an aura
  monitor.

## Preference testing

Use:

```text
/bestow pref category essential
/bestow pref category useful
/bestow pref category marginal
/bestow pref category none
```

For example:

```text
/bestow pref spellPower essential
```

## Stat-weight synchronization

1. Join the same party with two Bestow clients using the same stat-weight source.
2. Edit one current-spec weight on client A.
3. Open diagnostics on client B and confirm A reports
   `weights=advertised` with a revision and checksum.
4. Confirm client B's valuation and automatic assignments for A change, while
   another player with the same specialization continues using their own
   advertisement or the bundled profile.
5. Reset the edited row or use Reset All and confirm the revision changes and
   client B returns to the bundled value.
6. Temporarily test clients with different stat-weight source hashes and
   confirm diagnostics reports `weights=source-mismatch`; the receiver must
   ignore incompatible deltas.
7. Set the `mp5` field above zero and confirm MP5 effects gain
   raw utility in diagnostics. Reset it to zero and confirm pure-MP5 effects
   return to the legacy preference fallback when they have no curated bonus.
8. Open the `Buff Scores` view, navigate through all categories, and confirm
   each available single/Greater form shows `base+bonus=final`. Hover each
   family row and confirm it shows the spell tooltip for the highest known
   Greater rank, falling back to the highest Single rank when no Greater form
   exists.
9. Confirm Stamina families initially show a stock bonus of `10` and Cost
   Reduction families show `20`. Edit one bonus on client A and verify client B
   uses the advertised value only when scoring A; reset it and confirm both
   clients return to the appropriate stock value.
10. On every specialization belonging to Necromancer, Pyromancer, Cultist,
    Starcaller, Sun Cleric, Tinkerer, Runemaster, Primalist, Venomancer,
    Chronomancer, Stormbringer, Witch Doctor, or Witch Hunter, browse to Mana
    Regeneration and verify pure-MP5 families show a stock bonus of `10`.
    Verify the same rows show `0` on a class outside that list. Devotion of
    Grace combines its MP5 and Cost Reduction components, producing `30` for
    mana users and `20` for other classes.
11. Confirm every rank carrying Arcane, Fire, Frost, Nature, Shadow, or all
    resistances receives `+2` additional stock bonus points. In particular,
    Mark of Rivendare should show `12` and Mark of Zeliek should show `22`;
    resistance families without another stock adjustment should show `2`.

## Isolation

Runtime errors intentionally propagate to the normal client error handler so
BugSack records the original stack trace and locals without an addon wrapper.

If a file must be temporarily excluded, comment its line in
`Bestow.toc`. The load order is intentionally modular:

1. data;
2. discovery and roster;
3. aura/assignment core;
4. communications;
5. pixel/UI modules.

Blood Mage uses the client token `SONOFARUGAL`. Sanguinary Offering and
Bloodsoaked Offering should appear as active capabilities for that class.

Run `/bestow tooltips` out of combat to open a copyable TSV containing the
client tooltip for every spell ID in the catalog. Save the selected text as a
UTF-8 `.tsv` file and process it with:

```text
python scripts\extract_buff_effects.py --tooltip-tsv <path>
```
