# Blender ship authoring — quick reference

This is the practical companion to `SHIP_ASSET_PIPELINE.md`. The pipeline contract is authoritative if this quick sheet and the longer document ever differ.

## Scene setup

- Blender scene units: Metric, Unit Scale `1.0`.
- Ship forward: `-Z`; up: `+Y`; starboard: `+X`.
- Ship datum: world origin `(0, 0, 0)`; export root named `SHIP_root`.
- Model dimensions are metres. Keep anchor Empty scale at `(1, 1, 1)`.

## Object naming

| Object kind | Prefix | Example |
|---|---|---|
| Visible geometry | `MESH_` | `MESH_hull_main` |
| Empty spatial reference | `ANCHOR_` | `ANCHOR_pilot_seat` |
| Empty cockpit control pivot | `INTERACT_` | `INTERACT_switch_main_power` |
| Ship armature object | `ARMATURE_` | `ARMATURE_ship` |
| Armature bone | `BONE_` | `BONE_gear_nose` |
| Exported animation | `action_` | `action_gear_deploy` |

Identifiers after prefixes are lowercase snake_case, with no `.001` duplicate suffixes.

## Suggested hierarchy

```text
SHIP_root
├── MESH_hull_main
├── MESH_engine_left
├── MESH_engine_right
├── ANCHOR_ground_probe_front_left
├── ANCHOR_ground_probe_front_right
├── ANCHOR_ground_probe_rear_left
├── ANCHOR_ground_probe_rear_right
├── ANCHOR_cockpit_camera
├── ANCHOR_pilot_seat
├── INTERACT_switch_main_power
│   └── MESH_switch_main_power
└── ARMATURE_ship
    └── BONE_root
        ├── BONE_gear_nose
        ├── BONE_gear_main_left
        ├── BONE_gear_main_right
        └── BONE_cargo_ramp
```

This is a conceptual hierarchy. Blender armature bones are not ordinary scene objects; the diagram shows their logical parent relationship. Geometry may be parented to bones using Blender's Armature Deform / bone-parenting workflows.

## Mechanical rigging

- One ship armature is the preferred arrangement.
- Keep root bone at ship datum.
- Use bone parenting or one-bone rigid weights for hard components.
- Reserve Automatic Weights for flexible/deforming surfaces.
- Do not let the hull deform with landing gear or switch actions.
- Name all bones with `BONE_` so the imported skeleton can be inspected and validated.

## Actions and NLA

Create distinct actions (`action_gear_deploy`, `action_gear_retract`, etc.). For multi-object animations, arrange all object/bone tracks so one exported animation contains the complete motion. In the glTF exporter, use an animation mode that exports active/stashed Actions or NLA tracks. Stash/push down Actions that are not active. Check the resulting GLB in Godot; an action visible in Blender's Action Editor is not necessarily present in the exported file.

Only supported glTF animation channels should drive game mechanisms: node translation/rotation/scale, pose bones and shape keys. Use GDScript for gameplay logic, not custom Blender properties that glTF will discard.

## Before sending a ship mod

- [ ] One `.glb` with embedded textures.
- [ ] Root `SHIP_root` at origin, identity rotation, unit scale.
- [ ] Nose points `-Z`.
- [ ] All anchors use `ANCHOR_` and have unique names.
- [ ] All visible geometry objects intended for validation use `MESH_`.
- [ ] Every `INTERACT_` has a visible mesh child.
- [ ] One shared armature where practical; bones use `BONE_`.
- [ ] Required animations use `action_` and are actually exported.
- [ ] GLB passes the runtime ship-model test.
