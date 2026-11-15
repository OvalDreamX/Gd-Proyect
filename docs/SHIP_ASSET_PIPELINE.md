# Space Trucker — Ship Asset Pipeline Contract

**Status:** Phase 2A–2C implementation is present; local Godot 4.7.2 regression verification is pending. Runtime GLB loading attaches a validated model while preserving the placeholder on missing/invalid assets. Available Blender anchors drive the cockpit seat/camera, vane force-application positions and ground-effect probes. The first project-authored GLB is not yet included. Skeleton/animation playback and generated cockpit interactions remain later subphases.

**Engine target:** Godot 4.7.2 Stable, GDScript, GL Compatibility.  
**Asset format:** self-contained GLB (`.glb`).  
**Authoring tool:** Blender with the official glTF 2.0 exporter.

## 1. Design boundary

Blender/GLB owns visual and spatial authoring:

- Meshes, materials, object hierarchy and pivots.
- Armature, bones and mechanical animation clips.
- Spatial anchors for vanes, ground probes, seats, cameras, cargo and docking.
- Interaction object locations and their visible geometry.

`ship.json` owns simulation and gameplay data:

- Dry mass, dry centre of mass, hull dimensions and payload rating.
- Collision shape and cargo envelope.
- Vane IDs, groups, authority and control allocation.
- Propulsion, handling and aerodynamic coefficients.
- Ground-effect strength, range and probe requirements.

Do not duplicate coordinates in JSON when Blender can author the relevant transform. JSON may refer to a named anchor; it should not store a second, manually maintained position for it.

## 2. Paths and package layout

Built-in ships:

```text
res://data/ships/<ship-folder>/
    ship.json
    model.glb
```

User-installed ships:

```text
user://mods/ships/<ship-folder>/
    ship.json
    model.glb
```

The JSON `model` field is a relative path within that ship folder, normally `model.glb`. The runtime loader receives the resolved `res://` or `user://` path. Absolute operating-system paths, backslashes, `.` segments and `..` traversal segments are rejected.

The installed Phase 1 JSON layout is authoritative for this project. Do not use the older proposed `res://mods/<id>/mod.json` layout.

Use one GLB per ship for its ship model, anchors, skeleton and animations. Keep textures embedded in the GLB for the first version; sidecar resource support is not part of this contract yet.

## 3. Coordinate system, units and root

Project-specific ship basis:

- Nose/forward: `-Z`.
- Up: `+Y`.
- Right/starboard: `+X`.
- Distance: metres; one Blender unit is one metre.
- Mass: kilograms; forces: newtons; angles: degrees unless explicitly stated otherwise.

The authored GLB scene root must be named `SHIP_root`. Its origin is the ship's rigid-body reference datum. Keep the root at local position `(0, 0, 0)`, identity rotation and unit scale. Place the ship geometry and anchor objects relative to that datum. `GLTFDocument.generate_scene()` may add a Godot wrapper node named after the GLB file; the validator accepts that wrapper only when its direct authored child is `SHIP_root`.

Do not move the root to the visual centre of the mesh merely to make modelling convenient. The root datum must remain consistent with the ship's physics, collision and centre-of-mass data.

Before export, check that object scale is intentional and that the model's dimensions are in metres. Avoid negative scale and unapplied non-uniform scale on rigged components.

## 4. Naming convention

Names are case-sensitive. Use the exact uppercase category prefix, followed by lowercase `snake_case`. Identifiers must contain only `a-z`, `0-9` and single underscores. Do not add Blender duplicate suffixes such as `.001`; resolve duplicates at source.

### 4.1 Geometry — `MESH_`

A mesh object that should become a visual `MeshInstance3D` uses `MESH_`.

Examples:

```text
MESH_hull_main
MESH_engine_left
MESH_engine_right
MESH_gear_nose
MESH_gear_main_left
MESH_gear_main_right
MESH_cockpit_dashboard
MESH_switch_main_power
```

Static geometry may be joined where it shares material and does not need independent visibility or animation. Keep independently moving parts separate. The prefix is a validation aid, not an instruction to generate one draw call per object.

### 4.2 Spatial anchors — `ANCHOR_`

Create anchors as Blender Empty objects. Their transforms (position, rotation and scale) are the authored reference. Keep anchor scale at one; use rotation to define a meaningful local orientation.

Recommended names:

