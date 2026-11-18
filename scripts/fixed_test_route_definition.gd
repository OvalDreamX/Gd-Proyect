extends Resource
class_name FixedTestRouteDefinition

## Fixed test route leg definition for Phase 3F (GDD Annex v0.3 §4.1 & §7).
## Defines one deterministic leg (Planet -> Station or Station -> Planet).

@export var route_id: StringName = &"route_planet_to_station"
@export var display_name: String = "Test Planet Departure -> Orbital Relay Cube 01"
@export var origin_location_id: StringName = &"env_test_planet_surface"
@export var destination_location_id: StringName = &"env_station_local_space"
@export var required_departure_env_type: String = "PLANET_SURFACE"
@export_file("*.tscn") var destination_scene_path: String = "res://scenes/station_local_space.tscn"
@export var reverse_route_id: StringName = &"route_station_to_planet"
@export_file("*.tres") var reverse_route_path: String = "res://data/routes/route_station_to_planet.tres"

@export_category("Transit & Arrival")
@export_range(1.0, 86400.0, 10.0) var jump_duration_seconds: float = 420.0
@export_range(0.05, 10.0, 0.05) var visual_transition_seconds: float = 1.6
@export var arrival_position_local_m: Vector3 = Vector3(0.0, 0.0, 450.0)
@export var arrival_rotation_degrees: Vector3 = Vector3.ZERO
@export var arrival_velocity_local_mps: Vector3 = Vector3.ZERO

func get_arrival_transform() -> Transform3D:
	var arrival_basis := Basis.from_euler(Vector3(
		deg_to_rad(arrival_rotation_degrees.x),
		deg_to_rad(arrival_rotation_degrees.y),
		deg_to_rad(arrival_rotation_degrees.z)
	)).orthonormalized()
	return Transform3D(arrival_basis, arrival_position_local_m)

func validate_route() -> Dictionary:
	var errors := PackedStringArray()
	if String(route_id).strip_edges().is_empty():
		errors.append("route_id must not be empty.")
	if String(origin_location_id).strip_edges().is_empty():
		errors.append("origin_location_id must not be empty.")
	if String(destination_location_id).strip_edges().is_empty():
		errors.append("destination_location_id must not be empty.")
	if origin_location_id == destination_location_id:
		errors.append("origin_location_id and destination_location_id must differ.")
	if jump_duration_seconds <= 0.0:
		errors.append("jump_duration_seconds must be positive.")
	if destination_scene_path.strip_edges().is_empty() or not ResourceLoader.exists(destination_scene_path):
		errors.append("destination_scene_path does not exist: %s" % destination_scene_path)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
	}
