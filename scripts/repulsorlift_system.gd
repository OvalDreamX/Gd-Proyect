extends Node
class_name RepulsorliftSystem

## Converts ship-relative field commands into one central translation force
## plus front/rear, left/right and side-vane force pairs. Each secondary pair
## is applied at the weighted centroid of its participating vanes, allowing
## Godot's RigidBody3D solver to produce the corresponding rotation naturally.

@export_category("Main field vector")
## TWR is converted to force using this reference acceleration. The ship keeps
## propulsion authority in low/zero gravity; gravity is used only for telemetry
## and the local hover-threshold calculation.
@export_range(1.0, 20.0, 0.1) var reference_gravity_mps2: float = 9.81

@export_category("Maneuver authority")
## Fraction of each bottom vane's rated authority reserved for each commanded
## pitch/roll vector pair. This is a PLACEHOLDER for first control-feel tuning.
@export_range(0.0, 0.25, 0.005) var maneuver_authority_fraction: float = 0.05
## Maneuvering keeps a baseline while the field is online. Unused main-vector
## allocation can add up to this modest reserve at zero main-vector output.
@export_range(0.0, 0.35, 0.01) var maneuver_boost_at_zero_main_power: float = 0.20

@export_category("Debug vectors")
@export_range(1.0, 12.0, 0.5) var debug_arrow_length_per_twr_m: float = 4.0

const BOTTOM_FRONT_GROUP: StringName = &"bottom_front"
const BOTTOM_REAR_GROUP: StringName = &"bottom_rear"
const MAIN_REAR_GROUP: StringName = &"main_rear"
const SIDE_LEFT_GROUP: StringName = &"side_left"
const SIDE_RIGHT_GROUP: StringName = &"side_right"

const FRONT_VANE_IDS: Array[StringName] = [
	&"bottom_front_left", &"bottom_front_right"
]
const REAR_VANE_IDS: Array[StringName] = [
	&"bottom_rear_left", &"bottom_rear_right"
]
const LEFT_VANE_IDS: Array[StringName] = [
	&"bottom_front_left", &"bottom_rear_left"
]
const RIGHT_VANE_IDS: Array[StringName] = [
	&"bottom_front_right", &"bottom_rear_right"
]

const MINIMUM_MASS_KG: float = 0.0001
const MINIMUM_FORCE_SQUARED: float = 0.000001
const MINIMUM_TORQUE_SQUARED: float = 0.000001
const DEBUG_REFRESH_EVERY_CALLS: int = 3

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable
@onready var _vane_controller: VaneController = get_node("../VaneController") as VaneController
@onready var _force_debug: ForceVectorDebug = get_node_or_null("../ForceVectorDebug") as ForceVectorDebug

var _debug_visualization_enabled: bool = false
var _debug_refresh_counter: int = 0
var _last_field_online: bool = false
var _last_power_output: float = 0.0
var _last_maneuver_power_multiplier: float = 0.0
var _last_vane_redistribution_fraction: float = 0.0
var _last_maximum_vane_output_multiplier: float = 1.2
var _last_vector_angle_degrees: float = 90.0
var _last_pitch_command: float = 0.0
var _last_roll_command: float = 0.0
var _last_yaw_command: float = 0.0
var _last_main_force: Vector3 = Vector3.ZERO
var _last_total_force: Vector3 = Vector3.ZERO
var _last_total_torque: Vector3 = Vector3.ZERO
var _last_main_direction_world: Vector3 = Vector3.UP
var _last_gravity_magnitude: float = 0.0
var _last_vertical_twr: float = 0.0
var _last_maximum_lift_twr: float = 0.0
var _last_force_vectors: Array[Dictionary] = []
var _last_vane_contributions: Array[Dictionary] = []


