extends Resource
class_name StationDefinition

## Data-driven orbital cube station destination definition (GDD Annex v0.3 §4.1).

enum OrbitMode {
	STATIC_TEST_ANCHOR = 0,
	CIRCULAR_ANALYTIC = 1,
}

@export var station_id: StringName = &"station_orbital_cube_01"
@export var display_name: String = "Orbital Relay Cube 01"
@export var parent_body_id: StringName = &"body_test_planet"
@export var orbit_mode: OrbitMode = OrbitMode.STATIC_TEST_ANCHOR
@export_range(0.0, 10000000.0, 1000.0) var orbital_radius_m: float = 180000.0
@export var system_relative_position_m: Vector3 = Vector3(0.0, 0.0, -180000.0)
@export_file("*.tscn") var station_scene_path: String = "res://scenes/station_local_space.tscn"
@export_file("*.tres") var environment_profile_path: String = "res://data/environments/station_local_space.tres"

@export_category("Local Geometry & Arrival")
@export var station_size_m: Vector3 = Vector3(120.0, 120.0, 120.0)
@export var safe_arrival_offset_m: Vector3 = Vector3(0.0, 0.0, 450.0)
@export var docking_zone_offset_m: Vector3 = Vector3(0.0, 0.0, 78.0)
@export var docking_zone_size_m: Vector3 = Vector3(42.0, 28.0, 34.0)
@export_range(50.0, 5000.0, 10.0) var exclusion_radius_m: float = 250.0

func calculate_station_half_extents() -> Vector3:
	return station_size_m * 0.5

func get_orbit_mode_name() -> String:
	return "STATIC_TEST_ANCHOR" if orbit_mode == OrbitMode.STATIC_TEST_ANCHOR else "CIRCULAR_ANALYTIC"

func validate_definition() -> Dictionary:
	var errors := PackedStringArray()
	if String(station_id).strip_edges().is_empty():
		errors.append("station_id must not be empty.")
	if display_name.strip_edges().is_empty():
		errors.append("display_name must not be empty.")
	if station_scene_path.is_empty() or not ResourceLoader.exists(station_scene_path):
		errors.append("station_scene_path does not exist: %s" % station_scene_path)
	if station_size_m.x <= 1.0 or station_size_m.y <= 1.0 or station_size_m.z <= 1.0:
		errors.append("station_size_m must be > 1 m on all axes.")
	var min_safe_dist: float = calculate_station_half_extents().length() + 40.0
	if safe_arrival_offset_m.length() < min_safe_dist:
		errors.append("safe_arrival_offset_m is too close to station hull.")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
	}
