# Implementation history — Flight and ship-systems prototype

**Repository baseline reviewed:** `2c396eea61f5e949aa25d13b8732e92a20f8e6fa`  
**Commit title:** Fixes and polish pass  
**Review date:** 11 November 2026  
**Engine:** Godot 4.7.2 Stable · GDScript · GL Compatibility · Windows

This is the consolidated implementation record for Phases 2A–2U. It replaces the individual phase installation notes as the place to understand what each increment introduced, what was deliberately not included, and which later change superseded an earlier decision.

This is an implementation history, not a design authority. For intended game behavior, read the Game Design Document. For Phase 3 environment and travel implementation, read the Phase 3 specification. The current source tree and scenes are the final authority on what is implemented.

## Reading and authority rules

Use the documents in this order:

1. `docs/GAME_DESIGN_DOCUMENT_v0_1.md` — core game identity, confirmed design decisions, proposals and unresolved questions.
2. `docs/GDD_ANNEX_v0_3.md` — detailed and authoritative Phase 3 environment/travel specification.
3. `docs/FUTURE_PHASES.md` — concise roadmap for how Phase 3, later graphics/cockpit work and deferred proposals fit together.
4. `docs/IMPLEMENTATION_HISTORY.md` — what Phases 2A–2U actually changed, including superseded behavior.
5. `docs/AI_HANDOFF.md` — current architecture, constraints and development workflow.
6. `docs/TESTING.md` — current automated tests and manual regression procedures.

Do not use an old phase's install instructions as a description of current behavior. An earlier phase records what was true at that point in development; a later phase may have replaced it. In particular, do not resurrect the abandoned windshield SubViewport experiment or older thermal/cargo assumptions.

## Current implementation snapshot

The current repository is a **flight and ship-systems prototype**, not yet the complete space-trucking game.

Implemented foundations:

- Player walk-up, ship interaction and cockpit entry.
- One ship-owned `RigidBody3D` as the sole owner of ship translation, rotation, mass, inertia and collisions.
- Repulsorlift main-vector translation and vane-generated pitch, roll and yaw moments.
- Assisted and direct-vane flight-control modes.
- Atmospheric density, wind, quadratic drag and shield-generated glide lift.
- Cockpit/external camera switching, camera look/recentering, flight instruments and diagnostics.
- A ship-owned sensor-data boundary and inertial flight-path marker.
- Per-vane thermal state, cooling, wear, output derating/bonus, sputtering and failure.
- Abstract cargo mass and position that update the actual rigid-body mass and centre of mass.
- A seeded, visually readable test range used to validate flight.

Not yet implemented as complete gameplay systems:

- A contract/economy loop, physical cargo items, inventory or cargo-volume simulation.
- A planetary or orbital world, celestial-body framework, spaceport, docking system or hyperspace route.
- Walkable ship interiors beyond the current cockpit-entry foundation.
- A full reactor/APU/battery power network, active radiator-management system, repair gameplay or ship-personality system.
- Sensor bias, drift, lag, realistic instrument failure or terrain-relative radar altitude.
- A general mod manager or runtime-loaded ship pipeline.

The current project uses `scenes/test_range.tscn` as its regression environment. Do not replace it with a new environment scene; add later environments separately.

## Architecture established by the phases

The implementation is deliberately smaller than the full architecture envisioned by the GDD.

- `ShipInteractable` owns pilot occupancy/entry state and the ship's design mass ratings.
- `ShipFlightController` routes player input, manages field state, calls the FCC and sends the resulting commands to the physical force system.
- `FlightControlComputer` converts pilot requests and local angular-rate feedback into bounded pitch/roll/yaw commands.
- `RepulsorliftSystem` is the sole owner of repulsorlift force and torque application. It submits those forces during the physics update.
- `VaneController` owns per-ship runtime vane state, force-resultant calculations and thermal progression. Vane Resources remain configuration, not mutable runtime state.
- `AtmosphericFlightModel` applies the prototype atmosphere, wind, drag and shield-glide model.
- `FlightSensorSuite` produces instrument measurements and per-channel validity.
- `CargoSystem` updates the rigid body's mass and custom centre of mass from the abstract manifest.
- `FlightHUD` and `FlightHUDPhase2U` present telemetry. They must not own flight physics.
- `DisplaySettings` owns display-mode, window-resolution and HUD-scale settings.

