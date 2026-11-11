# AI Handoff — Space Trucker (Current Flight Prototype)

Read this file together with `GAME_DESIGN_DOCUMENT_v0_1.md` and `DEVELOPMENT_CHANGELOG.md`. The GDD is the design source of truth; the changelog records recent implementation milestones.

## Current project state

- Godot 4.7.2 Stable, GDScript, GL Compatibility renderer, Windows.
- Main scene: `res://scenes/test_range.tscn`.
- One ship `RigidBody3D` owns all physical motion. Do not split vanes into separate rigid bodies.
- Single-player walkaround/cockpit entry is implemented. Ship flight is a simplified Newtonian model with repulsorlift translation and vane force couples, FCC assistance, atmosphere drag/wind and shield glide lift.
- Phase 2N FCC changes keep maneuver controls available whenever the field is online, even at zero main-vector throttle; zero throttle gives a limited 20% maneuver boost, with bounded partial healthy-vane redistribution.
- Phase 2O introduced a ship-owned `FlightSensorSuite`. The HUD should consume sensor packets and validity flags rather than read physics state itself.
- Phase 2P ship sizing: 30,000 kg dry mass, 25,000 kg design payload, 55,000 kg maximum gross mass. Fixed bottom lift force is about 593.5 kN (1.10 gross TWR); rear forward force about 809.3 kN (1.50 gross TWR). Cargo is not implemented.
- Vane thermal behavior is described in the GDD but **not implemented**.

## Current HUD architecture and known issue

- Side gauges and control-input viewer are screen-space and should remain visible in both cockpit and third-person views (except while F3 diagnostics are open).
- Central ladder, boresight, flight-path marker and compass are projected onto a physical 3D windshield surface fixed to the ship. Camera head-look must move the camera relative to this surface, not move the HUD with the camera.
- The previous SubViewport implementation was missing in runtime despite node-existence checks passing. Phase 2Q moves the transparent 2D SubViewport to the ship root, sets `UPDATE_ALWAYS`, and configures the receiving material for premultiplied-alpha, no depth test, no depth writes and late transparent render priority.
- The central HUD is **not yet considered verified** until `tests/flight_hud_layout_test.gd` (run with the desktop renderer, not `--headless`) confirms non-transparent pixels from the SubViewport and the user confirms it displays in-game.

## Development constraints

- Preserve `scenes/test_range.tscn` as regression environment; new spaceport/planet and orbital test scenes should be separate.
- Do not alter the atmospheric drag/wind/glide-lift coefficients without an explicit request and a separate test pass.
- Build thermal behavior as a distinct subsystem later: current temperature changes available vane output; hot operation accelerates wear and fault risk; cooling recovers thermal margin. Keep temperature, wear and health separate.
- Keep code stable and defensive. Use physics tick for physical forces; do not set the rigid body's transform to simulate flight.
- Deliver overwrite ZIPs containing only modified files, preserving relative project paths; do not substitute patcher installers unless explicitly requested.

## Immediate next work

1. Verify Phase 2Q HUD render output and manual cockpit/third-person behavior.
2. Run the full regression test suite with the project's Godot 4.7.2 executable.
3. Only then proceed to environment profile architecture, a separate local spaceport scene, orbital-space scene and basic shaders.
