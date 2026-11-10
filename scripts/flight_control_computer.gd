extends Node
class_name FlightControlComputer

## Converts pilot rotation-rate requests into bounded vane-control commands.
## This is a proportional angular-rate controller, not an attitude-hold system:
## zero input requests zero angular rate, but never requests a return to level.
## The controller has no integral term, so it cannot accumulate windup while
## the field is offline or the available vane authority is saturated.

@export_category("Requested rotational rates")
@export_range(5.0, 90.0, 1.0) var maximum_pitch_rate_degrees_per_second: float = 32.0
@export_range(5.0, 90.0, 1.0) var maximum_roll_rate_degrees_per_second: float = 32.0
@export_range(5.0, 90.0, 1.0) var maximum_yaw_rate_degrees_per_second: float = 24.0

@export_category("FCC response and authority")
## Proportional response to normalized angular-rate error. Higher values
## accelerate the response but reach the output limit sooner.
@export_range(0.1, 4.0, 0.05) var rate_response_gain: float = 0.8
## Hard limit on each FCC vane command. The initial 0.8 cap preserves some
## response margin so normal assistance cannot fully conceal vane faults.
## Vane condition and power impose additional physical limits after this cap.
@export_range(0.1, 1.0, 0.05) var maximum_control_output: float = 0.8

## Input conditioning. Fixed initial tuning. These become FCC-display settings later; they are not
## exposed through a separate options menu.
const INPUT_DEADZONE: float = 0.01
## Blend from linear response toward a cubic response. 0.18 = 18% curve.
const INPUT_CURVATURE: float = 0.18

var assistance_enabled: bool = true


func set_assistance_enabled(enabled: bool) -> void:
	assistance_enabled = enabled


func calculate_control_outputs(
		pilot_pitch_request: float,
		pilot_roll_request: float,
		pilot_yaw_request: float,
		angular_velocity_world: Vector3,
		ship_basis: Basis,
		control_available: bool
) -> Dictionary:
	var pitch_request: float = _condition_input(pilot_pitch_request)
	var roll_request: float = _condition_input(pilot_roll_request)
	var yaw_request: float = _condition_input(pilot_yaw_request)

	# The rigid body's angular velocity is expressed in world coordinates.
	# Convert it to ship-local axes so pitch/roll/yaw retain their meaning when
	# the ship is rotated in the world.
	var safe_basis: Basis = ship_basis.orthonormalized()
	if absf(safe_basis.determinant()) <= 0.000001:
		safe_basis = Basis.IDENTITY
	var actual_rate_local: Vector3 = safe_basis.inverse() * angular_velocity_world

	# Measured angular-rate layout follows the ship's local axes:
	# X = pitch, Y = yaw, Z = roll. The existing 2F vane geometry produces
	# positive pilot yaw/roll with negative local Y/Z angular velocity, so the
	# yaw and roll rate setpoints use the inverse sign.
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

	if control_available:
		if assistance_enabled:
			raw_output_by_axis = Vector3(
				normalized_rate_error.x,
				-normalized_rate_error.y,
				-normalized_rate_error.z
			) * rate_response_gain
			var output_limit: float = clampf(maximum_control_output, 0.0, 1.0)
			output_by_axis = Vector3(
				clampf(raw_output_by_axis.x, -output_limit, output_limit),
				clampf(raw_output_by_axis.y, -output_limit, output_limit),
				clampf(raw_output_by_axis.z, -output_limit, output_limit)
			)
			pitch_saturated = absf(raw_output_by_axis.x) > output_limit + 0.0001
			yaw_saturated = absf(raw_output_by_axis.y) > output_limit + 0.0001
			roll_saturated = absf(raw_output_by_axis.z) > output_limit + 0.0001
		else:
			# Assistance OFF preserves the Phase 2F direct vane-control mapping.
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
		"fcc_pitch_output": output_by_axis.x,
		"fcc_yaw_output": output_by_axis.y,
		"fcc_roll_output": output_by_axis.z,
		"fcc_pitch_saturated": pitch_saturated,
		"fcc_roll_saturated": roll_saturated,
		"fcc_yaw_saturated": yaw_saturated,
		"fcc_any_axis_saturated": pitch_saturated or roll_saturated or yaw_saturated,
		"fcc_rate_response_gain": rate_response_gain,
		"fcc_maximum_control_output": maximum_control_output,
	}


## Symmetric deadzone remapping followed by a smooth linear-to-cubic blend.
## The curve preserves both endpoints and sign, while reducing center sensitivity.
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
