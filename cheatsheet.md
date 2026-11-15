# Space Trucker — Blender ship-modeling cheatsheet

**Use this beside Blender while creating the prototype freighter.**  
The authoritative details live in `docs/SHIP_ASSET_PIPELINE.md`. If this sheet and that contract ever disagree, the contract wins.

## 1. Non-negotiable scene setup

| Setting | Required value |
|---|---|
| Blender units | Metric |
| Unit Scale | `1.0` |
| One Blender unit | 1 metre |
| Forward / nose | `-Z` |
| Aft | `+Z` |
| Up | `+Y` |
| Down | `-Y` |
| Starboard / right | `+X` |
| Port / left | `-X` |
| Ship datum | `(0, 0, 0)` |
| Authored root object | `SHIP_root` |
| Root transform | Location `(0,0,0)`, rotation `(0,0,0)`, scale `(1,1,1)` |
| Export format | glTF Binary (`.glb`) |

The root is the ship's rigid-body reference datum, **not** a convenient visual centre. Model all geometry and place every anchor relative to it. Do not move the root to compensate for a badly placed mesh.

Current prototype reference dimensions are **3.6 m wide × 1.5 m high × 5.2 m long**. Keep the first blockout broadly consistent with the current hull/physics definition. Wings, gear, vanes and other appendages may extend beyond the central hull; changing the actual physics/collision envelope is a separate coordinated change to `ship.json` and Godot, not something the GLB silently changes.

## 2. Required root and hierarchy

Create a root Empty named exactly `SHIP_root`, at the world origin. It must be the authored scene root exported into the GLB. Godot may add its own filename-based wrapper around it after import; that is normal. The authored `SHIP_root` must remain a direct child of that generated wrapper.

A useful starting hierarchy is:

```text
SHIP_root                         (Empty; origin and identity transform)
├── MESH_hull_main                (visible hull; at least one real surface)
├── MESH_cockpit_canopy
├── MESH_engine_left
├── MESH_engine_right
├── MESH_gear_nose
├── MESH_gear_main_left
├── MESH_gear_main_right
├── MESH_vane_bottom_front_left
├── MESH_vane_bottom_front_right
├── MESH_vane_bottom_rear_left
├── MESH_vane_bottom_rear_right
├── MESH_vane_main_rear
├── MESH_vane_side_left
├── MESH_vane_side_right
├── ANCHOR_ground_probe_front_left
├── ANCHOR_ground_probe_front_right
├── ANCHOR_ground_probe_rear_left
├── ANCHOR_ground_probe_rear_right
├── ANCHOR_vane_vertical_a
├── ANCHOR_vane_vertical_b
├── ANCHOR_vane_vertical_c
├── ANCHOR_vane_vertical_d
├── ANCHOR_vane_horizontal_main_a
├── ANCHOR_vane_horizontal_side_a
├── ANCHOR_vane_horizontal_side_b
├── ANCHOR_pilot_seat
├── ANCHOR_cockpit_camera
└── ARMATURE_ship                (can be added for the later rig pass)
```

This is a conceptual hierarchy, not a requirement that every object remain a direct child. Moving meshes may be parented to bones; an `INTERACT_` pivot owns its visible mesh child. The important points are stable names, unique identifiers, and transforms relative to `SHIP_root`.

## 3. Naming rules

Names are case-sensitive. Use the exact prefix shown, then lowercase `snake_case`. Use only letters `a-z`, digits and single underscores after the prefix. Do not use spaces, hyphens, accented characters or Blender duplicate suffixes such as `.001`. Rename duplicates before export.

| Purpose | Object / data name | Example |
|---|---|---|
| Authored ship root | Exact special name | `SHIP_root` |
| Visible mesh object | `MESH_` | `MESH_hull_main` |
| Spatial reference Empty | `ANCHOR_` | `ANCHOR_pilot_seat` |
| Cockpit control pivot Empty | `INTERACT_` | `INTERACT_switch_main_power` |
| Armature object | `ARMATURE_` | `ARMATURE_ship` |
| Armature bone | `BONE_` | `BONE_gear_nose` |
| Exported animation/action | `action_` | `action_gear_deploy` |

**Important:** names are functional identifiers, not just labels. Do not rename them casually once code or `ship.json` references them.

## 4. Anchors consumed by Phase 2C

Create each anchor as a Blender **Empty**. Do not use a mesh vertex, mesh origin or Blender Camera object as a substitute. Anchor location is the reference point consumed by Godot. Rotation is used only by systems that explicitly consume orientation; vane thrust axes are currently defined by their anchor-name family. Keep every anchor's scale at `(1,1,1)`.

