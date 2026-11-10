# Space Trucker — Phase 2G: FCC Foundation

## Install

1. Back up the current project folder.
2. Extract this ZIP into the existing Godot project root.
3. Allow the included files to overwrite existing files.
4. Open the project with **Godot 4.7.2 Stable** and run the main scene with F5.

This package is an incremental update to the working Phase 2F project. It assumes the existing project still contains the 2F/2E dependencies, including:

- `scripts/repulsorlift_system.gd`
- `scripts/vane_controller.gd`
- `scripts/vane_definition.gd`
- `scripts/ship_camera_controller.gd`
- `scripts/force_vector_debug.gd`
- `data/vanes/` with the four bottom vanes, main rear vane and two side vanes
- `scenes/test_range.tscn`, `scenes/player.tscn` and the existing project assets

Do not remove those files. This ZIP only contains new or changed files.

## What changes in 2G

The new `FlightControlComputer` is a ship-owned component. It receives pilot intent and the ship's measured angular velocity, then returns normalized pitch, roll and yaw commands to the existing vane-force allocator.

### Assisted mode — default

Mouse X/Y and A/D now request **local angular rates**, rather than holding a direct rotational force command:

- Mouse up/down requests pitch rate.
- Mouse left/right requests roll rate.
- A/D requests yaw rate.
- Returning the persistent mouse stick to neutral requests zero angular rate.

The FCC compares the requested rates with the actual angular velocity, expressed in ship-local axes. It produces proportional vane commands from that rate error. As the ship approaches the requested rate, the command decreases. With neutral input, it opposes existing rotation.

This is **rate stabilization, not attitude hold**. It does not try to return the ship to level, preserve a heading, or undo a deliberate attitude change. If the ship is tilted and the pilot centers the stick, the FCC tries to stop the rotation at that attitude.

### Assistance disabled

Press **V** to toggle FCC assistance OFF. The existing Phase 2F direct vane-command mapping is restored. With assistance disabled, angular damping is zero and rotational inertia is preserved; removing input does not automatically stop a spin.

Press **V** again to restore assisted rate control.

### Bounded correction and saturation

The FCC's output is clamped by `maximum_control_output` in the FlightControlComputer Inspector. The initial 0.8 cap intentionally leaves 20% of the normal axis command authority unused in assisted mode, preventing the first controller pass from having unlimited correction. The vane groups impose further physical limits through their configured authority and current condition. If the requested correction exceeds the output cap, the FCC reports the saturated axis in telemetry. A damaged or overloaded ship can therefore retain unwanted rotation rather than having every fault silently corrected.

The proportional controller has no integral term. This avoids accumulated correction when the field is unavailable or the actuator command is saturated. A steady external imbalance may leave a small residual rate; this is intentional for the first FCC pass.

### What is not implemented yet

This is an FCC foundation, not the complete final flight computer. It does not yet provide:

- Per-vane output redistribution or a thermal-aware allocation solver.
- Attitude hold, auto-level, heading hold or automatic return to a previous attitude.
- Atmospheric maneuvering-envelope logic.
- Thermal, generator-power or detailed actuator-failure feedback.

The current FCC corrects rotational-rate errors through the existing pitch/roll/yaw vane-force pairs. Per-vane redistribution can be added after this control loop is evaluated in the running prototype.

## Controls

| Input | Action |
|---|---|
| F | Start / stop repulsorlift field |
| W / S | Increase / decrease field power |
| Q / E | Change main field vector between 0° and 110° |
| Mouse up / down | Request pitch rate |
| Mouse left / right | Request roll rate |
| A / D | Request yaw rate |
| V | Toggle FCC assistance ON / OFF |
| C | Cockpit / external camera |
| RMB | Camera-look mode; flight stick position is retained |
| Mouse wheel | External camera zoom |
| F3 | Debug overview and force-vector arrows |
| Shift while in camera-look mode | Temporarily release cursor for debug UI interaction |

The mouse virtual stick remains persistent. Moving it back toward its previous position reduces the requested rate; it does not auto-center.

## Tuning in the Inspector

Select the `FlightControlComputer` node under the ship.

| Setting | Initial value | Purpose |
|---|---:|---|
| Maximum pitch rate | 32°/s | Full-scale pitch rate request |
| Maximum roll rate | 32°/s | Full-scale roll rate request |
| Maximum yaw rate | 24°/s | Full-scale yaw rate request |
| Rate response gain | 0.8 | Proportional response to normalized rate error |
| Maximum control output | 0.8 | Hard normalized FCC output limit; leaves part of the axis authority unused |
| Command deadzone | 0.015 | Filters tiny virtual-stick noise |

These are initial tuning values, not confirmed ship-performance specifications. Change one setting at a time and compare the measured local rate against the requested rate in the F3 panel.

## Testing

Run both deterministic tests from the project root:

```bash
godot --headless --path . --script res://tests/flight_force_control_test.gd
godot --headless --path . --script res://tests/flight_control_computer_test.gd
```

The first test verifies the existing 2F force model. The second verifies FCC rate targets, local-axis conversion, rate damping, direct mode, output bounds, saturation reporting and the input deadzone. It also runs a short live test through the actual rigid body and vane-force allocator: the ship must acquire pitch rate under input and reduce that rate after the stick returns to neutral.

## Manual acceptance checks

1. Open the cockpit and start the field. Release W/S, Q/E and A/D so the control interlock arms.
2. Leave the FCC enabled. Apply a moderate mouse pitch command. The F3 panel should show a pitch-rate target and a measured pitch rate moving toward it.
3. Return the mouse stick to neutral. The measured pitch rate should decrease toward zero.
4. Observe the ship's attitude while the rate returns to zero. The FCC should stop the rotation, not level the ship.
5. Repeat with roll and A/D yaw. Rotate the ship and confirm the FCC still works in ship-local axes.
6. Press V. The HUD should report direct vane control. A command should now apply the previous direct force-pair response; releasing the command should not actively stop rotation.
7. Press V again and confirm assisted rate control returns.
8. Use F3 to inspect target rate, actual local rate, rate error, FCC output and any saturated axes.
9. Turn the field OFF while rotating. The FCC should stop applying vane correction, and angular inertia should remain rather than being passively damped by the rigid body.

For the damaged-vane acceptance test, use the existing VaneController runtime state or the force-model test to reduce `bottom_front_right` to 50%, then command pitch. Confirm that the resulting roll disturbance is reduced only within the FCC's available correction authority; inspect the saturation flag and any residual roll rate.

## Verification status

The package is statically checked for file references, scene resource counts, input-map additions, and script structure. The build environment does not contain the Godot 4.7.2 executable, so the parser, deterministic GDScript tests and live rigid-body behavior must still be verified in the target Godot installation.