The main physical rule is unchanged: all vanes influence one ship-wide fictional field. They are not independent rocket engines or separate rigid bodies. Grouped actuator contributions are combined into resultant forces and moments on the one ship body.

## Phase history

### Phase 2A — Flight-input and field-state foundation

**Purpose:** Establish a safe boundary between walking/boarding and ship-only controls.

**Implemented:**
- Added a ship-owned `ShipFlightController`.
- Added the OFF → STARTING → ONLINE field-state sequence and the initial 1.2-second startup delay.
- Added W/S field-power setpoint, Q/E vector-distribution setpoint and A/D yaw-command input.
- Added a telemetry-only HUD.
- Added a pilot-ready gate so the boarding key does not immediately toggle the field and flight controls cannot run before cockpit entry finishes.
- Kept ship-flight input separate from the player walking controller.

**Deliberate limit at this point:** No physical thrust, torque, vane allocation, mouse pitch/roll or atmospheric model. Commands were only state and telemetry.

### Phase 2B — Camera modes and virtual flight stick

**Purpose:** Make camera movement independent from ship movement and separate camera look from flight input.

**Implemented:**
- Added the external camera rig, SpringArm and external Camera3D.
- Added C to switch cockpit/external views.
- Added RMB camera-look mode. Camera look changes the selected camera only.
- Added a persistent mouse pitch/roll virtual-stick position in flight-control mode.
- Added Shift while in camera-look mode to release the cursor for future UI interaction.
- Added F3 diagnostics and external-camera wheel zoom foundation.

**Deliberate limit:** The ship remained physically frozen; camera and input architecture were being tested before flight forces were introduced.

### Phase 2C — Rigid-body baseline and test pad

**Purpose:** Verify that Godot's rigid-body integration, collision and sleep behavior were stable before adding propulsion.

**Implemented:**
- Enabled normal integration on the ship's single RigidBody3D.
- Added/adjusted landing-pad collision and ground collision so the ship could settle onto the pad.
- Enabled natural sleeping.
- Added external-camera zoom limits and basic rigid-body diagnostics.

**Deliberate limit:** No propulsion or vane force model yet. This was a physics-baseline phase.

### Phase 2D — Collective repulsorlift

**Purpose:** Produce real vertical acceleration without scripting ship position or attitude.

**Implemented:**
- Added `RepulsorliftSystem`.
- W/S field output now creates a central lift force opposite gravity.
- Added lift force, TWR and hover-threshold telemetry.
- Kept the ship on the one RigidBody3D.

**Initial behavior later superseded:** Lift was a simple collective force through the centre of mass; Q/E still did not steer the force vector in this increment. Initial TWR was a provisional current-mass-style prototype value. Later phases introduced the main-vector mapping and fixed gross-mass force rating.

### Phase 2E — Vane definitions and resultant mathematics

**Purpose:** Represent vane placement and condition as data, and calculate how asymmetric vane authority changes force and moment.

**Implemented:**
- Added `VaneDefinition` Resources for the four bottom vanes and the rear/main vane.
- Added `VaneController` with per-ship runtime integrity, failure and alignment state. Shared Resource definitions are not used as mutable per-ship state.
- Split bottom vanes into front/rear and left/right logical groups.
- Calculated per-vane force contributions, weighted effective application points and group resultant force/torque about the current centre of mass.
- Added deterministic force-model tests.

**Deliberate limit:** This phase calculated and displayed the moments, but did not yet apply the maneuver torque to the rigid body. That was added in Phase 2F.