### Required for the first anchor-integration pass

| Exact Empty name | Where to place it |
|---|---|
| `ANCHOR_ground_probe_front_left` | Underside, forward/port side of the useful ground-effect footprint |
| `ANCHOR_ground_probe_front_right` | Underside, forward/starboard side |
| `ANCHOR_ground_probe_rear_left` | Underside, aft/port side |
| `ANCHOR_ground_probe_rear_right` | Underside, aft/starboard side |
| `ANCHOR_vane_vertical_a` | Position of a bidirectional local-Y actuator |
| `ANCHOR_vane_vertical_b` | Position of a bidirectional local-Y actuator |
| `ANCHOR_vane_vertical_c` | Position of a bidirectional local-Y actuator |
| `ANCHOR_vane_vertical_d` | Position of a bidirectional local-Y actuator |
| `ANCHOR_vane_horizontal_main_a` | Position of a bidirectional local-Z actuator |
| `ANCHOR_vane_horizontal_side_a` | Position of a bidirectional local-X actuator |
| `ANCHOR_vane_horizontal_side_b` | Position of a bidirectional local-X actuator |
| `ANCHOR_pilot_seat` | Position and orientation of the seated pilot reference |
| `ANCHOR_cockpit_camera` | Pilot eye position; local `-Z` should point in the intended viewing direction |

Front means `-Z`; rear means `+Z`. Left/port means `-X`; right/starboard means `+X`. Keep the four ground probes spread around the footprint rather than clustering them near the centre. The current ground-effect configuration requires at least three valid probes, but author all four.

Vane anchors are **force/application reference points**, not decorative centre points. Put each one where the corresponding vane's force should act on the ship. For a moving vane, keep its visual pivot/origin aligned sensibly with its anchor so that the later rig does not need an arbitrary offset.

### Useful optional anchors (add when their locations are known)

| Exact Empty name | Purpose |
|---|---|
| `ANCHOR_external_camera_focus` | Desired focus point for the exterior camera |
| `ANCHOR_cargo_origin` | Reference origin for future cargo placement |
| `ANCHOR_docking_port` | Docking/alignment reference |

These are not required to get the first 2C anchor integration underway. Add them now only if their intended locations are clear.

The prototype `ship.json` references the full anchor names. The registry removes only the `ANCHOR_` prefix for lookup. Keep spelling and case exact; it does not guess or fuzzy-match names.

### Vane axis families and JSON control weights

The vane anchor prefix declares its available **bidirectional ship-local thrust axis**. It does not assign an exclusive maneuver role:

| Anchor prefix | Available axis | Positive direction |
|---|---|---|
| `ANCHOR_vane_vertical_` | Local Y | Up (`+Y`) |
| `ANCHOR_vane_horizontal_side_` | Local X | Starboard (`+X`) |
| `ANCHOR_vane_horizontal_main_` | Local Z | Aft (`+Z`); forward is the opposite sign |

The anchor's position defines its lever arm. Its rotation is not used for thrust direction in this phase. The actuator can produce force in either sign along its declared axis.

Each `propulsion.vanes[]` entry may include integer `control_weights` from 0 to 100:

```json
"control_weights": {
  "pitch": 100,
  "roll": 100,
  "yaw": 0,
  "lift": 100,
  "main_thrust": 0
}
```

These values describe how strongly the future allocator should recruit that actuator for each requested channel; they are not force percentages. Geometry, authority and runtime condition determine the physical result. A vane may participate in several channels. `lift` and `main_thrust` are higher-level FCC demands; the physical allocator will ultimately resolve them into force and torque.

Current prototype JSON retains legacy `group` identifiers so the existing force implementation remains compatible while the new metadata is introduced. The current force allocator does not yet consume these weights or axis vectors; that is the next implementation increment. Translation channels are intentionally deferred until the FCC has explicit translation commands and input bindings.

Phase 2C is implemented. Available model anchors override the corresponding cockpit, vane and ground-probe transforms. Missing individual anchors do not invalidate a valid GLB: the project restores the scene-authored seat/camera transforms, `.tres` vane positions or calculated ground-probe footprint positions as appropriate. The game reports missing anchor IDs in one diagnostic warning.

## 5. Visible geometry and mesh organization

