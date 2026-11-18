# SPACE TRUCKER --- GDD ANNEX AND IMPLEMENTATION SPECIFICATION

## Version 0.3 --- Environment, local space, and fixed-route hyperspace vertical slice

**Document status:** Authoritative Phase 3 annex (v0.3 Complete — Release Gate 0.3.8)\
**Target project:** `OvalDreamX/Gd-Proyect`\
**Target engine:** Godot 4.7.2 Stable, standard GDScript build\
**Renderer:** GL Compatibility\
**Platform:** Windows PC\
**Date:** 14 November 2026

------------------------------------------------------------------------

# 0. Authority, scope, and how this document must be used

## 0.1 Authority over the original GDD

This document is an authoritative annex to
`docs/GAME_DESIGN_DOCUMENT_v0_1.md`.

For Phase 3 / version 0.3, this annex **overrides the original GDD
wherever the two documents conflict**, especially in:

-   the gameplay structure of local planetary flight, local space, and
    hyperspace travel;

-   the simulation of the universe and celestial objects;

-   the meaning and scope of orbital mechanics;

-   the Phase 3 deliverable and implementation order;

-   the Phase 3 technical architecture and testing requirements.

It does **not** erase or silently rewrite unrelated confirmed concepts
from v0.1. The original GDD remains authoritative for the game's broader
identity, ship systems, repulsorlift concept, FCC, vane behavior, cargo
philosophy, ship-care ideas, economy direction, and long-term world tone
unless this annex explicitly changes a point.

If a future implementation agent finds a contradiction:

1.  Follow this annex for Phase 3 environment/travel work.

2.  Preserve the original GDD for unrelated systems.

3.  Do not infer that a proposal is confirmed merely because it appears
    in either document.

4.  Report any unresolved contradiction before making an irreversible
    architectural choice.

## 0.2 Status vocabulary

-   **CONFIRMED:** Explicitly chosen by the project owner.

-   **PHASE 3 REQUIREMENT:** Must be implemented and tested for the v0.3
    exit criteria.

-   **RECOMMENDED DESIGN:** The default implementation choice unless
    repository inspection reveals a concrete incompatibility.

-   **PLACEHOLDER:** A provisional value or simplified behavior used to
    complete the vertical slice.

-   **STRETCH:** Optional only after all required acceptance tests pass.

-   **OUT OF SCOPE:** Must not be implemented during Phase 3.

-   **TBD:** Deliberately unresolved; do not invent a permanent answer.

## 0.3 Phase 3 in one sentence

**Phase 3 builds the minimum coherent playable world around the
already-developed freighter: one small traversable spherical test planet with a usable surface
port and distant outpost, a local-space departure/arrival environment, one large cube-shaped
orbital station, and a fixed, pre-programmed hyperspace route that lets
the player depart the planet, jump to the station, approach it, and jump
back.**

The purpose is to prove the environment/travel architecture and the
complete physical travel loop, not to build a universe generator.

## 0.4 Mandatory implementation discipline

This is a design and implementation specification, not permission to
rewrite the project wholesale.

The coding agent must:

1.  Inspect the current repository and current `main` branch before
    editing. Do not assume earlier chat summaries describe the latest
    files.

2.  Read the original GDD, this annex, the current `project.godot`,
    relevant scenes/scripts, and the most recent phase handoff/install
    notes.

3.  Identify existing systems that can be extended. Reuse them where
    sound; do not create parallel replacements for the ship controller,
    HUD, environment model, or interaction system without a demonstrated
    reason.

4.  Produce a short repository-specific implementation plan before
    changing files.

5.  Work in small, independently testable milestones. One milestone
    should have one main technical objective.

6.  Preserve working behavior and existing controls unless a change is
    required and explicitly described.

7.  Prefer complete, overwrite-ready files over partial code fragments
    when handing work to the project owner.

8.  Never claim that code was run or tested unless the exact test was
    actually executed.

