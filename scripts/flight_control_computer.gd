extends Node
class_name FlightControlComputer

## Converts pilot rotation-rate requests into bounded vane-control commands,
## and in LOCAL_SPACE provides AOA-bounded vector-following speed control and
## inertial retrograde braking when FCC assistance is active.

@export_category("Requested rotational rates")
@export_range(5.0, 90.0, 1.0) var maximum_pitch_rate_degrees_per_second: float = 32.0
@export_range(5.0, 90.0, 1.0) var maximum_roll_rate_degrees_per_second: float = 32.0
@export_range(5.0, 90.0, 1.0) var maximum_yaw_rate_degrees_per_second: float = 24.0

@export_category("FCC response and authority")
@export_range(0.1, 4.0, 0.05) var rate_response_gain: float = 0.8
@export_range(0.0, 0.5, 0.01) var rate_integral_gain: float = 0.12
@export_range(0.0, 0.4, 0.01) var maximum_integral_trim_output: float = 0.25
@export_range(0.1, 1.0, 0.05) var maximum_control_output: float = 0.8

@export_category("Space assist mode")
@export_range(20.0, 300.0, 5.0) var space_max_speed_mps: float = 120.0
@export_range(5.0, 45.0, 1.0) var space_aoa_limit_degrees: float = 18.0
@export_range(0.3, 6.0, 0.1) var space_speed_response_time_s: float = 1.6
@export_range(0.25, 4.0, 0.05) var space_lateral_damping_time_s: float = 0.85
@export_range(0.25, 4.0, 0.05) var space_brake_response_time_s: float = 0.75
@export_range(0.25, 2.0, 0.05) var space_max_lateral_twr: float = 0.85

const INPUT_DEADZONE: float = 0.01
const INPUT_CURVATURE: float = 0.18
const VANE_REDISTRIBUTION_FRACTION: float = 0.50
const MAXIMUM_VANE_OUTPUT_MULTIPLIER: float = 1.20

var assistance_enabled: bool = true
var _integral_trim_output_by_axis: Vector3 = Vector3.ZERO


func apply_ship_definition(definition: ShipDefinition) -> void:
	if definition == null or definition.handling.is_empty():
		return
	var h: Dictionary = definition.handling
	maximum_pitch_rate_degrees_per_second = maxf(float(h.get("maximum_pitch_rate_degrees_per_second", maximum_pitch_rate_degrees_per_second)), 1.0)
	maximum_roll_rate_degrees_per_second = maxf(float(h.get("maximum_roll_rate_degrees_per_second", maximum_roll_rate_degrees_per_second)), 1.0)
	maximum_yaw_rate_degrees_per_second = maxf(float(h.get("maximum_yaw_rate_degrees_per_second", maximum_yaw_rate_degrees_per_second)), 1.0)


func set_assistance_enabled(enabled: bool) -> void:
	assistance_enabled = enabled
	if not assistance_enabled:
		reset_integral_trim()


func reset_integral_trim() -> void:
	_integral_trim_output_by_axis = Vector3.ZERO