**Configuration note:** The five initial vane Resources use provisional positions inside the placeholder hull. Their positions are data, not final ship-design dimensions. Two side-vane Resources were added with the FCC/force-allocation work.

### Phase 2F — Physical vane torque and control correction

**Purpose:** Make the force-resultant math move the ship physically.

**Implemented:**
- Applied group resultant forces at their contribution-weighted application points.
- Applied the residual pure torque needed when aligned vane directions cannot be represented by one point force.
- Pitch, roll and yaw now result from force/torque on the single rigid body rather than directly changing the ship transform.
- Added a physics integration test for asymmetric vane condition.
- Corrected mouse pitch convention to aircraft-style virtual-stick behavior: mouse up requests nose-down; mouse down requests nose-up.
- Established the current 0° forward, 90° up/VTOL and 110° up/rearward braking-blend vector convention.

**Deliberate limit:** This was still pre-FCC assistance. The force allocation and available authority were intentionally simple and tunable.

### Phase 2G — FCC foundation

**Purpose:** Convert pilot intent into controllable angular-rate response while preserving a direct mode.

**Implemented:**
- Added the `FlightControlComputer`.
- Assisted mode converts normalized pitch/roll/yaw requests into ship-local angular-rate setpoints and applies bounded rate-error control.
- V mode switches assistance off and restores direct shaped vane commands.
- Added deadzone, input curve, requested/actual rate telemetry, saturation reporting and local-axis extraction.
- Kept the FCC separate from the force allocator: the FCC commands; `RepulsorliftSystem` calculates and applies physical forces.
- Added bounded healthy-vane redistribution in later refinement; the values now in use are recorded below under 2N.

**Important behavior:** This is rate control, not attitude hold. Zero stick requests zero angular rate; it does not request a return to level or to a previous heading.

### Phase 2H — Cockpit flight HUD

**Purpose:** Replace the temporary telemetry readout with readable piloting instruments.

**Implemented:**
- Added field-power and vector-angle tapes with separate setpoint/actual indications.
- Added central flight data, attitude ladder, reference symbol, persistent pitch/roll control viewer, yaw/rudder indicator and status.
- Expanded F3 diagnostics to show FCC, force, vane and rigid-body information.
- Kept normal cockpit instruments presentation-only.

**Initial measurement limitations:** Altitude and vertical speed were initially tied to world Y/test-range assumptions. Later atmospheric/sensor work moved these toward a local-up model. The display has never been a substitute for terrain/radar altitude.

### Phase 2I — Display scalability and settings

**Purpose:** Make the interface usable across common window sizes and aspect ratios.

**Implemented:**
- Added windowed, borderless-fullscreen and exclusive-fullscreen settings.
- Added supported window-resolution selection, subject to monitor work-area limits.
- Added 80%, 90% and 100% HUD scale options.
- Preserved the 1280×720 reference layout and scaled it uniformly.
- Positioned side gauges for wider aspect ratios without stretching the central instruments.
- Added F10 and Escape settings-panel behavior and a display-settings regression test.

### Phase 2J — Atmospheric drag foundation

**Purpose:** Introduce a distinct atmosphere model while preserving Newtonian motion.

**Implemented:**
- Added `AtmosphericFlightModel`.
- Added exponential density falloff with altitude.
- Added air-relative velocity and quadratic drag.
- Added projected hull area using current attitude.
- Added atmosphere enable/disable and F3 telemetry for density, wind/relative velocity and drag.
- Kept aerodynamic drag as a central force in this first approximation to avoid introducing unvalidated aerodynamic moments.

**Deliberate limit:** The model is not CFD and does not yet use terrain-relative altitude or a complete planetary atmosphere profile.

### Phase 2K — Wind and input-response refinement

**Purpose:** Add a reproducible wind disturbance and improve fine control near stick centre.

**Implemented:**
- Added configured mean wind and coherent low-amplitude turbulence to the test atmosphere.
- Published mean wind, turbulence, current wind, air-relative velocity and drag diagnostics.
- Added symmetric input deadzone and linear-to-cubic response shaping to the FCC input path.
- Corrected the F3 text presentation so long diagnostic output remains readable.

