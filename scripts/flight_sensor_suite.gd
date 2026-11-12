extends Node
class_name FlightSensorSuite

## Ship-owned flight instrument data concentrator.
##
## This node is the only interface between physical ship state and the normal
## cockpit HUD. It currently reports ideal instruments, but each channel has an
## independent validity flag so gyro bias, compass error, latency and failures
## can later be introduced here without changing the HUD renderer.

const CHANNEL_ATTITUDE: StringName = &"attitude"
const CHANNEL_HEADING: StringName = &"heading"
const CHANNEL_VELOCITY: StringName = &"velocity"
const CHANNEL_ALTITUDE: StringName = &"altitude"

@export_category("Environment")
@export var planetary_reference_frame_path: NodePath = NodePath("../../PlanetaryReferenceFrame")

@export_category("Navigation reference")
## Legacy world-space north fallback used only when no planetary frame exists.
@export var reference_north_world: Vector3 = Vector3(0.0, 0.0, -1.0)

var _ship: RigidBody3D
var _atmosphere: Node
var _gravity_body: Node
var _planetary_reference_frame: PlanetaryReferenceFrame

var _channel_available: Dictionary = {
	CHANNEL_ATTITUDE: true,
	CHANNEL_HEADING: true,
	CHANNEL_VELOCITY: true,
	CHANNEL_ALTITUDE: true,
}


func _enter_tree() -> void:
	_ship = get_parent() as RigidBody3D
	_atmosphere = get_node_or_null("../AtmosphericFlightModel")
	_gravity_body = get_node_or_null("../PlanetaryGravityBody")
	_planetary_reference_frame = get_node_or_null(planetary_reference_frame_path) as PlanetaryReferenceFrame


func _ready() -> void:
	if _ship == null:
		push_error("FlightSensorSuite must be a direct child of the ship RigidBody3D.")
		set_process(false)


## Allows later damage/sensor-failure systems to invalidate individual channels.
## The last measured value remains available for diagnostics, but consumers must
## respect its corresponding *_valid flag.
func set_channel_available(channel: StringName, available: bool) -> void:
	if _channel_available.has(channel):
		_channel_available[channel] = available


func is_channel_available(channel: StringName) -> bool:
	return bool(_channel_available.get(channel, false))


## Converts physical state and environment measurements into instrument values.
## No HUD code should read RigidBody3D or flight-model state directly.
func get_instrument_snapshot() -> Dictionary:
	if not is_instance_valid(_ship):
		return {}

	var ship_basis: Basis = _ship.global_basis.orthonormalized()
	var ship_forward: Vector3 = (-ship_basis.z).normalized()
	var ship_velocity: Vector3 = _ship.linear_velocity
	var local_up: Vector3 = Vector3.UP
	var north_reference: Vector3 = reference_north_world
	var altitude_m: float = _ship.global_position.y
	var gravity_world: Vector3 = _ship.get_gravity()
	var frame_available: bool = false

	if is_instance_valid(_planetary_reference_frame):
		var local_frame: Dictionary = _planetary_reference_frame.get_local_frame(_ship.global_position)
		local_up = local_frame.get("up_world", Vector3.UP)
		north_reference = local_frame.get("north_world", reference_north_world)
		altitude_m = float(local_frame.get("altitude_m", altitude_m))
		gravity_world = local_frame.get("gravity_world", gravity_world)
		frame_available = true
	elif _gravity_body != null and _gravity_body.has_method("get_local_gravity_vector_world"):
		gravity_world = _gravity_body.call("get_local_gravity_vector_world")

	var atmosphere_density: float = 0.0
	var atmosphere_relative_velocity: Vector3 = ship_velocity
	var atmosphere_airspeed: float = ship_velocity.length()
	var atmosphere_available: bool = false
	if is_instance_valid(_atmosphere) and _atmosphere.has_method("get_telemetry"):
		var atmosphere_data: Dictionary = _atmosphere.call("get_telemetry")
		if not frame_available:
			local_up = atmosphere_data.get("atmosphere_up_world", local_up)
			if local_up.length_squared() > 0.000001:
				local_up = local_up.normalized()
			else:
				local_up = Vector3.UP
			altitude_m = float(atmosphere_data.get("atmosphere_altitude_m", _ship.global_position.dot(local_up)))
			north_reference = atmosphere_data.get("atmosphere_north_world", north_reference)
		atmosphere_density = float(atmosphere_data.get("atmosphere_density_kg_m3", 0.0))
		atmosphere_relative_velocity = atmosphere_data.get("atmosphere_relative_velocity_world", ship_velocity)
		atmosphere_airspeed = float(atmosphere_data.get("atmosphere_airspeed_mps", atmosphere_relative_velocity.length()))
		atmosphere_available = bool(atmosphere_data.get("atmosphere_enabled", false))
	elif gravity_world.length_squared() > 0.000001:
		local_up = -gravity_world.normalized()
		altitude_m = _ship.global_position.dot(local_up)

	if local_up.length_squared() > 0.000001:
		local_up = local_up.normalized()
	else:
		local_up = Vector3.UP

	var attitude: Dictionary = calculate_attitude_angles(ship_basis, local_up)
	var heading: Dictionary = calculate_heading_degrees(
		ship_forward,
		local_up,
		north_reference
	)

	var in_atmosphere: bool = atmosphere_available and atmosphere_density > 0.00001
	var measured_flight_velocity: Vector3 = atmosphere_relative_velocity if in_atmosphere else ship_velocity
	var measured_speed: float = atmosphere_airspeed if in_atmosphere else ship_velocity.length()
	var channel_attitude: bool = is_channel_available(CHANNEL_ATTITUDE)
	var channel_heading: bool = is_channel_available(CHANNEL_HEADING) and bool(heading.get("valid", false))
	var channel_velocity: bool = is_channel_available(CHANNEL_VELOCITY)
	var channel_altitude: bool = is_channel_available(CHANNEL_ALTITUDE)

	return {
		"instrument_attitude_basis_world": ship_basis,
		"instrument_pitch_degrees": float(attitude.get("pitch_degrees", 0.0)),
		"instrument_bank_degrees": float(attitude.get("bank_degrees", 0.0)),
		"instrument_heading_degrees": float(heading.get("heading_degrees", 0.0)),
		"instrument_heading_valid": channel_heading,
		"instrument_local_up_world": local_up,
		"instrument_north_reference_world": north_reference,
		"instrument_gravity_world": gravity_world,
		"instrument_north_world": heading.get("north_world", Vector3.ZERO),
		"instrument_air_relative_velocity_world": measured_flight_velocity,
		"instrument_inertial_velocity_world": ship_velocity,
		"instrument_speed_mps": measured_speed,
		"instrument_speed_label": "AIRSPEED" if in_atmosphere else "SPEED",
		"instrument_vertical_speed_mps": ship_velocity.dot(local_up),
		"instrument_altitude_m": altitude_m,
		"instrument_atmosphere_density_kg_m3": atmosphere_density,
		"instrument_attitude_valid": channel_attitude,
		"instrument_velocity_valid": channel_velocity,
		"instrument_altitude_valid": channel_altitude,
		"instrument_channel_status": {
			"ATTITUDE": "NOMINAL" if channel_attitude else "FAIL",
			"HEADING": "NOMINAL" if channel_heading else "FAIL",
			"VELOCITY": "NOMINAL" if channel_velocity else "FAIL",
			"ALTITUDE": "NOMINAL" if channel_altitude else "FAIL",
		},
	}


