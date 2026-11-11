# Space Trucker — Development Changelog / Context Ledger

This file records the recent flight/HUD milestones so future development sessions can resume without relying on chat history. The master design authority remains `GAME_DESIGN_DOCUMENT_v0_1.md`; this file records implementation state and deviations.

## Current baseline

- Engine: Godot 4.7.2 Stable, GDScript, GL Compatibility renderer, Windows PC.
- Main scene: `res://scenes/test_range.tscn`.
- Ship architecture: one `RigidBody3D`; the rigid body owns translation, rotation, mass, inertia and collisions.
- Flight model: simplified Newtonian translation, repulsorlift field, vane-generated pitch/roll/yaw forces, FCC rate assistance, atmospheric drag/wind and shield-generated glide lift.
- Keep `test_range.tscn` as the regression environment. New planetary/spaceport and orbital scenes should be separate scenes.

## Phase 2N — FCC, maneuver authority and flight instrumentation

- FCC maneuver controls remain available whenever the repulsorlift field is online, even with zero main-vector throttle.
- Maneuver force gets a limited reserve increase as main-vector output is reduced; the current configured zero-throttle increase is 20%.
- Healthy redundant vanes may receive bounded partial redistribution to compensate for a damaged partner; damage is not fully erased.
- HUD telemetry uses local-up altitude/vertical speed and camera/head-look aware projection logic from that phase.
- Atmospheric drag, wind and shield glide-lift equations were intentionally left unchanged.

## Phase 2O — Windshield display and sensor data boundary

- Central symbology was separated from side instruments and rendered through a transparent 1280×720 `SubViewport` texture on a 3D quad attached to the ship's windshield.
- Throttle/vector gauges and the control-input viewer remain screen-space instruments; central flight symbology is ship/window-fixed and should slide out of view as the pilot turns their head.
- Added `FlightSensorSuite` as the instrument-data boundary. It publishes attitude, heading, velocity and altitude measurements with independent validity flags. Future bias, drift, latency and failures belong in this sensor layer, not HUD drawing code.
- Compass heading is projected into the local horizontal plane using a north reference; pitch must not change the heading reading.
- The initial 3D projection failed to display in the user's runtime. Node-existence checks were insufficient and did not prove that the SubViewport rendered actual pixels.

## Phase 2P — Ship mass and fixed thrust rating

- Ship dry mass set to 30,000 kg.
- Design payload capacity is 25,000 kg; maximum gross mass is 55,000 kg. Cargo itself is not implemented yet.
- Vane authority is rated against the fixed 55,000 kg design gross mass, not current ship mass. This prevents cargo mass from automatically increasing engine force.
- Bottom vane set: 1.10 gross TWR = approximately 593.5 kN maximum vertical force. At 55,000 kg the ship has approximately 0.10 g net upward acceleration at full output; hover requires about 91% output. This makes fully loaded takeoff intentionally marginal/sluggish.
- Main rear vane: 1.50 gross TWR = approximately 809.3 kN forward thrust.
- Side HUD was made visible in external/third-person view. Central windshield symbology remains cockpit-only.
- Transparent-alpha blending was corrected to premultiplied alpha; that change alone did not restore the missing central display.
- Thermal performance is **not implemented**: vane temperature does not yet affect output, wear, sputter, alignment or failure probability. The GDD's proposed cold/warm/overdrive/critical behavior remains a future phase.

## Phase 2Q — Windshield render-path hardening

- Moved the SubViewport out of the `FlightHUD` CanvasLayer and made it a direct child of the ship. The render target is now independent of screen-space HUD visibility/parenting.
- Explicitly configured the render target as 1280×720, transparent, 2D-only and `UPDATE_ALWAYS`.
- Receiving 3D material uses premultiplied-alpha blending, `no_depth_test`, disabled depth writes, disabled culling and late render priority so cockpit geometry cannot occlude the combiner symbols.
- Added a regression test that samples the actual SubViewport image and requires non-transparent output. This catches the earlier failure mode where all nodes existed but no visible texture content was verified.
- Added compass heading wrap tests around north.
- Runtime result still needs confirmation in Godot 4.7.2 on the user's machine. Do not claim the windshield projection is fixed until the HUD image test passes and the user confirms it appears in the cockpit.

## Current file/architecture notes

- `scripts/flight_hud.gd`: builds side HUD and physical windshield projection; the viewport lives under the ship, separate from the CanvasLayer.
- `scripts/flight_hud_overlay.gd`: central/side symbology rendering and compass/attitude projection math.
- `scripts/flight_sensor_suite.gd`: instrument data packet and per-channel validity.
- `scripts/ship_flight_controller.gd`: gathers ship + subsystem telemetry and passes it to `FlightHUD`.
- `scripts/repulsorlift_system.gd` and `scripts/vane_controller.gd`: convert fixed authority ratings to forces and allocate vane resultant forces.
- `data/vanes/*.tres`: vane position and nominal authority definitions.
- `scenes/ship.tscn`: ship mass and component hierarchy.
- `docs/GAME_DESIGN_DOCUMENT_v0_1.md`: authoritative concept/design rules, including cargo, vane temperature and future systems.

## Next verification steps

1. Run `tests/flight_hud_layout_test.gd` with the desktop renderer (not `--headless`); it must confirm non-transparent pixels in the windshield SubViewport texture and correct material/ownership configuration.
2. Run `tests/flight_path_marker_test.gd`, `tests/flight_sensor_suite_test.gd`, and the existing physics/display regression suite.
3. Manually inspect cockpit: central HUD visible on windshield, remains fixed while head-look moves, no cockpit geometry occlusion.
4. Manually inspect third-person: screen-fixed side instruments remain present; the physical windshield surface is not visible on the exterior camera.
5. Only after those checks pass should the project move on to environment profiles, a spaceport test scene, orbital environment, or thermal vane simulation.