- The exported GLB must contain at least one actual renderable mesh surface. An Empty-only file, a mesh object with no mesh data, or a mesh with zero surfaces is invalid and will leave the placeholder visible.
- Every visible mesh object intended for the ship model should use `MESH_`.
- Keep separate objects for parts that move independently: landing gear, gear doors, vanes, ramps, switches, levers and similar mechanisms.
- Static parts that share materials and never move may be joined when that reduces unnecessary object/material overhead. Do not join parts that need separate animation, visibility or interaction.
- Keep the hull as static geometry. Do not deform the hull for landing gear or cockpit-switch animations.
- Give moving hard-surface parts sensible origins at their actual mechanical pivots. A gear door should rotate around its hinge, not around the ship origin.
- Apply mesh object rotation/scale where appropriate before export. Avoid negative scale and non-uniform unapplied scale on rigged parts. Do not apply transforms to `SHIP_root` to “fix” the model.
- Use clean normals, non-degenerate geometry and sensible UVs. Keep material count reasonable; separate meshes only when the geometry genuinely needs independent behavior.

The GLB provides visuals and authored transforms. The current physics body, collision shape, mass, centre of mass and flight parameters remain in Godot/`ship.json`. Do not add a second physics body or treat a Blender collision-looking mesh as the project's actual collision shape.

## 6. Armature and mechanical bones — Phase 2D

Rigging is **not required for the first Phase 2C blockout**. When adding it:

- Prefer one shared ship armature object named `ARMATURE_ship`.
- Keep `BONE_root` at the ship datum.
- Name the mechanism bones with the `BONE_` prefix.
- Use bone parenting or rigid one-bone weights for hard mechanical parts.
- Reserve Automatic Weights for geometry that genuinely deforms. It is usually wrong for rigid gear, vanes, doors, switches and ramps.
- Static hull geometry does not need to deform with the armature.
- Avoid a separate armature for every mechanism unless the design proves one shared skeleton is insufficient.
- Export exactly one shared `Skeleton3D`; more than one disables ship action playback.
- Include at least one bone. Name the datum bone exactly `BONE_root`; keep it at the same origin and axes as `SHIP_root`.
- Keep all bone names on the `BONE_` prefix convention. The runtime controller reports deviations.

Example bone names:

```text
BONE_root
BONE_gear_nose
BONE_gear_main_left
BONE_gear_main_right
BONE_vane_bottom_front_left
BONE_vane_bottom_front_right
BONE_vane_bottom_rear_left
BONE_vane_bottom_rear_right
BONE_vane_main_rear
BONE_vane_side_left
BONE_vane_side_right
BONE_cargo_ramp
BONE_switch_main_power
BONE_switch_field_assist
```

## 7. Cockpit interaction pivots — Phase 2E

Interaction nodes are Blender Empty objects whose transforms define the pivot/reference of a physical cockpit control. Parent the visible control mesh beneath the Empty.

```text
INTERACT_switch_main_power
└── MESH_switch_main_power

INTERACT_switch_field_assist
└── MESH_switch_field_assist

INTERACT_lever_throttle
└── MESH_lever_throttle

INTERACT_lever_vector_angle
└── MESH_lever_vector_angle

INTERACT_button_landing_lights
└── MESH_button_landing_lights
```

Use the `switch_`, `lever_` or `button_` categories after `INTERACT_`. Keep each pivot unique and put it at the real hinge/rotation axis or button press axis. The current Phase 2E controller discovers these Empty pivots and creates runtime `Area3D`/`BoxShape3D` hit areas from the union of their visible mesh descendants. Keep the Empty at the real mechanical pivot; do not add collision objects or scripts in Blender. Hit areas are generated by Godot and remain separate from the ship's rigid-body collision.

Supported category prefixes are exactly `switch_`, `lever_` and `button_`. Use unique lowercase snake_case IDs across the whole model. A malformed name, duplicate ID or pivot with no renderable mesh descendants is skipped and reported; it does not invalidate the entire visual model.

### 7.1 Current control bindings

| Exact ID | Runtime mapping | Notes |
|---|---|---|
| `INTERACT_switch_main_power` | Repulsorlift field on/off | Prototype mapping; there is no separate electrical bus yet. |
| `INTERACT_switch_field_assist` | Flight Control Computer assistance toggle | Existing system. |
| `INTERACT_lever_throttle` | Field-power command, 0–100% | Only accepted while the field is online. |
| `INTERACT_lever_vector_angle` | Vector distribution, 0–110° | Normalized lever value maps linearly to the range. |
| `INTERACT_button_landing_lights` | Unbound | Keep the node if the model has the control; no landing-light subsystem exists yet. |

The runtime model is data-only. It never loads or executes scripts from a ship asset. Only the fixed control IDs above reach the flight controller; unknown IDs remain visible/discoverable but are not dispatched. Levers receive a normalized value through the interaction API; a simple click must not snap them to an endpoint.

