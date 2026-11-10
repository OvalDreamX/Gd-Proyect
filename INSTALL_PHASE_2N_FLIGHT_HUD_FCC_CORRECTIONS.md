# Space Trucker — Phase 2N: Flight HUD and FCC Corrections

## Scope

This increment corrects the HUD's world/view references and separates main-vector translation output from maneuvering authority. It does not alter the atmospheric drag or shield-lift equations, coefficients, wind, or density profile.

## HUD

- Removes the text label beside the flight-path symbol.
- Keeps the HUD screen-anchored while projecting the attitude ladder and flight-path vector into the active cockpit-camera view. Head-look therefore moves the world cues relative to the fixed HUD center instead of detaching them from the visible horizon.
- Uses air-relative velocity for the flight-path symbol and airspeed while atmospheric density is meaningful; uses inertial velocity in vacuum.
- Uses the atmospheric model's local-up vector for altitude and vertical speed instead of assuming world Y is always vertical. The altitude datum remains the current local atmosphere reference point; it is not yet terrain/radar altitude.

## FCC / repulsorlift allocation

- Main-vector translation remains proportional to the W/S output.
- When the field is ONLINE, pitch, roll and yaw controls remain available even when the main-vector output is zero. FIELD OFF still removes all repulsorlift forces.
- Maneuver force has a baseline independent of main-vector throttle and receives up to a 20% linear reserve boost as main-vector output approaches zero. The boost is capped and does not change maximum translational output.
- Assisted FCC mode may redistribute 50% of a vane group's damaged-output deficit, but only into healthy spare capacity. A healthy vane is capped at 1.20× nominal. Damage therefore still reduces total authority and shifts the group's effective application point. Direct-vane mode does not use FCC redistribution.
- The current proportional rate controller, input curve, deadzone, angular-rate targets and aerodynamic force model are otherwise unchanged.

## Tests

Run from the project root with Godot 4.7.2 Stable:

```powershell
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/flight_path_marker_test.gd
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& $godot --headless --path . --script res://tests/display_settings_test.gd
& $godot --headless --path . --script res://tests/test_range_environment_test.gd
```

Manual checks: with the field ONLINE and W/S at zero, verify pitch/roll/yaw still rotate the ship while there is no main-vector translation. Compare maneuver response at zero and full main-vector output; zero should be about 20% stronger, not dramatically stronger. Switch the field OFF and verify all repulsorlift control ceases. Damage one front vane to 50%; inspect F3 to confirm limited redistribution and a remaining offset in the force application point. Turn the cockpit camera with RMB and verify the central horizon/flight-path cues remain screen-anchored but stay aligned with the visible world.

## Backup

The patcher creates both a pre-change rollback ZIP and a corrected Phase 2N checkpoint ZIP under `backups/`. Keep the corrected checkpoint before beginning planet/space environment work.

## Validation status

This patcher validates exact source patterns before writing, and runs no engine process. GDScript parsing, the included automated tests and the in-engine flight feel still need to be checked with the project's Godot 4.7.2 installation.
