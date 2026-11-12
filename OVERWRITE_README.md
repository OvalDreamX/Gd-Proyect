# Space Trucker — Ground Effect Diagnostics Patch

This is a small follow-up to the Ground Effect Phase 2 package. It fixes missing F3 visualization and exposes runtime ground-effect telemetry so the feature can be diagnosed before changing its physics tuning.

## Files

- `scripts/force_vector_debug.gd` — adds an orange force-vector category for ground effect.
- `scripts/ground_effect_diagnostics_overlay.gd` — new read-only F3 telemetry panel.
- `scenes/ship_ground_effect.tscn` — attaches the panel to the Phase 2 test-range ship.
- `docs/GROUND_EFFECT_DIAGNOSTICS.md` — manual verification procedure.

## Install

Extract into the Godot project root and allow overwriting. Do not delete files. Preserve existing `.gd.uid` sidecars.

## Expected result

With the field online, vector at 90 degrees, and the ship close to a supported surface, the F3 panel should show four valid probes, a small positive clearance, proximity near 1, a multiplier approaching 1.15, and a positive additional force. The F3 3D view should show a separate orange upward arrow.

This patch does not change the current force tuning or add automatic landing damping. Godot 4.7.2 runtime compilation/testing was not available in the packaging environment; manual in-engine verification remains required.
