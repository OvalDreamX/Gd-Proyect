# SPACE TRUCKER --- GDD ANNEX AND IMPLEMENTATION SPECIFICATION

## Version 0.3 --- Environment, local space, and fixed-route hyperspace vertical slice

**Document status:** Authoritative Phase 3 annex\
**Target project:** `OvalDreamX/Gd-Proyect`\
**Target engine:** Godot 4.7.2 Stable, standard GDScript build\
**Renderer:** GL Compatibility\
**Platform:** Windows PC\
**Date:** 11 November 2026

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
already-developed freighter: one small test planet with a usable surface
port, a local-space departure/arrival environment, one large cube-shaped
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

-   One test planet.

-   One surface starport/spaceport with a landing pad.

-   One local departure envelope or transition boundary.

-   One orbital station represented by a large, simple cube.

-   One local-space scene around the station.

-   One fixed outbound jump and one fixed return jump.

-   A reliable way to reset the test scenario.

**Optional stretch content:**

-   One small settlement some distance from the starport, visible from
    the air and reachable by flight.

-   A small number of static rocks, ridges, hills, or terrain features
    to improve altitude/speed perception.

-   Simple distant celestial visuals in the sky.

The settlement is not a second gameplay system. If included, it is an
authored visual/physical location with no economy, NPC schedule,
interior, or mission logic.

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

-   A small, controllable planetary environment.

-   A simple low-poly terrain surface or terrain patch arrangement.

-   A starport and landing pad.

-   A station local-space environment.

-   One fixed route stored in data/resources or a small route
    definition.

-   Jump eligibility validation.

-   Deterministic jump calculation and arrival resolution.

-   Scene transition/loading flow.

-   Return jump.

-   Debug telemetry for environment, jump, and arrival state.

-   Automated tests for pure calculations and state transitions.

-   Runtime acceptance tests in Godot 4.7.2.

-   Documentation and an install/verification handoff.

## 2.2 Explicitly out of scope

Do not implement these during Phase 3:

-   A general waypoint editor or full navigation network.

-   Five-letter waypoint naming conventions or route discovery.

-   Multiple star systems or a procedural galaxy.

-   Procedural planet generation at global scale.

-   Cube-sphere terrain, quadtree terrain streaming, planetary LOD, or
    planet-wide collision.

-   Voxel terrain, caves, overhangs, or destructible terrain.

-   Full N-body simulation.

-   Full orbital mechanics for the player's ship.

-   Realistic orbital insertion, transfer burns, rendezvous planning, or
    patched-conic trajectory solving.

-   Full geostationary-orbit simulation.

-   A physically continuous journey through hyperspace.

-   Miss-jumps, interdiction, jump interruption, hyperspace encounters,
    or random arrival hazards.

-   Dynamic traffic, piracy, patrols, or combat.

-   Economy, contracts, cargo transfer, reputation, NPCs, settlement
    simulation, or station services.

-   Walkable station interiors.

-   Detailed planet atmosphere scattering, volumetric clouds, weather
    simulation, or advanced post-processing.

-   Custom engine builds, Large World Coordinates builds, C++
    GDExtensions, compute shaders, or external planetary-rendering
    frameworks.

-   A replacement ship physics/flight architecture.

These features can be considered in v0.4/v0.5 after the Phase 3 vertical
slice is stable. Mentioning them here is for architectural awareness
only; this annex does not prescribe their future implementation.

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

A fixed route is enough to test the travel architecture. A general
navigation system would add data editing, route validation, UI,
persistence, discovery and edge cases that are not necessary yet.

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

Do not use unseeded random values for required Phase 3 behavior. If
visual randomness is introduced, derive it from a fixed seed and keep it
separate from gameplay calculations.

## 3.4 Coordinate frames

The project must distinguish at least these conceptual frames, even if
the implementation uses a compact structure:

1.  **System frame:** identifies the planet and station relative to one
    another. Phase 3 needs only a small, bounded system representation.

2.  **Body frame:** positions/orientations relative to the planet,
    including local up and local north.

3.  **Local simulation frame:** the active Godot scene's coordinate
    space, where the ship and nearby objects are represented.

Use `Vector3`/`Transform3D` in the active local scene. Do not put
astronomical distances into one `Node3D` hierarchy.

For the test planet:

-   define the planet's centre and radius in the body/system data;

-   calculate the local radial up vector from the ship's body-relative
    position;

-   define a stable north reference from the planet's rotation axis or
    an explicit reference direction;

-   ensure gravity points toward the planet centre;

-   ensure the ship's orientation and flight-control reference are
    interpreted consistently.

If the current flight systems assume world `Vector3.UP` or a fixed world
north, inspect and adapt only the necessary interfaces. Do not refactor
all flight control code merely for theoretical generality. Phase 3
should demonstrate that the environment can supply these references and
that the ship consumes them correctly.

### Local origin and precision

Keep the active local scene near its origin. The player ship should not
accumulate huge coordinates.

-   Planetary local terrain can be built around the current test area.

-   The planet visual can be a distant sphere or simplified body
    representation; do not require the entire planet mesh to share the
    same detailed local coordinate frame.

-   The station scene uses its own local origin.

-   A jump changes the active local scene and places the ship near the
    destination origin.

-   Store system/body location separately from local `Node3D`
    transforms.

No custom double-precision Godot build is required for Phase 3.

## 3.5 Fixed physics and simulation time

-   Keep ship physics inside Godot's physics tick (`_physics_process` /
    physics callbacks).

-   Do not apply forces from `_process`.

-   Do not use frame delta for jump arrival calculations.

-   The simulation clock is an explicit value, independent of wall-clock
    time.

-   A jump advances simulation time by its calculated duration in one
    controlled operation.

-   Local physics resumes normally after the scene transition.

-   Pause/transition logic must prevent physics from running against a
    half-loaded or invalid environment.

The time model should be simple: `simulation_time_seconds` or an
equivalent monotonic value. Calendar/date formatting can be added later.

------------------------------------------------------------------------

