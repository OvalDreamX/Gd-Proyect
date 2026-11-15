extends Node
class_name RepulsorliftSystem

const VANE_ACTUATOR_ALLOCATOR_SCRIPT = preload("res://scripts/vane_actuator_allocator.gd")

## Owns all ship-force submission. Main propulsion remains on the established
## field-vector path; pitch/roll use geometry-based actuator allocation, while
## yaw retains its legacy side-group path until those axes are redesigned.

@export_category("Main field vector")
## TWR values in vane resources are rated against maximum design gross mass
## (dry mass + payload capacity), not current loaded mass. This keeps maximum
## thrust fixed as cargo is added, so heavier loads accelerate less.
@export_range(1.0, 20.0, 0.1) var reference_gravity_mps2: float = 9.81

@export_category("Maneuver authority")
## Requested share of the installed geometry-derived pitch/roll torque
## capacity at full FCC deflection. This remains a control-feel tuning value.
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

const MINIMUM_MASS_KG: float = 0.0001
const MINIMUM_FORCE_SQUARED: float = 0.000001
const MINIMUM_TORQUE_SQUARED: float = 0.000001
const DEBUG_REFRESH_EVERY_CALLS: int = 3

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable
@onready var _vane_controller: VaneController = get_node("../VaneController") as VaneController
@onready var _force_debug: ForceVectorDebug = get_node_or_null("../ForceVectorDebug") as ForceVectorDebug
@onready var _planetary_gravity_body: Node = get_node_or_null("../PlanetaryGravityBody")

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
var _last_maneuver_allocation: Dictionary = {}


func _ready() -> void:
	if _ship == null or _vane_controller == null:
		push_error("RepulsorliftSystem requires ShipInteractable and VaneController siblings.")
		set_process(false)
		set_physics_process(false)
		return
	if _force_debug == null:
		push_warning("ForceVectorDebug node is missing; F3 force arrows will be unavailable.")

	_last_maximum_lift_twr = _get_maximum_lift_twr_at_current_mass()
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
		maximum_vane_output_multiplier: float = 1.2,
		delta_seconds: float = 0.0
) -> void:
	_reset_frame_output(field_online, power_output, vector_angle_degrees, pitch_command, roll_command, yaw_command)

	if not is_instance_valid(_ship) or not is_instance_valid(_vane_controller):
		return

	var thermal_delta: float = delta_seconds
	if thermal_delta <= 0.000001:
		thermal_delta = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)

	if _ship.freeze or not field_online:
		_step_vane_thermal(thermal_delta, false)
		_update_force_debug()
		return
	if _ship.mass <= MINIMUM_MASS_KG or not _vane_controller.is_configuration_valid():
		_step_vane_thermal(thermal_delta, true)
		_update_force_debug()
		return

	var body_basis: Basis = _ship.global_basis.orthonormalized()
	var center_of_mass_world: Vector3 = _ship.global_transform * _ship.center_of_mass
	_last_gravity_magnitude = _get_gravity_vector_world().length()
	var reference_force_newtons_per_twr: float = _get_rated_gross_mass_kg() * reference_gravity_mps2
	var main_vector_force_scale: float = reference_force_newtons_per_twr * _last_power_output
	# Maneuvering remains available whenever the field is ONLINE. Reducing the
	# main-vector allocation releases a small amount of capacity to the vanes.
	_last_maneuver_power_multiplier = 1.0 + (1.0 - _last_power_output) * clampf(maneuver_boost_at_zero_main_power, 0.0, 0.35)
	var maneuver_force_scale: float = reference_force_newtons_per_twr * _last_maneuver_power_multiplier
	_last_vane_redistribution_fraction = clampf(vane_redistribution_fraction, 0.0, 1.0)
	_last_maximum_vane_output_multiplier = clampf(maximum_vane_output_multiplier, 1.0, 1.5)
	_apply_main_vector(body_basis, center_of_mass_world, main_vector_force_scale)
	_apply_maneuver_allocator(
		body_basis,
		reference_force_newtons_per_twr,
		_last_vane_redistribution_fraction,
		_last_maximum_vane_output_multiplier
	)
	# The prototype side-vane positions/axis metadata are not yet sufficient for
	# a geometry-correct yaw couple. Keep its known-good group mapping until those
	# model anchors are updated; the allocator already supports yaw mathematically.
	_apply_yaw_pair(body_basis, maneuver_force_scale, _last_vane_redistribution_fraction, _last_maximum_vane_output_multiplier)

	if _last_gravity_magnitude > 0.0001:
		var local_up: Vector3 = -_get_gravity_vector_world().normalized()
		_last_vertical_twr = maxf(_last_total_force.dot(local_up), 0.0) / (_ship.mass * _last_gravity_magnitude)

	# Thermal load combines the current main-vector allocation with the actual
	# per-vane force contributions produced by the maneuver allocator.
	_step_vane_thermal(thermal_delta, true)

	_update_force_debug()


