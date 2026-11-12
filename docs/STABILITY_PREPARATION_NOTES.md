# Stability Preparation Notes

## Applied in this overwrite

The Phase 2U HUD subclass captures the diagnostic scroll position before calling the base HUD refresh, performs its wording substitutions and trim block append, then restores that position after the final text assignment. This closes the scroll-reset bug without refactoring the base HUD or changing the telemetry contract.

The flight controller now returns from the F3 debug-mode wheel branch without calling `set_input_as_handled()`. The event is already in `_unhandled_input`, meaning GUI controls had a chance to consume it first. If the GUI did not consume it, it is ignored during debug interaction instead of being intercepted as an external-camera zoom.

## Deferred work

- **HUD refresh throttling:** consider reducing the diagnostic text rebuild frequency independently from flight telemetry after profiling in Godot. Do not reduce physics or instrument update cadence.
- **HUD scale offset and heading wrap:** verify the draw transform's translation convention with the current base HUD and test at several aspect ratios and scale settings before modifying it.
- **Display resolution fallback:** make invalid saved resolutions choose the largest supported preset that fits the active monitor; keep the minimum-window constraint explicit.
- **Pilot ownership:** release a stale pilot claim if the player node exits unexpectedly; verify the player's scene-transition/exit behavior and exterior/interior visibility state.
- **Cargo inertia:** derive payload inertia about the combined center of mass, accounting for parallel-axis contributions and the limitations of Godot's exposed diagonal custom inertia. Test against the actual collider geometry and physics backend.
- **Planetary frame:** add a shared local frame provider for up/north/east, altitude, local gravity and atmospheric air-mass velocity, then migrate atmosphere, sensors, HUD and player locomotion together.
- **Aerodynamic moments:** defer until ship geometry and credible centers of pressure are defined.

These are planning items, not implemented or runtime-validated by this package.
