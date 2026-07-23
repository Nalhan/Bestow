# Bestow

Bestow coordinates mutually exclusive class buffs for Ascension's Conquest
of Azeroth realm on the WoW 3.3.5 client.

It discovers the effects each provider can cast, evaluates recipient
specialization preferences, assigns raid-wide Greater buffs and party
overrides, and presents the local caster with a secure one-click action queue.

## Current features

- all ten tracked shared-effect categories;
- all registered Conquest of Azeroth provider classes;
- highest-known spell-rank discovery;
- stronger/equivalent aura suppression;
- automatic party assignments and raid-wide Greater assignments;
- synchronized provider, cell, and Greater overrides;
- compact secure casting panel and group assignment matrix;
- combat-safe aura monitoring;
- LibSharedMedia font selection and pixel-aligned rendering.

The implementation is currently alpha software. See [TESTING.md](TESTING.md)
for the active testing procedure and [docs/SPEC.md](docs/SPEC.md) for the full
behavioral specification.

## Installation

1. Download a packaged release.
2. Extract the contained `Bestow` directory into `Interface/AddOns`.
3. Restart the client and enable **Bestow** at character selection.

The directory layout must be:

```text
Interface/
└── AddOns/
    └── Bestow/
        └── Bestow.toc
```

## Commands

```text
/bestow
/bestow assignments
/bestow config
/bestow dump
/bestow rescan
```

The legacy `/cbc` and `/coabuffs` aliases remain available during alpha.

## Development

Validate the source tree:

```text
python scripts/validate.py
```

Build a release archive:

```text
python scripts/package.py --version 0.1.0-alpha
```

The generated ZIP contains one top-level `Bestow/` directory and is written
to `dist/`.