func _step_vane_thermal(delta: float, field_online: bool) -> void:
	if not is_instance_valid(_vane_controller):
		return
	var ambient_temp: float = -10.0
	var atmosphere_node: Node = _ship.get_node_or_null("AtmosphericFlightModel") if is_instance_valid(_ship) else null
	if atmosphere_node != null and "ambient_temperature_celsius" in atmosphere_node:
		ambient_temp = float(atmosphere_node.ambient_temperature_celsius)

	var loads: Dictionary = {}
	if field_online:
		var force_newtons_per_twr: float = _get_rated_gross_mass_kg() * reference_gravity_mps2
		loads = _vane_controller.calculate_thermal_loads(
			_last_power_output,
			_last_vector_angle_degrees,
			_last_vane_contributions,
			force_newtons_per_twr
		)
	_vane_controller.update_thermal_simulation(delta, ambient_temp, field_online, loads)


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
	_last_maneuver_allocation = {
		"success": true,
		"converged": true,
		"actuator_outputs": [],
		"eligible_actuator_count": 0,
		"normalized_error": 0.0,
	}
	_last_maximum_lift_twr = _get_maximum_lift_twr_at_current_mass()


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

	# The ship-wide field resultant is applied at the fixed hull reference datum
	# (the rigid-body origin), not magically through the moving COM. An offset
	# cargo COM therefore creates a real lever arm and attitude moment. With the
	# empty ship's COM at the origin, this remains a zero-moment main resultant.
	var application_point_world: Vector3 = _ship.global_position
	_ship.apply_force(_last_main_force, Vector3.ZERO)
	var main_torque: Vector3 = (application_point_world - center_of_mass_world).cross(_last_main_force)
	_last_total_force += _last_main_force
	_last_total_torque += main_torque
	_last_force_vectors.append({
		"name": "MAIN FIELD VECTOR",
		"kind": "main",
		"force_world": _last_main_force,
		"application_point_world": application_point_world,
	})


