# Space Trucker — Phase 2F

## Install

Extract this ZIP into the existing Godot project root and overwrite files when prompted. The archive contains complete replacement scripts and one new test script:

- `scripts/repulsorlift_system.gd`
- `scripts/flight_hud.gd`
- `tests/vane_physics_integration_test.gd`

No scene files, input mappings, camera scripts, or player scripts need to be changed.

## What changed

The repulsorlift system now applies the already-calculated net vane torque to the ship's single `RigidBody3D`, in addition to applying net force centrally:

- `apply_central_force(net_force)`
- `apply_torque(net_torque)` when the net torque is non-zero

This pair is the equivalent physical wrench of the individual vane forces and their moments about the center of mass. Both calls are made from the existing physics-tick path. Neither is multiplied by `delta`.

The HUD now reports applied torque rather than predicted/not-applied torque.

## Deliberate scope boundary

This milestone integrates the torque produced by the current collective-lift force distribution. It makes asymmetric vane condition physically observable as unintended attitude change. It does **not** yet map mouse pitch/roll or A/D yaw commands to vane force directions, and it does not add FCC stabilization or compensation. Those are separate later steps; the exact vector allocation and side-vane layout remain design work.

## Automated test

Run from the project root with the Godot 4.7.2 executable:

```bash
godot --headless --path . --script res://tests/vane_physics_integration_test.gd
```

Expected checks:

1. The ship's vane configuration registers successfully.
2. Healthy symmetric vanes produce negligible angular velocity.
3. Reducing the right-front vane to 50% produces roll in one direction.
4. Reducing the left-front vane to 50% reverses the roll direction.

The test loads only the ship scene and places it above the ground to avoid contact effects.

## Manual in-game check

1. Run the normal test range.
2. Enter the cockpit and turn the field on.
3. Confirm takeoff and hover remain as before with healthy vanes.
4. Observe the new `NET TORQUE` HUD readout; it should remain near zero with healthy symmetric vanes.
5. Run the headless test above to verify the asymmetric roll response. Runtime vane damage is not yet exposed through an in-game inspector.

## Notes

- Ship mass and vane TWRs remain placeholders from the previous milestone.
- The ship remains one `RigidBody3D`; no vane physics bodies were added.
- Godot derives inertia from the existing collision shape.
- This package has not been run in Godot in the generation environment. Run the headless test and the normal project before committing.
