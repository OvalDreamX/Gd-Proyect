# F7B — Unified Actuator Allocation

## Purpose

F7A moved the main propulsion vector to geometry-based allocation, but main propulsion and pitch/roll/yaw still ran in separate allocator passes. A vane carrying weights for both could therefore be assigned a full scalar output in each pass. That was not a valid physical actuator limit.

F7B replaces those passes with one six-dimensional wrench solve per physics tick.

## Runtime contract

- Each configured vane is discovered by stable ID; there is no fixed actuator count or slot order.
- The allocator receives one record per physical actuator and produces one scalar output bounded to `[-1, +1]`.
- The output force is applied once at that vane's authored local position.
- Main propulsion target force retains the F7A 0°/90°/110° vector convention and TWR cross-fade.
- Main propulsion's target torque includes `(hull_datum - current_COM) × target_main_force`. This makes the sum of distributed anchor forces equivalent to the requested main resultant through the hull datum, without applying a second central force.
- Pilot pitch/roll/yaw torques are added to that datum torque before allocation.
- Pitch/roll reserve their configured authority share from the main-vector request when commanded. Yaw-only side actuators remain independent when their geometry and control weights allow it.
- Damage redistribution and zero-main-power maneuver boost are represented in the same physical actuator force limit; no second output budget exists.
- The solver's achieved wrench populates total force/torque telemetry. Main-vector and maneuver telemetry keys remain as compatibility aliases to the unified allocation.

## Thermal model

Thermal loads are now calculated from each vane's actual force contribution divided by its rated force. The controller's existing `update_thermal_simulation()` remains responsible for heating, cooling, sputter and wear. This removes the previous `bottom_front`, `bottom_rear` and `main_rear` group assumptions from thermal loading without changing the thermal state model.

## Compatibility notes

- `maneuver_allocator` and `main_vector_allocator` both expose the unified allocation result.
- `maneuver_allocator_active_actuators` remains a maneuver-channel eligibility count for existing HUD/tests; `actuator_allocator` exposes the complete unified result.
- Force-vector debug entries retain `pitch`, `roll`, and `yaw` kinds when only one maneuver axis is commanded. Shared multi-axis contributions are labelled `maneuver`.
- Group IDs remain descriptive metadata; force generation, lift capacity and thermal loading no longer use them as propulsion-role selectors.

## Validation

Run the complete existing force/vane test set after applying F7A and F7B together:

```powershell
& $godot --headless --path . --script res://tests/main_vector_allocator_test.gd
& $godot --headless --path . --script res://tests/unified_actuator_wrench_test.gd
& $godot --headless --path . --script res://tests/vane_yaw_geometry_test.gd
& $godot --headless --path . --script res://tests/ship_anchor_integration_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/vane_actuator_allocator_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
```

F7B was statically inspected in the packaging environment. Godot is not installed here, so no GDScript parser or runtime test result is claimed. In particular, verify full-power pitch/roll while hovering: the unified bound intentionally trades a small amount of propulsion output for the commanded maneuver reserve rather than exceeding a vane's rated scalar output.