**Deliberate limit:** The wind is a test-range disturbance, not a general weather system. Atmospheric coefficients were not replaced by a realistic global climate model.

### Phase 2L — Shield-generated glide lift

**Purpose:** Model the fictional particle-shield lifting-body effect so the ship can glide in atmosphere.

**Implemented:**
- Added a shield-generated lift force distinct from ordinary drag.
- Lift depends on air density, air-relative speed, signed angle of attack, projected ship-up direction and configured shield effectiveness.
- Added a low-speed gate and bounded post-stall reduction.
- Added F3 telemetry for angle of attack, lift coefficient, speed gate, lift force and direction.
- Preserved the distinction between fictional shield lift and conventional wing aerodynamics.

**Prototype tuning values at introduction:** 36 m² effective area, maximum lift coefficient 1.10, nominal stall angle 20°, low-speed gate beginning at 5 m/s and reaching full effect at 18 m/s. These are game parameters, not real-world aerodynamic data.

### Phase 2M — Initial flight-path marker and test-range visual references

**Purpose:** Give the pilot an immediately readable visual reference for flight path and ground movement.

**Implemented:**
- Added the first cockpit flight-path marker based on velocity relative to the ship's nose/reference.
- Reduced HUD symbology to 90% of its previous reference size and refined line/font weights.
- Replaced the featureless range with a seeded 1,000 m × 1,000 m textured ground plane, survey grid, approach strip, landing-pad markings, boundary beacons, distant faceted ridges and a wind-direction arrow.
- Kept test-range geometry generated from project resources/code rather than relying on a large external texture.

**Superseded later:** The initial marker behavior and its projection limits were replaced by the perspective-projected inertial FPM in 2R.

### Phase 2N — HUD and FCC corrections

**Purpose:** Correct instrument references and preserve maneuver authority at low main-vector power.

**Implemented:**
- Used the atmospheric model's local-up vector for altitude and vertical speed rather than hard-coding world Y.
- Kept pitch/roll/yaw maneuver control available whenever the field is ONLINE, even at zero main-vector throttle.
- Added up to a capped 20% maneuver reserve increase as main-vector power approaches zero.
- Added partial damaged-vane redistribution in assisted mode: 50% of the damage deficit may be redistributed, only into healthy spare capacity, with healthy vanes capped at 1.20× nominal.
- Kept direct-vane mode free of FCC redistribution.
- Adjusted head-look-aware HUD projection.
- Kept atmospheric drag, wind and shield-glide equations unchanged in this correction.

**Superseded detail:** The earlier 2N description used air-relative velocity for the FPM in meaningful atmosphere. Phase 2R establishes the current FPM as inertial velocity; the air-relative speed indication remains separate.

### Phase 2O — Windshield HUD experiment and sensor-data boundary

**Purpose:** Explore ship/window-fixed central symbology and separate instrument measurement from drawing.

**Implemented or specified in this experimental branch of work:**
- A transparent SubViewport rendered central symbology onto a 3D windshield quad attached to the ship.
- Side gauges and the control viewer remained screen-space.
- The central ladder used perspective/tangent projection; compass heading was projected onto a horizontal plane.
- A ship-owned `FlightSensorSuite` was established as the intended boundary between physical simulation and instrument display. It publishes attitude, heading, velocity and altitude measurements with independent validity.

**Superseded rendering path:** The windshield SubViewport implementation did not render reliably in the user's runtime. Node-existence checks were insufficient. Phase 2Q returned to the stable screen-space CanvasLayer design. The sensor-data boundary remains part of the current architecture; the abandoned windshield rendering path does not.

### Phase 2P — Fixed design-mass rating

**Purpose:** Make cargo increase inertia and reduce acceleration without silently increasing the engine rating.