func _ready() -> void:
	if _ship == null or _vane_controller == null:
		push_error("RepulsorliftSystem requires ShipInteractable and VaneController siblings.")
		set_process(false)
		set_physics_process(false)
		return
	if _force_debug == null:
		push_warning("ForceVectorDebug node is missing; F3 force arrows will be unavailable.")

	_last_maximum_lift_twr = _get_bottom_nominal_authority_twr()
	if not _vane_controller.is_configuration_valid():
		push_error("Vane configuration is invalid: %s" % "; ".join(_vane_controller.get_configuration_errors()))


## Main-vector convention for this prototype:
##   0°   = ship-forward (-Z)
##   90°  = ship-up (+Y), the VTOL/hover setting
##   110° = up with a rearward (+Z) component, providing a braking blend.
## The vector is transformed by the ship's basis, never by world axes.
static func main_vector_direction_local(vector_angle_degrees: float) -> Vector3:
	var angle_radians: float = deg_to_rad(clampf(vector_angle_degrees, 0.0, 110.0))
	return Vector3(0.0, sin(angle_radians), -cos(angle_radians)).normalized()


## Called exactly once per physics tick by ShipFlightController. It is the only
## place where repulsorlift forces are submitted to the physical ship.
func apply_flight_control_forces(
		field_online: bool,
		power_output: float,
		vector_angle_degrees: float,
		pitch_command: float,
		roll_command: float,
		yaw_command: float,
		vane_redistribution_fraction: float = 0.0,
		maximum_vane_output_multiplier: float = 1.2
) -> void:
	_reset_frame_output(field_online, power_output, vector_angle_degrees, pitch_command, roll_command, yaw_command)

	if not is_instance_valid(_ship) or not is_instance_valid(_vane_controller):
		return
	if _ship.freeze or not field_online:
		_update_force_debug()
		return
	if _ship.mass <= MINIMUM_MASS_KG or not _vane_controller.is_configuration_valid():
		_update_force_debug()
		return

	var body_basis: Basis = _ship.global_basis.orthonormalized()
	var center_of_mass_world: Vector3 = _ship.global_transform * _ship.center_of_mass
	_last_gravity_magnitude = _ship.get_gravity().length()
	var reference_force_newtons_per_twr: float = _ship.mass * reference_gravity_mps2
	var main_vector_force_scale: float = reference_force_newtons_per_twr * _last_power_output
	# Maneuvering remains available whenever the field is ONLINE. Reducing the
	# main-vector allocation releases a small amount of capacity to the vanes.
	_last_maneuver_power_multiplier = 1.0 + (1.0 - _last_power_output) * clampf(maneuver_boost_at_zero_main_power, 0.0, 0.35)
	_last_vane_redistribution_fraction = clampf(vane_redistribution_fraction, 0.0, 1.0)
	_last_maximum_vane_output_multiplier = clampf(maximum_vane_output_multiplier, 1.0, 1.5)
	var maneuver_force_scale: float = reference_force_newtons_per_twr * _last_maneuver_power_multiplier

	_apply_main_vector(body_basis, center_of_mass_world, main_vector_force_scale)
	_apply_pitch_pair(body_basis, maneuver_force_scale, _last_vane_redistribution_fraction, _last_maximum_vane_output_multiplier)
	_apply_roll_pair(body_basis, maneuver_force_scale, _last_vane_redistribution_fraction, _last_maximum_vane_output_multiplier)
	_apply_yaw_pair(body_basis, maneuver_force_scale, _last_vane_redistribution_fraction, _last_maximum_vane_output_multiplier)

	if _last_gravity_magnitude > 0.0001:
		var local_up: Vector3 = -_ship.get_gravity().normalized()
		_last_vertical_twr = maxf(_last_total_force.dot(local_up), 0.0) / (_ship.mass * _last_gravity_magnitude)

	_update_force_debug()