9.  Do not mark a milestone complete when it only parses or when
    node-existence tests pass. Verify runtime behavior and, for visual
    systems, inspect actual rendered output.

10. Keep the project opening and running in the pinned engine version
    throughout the phase.

The project owner is technically experienced in engineering and 3D
modeling but is still learning software architecture and GDScript.
Explain significant design choices and test procedures, but do not bury
the handoff in beginner-level explanations of every line.

------------------------------------------------------------------------

# 1. Phase 3 design decisions

## 1.1 The three gameplay environments

The game has three distinct operational modes. They are not three
unrelated minigames; they are three representations of one coherent
trip.

### A. Planetary flight --- continuous local simulation

The player flies the actual ship in a local planetary environment.

Simulated continuously:

-   the player's ship rigid body and its existing
    flight-control/repulsorlift systems;

-   local gravity and local up direction;

-   atmospheric density and wind where enabled;

-   drag and shield-generated lift using the existing atmospheric model;

-   nearby terrain collision;

-   landing pads and other local collision geometry;

-   nearby authored objects that can affect flight.

Phase 3 must not replace the existing ship flight model with a scripted
movement path. The environment supplies physical conditions; the ship
remains the owner of its own physics.

### B. Local space --- continuous local simulation

The player flies the same ship in a local space scene around the orbital
station.

Simulated continuously:

-   the player's ship and existing flight systems;

-   local inertial movement;

-   negligible or zero atmospheric drag;

-   local station geometry and collision;

-   nearby static navigation/approach references;

-   docking/landing interaction sufficient to establish arrival.

There is no requirement to simulate the entire planetary system as a
huge live scene.

### C. Hyperspace --- abstracted transition

Hyperspace is a calculated transition, not continuous flight through
every kilometre of the route.

The transition:

1.  validates the ship's departure conditions;

2.  records the departure state;

3.  calculates a deterministic travel duration and arrival result;

4.  advances the simulation clock;

5.  resolves the destination's current reference-frame position;

6.  unloads the departure local scene and loads the destination local
    scene;

7.  places the ship at a calculated arrival position and orientation;

8.  returns control to the player after the transition.

A hyperspace effect/loading screen can conceal scene loading. It must
not be the source of gameplay logic. The calculation and state
transition must be independent of the visual effect.

## 1.2 Phase 3 gameplay loop

The required vertical slice is:

1.  Start in or beside the ship at the planetary starport.

2.  Enter the cockpit and bring the existing flight systems online.

3.  Take off and fly away from the port.

4.  Climb through the atmosphere and reach the designated **jump-entry
    envelope**.

5.  Receive a clear indication that the fixed jump is available.

6.  Initiate the programmed jump to the orbital station.

7.  See a short hyperspace transition.

8.  Arrive in the station's local-space environment with the station
    visible and within a reasonable approach distance.

9.  Manoeuvre physically to the station and complete a basic
    docking/arrival interaction.

10. Initiate the pre-programmed return jump.

11. Arrive at a defined planetary upper-atmosphere/space approach point.

12. Fly the ship back through the atmosphere and land at the starport.

The fixed route is already present in the ship's computer as a test
fixture. The player does not need to create, edit, discover, name, or
manage waypoints in Phase 3.

## 1.3 Phase 3 world content

**Required:**

-   One test planet (upgraded in 0.3.8 to a closed 360° 60 km Simple Planet globe).

-   One surface starport/spaceport with a landing pad.

-   One local departure envelope or transition boundary.

-   One orbital station represented by a large, simple cube.

-   One local-space scene around the station.

-   One fixed outbound jump and one fixed return jump.

-   A reliable way to reset the test scenario.

**Implemented stretch content (0.3.8):**

-   `Horizon Outpost` settlement ~23.9 km northeast of Starport Alpha on the curved globe, reachable by flight and selectable via surface nav (`N`).