# 4. Recommended architecture and responsibilities

The names below are proposed names, not an instruction to duplicate an
existing class. The implementation agent must map these responsibilities
onto the current project structure after inspecting it.

## 4.1 Data resources / definitions

### `EnvironmentProfile`

Purpose: describes physical and visual conditions for an active local
environment.

Minimum data:

-   stable `environment_id`;

-   environment type (`PLANET_SURFACE`, `LOCAL_SPACE`, or equivalent);

-   local gravity source or gravity magnitude;

-   atmospheric density parameters (zero for space);

-   wind parameters (zero for space);

-   local up reference or gravity provider;

-   local north/reference direction;

-   simple lighting/sky configuration identifier;

-   optional debug label.

Do not make this resource responsible for constructing meshes or
changing scenes.

### `CelestialBodyDefinition`

Purpose: describes the test planet as data.

Minimum data:

-   stable body ID and display name;

-   radius;

-   gravitational parameter `mu` or a clearly defined
    surface-gravity/radius pair from which `mu` is derived;

-   rotation period and axis/reference direction (can be a placeholder
    if rotation is not needed);

-   atmosphere parameters: reference density, scale height, and
    top/transition altitude;

-   terrain profile/seed only if useful for the chosen terrain
    implementation;

-   star illumination direction/colour or reference to system star data.

For a spherical body, use a consistent gravity relation. If using `mu`:

-   gravitational acceleration magnitude at radius `r` is `mu / r²`;

-   local gravity vector points toward the body centre;

-   surface gravity is `mu / R²`.

If using a simplified constant-gravity approximation in the immediate
test area, label it as such and do not mix it silently with an orbital
calculation that assumes a different `mu`.

### `OrbitalDestinationDefinition` or `StationDefinition`

Purpose: describes the station destination independently of its scene
mesh.

Minimum data:

-   stable station ID;

-   display name;

-   parent body/system ID;

-   orbit mode (`STATIC_TEST_ANCHOR` or `CIRCULAR_ANALYTIC`); choose the
    simplest valid mode for Phase 3;

-   orbital radius or fixed system-relative position;

-   reference epoch/time if using analytic movement;

-   local arrival transform/offset;

-   station scene path or scene identifier.

The scene path should be validated before a jump is committed.

### `FixedTestRouteDefinition`

Purpose: defines exactly the two Phase 3 jump legs.

Minimum data:

-   route ID;

-   origin location ID;

-   destination location ID;

-   required departure environment/type;

-   required jump-entry condition;

-   fixed travel duration or simple deterministic duration formula;

-   arrival offset and orientation;

-   reverse route reference.

This is not a general route graph or waypoint editor.

### `JumpResult` / transition snapshot

Can be a small typed data object, dictionary with strict validation, or
resource. It must carry:

-   source location/environment;

-   destination location/environment;

-   departure simulation time;

-   jump duration;

-   arrival simulation time;

-   calculated arrival transform;

-   route ID/leg ID;

-   validity/error code.

Do not store Node references in persistent jump state.

## 4.2 Runtime managers

### `EnvironmentManager`

Responsibilities:

-   expose the active environment profile;

-   provide gravity, local up, local north and atmospheric state to
    systems that need them;

-   activate/deactivate local environment-specific behavior;

-   avoid owning unrelated ship control logic.

### `SimulationClock`

Responsibilities:

-   store current simulation time;

-   advance by an explicit duration;

-   provide a stable query for body/station positions;

-   support deterministic tests.

### `TravelManager` / `JumpController`

Responsibilities:

-   check jump eligibility;

-   obtain the selected fixed route;

-   calculate a result without changing the world;

-   ask the transition coordinator to perform the scene change;

-   commit the new location only after the destination scene has loaded
    and validated;

-   report failure without leaving the project in a half-transitioned
    state.

### `LocalWorld` / `EnvironmentScene`

Responsibilities:

-   contain the active local terrain/space objects;

-   expose a spawn/arrival marker;

-   provide a valid local origin;

-   provide collision and environment interfaces;

-   not decide route outcomes.

### `ArrivalResolver`

Responsibilities:

-   turn a route result and simulation time into a destination-local
    spawn transform;

-   validate that the ship will not spawn inside terrain/station
    collision;

-   apply a deterministic safe offset if needed;

-   not apply arbitrary random offsets.

### `DebugEnvironmentOverlay`

Responsibilities:

-   display active environment ID/type;

-   gravity magnitude/vector and local up;

-   atmospheric density or space state;

-   simulation time;

-   jump eligibility and reason when unavailable;

-   route leg and calculated arrival location/time;

-   transition errors.

Use existing HUD/debug conventions where possible. Do not create a
second full HUD system.

------------------------------------------------------------------------

# 5. Planet and surface environment specification

## 5.1 Planet scale philosophy

The planet should be deliberately small compared with a real terrestrial
planet, closer to the gameplay scale of KSP than to a realistic Solar
System simulator. The intended surface-to-jump-entry experience is
approximately ten minutes for a normally loaded freighter:

-   about five minutes of ascent through the atmosphere;

-   about five additional minutes to reach the jump-entry envelope.

These are **PLACEHOLDER pacing targets**, not locked physical constants.

Important: "low orbit" and "jump-entry envelope" are not
interchangeable. A ship at a chosen altitude is not automatically in a
stable orbit. A stable orbit also requires sufficient tangential
velocity. Phase 3 does not require a stable orbit. Use the term
**jump-entry envelope** for the required departure condition unless a
true orbit is actually implemented and verified.

## 5.2 Gravity and scale tuning

Do not choose radius, gravity, atmosphere, and ship acceleration
independently without checking their combined effect.

The implementation should parameterize:

-   planet radius `R`;

-   gravitational parameter `mu` or surface gravity `g_surface`;

-   atmosphere reference density and scale height;

-   jump-entry altitude band;

-   ship mass and thrust/force values already defined by the ship model.

If using a spherical gravity model:

-   `g_surface = mu / R²`;

-   `g(r) = mu / r²`;

