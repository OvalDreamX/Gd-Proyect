# Stability Pass 2 — Implementation Notes

## HUD
The HUD's 1280×720 logical layout is letterboxed. The draw origin is a viewport-space translation, so the logical margin must be multiplied by the active scale before it is passed to the CanvasItem transform. The lower heading display now uses the shared wrap-safe formatter.

## Display fallback
A pure helper chooses the largest configured preset fitting the usable display. Invalid saved values use this fallback. If the monitor is smaller than 800×450, no preset satisfies both fit and minimum constraints; the code preserves the explicit minimum window size.

## Pilot lifecycle
The ship listens once for the accepted pilot node's tree_exiting signal. Unexpected removal clears occupancy and restores the hull/interior visibility. This does not add a normal disembark feature.

## Validation
Regression scripts were added or extended but were not executed here. Run the commands in OVERWRITE_README.md in Godot 4.7.2 before treating this pass as runtime-verified.