func _apply_maneuver_allocator(
		body_basis: Basis,
		reference_force_newtons: float,
		redistribution_fraction: float,
		maximum_output_multiplier: float
) -> void:
	var center_of_mass_local: Vector3 = _ship.center_of_mass
	var active_channels: Array[StringName] = []
	if absf(_last_pitch_command) > 0.0001:
		active_channels.append(&"pitch")
	if absf(_last_roll_command) > 0.0001:
		active_channels.append(&"roll")

	var runtime_entries: Array[Dictionary] = []
	var characteristic_length_m: float = 1.0
	var total_damage_shortfall_twr: float = 0.0
	var total_healthy_headroom_twr: float = 0.0
	var safe_maximum_multiplier: float = clampf(maximum_output_multiplier, 1.0, 1.5)

	# Discover every configured actuator by stable ID. Eligibility comes from
	# its channel weights; there is no fixed front/rear/left/right slot count.
	for vane_id: StringName in _vane_controller.get_vane_ids():
		var definition: VaneDefinition = _vane_controller.get_vane_definition(vane_id)
		if not is_instance_valid(definition) or not definition.enabled:
			continue
		var eligible_for_active_channel: bool = false
		for channel: StringName in active_channels:
			if definition.get_control_weight(channel) > 0:
				eligible_for_active_channel = true
				break
		if not eligible_for_active_channel:
			continue

		var base_authority_twr: float = _vane_controller.get_vane_effective_authority_twr(vane_id)
		var spare_headroom_twr: float = 0.0
		if _vane_controller.can_vane_receive_redistributed_authority(vane_id):
			spare_headroom_twr = definition.nominal_authority_twr * (safe_maximum_multiplier - 1.0)
		total_damage_shortfall_twr += maxf(definition.nominal_authority_twr - base_authority_twr, 0.0)
		total_healthy_headroom_twr += spare_headroom_twr
		characteristic_length_m = maxf(
			characteristic_length_m,
			(definition.local_position - center_of_mass_local).length()
		)
		runtime_entries.append({
			"vane_id": vane_id,
			"definition": definition,
			"base_authority_twr": base_authority_twr,
			"spare_headroom_twr": spare_headroom_twr,
		})

	var redistribution_budget_twr: float = minf(
		total_damage_shortfall_twr * clampf(redistribution_fraction, 0.0, 1.0),
		total_healthy_headroom_twr
	)
	var actuators: Array[Dictionary] = []
	var pitch_capacity_torque_nm: float = 0.0
	var roll_capacity_torque_nm: float = 0.0

	for entry_value: Dictionary in runtime_entries:
		var entry: Dictionary = entry_value
		var vane_id: StringName = StringName(str(entry["vane_id"]))
		var definition: VaneDefinition = entry["definition"]
		var spare_headroom_twr: float = float(entry["spare_headroom_twr"])
		var redistributed_authority_twr: float = 0.0
		if total_healthy_headroom_twr > 0.000001 and spare_headroom_twr > 0.0:
			redistributed_authority_twr = (
				redistribution_budget_twr * spare_headroom_twr / total_healthy_headroom_twr
			)
		var effective_authority_twr: float = (
			float(entry["base_authority_twr"]) + redistributed_authority_twr
		)
		var max_force_n: float = (
			effective_authority_twr
			* reference_force_newtons
			* _last_maneuver_power_multiplier
		)
		var actuator_axis: Vector3 = _vane_controller.get_vane_effective_thrust_axis_local(vane_id)
		if actuator_axis.length_squared() <= MINIMUM_FORCE_SQUARED:
			continue
		var lever_arm_local: Vector3 = definition.local_position - center_of_mass_local
		var maximum_torque_local: Vector3 = lever_arm_local.cross(actuator_axis) * max_force_n
		if definition.get_control_weight(&"pitch") > 0:
			pitch_capacity_torque_nm += absf(maximum_torque_local.x)
		if definition.get_control_weight(&"roll") > 0:
			roll_capacity_torque_nm += absf(maximum_torque_local.z)
		actuators.append({
			"id": StringName(str(entry["vane_id"])),
			"position_local": definition.local_position,
			"axis_local": actuator_axis,
			"max_force_n": max_force_n,
			"control_weights": definition.control_weights,
			"enabled": definition.enabled,
		})

	var normalized_pitch_demand: float = 0.0
	var normalized_roll_demand: float = 0.0
	if reference_force_newtons > MINIMUM_FORCE_SQUARED and characteristic_length_m > 0.0:
		var wrench_reference: float = reference_force_newtons * characteristic_length_m
		normalized_pitch_demand = (
			_last_pitch_command * maneuver_authority_fraction
			* pitch_capacity_torque_nm / wrench_reference
		)
		normalized_roll_demand = (
			_last_roll_command * maneuver_authority_fraction
			* roll_capacity_torque_nm / wrench_reference
		)

	var demands: Dictionary = {
		"pitch": clampf(normalized_pitch_demand, -1.0, 1.0),
		"roll": clampf(normalized_roll_demand, -1.0, 1.0),
	}
	var allocation: Dictionary = VANE_ACTUATOR_ALLOCATOR_SCRIPT.allocate(
		actuators,
		demands,
		center_of_mass_local,
		reference_force_newtons,
		characteristic_length_m
	)
	_last_maneuver_allocation = allocation
	if not bool(allocation.get("success", false)):
		return

	var maneuver_force_kind: String = "maneuver"
	if active_channels.size() == 1:
		maneuver_force_kind = String(active_channels[0])

	for output_entry: Dictionary in allocation.get("actuator_outputs", []):
		var output_id: StringName = StringName(str(output_entry.get("id", "")))
		var definition: VaneDefinition = _vane_controller.get_vane_definition(output_id)
		if not is_instance_valid(definition):
			continue
		var force_local: Vector3 = output_entry.get("force_local_n", Vector3.ZERO)
		if force_local.length_squared() <= MINIMUM_FORCE_SQUARED:
			continue

		var force_world: Vector3 = body_basis * force_local
		var application_offset_world: Vector3 = body_basis * definition.local_position
		var application_point_world: Vector3 = _ship.global_position + application_offset_world
		var torque_local: Vector3 = (
			definition.local_position - center_of_mass_local
		).cross(force_local)
		var torque_world: Vector3 = body_basis * torque_local
		_ship.apply_force(force_world, application_offset_world)
		_last_total_force += force_world
		_last_total_torque += torque_world
		_last_vane_contributions.append({
			"vane_id": output_id,
			"display_name": definition.display_name,
			"group_id": definition.group_id,
			"force_world": force_world,
			"torque_world": torque_world,
			"application_point_world": application_point_world,
			"lever_arm_world": body_basis * (definition.local_position - center_of_mass_local),
			"effective_authority_twr": (
				float(output_entry.get("max_force_n", 0.0))
				/ maxf(reference_force_newtons * _last_maneuver_power_multiplier, 0.0001)
			),
			"allocation_weight": float(output_entry.get("control_weight", 0.0)),
			"actuator_output": float(output_entry.get("output", 0.0)),
		})
		_last_force_vectors.append({
			"name": "MANEUVER %s" % String(output_id),
			"kind": maneuver_force_kind,
			"force_world": force_world,
			"application_point_world": application_point_world,
		})


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


