# Space Trucker — 0.2 GLB / Flight Refactor Handoff for 0.3 Integration

**Purpose:** Give the AI integrating the independently developed 0.3 environment work a reliable account of the 0.2 GLB, ship-definition, and flight-actuator work. This document describes the 0.2 side and its integration contracts; it is not permission to redesign either side.

**Engine target:** Godot 4.7.2 Stable, GDScript, GL Compatibility.

**Status wording:** The core GLB/runtime pipeline and the geometry-based flight allocator are implemented. The 0.2 work is **not fully closed**: it still needs a real project-authored reference freighter GLB, final cleanup of legacy JSON metadata, translation controls, and a combined regression pass against the exact merged project.

---

## 1. Source-of-truth warning — read this first

The public GitHub branch `0.2glb-integration` was checked on 16 November 2026. It still points to:

- Branch: `0.2glb-integration`
- Commit: `539eb8a2b3223d517e3d7dba9c2861b0a6e731bd`
- Commit message: `Changelogs and tests missing from previous`

That repository snapshot contains the Phase 2A–2E GLB implementation and the earlier flight work, but **does not contain the subsequently delivered local F6 and F7A–F7D patches**. The actual 0.2 source of truth for integration is the user's current working project after applying:

1. the latest `0.2glb-integration` project state;
2. `0.2.5F6_Geometry_Yaw_Integration.zip`;
3. `0.2.5F7A_Geometry_Main_Vector_Allocation.zip`;
4. `0.2.5F7B_Unified_Actuator_Allocation.zip`;
5. `0.2.5F7C_Unified_Allocation_Corrections.zip`;
6. `0.2.5F7D_Unified_Force_Test_Contract.zip`.

Do not use the GitHub branch alone as the merge baseline. Do not overwrite F6/F7 files with their older remote versions. If the current project directory or a current project ZIP is not available, ask the owner for that exact working state before writing a merge patch.

F7D is test/documentation-only; F6 through F7C contain production changes.

## 2. High-level result

The 0.2 work has two connected outcomes:

1. **Ship asset/data pipeline:** a validated, data-only JSON + GLB workflow for loading the prototype ship model, discovering authored anchors, optionally playing exported mechanism actions, and discovering/dispatching a limited set of cockpit controls. A missing or invalid GLB leaves the current placeholder visible and does not disable the ship's physics.
2. **Geometry-driven repulsorlift control:** pitch, roll, yaw, lift, and main thrust are allocated through the actual configured vane geometry and a shared per-actuator force bound. The old assumption that actuator IDs/groups determine their force role is being retired. Anchor position determines the force application point; the anchor-name family determines the bidirectional ship-local force axis.

The 0.2 changes are mainly ship-system and ship-asset-boundary work. The later 0.3 environment implementation should build around these interfaces instead of replacing them.

## 3. Ship definition and GLB pipeline

### 3.1 JSON definition foundation

Implemented foundation:

- Versioned schema: `schema_version: 1`.
- Typed `ShipDefinition` constructed by `ShipDefinitionLoader` after strict parsing and validation.
- Validates identity, relative model path, physical values, cargo bounds, vane records, IDs, and required fields. Validation reports useful errors rather than constructing a partially valid definition.
- Prototype definition lives at `res://data/ships/prototype_freighter/ship.json`.
- Built-in ship layout: `res://data/ships/<ship-folder>/ship.json` plus `model.glb`.
- Intended installed-mod layout: `user://mods/ships/<ship-folder>/ship.json` plus `model.glb`.
- Model paths are relative to the ship-definition folder. Absolute filesystem paths, backslashes, `.`/`..` traversal segments and unsafe path forms are rejected.
- JSON holds simulation/gameplay values; Blender/GLB holds visual geometry and authored spatial transforms. Avoid storing a second copy of an anchor position in JSON when the anchor can own it.

The JSON schema has sections for ship identity, physics, cargo, propulsion, and optional handling/aerodynamic/ground-effect/camera configuration. The existence of a parsed field does **not** prove that every old hard-coded subsystem has already been migrated to consume it. The generic ship factory and complete mod discovery/catalog pipeline were not completed in this phase.

### 3.2 Asset folder and authoring contract

A single self-contained GLB per ship is the current contract. Textures are expected to be embedded for the first implementation. Use Blender's glTF 2.0 binary export.

