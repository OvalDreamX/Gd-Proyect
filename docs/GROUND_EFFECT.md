# Repulsorlift ground effect — implementation notes

## Behaviour

Ground effect is a near-surface increase in the ship's upward repulsorlift force. It is independent of atmospheric density and remains available in vacuum.

The implementation deliberately modifies only the positive component of the main repulsorlift resultant along the local planetary up vector. It does not increase forward/lateral thrust, downward braking force, manoeuvring-vane output, or aerodynamic lift. No automatic altitude hold, damping, landing assist, or translational-lift effect is added.

For average probe clearance `h` and configured footprint width `L`:

```text
x = clamp(h / L, 0, 1)
proximity = 1 - x*x*(3 - 2*x)
added_upward_force = main_upward_force * max_gain * proximity
```

The curve is continuous with zero slope at both ends. The prototype uses `L = 5 m` and `max_gain = 0.15`, giving at most 15% extra upward force at the surface and zero gain at/above 5 m clearance.

## Surface sampling

- Four downward ray probes are used.
- The ship's own RID is excluded from every ray.
- A hit is accepted only when its surface normal has at least the configured alignment with local up; this rejects walls and steep sides.
- At least three valid probes are required. Their clearances are averaged to reduce sensitivity to one bad sample or a single edge hit.
- The planetary reference frame supplies local up. Without it, the system falls back to the ship's gravity vector.
- Ray queries use the configured collision mask.

The prototype GLB does not exist yet. Until model anchors are present, the system places the four fallback probes at 40% of the hull half-extents, at the bottom of the JSON-defined hull dimensions. When a future model provides nodes matching `probe_anchors`, those nodes take precedence. The JSON anchor names are therefore already the intended stable interface for the GLB phase.

## Configuration

`ground_effect` in `data/ships/prototype_freighter/ship.json` controls the feature:

| Field | Meaning |
|---|---|
| `enabled` | Master switch |
| `probe_anchors` | Node names/paths for the surface probes |
| `footprint_width_m` | Clearance at which the effect reaches zero |
| `max_gain` | Maximum fractional increase to upward main force; 0.15 = 15% |
| `probe_ray_start_offset_m` | Starts each ray slightly above its probe |
| `minimum_valid_probes` | Minimum accepted surface hits |
| `surface_normal_alignment_min` | Minimum dot product between hit normal and local up |
| `collision_mask` | Physics collision layers sampled by probes |

The loader rejects missing/duplicate probe names, too few probes, invalid ranges, and non-positive footprint width when enabled. Schema version remains 1 because these are optional fields within the existing optional `ground_effect` section; old definitions without the section remain valid and simply have no ground effect.

## Runtime wiring

The test range now instances `ship_ground_effect.tscn`, an inherited variant of the original ship scene. It swaps the existing `RepulsorliftSystem` script for `RepulsorliftGroundEffectSystem`, which calls the parent force allocator first and adds the bounded force in the same flight-control call. The base ship scene remains unchanged for other uses.

The current runtime loads the built-in prototype definition at `res://data/ships/prototype_freighter/ship.json`. General mod discovery and per-instance definition injection remain later work; this implementation does not claim to support arbitrary ship mods yet.

## Manual test procedure

1. Run the test range and pilot the freighter.
2. Enable the repulsorlift field and set the vector to 90 degrees (vertical).
3. Open the diagnostic HUD and inspect `ground_effect_*` telemetry. Near the pad, expect four valid probes, a small positive average clearance, proximity near 1, and multiplier approaching 1.15.
4. Ascend slowly. The multiplier should decrease smoothly and reach 1.0 at approximately 5 m clearance.
5. At 90 degrees, compare hover response near the pad and above 5 m. Ground effect should provide a small additional upward acceleration near the surface.
6. Set the main vector to 0 degrees (forward). Ground-effect force should remain zero even near the surface.
7. Test with atmosphere disabled if available. Ground effect should remain active.
8. Move close to an edge or over a surface outside the collision mask. With fewer than three valid probes, the effect should turn off rather than use stale readings.

Telemetry keys include `ground_effect_enabled`, `ground_effect_valid_probe_count`, `ground_effect_average_clearance_m`, `ground_effect_proximity`, `ground_effect_multiplier`, and `ground_effect_force_world`.
