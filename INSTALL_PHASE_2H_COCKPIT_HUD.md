# Space Trucker — Phase 2H: Cockpit Flight HUD

## Install

1. Make a backup copy of the current project folder.
2. Extract this ZIP directly into the existing Godot project root.
3. Allow the included files to overwrite the existing files.
4. Open the project in **Godot 4.7.2 Stable** and run the main scene with F5.

This package includes the Phase 2G FCC files so the update is self-contained relative to the working 2G project. It still relies on the existing Phase 2F/2E project dependencies remaining in place, including:

- `scripts/repulsorlift_system.gd`
- `scripts/vane_controller.gd`
- `scripts/vane_definition.gd`
- `scripts/ship_camera_controller.gd`
- `scripts/force_vector_debug.gd`
- Existing bottom, main-rear and side-vane Resources under `data/vanes/`
- `scenes/test_range.tscn` and `scenes/player.tscn`

Do not remove those files.

## What changes in 2H

### Normal cockpit display

The previous prototype status panels and detailed telemetry no longer clutter the normal view. A new transparent flight HUD appears when the player is piloting in cockpit camera view.

- **Left vertical tape — field power:** the green filled bar and ACT readout show actual actuator output. The amber tick and SET readout show the W/S setpoint.
- **Right vertical tape — vector angle:** the green filled bar and ACT readout show the actual field-vector angle. The amber tick and SET readout show the Q/E setpoint.
- **Central flight data:** local altitude, speed, vertical speed, heading, pitch and bank/roll.
- **Central attitude ladder:** follows ship pitch and roll while the aircraft reference remains fixed on the display.
- **Bottom controls:** the square shows the persistent mouse pitch/roll stick position. The thick vertical rudder marker moves laterally with A/D yaw input.
- **Status:** repulsorlift state and FCC assistance mode remain visible.

The normal cockpit HUD is hidden while using the external camera. This prevents the flight symbology from floating over the exterior view.

### F3 diagnostics

F3 now opens a full-screen, scrollable diagnostics page. It contains the previous telemetry and additional FCC information:

- Field state, power setpoint/output and vector setpoint/output.
- Pilot commands, camera mode, camera-look angles and control arming.
- FCC requested/actual angular rates, rate error, output and saturation.
- Ship mass, local position/altitude, linear velocity, speed, vertical speed, attitude and angular velocity.
- Center-of-mass mode, rigid-body state, gravity, hover threshold and TWR.
- Total force, main-vector direction and applied torque.
- Vane configuration and condition, individual vane contributions, and applied resultant vectors/application points.

F3 continues to enable the world-space force arrows. The normal flight HUD is replaced while the diagnostics page is active. The diagnostics page remains available in external camera view.

To scroll or interact with the diagnostic page, use the existing camera-look cursor procedure: hold RMB to enter camera-look mode, then hold Shift to release the cursor temporarily. F3 closes diagnostics and restores the cockpit HUD when the cockpit camera is active.

## Controls

| Input | Action |
|---|---|
| F | Start / stop repulsorlift field |
| W / S | Field power setpoint |
| Q / E | Field-vector angle setpoint (0–110°) |
| Mouse up / down | Pitch-rate request |
| Mouse left / right | Roll-rate request |
| A / D | Yaw-rate / rudder request |
| V | Toggle FCC assistance |
| C | Cockpit / external camera |
| RMB | Camera-look mode |
| Mouse wheel | External camera zoom |
| F3 | Toggle diagnostics and force-vector arrows |
| Shift while RMB-look is active | Temporarily release cursor for diagnostics scrolling |

The mouse stick remains persistent. Moving the mouse back toward its previous position reduces the requested pitch/roll rate; the stick does not auto-center.

## Display measurement notes

- `LOCAL ALT` currently displays the ship's local scene-origin Y coordinate. In the current test range, the ground reference is at Y=0, so it is useful as prototype altitude. It is **not yet radar altitude above arbitrary terrain**. A terrain-relative raycast/reference will be added when planetary surfaces are introduced.
- Speed is the magnitude of the ship's current linear velocity.
- Vertical speed is the world-Y component of velocity, matching the current test-range gravity orientation.
- Pitch, bank and heading are derived from the ship's current basis.
- Command and actual actuator values are sampled for HUD presentation at 30 Hz. The physics and force calculations remain on the existing physics tick; no flight-model coefficients or force allocations are changed in this milestone.

## Tests

Run these from the project root:

```bash
godot --headless --path . --script res://tests/flight_control_computer_test.gd
godot --headless --path . --script res://tests/flight_hud_layout_test.gd
```

Also rerun the existing Phase 2F force-model test:

```bash
godot --headless --path . --script res://tests/flight_force_control_test.gd
```

The new HUD test verifies that the normal display appears only in cockpit view, F3 replaces it with diagnostics, and diagnostics remain accessible in external view.

## Scope boundary

This milestone changes presentation and the telemetry refresh interval only. It does not change the FCC, vane forces, mass, inertia, damping, atmospheric model, drag, shield lift, landing behavior or camera physics. The new HUD is drawn with Godot Controls/CanvasItem primitives and introduces no external asset or plugin dependency.

The files have been statically inspected and checked for resource/input wiring and archive integrity. The build environment does not contain a Godot 4.7.2 executable, so GDScript parsing, the included tests and visual layout must still be verified in the target editor/runtime.
