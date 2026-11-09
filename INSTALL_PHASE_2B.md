# Space Trucker — Phase 2B installation

Target: Godot 4.7.2 Stable. This patch builds on the tested Phase 2A repository state.

## Install

1. Keep a backup or commit your current working project.
2. Extract the patch archive.
3. Copy the extracted files into the existing Godot project root, preserving paths. Overwrite only the listed files.
4. Open the project in Godot 4.7.2 and let the editor scan the new `ship_camera_controller.gd` script.
5. Run the configured main scene (`test_range.tscn`).

## Files

- `scripts/ship_camera_controller.gd` — new camera-only component.
- `scripts/ship_flight_controller.gd` — routes mouse input and owns input modes / virtual flight-control position.
- `scripts/flight_hud.gd` — displays camera/input state and F3 debug overview.
- `scenes/ship.tscn` — adds external camera rig, SpringArm3D and Camera3D.
- `project.godot` — adds the `ship_camera_toggle` InputMap action (C).

## Controls while seated

- **C** — switch cockpit / external camera.
- **RMB** — toggle flight-control mode / camera-look mode.
- **Flight-control mode:** mouse changes the persistent virtual pitch/roll position.
- **Camera-look mode:** mouse rotates the selected camera only; virtual pitch/roll values remain frozen.
- **Hold Shift in camera-look mode:** show the cursor and enter debug-UI interaction mode. Flight and camera input are blocked while held. There are no interactive debug widgets in this milestone; this is the input-mode foundation for the later vane inspector.
- **F3** — toggle the debug overview panel.
- **F / W/S / Q/E / A/D** — retain their Phase 2A field controls.

The virtual flight-control position is deliberately persistent and does not auto-center. Moving the mouse back toward the previous position returns the command toward zero. This is an input abstraction only; no attitude or force is applied yet.

## Acceptance tests

1. Enter the cockpit. The cockpit view remains active, the mouse is captured, and the HUD appears.
2. Press C. The external view appears and the hull is visible. Press C again; the cockpit returns and the hull is hidden.
3. In the external view, orbit with RMB camera-look mode. The camera orbits around the ship; the ship itself does not rotate.
4. Repeat camera-look in cockpit view. The cockpit camera rotates locally; the ship itself does not rotate.
5. Press F to turn the field online, release W/S, Q/E and A/D to arm controls, then move the mouse in flight-control mode. Pitch/roll command telemetry changes.
6. Hold RMB to enter camera-look mode and move the mouse. Camera angle changes, but pitch/roll command telemetry stays unchanged.
7. Toggle RMB back to flight-control mode. The saved pitch/roll values are still present and new mouse movement continues from that position; there is no recenter or jump.
8. In camera-look mode, hold Shift. The cursor appears. Mouse and keyboard flight commands are blocked. Release Shift; the cursor is captured again. Release W/S, Q/E and A/D before expecting those commands to resume.
9. Press F3. The debug overview appears; press F3 again to hide it.
10. Repeat C and RMB switching several times. Camera changes must not alter ship orientation, position, velocity or field telemetry.
11. Confirm the ship remains frozen and force output remains disconnected.

## Scope boundary

This is camera and input routing only. It does not implement force/torque calculations, vane simulation, FCC stabilization or actual flight. The GDD rigid-body baseline remains a required validation step before physical force integration.