func _get_gravity_vector_world() -> Vector3:
	if is_instance_valid(_planetary_gravity_body) and _planetary_gravity_body.has_method("get_local_gravity_vector_world"):
		return _planetary_gravity_body.call("get_local_gravity_vector_world")
	return _ship.get_gravity() if is_instance_valid(_ship) else Vector3.ZERO


func _get_rated_gross_mass_kg() -> float:
	if not is_instance_valid(_ship):
		return 0.0
	return maxf(_ship.get_design_gross_mass_kg(), MINIMUM_MASS_KG)


func is_field_online() -> bool:
	return _last_field_online


func _get_maximum_lift_twr_at_current_mass() -> float:
	if not is_instance_valid(_ship) or _ship.mass <= MINIMUM_MASS_KG:
		return 0.0
	var local_gravity_mps2: float = _get_gravity_vector_world().length()
	if local_gravity_mps2 <= 0.0001:
		return 0.0
	var rated_lift_force: float = (
		_get_bottom_nominal_authority_twr()
		* _get_rated_gross_mass_kg()
		* reference_gravity_mps2
	)
	return rated_lift_force / (_ship.mass * local_gravity_mps2)


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
	var reference_force: float = _get_rated_gross_mass_kg() * reference_gravity_mps2
	_force_debug.update_force_vectors(_last_force_vectors, _ship.global_transform, reference_force)


## Read-only snapshot for HUD and tests. HUD never modifies simulation state.
func get_telemetry() -> Dictionary:
	var local_gravity_magnitude: float = _get_gravity_vector_world().length() if is_instance_valid(_ship) else 0.0
	var bottom_effective_twr: float = _get_bottom_effective_authority_twr()
	var hover_power_percent: float = -1.0
	var rated_gross_mass_kg: float = _get_rated_gross_mass_kg()
	var current_mass_kg: float = _ship.mass if is_instance_valid(_ship) else 0.0
	if (bottom_effective_twr > 0.0001 and local_gravity_magnitude > 0.0001
			and rated_gross_mass_kg > MINIMUM_MASS_KG and current_mass_kg > MINIMUM_MASS_KG):
		hover_power_percent = (
			100.0 * current_mass_kg * local_gravity_magnitude
			/ (rated_gross_mass_kg * reference_gravity_mps2 * bottom_effective_twr)
		)

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
		"lift_rated_gross_mass_kg": rated_gross_mass_kg,
		"lift_design_dry_mass_kg": _ship.get_design_dry_mass_kg() if is_instance_valid(_ship) else 0.0,
		"lift_payload_capacity_kg": _ship.max_payload_mass_kg if is_instance_valid(_ship) else 0.0,
		"lift_current_mass_kg": current_mass_kg,
		"lift_maximum_vertical_force_n": rated_gross_mass_kg * reference_gravity_mps2 * bottom_effective_twr,
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
		"maneuver_allocator": _last_maneuver_allocation.duplicate(true),
		"maneuver_allocator_active_actuators": int(_last_maneuver_allocation.get("eligible_actuator_count", 0)),
		"maneuver_allocator_normalized_error": float(_last_maneuver_allocation.get("normalized_error", 0.0)),
		"reference_gravity_mps2": reference_gravity_mps2,
	}
	telemetry.merge(vane_telemetry, true)
	return telemetry