-   gravitational force on the ship is `mass * gravity_vector`.

If the existing ship flight model uses a fixed `reference_gravity_mps2`,
preserve the design intent but ensure the active environment's gravity
is supplied consistently. Do not silently scale vane thrust with cargo
mass or change the gross-mass rating from the original GDD.

The exact radius/gravity values are **TBD until tested**. Prefer a small
test body and tune the departure time by changing environment parameters
and/or the jump-entry envelope, not by secretly teleporting the ship
upward.

## 5.3 Departure envelope

The jump-entry envelope is a data-defined condition, not a hard-coded
keypress.

Minimum conditions:

-   ship is in the correct environment;

-   ship is above the configured minimum altitude;

-   ship is outside any configured restricted/planetary exclusion
    region;

-   ship is not landed or in collision;

-   required ship systems are online (only if the current project
    already has a meaningful system state for this);

-   ship speed and/or orientation meet a simple configured safety
    threshold if needed.

For Phase 3, use a simple and readable rule. Do not implement a complex
gravity-well model. The HUD should display which condition is not met.

The player should be able to reach the envelope through normal flight.
If it is not achievable with current thrust/drag values, tune the
planet/environment or agree on a change to the flight model; do not add
a hidden teleport or bypass.

## 5.4 Surface geography

**RECOMMENDED DESIGN:** Start with an authored low-poly terrain area or
a small deterministic heightfield patch, not a full procedural planet.

Terrain should provide:

-   a readable horizon;

-   visible altitude references;

-   hills/ridges or low mountains in the distance;

-   a few closer terrain features for parallax and speed perception;

-   a clear landing area around the starport;

-   collision geometry sufficient for safe landing and crash testing.

Use a simple terrain mesh, heightmap, or a small set of authored meshes
according to what the current project already uses. The decision should
be made after inspecting the existing Phase 2 test range.

Do not implement cube-sphere terrain, quadtree streaming, terrain LOD or
a planet-wide mesh in Phase 3.

### Terrain performance rules

-   Prefer a few combined/static meshes over hundreds of individual
    nodes.

-   Keep collision meshes simpler than visible meshes.

-   Avoid per-frame mesh regeneration.

-   Use MultiMesh only if there are enough repeated props to justify it.

-   Do not add a procedural vegetation system.

-   Terrain generation, if used, must be deterministic and run only when
    the scene is built/loaded, not every frame.

## 5.5 Starport

The first starport is a simple authored location.

Required:

-   one landing pad with clear orientation and touchdown markings;

-   a small number of low-poly buildings or hangars;

-   a visible approach direction or beacon;

-   collision geometry;

-   a ship spawn point and a repeatable reset/starting position.

The pad should provide useful visual references for:

-   height above ground;

-   lateral drift;

-   forward speed;

-   yaw/heading;

-   approach alignment;

-   touchdown.

No ATC, fees, NPCs, cargo services, or walkable building interiors are
required.

## 5.6 Optional settlement

Only after the required planet/port/jump loop works:

-   add one small settlement at a distinct location from the starport;

-   place it far enough away to require meaningful flight, but close
    enough for a short test;

-   make it visually identifiable from altitude;

-   provide a simple landing area if needed;

-   no NPCs, interiors, missions, or economy.

The settlement is a test destination and a scale reference, not a second
content pipeline.

------------------------------------------------------------------------

# 6. Local-space station environment

## 6.1 Scene purpose

The station scene exists to validate:

-   that the ship retains its physical state through transitions;

-   that local space behaves differently from atmosphere;

-   that the player can approach a large target using the same controls;

-   that a destination can be loaded and unloaded without corrupting
    ship state.

## 6.2 Station geometry

Use a large cube or rectangular prism with:

-   simple material;

-   visible face/edge structure;

-   a few approach markings or lights if useful;

-   collision geometry;

-   a clear docking/arrival target or trigger volume.

Avoid detailed surface greebles. The station must be easy to see and
approach.

## 6.3 Local space conditions

-   Atmospheric density = 0.

-   Wind = 0.

-   Atmospheric drag = 0 or the smallest safe value used by the current
    atmospheric system.

-   Gravity should be zero in the initial local station scene unless a
    simple local gravity reference is explicitly needed. Do not leave
    planetary gravity accidentally active.

-   The existing ship retains inertia and its normal repulsorlift
    controls.

-   The station is static in the local scene for the approach test.

A station-local scene does not need a physically meaningful planetary
orbit. Its system-level destination position is represented separately.

## 6.4 Arrival and docking

The jump should place the ship at a predictable, safe arrival point with
the station visible ahead or slightly offset.

The arrival point must:

-   be outside station collision;

-   be far enough away for a short approach;

-   use a known orientation/reference direction;

-   avoid spawning the ship with a large unintended velocity unless that
    is a deliberate test variable.

For Phase 3, docking can be a simple interaction or trigger zone that
records "station reached" and enables the return jump. Do not implement
docking clamps, pressure doors, station interiors, landing gear
simulation, or a docking minigame.

------------------------------------------------------------------------

# 7. Fixed hyperspace route and transition system

## 7.1 Scope

Implement only two route legs:

-   Planetary departure point → orbital station local-space arrival.

-   Station departure point → planetary upper-atmosphere arrival.

The ship's computer can display the fixed route as a simple preloaded
destination label and status. It does not need a general route editor.

## 7.2 Jump eligibility

Use a small validator that returns a structured result:

-   `can_jump: bool`;

-   reason/error code;

-   optional human-readable reason.

Example eligibility rules:

-   correct current environment;

-   correct route origin;

-   ship not landed;

-   ship not in a collision state;

-   planetary leg: inside jump-entry envelope;

-   station leg: inside station departure zone or a simple safe-distance
    rule;

-   ship systems online if this is already supported and reliable.

The HUD must explain why a jump is unavailable. Never silently ignore a
jump command.

## 7.3 Jump calculation

The calculation should be pure and testable. It should not load scenes
or change nodes.

Inputs:

-   fixed route definition;

-   current simulation time;