**Implemented:**
- Set prototype freighter dry mass to 30,000 kg.
- Set design payload capacity to 25,000 kg.
- Established 55,000 kg design gross mass.
- Rated vane authority against that fixed gross mass, rather than the current loaded mass.
- At 1.10 gross TWR, the nominal bottom-vane set is approximately 593.5 kN at 9.81 m/s² reference gravity.
- The rear/main vane remains rated at 1.50 gross TWR, approximately 809.3 kN on the same design rating basis.

**Important:** Cargo itself was not part of 2P. The cargo subsystem arrived in 2T. No cargo mass should cause the force rating to scale upward.

### Phase 2Q — Stable HUD and cockpit recentering

**Purpose:** Restore predictable HUD behavior after the unsuccessful windshield experiment.

**Current behavior established:**
- The normal flight HUD is a screen-space CanvasLayer/Control implementation.
- Side power/vector gauges and the pitch/roll/rudder control viewer remain visible in cockpit and external views (unless F3 diagnostics are open).
- Central heading tape, flight data, attitude ladder and FPM are limited to cockpit view while the cockpit camera is within 0.5° of default boresight.
- RMB toggles camera-look mode. Returning to flight control starts a 3-second delay; if the pilot does not re-enter look mode, the cockpit camera smoothly recenters.
- Heading wraps through north and is calculated from the forward vector projected onto the local horizontal plane.
- Attitude ladder spacing uses tangent-based perspective projection rather than a constant pixels-per-degree approximation.

**Current architecture rule:** Do not reintroduce the historical SubViewport windshield overlay without a new, separately verified implementation and actual rendered-pixel/runtime evidence.

### Phase 2R — Inertial FPM and sensor suite integration

**Purpose:** Make the velocity marker unambiguously represent where the ship is travelling and keep instrument calculations out of the HUD.

**Current behavior:**
- The FPM represents world-space inertial linear velocity, not nose direction and not air-relative velocity.
- Projection uses the active camera basis and its actual vertical FOV.
- The marker is centered when velocity aligns with the boresight and suppressed below 2 m/s.
- When its projected direction leaves the central HUD field, the cue moves to the HUD boundary and changes to a same-size circle with an X. Rearward vectors use the selected edge rule, including a bottom-centre cue for directly aft velocity.
- The HUD reads the sensor packet for attitude, heading, inertial velocity, air-relative velocity/speed, local altitude and vertical speed.
- Sensor channels can be invalidated independently. The current sensors are ideal; bias, drift, latency and modeled failures are future work.

**Reference-frame limitation:** The current compass uses world north. A planetary environment profile must provide a proper local tangent north reference. Current altitude is not terrain/radar altitude.

### Phase 2S — Vane thermal simulation

**Purpose:** Make vane temperature and degradation affect available authority and operational risk.

**Current model, including the 2U correction:**
- Each vane has its own temperature, load fraction, integrity, wear rate, failure and sputter state.
- Load-dependent green zone: lower bound is 60°C × load^0.7; upper bound is 180°C − 20°C × load.
- Online heat input: 3°C/s + 22°C/s × load².
- Cooling: 0.05/s × (vane temperature − ambient temperature).
- Baseline integrity wear inside the green zone: 0.000002/s.
- Outside the green zone: baseline plus 0.000008 × temperature_delta² × load² per second.
- Below 60°C, usable authority is clamped from 70% toward 100% as the vane warms from −10°C to 60°C.
- Above 180°C and up to 230°C, a temporary 5% output bonus is applied.
- Above 230°C, or below 20% integrity, the vane may sputter. Integrity reaching zero fails it.
- Thermal load is derived from main-vector allocation plus per-vane maneuver contributions from the force allocator.

**2U correction:** Thermal state advances every repulsorlift physics update, including when the field is offline or the body is frozen. Offline vanes have zero load, do not accrue operating wear, and cool toward ambient. A zero/invalid time step uses the configured physics tick as a fallback.

