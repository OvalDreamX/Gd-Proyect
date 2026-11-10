# Space Trucker — Phase 2F Control Correction

## Install

1. Make a backup copy of your current project folder.
2. Extract this ZIP into the existing Godot project root.
3. Allow the included files to overwrite existing files.
4. Open the project in Godot 4.7.2 and run the main scene.

The ZIP contains complete replacement scripts/scenes and two new side-vane Resources. It assumes the existing Phase 2E files remain in place, including `scripts/vane_definition.gd`, the four bottom-vane Resources, `data/vanes/main_rear.tres`, and `scripts/ship_camera_controller.gd`.

## Controls

- **F:** Field OFF / STARTING / ONLINE.
- **W / S:** Overall field power.
- **Q / E:** Move the main force vector. Q moves toward 0 degrees (forward); E moves toward 110 degrees (up/rearward braking blend).
- **Mouse up / down:** Nose up / nose down.
- **Mouse right / left:** Right roll / left roll.
- **D / A:** Yaw right / yaw left.
- **RMB:** Switch between flight control and camera look. For pitch/roll input, the HUD must show `FLIGHT CONTROL`.
- **C:** Cockpit / external camera.
- **Mouse wheel:** External camera zoom.
- **F3:** Toggle the debug overview and force-vector arrows.
- **Shift while in camera-look mode:** Temporarily release the cursor for debug UI interaction.

Mouse pitch/roll uses a persistent virtual-stick position. Moving the mouse back toward the previous position reduces the command; the stick does not automatically recenter.

## Main-vector convention used in this prototype

The GDD leaves the exact coordinate convention TBD. This implementation uses:

- **0 degrees:** ship-forward (`-Z`).
- **90 degrees:** ship-up (`+Y`), the initial VTOL/hover setting.
- **110 degrees:** upward with a rearward (`+Z`) component, a braking blend.

The main vector rotates with the ship. It is not fixed to world-up.

## Force allocation

- The primary field resultant acts through the center of mass.
- Mouse pitch produces opposing front/rear force pairs.
- Mouse roll produces opposing left/right bottom-vane force pairs.
- A/D yaw uses opposing side-vane forces.
- Secondary group forces act at their live, contribution-weighted vane centroid. A damaged vane therefore shifts the application point toward the healthier vane.
- Godot applies the resultant forces to the existing single `RigidBody3D`; no vane is a separate physics body.

The two side vanes and their 0.03 TWR each are **PLACEHOLDERS** because the GDD leaves the exact side-vane count, placement and authority TBD. The maneuver-authority fraction and passive angular damping are exposed in the Inspector for tuning. There is no FCC attitude-hold or active stabilization in this correction.

## F3 force arrows

F3 draws an arrow for each force actually submitted to the rigid body. The tail marks the application point, the arrow points in the force direction, and its length scales with force magnitude. Colors distinguish the main, pitch, roll and yaw groups.

## Verification

The package adds a deterministic force-allocation and rigid-body smoke test:

```bash
godot --headless --path . --script res://tests/flight_force_control_test.gd
```

Manual acceptance checks:

1. With the field online at 90 degrees, W/S controls lift and the ship remains controllable.
2. Q/E changes the main force direction relative to the ship, not world-up.
3. Mouse input changes pitch and roll when the HUD says `FLIGHT CONTROL`.
4. A/D produces yaw.
5. F3 shows the main vector and the secondary force arrows at their application points.
6. Healthy paired forces produce rotation without adding unintended net translation.
7. A 50%-effective front-right vane shifts the front pitch vector toward the healthier left vane and creates the corresponding unwanted roll.
8. Existing cockpit/external cameras, RMB look mode, wheel zoom and field spool behavior remain functional.

The scripts and scene references were statically checked in the packaging environment. Godot 4.7.2 runtime validation still needs to be performed on your installation.
