extends RefCounted
class_name JumpEnvelopeEvaluator

## Pure deterministic departure-envelope evaluator for Phase 3D.
## Evaluates whether the ship meets active environment jump conditions and
## returns structured eligibility + human-readable rejection reasons for HUD/F3.

const REASON_READY: String = "READY"
const REASON_ENV_DISALLOWED: String = "ENV_DISALLOWED"
const REASON_SYSTEMS_OFFLINE: String = "SYSTEMS_OFFLINE"
const REASON_SHIP_IN_CONTACT: String = "SHIP_IN_CONTACT"
const REASON_SENSOR_ALTITUDE_INVALID: String = "SENSOR_ALTITUDE_INVALID"
const REASON_BELOW_MIN_ALTITUDE: String = "BELOW_MIN_ALTITUDE"
const REASON_INSIDE_EXCLUSION_ZONE: String = "INSIDE_EXCLUSION_ZONE"
const REASON_SPEED_ABOVE_LIMIT: String = "SPEED_ABOVE_LIMIT"

static func evaluate(context: Dictionary) -> Dictionary:
	var env_id: String = str(context.get("environment_id", "unknown"))
	var env_type: String = str(context.get("environment_type", "PLANET_SURFACE"))
	var env_label: String = str(context.get("environment_label", env_id))
	var jump_allowed: bool = bool(context.get("jump_allowed", false))
	var configured_min_alt: float = maxf(float(context.get("min_altitude_m", 0.0)), 0.0)
	var effective_min_alt: float = configured_min_alt if env_type == "PLANET_SURFACE" else 0.0
	var exclusion_radius_m: float = maxf(float(context.get("exclusion_radius_m", 0.0)), 0.0)
	var max_speed_mps: float = maxf(float(context.get("max_speed_mps", 0.0)), 0.0)
	var require_online: bool = bool(context.get("require_systems_online", true))
	var disallow_contact: bool = bool(context.get("disallow_contact", true))

	var altitude_m: float = float(context.get("altitude_m", 0.0))
	var altitude_valid: bool = bool(context.get("altitude_valid", true))
	var radial_distance_m: float = maxf(float(context.get("radial_distance_m", 0.0)), 0.0)
	var speed_mps: float = maxf(float(context.get("speed_mps", 0.0)), 0.0)
	var velocity_valid: bool = bool(context.get("velocity_valid", true))
	var field_state: String = str(context.get("field_state", "OFF"))
	var in_contact: bool = bool(context.get("in_contact", false))

	var remaining_alt: float = maxf(effective_min_alt - altitude_m, 0.0)
	var progress: float = 1.0 if effective_min_alt <= 0.001 else clampf(altitude_m / effective_min_alt, 0.0, 1.0)

	var eligible: bool = false
	var reason_code: String = REASON_READY
	var reason_text: String = "JUMP READY"

	if not jump_allowed:
		reason_code = REASON_ENV_DISALLOWED
		reason_text = "JUMP UNAVAILABLE: NO ACTIVE ROUTE IN ENVIRONMENT"
	elif require_online and field_state != "ONLINE":
		reason_code = REASON_SYSTEMS_OFFLINE
		reason_text = "JUMP UNAVAILABLE: REPULSOR FIELD %s (PRESS F)" % field_state
	elif disallow_contact and in_contact:
		reason_code = REASON_SHIP_IN_CONTACT
		reason_text = "JUMP UNAVAILABLE: LANDED / SURFACE CONTACT"
	elif effective_min_alt > 0.0 and not altitude_valid:
		reason_code = REASON_SENSOR_ALTITUDE_INVALID
		reason_text = "JUMP UNAVAILABLE: ALTITUDE SENSOR INVALID"
	elif effective_min_alt > 0.0 and altitude_m < effective_min_alt:
		reason_code = REASON_BELOW_MIN_ALTITUDE
		reason_text = "BELOW JUMP ENVELOPE: %.0f / %.0f m (%d%%)" % [maxf(altitude_m, 0.0), effective_min_alt, int(round(progress * 100.0))]
	elif exclusion_radius_m > 0.0 and radial_distance_m < exclusion_radius_m:
		reason_code = REASON_INSIDE_EXCLUSION_ZONE
		reason_text = "INSIDE EXCLUSION ZONE: %.0f / %.0f m" % [radial_distance_m, exclusion_radius_m]
	elif max_speed_mps > 0.0 and not velocity_valid:
		reason_code = REASON_SPEED_ABOVE_LIMIT
		reason_text = "JUMP UNAVAILABLE: VELOCITY SENSOR INVALID"
	elif max_speed_mps > 0.0 and speed_mps > max_speed_mps:
		reason_code = REASON_SPEED_ABOVE_LIMIT
		reason_text = "REDUCE SPEED FOR JUMP: %.0f / %.0f m/s" % [speed_mps, max_speed_mps]
	else:
		eligible = true

	return {
		"jump_eligible": eligible,
		"jump_reason_code": reason_code,
		"jump_reason_text": reason_text,
		"jump_environment_id": env_id,
		"jump_environment_type": env_type,
		"jump_environment_label": env_label,
		"jump_altitude_m": altitude_m,
		"jump_min_altitude_m": effective_min_alt,
		"jump_remaining_altitude_m": remaining_alt,
		"jump_altitude_progress": progress,
		"jump_exclusion_radius_m": exclusion_radius_m,
		"jump_radial_distance_m": radial_distance_m,
		"jump_max_speed_mps": max_speed_mps,
		"jump_in_contact": in_contact,
		"jump_speed_mps": speed_mps,
	}

