# Space Trucker — Development Changelog / Context Ledger

The master design authority is `GAME_DESIGN_DOCUMENT_v0_1.md`. This file records implementation state, known boundaries and deviations.

## Current baseline

- Godot 4.7.2 Stable, GDScript, GL Compatibility, Windows.
- Main scene: `res://scenes/test_range.tscn`.
- One `RigidBody3D` owns translation, rotation, mass, inertia and collisions.
- Flight model: simplified Newtonian motion, repulsorlift translation and maneuver forces, FCC assistance, atmosphere drag/wind and shield glide lift.
- Dry mass 30,000 kg; payload rating 25,000 kg; gross design mass 55,000 kg.
- Vane authority ratings use fixed gross design mass.

## 2N–2R — FCC, HUD and sensors

- Maneuver controls remain available whenever the field is online, even at zero main-vector throttle.
- Healthy redundant vanes may receive bounded partial redistribution, capped at 1.20× nominal authority.
- HUD sensor values come through the ship-owned `FlightSensorSuite`.
- Flight-path marker represents inertial velocity projected into the active camera view; outside the central field it uses a circle/X edge cue.
- Sensor channels have independent validity flags, but sensors are currently ideal (no modeled bias, drift or latency).
- Compass north is still a world reference; planetary environment profiles must later supply local tangent north.
- Current HUD is screen-space CanvasLayer with camera-alignment gating and side instruments in external view. The windshield SubViewport experiment is historical, not the current scene implementation.

## 2S — Vane thermal model

- Every vane has per-instance temperature, load, wear, integrity, failure and sputter state.
- Green-zone limits are load-dependent; cold authority clamps below 60°C; hot operation can provide a temporary 5% bonus before critical sputtering.
- Thermal load combines main-vector group allocation and per-vane maneuver contributions.
- **2U correction:** thermal state now advances once per repulsorlift update even while the field is offline or the ship is frozen. Offline vanes cool toward ambient and accrue no operating wear.
- Current coefficients produce rapid heating at high load. The previous 25–35 second full-power overheat documentation was incorrect and has been corrected in `INSTALL_PHASE_2S_THERMAL_MODEL.md`.
- The load model remains a game approximation, not a full heat-transfer network or electrical-energy simulation.

## 2T — Cargo subsystem

- `CargoSystem` attaches to the ship and calculates payload mass and combined COM.
- It updates the real rigid-body mass and custom COM; vane mounts remain fixed.
- F4 offers mass/offset sliders and presets; F3 reports mass and COM.
- **2U correction:** dry mass and payload capacity now derive from `ShipInteractable`, avoiding duplicate ratings.
- The cargo test now instantiates the actual ship scene and checks rigid-body mass/COM, payload clamping, force-induced torque and field-off thermal cooling.

## 2U — Thermal, cargo and FCC polish

- `RepulsorliftSystem` applies the main-field resultant at the fixed hull reference datum rather than forcing it through the current COM. Off-centre cargo therefore creates the intended lever-arm moment. Gravity itself is not treated as a torque source.
- FCC assisted mode now uses a bounded PI angular-rate controller with anti-windup. Existing P gain and output cap remain; trim cannot exceed available authority and cannot guarantee level flight for extreme cargo offsets.
- The HUD presents the distinction correctly: bounded rate trim, possible saturation and residual rotation.
- Added regression coverage for integral trim, anti-windup, field-off thermal cooling and actual cargo/rigid-body integration.
- No atmospheric drag, wind or shield-glide coefficients were changed in this pass.

## Architecture notes

- `scripts/ship_flight_controller.gd`: input, field state, FCC and telemetry routing.
- `scripts/flight_control_computer.gd`: bounded PI rate control in assisted mode; direct mapping when assistance is disabled.
- `scripts/repulsorlift_system.gd`: main and maneuver force/torque application; physics-tick thermal orchestration.
- `scripts/vane_controller.gd`: per-vane resultant math and thermal/condition state.
- `scripts/cargo_system.gd`: payload mass and COM; parent ship is the rating source.
- `scripts/flight_sensor_suite.gd`: instrument measurements and validity.
- `scripts/flight_hud_phase_2u.gd`: corrected cargo/trim presentation layered over the existing HUD.
- `docs/GAME_DESIGN_DOCUMENT_v0_1.md`: design source of truth.

## Verification status

The Phase 2U package includes headless regression tests. Runtime/parser validation must be run with the project's Godot 4.7.2 executable. Source review and ZIP integrity checks are not proof of runtime success.
