# AI handoff — Space Trucker

**Repository baseline reviewed:** `2c396eea61f5e949aa25d13b8732e92a20f8e6fa` (11 November 2026)  
**Engine:** Godot 4.7.2 Stable · GDScript · GL Compatibility · Windows  
**Main scene:** `res://scenes/test_range.tscn`

## Read these documents first

1. `GAME_DESIGN_DOCUMENT_v0_1.md` — core design authority. Respect the CONFIRMED / DESIGN DIRECTION / PROPOSED / TBD distinctions.
2. `GDD_ANNEX_v0_3.md` — detailed authoritative specification for the Phase 3 environment/travel vertical slice. It overrides the GDD only where it explicitly defines Phase 3.
3. `FUTURE_PHASES.md` — short navigation/priority guide for Phase 3 and deferred graphics, cockpit and modelling work.
4. `IMPLEMENTATION_HISTORY.md` — consolidated record of Phases 2A–2U, including superseded decisions and the current file map.
5. `TESTING.md` — regression commands and manual test expectations.

Do not use old installation notes, old ZIPs or chat summaries as the current source of truth. Inspect the current repository and source files before editing.

## Current project state

This is a flight and ship-systems prototype, not yet a complete cargo/trading game or planetary/orbital world.

- One `RigidBody3D` owns ship movement, rotation, mass, inertia and collisions.
- `ShipFlightController` handles pilot input, field state and telemetry routing.
- `FlightControlComputer` provides bounded PI angular-rate assistance in assisted mode and direct shaped vane commands when assistance is disabled. It is not attitude hold.
- `RepulsorliftSystem` owns repulsorlift force and torque calculations and applies them in the physics tick.
- `VaneController` owns per-instance vane condition, resultant math and thermal state. Vane Resources remain configuration data.
- `AtmosphericFlightModel` owns the current test-atmosphere, wind, drag and shield-glide model.
- `FlightSensorSuite` is the instrument-data boundary. The HUD consumes sensor packets and validity flags rather than calculating physical measurements itself.
- `CargoSystem` models abstract payload mass and position, updates the real rigid-body mass and custom COM, and reads its dry-mass/payload ratings from `ShipInteractable`.
- The current HUD is the screen-space CanvasLayer/Control implementation. Side instruments remain visible in cockpit/external views; central symbology is gated by cockpit view and camera alignment. The windshield SubViewport experiment is historical, not active.

Prototype freighter ratings: 30,000 kg dry mass, 25,000 kg payload capacity and 55,000 kg design gross mass. Vane authority is rated against fixed design gross mass so adding cargo increases inertia without increasing engine force.

## Important current behavior

- Main vector: 0° forward, 90° ship-up/VTOL and 110° up/rearward braking blend.
- W/S controls overall field power; Q/E controls vector distribution; mouse controls pitch/roll; A/D controls yaw.
- The FPM represents inertial/world velocity. Airspeed is air-relative in atmosphere and inertial in vacuum.
- Side gauges/control indicators remain screen-space. Central HUD symbology appears only in cockpit view near the default boresight. RMB-look exit starts a 3-second recenter delay.
- Thermal state updates even while the field is offline or the body is frozen. Offline vanes cool toward ambient without operating wear.
- Assisted FCC mode is bounded PI rate control with anti-windup. Integral trim is limited and cleared when control authority is unavailable or assistance is disabled. Saturation and residual rotation are valid outcomes.
- The main-field resultant acts at the fixed hull reference datum. A displaced cargo COM therefore produces a physical lever-arm moment. Gravity itself is not treated as a torque source merely because the COM moved.

## Development constraints

- Preserve `scenes/test_range.tscn` as the flight regression environment. New planetary, spaceport and orbital environments must be separate scenes.
- Keep force application and physical subsystem updates on the physics tick.
- Do not directly set the rigid body's transform during normal flight.
- Do not split vanes into separate rigid bodies.
- Do not change flight feel, atmosphere, thrust ratings or thermal coefficients during an unrelated documentation/polish task.
- Do not silently upgrade Godot or change renderer. Target Godot 4.7.2 Stable and GL Compatibility.
- Keep design decisions distinct from implementation facts. A value in code is not automatically a final balance decision.
- Add focused tests, run relevant regressions and report exact evidence. Never claim a test passed unless it was actually run.
- For visual features, node existence is not proof of successful rendering; inspect actual rendered output.
- Prefer complete, ordinary overwrite ZIPs containing only changed files at original project-relative paths. Do not use patcher installers.

## Next approved implementation direction

The next major work is the Phase 3 environment/travel vertical slice described in `GDD_ANNEX_v0_3.md`: one compact planet/starport, a separate local-space station environment and a fixed round-trip hyperspace route. Read that annex in full before proposing implementation. Do not start general procedural systems, full orbital mechanics, a large universe, economy/NPCs or walkable station interiors as part of that phase.

Graphics and cockpit refinements should support the scoped environment loop and existing systems rather than become a parallel redesign. See `FUTURE_PHASES.md` for which details are confirmed, deferred or still require owner approval.