static func build_context_from_nodes(
		ship: RigidBody3D,
		sensor_snapshot: Dictionary,
		env_manager: Node,
		field_state: String,
		exclusion_origin_world: Vector3 = Vector3.ZERO) -> Dictionary:
	var altitude_m: float = float(sensor_snapshot.get("instrument_altitude_m", ship.global_position.y if is_instance_valid(ship) else 0.0))
	var altitude_valid: bool = bool(sensor_snapshot.get("instrument_altitude_valid", true))
	var velocity_valid: bool = bool(sensor_snapshot.get("instrument_velocity_valid", true))
	var raw_vel: Variant = sensor_snapshot.get("instrument_inertial_velocity_world", ship.linear_velocity if is_instance_valid(ship) else Vector3.ZERO)
	var speed_mps: float = Vector3(raw_vel).length()
	var radial_distance_m: float = ship.global_position.distance_to(exclusion_origin_world) if is_instance_valid(ship) else 0.0

	if not is_instance_valid(env_manager):
		return {
			"environment_id": "test_range",
			"environment_type": str(sensor_snapshot.get("instrument_environment_type", "PLANET_SURFACE")),
			"environment_label": "Test Range (No Route)",
			"jump_allowed": false,
			"min_altitude_m": 0.0,
			"exclusion_radius_m": 0.0,
			"max_speed_mps": 0.0,
			"require_systems_online": true,
			"disallow_contact": true,
			"altitude_m": altitude_m,
			"altitude_valid": altitude_valid,
			"radial_distance_m": radial_distance_m,
			"speed_mps": speed_mps,
			"velocity_valid": velocity_valid,
			"field_state": field_state,
			"in_contact": false,
		}

	var env_id: String = str(env_manager.call("get_environment_id")) if env_manager.has_method("get_environment_id") else "unknown"
	var env_type: String = str(env_manager.call("get_environment_type_name")) if env_manager.has_method("get_environment_type_name") else "PLANET_SURFACE"
	var env_label: String = str(env_manager.call("get_display_label")) if env_manager.has_method("get_display_label") else env_id
	var cfg: Dictionary = env_manager.call("get_jump_envelope_config") if env_manager.has_method("get_jump_envelope_config") else {}

	var in_contact: bool = false
	if is_instance_valid(ship):
		var active_contacts: bool = ship.contact_monitor and ship.get_contact_count() > 0
		var sleeping_on_surface: bool = env_type == "PLANET_SURFACE" and ship.sleeping and altitude_m <= 2.0
		in_contact = active_contacts or sleeping_on_surface

	return {
		"environment_id": env_id,
		"environment_type": env_type,
		"environment_label": env_label,
		"jump_allowed": bool(cfg.get("jump_allowed", true)),
		"min_altitude_m": float(cfg.get("min_altitude_m", 0.0)),
		"exclusion_radius_m": float(cfg.get("exclusion_radius_m", 0.0)),
		"max_speed_mps": float(cfg.get("max_speed_mps", 0.0)),
		"require_systems_online": bool(cfg.get("require_systems_online", true)),
		"disallow_contact": bool(cfg.get("disallow_contact", true)),
		"altitude_m": altitude_m,
		"altitude_valid": altitude_valid,
		"radial_distance_m": radial_distance_m,
		"speed_mps": speed_mps,
		"velocity_valid": velocity_valid,
		"field_state": field_state,
		"in_contact": in_contact,
	}