Coordinate convention:

- Nose / forward: local `-Z`.
- Up: local `+Y`.
- Right / starboard: local `+X`.
- One Blender unit = one metre.
- Mass values are kg; forces are N; angles are degrees unless a field explicitly states otherwise.
- Root object: `SHIP_root`, at the rigid-body reference datum, origin `(0,0,0)`, identity rotation, unit scale.

Naming contract (case-sensitive; suffixes use lowercase snake_case; avoid Blender `.001` duplicates):

| Prefix | Meaning | Example |
|---|---|---|
| `SHIP_root` | Authored ship scene root / physics datum | `SHIP_root` |
| `MESH_` | Renderable visual mesh | `MESH_hull_main` |
| `ANCHOR_` | Spatial reference Empty | `ANCHOR_pilot_seat` |
| `ARMATURE_` | Shared ship armature | `ARMATURE_ship` |
| `BONE_` | Armature bone | `BONE_root`, `BONE_gear_nose` |
| `INTERACT_` | Cockpit-control pivot Empty | `INTERACT_lever_throttle` |
| `action_` | Exported animation clip | `action_gear_deploy` |

Use one shared armature where practical. Keep the hull static; parent hard mechanical parts to their bones or use rigid single-bone weights. Automatic Weights are for truly deforming geometry, not gears, switches, vanes, or other rigid mechanisms. Exported Actions must actually be exposed through Blender's glTF export/NLA setup; an Action visible in the Action Editor is not proof that it exists in the GLB.

### 3.3 Runtime loader, validator, mount, and fallback

Implemented components:

- `ShipModelLoader`: imports a GLB with `GLTFDocument`, generates the scene, runs structural validation, builds an anchor registry, and returns a structured result (`success`, root, registry, errors/warnings, discovered counts). Model paths are checked before import.
- `ShipModelValidator`: validates the generated root and authored `SHIP_root`, renderable `MeshInstance3D` surfaces, naming syntax, duplicate anchors, `MESH_` node types, and interaction-node structure.
- `ShipAnchorRegistry`: indexes `ANCHOR_` descendants by the suffix after the prefix and offers lookup, existence, names, and missing-anchor queries. Lookup accepts the normalized identifier/name.
- `ShipModelMount`: mounted under the exterior visual group. Loads the model path from the selected ship definition. The placeholder is hidden **only after** a valid model has actually been attached.

Failure policy:

- Missing path/file, invalid path, import failure, invalid structure, or no renderable mesh must not crash the ship or remove the placeholder.
- An invalid/missing model does not replace collision, rigid-body ownership, cargo logic, flight controllers, or force code.
- A structurally valid visual model may omit optional anchors. A missing anchor causes the dependent subsystem to keep its previous scene/Resource fallback; it does not globally invalidate the model.
- The absent `res://data/ships/prototype_freighter/model.glb` is an expected state until the reference asset is authored. The “model missing; keeping placeholder visible” warning is not itself a pipeline failure.

### 3.4 Runtime anchor integration (Phase 2C)

`ShipAnchorIntegration` runs after `Visuals` / `ModelMount` has loaded and before the camera, vane controller, and repulsorlift force consumer initialize. Scene sibling order is significant and must be preserved in `scenes/ship.tscn`:

1. `Visuals` (including exterior `ModelMount`);
2. `ShipAnchorIntegration`;
3. camera controller;
4. `VaneController`;
5. `RepulsorliftSystem`.

It uses available GLB anchors for:

- `ANCHOR_pilot_seat` → cockpit seat transform;
- `ANCHOR_cockpit_camera` → cockpit camera transform relative to seat;
- vane anchors → per-ship force application positions;
- ground-probe anchors → runtime `Marker3D` aliases expected by the existing ground-effect lookup.

Runtime vane definitions are duplicated before applying per-ship anchor positions. Shared `.tres` Resources are configuration/fallback data and must not be mutated as per-instance state.

Missing anchors are handled independently: cockpit transforms fall back to scene-authored values, vane positions to their original Resource `local_position`, and ground probes to the existing hull-dimension-derived positions. Missing IDs are summarized as warnings. The integration does not change collision shape, mass, force ratings, thermal coefficients, or the flight model.

