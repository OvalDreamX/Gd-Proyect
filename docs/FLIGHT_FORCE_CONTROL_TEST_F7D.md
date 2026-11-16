# Flight force-control test contract — F7D

This note explains three assertions changed in `tests/flight_force_control_test.gd` after adopting the unified physical actuator allocation in F7B/F7C.

## 1. Combined pitch and roll can use a diagonal pair

For the prototype's symmetric four-bottom-vane arrangement, simultaneous pitch and roll requests of equal magnitude can be produced by two diagonally opposed vertical actuators. Their forces cancel in translation while creating both requested torque components. The minimum-force wrench solution therefore uses two nonzero bottom-vane outputs for this command, rather than forcing all four to carry nonzero force.

The other two bottom actuators remain eligible. The revised test checks all four IDs are included in the unified allocator's eligible output set, checks the two-vector diagonal couple, and checks both pitch and roll torque components.

This is not a return to independent pitch and roll force passes; each physical actuator still has one scalar output and one shared bound.

## 2. Cancellation tolerance is specific to diagnostic vector summation

The old `0.01 N` tolerance was below the useful precision of the test's summation of large opposing `Vector3` force values. The observed `0.061 N` residual is approximately `7.5e-8` of the `809,325 N` rated main propulsion force. A separate `0.1 N` tolerance is now used only for those pitch/roll diagnostic cancellation sums.

The global `EPSILON` is unchanged. No allocator residual threshold, maximum force, physical actuator limit, or applied-force calculation is relaxed.

## 3. Damaged lift plus pitch is a combined physical contribution

With a 50%-integrity front-right lift vane, the main-only baseline cannot necessarily reproduce the requested main resultant with zero torque. The unified allocator instead solves the actual achievable combined wrench. F7C reports those forces with `kind = "combined"` when the main-only diagnostic decomposition is not valid.

The revised assertion checks those four combined bottom-vane force entries and retains the cross-axis roll-moment and damaged-authority checks. It no longer asks the telemetry to label a combined propulsion/control force as a pure `pitch` force.

## Scope

F7D modifies regression-test expectations and documentation only. Production simulation scripts are unchanged.
