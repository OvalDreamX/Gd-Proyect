# Phase 3A — Repository Audit & Environment Contract

**Document role:** Phase 3A deliverable for `docs/GDD_ANNEX_v0_3.md` §9  
**Engine target:** Godot 4.7.2 Stable · GDScript · GL Compatibility  
**Regression scene:** `res://scenes/test_range.tscn`

---

## 1. Existing Architecture & Call-Site Map

### 1.1 Ship ownership & scene hierarchy
- `res://scenes/ship.tscn`: Single `RigidBody3D` root (`ShipInteractable`, `scripts/ship_interactable.gd`), owning mass, inertia, collision, pilot seat (`CockpitSeat`), cameras (`CameraController`), `VaneController`, `RepulsorliftSystem`, `FlightControlComputer`, `AtmosphericFlightModel`, `FlightSensorSuite`, `CargoSystem`, `PlanetaryGravityBody`, and `FlightController` (`ShipFlightController`).
- `res://scenes/ship_ground_effect.tscn`: Inherited scene from `ship.tscn` that swaps `RepulsorliftSystem` for `scripts/repulsorlift_ground_effect_system.gd` and adds `GroundEffectDiagnostics`.
- `res://scenes/test_range.tscn`: Instances `ship_ground_effect.tscn` as `Ship`, `player.tscn` as `Player`, and `PlanetaryReferenceFrame` as a direct child of the scene root.

### 1.2 Current gravity, up, north, and atmosphere consumers
| Script | Current Environment Dependency | Default / Fallback Behavior | Phase 3B Integration Need |
|---|---|---|---|
| `scripts/planetary_reference_frame.gd` | Scene-root `Node3D` (`FLAT_PLANE` / `SPHERICAL`) | `surface_gravity_mps2 = 9.81`, `north_reference_local = (0,0,-1)` | Accept/apply `EnvironmentProfile` & `CelestialBodyDefinition` data |
| `scripts/planetary_gravity_body.gd` | `NodePath("../../PlanetaryReferenceFrame")` | Leaves `RigidBody3D.gravity_scale` untouched if frame missing | Query `EnvironmentManager`; explicitly zero `gravity_scale` & force in `LOCAL_SPACE` |
| `scripts/atmospheric_flight_model.gd` | `NodePath("../../PlanetaryReferenceFrame")` | `atmosphere_enabled = true`, `1.225 kg/m³`, wind `(5,0,-6.25)`, `-10°C` | Override density/wind/temp from active `EnvironmentProfile` when `EnvironmentManager` is present |
| `scripts/flight_sensor_suite.gd` | `NodePath("../../PlanetaryReferenceFrame")` + sibling `AtmosphericFlightModel` | World `UP`, `(0,0,-1)` north, `global_position.y` altitude | Fall back cleanly to `EnvironmentManager`; expose `environment_id` & `environment_type` |
| `scripts/repulsorlift_system.gd` | Queries `PlanetaryGravityBody.get_local_gravity_vector_world()` and `AtmosphericFlightModel.ambient_temperature_celsius` | Reads `_ship.get_gravity()` and `-10.0°C` fallback | Automatically receives space/planet ambient temperature once `AtmosphericFlightModel` reads `EnvironmentProfile` |
| `scripts/player_controller.gd` | `NodePath("../PlanetaryReferenceFrame")` | `physics/3d/default_gravity` & world `UP` | Retain existing behavior on planet surface; safe fallback in space |

### 1.3 HUD telemetry flow
- `ShipFlightController` polls `FlightSensorSuite.get_instrument_snapshot()` and passes telemetry dictionaries to `FlightHUDPhase2U` (extends `FlightHUD`, `scripts/flight_hud.gd`).
- `FlightHUD` never reads `RigidBody3D` physics nodes directly; all instrument readouts flow through `FlightSensorSuite`.
- Phase 3 jump-eligibility and environment status will extend `FlightSensorSuite` / `ShipFlightController` -> `FlightHUDPhase2U` (and `F3` debug text) without creating a second HUD system.

### 1.4 Existing automated test pattern
- Tests live in `res://tests/*_test.gd`, extend `SceneTree`, defer `_run_tests()` from `_initialize()`, use `await process_frame` / `await physics_frame`, and exit via `quit(1 if _failures > 0 else 0)`.
- Executed headless on Windows via:
  `& $godot --headless --path . --script res://tests/<test_file>.gd`

---

## 2. Stable Phase 3 Identifiers

| Entity | Stable ID (`StringName`) | Purpose |
|---|---|---|
| Test Planet | `&"test_planet"` | Compact spherical test planet (`CelestialBodyDefinition`) |
| Planet Surface Environment | `&"env_test_planet_surface"` | Continuous planetary flight & starport scene (`PLANET_SURFACE`) |
| Planet Starport Location | `&"loc_starport_alpha"` | Surface launch/landing pad location ID |
| Orbital Station | `&"station_cube_01"` | Cube-shaped orbital destination (`OrbitalDestinationDefinition`) |
| Station Local Space Environment | `&"env_station_local_space"` | Zero-gravity, zero-atmosphere local space scene (`LOCAL_SPACE`) |
| Outbound Route Leg | `&"route_planet_to_station"` | Fixed departure envelope -> cube station local arrival |
| Return Route Leg | `&"route_station_to_planet"` | Fixed station departure zone -> planetary upper-atmosphere approach |

---

## 3. Coordinate Frames & Explicit Units

1. **System Frame:** Logical IDs and analytical body/station descriptors (`body_id`, `station_id`, `orbit_radius_m`). Never placed as astronomical distances inside a Godot `Node3D` hierarchy.
2. **Body Frame:** Positions relative to the active celestial body center (`global_position - body_center`), providing radial `up_world`, tangent `north_world`, tangent `east_world`, and `altitude_m = radial_distance - radius_m`.
3. **Local Simulation Frame:** Active Godot scene origin near `(0, 0, 0)` so ship coordinates stay numerically well-conditioned.
4. **Ship Local Basis (unchanged):** Forward `-Z`, Up `+Y`, Starboard `+X`.
5. **Local Wind Vector Basis (unchanged):** `Vector3(east_mps, up_mps, north_mps)` in `PlanetaryReferenceFrame` / `AtmosphericFlightModel` (`X = East`, `Y = Up`, `Z = North`, where `-Z` is North).
6. **Mandatory Units:** Metres (`_m`), metres/second (`_mps`), metres/second² (`_mps2`), kilograms (`_kg`), newtons (`_n`), kilograms/metre³ (`_kg_m3`), degrees Celsius (`_celsius`), simulation seconds (`_seconds`).

---

## 4. Parallel Development Boundary (GLB/Armatures vs Phase 3)

To keep Phase 3 patches cleanly mergeable with concurrent GLB/armature work:
- **Do not touch in Phase 3 patches:** `scenes/ship.tscn` visual hierarchy, `scripts/ship_model_loader.gd`, `scripts/ship_model_validator.gd`, `scripts/ship_anchor_registry.gd`, `scripts/ship_definition*.gd`, `scripts/vane_controller.gd`, `data/ships/*`.
- **Keep `scenes/test_range.tscn` untouched:** All Phase 3 planet/station scenes are separate scene files (`scenes/planet_surface.tscn`, `scenes/station_local_space.tscn`).
- **Backward-compatible ship hooks:** Any ship-side script touched (`PlanetaryGravityBody`, `AtmosphericFlightModel`, `FlightSensorSuite`) must preserve 100% identical defaults and behavior when no `EnvironmentManager` is present.