### 3.5 Rig and animation controller (Phase 2D)

`ShipAnimationController` lives beside `ModelMount` under the exterior visual group and scans the mounted GLB after it is attached. It discovers imported `AnimationPlayer` nodes and exposes valid `action_*` clips through methods such as:

- `play_action(action_id, loop, custom_speed, from_end, custom_blend)`;
- `stop_action(action_id)` / `stop_all_actions()`;
- `is_action_playing(action_id)`;
- `get_available_actions()` / `get_animation_status()`;
- `refresh_from_mount()` after an explicit model reload.

Rig policy:

- A static model with zero `Skeleton3D` is allowed.
- Exactly one `Skeleton3D` with at least one bone is the supported ship rig. `BONE_root` at the datum is expected; deviations are reported as warnings.
- More than one skeleton or a skeleton with no bones marks the rig invalid and disables action discovery/playback, but does **not** remove the visual model.
- Duplicate/malformed action IDs are reported instead of selecting one silently.
- No action autoplays. A gameplay subsystem must request it.
- Loop changes are applied to a runtime duplicate of the Animation resource, not the imported source resource.

The controller provides animation access, not mechanism gameplay. Landing-gear state, power switches, ramps, etc. must be commanded by the system that owns that gameplay state.

### 3.6 Cockpit interaction discovery and safe dispatch (Phase 2E)

Implemented components:

- `ShipInteractionController`: recursively discovers `INTERACT_*` pivot nodes, validates IDs and visible mesh descendants, calculates their bounds in pivot-local space, creates child `Area3D` / `BoxShape3D` hit areas, and exposes camera ray-picking and activation/value APIs.
- `ShipFlightControllerInteraction`: narrow extension/bridge on the flight-controller side. It is the fixed allowlist that maps data-authored control IDs to existing ship/FCC methods.

Important behavior:

- Generated hit areas use a dedicated collision layer (layer 20 / mask bit `1 << 19`), zero mask, and no overlap monitoring. They must not participate in normal ship/world collision. Interaction ray queries must target areas and the dedicated layer, not bodies.
- Duplicate/invalid controls are skipped or rejected without invalidating the visual model or flight physics.
- Models are **data-only**. Never load or execute scripts, method names, or callables supplied by a GLB/mod. Dispatch must remain through a fixed allowlist.
- The interaction controller does not seize existing mouse/keyboard flight input. The caller invokes pick/drag/activate intentionally in an interaction mode.
- Switches/buttons call activation; levers receive a normalized `[0,1]` value. A click must not snap a lever to an endpoint.
- Controls require an active pilot and closed modal HUD panels.

Current ID mappings:

| Blender ID | Existing game command | Status |
|---|---|---|
| `switch_main_power` | Existing repulsorlift field online/offline | Implemented; it is not a separate ship electrical bus |
| `switch_field_assist` | FCC assistance toggle | Implemented |
| `lever_throttle` | Field-power command, normalized 0–1 | Implemented while field online |
| `lever_vector_angle` | Vector-distribution command, normalized 0–1 → 0–110° | Implemented while field online |
| `button_landing_lights` | Landing-light system | Structurally discoverable, but unbound because that gameplay system does not yet exist |

### 3.7 Phase 2F is still outstanding

The first project-authored reference freighter asset has not been completed/validated as part of the recorded implementation. Remaining 2F work:

- author and export a real Blender freighter GLB;
- include visible hull/engine/gear/switch/vane geometry, required anchors, one shared rig, and representative animation actions;
- import it into Godot 4.7.2 and validate the exact exported node names, transforms, skeleton, clips, and hit areas;
- validate visual placement and cockpit camera/seat alignment;
- ensure vane and probe positions are correct in the actual model;
- run asset-pipeline tests against the real imported asset, not only synthetic test hierarchies;
- finalize the modeler cheatsheet and closeout documentation.

Collision-mesh naming such as `COLLISION_hull`, an `ANCHOR_cg` dry-COG anchor, a fully generic ship factory, and user mod discovery/catalog are **not completed contracts** unless the current working project says otherwise. Do not silently promote suggestions from design discussion into implementation facts.

---

## 4. Flight model / JSON actuator refactor

### 4.1 Geometry allocator foundation (pre-F6 dependency)

