# Space Trucker — Stability Pass 3 Overwrite

This is the second-half overwrite package. Extract it into the existing Godot project root and allow the included project-relative paths to overwrite their counterparts. It is designed to be combined with the separate Stability Pass 2 ZIP; the two packages have no overlapping project paths.

## Implemented

### Cargo rotational inertia

- The dry freighter is approximated as a uniform box using the dimensions of its centered, axis-aligned `CollisionShape3D` `BoxShape3D`.
- The cargo manifest is represented as one consolidated, axis-aligned box. Its default full-load envelope is 2 × 1 × 3 m and scales with the cube root of the load fraction. Its centroid is constrained so the envelope remains inside the cargo bay.
- The system computes total mass, combined center of mass, intrinsic box inertias, and parallel-axis contributions about the combined center of mass.
- The diagonal moments are written to `RigidBody3D.inertia`. The remaining products of inertia are reported in telemetry as `(Ixy, Ixz, Iyz)` under `inertia_products_kg_m2` and marked as omitted from the solver.

**Known approximation:** `RigidBody3D.inertia` is exposed as a `Vector3`, so this implementation does not apply a full off-diagonal inertia tensor or rotate to its true principal axes. The diagonal approximation is explicit and the omitted products remain visible in telemetry. The hull and aggregate cargo are also assumed uniformly distributed within their boxes; this is a prototype mass model, not a replacement for a detailed parcel manifest or final ship mass layout.

### Shared planetary reference frame

- Adds `PlanetaryReferenceFrame`, which supplies local up, tangent north/east, altitude, and a gravity vector at a world position.
- Supports a flat reference plane and a spherical surface. Spherical gravity uses inverse-square falloff outside the surface and a uniform-density linear interior approximation, avoiding a singular field at the center.
- Adds `PlanetaryGravityBody`, which disables default world-axis gravity while a provider is present and applies the provider's local gravity to its parent rigid body. It leaves normal Godot gravity intact when no provider is found, resumes it if the provider disappears, and avoids continuously waking settled sleeping bodies.
- The test-range scene now owns the shared frame. The ship, atmosphere, flight instruments, repulsorlift TWR calculations, and walking controller consume that same frame.
- Atmospheric mean wind and turbulence are now specified in local east/up/north components and transformed into world space at the ship's position. The default values preserve the existing test-range wind direction.
- The player controller aligns its walking up direction, jump, movement plane, and yaw axis to local planetary up.

**Scope boundary:** the default test range remains flat. The spherical mode supplies reference geometry, altitude, local directions, and gravity calculations; it does not create spherical terrain or collision, atmospheric rotation, a multi-body gravity solver, orbital propagation, or floating-origin/rebasing support. The provider is one explicitly referenced frame per scene for this phase.

## Tests to run in Godot 4.7.2

New/updated checks:

```text
godot --headless --path . --script res://tests/cargo_system_test.gd
godot --headless --path . --script res://tests/planetary_reference_frame_test.gd
```

Relevant regressions:

```text
godot --headless --path . --script res://tests/flight_sensor_suite_test.gd
godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd
godot --headless --path . --script res://tests/test_range_environment_test.gd
godot --headless --path . --script res://tests/vane_physics_integration_test.gd
```

**These tests were not executed during package preparation.** No Godot executable was available in this environment; the commands are provided for local validation. Static resource-path and source-snapshot checks were performed, but they are not a substitute for importing/running the project in Godot.

## Files in this overwrite

Modified:
- `scripts/cargo_system.gd`
- `scripts/atmospheric_flight_model.gd`
- `scripts/flight_sensor_suite.gd`
- `scripts/repulsorlift_system.gd`
- `scripts/ship_flight_controller.gd`
- `scripts/player_controller.gd`
- `scenes/ship.tscn`
- `scenes/test_range.tscn`
- `tests/cargo_system_test.gd`

Added:
- `scripts/planetary_reference_frame.gd`
- `scripts/planetary_gravity_body.gd`
- `tests/planetary_reference_frame_test.gd`
- `docs/STABILITY_PASS_3_NOTES.md`
- `STABILITY_PASS_3_CLEANUP.txt`

No existing project files need to be deleted. Keep every existing `.gd.uid` sidecar. No GDD, project settings, art assets, or vane resources are changed.

Aerodynamic force moments remain deferred until the hull geometry defines credible drag/lift application points and centers of pressure. Applying arbitrary moment arms now would introduce ungrounded rotational behavior.