func _reset_frame_output(
		field_online: bool,
		power_output: float,
		vector_angle_degrees: float,
		pitch_command: float,
		roll_command: float,
		yaw_command: float
) -> void:
	_last_field_online = field_online
	_last_power_output = clampf(power_output, 0.0, 1.0) if field_online else 0.0
	_last_maneuver_power_multiplier = 1.0 if field_online else 0.0
	_last_vane_redistribution_fraction = 0.0
	_last_maximum_vane_output_multiplier = 1.2
	_last_vector_angle_degrees = clampf(vector_angle_degrees, 0.0, 110.0)
	_last_pitch_command = clampf(pitch_command, -1.0, 1.0) if field_online else 0.0
	_last_roll_command = clampf(roll_command, -1.0, 1.0) if field_online else 0.0
	_last_yaw_command = clampf(yaw_command, -1.0, 1.0) if field_online else 0.0
	_last_main_force = Vector3.ZERO
	_last_total_force = Vector3.ZERO
	_last_total_torque = Vector3.ZERO
	_last_main_direction_world = Vector3.ZERO
	_last_gravity_magnitude = 0.0
	_last_vertical_twr = 0.0
	_last_force_vectors.clear()
	_last_vane_contributions.clear()
	_last_maximum_lift_twr = _get_bottom_nominal_authority_twr()


func _apply_main_vector(body_basis: Basis, center_of_mass_world: Vector3, force_newtons_per_twr: float) -> void:
	var local_direction: Vector3 = main_vector_direction_local(_last_vector_angle_degrees)
	_last_main_direction_world = (body_basis * local_direction).normalized()

	# Cross-fade between the rear/main vane's forward authority and the four
	# bottom vanes' collective lift authority. Past vertical, retain the bottom
	# array's authority while the vector continues into the braking direction.
	var lift_blend: float = clampf(_last_vector_angle_degrees / 90.0, 0.0, 1.0)
	var propulsion_twr: float = _vane_controller.get_group_effective_authority_twr(MAIN_REAR_GROUP)
	var lift_twr: float = _get_bottom_effective_authority_twr()
	var available_main_twr: float = lerpf(propulsion_twr, lift_twr, lift_blend)
	_last_main_force = _last_main_direction_world * force_newtons_per_twr * available_main_twr

	if _last_main_force.length_squared() <= MINIMUM_FORCE_SQUARED:
		return

	# The primary field resultant acts through the COM. It translates the ship
	# without introducing an arbitrary neutral-state pitch/roll oscillation.
	_ship.apply_central_force(_last_main_force)
	_last_total_force += _last_main_force
	_last_force_vectors.append({
		"name": "MAIN FIELD VECTOR",
		"kind": "main",
		"force_world": _last_main_force,
		"application_point_world": center_of_mass_world,
	})


func _apply_pitch_pair(body_basis: Basis, force_newtons_per_twr: float, redistribution_fraction: float, maximum_output_multiplier: float) -> void:
	if absf(_last_pitch_command) <= 0.0001:
		return
	var force_scale: float = force_newtons_per_twr * maneuver_authority_fraction * absf(_last_pitch_command)
	var nose_direction: Vector3 = body_basis * Vector3.UP * signf(_last_pitch_command)
	var rear_direction: Vector3 = -nose_direction

	_apply_vane_set_force(
		"PITCH FRONT",
		"pitch",
		FRONT_VANE_IDS,
		nose_direction,
		force_scale,
		redistribution_fraction,
		maximum_output_multiplier
	)
	_apply_vane_set_force(
		"PITCH REAR",
		"pitch",
		REAR_VANE_IDS,
		rear_direction,
		force_scale,
		redistribution_fraction,
		maximum_output_multiplier
	)


