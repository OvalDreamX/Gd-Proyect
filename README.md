# Space Trucker — project guide

**Engine:** Godot 4.7.2 Stable · GDScript · GL Compatibility · Windows  
**Main scene:** `res://scenes/test_range.tscn`

Space Trucker is a single-player ship-operations and space-trucking prototype. The current build concentrates on walk-up/cockpit entry, assisted Newtonian ship flight, repulsorlift vane behavior, atmosphere and shield glide, flight instruments, thermal limits and cargo mass distribution.

## Current prototype systems

- One physical ship `RigidBody3D` owns movement, mass, inertia and collisions.
- Repulsorlift translation and vane-based pitch/roll/yaw force allocation.
- Bounded PI rate-assist FCC and direct-vane mode.
- Atmospheric drag, wind and shield-generated glide lift.
- Sensor-data boundary and inertial flight-path marker.
- Cockpit/external cameras, recentering, F3 diagnostics and display settings.
- Per-vane temperature, load, wear, degradation, sputtering and failure.
- Abstract cargo manifest affecting actual rigid-body mass and centre of mass.

The project is not yet a complete cargo economy, planetary environment, spaceport or orbital simulation. Keep the test range as the flight-model regression scene.

## Controls

| Input | Action |
|---|---|
| F near ship / while seated | Enter cockpit / toggle repulsorlift field |
| W / S | Increase / decrease main-vector power |
| Q / E | Change main-vector direction |
| Mouse | Pitch/roll virtual-stick commands |
| A / D | Yaw |
| RMB | Toggle camera-look mode |
| C | Switch cockpit/external camera |
| Mouse wheel | Zoom external camera |
| F3 | Diagnostics and force visualization |
| F4 | Cargo manifest |
| F10 | Display settings |
| Escape | Close F4/F10 panel |

Input mappings in `project.godot` are authoritative.

## Documentation map

| Document | Purpose |
|---|---|
| `docs/GAME_DESIGN_DOCUMENT_v0_1.md` | Overall design authority. Status labels distinguish confirmed decisions, proposals and open questions. |
| `docs/GDD_ANNEX_v0_3.md` | Detailed authoritative Phase 3 environment/travel implementation specification. |
| `docs/FUTURE_PHASES.md` | Short roadmap connecting Phase 3 to later graphics, cockpit and modelling work. |
| `docs/IMPLEMENTATION_HISTORY.md` | Consolidated history of Phases 2A–2U, including superseded decisions. |
| `docs/AI_HANDOFF.md` | Current architecture and instructions for future development conversations. |
| `docs/TESTING.md` | Regression commands, manual checks and validation policy. |
| `docs/GDD_REVIEW_PROPOSALS.md` | Proposed GDD clarifications for owner review; the GDD itself is unchanged. |

The root-level Phase 2 INSTALL notes and the older duplicate GDD/hand-off files are historical material and should not be used as current project guidance. The GDD Markdown file listed above is the canonical editable copy; same-name DOCX/PDF files, if retained, are archival exports rather than independent design authorities.

Do not claim a milestone is runtime-validated until the tests have actually been run with the project's pinned Godot 4.7.2 executable and the relevant in-game behavior has been inspected.
