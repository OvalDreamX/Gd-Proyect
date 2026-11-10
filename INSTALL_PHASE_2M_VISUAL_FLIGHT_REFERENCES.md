# Space Trucker — Phase 2M: Flight-path marker and test-range visuals

## Install

1. Back up the current working **Phase 2L** project.
2. Extract this ZIP directly into the existing Godot project root.
3. Allow the included files to overwrite existing files.
4. Open the project in **Godot 4.7.2 Stable** and run the main scene with F5.

This is an incremental overwrite package. It assumes the existing Phase 2L project already contains the ship, Phase 2L atmospheric model, FCC, flight HUD manager, display settings, player scene and supporting resources. It does not replace those systems.

## Cockpit HUD: flight-path marker

A cyan flight-path marker (FPV) is drawn inside the attitude display. It is based on the ship's current world-space linear velocity transformed into ship-local coordinates, so it shows actual motion relative to the ground/test range rather than simply following the ship's nose.

- Marker centered on the nose reference: velocity is aligned with the ship's forward axis.
- Marker below the nose reference: the ship is pitched above its current direction of travel (positive angle of attack).
- Marker above the nose reference: the ship is travelling upward relative to its nose reference.
- Marker left/right: lateral drift or sideslip.
- The marker hides below 2 m/s and when the ship is not moving meaningfully forward. It is clamped to the HUD's forward field of view at ±23 degrees.

This is intentionally a flight-path/velocity marker, not a commanded propulsion-vector indicator. It is display-only and does not change forces or control behavior.

## HUD visual refinement

- The complete cockpit symbology is reduced to 90% of its previous reference size, independently of the user's existing HUD-scale setting.
- Fonts, bars, ladder strokes, bank marks, reference symbol and input indicators are smaller or thinner.
- The original positions and layout hierarchy are retained to avoid disturbing the instrument arrangement.

## Test-range environment

The existing test-range scene now has:

- A 1,000 m × 1,000 m textured ground plane generated from seeded FastNoiseLite/NoiseTexture2D resources at runtime. No external texture assets are required.
- A 20 m survey grid, with the center axes omitted to keep the landing pad clear.
- A dark approach strip with edge lines, centerline dashes, threshold markings and 25/50/75 m visual reference marks.
- A higher-contrast H and perimeter marking on the existing 14 m physical landing pad.
- Four collision beacons along the range boundary.
- Distant faceted ridge silhouettes and a sky-colored background for a more readable horizon.
- A ground arrow showing the configured mean wind-flow direction.

The central 14 m landing-pad opening in the ground collision remains intact. The four ground collision strips were expanded to meet the new visual ground extent without putting a duplicate collider underneath the pad. Distant ridges are visual backdrops only; the close range beacons have collision.

No ship mass, center of mass, collision shape, vane position, atmospheric coefficients, FCC gains, wind values or flight forces are changed in this phase.

## Tests

Run from the project root:

```powershell
& $godot --headless --path . --script res://tests/flight_path_marker_test.gd
& $godot --headless --path . --script res://tests/test_range_environment_test.gd
```

Also rerun the existing regression checks:

```powershell
& $godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/display_settings_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
```

Set `$godot` to the full path of the Godot 4.7.2 executable before running these commands, as in previous phase instructions.

## Scope boundary

This is a HUD and test-range presentation update. It does not change the flight model. The ground is flat in the operational area; the grid and approach lane are visual measurements, not terrain deformation. The distant ridge shapes are intentionally outside the normal test area. This keeps takeoff, glide and landing results comparable with the previous test range while adding enough visual scale and landmarks to judge attitude, drift, altitude and closure rate.

The package has been statically inspected and its ZIP integrity checked. The build environment does not contain a Godot 4.7.2 executable, so GDScript parsing, automated tests and in-engine visual inspection must still be performed in the target editor/runtime.