-   departure local state (only fields that materially affect the v0.3
    result);

-   destination definition.

Outputs:

-   valid/invalid result;

-   duration;

-   arrival simulation time;

-   destination environment ID;

-   destination local spawn transform;

-   optional arrival quality value reserved for later versions.

For Phase 3, keep the result deterministic. A simple travel-duration
formula is sufficient:

-   fixed duration per route, or

-   a small formula based on configured route distance and a configured
    hyperspace travel rate.

Do not add stochastic navigation error, mass-dependent jump performance,
drive wear, fuel cost, route quality, or miss-jumps in v0.3.

## 7.4 Arrival accuracy

The user-facing idea of imperfect arrival precision is a long-term
feature. For this phase:

-   use a fixed arrival transform or a deterministic small offset;

-   make sure the ship always appears in a safe region;

-   keep the arrival transform in route data, not embedded in transition
    code;

-   do not randomize arrival.

This gives the code a place to extend later without implementing the
full uncertainty model now.

## 7.5 Transition sequence and safety

Implement a controlled state machine. Suggested states:

`IDLE → VALIDATING → PREPARING → TRANSITION_EFFECT → LOADING_DESTINATION → RESTORING_SHIP → COMMITTING → IDLE`

Failure path:

`ANY_TRANSITION_STATE → ABORT/RECOVERY → IDLE`

Required behavior:

1.  Reject a second jump request while a transition is active.

2.  Validate all destination IDs and scene paths before unloading the
    current scene.

3.  Capture a transition snapshot of the ship and simulation state.

4.  Disable player input and pause/disable local physics in a controlled
    way.

5.  Show the hyperspace transition visual.

6.  Advance simulation time exactly once.

7.  Load the destination scene.

8.  Verify that the destination scene exposes a valid spawn point and
    environment profile.

9.  Place the ship at the resolved transform and restore required state.

10. Activate the destination environment.

11. Resume physics/input only after the destination is ready.

12. Commit the new current location only after successful restoration.

If loading fails:

-   do not leave the player in a blank scene;

-   restore the departure scene/state where possible;

-   display a useful error;

-   allow a retry or clean reset.

Do not use arbitrary `await create_timer()` delays as the only guarantee
that a scene is ready. Use explicit scene-loaded/ready signals or a
controlled transition coordinator with verified readiness.

## 7.6 What state survives a jump

At minimum preserve:

-   ship mass;

-   ship linear and angular velocity only if the arrival design
    explicitly uses them; otherwise set a documented safe arrival
    velocity;

-   ship orientation or a route-defined arrival orientation;

-   field/system online/off state;

-   vane runtime condition/temperature if those systems are already
    persistent;

-   simulation time;

-   current route leg and location ID.

For v0.3, it is acceptable to reset local velocity to a safe arrival
value at the jump boundary. This is a deliberate abstraction and must be
documented, not an accidental loss of state.

Do not persist Node references, scene instance IDs, or raw local
transforms as universal coordinates.

## 7.7 Hyperspace visual

A basic effect is enough:

-   short fade/cover transition;

-   simple star streaks, tunnel, or stretched points;

-   brief arrival fade;

-   no complex shader requirement;

-   must work in GL Compatibility;

-   effect can be disabled in debug mode.

The effect must not determine when the jump calculation occurs. The
transition manager owns timing and state.

------------------------------------------------------------------------

# 8. Planetary departure and arrival flow

## 8.1 Outbound

1.  Ship begins on the starport pad.

2.  Player starts and controls the ship using the existing flight
    systems.

3.  Ship takes off and climbs.

4.  Environment manager supplies gravity/up/atmosphere to the flight
    systems.

5.  HUD shows altitude, vertical speed, airspeed, environment type, and
    jump eligibility using existing instruments where possible.

6.  When the ship enters the configured jump-entry envelope, the
    computer reports `JUMP READY`.

7.  Player initiates the fixed jump.

8.  The station scene loads.

## 8.2 Return

1.  Player leaves the station docking/arrival trigger.

2.  Ship reaches the station's safe departure zone.

3.  Computer reports `JUMP READY`.

4.  Player initiates the fixed return jump.

5.  The planetary local scene loads at an upper-atmosphere/space
    approach point.

6.  The ship is oriented toward a useful approach direction, not
    automatically landed.

7.  Player descends, manages speed and lift, and returns to the
    starport.

Do not use a cinematic autopilot to land the ship in Phase 3. The
purpose is to validate the player's continuous flight through departure
and return.

------------------------------------------------------------------------

# 9. Detailed implementation roadmap

Each subphase must end with a testable state. Do not combine all phases
into one coding request.

## Phase 3A --- Repository audit and environment contract

**Goal:** Establish how the current project represents ship state,
gravity, up, north, HUD telemetry, scene ownership and tests. Define the
smallest environment interface that can be added without destabilizing
flight.

Tasks:

1.  Inspect all relevant scripts/scenes and the current GDD.

2.  Identify existing gravity and atmospheric assumptions.

3.  Identify all places where world up or world north is hard-coded.

4.  Identify how the ship is spawned, controlled, and referenced by the
    player/camera.

5.  Identify how the HUD obtains telemetry.

6.  Identify the project's existing test pattern and how tests are run.

7.  Write a concise architecture map and a list of required changes.

8.  Define stable IDs for the test planet, surface environment, station,
    and two route legs.

9.  Define the local coordinate conventions and units.

10. Do not change flight behavior in this audit milestone.

**Acceptance:**

-   The agent can explain the existing data/control flow.

-   No duplicate manager architecture has been introduced.

-   The coordinate and environment interfaces are documented.

-   Current project still opens and runs unchanged.

## Phase 3B --- Environment data and local physical references

**Goal:** Make the ship receive environment conditions through a clear
interface.

Tasks:

1.  Add or adapt the environment profile resource/data structure.

2.  Add or adapt the test celestial body definition.

3.  Implement a gravity provider for the test planet.

4.  Implement local up and local north queries.

5.  Provide atmosphere density/wind values from the active environment.