## Heading is computed in the local horizontal plane, so pitch angle cannot
## contaminate the compass reading. Heading is clockwise from north: N=000,
## E=090, S=180, W=270.
static func calculate_heading_degrees(
		forward_world: Vector3,
		local_up_world: Vector3,
		north_reference_world: Vector3
) -> Dictionary:
	var result: Dictionary = {
		"valid": false,
		"heading_degrees": 0.0,
		"north_world": Vector3.ZERO,
		"east_world": Vector3.ZERO,
	}
	if local_up_world.length_squared() <= 0.000001 or forward_world.length_squared() <= 0.000001:
		return result

	var up: Vector3 = local_up_world.normalized()
	var north: Vector3 = north_reference_world - up * north_reference_world.dot(up)
	if north.length_squared() <= 0.000001:
		# Fallback avoids a singular compass exactly at a pole. A planetary
		# EnvironmentProfile should replace this with its local north vector.
		var fallback_axis: Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		north = fallback_axis - up * fallback_axis.dot(up)
	if north.length_squared() <= 0.000001:
		return result
	north = north.normalized()
	var east: Vector3 = north.cross(up).normalized()
	var horizontal_forward: Vector3 = forward_world - up * forward_world.dot(up)
	if horizontal_forward.length_squared() <= 0.000001:
		return result
	horizontal_forward = horizontal_forward.normalized()
	var heading_degrees: float = fposmod(
		rad_to_deg(atan2(horizontal_forward.dot(east), horizontal_forward.dot(north))),
		360.0
	)
	result["valid"] = true
	result["heading_degrees"] = heading_degrees
	result["north_world"] = north
	result["east_world"] = east
	return result


static func calculate_attitude_angles(ship_basis: Basis, local_up_world: Vector3) -> Dictionary:
	var up: Vector3 = local_up_world.normalized() if local_up_world.length_squared() > 0.000001 else Vector3.UP
	var basis: Basis = ship_basis.orthonormalized()
	var forward: Vector3 = (-basis.z).normalized()
	var pitch: float = rad_to_deg(asin(clampf(forward.dot(up), -1.0, 1.0)))

	# Construct the zero-bank local vertical in the plane perpendicular to the
	# ship's forward axis. This remains correct when pitch and bank are combined.
	var level_up: Vector3 = up - forward * up.dot(forward)
	var bank: float = 0.0
	if level_up.length_squared() > 0.000001:
		level_up = level_up.normalized()
		bank = rad_to_deg(atan2(-basis.x.dot(level_up), basis.y.dot(level_up)))
	return {
		"pitch_degrees": pitch,
		"bank_degrees": bank,
	}
