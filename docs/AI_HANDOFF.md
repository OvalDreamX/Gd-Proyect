# AI Handoff — Space Trucker

Read this file together with `GAME_DESIGN_DOCUMENT_v0_1.md` and `DEVELOPMENT_CHANGELOG.md`. The GDD remains the design source of truth; this handoff describes the current implementation.

## Current project baseline

- Godot 4.7.2 Stable, GDScript, GL Compatibility renderer, Windows.
- Main scene: `res://scenes/test_range.tscn`.
- One `RigidBody3D` owns all ship motion, mass, inertia and collisions. Do not split vanes into independent rigid bodies.
- Flight uses simplified Newtonian translation, fixed-rated repulsorlift authority, vane-generated maneuver forces, FCC assistance, atmosphere drag/wind and shield-generated glide lift.
- Ship dry mass: 30,000 kg. Design payload: 25,000 kg. Maximum gross design mass: 55,000 kg.
- Vane authority is rated at design gross mass, so cargo adds inertia without increasing engine rating.
- `FlightSensorSuite` is the instrument-data boundary; HUD rendering consumes the instrument packet and validity flags.
- Current HUD is the screen-space `CanvasLayer` implementation. Side instruments remain visible in cockpit/external views; central symbology is gated by cockpit view and camera alignment. The earlier physical windshield/SubViewport experiment is not the active scene architecture.

## Flight control and force allocation

- `RepulsorliftSystem` owns force and torque calculations and submits them from the physics-tick path.
- `VaneController` stores per-instance vane health, alignment and thermal state. Vane resources remain immutable configuration.
- FCC assisted mode uses a bounded PI angular-rate controller with anti-windup. It is **not** attitude hold; it does not command a return to level.
- Integral trim clears when the field/control authority is unavailable or assistance is disabled.
- Existing P response, output cap, direct-vane mode, input shaping and limited healthy-vane redistribution remain.
- Main-field resultant is applied at the fixed hull reference datum. An offset cargo COM produces a real lever-arm moment. Gravity is not itself treated as a torque source merely because the COM is shifted.
- FCC can counter only moments within its available vane authority. Saturation and residual rotation are legitimate outcomes.

## Thermal model

- Vane temperature, load, wear, integrity, failure and sputtering are per-vane state.
- Main-vector demand is allocated to the appropriate vane groups; maneuver contributions add per-vane load from the force allocator.
- Thermal updates advance every repulsorlift physics call, including field-off/frozen calls. Offline vanes cool toward ambient and do not accrue operating wear.
- Thermal coefficients are game-tuned; do not silently change them or claim real-world equivalence.
- Load-dependent green-zone bounds: `60 * load^0.7` through `180 - 20 * load` °C.
- Full load heats quickly with the present coefficients; the earlier 25–35 second overheat statement is not current behavior.

## Cargo model

- `CargoSystem` derives dry mass and maximum payload from its parent `ShipInteractable`; do not add competing mass-rating exports.
- It updates the actual `RigidBody3D` mass and custom COM.
- The F4 manifest is an abstract mass/position model, not yet physical packages, storage volume, loading animations, inventory or contract cargo.
- Hover throttle display is a nominal 1g estimate only. It excludes thermal derating, damage, local gravity and current allocator limits.

## Testing and workflow

Keep `scenes/test_range.tscn` as the regression environment. New planets, local spaceports and orbital scenes should be separate.

Run the thermal, cargo integration, FCC trim, FCC, force-allocation, sensor, FPM, HUD-layout and display-settings tests after relevant changes. Use Godot 4.7.2, not a different major version. Do not claim tests passed unless they were actually run.

Preserve the user's preferred delivery format: ordinary overwrite ZIP, only changed files, original project-relative paths, no patcher. Make no unrelated flight-model tuning changes during polish passes.