6.  Connect only the necessary existing flight/sensor systems to those
    values.

7.  Keep the existing test range working as a regression scene.

8.  Add pure tests for gravity magnitude/direction and coordinate
    references.

**Acceptance:**

-   The same ship can be given two test profiles (planetary and space).

-   Planet profile produces gravity toward the body centre.

-   Space profile produces zero/near-zero gravity and no atmosphere.

-   The existing test range remains functional.

-   No scene transition code is required yet.

## Phase 3C --- Planetary test environment

**Goal:** Replace or supplement the featureless test area with one
compact planetary surface scene.

Tasks:

1.  Build a low-poly terrain area with a readable horizon.

2.  Add distant hills/ridges and a few closer visual references.

3.  Add a starport landing pad and simple buildings/hangar.

4.  Add collision geometry.

5.  Add a spawn marker and reset point.

6.  Connect the active planet environment profile.

7.  Add a simple star light/sky/planetary atmosphere presentation
    compatible with GL Compatibility.

8.  Keep visual meshes separate from collision where practical.

9.  Do not build a full spherical terrain system.

10. If the existing test range is valuable for flight regression,
    preserve it as a separate scene.

**Acceptance:**

-   Ship can take off, climb, manoeuvre, descend and land.

-   Gravity and atmosphere respond to altitude.

-   Landing pad and terrain collisions behave correctly.

-   Terrain provides enough reference to judge altitude and speed.

-   Existing test range remains available.

## Phase 3D --- Planetary departure envelope

**Goal:** Define and validate the conditions for leaving the planetary
environment.

Tasks:

1.  Add data-driven minimum altitude and any simple velocity/safety
    conditions.

2.  Implement a pure eligibility check.

3.  Expose eligibility state and rejection reason to the HUD/debug
    display.

4.  Tune planet parameters and envelope to approach the provisional
    ten-minute departure target with a normal loaded ship.

5.  Test empty, nominal and maximum design gross mass where possible.

6.  Do not add orbital mechanics or a general gravity-well system.

**Acceptance:**

-   Player can reach jump-ready state by normal flight.

-   Jump-ready state is not triggered while landed or below the
    configured envelope.

-   The HUD correctly reports why a jump is unavailable.

-   The target travel time is measured and recorded; if not close to ten
    minutes, report the measured result and the tuning trade-off.

## Phase 3E --- Local-space station scene

**Goal:** Create a separate local-space environment around the cube
station.

Tasks:

1.  Create the station mesh and collision.

2.  Create a local-space environment profile with no atmosphere.

3.  Add a safe arrival marker and station approach reference.

4.  Add a simple docking/arrival trigger.

5.  Ensure the ship uses the same controller/physics architecture.

6.  Verify that atmospheric drag/wind/lift are disabled or appropriately
    neutralized.

7.  Add a return-jump readiness zone/state.

**Acceptance:**

-   Ship can manoeuvre in local space without planetary gravity or
    atmospheric forces accidentally persisting.

-   Station is visible and collision works.

-   Arrival point is safe and approach distance is reasonable.

-   Docking/arrival trigger works repeatedly.

## Phase 3F --- Fixed jump calculation and transition coordinator

**Goal:** Implement the two fixed route legs and safe scene transitions.

Tasks:

1.  Define the two route legs as data.

2.  Implement jump eligibility and reason codes.

3.  Implement a pure deterministic jump calculator.

4.  Implement a transition snapshot.

5.  Implement the transition state machine.

6.  Implement scene loading/unloading and destination readiness
    validation.

7.  Implement arrival resolution and safe ship placement.

8.  Advance simulation time exactly once per successful jump.

9.  Add a simple hyperspace visual.

10. Add recovery behavior for invalid routes or failed scene loads.

11. Add unit tests for route validity, eligibility, duration, arrival
    time, and deterministic transforms.

12. Add integration tests for outbound and return transitions.

**Acceptance:**

-   Planet → station jump succeeds.

-   Station → planet return jump succeeds.

-   No duplicate transitions occur from held/repeated input.

-   Simulation time advances once and only once.

-   Ship mass and selected persistent state survive.

-   Arrival transform is deterministic.

-   Failed transition does not strand the player in an invalid scene.

-   No physics runs against an unloaded or half-loaded scene.

## Phase 3G --- Vertical-slice integration and optional settlement

**Goal:** Make the complete loop repeatable and improve spatial
readability only after stability is proven.

Tasks:

1.  Test full surface → departure → jump → station → return jump →
    planetary approach → landing.

2.  Repeat at different ship masses.

3.  Repeat after resetting the scenario.

4.  Verify the old test range remains accessible.

5.  Add the optional settlement only if all previous acceptance tests
    pass.

6.  Add only enough scenery to make the settlement distinguishable and
    reachable.

7.  Run a performance pass on the target GTX 1650-class hardware or
    equivalent.

8.  Record known limitations.

**Acceptance:**

-   A player can complete the entire loop repeatedly without restarting
    the game.

-   No state is lost or duplicated.

-   No transition leaves stale nodes, active cameras, input locks or
    physics state behind.

-   The optional settlement does not reduce the stability/performance of
    the required loop.

## Phase 3H --- Release gate and handoff

**Goal:** Deliver a stable v0.3 test build and a reliable handoff to
v0.4.

Tasks:

1.  Run the full test checklist.

2.  Run headless parse/import checks where available.

3.  Run the game in the exact pinned Godot version.

4.  Test at least one complete loop manually.

5.  Test reset/retry and invalid jump conditions.

6.  Review logs for errors and warnings.

7.  Document engine version, commit, changed files and test results.

8.  Update the GDD status table: implemented, tested, partial, deferred.

9.  Prepare an overwrite-ready ZIP containing only changed/added files
    with original folder paths.

10. Do not include caches, `.godot/`, generated imports, or unrelated
    files in the delivery ZIP.

**Acceptance:**

-   All required tests pass or any failure is explicitly listed.

-   The game opens and the vertical slice is playable.

-   The handoff clearly identifies untested areas.

