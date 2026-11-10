# Space Trucker — Phase 2J: Atmospheric Drag and Flight-Regime Foundation

## Install

1. Back up the working project folder.
2. Extract this ZIP directly into the existing Godot project root — the folder containing `project.godot`.
3. Allow the included files to overwrite their matching files.
4. Open the project in **Godot 4.7.2 Stable** and run the main scene with F5.

This is an incremental overwrite package. It intentionally does not replace `project.godot`, the display settings, vane resources or unrelated scenes. It assumes the Phase 2I project is installed, and that the Phase 2E/2F dependencies remain in place:

- `scripts/ship_interactable.gd`
- `scripts/ship_camera_controller.gd`
- `scripts/repulsorlift_system.gd`
- `scripts/vane_controller.gd`
- `scripts/vane_definition.gd`
- `scripts/flight_control_computer.gd`
- `scripts/force_vector_debug.gd`
- `scripts/display_settings.gd`
- Existing vane Resources under `data/vanes/`
- Existing player and test-range scenes

## What changes

### 1. Normal flight-sim pitch convention

Mouse pitch is inverted at the input boundary only:

- Move the mouse **up** (push the virtual stick forward): nose-down command.
- Move the mouse **down** (pull the virtual stick back): nose-up command.

The FCC, vane force directions and physical pitch sign convention are unchanged. The cockpit virtual-stick marker now moves in the same direction as the mouse input. Roll and yaw are unchanged.

### 2. Separate atmospheric drag subsystem

A new `AtmosphericFlightModel` node is added to the ship scene. It applies drag independently of the pilot, FCC and repulsorlift field, so a ship that has been accelerated continues to experience drag even when the player is not seated or the field is off.

The initial model uses:

- Exponential density falloff with altitude: `rho = rho0 * exp(-h / H)`.
- Air-relative velocity: ship velocity minus the configured local wind velocity.
- Quadratic drag: `F = -0.5 * rho * Cd * A * |v_rel| * v_rel`.
- Projected box area based on the ship's local hull dimensions and current attitude.
- Central force application, avoiding artificial aerodynamic torque from this first-order drag model.

The starting hull dimensions match the current prototype collision box: 3.6 × 1.5 × 5.2 m. Initial density, scale-height and drag-coefficient values are exposed in the Inspector. These are tuning placeholders, not final ship performance values.

### 3. Atmosphere reference and space-like tests

The atmosphere reference position is a world-space point defining local altitude zero. The current flat test range uses the ground plane at world Y = 0. Altitude is sampled at the ship body's origin, which is sufficient for this compact hull and avoids relying on `RigidBody3D.center_of_mass` in automatic-COM mode. The model derives local up from the ship's gravity direction, falling back to world up if gravity is zero.

For a future vacuum/orbital test scene, set `atmosphere_enabled` to false or set sea-level density to zero. Each local environment can later provide its own reference point, density profile and wind.

### 4. F3 diagnostics

F3 now includes atmospheric enable state, local altitude above the reference point, density, airspeed, wind, relative-air velocity, projected hull area, drag coefficient and applied drag force. The normal cockpit HUD remains unchanged apart from the corrected pitch-stick marker.

## Explicit scope boundary

This phase adds **drag only**. It does not implement particle-shield lift, angle-of-attack limits, an FCC aerodynamic envelope, wind variation by altitude, heating, shield power consumption, terrain-relative altitude, landing assistance or planetary approach logic. Those need separate tuning and acceptance tests. The drag model is deliberately isolated from the repulsorlift force allocator.

## Tests

Run these from PowerShell in the project root. Replace the executable path with the location of your Godot 4.7.2 executable:

```powershell
$godot = "C:\Path\To\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/display_settings_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
```

Run each command separately. The Phase 2J test covers pitch-input direction, density falloff, projected area, quadratic drag, zero-density behavior and a live `RigidBody3D` drag smoke test. The remaining tests protect the previous HUD, display, FCC and vane-force milestones.

## Manual validation

1. Confirm that moving the mouse upward commands nose-down and moving it downward commands nose-up. Confirm that the virtual-stick dot moves with the mouse.
2. Accelerate in the test range, release the propulsion input and observe that speed gradually decays instead of remaining perfectly constant.
3. Repeat at higher altitude and verify that drag weakens as density falls.
4. Rotate the ship and compare the projected area/drag response in F3.
5. Set `AtmosphericFlightModel.atmosphere_enabled` to false in the Inspector and verify that the ship coasts without atmospheric drag. Repulsorlift control should remain unchanged.
6. Repeat the existing hover, vectoring, FCC on/off, damage and display-settings checks.

## Validation status

The package was statically reviewed for scene wiring, script references, mathematical edge cases and archive structure. The build environment does not contain Godot 4.7.2, so GDScript parsing, automated runtime tests and in-engine tuning have **not** been performed here. Treat the drag coefficient and density profile as provisional until the included test and manual flight checks pass on the target installation.