**Model boundary:** This is a game-tuned actuator-load approximation, not a full thermodynamic simulation, electrical-energy solution or thermal network between vanes/radiators. High-load heating is rapid; do not repeat the older 25–35 second overheat claim.

### Phase 2T — Cargo manifest and centre of mass

**Purpose:** Make abstract payload mass and distribution affect actual ship physics.

**Implemented:**
- Added a dedicated CargoSystem node.
- Cargo is represented by a payload mass and one position within the hold, not individual crate rigid bodies.
- Combined COM is calculated from dry-hull mass/COM and payload mass/position.
- The subsystem sets the actual RigidBody3D mass and custom centre of mass; vane mounting points do not move.
- F4 provides mass and X/Y/Z cargo-offset controls and empty, half, maximum, port-heavy, starboard-heavy, nose-heavy and aft-heavy presets.
- Cargo limits are clamped to the ship's rated payload capacity.

**2U correction:** Dry mass and payload capacity are read from the parent ShipInteractable. CargoSystem does not maintain a competing set of exported mass ratings.

**Hover readout limitation:** The F4 hover figure is a nominal 1g estimate based on the fixed design rating. It is not a guarantee; it excludes local-gravity changes, thermal derating, damage and the actual current force allocator limits.

### Phase 2U — Thermal, cargo and FCC polish

**Purpose:** Correct the integration gaps discovered after 2S/2T and make asymmetric cargo affect actual flight behavior without promising perfect compensation.

**Implemented:**
- Moved thermal progression to a once-per-physics-update path that continues while the field is off or the body is frozen. Offline vanes cool and do not accrue operating wear.
- Reworked thermal load input to combine main-vector group allocation with the actual per-vane maneuver force contributions for that physics update.
- Applied the main-field resultant at the fixed hull reference datum (the rigid-body origin), rather than artificially applying it through the shifted COM. The shifted COM therefore produces a genuine lever-arm moment under main-field force. Gravity itself is not treated as a torque source just because the COM moved.
- Changed assisted FCC mode to bounded PI angular-rate control with anti-windup. The existing proportional response, maximum output cap, direct-vane mode and partial damaged-vane redistribution remain.
- The integral trim can retain a bounded counter-command against a persistent disturbance, but it is cleared when control authority is unavailable or assistance is disabled.
- Kept the FCC a rate controller, not an attitude-hold system. If the disturbance exceeds available vane authority, the output saturates and residual rotation remains.
- Made CargoSystem derive mass ratings from ShipInteractable and made the F4 slider follow the ship-authored payload capacity.
- Updated the F4 cargo panel and F3 diagnostics to report the force-lever-arm explanation and bounded PI-trim state accurately.
- Added integration coverage for actual ship mass/COM, main-field torque, payload clamp and offline thermal cooling.

**PI prototype tuning defaults:** proportional rate-response gain 0.8; integral gain 0.12; per-axis integral-trim limit 0.25; overall assisted output limit 0.8. These are current implementation values, not immutable game-balance commitments.

## Superseded statements and traps for future agents

| Earlier statement or implementation | Current rule |
|---|---|
| Phase 2D collective lift always passed through the moving COM. | Phase 2U applies the main-field resultant at the fixed hull reference datum; an offset COM creates the intended moment. |
| Cargo offset creates a “gravity moment”. | Incorrect. Gravity acts through the combined COM. The relevant prototype moment comes from the main-field force acting away from the shifted COM. |
| FCC has no integral term. | Superseded in 2U. Assisted mode is bounded PI angular-rate control with anti-windup. |
| FCC keeps the ship level or guarantees compensation for asymmetric cargo. | Incorrect. It is not attitude hold; integral trim is bounded and residual rotation is expected when authority is insufficient. |
| Thermal behavior stops when the field is off. | Superseded in 2U. Thermal progression continues; offline vanes cool without operating wear. |
| Full-power overheat takes 25–35 seconds. | Outdated. With current coefficients and load-dependent green-zone limits, heating is much faster. Use current runtime diagnostics and the updated thermal test. |
| FPM represents air-relative velocity in atmosphere. | Superseded in 2R. FPM represents inertial/world velocity. The airspeed instrument remains air-relative in atmosphere. |
| The physical windshield SubViewport is the active HUD. | Incorrect. The current HUD is screen-space CanvasLayer/Control with cockpit alignment gating. The windshield SubViewport experiment is historical. |
| The central HUD follows the camera during head-look. | No. Central symbology is hidden when the cockpit camera is off boresight; side instruments remain screen-fixed. |
| Thermal and cargo systems are future/unimplemented. | Outdated. Both are implemented as prototype systems in 2S/2T and corrected in 2U. |
| Cargo is physical crates or a complete cargo economy. | Incorrect. Current cargo is one abstract mass/position manifest, not a crate/inventory/contract system. |
| Sensor values include realistic error or planetary references. | Not yet. Sensors are currently ideal; world north and local altitude datum still need environmental integration. |