-   Deterministic 3D harmonic continents/ridges and parallax outcrops for altitude/speed perception.

-   Orbital limb `AtmosphereHalo` visible above 3,000 m and on planetary jump return.

The settlement is not a second gameplay system; it is an authored visual/physical location with no economy, NPC schedule, interior, or mission logic.

## 1.4 What the station is

The station is a large cube-shaped structure, intentionally simple. Its
purpose is to provide:

-   a strong visual reference in space;

-   a target for approach and manoeuvring;

-   a scale reference for the ship;

-   a place to test local-space navigation and docking.

It does not need a finished interior, walkable deck, rotating habitat,
traffic, NPCs, or functional station services.

### Station orbit and arrival model

**RECOMMENDED DESIGN:** Treat the station as an orbital destination
whose system-level position is data-driven, but load a compact
local-space scene around it after the jump.

For Phase 3:

-   Do not attempt full orbital rendezvous or continuous station/planet
    simulation.

-   Do not label an orbit "geostationary" unless the station's
    equatorial orbit period is actually matched to the planet's rotation
    period.

-   The system may use a simple circular orbit or a fixed high-orbit
    anchor for calculating a destination transform.

-   The local station scene can use a stable local origin and a fixed
    station position while the player performs the approach.

-   The jump return resolves to a planetary entry location, not
    necessarily to the exact departure coordinates.

The player should physically fly from the arrival point to the station.
The jump itself handles the long-distance transfer.

------------------------------------------------------------------------

# 2. Phase 3 boundaries

## 2.1 Explicitly in scope

-   Environment data model sufficient to describe the test planet and
    station.

-   A local coordinate-frame contract for the ship and environment.

-   Planet-local gravity/up/north supplied to existing flight/sensor
    systems where needed.

-   A small, controllable spherical planetary environment (upgraded in 0.3.8 from the initial flat terrain patch to a closed 60 km Simple Planet cube-sphere).

-   A starport and landing pad + distant Horizon Outpost landing pad.

-   A station local-space environment.

-   One fixed route stored in data/resources.

-   Jump eligibility validation.

-   Deterministic jump calculation and arrival resolution.

-   Scene transition/loading flow.

-   Return jump.

-   Debug telemetry for environment, jump, and arrival state.

-   Automated tests for pure calculations and state transitions.

-   Runtime acceptance tests in Godot 4.7.2.

-   Documentation and an install/verification handoff.

## 2.2 Explicitly out of scope

Deferred beyond Phase 3:

-   A general waypoint editor or full five-letter navigation network.

-   Multiple star systems or a procedural galaxy.

-   Quadtree terrain streaming, runtime planetary LOD, or multi-planet procedural generation.

-   Voxel terrain, caves, overhangs, or destructible terrain.

-   Full N-body simulation or orbital transfer solvers.

-   Full geostationary-orbit simulation.

-   A physically continuous journey through hyperspace.

-   Miss-jumps, interdiction, jump interruption, or random arrival hazards.

-   Dynamic traffic, piracy, patrols, or combat.

-   Economy, contracts, cargo transfer, reputation, NPCs, settlement simulation, or station services.

-   Walkable station interiors.

-   Volumetric clouds, weather simulation, or advanced shaders.

-   Custom engine builds, Large World Coordinates builds, C++ GDExtensions, or compute shaders.

-   A replacement ship physics/flight architecture.

## 2.3 Why the scope is deliberately narrow

The objective is to validate a complete travel loop, not to prove that
every future feature is technically possible. A small set of
deterministic scenes and fixed destinations gives the project a strong
test bed for:

-   local flight under different gravity/atmosphere conditions;

-   entering and leaving a planetary environment;

-   loading and unloading local simulation scenes safely;

-   preserving ship state across transitions;

-   advancing time without simulating every intermediate frame;

-   approaching and docking with a large structure.

------------------------------------------------------------------------

# 3. Core technical principles

## 3.1 Preserve the existing ship simulation