func _apply_roll_pair(body_basis: Basis, force_newtons_per_twr: float, redistribution_fraction: float, maximum_output_multiplier: float) -> void:
	if absf(_last_roll_command) <= 0.0001:
		return
	var force_scale: float = force_newtons_per_twr * maneuver_authority_fraction * absf(_last_roll_command)
	# Positive roll means right side down: left vanes push up, right vanes down.
	var left_direction: Vector3 = body_basis * Vector3.UP * signf(_last_roll_command)
	var right_direction: Vector3 = -left_direction

	_apply_vane_set_force("ROLL LEFT", "roll", LEFT_VANE_IDS, left_direction, force_scale, redistribution_fraction, maximum_output_multiplier)
	_apply_vane_set_force("ROLL RIGHT", "roll", RIGHT_VANE_IDS, right_direction, force_scale, redistribution_fraction, maximum_output_multiplier)


func _apply_yaw_pair(body_basis: Basis, force_newtons_per_twr: float, redistribution_fraction: float, maximum_output_multiplier: float) -> void:
	if absf(_last_yaw_command) <= 0.0001:
		return
	var force_scale: float = force_newtons_per_twr * absf(_last_yaw_command)
	# Positive A/D command is yaw-right: the left side pushes forward (-Z),
	# while the right side pushes aft (+Z). The pair cancels translation and
	# creates a moment around the ship's vertical axis.
	var left_direction: Vector3 = body_basis * Vector3.FORWARD * signf(_last_yaw_command)
	var right_direction: Vector3 = -left_direction

	_apply_group_force("YAW LEFT", "yaw", SIDE_LEFT_GROUP, left_direction, force_scale, redistribution_fraction, maximum_output_multiplier)
	_apply_group_force("YAW RIGHT", "yaw", SIDE_RIGHT_GROUP, right_direction, force_scale, redistribution_fraction, maximum_output_multiplier)


func _apply_vane_set_force(
		force_name: String,
		force_kind: String,
		vane_ids: Array[StringName],
		force_direction_world: Vector3,
		force_scale: float,
		redistribution_fraction: float,
		maximum_output_multiplier: float
) -> void:
	var resultant: Dictionary = _vane_controller.calculate_vane_set_resultant(
		vane_ids,
		force_direction_world,
		force_scale,
		_ship.global_transform,
		_ship.center_of_mass,
		redistribution_fraction,
		maximum_output_multiplier
	)
	_apply_resultant(force_name, force_kind, resultant)


func _apply_group_force(
		force_name: String,
		force_kind: String,
		group_id: StringName,
		force_direction_world: Vector3,
		force_scale: float,
		redistribution_fraction: float,
		maximum_output_multiplier: float
) -> void:
	var resultant: Dictionary = _vane_controller.calculate_group_resultant(
		group_id,
		force_direction_world,
		force_scale,
		_ship.global_transform,
		_ship.center_of_mass,
		redistribution_fraction,
		maximum_output_multiplier
	)
	_apply_resultant(force_name, force_kind, resultant)


func _apply_resultant(force_name: String, force_kind: String, resultant: Dictionary) -> void:
	var force_world: Vector3 = resultant.get("net_force", Vector3.ZERO)
	if force_world.length_squared() <= MINIMUM_FORCE_SQUARED:
		return

	var application_point_world: Vector3 = resultant.get(
		"effective_application_point_world",
		_ship.global_transform * _ship.center_of_mass
	)
	var center_of_mass_world: Vector3 = _ship.global_transform * _ship.center_of_mass
	var application_offset_world: Vector3 = application_point_world - _ship.global_position

	# Godot expects a force offset from the body origin in global coordinates.
	# A weighted group point preserves the group moment without separate torque
	# for the normal aligned-vane case.
	_ship.apply_force(force_world, application_offset_world)

	var torque_from_application_point: Vector3 = (
		application_point_world - center_of_mass_world
	).cross(force_world)
	var exact_group_torque: Vector3 = resultant.get("net_torque", torque_from_application_point)
	var residual_torque: Vector3 = exact_group_torque - torque_from_application_point
	if residual_torque.length_squared() > MINIMUM_TORQUE_SQUARED:
		# Alignment offsets can make individual vane directions differ. Preserve
		# the remaining couple as a pure torque rather than losing that physics.
		_ship.apply_torque(residual_torque)

	_last_total_force += force_world
	_last_total_torque += exact_group_torque
	_last_vane_contributions.append_array(resultant.get("contributions", []))
	_last_force_vectors.append({
		"name": force_name,
		"kind": force_kind,
		"force_world": force_world,
		"application_point_world": application_point_world,
	})