-   The user can extract the ZIP over the project root without manual
    merging.

------------------------------------------------------------------------

# 10. Testing strategy and quality gates

## 10.1 Test pyramid

Use three levels.

### Level 1 --- Pure logic tests

Test calculations without loading a scene:

-   gravity magnitude and direction;

-   local up/north basis validity;

-   atmosphere density at known altitudes;

-   jump eligibility;

-   route origin/destination validity;

-   travel duration;

-   simulation-clock advance;

-   deterministic arrival transform;

-   safe arrival offset.

These should be fast and deterministic.

### Level 2 --- Scene/integration tests

Test:

-   environment profile activation;

-   ship receives correct gravity and atmosphere;

-   space profile clears planetary forces;

-   station arrival marker exists;

-   landing pad collision/spawn marker exists;

-   transition state machine prevents re-entry;

-   ship state snapshot/restoration.

### Level 3 --- Manual runtime tests

Must be performed in the Godot editor/runtime:

-   takeoff and ascent;

-   atmosphere-to-space transition;

-   outbound jump;

-   station approach;

-   return jump;

-   planetary descent and landing;

-   repeat loop;

-   inspect HUD and visuals;

-   verify input/camera recovery after transition.

A test that only checks that a node exists is not sufficient to validate
a visual, physics, or scene-transition feature.

## 10.2 Required regression tests

The Phase 2 flight model must remain intact.

At minimum:

-   current test range loads;

-   cockpit entry and exit still work;

-   ship camera switching still works;

-   existing flight controls still work;

-   FCC assist toggle remains functional;

-   vane force/torque diagnostics remain available;

-   HUD does not disappear or become permanently screen-locked
    incorrectly;

-   current mass/force rating behavior remains unchanged;

-   no new gravity is applied in the test range unless explicitly
    configured.

## 10.3 Physics and numerical safety

-   Guard against zero-length vectors before normalization.

-   Guard against division by zero in weighted force/arrival
    calculations.

-   Clamp altitudes and density inputs to valid ranges.

-   Validate route IDs and destination scene paths before transition.

-   Use explicit units in variable names where ambiguity is possible
    (`_m`, `_mps`, `_kg`, `_seconds`).

-   Avoid hidden unit conversions.

-   Avoid accumulating floating-point time by repeatedly adding tiny
    values when one explicit duration can be added.

-   Avoid setting `RigidBody3D` transform during ordinary flight.

-   If the ship must be repositioned at a jump boundary, do so only
    while physics/input are controlled and the transition state is
    explicit.

-   Ensure no old local environment forces remain connected after scene
    replacement.

-   Prevent duplicate signal connections and stale node references after
    reload.

## 10.4 Performance targets

Phase 3 is a stability prototype, not a visual benchmark. Use
conservative geometry and simple materials.

Target:

-   stable playability at 1280×720 on the existing target-class PC;

-   no unnecessary per-frame allocations or mesh rebuilding;

-   no hundreds/thousands of independent decorative nodes;

-   no high-frequency scene-tree searches in physics callbacks;

-   cache references during setup and invalidate them cleanly on scene
    changes;

-   use simple collision shapes and static bodies for static environment
    geometry.

Do not prematurely optimize by introducing complex object pooling,
custom render paths, threads, or native extensions. First profile an
actual bottleneck.

------------------------------------------------------------------------

# 11. AI-assisted implementation protocol

This section is mandatory for future coding chats or coding agents. It
is designed to reduce context drift, over-large edits, invented APIs,
and untested code.

## 11.1 Required context packet

Before coding, the agent must have:

1.  This annex.

2.  Original v0.1 GDD.

3.  Current repository state and branch/commit.

4.  Relevant scripts/scenes for the milestone.

5.  The exact Godot version and renderer.

6.  Current known bugs and unverified changes.

7.  The acceptance criteria for the one milestone being implemented.

If any of these are missing, inspect the repository or ask for the
missing artifact. Do not guess at current code.

## 11.2 Plan before implementation

For each milestone, the agent must first report:

-   the intended behavior;

-   existing files it will reuse;

-   files it expects to add/change;

-   data flow and ownership;

-   risks and failure modes;

-   tests it will run;

-   explicit non-goals for that milestone.

The plan should be small enough to review. Do not ask an agent to
implement all of Phase 3 in one prompt.

## 11.3 One objective per coding task

Good task: \> Add the EnvironmentProfile data interface and connect the
existing gravity query to it. Do not build terrain or change the HUD.
Add pure tests for the profile and gravity provider.

Bad task: \> Build the planet, station, hyperspace, HUD, orbital
mechanics and procedural terrain.

Each coding task should normally modify a limited set of related files
and should have a clear before/after behavior. If the task expands, stop
and split it.

## 11.4 Repository-grounded coding

-   Read the complete target scripts before editing.

-   Search for all call sites before changing a public method, signal,
    input action or node path.

-   Verify exact Godot 4.7.2 APIs in the matching official documentation
    or class reference.

-   Do not invent property names or assume an API from another engine
    version.

-   Prefer existing project conventions and GDScript typed declarations
    where practical.

-   Avoid generic frameworks or abstractions that have no immediate use.

-   Do not rename/reorganize unrelated files.

-   Do not silently rewrite the GDD's confirmed ship mechanics.

## 11.5 Implementation loop

For each task:

1.  Inspect.

2.  State a short plan.

3.  Implement one coherent change.

4.  Run parse/import checks.

5.  Run focused tests.

6.  Run the project if the environment supports it.

7.  Inspect logs and actual behavior.

8.  Review the diff for unrelated changes.

9.  Report exact test evidence and remaining uncertainty.

10. Package the changed files preserving their repository paths.

If the agent cannot run Godot, it must say so and perform only the
checks it can actually perform. Static inspection is not runtime
validation.

## 11.6 Context-window and long-task management

-   Keep this annex as the durable plan rather than relying on chat
    history.

-   After each milestone, produce a short handoff note containing
    commit/hash, files changed, behavior implemented, tests run,
    failures, and next milestone.