The existing ship is a single `RigidBody3D` with force/torque systems.
Keep that design.

-   Do not make the vanes individual rigid bodies.

-   Do not drive the ship by setting its transform every frame.

-   Do not implement separate "planet flight" and "space flight" ship
    controllers.

-   Environment state should change the forces/conditions applied to the
    same ship.

-   Scene transitions may reposition the ship deliberately at a
    transition boundary, but ordinary movement remains physics-driven.

Any required changes to the flight model must be isolated and
regression-tested against the current test range.

## 3.2 Separate authoritative state from presentation

Use clear ownership boundaries:

-   **Simulation state:** current location ID, current environment ID,
    simulation time, ship physical state, jump state, current route leg.

-   **Definitions/data:** planet parameters, station parameters, route
    endpoints, arrival offsets, environment settings.

-   **Presentation:** terrain meshes, sky, lighting, station mesh,
    hyperspace visual, HUD labels.

-   **Transition orchestration:** validates, snapshots, unloads/loads,
    restores, and commits state.

The hyperspace visual must not own or calculate arrival logic. The
terrain mesh must not be the source of gravity. The station mesh must
not define its authoritative system position.

## 3.3 Deterministic and reproducible behavior

For a given saved/test state and route definition, the same jump should
produce the same:

-   travel duration;

-   destination environment;

-   arrival offset;

-   arrival orientation;

-   simulation-clock advance.

Do not use unseeded random values for required Phase 3 behavior.

## 3.4 Coordinate frames

1.  **System frame:** identifies the planet and station relative to one
    another.

2.  **Body frame:** positions/orientations relative to the planet center `(0, -60000, 0)`,
    including local radial up and local tangent north/east.

3.  **Local simulation frame:** the active Godot scene's coordinate
    space, where the ship and nearby objects are represented.

No custom double-precision Godot build is required for Phase 3.

## 3.5 Fixed physics and simulation time

-   Keep ship physics inside Godot's physics tick (`_physics_process`).

-   Do not apply forces from `_process`.

-   Do not use frame delta for jump arrival calculations.

-   The simulation clock advances by one explicit duration per committed jump.

------------------------------------------------------------------------

# 4. Architecture and responsibilities (Implemented)

-   **`EnvironmentProfile` / `CelestialBodyDefinition`:** `PlanetSurface` and `StationLocalSpace` data resources including altitude temperature curves and `mu / r^2` gravity.
-   **`EnvironmentManager` & `PlanetaryReferenceFrame`:** Supply local gravity vector, radial up, tangent north/east, and altitude-resolved atmospheric conditions.
-   **`SimulationClock`:** Autoload tracking monotonic `current_time_seconds` and `jump_count`.
-   **`FixedTestRouteDefinition` & `JumpCalculator`:** Pure route validation, envelope checking, and deterministic jump planning.
-   **`TransitionCoordinator` & `ArrivalResolver`:** State machine with anti-duplicate lock, hyperspace star-streak cover, radial terrain/station clearance, state restoration, and failure recovery.
-   **`ShipInteractable` & `VaneController`:** Authoritative `ship.json` hydration, convective + radiative cooling, and `75% / 50% / 25%` integrity wear & fault tiers.

------------------------------------------------------------------------

# 5. Planet and surface environment specification

## 5.1 Planet scale philosophy

Test planet radius is `R = 60,000 m` (`g_surface = 9.81 m/s^2`, `45,000 m` jump-entry envelope, `46,500 m` upper-atmosphere return point). Low-orbit horizon curvature and blue atmospheric limb scatter are visible directly from upper atmosphere without requiring full terrestrial scales.

## 5.2 Gravity and scale tuning

-   `g_surface = mu / R^2 = 9.81 m/s^2`; `g(r) = mu / r^2` pointing toward `PLANET_CENTER = (0, -60000, 0)`.
-   Payload mass increases rigid-body inertia without scaling vane thrust rating.

