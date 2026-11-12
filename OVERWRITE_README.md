# Space Trucker — Ground Effect Implementation

This overwrite package implements the first in-game repulsorlift ground-effect pass and connects it to the prototype ship JSON.

## Files included

- `scripts/repulsorlift_ground_effect_system.gd` — specialized repulsorlift system with near-surface force gain.
- `scripts/ship_definition_loader.gd` — stricter validation for the ground-effect JSON section.
- `data/ships/prototype_freighter/ship.json` — complete prototype definition with ground-effect settings.
- `scenes/ship_ground_effect.tscn` — inherited ship variant that enables the specialized system.
- `scenes/test_range.tscn` — switches the test range to the ground-effect ship variant.
- `tests/repulsorlift_ground_effect_test.gd` — math and JSON tests.
- `docs/GROUND_EFFECT.md` — behaviour, configuration, and manual test plan.

## Install

1. Extract this ZIP into the Godot project root.
2. Allow folder merging and overwrite the listed existing files when prompted.
3. Do not delete any files.
4. Keep existing `.gd.uid` sidecars; Godot will regenerate/update them if necessary.
5. Open the project in Godot and let the filesystem scan finish.

## Tests

Run:

```sh
godot --headless --path . --script res://tests/repulsorlift_ground_effect_test.gd
```

Also run the existing loader tests:

```sh
godot --headless --path . --script res://tests/ship_definition_loader_test.gd
```

The package was checked for ZIP integrity and JSON syntax. Godot is not installed in the build environment, so GDScript parsing and runtime behaviour have **not** been verified here. Manual in-engine testing is required.

## Parser hotfix

This package includes a correction to the indentation of the `minimum_valid_probes` validation block in `scripts/ship_definition_loader.gd`. The prior ZIP had one extra indentation level on that `if` statement, causing the loader parse failure and the downstream unresolved `ShipDefinitionLoader` error.
