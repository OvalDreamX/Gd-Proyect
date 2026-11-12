# Space Trucker — Stability Pass 2 Overwrite

Extract this ZIP into the existing Godot project root and allow included paths to overwrite matching files. This is a focused overwrite package, not a full project archive.

## Implemented

- Corrected HUD letterbox translation so the margin is expressed in viewport pixels before the scaled draw transform is applied.
- Normalized the lower flight-data heading readout through the shared 000–359° formatter.
- Invalid, undersized, or off-monitor saved window sizes now select the largest supported preset fitting the usable display area. If the display itself is smaller than 800×450, the explicit minimum-window constraint is retained.
- Unexpected player-node exit releases the ship's pilot claim and restores exterior/interior visibility.
- Added regression checks for HUD alignment/heading, resolution fallback, and pilot replacement after exit.

## Tests

Run from the project root with Godot 4.7.2:

```text
godot --headless --path . --script res://tests/flight_hud_layout_test.gd
godot --headless --path . --script res://tests/display_settings_test.gd
godot --headless --path . --script res://tests/ship_pilot_cleanup_test.gd
```

These tests were not executed during package preparation; no runtime pass is claimed.

## Scope

Only listed scripts and tests are changed/added. No scenes, project settings, resources, GDD files, or existing UID sidecars are changed.
