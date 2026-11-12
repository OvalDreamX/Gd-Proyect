# Space Trucker — Ship Modding Phase 1

## Contents

- `scripts/ship_definition.gd` — typed runtime definition container.
- `scripts/ship_definition_loader.gd` — JSON parser and schema-v1 validation.
- `data/ships/prototype_freighter/ship.json` — reference configuration for the current prototype.
- `tests/ship_definition_loader_test.gd` — parser and validation regression tests.
- `docs/SHIP_MODDING.md` — format and implementation roadmap.

## Install

Extract this ZIP into the Godot project root and allow the files to merge. No existing files are overwritten. Do not delete any files or `.gd.uid` sidecars.

## Test

```sh
godot --headless --path . --script res://tests/ship_definition_loader_test.gd
```

This package intentionally does not change the existing ship scene or simulation scripts. It establishes the data contract before runtime integration, reducing collision risk with the ground-effect work and avoiding a half-converted ship.
