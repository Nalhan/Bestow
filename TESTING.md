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
