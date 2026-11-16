# F7C — Unified Allocation Corrections

## Purpose

F7B introduced the single bounded physical actuator solve, but the first local test run exposed three integration problems: unrelated active channels diluted actuator recruitment priority, damage redistribution crossed channel boundaries, and the old force-vector telemetry no longer separated the main resultant from maneuver components.

F7C corrects those issues without returning to separate physical force passes.

## Corrections

### 1. Saturated combined-wrench residual

The physical allocator regularization is tightened from `1e-8` to `1e-9`. The F7B yaw-plus-hover case had a small regularization residual above the existing `0.01 N` maneuver-pair test threshold despite being geometrically achievable. The tighter value reduces that residual while keeping the bounded solve and its per-actuator output limits unchanged.

### 2. Channel-local recruitment priority

`VaneActuatorAllocator` now computes an actuator's effective recruitment weight using only active channels for which that actuator has a non-zero configured weight. A yaw-only vane therefore retains its configured yaw priority when a much larger lift demand is present. An unrelated lift demand no longer dilutes that yaw priority.

The per-actuator output remains one scalar in `[-1, +1]`; this change affects the regularization priority, not force authority or output bounds.

### 3. Channel-scoped damage redistribution

Damage shortfall and healthy headroom are measured independently for each active control channel. A damaged yaw vane can redistribute only into healthy yaw-eligible actuators; it cannot consume spare capacity from lift-only or pitch/roll-only vanes.

If one actuator participates in several active channels, the largest single channel share is used. Shares are not summed, because the actuator has one physical output bound.

### 4. Telemetry compatibility and force-vector meaning

- `actuator_allocator` and `main_vector_allocator` expose the full unified physical allocation.
- `maneuver_allocator` retains the full unified actuator-output list, but its `eligible_actuator_count` is the count of actuators eligible for the currently commanded maneuver axes. `unified_eligible_actuator_count` exposes the full solve count.
- `lift_main_force_vector` now denotes the requested main resultant. `lift_force_vector` and `lift_vane_contributions` report the achieved physical resultant and the actual per-vane forces applied to the rigid body.
- When propulsion and pilot maneuver commands overlap, `lift_force_vectors` uses an equivalent decomposition: the main resultant at the hull datum plus maneuver differential vectors at vane anchors. A main-only reference allocation is calculated for this visualization/telemetry decomposition only. It is not applied to the ship and does not create a second force budget.
- The rigid body still receives exactly one `apply_force()` call per non-zero physical actuator output from the unified solve.

The component decomposition preserves the previous diagnostic interpretation: a pure pitch or roll couple has near-zero net translation even while the ship is producing its main lift force.

## Tests

Run after F7A, F7B and F7C are all applied:

```powershell
& $godot --headless --path . --script res://tests/unified_actuator_channel_priority_test.gd
& $godot --headless --path . --script res://tests/unified_actuator_wrench_test.gd
& $godot --headless --path . --script res://tests/vane_yaw_geometry_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/main_vector_allocator_test.gd
& $godot --headless --path . --script res://tests/ship_anchor_integration_test.gd
& $godot --headless --path . --script res://tests/vane_actuator_allocator_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
```

F7C was statically inspected and its channel-priority test case was numerically replicated outside Godot. Godot is not installed in the packaging environment, so no GDScript parser or local runtime result is claimed. The existing two failing tests from the F7B report are specifically covered by the updated compatibility telemetry, force-component decomposition and channel-scoped redistribution paths; rerun them locally to confirm.
