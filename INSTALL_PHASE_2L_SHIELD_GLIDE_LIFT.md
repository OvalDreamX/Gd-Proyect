# Space Trucker — Phase 2L: Shield-Generated Glide Lift

## Installation

1. Back up the current **Phase 2K** project folder.
2. Extract this ZIP directly into the existing Godot project root.
3. Allow the included files to overwrite the existing files.
4. Open the project in **Godot 4.7.2 Stable**.

This is an incremental update to Phase 2K. It intentionally does not replace `project.godot`, `scenes/ship.tscn`, the FCC, vane definitions or display settings. It expects the existing `AtmosphericFlightModel` node on the ship to remain connected to `scripts/atmospheric_flight_model.gd`.

## What changed

### Shield-generated lifting-body force

The existing `AtmosphericFlightModel` now calculates and applies two independent environmental forces using the same air-density and air-relative-velocity sample:

- **Drag:** continues to oppose air-relative velocity.
- **Glide lift:** represents the fictional particle-shield lifting-body effect. It is not conventional wing aerodynamics and does not require physical wings.

The lift model uses:

- Air density from the existing exponential atmosphere profile.
- Air-relative speed, including the configured wind and coherent turbulence.
- Signed angle of attack between ship-forward and the air-relative flight path.
- A ship-up direction projected onto the plane perpendicular to airflow.
- An effective shield lift area, lift coefficient and shield-effectiveness factor.
- A smooth low-speed gate and a bounded post-stall reduction.

The model applies a continuous central force during `_physics_process`. It does not modify the ship transform, inject impulses, depend on the repulsorlift field being online, or apply torque through the vane allocator.

### Initial tuning values

These values are deliberately provisional and exposed in the Inspector under **Shield-generated glide lift**:

| Setting | Initial value | Purpose |
|---|---:|---|
| Glide lift enabled | On | Master test switch |
| Effective lift area | 36 m² | Effective field area, not literal wing surface |
| Shield lift effectiveness | 100% | Placeholder for future shield condition/power |
| Maximum lift coefficient | 1.10 | Maximum coefficient before post-stall fade |
| Stall angle | 20° | Angle at which the coefficient reaches its maximum |
| Minimum effective airspeed | 5 m/s | Start of the smooth low-speed gate |
| Full effective airspeed | 18 m/s | Speed at which the low-speed gate reaches 100% |

These are not final balance values. At 20 m/s and 10° positive angle of attack, the current parameters produce roughly 4.8 kN of lift at sea-level density. At 40 m/s, the force is approximately four times greater at the same angle and density, before coefficient saturation.

### F3 diagnostics

The atmosphere section now includes a **SHIELD / GLIDE LIFT** subsection with:

- Enabled state, shield effectiveness and effective field area.
- Angle of attack and current lift coefficient.
- Low-speed gate and forward-flow factor.
- Stall angle and configured maximum lift coefficient.
- Lift force vector, magnitude and direction.

The standard cockpit HUD remains unchanged.

## How to test in the current test range

For a controlled first test:

1. Start the ship and get it moving forward with the main vector near 0°.
2. Reach a steady forward airspeed; 40–60 m/s is a useful initial range.
3. Reduce repulsorlift power or switch the field off once safe altitude and forward speed are established.
4. Hold a modest nose-up attitude, approximately 5–10°, and observe the vertical velocity and F3 glide-lift telemetry.
5. Compare with the ship at approximately 0° angle of attack. The lift coefficient should approach zero.
6. Try a nose-down attitude. Lift should become negative.
7. Reduce speed. Lift should diminish with dynamic pressure and fade near the configured low-speed gate.
8. Turn off **Shield glide lift enabled** in the Inspector and repeat. Drag should remain, but the extra lift should disappear.

Do not evaluate the first pass as a final flight-handling tune. The current wind, drag, shield-area and coefficient values are test parameters.

## Tests

Run from the project root using the Godot 4.7.2 executable:

```powershell
& $godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/display_settings_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
```

The updated atmosphere test adds checks for AoA sign, lift direction, perpendicular lift, the square-speed relationship, post-stall attenuation, disabled shield lift, zero-density/vacuum behavior, low-speed suppression, rearward airflow rejection and a live rigid-body smoke test with the repulsorlift system absent.

## Scope boundary

This phase does not add atmospheric control-envelope logic to the FCC, shield power consumption, shield damage, wing surfaces, aerodynamic control moments, landing automation or terrain-relative altitude. These should remain separate follow-on tasks so the core force model can be tuned before landing behavior and environmental presentation are introduced.

The source has been statically inspected and numerical behavior checked independently. A Godot 4.7.2 executable was not available in the build environment, so GDScript parsing, the automated test scripts and in-engine behavior still require verification in the target project.

## Suggested next milestone

After Phase 2L is verified and tuned, add a focused landing/handling-limit pass on the existing test range: measure approach speed, sink rate, hover margin, control saturation and repeatable touchdown behavior. Once that flight loop is dependable, begin the basic spaceport environment and visual asset pass while keeping the current test range as a regression scene.