The prior 0.2.5F.4/F.5 work established the geometry allocator and pitch/roll integration:

- `VaneActuatorAllocator` is a scene-independent, deterministic bounded six-dimensional wrench solver.
- It solves for bidirectional scalar actuator outputs from each vane's position, axis, max force, enabled state, and channel recruitment weights.
- It supports rotational channels `pitch`, `roll`, `yaw` and force channels `lift`, `main_thrust`, `translate_x`, `translate_y`, `translate_z`.
- It reports achieved wrench, residual, convergence and actuator outputs.
- Pitch and roll had already moved to geometry allocation before F6. Actuator forces were applied at physical vane positions, preserving torque about the current COM.
- Runtime actuator discovery is based on configured vane records; there is no intended fixed four-slot allocator requirement.

The current 0.2 patch stack completes yaw and main-vector allocation, then unifies the commands so an actuator is not double-spent.

### 4.2 Anchor family defines thrust axis; position defines lever arm

The runtime convention is:

| Anchor family | Bidirectional ship-local force axis |
|---|---|
| `ANCHOR_vane_vertical_*` | Local Y (`+Y` / `-Y`) |
| `ANCHOR_vane_horizontal_side_*` | Local X (`+X` / `-X`) |
| `ANCHOR_vane_horizontal_main_*` | Local Z (`+Z` / `-Z`) |

Anchor **position** is the force-application point / lever arm. Anchor rotation is not used to rotate the force axis in this allocator. Model the actual vane/pivot to align with the family-declared axis; do not rotate an Empty expecting its rotation to define thrust direction.

Control weights are integer recruitment priorities (`0–100`), not percent force allocation and not exclusive roles. An actuator can contribute to several channels. The JSON prototype records the full weight set including explicit zeros for `translate_x/y/z`.

### 4.3 F6 — geometry-driven yaw

F6 corrected the prototype's two side-mounted yaw actuators. Their old `horizontal_side` classification represented local-X thrust, which could not create the needed yaw moment when their positions were separated across local X. The old hard-coded yaw force path had hidden the invalid geometry.

Corrected anchor identifiers:

- `ANCHOR_vane_horizontal_main_side_left` (port/left, negative local X position);
- `ANCHOR_vane_horizontal_main_side_right` (starboard/right, positive local X position).

Both use the bidirectional local-Z axis. For positive yaw:

- port actuator pushes forward (`-Z`);
- starboard actuator pushes aft (`+Z`);
- net longitudinal translation cancels;
- the pair produces negative local-Y torque, turning the nose right.

F6 changes:

- Added yaw to the shared maneuver allocator channel set.
- Removed the hard-coded left/right yaw group force path from `RepulsorliftSystem`.
- Computes yaw capacity from each eligible actuator's effective axis, force limit, and COM lever arm.
- Preserves alignment drift, damage/thermal authority, physical application points, telemetry, debug vectors and load contribution.
- Damage redistribution is channel-aware so yaw shortfall cannot consume unrelated pitch/roll headroom.
- Preserves full-command yaw authority; `maneuver_authority_fraction` remains a pitch/roll feel scalar and is not applied to yaw.
- Updated side-vane `.tres` fallback axis and prototype JSON anchor references.
- Added yaw geometry/runtime tests and anchor-integration assertions.

The `group` fields and old `control_sets.yaw_left/yaw_right` metadata may still be present for schema/legacy compatibility. F6 yaw allocation does not use them as force-role selectors.

### 4.4 F7A — geometry-driven main thrust and lift

F7A migrated the main-vector resultant away from fixed `main_rear`, `bottom_front`, and `bottom_rear` group lookups to the same geometry allocator. Main force recruitment uses `control_weights.lift` and `control_weights.main_thrust` plus each actuator's effective axis, position, force rating and health/thermal authority.

Preserved main-vector control curve:

- `0°`: forward (`-Z`), rated `1.50` gross TWR (`main_thrust` channel);
- `90°`: upward (`+Y`) VTOL lift, rated `1.10` gross TWR (`lift` channel);
- `0–90°`: linear capacity cross-fade between main thrust and lift;
- `90–110°`: retains lift while reversing a main-thrust component to provide rearward braking.

F7A was intentionally intermediate: it still had separate main-vector and maneuver passes, so it was not yet safe to call the whole architecture complete. F7B removed that double-spend.