| Name | Purpose |
|---|---|
| `ANCHOR_ground_probe_front_left` | Ground-effect surface sample |
| `ANCHOR_ground_probe_front_right` | Ground-effect surface sample |
| `ANCHOR_ground_probe_rear_left` | Ground-effect surface sample |
| `ANCHOR_ground_probe_rear_right` | Ground-effect surface sample |
| `ANCHOR_vane_bottom_front_left` | Vane force/application position |
| `ANCHOR_vane_bottom_front_right` | Vane force/application position |
| `ANCHOR_vane_bottom_rear_left` | Vane force/application position |
| `ANCHOR_vane_bottom_rear_right` | Vane force/application position |
| `ANCHOR_vane_main_rear` | Main propulsion vane position |
| `ANCHOR_vane_side_left` | Left yaw-vane position |
| `ANCHOR_vane_side_right` | Right yaw-vane position |
| `ANCHOR_cockpit_camera` | Cockpit camera transform |
| `ANCHOR_pilot_seat` | Pilot seat transform |
| `ANCHOR_external_camera_focus` | External camera focus |
| `ANCHOR_cargo_origin` | Cargo placement origin |
| `ANCHOR_docking_port` | Docking alignment reference |

Anchor identifiers are unique across the entire model, not just within one parent. Phase 2A's registry exposes the identifier without the prefix: `get_anchor("pilot_seat")` resolves `ANCHOR_pilot_seat`.

The prototype `ship.json` now uses the canonical anchor identifiers without the `ANCHOR_` prefix (for example, `vane_main_rear`). These IDs match the suffix after `ANCHOR_` exactly. Keep JSON and Blender names synchronized when introducing new anchors; do not rely on fuzzy matching or case conversion.

### 4.3 Mechanical rig — `ARMATURE_` and `BONE_`

Use one armature for the ship where practical:

```text
ARMATURE_ship
└── BONE_root
    ├── BONE_gear_nose
    ├── BONE_gear_main_left
    ├── BONE_gear_main_right
    ├── BONE_wing_left
    ├── BONE_wing_right
    ├── BONE_cargo_ramp
    ├── BONE_vane_main_rear
    ├── BONE_switch_main_power
    └── BONE_switch_field_assist
```

Keep `BONE_root` at the ship datum. Use bone parenting or rigid single-bone weights for mechanical parts such as gear doors, vanes, switches and ramps. Automatic Weights are for genuinely deforming geometry; they are usually wrong for rigid mechanisms because they can bend parts that should remain rigid.

Static hull geometry does not need to deform. It can remain a static mesh under the GLB root or be attached rigidly to the root bone when a common armature hierarchy is required by the export setup. Avoid separate armatures for individual mechanisms unless a measured need justifies one; the intended ship rig is one shared Skeleton3D.

### 4.4 Cockpit interaction nodes — `INTERACT_`

Create one Empty at each control's pivot/reference point. Parent the visible control mesh beneath it. The interaction node's transform defines the pivot; the mesh child defines its appearance.

Allowed categories:

```text
INTERACT_switch_main_power
INTERACT_switch_field_assist
INTERACT_lever_throttle
INTERACT_lever_vector_angle
INTERACT_button_landing_lights
```

The current validator accepts only `switch_*`, `lever_*` and `button_*` identifiers. It requires each interaction node to contain at least one `MeshInstance3D` descendant. Hit-area creation and control semantics are intentionally deferred to a later subphase; these nodes do not become clickable in Phase 2A alone.

### 4.5 Animation clips — `action_`

Use lowercase `action_` names:

```text
action_gear_deploy
action_gear_retract
action_cargo_ramp_open
action_cargo_ramp_close
action_vane_deploy
action_wing_extend
action_switch_power_on
action_switch_power_off
```

The clip name must identify the whole action, not a single object's action track. Where multiple objects or bones participate in one motion, make their Blender tracks combine into one exported glTF animation with the same name.

## 5. Blender authoring and export checklist

1. Set the scene to Metric units with Unit Scale `1.0`.
2. Model the ship around the origin. Nose points down Blender `-Z`; top is `+Y`; starboard is `+X`.
3. Name visual mesh objects with `MESH_` and Empty anchor objects with `ANCHOR_`.
4. Use one ship armature. Name bones with `BONE_`; keep a root bone at the ship datum.
5. Parent rigid components to their control bones. Do not use automatic weights for hard mechanical parts unless they genuinely deform.
6. Place each `INTERACT_` Empty at the intended pivot and parent the visible mesh below it.
7. Create Actions named `action_*`. Ensure every required Action is active or stashed/pushed down to an NLA track so the exporter can see it.
8. Export as glTF Binary (`.glb`). Enable mesh, skinning and animation export as required by the model. Keep textures embedded for the first contract version.
9. Re-import the exported GLB into a clean Blender file or inspect it in Godot. Confirm node names, anchor transforms, skeleton and animation clip names survived.
10. Test the actual GLB with the project's runtime loader and validator. A successful Blender export is not proof that the game can use every expected node.

