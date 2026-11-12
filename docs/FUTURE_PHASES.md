# Future phases — Environment, graphics and cockpit work

**Purpose:** A short navigation and scope document for future implementation. It does not replace the detailed GDD or the Phase 3 annex, and it does not turn proposals into confirmed requirements.

## Authority and document boundaries

- `GAME_DESIGN_DOCUMENT_v0_1.md` remains the overall game-design authority.
- `GDD_ANNEX_v0_3.md` is the detailed, authoritative Phase 3 implementation specification. It explicitly overrides the original GDD only for Phase 3 environment, local-space, hyperspace and associated technical decisions.
- This document connects that Phase 3 specification to the broader graphics, cockpit and modelling intentions in the GDD. It is deliberately shorter than the annex and must not be used instead of reading it before Phase 3 implementation.
- `IMPLEMENTATION_HISTORY.md` records completed work through Phase 2U. Do not repeat those systems or treat historical phase notes as future requirements.

## Next major implementation phase: Phase 3 vertical slice

The approved Phase 3 target is a small, coherent travel loop around the already-developed freighter:

1. One compact test planet with a usable surface, landing pad and small starport.
2. A separate local-space environment containing one large, simple orbital station.
3. A fixed, pre-programmed hyperspace route from the planet to the station and a return leg.
4. Continuous local flight in each local environment. Hyperspace is a deterministic calculated transition, not a continuously simulated journey through a full star system.
5. A complete loop in which the player takes off, reaches a departure envelope, jumps, arrives in local space, approaches the station, jumps back and lands.

The detailed annex defines the route calculation, arrival resolver, scene transitions, environment profiles, local coordinate rules, test pyramid, implementation order and exit criteria. Read `GDD_ANNEX_v0_3.md` in full before writing Phase 3 code.

Phase 3 is intentionally not a general universe simulator. The annex excludes a procedural galaxy, full orbital/n-body mechanics, general waypoint editor, procedural planet streaming, economy, NPCs, combat, station interiors and broader cargo/trading gameplay. Do not silently add these because they appear in the long-term GDD.

## Graphics and environment direction

The existing visual direction is in GDD §17.1: low-poly, 1990s/PS1-inspired 3D, especially in the cockpit, with selective modern techniques only where they improve lighting, atmosphere, shadows, post-processing, material readability or interface clarity.

The current 2M test range already provides a seeded ground surface, survey grid, approach markings, landing-pad markings, boundary beacons and distant faceted terrain silhouettes. Treat this as flight-test reference scenery, not a final planetary terrain system.

For Phase 3, keep graphics subordinate to the travel loop:

- Use authored simple geometry and low-cost procedural terrain detail as specified by the Phase 3 annex.
- Preserve horizon, scale, landing-area and approach readability before adding material complexity.
- Keep local scenes near the origin and avoid introducing a large-world coordinate system without a measured need.
- Avoid compute-shader or third-party planet-framework dependencies; the annex's scope and renderer assumptions remain authoritative.
- Keep test-range regression assets separate from the new planetary and local-space scenes.

A larger visual-art/renderer specification does not currently exist as a separate approved document. Do not invent one or treat specific shader, texture-resolution, anti-aliasing or post-processing settings as confirmed without discussing them first.

## Cockpit and ship-interior direction

The current cockpit implementation is a functional flight prototype: cockpit entry, screen-space CanvasLayer instruments, side gauges, central flight symbology with camera-alignment gating, F3 diagnostics, F4 cargo manifest and F10 display settings.

The earlier physical windshield SubViewport was an experiment and is not the active HUD architecture. Do not restore it as a default assumption.

The GDD's longer-term cockpit/ship-interior direction remains:

- Instruments and switches should make ship operation legible.
- Walkaround inspection and physical access to selected systems should eventually matter.
- Interior complexity should depend on ship size; avoid a full Star Citizen-scale interior simulation.
- Larger ships may use elevators or discrete transitions between meaningful points of interest.
- The first flight prototype was not intended to contain a polished interactive cockpit. Current prototype UI should therefore be treated as the working instrument layer, not as a final cockpit layout decision.

Phase 3 does not require a walkable station interior or a comprehensive redesign of the cockpit. Keep those as later work unless the project owner changes the scope.

## Deferred modelling/modding pipeline proposal — not approved

A separate short note proposed a highly moddable ship pipeline in which a creator could add ship/cockpit models and animations without opening the Godot editor. The concept proposed JSON configuration files and runtime-loaded GLB assets under a per-ship mod directory, using Godot's GLTFDocument API.

This remains an **unapproved exploration**, not a current architecture requirement:

- The current repository does not contain a ModManager or a runtime JSON/GLB ship-loading pipeline.
- The current ship architecture uses authored Godot scenes, scripts and Resources.
- A runtime-mod pipeline introduces security, validation, versioning, asset-import, compatibility and testing costs. It should not be adopted merely because a short modelling note proposed it.
- Before implementing it, decide whether mod support is a real product requirement, who the target modders are, what must be editable outside the editor, and whether Godot Resources/scenes plus an editor workflow would be sufficient.

This consolidates the old modelling annex's content without preserving its unsupported “must” language as a project commitment.

## Suggested order after Phase 3

This is a dependency-oriented proposal, not a confirmed release schedule:

1. Complete and validate the Phase 3 planet → station → planet travel loop.
2. Polish local environment art, materials, lighting and atmosphere against the actual test environments.
3. Revisit cockpit presentation using the working sensor/flight-data contract; choose screen-space, physical windshield or a hybrid only after a rendered prototype is tested.
4. Expand walkaround and physical ship-system interaction where it adds operational value.
5. Decide on a data-driven second ship and only then decide whether a general mod pipeline is justified.
6. Add cargo contracts, services, economy and broader progression after the travel loop is playable.

Do not implement these later items as part of the Phase 3 task unless the owner explicitly revises the scope.
