# Phase 2U — Thermal, cargo and FCC polish

This is an overwrite-only incremental update for the Phase 2T project based on repository commit `f8931b4` (`Up to 2T`).

Extract the ZIP into the folder containing `project.godot` and allow the included files to overwrite matching paths. No installer or patcher is used.

## Changes

### Thermal simulation
- Advances once per repulsorlift physics update while the field is online, offline, or the rigid body is frozen.
- Offline vanes cool toward the current ambient temperature and do not accrue operating wear.
- Thermal load is calculated from the main-vector allocation plus the per-vane maneuver contributions produced that tick.
- Invalid/zero time-step fallback uses the configured engine physics tick rate.

### Main-force application and cargo COM
- The main-field resultant is applied at the fixed hull reference datum (rigid-body origin), not through the moving COM.
- A shifted cargo COM therefore produces an actual force moment. Gravity itself is not treated as a torque source.
- Cargo derives dry mass and payload capacity from the parent ship.
- The F4 cargo slider follows the ship's payload limit.

### FCC trim
- Assisted mode is now bounded PI rate control with anti-windup.
- Integral trim is cleared when the field/control authority is unavailable or assistance is disabled.
- Existing P gain, output cap, direct-vane mode, input shaping and partial vane redistribution are preserved.
- The FCC remains a rate controller, not an attitude-hold autopilot. Saturation and residual rotation are expected when disturbance torque exceeds available authority.

### HUD feedback
- F4 no longer describes cargo offset as a gravity-generated torque or promises perfect attitude compensation.
- F3 reports trim state, integral output, configured limits and saturation.

## Tests

Run from PowerShell in the project root:

```powershell
& $godot --headless --path . --script res://tests/vane_thermal_model_test.gd
& $godot --headless --path . --script res://tests/cargo_system_test.gd
& $godot --headless --path . --script res://tests/flight_control_trim_test.gd
& $godot --headless --path . --script res://tests/flight_hud_phase2u_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
```

Also run the existing sensor, FPM, HUD-layout and display settings tests. Manually test:
1. Start cold, run at 30–40% power, and observe warmup.
2. Shut the field down and confirm the vanes cool while F3 remains open.
3. Load `PORT_HEAVY`, inspect the COM and F3 trim/saturation status, then attempt hover.
4. Repeat with centered and nose-heavy cargo.
5. Open F4 and verify flight inputs remain blocked until the panel closes.

Godot runtime/parser tests must be run in the target Godot 4.7.2 installation. Source-level inspection or ZIP integrity checks do not substitute for runtime validation.