func calculate_control_outputs(
		pilot_pitch_request: float,
		pilot_roll_request: float,
		pilot_yaw_request: float,
		angular_velocity_world: Vector3,
		ship_basis: Basis,
		control_available: bool,
		delta_seconds: float = 0.0
) -> Dictionary:
	var pitch_request: float = _condition_input(pilot_pitch_request)
	var roll_request: float = _condition_input(pilot_roll_request)
	var yaw_request: float = _condition_input(pilot_yaw_request)

	var safe_basis: Basis = ship_basis.orthonormalized()
	if absf(safe_basis.determinant()) <= 0.000001:
		safe_basis = Basis.IDENTITY
	var actual_rate_local: Vector3 = safe_basis.inverse() * angular_velocity_world

	var maximum_rate_local := Vector3(
		deg_to_rad(maxf(maximum_pitch_rate_degrees_per_second, 0.1)),
		deg_to_rad(maxf(maximum_yaw_rate_degrees_per_second, 0.1)),
		deg_to_rad(maxf(maximum_roll_rate_degrees_per_second, 0.1))
	)
	var desired_rate_local := Vector3(
		pitch_request * maximum_rate_local.x,
		-yaw_request * maximum_rate_local.y,
		-roll_request * maximum_rate_local.z
	)
	var rate_error_local: Vector3 = desired_rate_local - actual_rate_local
	var normalized_rate_error := Vector3(
		rate_error_local.x / maximum_rate_local.x,
		rate_error_local.y / maximum_rate_local.y,
		rate_error_local.z / maximum_rate_local.z
	)

	var raw_output_by_axis: Vector3 = Vector3.ZERO
	var output_by_axis: Vector3 = Vector3.ZERO
	var pitch_saturated: bool = false
	var roll_saturated: bool = false
	var yaw_saturated: bool = false

	if not control_available or not assistance_enabled:
		reset_integral_trim()

	if control_available:
		if assistance_enabled:
			var output_rate_error := Vector3(
				normalized_rate_error.x,
				-normalized_rate_error.y,
				-normalized_rate_error.z
			)
			var proportional_output: Vector3 = output_rate_error * rate_response_gain
			var output_limit: float = clampf(maximum_control_output, 0.0, 1.0)
			var integration_delta: float = maxf(delta_seconds, 0.0)

			if integration_delta > 0.0 and rate_integral_gain > 0.0:
				_integral_trim_output_by_axis.x = _integrate_axis(
					_integral_trim_output_by_axis.x, output_rate_error.x,
					proportional_output.x, integration_delta, output_limit
				)
				_integral_trim_output_by_axis.y = _integrate_axis(
					_integral_trim_output_by_axis.y, output_rate_error.y,
					proportional_output.y, integration_delta, output_limit
				)
				_integral_trim_output_by_axis.z = _integrate_axis(
					_integral_trim_output_by_axis.z, output_rate_error.z,
					proportional_output.z, integration_delta, output_limit
				)

			raw_output_by_axis = proportional_output + _integral_trim_output_by_axis
			output_by_axis = Vector3(
				clampf(raw_output_by_axis.x, -output_limit, output_limit),
				clampf(raw_output_by_axis.y, -output_limit, output_limit),
				clampf(raw_output_by_axis.z, -output_limit, output_limit)
			)
			pitch_saturated = absf(raw_output_by_axis.x) > output_limit + 0.0001
			yaw_saturated = absf(raw_output_by_axis.y) > output_limit + 0.0001
			roll_saturated = absf(raw_output_by_axis.z) > output_limit + 0.0001
		else:
			raw_output_by_axis = Vector3(pitch_request, yaw_request, roll_request)
			output_by_axis = raw_output_by_axis

	return {
		"fcc_assistance_enabled": assistance_enabled,
		"fcc_input_deadzone": INPUT_DEADZONE,
		"fcc_input_curvature": INPUT_CURVATURE,
		"fcc_pitch_input_raw": clampf(pilot_pitch_request, -1.0, 1.0),
		"fcc_roll_input_raw": clampf(pilot_roll_request, -1.0, 1.0),
		"fcc_yaw_input_raw": clampf(pilot_yaw_request, -1.0, 1.0),
		"fcc_pitch_input_conditioned": pitch_request,
		"fcc_roll_input_conditioned": roll_request,
		"fcc_yaw_input_conditioned": yaw_request,
		"fcc_control_available": control_available,
		"fcc_desired_rate_local_rad_s": desired_rate_local,
		"fcc_actual_rate_local_rad_s": actual_rate_local,
		"fcc_rate_error_local_rad_s": rate_error_local,
		"fcc_raw_control_output_by_axis": raw_output_by_axis,
		"fcc_control_output_by_axis": output_by_axis,
		"fcc_integral_trim_output_by_axis": _integral_trim_output_by_axis,
		"fcc_trim_active": _integral_trim_output_by_axis.length() > 0.01,
		"fcc_pitch_output": output_by_axis.x,
		"fcc_yaw_output": output_by_axis.y,
		"fcc_roll_output": output_by_axis.z,
		"fcc_pitch_saturated": pitch_saturated,
		"fcc_roll_saturated": roll_saturated,
		"fcc_yaw_saturated": yaw_saturated,
		"fcc_any_axis_saturated": pitch_saturated or roll_saturated or yaw_saturated,
		"fcc_rate_response_gain": rate_response_gain,
		"fcc_rate_integral_gain": rate_integral_gain,
		"fcc_maximum_integral_trim_output": maximum_integral_trim_output,
		"fcc_maximum_control_output": maximum_control_output,
		"fcc_vane_redistribution_fraction": VANE_REDISTRIBUTION_FRACTION if assistance_enabled else 0.0,
		"fcc_maximum_vane_output_multiplier": MAXIMUM_VANE_OUTPUT_MULTIPLIER,
	}


