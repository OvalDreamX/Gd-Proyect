# F6 — Geometry-driven yaw actuator authoring note

**Status:** F6 implementation contract. This note supersedes any older prototype example that identifies the two side-mounted yaw actuators as `ANCHOR_vane_horizontal_side_a/b`.

## Coordinate and naming contract

The anchor-name family declares the actuator's available **bidirectional ship-local thrust axis**. The anchor's location defines its application point and lever arm. Anchor rotation does not rotate the thrust axis in this implementation.

| Anchor family | Bidirectional thrust axis | Positive axis direction |
|---|---|---|
| `ANCHOR_vane_vertical_*` | Local Y | Up (`+Y`) |
| `ANCHOR_vane_horizontal_side_*` | Local X | Starboard (`+X`) |
| `ANCHOR_vane_horizontal_main_*` | Local Z | Aft (`+Z`); the actuator may also push forward (`-Z`) |

A physical location and a thrust-axis family are not the same thing. In particular, the prototype yaw actuators are mounted at the port and starboard sides of the hull, but their thrust axis is longitudinal. Their names therefore use the `horizontal_main` family:

```text
ANCHOR_vane_horizontal_main_side_left
ANCHOR_vane_horizontal_main_side_right
```

Place the left/port actuator at negative local X and the right/starboard actuator at positive local X. Keep the two anchor positions separated across the hull. Their shared local thrust axis is `+Z`, but each is bidirectional.

## Why this geometry is required

Yaw is a moment around local Y. A force along local X applied at a point separated only along local X cannot generate that moment: the line of action is parallel to the separation. The old `horizontal_side` axes therefore could not create the intended yaw couple from the prototype's port/starboard positions.

With both actuators on local Z and separated along X, positive yaw uses:

- Port/left actuator: force toward `-Z` (forward).
- Starboard/right actuator: force toward `+Z` (aft).

Their longitudinal forces cancel while both create the same negative-Y yaw moment. This preserves the existing control sign: a positive yaw command turns the nose right.

Do not rename an anchor to `horizontal_side` merely because the mesh is physically mounted on the side. Use the prefix that describes the force axis. `horizontal_side` remains valid for actuators whose force axis is local X, including future lateral translation or other geometry that genuinely uses that axis.

## JSON control weights

The axis family does not assign an exclusive gameplay role. Use `control_weights` to specify which control channels may recruit an actuator. A longitudinal (`horizontal_main`) actuator may have a `yaw` weight, and a vertical (`vertical`) actuator may have both `lift`, `pitch` and `roll` weights. Weights are integer recruitment priorities from 0 to 100, not force percentages.

The prototype yaw entries retain their stable actuator IDs and ratings:

- `side_left`: anchor `ANCHOR_vane_horizontal_main_side_left`, yaw weight 100, nominal authority 0.03 TWR.
- `side_right`: anchor `ANCHOR_vane_horizontal_main_side_right`, yaw weight 100, nominal authority 0.03 TWR.

The `group` field remains required by the current ship-definition schema and is retained for compatibility with other legacy consumers. **Yaw allocation no longer looks up `side_left` or `side_right` group IDs.** It discovers actuators by stable IDs, channel weights and geometry. The allocator supports arbitrary group IDs and multiple actuators in the same group.

## Runtime behavior

Pitch, roll and yaw are now passed through one combined geometry allocation per physics update. Each physical actuator receives one bounded scalar output in `[-1, +1]`; a vane with weights on multiple active channels is not independently commanded once per channel. This is important for future definitions that deliberately share an actuator between pitch, roll and yaw.

The yaw target preserves the prototype's previous rated full-command yaw authority. Pitch/roll retain their existing `maneuver_authority_fraction` tuning scalar; yaw does not inherit that 5% scalar. Geometry, effective thrust axis after alignment drift, COM lever arm, force rating, damage/thermal authority, and permitted redistribution determine actual achieved torque. Damage-recovery headroom is partitioned by active control channel so an unrelated pitch/roll actuator cannot absorb yaw-vane recovery budget; an actuator shared by multiple channels still has one aggregate headroom cap. Unsatisfied wrench remains visible in allocator residuals.

## Model migration

Rename the prototype's old yaw anchors:

| Old identifier | New identifier |
|---|---|
| `ANCHOR_vane_horizontal_side_a` | `ANCHOR_vane_horizontal_main_side_left` |
| `ANCHOR_vane_horizontal_side_b` | `ANCHOR_vane_horizontal_main_side_right` |

Keep their authored positions at the port/starboard force-application points. Do not rotate the Empty to obtain the longitudinal thrust axis; the family declares `+Z` and the actual vane model/pivot should be oriented to match that declared force direction. The anchor rotation is not consumed by the allocator.

If a model still contains only the old names, the new JSON anchor references will be missing and the corresponding `.tres` fallback positions/axes are used. This remains a safe fallback but will not use the model-authored side-vane positions until the GLB is renamed and re-exported.
