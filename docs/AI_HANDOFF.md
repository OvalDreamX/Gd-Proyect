# AI Development Handoff — Space Trucker v0.4.0 (Unified)

**Version:** 0.4.0  
**Engine:** Godot 4.7.2 Stable · GL Compatibility · Standard GDScript

## Unified Architecture
- **Ship Visuals & GLB Pipeline (`0.2.5`):** `scenes/ship.tscn` mounts exterior meshes under `$Visuals/Exterior` (`PlaceholderModel` fallback + `ModelMount` runtime GLB replacement), binds anchors via `ShipAnchorIntegration`, and runs `RepulsorliftGroundEffectSystem` at `RepulsorliftSystem` (`index="8"`).
- **6-DOF Actuator Allocator (`0.2.5 F6–F7D`):** `VaneActuatorAllocator` + `RepulsorliftSystem._apply_unified_actuator_allocator` solve bounded actuator outputs across `pitch`, `roll`, `yaw`, `lift`, `main_thrust`, and `translate_x` with single-share damage redistribution and thermal telemetry derived from actual per-vane contributions.
- **Thermal & Integrity (`0.3.7`):** `VaneController` merges convective radiator airflow cooling, endurance wear, stochastic sputter/misalignment, startup reliability, and live `ship.json` propagation while preserving GLB anchor-resolved positions.
- **Solar System, Orbit, Navigation & Space Assist (`0.3.8–0.3.11`):** `PlanetSurface` (600 km Tatooine desert planet + waypoint navigation + outpost landing pad), `StationLocalSpace` (Orbital Relay Cube 01 + Star Wars orbital Tatooine horizon shader), `TransitionCoordinator` + `SimulationClock` hyperspace loop, and FCC Space Mode (`SPACE STANDBY` / `SPACE VECTOR` / `SPACE BRAKE`) routed through the unified actuator allocator.