func calculate_space_assist_command(
		velocity_world: Vector3,
		ship_basis: Basis,
		ship_mass_kg: float,
		rated_gross_mass_kg: float,
		reference_gravity_mps2: float,
		main_rear_effective_twr: float,
		space_mode_active: bool,
		throttle_command: float,
		throttle_engaged: bool,
		brake_requested: bool,
		control_available: bool
) -> Dictionary:
	var safe_basis: Basis = ship_basis.orthonormalized()
	if absf(safe_basis.determinant()) <= 0.000001:
		safe_basis = Basis.IDENTITY
	var fwd: Vector3 = (-safe_basis.z).normalized()
	var current_speed: float = velocity_world.length()
	var v_fwd: float = velocity_world.dot(fwd)
	var v_perp: Vector3 = velocity_world - fwd * v_fwd
	var perp_speed: float = v_perp.length()
	var slip_angle_deg: float = rad_to_deg(atan2(perp_speed, maxf(absf(v_fwd), 0.1))) if current_speed > 0.15 else 0.0

	var result: Dictionary = {
		"fcc_space_mode_active": space_mode_active,
		"fcc_space_mode_engaged": false,
		"fcc_space_assist_active": false,
		"fcc_space_brake_active": brake_requested and space_mode_active,
		"fcc_space_max_speed_mps": space_max_speed_mps,
		"fcc_space_target_speed_mps": 0.0,
		"fcc_space_current_speed_mps": current_speed,
		"fcc_space_forward_speed_mps": v_fwd,
		"fcc_space_lateral_slip_mps": perp_speed,
		"fcc_space_slip_angle_deg": slip_angle_deg,
		"fcc_space_aoa_limit_deg": space_aoa_limit_degrees,
		"fcc_space_assist_force_world": Vector3.ZERO,
		"fcc_mode_label": "ATMO RATE ASSIST" if assistance_enabled else "DIRECT VANES",
	}

	if not space_mode_active:
		return result

	if not assistance_enabled:
		result["fcc_mode_label"] = "SPACE DRIFT // DIRECT"
		return result

	if not control_available:
		result["fcc_mode_label"] = "SPACE OFFLINE"
		return result

	var engaged: bool = throttle_engaged or brake_requested or throttle_command > 0.005
	if not engaged:
		result["fcc_mode_label"] = "SPACE STANDBY"
		return result

	var target_speed: float = 0.0 if brake_requested else clampf(throttle_command, 0.0, 1.0) * space_max_speed_mps
	var safe_mass: float = maxf(ship_mass_kg, 1.0)
	var ref_force_per_twr: float = maxf(rated_gross_mass_kg, safe_mass) * maxf(reference_gravity_mps2, 1.0)
	var max_fwd_force: float = ref_force_per_twr * maxf(main_rear_effective_twr, 0.5)
	var max_lat_force: float = ref_force_per_twr * maxf(space_max_lateral_twr, 0.25)
	var max_fwd_accel: float = max_fwd_force / safe_mass
	var max_lat_accel: float = max_lat_force / safe_mass

	var desired_force: Vector3 = Vector3.ZERO
	var braking_mode: bool = brake_requested or target_speed <= 0.1
	if braking_mode:
		if current_speed > 0.06:
			var a_req: Vector3 = -velocity_world / maxf(space_brake_response_time_s, 0.15)
			var a_req_fwd: float = clampf(a_req.dot(fwd), -max_fwd_accel, max_fwd_accel)
			var a_req_perp: Vector3 = a_req - fwd * a_req.dot(fwd)
			var a_perp_len: float = a_req_perp.length()
			if a_perp_len > max_lat_accel:
				a_req_perp = a_req_perp * (max_lat_accel / a_perp_len)
			desired_force = (fwd * a_req_fwd + a_req_perp) * safe_mass
		result["fcc_mode_label"] = "SPACE BRAKE"
		result["fcc_space_brake_active"] = true
	else:
		var a_fwd: float = clampf((target_speed - v_fwd) / maxf(space_speed_response_time_s, 0.2), -max_fwd_accel * 0.85, max_fwd_accel)
		var a_lat: Vector3 = Vector3.ZERO
		if perp_speed > 0.04:
			var aoa_excess: float = maxf(slip_angle_deg - space_aoa_limit_degrees, 0.0)
			var aoa_boost: float = 1.0 + clampf(aoa_excess / 45.0, 0.0, 0.65)
			var eff_tau: float = maxf(space_lateral_damping_time_s / aoa_boost, 0.15)
			var lat_accel_mag: float = clampf(perp_speed / eff_tau, 0.0, max_lat_accel * aoa_boost)
			a_lat = (-v_perp / perp_speed) * lat_accel_mag
		desired_force = (fwd * a_fwd + a_lat) * safe_mass
		result["fcc_mode_label"] = "SPACE VECTOR"

	result["fcc_space_mode_engaged"] = true
	result["fcc_space_assist_active"] = true
	result["fcc_space_target_speed_mps"] = target_speed
	result["fcc_space_assist_force_world"] = desired_force
	return result