-   Do not repeat the entire GDD in every prompt. Attach/link the
    authoritative documents and provide the current milestone.

-   If the conversation becomes long or unreliable, start a new chat
    with the context packet and latest handoff.

-   Do not combine partially completed work from several failed attempts
    without first inspecting the actual repository state.

-   Never assume a ZIP from an earlier conversation contains the current
    project.

## 11.7 Definition of done

A task is not done merely because code was generated. It is done when:

-   the change matches the agreed scope;

-   the project parses/imports;

-   relevant tests pass;

-   runtime behavior is verified where possible;

-   no known regression is introduced;

-   changed files are identified;

-   test status is stated honestly;

-   the delivery can be applied without manual code merging.

------------------------------------------------------------------------

# 12. Repository and external technical references

Use these references as technical guidance, not as a reason to add
dependencies.

## 12.1 Godot

-   [Godot 4.7 documentation](https://docs.godotengine.org/en/4.7/): use
    version-matched documentation, not assumptions from Godot 3 or a
    future development branch.

-   [Godot 4.7
    `RigidBody3D`](https://docs.godotengine.org/en/4.7/classes/class_rigidbody3d.html):
    physics-driven body behavior and force APIs.

-   [Godot 4.7 physics
    introduction](https://docs.godotengine.org/en/4.7/tutorials/physics/physics_introduction.html):
    physics processing and body ownership.

-   [Godot 4.7 thread-safe
    APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html):
    SceneTree operations are not generally thread-safe. Phase 3 should
    not need worker threads.

-   [Godot 4.7 large world
    coordinates](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html):
    understand precision constraints; do not build a custom
    double-precision engine for this phase.

-   [Godot compatibility
    renderer](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html):
    retain GL Compatibility and avoid features that require Forward+.

## 12.2 Project repository

-   [Space Trucker project
    repository](https://github.com/OvalDreamX/Gd-Proyect)

-   The current repository is the implementation authority. Chat
    summaries and old ZIPs are not substitutes for checking the latest
    branch.

## 12.3 Design references

-   [Frontier: Elite II graphics reverse-engineering
    study](https://github.com/Warp-Engineer/Frontier): study its
    distance-dependent representation and restrained rendering
    philosophy. Do not attempt to reproduce its software renderer.

-   [Frontier: First Encounters
    retrospective](https://frontierastro.co.uk/History/FFE25.html): use
    as a reference for more varied planetary landscapes; do not claim an
    unverified exact terrain algorithm.

-   [KSP on-rails concept and kRPC
    documentation](https://krpc.github.io/): inspiration for separating
    remote analytical motion from nearby active physics. This is a
    design analogy, not a dependency.

-   [Godot Procedural Planet --- Chunked
    LOD](https://godotengine.org/asset-library/asset/2058): reference
    for future planetary terrain research only. Do not import it into
    Phase 3.

## 12.4 AI-assisted development references

-   [OpenAI Codex best
    practices](https://learn.chatgpt.com/guides/best-practices): provide
    goal, context, constraints and measurable completion criteria; plan
    complex work before implementation.

-   [OpenAI: How OpenAI uses Codex to accelerate
    engineering](https://openai.com/business/guides-and-resources/how-openai-uses-codex/):
    use small scoped tasks and iterative verification.

-   [VS Code agent best
    practices](https://code.visualstudio.com/docs/agents/guides/customize-copilot-guide):
    establish a baseline, define success criteria, inspect changes and
    validate generated code.

These practices are included because coding agents can produce plausible
but incorrect code, misunderstand repository conventions, or make overly
broad edits. The process must make assumptions visible and require
tests.

------------------------------------------------------------------------

# 13. Phase 3 deliverables

The phase is complete only when the following are delivered:

## 13.1 Playable deliverable

-   One working planetary surface environment.

-   One starport and landing pad.

-   One cube-shaped orbital station in a separate local-space
    environment.

-   A fixed outbound jump from the planetary departure envelope to the
    station.

-   A fixed return jump to a planetary approach point.

-   Continuous manual flight in the planetary and station-local
    environments.

-   A repeatable full loop without restarting the game.

-   A reset/test-start mechanism.

## 13.2 Technical deliverable

-   Environment data interface.

-   Planet/body definition.

-   Local gravity/up/north provider.

-   Station destination definition.

-   Fixed route definition.

-   Simulation clock.

-   Pure jump calculator.

-   Transition state machine/coordinator.

-   Safe arrival resolver.

-   Focused unit/integration tests.

-   Updated project documentation and handoff.

The implementation may combine responsibilities into fewer scripts if
that fits the existing project architecture better. Do not create a
script per bullet simply to match the diagram.

## 13.3 Documentation deliverable

-   Updated GDD status table.

-   Phase 3 implementation notes.

-   Exact engine version and commit hash.

-   Changed/added file list.

-   Test checklist with pass/fail/not-run.

-   Known limitations and deferred items.

-   Overwrite-ready ZIP containing only modified/added files, preserving
    paths.

------------------------------------------------------------------------

# 14. Phase 3 exit criteria

All mandatory criteria must pass:

1.  The existing Phase 2 test range remains usable.

2.  The ship can take off from the planet's starport using the
    established flight model.

3.  The environment supplies gravity, local up/north and atmospheric
    conditions consistently.

4.  The player can reach the configured jump-entry envelope through
    normal flight.

5.  Jump eligibility is explained to the player.

6.  The outbound jump loads the station-local environment.

7.  The cube station is visible, collidable and approachable.

8.  The ship can complete a basic station arrival/docking interaction.

9.  The return jump loads the planetary approach environment.

10. The player can fly back and land at the starport.

11. The full loop can be repeated without restarting.

12. Simulation time advances exactly once per successful jump.

13. Ship mass and explicitly selected persistent state survive
    transitions.

14. Invalid jump attempts are rejected cleanly.

15. Failed scene loads or invalid destinations do not strand the player.

16. No known parser errors, recurring runtime errors, stale input locks,
    duplicate transitions, or orphaned local environment systems remain.

17. Performance is acceptable on the target PC at the project's normal
    test resolution.

18. The delivery includes only the changed/added files and an honest
    test report.

The settlement is not an exit criterion. It is stretch content.

------------------------------------------------------------------------

# 15. Deferred concepts for v0.4/v0.5 --- awareness only

This section records the broader direction so Phase 3 architecture does
not accidentally block it. It is **not an implementation plan**.

## 15.1 General navigation network

The intended future model uses ordered navigation fixes, often
identified by five-letter names in the style of aviation fixes. Some
fixes may have physical navigation buoys; others may be virtual points
broadcast by stations, planets or infrastructure. A general route
planner, editable flight plan, waypoint database and route discovery
system are not part of v0.3.

## 15.2 Multi-leg and multi-system travel

Future travel can consist of multiple jumps through a chain of
navigation fixes. Each leg is a separately validated and calculated
transition. Routes can differ in safety, travel time and quality. This
does not require continuous simulation of the entire route.

## 15.3 Arrival uncertainty and navigation quality

Future arrival precision may depend on navigation data, departure
position, route quality, drive condition, destination motion, ship mass
or other agreed variables. Miss-jumps and arrival hazards are deferred.
v0.3 uses deterministic safe arrival transforms.

## 15.4 Interdiction and hyperspace encounters

An interrupted jump can load a special encounter environment. The normal
travel model need not simulate intermediate space continuously. The
encounter resolver and event rules are future design work.

## 15.5 Larger planetary systems

Future work may add multiple planets, moons, stations, orbital objects,
analytical orbital propagation, and system-time visualization. The
architecture should retain stable IDs and reference frames, but v0.3
does not require a general orbital simulator.

## 15.6 Procedural planetary geography

The long-term art/technical direction draws from Frontier: Elite II and
First Encounters:

-   deterministic seeds and reproducible geography;

-   distant planet proxies and progressively richer local
    representations;

-   broad terrain structure plus mountain/ridge/crater detail;

-   authored ports and landmarks placed intentionally on procedural
    geography;

-   restrained directional lighting and controlled palettes;

-   simple low-poly surfaces before advanced shaders.

Future research may consider cube-sphere patches, quadtree LOD,
screen-space error, seam handling, near-field collision meshes, vertex
colours, biome masks and batched surface scatter. None is required for
the single Phase 3 planet.

## 15.7 Larger world simulation

Future work may include moving stations, orbital traffic, local
encounters, traffic lanes, patrols, and remote object state updates.
Remote objects should generally be analytical or abstracted; only nearby
gameplay objects need full local simulation.

## 15.8 Broader gameplay systems

Contracts, cargo loading, economy, station services, settlement
activity, NPCs, ship maintenance loops, weather, ship personality,
piracy, combat, walkable station interiors, and emergency systems remain
part of the larger game direction described in v0.1. They are not Phase
3 requirements.

------------------------------------------------------------------------

# 16. Handoff prompt for the next coding conversation

Use this prompt together with the original v0.1 GDD, this annex, and the
current repository:

> We are continuing development of Space Trucker in Godot 4.7.2 Stable
> using GL Compatibility. Read the original GDD and `GDD_ANNEX_v0_3.md`
> completely. The annex is authoritative for Phase 3 environment and
> travel decisions wherever it conflicts with v0.1.
>
> Phase 3 is a tightly scoped vertical slice: preserve the existing ship
> and flight model; create one compact planetary environment with a
> starport and landing pad; create a separate local-space scene with one
> large cube station; implement exactly two fixed hyperspace route legs
> (planet to station and station back to planet). The ship must fly
> continuously in each local environment. Hyperspace is a deterministic
> calculated scene transition, not continuous simulation of the route.
> There is no general waypoint editor, procedural galaxy, full orbital
> mechanics, procedural planet streaming, economy, NPCs, combat, or
> station interior in this phase.
>
> Before coding, inspect the latest repository and current branch. Map
> the existing architecture and identify the exact files to reuse. Do
> not rely on stale chat summaries or old ZIPs. Then propose one small
> milestone with its scope, files, risks, and tests. Do not implement
> the entire phase in one task.
>
> Preserve existing working behavior. Do not replace the
> single-`RigidBody3D` ship architecture, do not directly set the ship
> transform during ordinary flight, and do not apply physics forces
> outside the physics tick. Keep local scenes near the origin; keep
> system/body identity separate from local `Node3D` transforms. Use
> deterministic pure calculations for jump duration and arrival.
> Validate destination scenes before unloading the current scene. Ensure
> transitions cannot be triggered twice and have a recovery path if
> loading fails.
>
> Use Godot 4.7.2 APIs only. Keep GL Compatibility. Avoid custom engine
> builds, C++ extensions, compute shaders, third-party planetary
> frameworks, and premature multithreading. Add tests for pure
> calculations and state transitions, and perform actual runtime tests
> for flight, visual rendering, and scene changes. A node-existence test
> is not sufficient for a visual or physics feature.
>
> Work incrementally: inspect, plan, implement one coherent change,
> parse/import, run focused tests, run the project where possible,
> inspect logs and actual behavior, review the diff, and report exact
> test evidence. If runtime testing is unavailable, state that plainly.
> Deliver complete overwrite-ready files in a ZIP with original folder
> paths and only the changed/added files.

------------------------------------------------------------------------

# 17. Final authority summary

For Phase 3, the intended game is **not** a continuous realistic Solar
System simulator. It is a physical local-flight game connected by
calculated, discrete hyperspace transitions.

The player should experience:

-   taking off from a real-feeling local surface;

-   climbing through an atmosphere with the established ship physics;

-   reaching a defined departure envelope;

-   initiating a jump whose result is calculated;

-   arriving in a separate local space around a large station;

-   physically approaching the station;

-   jumping back and flying down to the planet.

Build this loop first. Keep the environment visually simple,
deterministic, data-driven, testable and inexpensive. Do not spend Phase
3 implementing the larger universe that this loop will eventually
inhabit.