### 4.5 F7B — one unified physical solve

F7B combined `lift`, `main_thrust`, `pitch`, `roll`, and `yaw` into one six-dimensional wrench allocation per physics tick.

Runtime contract:

- Discover configured actuators by stable ID and geometry; no fixed actuator slot count/order.
- One scalar output per physical actuator, bounded to `[-1,+1]`.
- One physical force application per actuator output, at its actual authored anchor point.
- The target includes main resultant force and the main-resultant moment about the current COM, equivalent to the desired main resultant acting through the fixed hull datum: `(hull_datum - current_COM) × target_main_force`.
- Pilot pitch/roll/yaw torque is added to the same target wrench.
- An actuator shared across propulsion and maneuver channels cannot receive independent full-strength commands from separate solves.
- Pitch/roll reserve configured authority from main-vector demand when they are commanded. The system trades some requested propulsion output for maneuver authority rather than exceeding the physical actuator bound.
- Damage redistribution and the low-main-power maneuver boost share the same physical output bound.
- Thermal load estimates now derive from each vane's actual force contribution divided by its rated force; the existing thermal simulation itself remains responsible for heating, cooling, sputter and wear.
- `group` IDs remain descriptive/compatibility metadata, not propulsion-role selectors for force generation, lift capacity or thermal loading.

F7B preserves F7A's vector-angle curve and force ratings.

### 4.6 F7C — unified allocator corrections

F7C fixed the first F7B integration problems without returning to separate physical force passes:

1. Tightened allocator regularization (`1e-8` → `1e-9`) to reduce achievable combined-wrench residual.
2. Recruitment priority is calculated from active channels for which a vane actually has non-zero weight. A lift demand no longer dilutes the recruitment priority of a yaw-only vane.
3. Damage shortfall/headroom is channel-scoped. A damaged yaw actuator cannot redirect its recovery demand into lift-only or pitch/roll-only actuators. Multi-channel actuators still have one shared output bound; recovery shares are not summed beyond that bound.
4. Restored the meaning of telemetry/force-vector diagnostics. The requested main resultant, achieved total physical resultant, per-vane force contributions, maneuver-eligible count and full unified eligible count are distinguished.
5. A non-applied main-only reference allocation may be used to explain the combined force-vector visualization. It is diagnostic only; the ship receives only the unified physical actuator solution.

The key telemetry distinction:

- `lift_main_force_vector`: requested main resultant;
- `lift_force_vector` / `lift_vane_contributions`: achieved physical resultant and actual per-vane forces;
- `actuator_allocator` / `main_vector_allocator`: full unified allocation;
- `maneuver_allocator` keeps compatibility behavior for old consumers while `unified_eligible_actuator_count` exposes the full solve's eligibility.

### 4.7 F7D — test-contract correction only

F7D changed `tests/flight_force_control_test.gd` and documentation only. No production force model, allocator, actuator bound, thermal model, or HUD behavior changed.

It corrected three expectations to match the unified physical solver:

- A symmetric equal pitch+roll command can be satisfied by a diagonally opposed two-actuator couple; the other two bottom vanes remain eligible but do not need non-zero output. The test now verifies both torques, cancellation and the full eligible set rather than requiring four non-zero vectors.
- Cancellation of very large opposing diagnostic `Vector3` values has a dedicated `0.1 N` test tolerance. The observed residual was about `0.061 N` against an `809,325 N` reference force. Global `EPSILON` and physical allocator tolerances were not relaxed.
- A damaged asymmetric lift+pitch solve may yield a genuinely combined force contribution, so debug entries can be labelled `combined` instead of falsely claiming all of that applied force is pure pitch.

The user's latest local report after applying F7D was: **`flight_force_control_test.gd` ran with no failures.** This is not evidence that every project test or the not-yet-authored GLB has passed.

### 4.8 Preserved flight behavior and numeric ratings

Prototype freighter design values:

- Dry mass: `30,000 kg`.
- Maximum payload: `25,000 kg`.
- Design gross mass: `55,000 kg`.
- Main forward rating: `1.50` gross TWR, approximately `809.3 kN` at `9.81 m/s²` reference gravity.
- Lift rating: `1.10` gross TWR, approximately `593.5 kN` at `9.81 m/s²` reference gravity.
- Force ratings are based on fixed design gross mass, not current loaded mass. Cargo increases inertia/mass/COM effects; it must not automatically increase engine force rating.