The glTF exporter supports object transform, pose-bone and shape-key animation. Arbitrary custom properties, physics simulations, material parameters and other Blender-only properties are not a substitute for exported animation tracks. Blender's exporter only includes Actions that are active or correctly stashed/associated with NLA tracks; merely creating an Action does not guarantee export. Export UI labels can differ between Blender versions, so validate the resulting GLB rather than relying on an assumed setting.

## 6. Runtime loader API (Phase 2A)

`ShipModelLoader.load_glb(path)` returns a Dictionary:

- `success`: whether import and structural validation succeeded.
- `model_root`: generated, unparented Node3D on success; caller owns it and must add/free it.
- `anchor_registry`: `ShipAnchorRegistry` built from the generated scene.
- `errors` / `warnings`: PackedStringArray diagnostics.
- `mesh_count`, `anchor_count`, `interaction_count`, `skeleton_count`: discovered counts.

`ShipModelLoader.validate_model_path(path)` returns an empty string for a permitted path or a human-readable rejection reason.

`ShipModelValidator.validate_model_root(root)` checks the generated root and authored `SHIP_root`, requires at least one renderable `MeshInstance3D` surface, checks naming syntax, duplicate anchors, MESH node types and INTERACT node structure. A GLB with no renderable geometry is rejected so it cannot silently replace the fallback with an invisible ship. Missing optional anchors are not errors at this stage because different ships may provide different equipment. Required anchors are checked against the ship definition when dependent systems are integrated.

`ShipAnchorRegistry` provides `has_anchor`, `get_anchor`, `get_anchor_names`, `get_missing_anchors` and `clear`.

Phase 2A established the loader and contract. Phase 2B added `ShipModelMount` under the ship's exterior visual group. It loads the `model` path relative to the selected `ship.json`, attaches only a structurally valid GLB and hides `PlaceholderModel` only after attachment succeeds. Missing definition/model files, invalid paths or failed GLB imports leave the placeholder visible and do not change the rigid body, collision, flight controllers or cargo systems. A missing prototype `model.glb` is an expected fallback state until the reference freighter asset is added. The mount exposes a status Dictionary, the generated model root and its anchor registry.

### Phase 2C — Runtime anchor integration

`ShipAnchorIntegration` runs after `ShipModelMount` has attempted its load and before `ShipCameraController` and the flight-force consumers initialize. Its behavior is deliberately tolerant of incomplete greybox models:

- `ANCHOR_pilot_seat` supplies the `CockpitSeat` transform.
- `ANCHOR_cockpit_camera` supplies the child `CockpitCamera` transform relative to that seat.
- Each `ANCHOR_vane_*` supplies the corresponding vane's ship-local force application point. Runtime `VaneDefinition` Resources are duplicated before applying per-ship values; the shared `.tres` assets are not mutated.
- Each `ANCHOR_ground_probe_*` is exposed through an invisible runtime `Marker3D` alias named by the canonical JSON ID. This preserves the existing direct-child lookup contract of `RepulsorliftGroundEffectSystem` without moving its raycast or force logic.

The prototype JSON was migrated in the same change: vane `anchor` fields, `ground_effect.probe_anchors`, and cockpit/seat camera references now use the canonical lowercase IDs without `ANCHOR_`. This prevents the configuration and consuming code from drifting apart.

If an individual anchor is absent, the valid model remains mounted and only that item falls back: the cockpit uses its scene-authored transforms, vanes use their original `.tres` `local_position` values, and ground probes use the existing hull-dimension-derived positions. Missing IDs are summarized in one warning. A missing or invalid GLB still follows the Phase 2B placeholder behavior. No collision shape, rigid-body transform, force magnitude, authority rating, environmental scene or flight-control tuning is modified by this phase.

The integration node must remain after `Visuals` (so the model mount has completed `_ready`) and before `CameraController`, `VaneController` and `RepulsorliftSystem` in `scenes/ship.tscn`. This ordering lets the cockpit camera controller capture the Blender-authored boresight and lets force consumers observe the remapped per-ship vane definitions before their first physics update.

### Phase 2D — Shared skeleton and action playback

`ShipAnimationController` is attached as `Visuals/Exterior/AnimationController`, next to `ModelMount`. The mount is earlier in sibling order, so the GLB is attached before the animation controller scans it. The controller can also be refreshed after an explicit model retry with `refresh_from_mount()`.