## 5.3 Departure envelope

-   `JumpEnvelopeEvaluator` enforces environment support, field `ONLINE`, not landed/in contact, `altitude_m >= 45,000 m` (planet) or outside `250 m` exclusion perimeter (station). HUD reports exact rejection code/text and progress.

## 5.4 Surface geography (Simple Planet — 0.3.8)

-   Closed 360° 6-face cube-sphere (`R = 60,000 m`, `32x32` visual / `20x20` collision per face) seamlessly stitched with an `18 m` tucked skirt around the high-detail `4,400 m` Starport Alpha basin (`56x56` visual / `28x28` collision).
-   Continuous 3D harmonic continent and ridge heightfield evaluated deterministically from unit radial direction.
-   `AtmosphereHalo` (`R = 62,600 m`) plus dynamic `Camera3D.far` scaling (`75,000–400,000 m`).

## 5.5 Starport Alpha & Horizon Outpost

-   **Starport Alpha** at the North Pole `(0, 0, 0)`: 26.4 m marked pad, control tower, cargo hangar, service block, approach beacons, and `Backspace` reset point.
-   **Horizon Outpost** at `~23.9 km` northeast (`OUTPOST_DIRECTION = Vector3(0.32, 0.92, -0.22).normalized()`), aligned to local spherical tangent basis with `OutpostPad` collider, hab module, comms mast, beacon lamp, and `Label3D`. Selectable as an active surface navigation target via **N**.

------------------------------------------------------------------------

# 6. Local-space station environment

-   `res://scenes/station_local_space.tscn`: 120 m Orbital Relay Cube 01 with collidable hull, glowing `+Z` docking bay trigger, `250 m` exclusion zone, zero gravity, and zero atmosphere.

------------------------------------------------------------------------

# 7. Fixed hyperspace route and transition system

-   `route_planet_to_station.tres`: Planet -> Station (`420 s` jump, arrives at `(0, 0, 450)`).
-   `route_station_to_planet.tres`: Station -> Planet (`420 s` jump, arrives at `(0, 46500, 1200)` pitched `-18°` toward Starport Alpha).

------------------------------------------------------------------------

# 8. Planetary departure and arrival flow

Outbound: Starport Alpha -> climb through cold tropopause cooling sweet spot (`~14 km`) -> cross `45,000 m` -> press **J** -> StationLocalSpace.  
Return: Dock/undock -> clear `250 m` -> press **J** -> arrive `46,500 m` above Simple Planet with visible curved horizon & `AtmosphereHalo` -> descend & land at Starport Alpha (or fly to Horizon Outpost via **N**).

------------------------------------------------------------------------

# 9. Implementation roadmap (v0.3 Complete)

-   **Phase 3A (0.3.1):** Repository audit & coordinate/environment contracts.
-   **Phase 3B (0.3.2):** `EnvironmentProfile`, `CelestialBodyDefinition`, `PlanetaryReferenceFrame`, and `EnvironmentManager`.
-   **Phase 3C (0.3.3–0.3.4):** `PlanetSurface` starport basin, local frame gravity, dynamic sky/fog, and `Backspace` reset.
-   **Phase 3D–3E (0.3.5):** `JumpEnvelopeEvaluator` (45 km / 250 m), `StationLocalSpace` cube station, and docking zone.
-   **Phase 3F (0.3.6):** `SimulationClock`, `FixedTestRouteDefinition`, `JumpCalculator`, `ArrivalResolver`, and `TransitionCoordinator`.
-   **Phase 3G-Pre (0.3.7–0.3.7b):** Authoritative `ship.json` hydration, Freighter aero rebalance, convective air radiators with cold tropopause curve, 8–10 min critical / 60+ min green wear, and tiered `75% / 50% / 25%` integrity faults.
-   **Phase 3H (0.3.8):** Closed 360° **Simple Planet** cube-sphere terrain, `Horizon Outpost`, `AtmosphereHalo`, dynamic `Camera3D.far`, spherical navigation (**N**), `simple_planet_loop_test.gd`, and v0.3 Release Gate.