Pilot controls remain:

- W/S: field power;
- Q/E: vector angle;
- mouse: pitch/roll;
- A/D: yaw.

Thermal/damage authority, force application through the single ship `RigidBody3D`, and the 0°/90°/110° vector curve remain part of the contract. Do not retune them as an incidental part of environment merging.

---

## 5. Important existing 0.2 systems the 0.3 environment should reuse

These are already part of the 0.2 project baseline and should not be re-created by the 0.3 workstream:

- One ship `RigidBody3D` owns movement, angular motion, mass/inertia and collision.
- `ShipFlightController` handles pilot inputs, field state and telemetry routing.
- `FlightControlComputer` provides bounded PI angular-rate assistance in assisted mode and direct shaped vane commands when assistance is off. It is **rate assistance**, not attitude hold.
- `RepulsorliftSystem` is the physics-tick owner of repulsorlift force/torque allocation and application.
- `VaneController` owns per-ship vane integrity, failure, alignment, thermal state and operating wear. Configuration `VaneDefinition` Resources are not mutable runtime state.
- `AtmosphericFlightModel` owns the current test atmosphere, wind, drag and shield-generated glide lift. It is not yet a complete global planetary atmosphere model.
- `FlightSensorSuite` is the instrument-data boundary. HUD code should read sensor packets and validity flags, not recalculate physical measurements.
- `CargoSystem` changes actual rigid-body mass and custom COM from abstract cargo mass/distribution, using ship definition limits.
- `PlanetaryGravityBody` and `PlanetaryReferenceFrame` already exist in the 0.2 branch for planetary gravity/local-up context. Reuse and audit them before adding a second reference-frame abstraction.
- The FPM represents inertial/world velocity. Airspeed is air-relative in atmosphere and inertial in vacuum.
- Current compass north is world north. A planetary surface should provide local tangent north through the relevant environment/reference-frame contract; do not assume world north remains appropriate everywhere.
- Current altitude is not a terrain/radar-altitude measurement. Do not silently relabel it as one.

`scenes/test_range.tscn` remains the flight-regression environment. Preserve it. New planet, local-space/station and hyperspace environments should be separate scenes as specified by the 0.3 design annex.

## 6. What remains unfinished on the 0.2 side

| Item | State | Notes |
|---|---|---|
| Actual reference freighter GLB (Phase 2F) | Pending | Synthetic fixtures do not prove a real Blender export is valid. |
| Real-asset anchor/rig/animation/hitbox validation | Pending | Must be tested in Godot 4.7.2 after the asset exists. |
| Cockpit landing lights gameplay binding | Pending | Interaction is discoverable but has no landing-light subsystem to command. |
| Translation X/Y/Z | Allocator-supported, pilot binding deferred | Do not infer that weights alone give the player translation control. FCC/input integration is not completed. |
| JSON legacy mapping cleanup (F9) | Pending | `control_sets`, legacy `group` fields, `main_vector.forward_group` and `lift_groups` remain in the prototype definition. Audit all consumers before deleting. |
| Fully generic ship factory | Not completed | Prototype scene integration is not the same as a generic arbitrary-ship spawner. |
| User mod discovery/catalog | Not completed | The data/loader boundary exists; discovery, duplicate-ID policy, catalog UI and full mod lifecycle do not. |
| Dry-COM GLB anchor / cargo envelope migration | Not completed as a full GLB contract | JSON still has dry-COM/hull/cargo values; do not assume `ANCHOR_cg` or collider mesh conventions are implemented. |
| Final merged regression and tuning | Pending | The user confirmed the F7D force-control test passes; the exact merged project needs a wider regression run. |

Proposed next 0.2 closeout tasks were labelled F8–F10:

- **F8:** wire translation X/Y/Z demands into the FCC and pilot-input/control bindings, with deliberate control scheme and tests.
- **F9:** remove/deprecate legacy group/control-set/main-vector mappings only after searching every runtime and test consumer; keep migration compatibility where needed.
- **F10:** final regression, real-world/model integration, numerical tuning and closeout documentation.

