extends RefCounted
class_name ArrivalResolver

## Deterministic Phase 3H destination arrival placement and state restoration.
## Supports Floating Origin planetary scenes, resets flight controls cleanly to
## neutral upon arrival, and prevents terrain or station hull overlaps.

const PLANET_SURFACE_CLEARANCE_M: float = 25.0
const STATION_HULL_CLEARANCE_M: float = 60.0

static func resolve_arrival_transform(scene_root: Node, jump_result: Dictionary) -> Dictionary:
	var planned_xform: Transform3D = jump_result.get("arrival_transform", Transform3D.IDENTITY)
	var origin: Vector3 = planned_xform.origin
	var adjusted: bool = false
	var note: String = "Nominal route arrival transform."

	# Fallback to authored marker if planned transform is exactly zero on a scene with a spawn marker.
	var marker := scene_root.get_node_or_null("ShipArrivalPoint") as Marker3D
	if marker == null:
		marker = scene_root.get_node_or_null("ShipSpawnPoint") as Marker3D
	if marker != null and origin.is_zero_approx() and not marker.global_position.is_zero_approx():
		planned_xform = marker.global_transform
		origin = planned_xform.origin
		adjusted = true
		note = "Used destination arrival marker."

	# Guard against spherical planet terrain overlap anywhere on the 360-degree globe.
	if scene_root.has_method("get_spherical_surface_point") and (scene_root.has_method("get_scene_planet_center") or scene_root.has_method("get_planet_center")):
		var planet_center: Vector3 = Vector3(scene_root.call("get_scene_planet_center")) if scene_root.has_method("get_scene_planet_center") else Vector3(scene_root.call("get_planet_center"))
		var origin_offset: Vector3 = Vector3(scene_root.call("get_world_origin_offset")) if scene_root.has_method("get_world_origin_offset") else Vector3.ZERO
		var radial: Vector3 = origin - planet_center
		var unit_dir: Vector3 = radial.normalized() if radial.length_squared() > 0.001 else Vector3.UP
		var surface_pt: Vector3 = Vector3(scene_root.call("get_spherical_surface_point", unit_dir)) + origin_offset
		var min_safe_radius: float = (surface_pt - planet_center).length() + PLANET_SURFACE_CLEARANCE_M
		if radial.length() < min_safe_radius:
			origin = planet_center + unit_dir * min_safe_radius
			adjusted = true
			note = "Lifted arrival altitude radially above spherical terrain clearance."
	elif scene_root.has_method("calculate_terrain_height_m"):
		var terrain_y: float = float(scene_root.call("calculate_terrain_height_m", origin.x, origin.z))
		var min_safe_y: float = terrain_y + PLANET_SURFACE_CLEARANCE_M
		if origin.y < min_safe_y:
			origin.y = min_safe_y
			adjusted = true
			note = "Lifted arrival altitude above terrain clearance."

	# Guard against cube station overlap if OrbitalStationBody exists.
	var station_body := scene_root.get_node_or_null("OrbitalStationBody") as Node3D
	if is_instance_valid(station_body):
		var station_size := Vector3(120.0, 120.0, 120.0)
		if scene_root.has_method("get_station_size_m"):
			station_size = Vector3(scene_root.call("get_station_size_m"))
		var min_station_radius: float = station_size.length() * 0.5 + STATION_HULL_CLEARANCE_M
		var rel: Vector3 = origin - station_body.global_position
		if rel.length() < min_station_radius:
			var push_dir: Vector3 = rel.normalized() if rel.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
			origin = station_body.global_position + push_dir * min_station_radius
			adjusted = true
			note = "Shifted arrival position outside station hull clearance."

	planned_xform.origin = origin
	return {
		"transform": planned_xform,
		"adjusted": adjusted,
		"note": note,
	}

static func apply_arrival_to_scene(scene_root: Node, jump_result: Dictionary) -> Dictionary:
	var ship := scene_root.get_node_or_null("Ship") as RigidBody3D
	if not is_instance_valid(ship):
		return {"valid": false, "error": "Destination scene is missing Ship node."}

	if scene_root.has_method("notify_arrival_grace"):
		scene_root.call("notify_arrival_grace")

	var resolved: Dictionary = resolve_arrival_transform(scene_root, jump_result)
	var arrival_xform: Transform3D = resolved.get("transform", Transform3D.IDENTITY)
	var arrival_vel: Vector3 = Vector3(jump_result.get("arrival_velocity_mps", Vector3.ZERO))

	ship.freeze = false
	ship.linear_velocity = arrival_vel
	ship.angular_velocity = Vector3.ZERO
	ship.global_transform = arrival_xform
	ship.sleeping = false
	if ship.has_method("reset_physics_interpolation"):
		ship.call("reset_physics_interpolation")

	var persistent: Dictionary = jump_result.get("persistent_ship_state", {})
	var cargo := ship.get_node_or_null("CargoSystem")
	if is_instance_valid(cargo) and not persistent.is_empty():
		var preset_name: String = str(persistent.get("cargo_preset", "EMPTY"))
		if cargo.has_method("set_cargo"):
			cargo.call("set_cargo", float(persistent.get("cargo_mass_kg", 0.0)), Vector3(persistent.get("cargo_offset_m", Vector3.ZERO)), preset_name)

	if scene_root.has_method("seat_pilot_immediately"):
		scene_root.call("seat_pilot_immediately")

	var fcc := ship.get_node_or_null("FlightControlComputer")
	if is_instance_valid(fcc) and fcc.has_method("set_assistance_enabled") and not persistent.is_empty():
		fcc.call("set_assistance_enabled", bool(persistent.get("fcc_assistance_enabled", true)))

	var controller := ship.get_node_or_null("FlightController")
	if is_instance_valid(controller):
		if controller.has_method("reset_controls_for_arrival"):
			controller.call("reset_controls_for_arrival", true)
		else:
			controller.set("_field_state", 2)
			controller.set("_field_power_command", 0.0)
			controller.set("_field_power_output", 0.0)
			controller.set("_vector_distribution_degrees", 90.0)
			controller.set("_vector_distribution_actual_degrees", 90.0)
			controller.set("_pitch_command", 0.0)
			controller.set("_roll_command", 0.0)
			controller.set("_yaw_command", 0.0)
			if controller.has_method("_publish_telemetry"):
				controller.call("_publish_telemetry")

	if scene_root.has_method("update_sky_and_atmosphere"):
		scene_root.call("update_sky_and_atmosphere")

	return {
		"valid": true,
		"transform": arrival_xform,
		"adjusted": bool(resolved.get("adjusted", false)),
		"note": str(resolved.get("note", "")),
	}