------------------------------------------------------------------------

# 10. Testing strategy and quality gates

-   **Level 1 (Pure logic):** Spherical heightfield continuity, cube-sphere outward winding, `PlanetaryReferenceFrame` gravity & tangent basis orthogonality, `JumpEnvelopeEvaluator`, `JumpCalculator`, `VaneController` thermal/wear curves.
-   **Level 2 (Headless scene integration):** 14 Phase 2 regression suites + 9 Phase 3 suites covering live `RigidBody3D`, `PlanetSurface <-> StationLocalSpace` round-trip jumps, mass/cargo preservation, broken-route recovery, `Horizon Outpost` alignment, `AtmosphereHalo` limb visibility, and `reset_to_starport()`.
-   **Level 3 (Manual desktop GL Compatibility):** Inspect Starport Alpha seam, 14 km tropopause radiator cooling, 46.5 km curved horizon & blue limb glow, Horizon Outpost flight/landing, and repeatable round-trip loop in Godot 4.7.2.

------------------------------------------------------------------------

# 11. AI-assisted implementation protocol

1. Inspect the repository before editing.
2. Propose one milestone with clear scope, files, risks, and tests.
3. Implement cleanly using Godot 4.7.2 + GL Compatibility APIs only.
4. Run headless tests and inspect rendered desktop output before claiming runtime validation.
5. Package overwrite-ready files with project-relative paths (zero `.godot/` caches).

------------------------------------------------------------------------

# 12. Technical references

- Godot 4.7 Documentation (`RigidBody3D`, GL Compatibility renderer, `SurfaceTool`, `ConcavePolygonShape3D`).
- Space Trucker repository (`OvalDreamX/Gd-Proyect`).

------------------------------------------------------------------------

# 13. Phase 3 deliverables

- Playable `PlanetSurface` (closed 60 km Simple Planet + Starport Alpha + Horizon Outpost) & `StationLocalSpace` (Orbital Relay Cube 01).
- Deterministic fixed-route `TransitionCoordinator`, `SimulationClock`, `JumpCalculator`, and radial `ArrivalResolver`.
- Authoritative `ship.json` subsystem hydration, convective radiators, and tiered `75/50/25%` vane integrity.
- Complete Phase 2 (14) + Phase 3 (9) headless test suites and updated documentation (`AI_HANDOFF.md`, `TESTING.md`, `GDD_ANNEX_v0_3.md`).

------------------------------------------------------------------------

# 14. Phase 3 exit criteria

All 18 mandatory Phase 3 exit criteria are satisfied in code and covered by automated headless suites, with desktop GL Compatibility visual sign-off checklist documented in `docs/TESTING.md`.

------------------------------------------------------------------------

# 15. Deferred concepts for v0.4/v0.5

- Five-letter aviation navigation fix network & editable flight plan.
- Multi-system & multi-planet analytical orbital propagation.
- Arrival navigation quality / miss-jump probability & interdiction encounters.
- Economy, cargo contracts, NPC traffic, combat, and walkable station interiors.
- Ship Asset Pipeline Phase 2B–2F (Blender GLB model mounting onto `ShipInteractable`) and Flight Assist Space Mode (AOA-bounded vector-following).

------------------------------------------------------------------------

# 16. Handoff summary for v0.4

> Continue Space Trucker in Godot 4.7.2 Stable using GL Compatibility. v0.3 (Phases 3A–3H) is complete as of Patch 0.3.8: all ship systems hydrate from `ship.json`, convective radiators + 75/50/25% wear are active, `PlanetSurface` is a closed 360° 60 km cube-sphere with Starport Alpha and Horizon Outpost, and the repeatable Planet <-> Station jump loop is wired through `TransitionCoordinator`. Preserve the single-`RigidBody3D` architecture, GLB anchor names, and `test_range.tscn` regression behavior when starting v0.4 work.