Rig validation is intentionally separate from the visual-model loader:

- Zero `Skeleton3D` nodes is allowed. This keeps the first static greybox valid and still permits node-transform actions that do not use bones.
- Exactly one `Skeleton3D` is the supported ship rig. It must contain at least one bone. `BONE_root` at the ship datum is expected; missing `BONE_` prefixes and a missing root bone are reported as warnings.
- More than one `Skeleton3D`, or a skeleton with no bones, sets the controller to `invalid_rig` and disables action discovery/playback. The visual model remains mounted; the animation issue does not replace it with the placeholder.
- Imported `AnimationPlayer` nodes are scanned recursively. Only valid lowercase `action_*` clips are exposed. A malformed action name or duplicate action ID is reported rather than silently choosing one.

The controller exposes these methods:

```gdscript
play_action(action_id, loop = false, custom_speed = 1.0, from_end = false, custom_blend = -1.0)
stop_action(action_id)
stop_all_actions()
is_action_playing(action_id)
get_available_actions()
get_animation_status()
refresh_from_mount()
```

Pass either `"action_gear_deploy"` or the shorter `"gear_deploy"`. `action_started` is emitted when a playback request is accepted. `action_finished` is emitted when a non-looping clip completes; Godot does not emit its animation-finished signal for looping clips. Loop mode is applied to a duplicated `Animation` in the generated model's runtime `AnimationLibrary`, not to the imported source resource. No action autoplays, and this phase does not decide when a mechanism should move; later gameplay systems will issue the calls.

The animation controller test constructs an in-memory Skeleton3D, AnimationPlayer and transform clip. It checks discovery, one-shot completion, looping, stop behavior, multiple-skeleton rejection and acceptance of a static model without an armature. It does not replace validation against the actual Blender-exported GLB when that asset exists.

### Phase 2E — Cockpit interaction discovery and dispatch

`ShipInteractionController` is attached as a direct child of the ship root. After `ShipModelMount` loads the GLB, it recursively discovers Blender Empty nodes named `INTERACT_*`, validates their type/category/ID and requires at least one descendant `MeshInstance3D` with renderable surfaces. Duplicate interaction IDs are rejected as a group. Invalid controls are skipped without invalidating the mounted visual model or changing flight physics.

For each valid pivot, the controller computes the union of its visible mesh bounds in the pivot's local coordinate space, adds the configured padding (default 0.08 m), enforces a small minimum size and creates a child `Area3D` with a `BoxShape3D`. Generated areas use dedicated collision layer bit 20, a zero collision mask and no overlap monitoring. They do not join normal ship/world collision or change the rigid body. A ray query must set `collide_with_areas=true`, `collide_with_bodies=false` and use the same collision layer.

The public interaction API is:

```gdscript
get_interaction_ids()
get_interaction_info(interaction_id)
get_interaction_status()
pick_interaction_from_camera(camera, screen_position, max_distance = -1.0)
interact_at_screen_position(camera, screen_position)
activate_interaction(interaction_id)
set_interaction_value(interaction_id, normalized_value)
refresh_from_mount()
```

`activate_interaction()` is for switches and buttons. Levers use `set_interaction_value()` with a normalized value in [0, 1]; a click alone never snaps a lever to an endpoint. `interaction_requested`, `interaction_dispatched` and `interaction_failed` signals are available to UI/input code. The phase does not seize the existing flight mouse or key input: callers route an intentional cockpit click/drag to these methods from their chosen interaction mode.

The mounted model remains data-only. No script, method name, or callable supplied by a model is loaded or executed. Requests pass through a fixed allowlist in an inherited extension of `ShipFlightController`:

| Blender control ID | Existing system mapping |
|---|---|
| `switch_main_power` | Existing repulsorlift field start/stop. The prototype does not yet have a separate ship electrical bus. |
| `switch_field_assist` | Existing Flight Control Computer assistance toggle. |
| `lever_throttle` | Existing field-power command, normalized 0–1; accepted while the field is online. |
| `lever_vector_angle` | Existing vector-distribution command, normalized 0–1 mapped to 0–110 degrees; accepted while online. |
| `button_landing_lights` | Discovered and hit-tested, but unbound because no landing-light system exists yet. |

All bindings require an active pilot and closed modal HUD panels. Unknown IDs and unimplemented systems are rejected. A missing model simply leaves interaction discovery waiting; it does not affect the placeholder or flight scene. Call `refresh_from_mount()` after a deliberate model reload.