These are not prerequisites for the 0.3 environment unless the environment explicitly needs a deferred capability. Do not implement them opportunistically during an unrelated scene merge.

---

## 7. Merge instructions for the independently developed 0.3 work

### 7.1 Establish the exact base before editing

1. Obtain the user's current working 0.2 project or exact ZIP containing F6 + F7A + F7B + F7C + F7D.
2. Obtain the independent 0.3 worktree/branch and identify the common ancestor.
3. Compare both branches by file path and diff, not by phase labels or recollection.
4. Make a new integration branch from the 0.3 work (or a clean common ancestor plus both sides); preserve each side until the merged build passes.
5. Record the exact base SHAs and a list of overlapping files before applying edits.

### 7.2 Files that deserve special conflict scrutiny

Potential shared or high-risk surfaces include:

- `project.godot` (main scene, input map, autoloads, renderer/settings);
- `scenes/ship.tscn` and the ship's child-node ordering;
- `scripts/ship_flight_controller.gd` / `ship_flight_controller_interaction.gd`;
- `scripts/repulsorlift_system.gd`;
- `scripts/vane_actuator_allocator.gd` and `scripts/vane_controller.gd`;
- `scripts/ship_definition_loader.gd`, `ship_model_mount.gd`, `ship_anchor_integration.gd`;
- `scripts/flight_sensor_suite.gd`, `scripts/atmospheric_flight_model.gd`;
- `scripts/planetary_gravity_body.gd` and `scripts/planetary_reference_frame.gd`;
- ship JSON and `data/vanes/*.tres`;
- `docs/GDD_ANNEX_v0_3.md`, implementation history and testing instructions.

Do not replace a complete shared file with the version from one branch simply because that branch has the newer timestamp. Merge the semantic changes and preserve the contracts described above.

### 7.3 Scene boundary and runtime sequencing

- Keep the test range intact as a known-good flight regression scene.
- Add the 0.3 planet surface, local-space/station and hyperspace transition as separate environments/scenes rather than mutating the flight test scene into the production environment.
- Preserve the ship scene's `ModelMount` → `ShipAnchorIntegration` → camera/vane/repulsorlift initialization order.
- Do not add a second rigid body for vanes or directly set the ship transform during normal flight.
- Keep physics force and physical subsystem updates on the physics tick.
- Keep the 0.2 ship/actuator model independent of environment scene hierarchy. Environment gravity, atmosphere and reference-frame data should be delivered through clear environment/profile interfaces.
- Do not make the ship asset loader depend on a planet/station scene, and do not make environment scene instantiation require a particular GLB to exist; placeholder fallback must continue to work.

### 7.4 Environment integration points to validate

The 0.3 work should confirm, rather than assume:

- the environment supplies the appropriate gravity vector/local-up basis used by the ship and sensors;
- the HUD heading reference uses local tangent north on a planet, not world north by accident;
- altitude/vertical speed semantics remain clear and are not presented as terrain clearance without a terrain-relative sensor;
- atmospheric density/wind/drag/shield-glide profile changes are explicit and do not silently retune the test atmosphere;
- cargo mass/COM remains connected to the actual rigid body so the unified actuator wrench solver sees the current COM;
- the main resultant's hull-datum lever arm remains correct when the cargo shifts COM;
- the 0° forward, 90° hover and 110° braking behavior remains stable across local gravity/reference-frame changes;
- the station/local-space and planet/surface tests exercise the same ship physics code, not a simplified duplicate flight implementation.

The current 0.2 branch's compass is world-north based and current altitude is not terrain/radar altitude. These are real integration gaps, not reasons to duplicate the whole sensor system.

### 7.5 Scope guard for 0.3

The approved 0.3 target described in `docs/GDD_ANNEX_v0_3.md` is a compact round-trip travel vertical slice: one planet with usable surface/landing area/small starport, a separate local-space station environment, and a fixed outbound/return hyperspace route. Keep the existing 0.2 flight stack and test range stable while implementing it.

Do not silently expand this merge into a general procedural galaxy, full n-body/orbital simulator, general waypoint editor, procedural streaming planet framework, economy/NPC/combat systems, or walkable station interior. Those are outside the scoped environment slice unless the owner explicitly changes the scope.

---

## 8. Validation checklist

### 8.1 GLB/data tests

