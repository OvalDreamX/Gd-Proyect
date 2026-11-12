# Stability Pass 3 — Cargo Inertia and Planetary Reference Frame

## Cargo inertia model

`CargoSystem` now estimates the dry hull as a centered, axis-aligned uniform box read from the ship's active `CollisionShape3D` `BoxShape3D`. It models all cargo as one consolidated uniform box. At full payload that box defaults to 2 × 1 × 3 m; its dimensions scale with the cube root of the fill fraction, so the assumed volume scales with cargo mass. The cargo centroid remains bounded so the aggregate box does not cross the hold limits.

The combined center of mass is computed from the dry hull and cargo centroids. Intrinsic box moments are added to parallel-axis contributions about that combined center. The resulting diagonal is assigned to `RigidBody3D.inertia`; the inertia products `(Ixy, Ixz, Iyz)` are returned separately as telemetry. They are not applied to the solver because the `RigidBody3D.inertia` property is a `Vector3`, not a user-set full tensor. This keeps the approximation visible rather than claiming a fully coupled inertia model.

The model assumes the dry collision box is centered and axis-aligned. If the collider is offset or rotated, the implementation warns and uses the prototype dimensions as a fallback. Final mass-property work should replace both box assumptions with actual hull mass regions and individual cargo geometry/density data.

## Planetary frame contract

`PlanetaryReferenceFrame` is the shared environment provider. Its local components are:

- `up_world`: local vertical, opposite the gravity vector.
- `north_world` and `east_world`: orthogonal tangent directions.
- `altitude_m`: height above the selected flat datum or spherical radius.
- `gravity_world` and `gravity_magnitude_mps2`: the local gravity result.

For spherical geometry, up is radial. Gravity is inverse-square outside the reference surface and linear with radius inside, matching a uniform-density sphere as a simple finite interior approximation. At a pole, tangent north is mathematically undefined; the provider uses a deterministic projected local-axis fallback.

`PlanetaryGravityBody` applies local gravity to its parent rigid body and disables the built-in world-axis gravity while the provider is valid. It leaves default gravity untouched if no provider is present, restores it if the provider is removed, and skips the repeated force while a body is sleeping. A changed gravity vector wakes the body so the new field takes effect. Cargo manifest changes also wake the ship after updating mass properties.

The TestRange root now owns the provider. The ship's gravity adapter, atmospheric model, and sensor suite reference it by explicit relative path; the walking player uses the sibling provider. Repulsorlift gravity/TWR telemetry reads the same adapter. The atmosphere specifies wind in local east/up/north components and converts it through the provider at the ship's current position, keeping wind, instruments, gravity, and locomotion on one frame.

## Deliberate limits

This is a local-frame foundation, not a full planetary simulation. The TestRange remains flat and collides with the existing flat ground. Spherical mode does not generate terrain/colliders, model planetary rotation or atmospheric rotation, switch automatically among multiple bodies, propagate orbits, or rebase large coordinates. The current provider is attached explicitly to one scene and can later be replaced or extended by a system/planet environment manager.

Aerodynamic forces remain central. They should only gain application points and moments after the ship's actual collision/visual geometry and aerodynamic centers are defined; arbitrary guessed lever arms would undermine the current force/torque separation.

## Validation status

`cargo_system_test.gd` was extended for centered and offset cargo inertia. `planetary_reference_frame_test.gd` covers flat and spherical frame values, rotated local axes/wind, gravity adapter behavior, sleep eligibility, and TestRange wiring. The files were statically reviewed and resource paths checked against the base snapshot. No Godot runtime/import test was executed during preparation because the Godot executable was unavailable.
