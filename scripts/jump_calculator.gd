extends RefCounted
class_name JumpCalculator

## Pure deterministic hyperspace jump calculator for Phase 3F.
## Computes a validated JumpResult dictionary without modifying scenes or storing Node references.

const ERR_OK: String = "OK"
const ERR_INVALID_ROUTE: String = "INVALID_ROUTE"
const ERR_ROUTE_ENV_MISMATCH: String = "ROUTE_ENV_MISMATCH"
const ERR_ENVELOPE_REJECTED: String = "ENVELOPE_REJECTED"
const ERR_SCENE_MISSING: String = "SCENE_MISSING"

static func calculate_jump(
		route: Resource,
		envelope_result: Dictionary,
		departure_sim_time_s: float,
		persistent_ship_state: Dictionary = {}) -> Dictionary:
	if route == null:
		return _error_result(ERR_INVALID_ROUTE, "No active hyperspace route selected.")

	var route_validation: Dictionary = route.call("validate_route") if route.has_method("validate_route") else {"valid": false, "errors": ["Route resource missing validate_route()."]}
	if not bool(route_validation.get("valid", false)):
		var err_list: PackedStringArray = route_validation.get("errors", PackedStringArray())
		var first_err: String = ", ".join(err_list) if not err_list.is_empty() else "Route validation failed."
		var code: String = ERR_SCENE_MISSING if first_err.contains("destination_scene_path") else ERR_INVALID_ROUTE
		return _error_result(code, first_err, str(route.get("route_id")))

	var route_id: String = str(route.get("route_id"))
	var route_name: String = str(route.get("display_name"))
	var origin_id: String = str(route.get("origin_location_id"))
	var dest_id: String = str(route.get("destination_location_id"))
	var required_env_type: String = str(route.get("required_departure_env_type"))
	var dest_scene: String = str(route.get("destination_scene_path"))
	var duration_s: float = maxf(float(route.get("jump_duration_seconds")), 0.0)
	var visual_s: float = maxf(float(route.get("visual_transition_seconds")), 0.05)

	var active_env_id: String = str(envelope_result.get("jump_environment_id", ""))
	var active_env_type: String = str(envelope_result.get("jump_environment_type", ""))
	if not origin_id.is_empty() and not active_env_id.is_empty() and active_env_id != origin_id:
		return _error_result(
			ERR_ROUTE_ENV_MISMATCH,
			"Route %s requires origin %s (active: %s)." % [route_id, origin_id, active_env_id],
			route_id
		)
	if not required_env_type.is_empty() and not active_env_type.is_empty() and active_env_type != required_env_type:
		return _error_result(
			ERR_ROUTE_ENV_MISMATCH,
			"Route %s requires %s environment (active: %s)." % [route_id, required_env_type, active_env_type],
			route_id
		)

	if not bool(envelope_result.get("jump_eligible", false)):
		return _error_result(
			ERR_ENVELOPE_REJECTED,
			str(envelope_result.get("jump_reason_text", "Ship is not inside jump departure envelope.")),
			route_id
		)

	var arrival_xform: Transform3D = route.call("get_arrival_transform") if route.has_method("get_arrival_transform") else Transform3D.IDENTITY
	var arrival_vel: Vector3 = Vector3(route.get("arrival_velocity_local_mps")) if "arrival_velocity_local_mps" in route else Vector3.ZERO
	var safe_departure_time: float = maxf(departure_sim_time_s, 0.0)

	return {
		"valid": true,
		"error_code": ERR_OK,
		"error_message": "Jump plan validated.",
		"route_id": route_id,
		"route_display_name": route_name,
		"source_location_id": origin_id,
		"destination_location_id": dest_id,
		"destination_scene_path": dest_scene,
		"departure_sim_time_s": safe_departure_time,
		"jump_duration_s": duration_s,
		"visual_transition_s": visual_s,
		"arrival_sim_time_s": safe_departure_time + duration_s,
		"arrival_transform": arrival_xform,
		"arrival_velocity_mps": arrival_vel,
		"persistent_ship_state": sanitize_persistent_state(persistent_ship_state),
	}

static func sanitize_persistent_state(raw_state: Dictionary) -> Dictionary:
	return {
		"cargo_preset": str(raw_state.get("cargo_preset", "EMPTY")),
		"cargo_mass_kg": maxf(float(raw_state.get("cargo_mass_kg", 0.0)), 0.0),
		"cargo_offset_m": Vector3(raw_state.get("cargo_offset_m", Vector3.ZERO)),
		"field_power_command": clampf(float(raw_state.get("field_power_command", 0.0)), 0.0, 1.0),
		"field_power_output": clampf(float(raw_state.get("field_power_output", 0.0)), 0.0, 1.0),
		"vector_distribution_degrees": clampf(float(raw_state.get("vector_distribution_degrees", 90.0)), 0.0, 110.0),
		"vector_distribution_actual_degrees": clampf(float(raw_state.get("vector_distribution_actual_degrees", 90.0)), 0.0, 110.0),
		"fcc_assistance_enabled": bool(raw_state.get("fcc_assistance_enabled", true)),
		"external_camera_view": bool(raw_state.get("external_camera_view", false)),
	}

static func _error_result(code: String, message: String, route_id: String = "") -> Dictionary:
	return {
		"valid": false,
		"error_code": code,
		"error_message": message,
		"route_id": route_id,
		"route_display_name": "",
		"source_location_id": "",
		"destination_location_id": "",
		"destination_scene_path": "",
		"departure_sim_time_s": 0.0,
		"jump_duration_s": 0.0,
		"visual_transition_s": 0.0,
		"arrival_sim_time_s": 0.0,
		"arrival_transform": Transform3D.IDENTITY,
		"arrival_velocity_mps": Vector3.ZERO,
		"persistent_ship_state": {},
	}
