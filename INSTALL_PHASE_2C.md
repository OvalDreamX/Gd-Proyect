# Space Trucker — Phase 2C overwrite files

Target: Godot 4.7.2 Stable

## Install

1. Make a backup or commit your current working project.
2. Extract this ZIP directly into your existing Godot project folder.
3. Allow the six files in `scripts/` and `scenes/` to overwrite the existing versions.
4. Reopen the project in Godot and run `scenes/test_range.tscn`.

No `git apply` command is required. No new InputMap actions or external dependencies are required.

## Included replacement files

- `scripts/ship_camera_controller.gd` — external-camera scroll zoom.
- `scripts/ship_flight_controller.gd` — routes wheel events and publishes rigid-body telemetry at 10 Hz.
- `scripts/ship_interactable.gd` — enables normal rigid-body integration for baseline validation.
- `scripts/flight_hud.gd` — displays rigid-body diagnostics.
- `scenes/ship.tscn` — enables natural sleeping on the ship body.
- `scenes/test_range.tscn` — adds collision to the landing pad and clears overlapping ground collision beneath it.

## Scope

This milestone validates the free rigid-body baseline only. No repulsorlift forces, torques, vane simulation, FCC or aerodynamic forces are applied. The ship should settle under gravity onto the landing pad and eventually sleep.

## Acceptance checks

- External camera wheel zoom works and remains within 4–24 m.
- Cockpit view is unaffected by the wheel.
- The ship falls onto the pad, settles and eventually sleeps.
- F3 shows position, linear/angular velocity, body state and center-of-mass mode.
- Repulsorlift controls still do not move the ship.
