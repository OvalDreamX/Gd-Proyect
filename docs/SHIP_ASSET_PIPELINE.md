# Space Trucker — Ship Asset Pipeline Contract

**Status:** Phase 2A contract. The runtime loader and structural validation utilities are included in this phase. Scene integration, model-driven physics anchors, animation playback and generated cockpit interactions are later subphases.

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

The GLB scene root must be named `SHIP_root`. Its origin is the ship's rigid-body reference datum. Keep the root at local position `(0, 0, 0)`, identity rotation and unit scale. Place the ship geometry and anchor objects relative to that datum.

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

The current prototype JSON still contains legacy anchor names. They remain in use until a later integration subphase migrates the prototype definition and existing systems together. Do not rename only the JSON or only the model.

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

`ShipModelValidator.validate_model_root(root)` checks the root type, naming syntax, duplicate anchors, MESH node types and INTERACT node structure. Missing optional anchors are not errors at this stage because different ships may provide different equipment. Required anchors are checked against the ship definition when dependent systems are integrated.

`ShipAnchorRegistry` provides `has_anchor`, `get_anchor`, `get_anchor_names`, `get_missing_anchors` and `clear`.

Phase 2A does not yet attach a GLB to the active ship, replace its placeholder, move the vanes/cameras/probes, play animations or spawn interaction hitboxes. Those are intentionally separated into follow-up phases so the stable flight scene is not disturbed while the asset contract is verified.

## 8. Remaining Phase 2 subphases

| Subphase | Scope |
|---|---|
| 2A — Contract and loader foundation | Naming/authoring contract, runtime GLB loader, structural validator, anchor registry and test fixture. This package. |
| 2B — Ship model mount and fallback | Add a dedicated model mount to the prototype ship variant. Keep the placeholder visible until a candidate GLB loads and validates; failed/missing models leave physics and fallback visuals intact. |
| 2C — Runtime anchor integration | Resolve cockpit camera/seat, ground probes and vane application points from Blender anchors. Migrate the prototype JSON to canonical names in the same change as the code that consumes them. |
| 2D — Skeleton and animation | Validate the shared Skeleton3D, discover `action_*` clips and provide a small controller API for play/stop/loop/finished events. |
| 2E — Cockpit interaction discovery | Discover `INTERACT_` pivots, generate/validate hit areas and map typed controls to existing ship systems. Do not permit mods to run scripts. |
| 2F — Reference asset and closeout | Produce a reference freighter GLB with rig, gear, switch, vane, anchors and exported clips; validate in Godot; finalize modder-facing docs and regression tests. |

These subphases touch the ship asset boundary and ship-owned components only. They must not modify the planet, local-space, hyperspace, travel-route or environment scenes. Environment development can continue separately, provided both workstreams do not edit the same shared ship scenes or project-wide settings simultaneously.

## 9. Compatibility and failure policy

- Unsupported or malformed models must return structured errors; they must not crash the flight scene.
- Missing optional anchors are reported by dependent systems, not treated as a globally invalid model.
- Duplicate anchor identifiers and malformed declared prefixes are structural errors.
- A missing or failed GLB must eventually leave the generic ship's fallback placeholder visible. Phase 2B implements and tests that scene integration.
- Do not execute scripts supplied by a ship mod. Mod assets are data only.