## 8. Animation names — Phase 2D

Use lowercase `action_` clip names. The name describes the complete mechanism event, not an individual object's track.

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

For one mechanism involving several bones/objects, make those tracks part of the same exported animation clip. An Action visible in Blender is not proof that it is present in the GLB. Make sure it is active or properly stashed/represented on an NLA track for the export mode you use. Verify the clip names in the resulting GLB/Godot import.

Use exported node/bone translation, rotation and scale (and supported shape-key animation) for authored motion. Do not rely on Blender-only drivers, simulations, custom properties or Python scripts to create runtime behavior; those are not a replacement for exported glTF animation channels or Godot game logic.

The runtime discovers clips in imported `AnimationPlayer` nodes. Every clip intended for ship mechanisms must begin with `action_` and use lowercase snake_case. For example, export one clip named `action_gear_deploy` containing every bone/object track needed to complete the gear deployment; do not split the left gear, right gear and doors into unrelated clips unless the game should control them separately.

The runtime API is exposed by `Visuals/Exterior/AnimationController`:

```gdscript
animation_controller.play_action("gear_deploy", loop = false)
animation_controller.stop_action("gear_deploy")
animation_controller.stop_all_actions()
animation_controller.is_action_playing("gear_deploy")
animation_controller.get_available_actions()
```

The `action_started` signal fires when a play request is accepted. `action_finished` fires after a one-shot clip completes; Godot does not emit the animation-finished signal for a looping clip. The controller duplicates imported `Animation` resources before changing their runtime loop mode, so the source import is not edited. Actions do not autoplay; game systems request them when appropriate.

## 9. Export and validation

1. Save the editable `.blend` source separately; do not treat the GLB as the only source file.
2. Export **glTF Binary (`.glb`)**.
3. Include the complete `SHIP_root` hierarchy, its visible meshes and all intended anchors/rigs/actions. Do not accidentally export only the selected hull mesh.
4. Embed textures in the GLB. The current first-version pipeline expects one self-contained model file and does not rely on external texture sidecars.
5. Exclude unrelated scene objects, lights, test primitives and editor-only helpers.
6. Re-import the exported GLB into a clean Blender file or inspect it in Godot. Confirm `SHIP_root`, names, visible geometry, anchor transforms, skeleton and animation clips survived.
7. Test the actual GLB with the project's loader and model-mount tests. A successful Blender export is not proof that Godot can use the file.

Export panel labels can change between Blender versions. Validate the resulting GLB rather than following a checklist of version-specific UI labels.

## 10. First delivery target — start now

For the first handoff, make a **greybox/blockout GLB**, not a finished art asset:

- `SHIP_root` at the origin with identity transform.
- A clearly visible hull and enough visible geometry to make the ship recognizable in Godot.
- The 13 required Phase 2C anchors from Section 4, placed sensibly.
- Correct `MESH_` and `ANCHOR_` names; no duplicate suffixes.
- The first greybox can omit the armature, animation clips and `INTERACT_` controls. Add them now only if doing so does not delay the first testable hull/anchor export.
- Export to `data/ships/prototype_freighter/model.glb` for the prototype path.
- Keep and provide the editable `.blend` alongside the `.glb` so pivots and anchor positions can be adjusted without reverse-engineering the export.

The Phase 2C consumers are already wired. As soon as this GLB is installed at the prototype path, its supplied anchors become authoritative for the cockpit seat/camera, vane force application points and ground-effect probes. Phase 2D now provides the shared-skeleton validation and action playback API; a model can still be mounted without a rig, but bone-driven actions require the one shared `Skeleton3D`. Phase 2E now discovers the `INTERACT_*` pivots, generates dedicated raycast hit areas and exposes safe typed control requests. The project can still load a model that has no interactions yet. Do not wait until 2F to show the first model.

## 11. Diagnostic note — expected test warning

The mount test intentionally generates a tiny GLB with **no renderable mesh surfaces** to verify the failure path. It is supposed to produce:

```text
ShipModelMount: Model contains no renderable MeshInstance3D surfaces.; keeping placeholder visible.
```

The expected result is that the model is rejected, the placeholder stays visible, and the test prints `Ship model mount tests passed.` This warning in that specific test is evidence that the fallback path is working; do not suppress it just to get a warning-free test log.

The same warning when loading your real `model.glb` is **not** acceptable: it means the exported file has no usable renderable mesh surface or failed structural validation. In that case, the placeholder should remain visible until the GLB is corrected.
