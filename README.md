# Space Trucker — Flight and Ship Systems Prototype

**Engine:** Godot 4.7.2 Stable (GDScript, GL Compatibility)  
**Platform target:** Windows PC  
**Main scene:** `res://scenes/test_range.tscn`

Space Trucker is a single-player ship-operations and space-trucking prototype. The current build focuses on walk-up/cockpit entry, assisted ship flight, propulsion-vane behavior, cockpit instrumentation, cargo mass distribution and thermal limits.

## Current prototype systems

- Single `RigidBody3D` ship with simplified Newtonian motion.
- Repulsorlift main-vector translation and vane-based pitch/roll/yaw forces.
- Flight-control computer with assisted rate control and direct-vane mode.
- Atmospheric drag, wind and shield-generated glide lift.
- Sensor-data boundary for attitude, heading, velocity and altitude instruments.
- Inertial flight-path marker with clipped edge cue.
- Cockpit and external camera, cockpit recentering, F3 diagnostics and display settings.
- Per-vane temperature, load, wear, degradation and sputtering.
- Cargo manifest with payload mass and center-of-mass offset.

The prototype is not yet a complete cargo economy, planetary environment, spaceport or orbital simulation. Keep the test range as the flight-model regression scene.

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

Input mappings in `project.godot` remain authoritative.

## Development notes

Read:
- `docs/GAME_DESIGN_DOCUMENT_v0_1.md` — design authority.
- `docs/DEVELOPMENT_CHANGELOG.md` — implementation ledger.
- `docs/AI_HANDOFF.md` — architecture and workflow constraints.
- `INSTALL_PHASE_2U_POLISH.md` — latest polish pass and verification commands.

Do not claim a milestone is runtime-validated until its Godot tests have actually been run.