func _get_bottom_nominal_authority_twr() -> float:
	if not is_instance_valid(_vane_controller):
		return 0.0
	return (
		_vane_controller.get_group_nominal_authority_twr(BOTTOM_FRONT_GROUP)
		+ _vane_controller.get_group_nominal_authority_twr(BOTTOM_REAR_GROUP)
	)


func _get_bottom_effective_authority_twr() -> float:
	if not is_instance_valid(_vane_controller):
		return 0.0
	return (
		_vane_controller.get_group_effective_authority_twr(BOTTOM_FRONT_GROUP)
		+ _vane_controller.get_group_effective_authority_twr(BOTTOM_REAR_GROUP)
	)


func set_debug_visualization_enabled(enabled: bool) -> void:
	_debug_visualization_enabled = enabled
	if is_instance_valid(_force_debug):
		_force_debug.visible = enabled
		if enabled:
			_update_force_debug(true)


func _update_force_debug(force_refresh: bool = false) -> void:
	if not _debug_visualization_enabled or not is_instance_valid(_force_debug):
		return
	_debug_refresh_counter += 1
	if not force_refresh and _debug_refresh_counter < DEBUG_REFRESH_EVERY_CALLS:
		return
	_debug_refresh_counter = 0
	var reference_force: float = _ship.mass * reference_gravity_mps2
	_force_debug.update_force_vectors(_last_force_vectors, _ship.global_transform, reference_force)


## Read-only snapshot for HUD and tests. HUD never modifies simulation state.
func get_telemetry() -> Dictionary:
	var local_gravity_magnitude: float = _ship.get_gravity().length() if is_instance_valid(_ship) else 0.0
	var bottom_effective_twr: float = _get_bottom_effective_authority_twr()
	var hover_power_percent: float = -1.0
	if bottom_effective_twr > 0.0001 and local_gravity_magnitude > 0.0001:
		hover_power_percent = 100.0 * local_gravity_magnitude / (reference_gravity_mps2 * bottom_effective_twr)

	var vane_telemetry: Dictionary = {}
	if is_instance_valid(_vane_controller):
		vane_telemetry = _vane_controller.get_telemetry()

	var telemetry: Dictionary = {
		"lift_field_online": _last_field_online,
		"lift_power_output": _last_power_output,
		"lift_force_vector": _last_total_force,
		"lift_force_newtons": _last_total_force.length(),
		"lift_main_force_vector": _last_main_force,
		"lift_main_direction_world": _last_main_direction_world,
		"lift_actual_twr": _last_vertical_twr,
		"lift_maximum_twr": _last_maximum_lift_twr,
		"lift_hover_power_percent": hover_power_percent,
		"lift_gravity_magnitude": local_gravity_magnitude,
		"lift_torque_vector": _last_total_torque,
		"lift_torque_magnitude": _last_total_torque.length(),
		"lift_torque_applied": _last_total_torque.length_squared() > MINIMUM_TORQUE_SQUARED,
		"lift_force_vectors": _last_force_vectors.duplicate(true),
		"lift_vane_contributions": _last_vane_contributions.duplicate(true),
		"maneuver_authority_fraction": maneuver_authority_fraction,
		"maneuver_power_multiplier": _last_maneuver_power_multiplier,
		"maneuver_boost_at_zero_main_power": maneuver_boost_at_zero_main_power,
		"vane_redistribution_fraction": _last_vane_redistribution_fraction,
		"maximum_vane_output_multiplier": _last_maximum_vane_output_multiplier,
		"reference_gravity_mps2": reference_gravity_mps2,
	}
	telemetry.merge(vane_telemetry, true)
	return telemetry