Run from the project root using Godot 4.7.2:

```powershell
godot --headless --path . --script res://tests/ship_definition_loader_test.gd
godot --headless --path . --script res://tests/ship_model_pipeline_test.gd
godot --headless --path . --script res://tests/ship_model_mount_test.gd
godot --headless --path . --script res://tests/ship_pilot_cleanup_test.gd
godot --headless --path . --script res://tests/ship_anchor_integration_test.gd
godot --headless --path . --script res://tests/ship_animation_controller_test.gd
godot --headless --path . --script res://tests/ship_interaction_controller_test.gd
godot --headless --path . --script res://tests/ship_cockpit_control_bridge_test.gd
```

These tests use synthetic/in-memory GLB-like hierarchies and fixture files in places. They are useful regression coverage but do not validate the first actual project-authored Blender freighter asset.

### 8.2 Allocator / force / vane tests

After applying F6 + F7A + F7B + F7C + F7D together, run:

```powershell
godot --headless --path . --script res://tests/vane_actuator_allocator_test.gd
godot --headless --path . --script res://tests/vane_yaw_geometry_test.gd
godot --headless --path . --script res://tests/main_vector_allocator_test.gd
godot --headless --path . --script res://tests/unified_actuator_wrench_test.gd
godot --headless --path . --script res://tests/unified_actuator_channel_priority_test.gd
godot --headless --path . --script res://tests/flight_force_control_test.gd
godot --headless --path . --script res://tests/vane_force_model_test.gd
godot --headless --path . --script res://tests/vane_physics_integration_test.gd
godot --headless --path . --script res://tests/vane_thermal_model_test.gd
```

F6 was reported by the user as running correctly. After F7D, the user reported `flight_force_control_test.gd` with no failures. The assistant did not run Godot in the packaging environment. Do not report the remaining command set as passed until it has been run against the exact combined/merged project.

### 8.3 Manual test matrix after merge

At minimum, check:

- startup with no GLB: cube placeholder remains visible; ship can still be piloted;
- startup with a valid GLB: model appears, placeholder hides, collision/physics remains unchanged;
- invalid GLB: error/status is readable; placeholder and ship remain operational;
- missing optional anchor: only its dependent item falls back;
- seat/camera: model-authored cockpit alignment is correct;
- vane anchors: thrust directions/positions and torque signs remain correct;
- animation: gear/switch/vane actions are discovered and invoked only by owning systems;
- interaction: ray hits only intended interaction areas; normal world collision unaffected; allowlist rejects unknown commands;
- pitch/roll/yaw and main-vector simultaneously: one output bound per vane; damage/thermal degradation remains local and visible;
- cargo at shifted COM: expected hull-datum main thrust moment remains present;
- surface, station and return route: same ship controller/sensors/allocator; no test-range regressions.

---

## 9. AI operating instructions

When combining this work with 0.3:

1. Treat this handoff as a map of the 0.2 contracts, not as a substitute for inspecting the actual current files.
2. Read the current project source and `docs/SHIP_ASSET_PIPELINE.md`, `docs/BLENDER_SHIP_AUTHORING.md`, `docs/AI_HANDOFF.md`, `docs/TESTING.md`, and `docs/GDD_ANNEX_v0_3.md` before editing.
3. Verify that F6/F7 production code is present in the working tree; the remote branch was stale at the time this note was written.
4. Keep design proposals, pending work and implementation facts separate. Do not silently convert `PROPOSED` or `TBD` details into confirmed requirements.
5. Preserve `.gd.uid` sidecars when modifying scripts. Do not delete `.godot` or import metadata as part of a patch. Do not change project-wide renderer/settings or the main test scene without a concrete requirement.
6. Preserve existing tests and add focused tests for new integration behavior. Do not weaken assertions just to make the merge green; F7D's test changes are specifically documented above and changed only assumptions invalidated by the unified solver.
7. Deliver incremental changed-files-only overwrite ZIPs with original relative paths, a README, and a changelog. Explain the reason for each architectural change and report exactly which tests were actually run.

**Practical status:** 0.2 core ship asset pipeline + unified geometry-based flight allocation are implemented; 0.3 can proceed in parallel on separate environments. The 0.2 reference asset and closeout work remain outstanding and should be integrated deliberately, not assumed finished.