func _integrate_axis(
		current_integral: float,
		error_for_output: float,
		proportional_output: float,
		delta_seconds: float,
		output_limit: float
) -> float:
	var integral_limit: float = clampf(maximum_integral_trim_output, 0.0, 0.4)
	var candidate: float = clampf(
		current_integral + error_for_output * rate_integral_gain * delta_seconds,
		-integral_limit,
		integral_limit
	)
	var candidate_raw_output: float = proportional_output + candidate
	if absf(candidate_raw_output) <= output_limit:
		return candidate
	if candidate_raw_output > output_limit and error_for_output < 0.0:
		return candidate
	if candidate_raw_output < -output_limit and error_for_output > 0.0:
		return candidate
	return current_integral


static func shape_pilot_input(value: float, deadzone: float = INPUT_DEADZONE, curvature: float = INPUT_CURVATURE) -> float:
	var safe_value: float = clampf(value, -1.0, 1.0)
	var safe_deadzone: float = clampf(deadzone, 0.0, 0.95)
	var magnitude: float = absf(safe_value)
	if magnitude <= safe_deadzone:
		return 0.0

	var normalized_magnitude: float = (magnitude - safe_deadzone) / (1.0 - safe_deadzone)
	var cubic_magnitude: float = normalized_magnitude * normalized_magnitude * normalized_magnitude
	var curve_blend: float = clampf(curvature, 0.0, 1.0)
	var curved_magnitude: float = lerpf(normalized_magnitude, cubic_magnitude, curve_blend)
	return signf(safe_value) * curved_magnitude


func _condition_input(value: float) -> float:
	return shape_pilot_input(value)
