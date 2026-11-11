# Phase 2T — Cargo Manifest, Mass and Center of Mass (current behavior after 2U)

## Cargo subsystem

`CargoSystem` is a dedicated node on the ship. It derives dry mass and payload capacity from its parent `ShipInteractable`; those ratings are no longer duplicated as independent cargo-system settings.

It models an abstract payload mass and a payload position within the hold. The combined center of mass is:

\[
\vec R_{COM} = \frac{M_{cargo}\vec R_{cargo}}{M_{dry}+M_{cargo}}
\]

The subsystem updates the actual `RigidBody3D.mass`, `center_of_mass_mode` and `center_of_mass`. Vane mount positions remain fixed.

The F4 panel provides mass and X/Y/Z offset sliders plus empty, half, maximum, port-heavy, starboard-heavy, nose-heavy and aft-heavy presets. The payload slider follows the ship-authored payload capacity.

## 2U physical correction: where the torque comes from

Gravity does not generate a torque merely because the center of mass moves. Gravity acts through the combined center of mass.

The repulsorlift main-field resultant is now applied at the fixed ship/hull reference datum (the rigid-body origin), rather than being artificially applied through the current center of mass. An offset center of mass therefore creates a real lever arm:

\[
\vec \tau = (\vec r_{hull}-\vec r_{COM}) \times \vec F_{main}
\]

The empty ship retains its zero-offset baseline. An asymmetric manifest changes the main-field moment and therefore changes flight behavior.

## 2U FCC trim correction

Assisted FCC mode now uses a bounded PI angular-rate controller. Its integral term can retain a small counter-command against a persistent disturbance. The original proportional response, maximum output cap and vane redistribution limits remain in place. The integrator uses anti-windup and is cleared when control authority is unavailable or the pilot switches to direct-vane mode.

This is **not** an attitude-hold system, and it does not guarantee level flight under every cargo arrangement. The trim output is bounded; if the induced moment exceeds available maneuver authority, the FCC saturates and residual rotation remains. This is intentional feedback, not a hidden unlimited compensation mechanism.

The F4 panel and F3 diagnostics now describe that limitation accurately. F3 reports whether integral trim is active and whether the FCC is saturated.

## Hover estimate

The F4 hover-throttle figure remains a nominal 1g estimate based on the fixed 1.10 gross-TWR design rating. It excludes local gravity changes, vane thermal derating, damage and current force-allocation limits. Treat it as a planning figure, not a guaranteed hover setting.

## Tests

```powershell
& $godot --headless --path . --script res://tests/cargo_system_test.gd
& $godot --headless --path . --script res://tests/flight_control_trim_test.gd
& $godot --headless --path . --script res://tests/flight_hud_phase2u_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
```

`cargo_system_test.gd` instantiates the actual ship scene and checks its rigid-body mass, custom COM, main-field induced torque, payload clamp and offline thermal cooling.