## Current file map

| Responsibility | Current files |
|---|---|
| Ship body, pilot occupancy and design mass ratings | `scripts/ship_interactable.gd`, `scenes/ship.tscn` |
| Player entry and walkaround controls | `scripts/player_controller.gd`, `scenes/player.tscn` |
| Flight input, field state and telemetry assembly | `scripts/ship_flight_controller.gd` |
| FCC rate control and trim | `scripts/flight_control_computer.gd` |
| Force/resultant application and thermal orchestration | `scripts/repulsorlift_system.gd` |
| Vane definitions, runtime condition, resultant mathematics and thermal state | `scripts/vane_definition.gd`, `scripts/vane_controller.gd`, `data/vanes/*.tres` |
| Atmosphere, wind, drag and shield glide lift | `scripts/atmospheric_flight_model.gd` |
| Instrument data and channel validity | `scripts/flight_sensor_suite.gd` |
| Cargo mass and COM | `scripts/cargo_system.gd` |
| Cockpit/external camera and recenter | `scripts/ship_camera_controller.gd` |
| Normal HUD, Phase 2U cargo/trim presentation and display settings | `scripts/flight_hud.gd`, `scripts/flight_hud_phase_2u.gd`, `scripts/flight_hud_overlay.gd`, `scripts/display_settings.gd` |
| Force visualization and test range | `scripts/force_vector_debug.gd`, `scripts/test_range_environment.gd`, `scenes/test_range.tscn` |

## Regression test inventory

These tests exist in the current repository. Their presence does not prove they have passed in the current checkout; see `docs/TESTING.md` for commands and validation rules.

- `tests/flight_force_control_test.gd`
- `tests/vane_force_model_test.gd`
- `tests/vane_physics_integration_test.gd`
- `tests/flight_control_computer_test.gd`
- `tests/flight_control_trim_test.gd`
- `tests/phase_2j_flight_model_test.gd`
- `tests/test_range_environment_test.gd`
- `tests/display_settings_test.gd`
- `tests/flight_path_marker_test.gd`
- `tests/flight_sensor_suite_test.gd`
- `tests/flight_hud_layout_test.gd`
- `tests/flight_hud_phase2u_test.gd`
- `tests/vane_thermal_model_test.gd`
- `tests/cargo_system_test.gd`

## Development rules preserved across all phases

- Inspect the current branch and relevant source files before editing; do not rely on an old ZIP or chat summary.
- Keep the single RigidBody3D as the physical authority.
- Apply physical forces and update physical subsystems from the physics-tick path.
- Keep input, control law, actuator/force allocation, physical integration, sensors and HUD presentation separated.
- Do not silently tune atmosphere, flight feel, thrust ratings or thermal coefficients during an unrelated polish pass.
- Keep test-range regression scenes separate from future planet/orbit/spaceport scenes.
- Add focused tests for new behavior and run the full relevant regression suite.
- For visual behavior, node existence is not sufficient; inspect actual rendered output.
- Never report a test as passing unless it was actually run with the project's pinned Godot version.
