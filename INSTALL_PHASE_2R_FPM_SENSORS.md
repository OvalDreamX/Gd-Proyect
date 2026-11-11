# Phase 2R — F-16-style flight-path marker and sensor layer

## Install

1. Close the running game/editor.
2. Extract this ZIP into the Godot project root (the folder containing `project.godot`).
3. Allow the files to overwrite their matching paths.
4. Open the project in Godot 4.7.2 and let it finish importing.

This is an overwrite-only package. It contains only files changed for Phase 2R and retains the Phase 2Q HUD/camera behavior.

## What changed

### Flight-path marker (FPM)

- The FPM now represents the ship's **inertial velocity vector** (world-space linear velocity), not its nose direction and not its air-relative velocity.
- The projection uses the active cockpit camera basis and the camera's actual vertical FOV. This gives it a true perspective projection rather than a fixed pixels-per-degree approximation.
- A velocity vector aligned with the boresight is centered on the boresight. The previous 12-pixel vertical offset has been removed. Rearward vectors use their lateral/vertical components to choose an edge; a directly aft vector is indicated at the bottom center.
- When the vector leaves the central HUD field, its marker moves to the first intersection of its projected direction ray with the HUD boundary (rather than being clamped independently to a corner) and changes to a same-size circle with an overlaid X, following the F-16 convention.
- A nearly stationary ship does not display a useful velocity vector, so the FPM is suppressed below 2 m/s.

### Separate instrument/sensor layer

- `FlightSensorSuite` is a ship-owned node between physical simulation state and the HUD.
- It publishes attitude, heading, inertial velocity, air-relative velocity/speed, local altitude, vertical speed, and independent validity flags.
- The normal HUD reads these instrument fields and does not calculate flight measurements from the rigid body or atmosphere model.
- The controller publishes a fresh instrument snapshot with the existing 30 Hz HUD telemetry update. Physics integration and force calculations are unchanged.
- The FPM uses the inertial world-velocity vector. The speed readout uses air-relative speed when an atmosphere is active and inertial speed in vacuum.
- Sensor channels can be independently invalidated later for damage, drift, lag, or sensor failures.

## Tests

Run these from PowerShell in the project root. Reuse the `$godot` executable variable configured during earlier phases:

```powershell
& $godot --headless --path . --script res://tests/flight_path_marker_test.gd
& $godot --headless --path . --script res://tests/flight_sensor_suite_test.gd
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
```

The package was statically inspected and its ZIP integrity checked. Godot runtime/parser tests were not run in the build environment, so run the commands above before treating the phase as validated.