The Phase 2E tests use synthetic GLB-like node hierarchies and a fake request receiver to verify discovery, duplicate/invalid-node rejection, hitbox sizing and dispatch. A second test instantiates the actual ship scene and checks that the bridge changes the real FCC/flight-controller state only while piloted. They complement, but do not replace, validation against the first real Blender-exported ship.

## 8. Remaining Phase 2 subphases

| Subphase | Scope |
|---|---|
| 2A — Contract and loader foundation | Naming/authoring contract, runtime GLB loader, structural validator, anchor registry and test fixture. Previous package. |
| 2B — Ship model mount and fallback | **Implemented:** dedicated mount in the base prototype ship scene. Placeholder hides only after successful GLB import/validation; missing or invalid models preserve fallback and physics. |
| 2C — Runtime anchor integration | **Implemented in source; runtime verification pending:** `ShipAnchorIntegration` applies available cockpit, vane and ground-probe anchors; incomplete models retain per-item fallbacks. Prototype JSON uses canonical anchor IDs. |
| 2D — Skeleton and animation | **Implemented in source; runtime verification pending:** `ShipAnimationController` validates the shared skeleton contract, discovers `action_*` clips and provides play/stop/loop/completion signals. Actual Blender GLB verification remains pending. |
| 2E — Cockpit interaction discovery | **Implemented in source; runtime verification pending:** discover `INTERACT_` pivots, create dedicated raycast hit areas, and route a fixed set of typed controls to existing flight/FCC systems. Model assets remain data-only. |
| 2F — Reference asset and closeout | Produce a reference freighter GLB with rig, gear, switch, vane, anchors and exported clips; validate in Godot; finalize modder-facing docs and regression tests. |

These subphases touch the ship asset boundary and ship-owned components only. They must not modify the planet, local-space, hyperspace, travel-route or environment scenes. Environment development can continue separately, provided both workstreams do not edit the same shared ship scenes or project-wide settings simultaneously.

## 9. Compatibility and failure policy

- Unsupported or malformed models must return structured errors; they must not crash the flight scene.
- Missing optional anchors are reported by dependent systems, not treated as a globally invalid model.
- Duplicate anchor identifiers and malformed declared prefixes are structural errors.
- A missing or failed GLB leaves the generic ship's fallback placeholder visible. Phase 2B implements and tests that scene integration.
- Do not execute scripts supplied by a ship mod. Mod assets are data only.


## Ship-asset regression test commands

Run from the project root with the project's Godot 4.7.2 executable:

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

These SceneTree tests return a non-zero process exit code when an assertion fails. The anchor-integration test creates synthetic in-memory `SHIP_root` hierarchies, so it tests full and partial anchor sets without requiring the finished Blender GLB. The animation-controller test creates a synthetic one-bone skeleton and an AnimationPlayer clip; it does not require a Blender export. The first test also checks that validation reports independent errors in one pass rather than stopping after the first identity/path errors.

## Vane actuator metadata — first allocator-preparation increment

The prototype now treats a vane definition as a general actuator record. Each JSON vane may specify `control_weights` for `pitch`, `roll`, `yaw`, `lift` and `main_thrust`, each an integer from 0 to 100. These are recruitment weights, not literal force percentages. A vane can contribute to multiple channels. The future allocator must combine simultaneous demands into one bounded output per actuator and calculate the resulting physical force and moment from geometry.

The Blender anchor name declares the bidirectional ship-local thrust axis:

- `ANCHOR_vane_vertical_*` → local Y axis.
- `ANCHOR_vane_horizontal_side_*` → local X axis.
- `ANCHOR_vane_horizontal_main_*` → local Z axis.

The anchor position is the actuator application point. Anchor rotation is deliberately ignored in this increment; the axis is determined by the prefix and can be used with either sign.

`ShipAnchorIntegration` now builds the runtime actuator list from the ship definition, matching existing `.tres` resources for fallback values and creating definitions for additional JSON-declared actuators. A new actuator whose anchor is missing remains registered but disabled because it has no valid application point. Existing actuators retain their `.tres` position when their optional model anchor is absent. Duplicate/empty IDs are skipped with diagnostics.

**Important boundary:** this increment introduces and validates the data model but does not yet replace the existing fixed-group force allocator. Legacy `group` identifiers remain in the prototype JSON so current flight behavior is preserved. The next increment will consume the axis vectors and control weights in a geometry-aware allocator. FCC translation channels and keyboard bindings are also deferred; they require a defined translation command interface rather than JSON metadata alone.