------------------------------------------------------------------------

# 17. Final authority summary

Phase 3 proves the complete physical local-flight + discrete hyperspace transition vertical slice across a traversable 60 km spherical planet and an orbital cube station without prematurely building a procedural universe simulator.

------------------------------------------------------------------------

# 18. V0.3 Implementation Status Table & Phase 3H Release Gate

| System / Deliverable | Status | Patch | Notes & Verification Reference |
|---|---|---|---|
| Phase 2 Test Range & Core Flight Model (14 suites) | **TESTED** | 0.3.1–0.3.6 | `test_range.tscn` preserved; line 199 `phase_2j` warning fixed in `0.3.6`. |
| `EnvironmentProfile` & `CelestialBodyDefinition` | **TESTED** | 0.3.2 / 0.3.7 | `environment_profile_test.gd`; altitude temp curve added in `0.3.7`. |
| `PlanetaryReferenceFrame` & `EnvironmentManager` | **TESTED** | 0.3.2 / 0.3.8 | Inverse-square radial gravity & tangent basis tested across 360° (`simple_planet_loop_test.gd`). |
| Closed 360° Cube-Sphere Planet & Starport Alpha Basin | **IMPLEMENTED** | 0.3.3–0.3.8 | `planet_surface_environment.gd` 6-face `R=60km` sphere + tucked 4.4 km basin; headless physics/mesh/winding checks in `simple_planet_loop_test.gd`; desktop visual check pending user run. |
| `Horizon Outpost` & Surface Waypoint Nav (**N**) | **IMPLEMENTED** | 0.3.8 | Located ~23.9 km NE with `OutpostPad` collider & HUD bearing/distance; headless checks pass. |
| `AtmosphereHalo` Limb Glow & Dynamic `Camera3D.far` | **IMPLEMENTED** | 0.3.8 | Scales `75km–400km` and fades halo above 3 km; headless checks pass, desktop pixel check pending user run. |
| `JumpEnvelopeEvaluator` (45 km / 250 m) | **TESTED** | 0.3.5 | `jump_envelope_evaluator_test.gd`. |
| `StationLocalSpace` Orbital Relay Cube 01 | **TESTED** | 0.3.5 | `station_local_space_test.gd`; zero gravity/drag, `+Z` docking bay trigger. |
| Fixed Routes, `SimulationClock`, `JumpCalculator`, `TransitionCoordinator` | **TESTED** | 0.3.6 / 0.3.8 | `hyperspace_jump_test.gd` & `simple_planet_loop_test.gd`; radial terrain clearance & broken-route recovery. |
| Authoritative `ship.json` Hydration & Freighter Rebalance | **TESTED** | 0.3.7 / 0.3.7a | `ship_systems_tuning_test.gd`; preserves GLB anchor names for Phase 2B–2F. |
| Convective Air Radiators & Cold Tropopause Sweet Spot | **TESTED** | 0.3.7–0.3.7b | `ship_systems_tuning_test.gd` & `vane_thermal_model_test.gd`. |
| Tiered `75% / 50% / 25%` Wear, Faults & Startup Misfires | **TESTED** | 0.3.7–0.3.7b | `ship_systems_tuning_test.gd`; 8–10 min critical / 60+ min green targets calibrated. |
| Blender GLB Model Mount & Animations (Phases 2B–2F) | **DEFERRED** | v0.4+ | Intentionally untouched during Phase 3 to stay parallel-safe. |
| Flight Assist Space Mode (Vector-Following / AOA Throttle) | **DEFERRED** | v0.4+ | Scoped after v0.3 release gate. |
| Five-Letter Nav Network, Multi-System Orbits, Economy, NPCs | **DEFERRED** | v0.4 / v0.5 | Recorded in Section 15 for architectural continuity. |
