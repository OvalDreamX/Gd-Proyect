extends Node
class_name RepulsorliftSystem

const VANE_ACTUATOR_ALLOCATOR_SCRIPT = preload("res://scripts/vane_actuator_allocator.gd")

## Owns all ship-force submission. Main-vector and maneuver demands are solved
## together in one bounded wrench allocation, producing one scalar output per
## physical actuator and one force application at each authored anchor.

@export_category("Main field vector")
## TWR values in vane resources are rated against maximum design gross mass
## (dry mass + payload capacity), not current loaded mass. This keeps maximum
## thrust fixed as cargo is added, so heavier loads accelerate less.
@export_range(1.0, 20.0, 0.1) var reference_gravity_mps2: float = 9.81

@export_category("Maneuver authority")
## Requested share of the installed geometry-derived pitch/roll torque
## capacity at full FCC deflection. Yaw preserves its existing rated side-vane
## authority and is not scaled by this percentage.
@export_range(0.0, 0.25, 0.005) var maneuver_authority_fraction: float = 0.05
## Maneuvering keeps a baseline while the field is online. Unused main-vector
## allocation can add up to this modest reserve at zero main-vector output.
@export_range(0.0, 0.35, 0.01) var maneuver_boost_at_zero_main_power: float = 0.20

@export_category("Debug vectors")
@export_range(1.0, 12.0, 0.5) var debug_arrow_length_per_twr_m: float = 4.0

const MAIN_VECTOR_ALLOCATOR_REGULARIZATION: float = 0.000000001

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
var _last_main_vector_allocation: Dictionary = {}
var _pending_space_assist_active: bool = false
var _pending_space_assist_force_world: Vector3 = Vector3.ZERO


func apply_ship_definition(definition: ShipDefinition) -> void:
	if definition == null:
		return
	if definition.propulsion.has("reference_gravity_mps2"):
		reference_gravity_mps2 = clampf(float(definition.propulsion.get("reference_gravity_mps2", reference_gravity_mps2)), 1.0, 20.0)
	if definition.propulsion.has("maneuver_authority_fraction"):
		maneuver_authority_fraction = clampf(float(definition.propulsion.get("maneuver_authority_fraction", maneuver_authority_fraction)), 0.0, 0.5)
	if definition.propulsion.has("maneuver_boost_at_zero_main_power"):
		maneuver_boost_at_zero_main_power = clampf(float(definition.propulsion.get("maneuver_boost_at_zero_main_power", maneuver_boost_at_zero_main_power)), 0.0, 0.5)
	_last_maximum_lift_twr = _get_maximum_lift_twr_at_current_mass()


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


static func main_vector_direction_local(vector_angle_degrees: float) -> Vector3:
	var angle_radians: float = deg_to_rad(clampf(vector_angle_degrees, 0.0, 110.0))
	return Vector3(0.0, sin(angle_radians), -cos(angle_radians)).normalized()


func apply_collective_lift(field_online: bool, power_output: float) -> void:
	apply_flight_control_forces(field_online, power_output, 90.0, 0.0, 0.0, 0.0, 0.0, 1.2, 0.0)


func set_space_assist_override(active: bool, force_world: Vector3 = Vector3.ZERO) -> void:
	_pending_space_assist_active = active
	_pending_space_assist_force_world = force_world if active else Vector3.ZERO


func get_main_rear_effective_authority_twr() -> float:
	if not is_instance_valid(_vane_controller):
		return 1.5
	return maxf(_get_main_vector_channel_capacity_twr(&"main_thrust", Vector3.BACK), 0.0)


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
	var suppress_manual_main_vector: bool = _pending_space_assist_active
	var space_assist_force_world: Vector3 = _pending_space_assist_force_world
	_pending_space_assist_active = false
	_pending_space_assist_force_world = Vector3.ZERO
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
	_last_gravity_magnitude = _get_gravity_vector_world().length()
	var reference_force_newtons_per_twr: float = _get_rated_gross_mass_kg() * reference_gravity_mps2
	_last_maneuver_power_multiplier = 1.0 + (1.0 - _last_power_output) * clampf(maneuver_boost_at_zero_main_power, 0.0, 0.35)
	_last_vane_redistribution_fraction = clampf(vane_redistribution_fraction, 0.0, 1.0)
	_last_maximum_vane_output_multiplier = clampf(maximum_vane_output_multiplier, 1.0, 1.5)
	_apply_unified_actuator_allocator(
		body_basis,
		reference_force_newtons_per_twr,
		_last_vane_redistribution_fraction,
		_last_maximum_vane_output_multiplier,
		suppress_manual_main_vector,
		space_assist_force_world
	)

	if _last_gravity_magnitude > 0.0001:
		var local_up: Vector3 = -_get_gravity_vector_world().normalized()
		_last_vertical_twr = maxf(_last_total_force.dot(local_up), 0.0) / (_ship.mass * _last_gravity_magnitude)

	if suppress_manual_main_vector:
		var main_cap_twr: float = maxf(get_main_rear_effective_authority_twr(), 0.5)
		var max_main_f: float = maxf(reference_force_newtons_per_twr * main_cap_twr, 1.0)
		_last_power_output = clampf(space_assist_force_world.length() / max_main_f, 0.0, 1.0)
		_last_vector_angle_degrees = 0.0

	_step_vane_thermal(thermal_delta, true)
	_update_force_debug()


func _step_vane_thermal(delta: float, field_online: bool) -> void:
	if not is_instance_valid(_vane_controller):
		return
	var ambient_temp: float = -10.0
	var air_density: float = 0.0
	var airspeed_mps: float = _ship.linear_velocity.length() if is_instance_valid(_ship) else 0.0
	var convective_eff: float = 1.0
	var atmosphere_node: Node = _ship.get_node_or_null("AtmosphericFlightModel") if is_instance_valid(_ship) else null
	if atmosphere_node != null:
		if "ambient_temperature_celsius" in atmosphere_node:
			ambient_temp = float(atmosphere_node.ambient_temperature_celsius)
		if atmosphere_node.has_method("get_telemetry"):
			var atmo_tele: Dictionary = atmosphere_node.call("get_telemetry") as Dictionary
			air_density = float(atmo_tele.get("atmosphere_density_kg_m3", 0.0))
			airspeed_mps = float(atmo_tele.get("atmosphere_airspeed_mps", airspeed_mps))
			convective_eff = float(atmo_tele.get("atmosphere_convective_efficiency", 1.0))

	var loads: Dictionary = {}
	if field_online:
		var force_newtons_per_twr: float = _get_rated_gross_mass_kg() * reference_gravity_mps2
		for vane_id: StringName in _vane_controller.get_vane_ids():
			var definition: VaneDefinition = _vane_controller.get_vane_definition(vane_id)
			if not is_instance_valid(definition) or not definition.enabled:
				loads[vane_id] = 0.0
				continue
			var rated_force: float = definition.nominal_authority_twr * force_newtons_per_twr
			loads[vane_id] = 0.0
			if rated_force > MINIMUM_FORCE_SQUARED:
				for contribution_value: Dictionary in _last_vane_contributions:
					var contribution: Dictionary = contribution_value
					if StringName(contribution.get("vane_id", &"")) != vane_id:
						continue
					var force_world: Vector3 = contribution.get("force_world", Vector3.ZERO)
					loads[vane_id] = float(loads[vane_id]) + force_world.length() / rated_force
			loads[vane_id] = clampf(float(loads[vane_id]), 0.0, 1.5)
	_vane_controller.update_thermal_simulation(
		delta, ambient_temp, field_online, loads, air_density, airspeed_mps, convective_eff
	)


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
	_last_main_vector_allocation = _empty_main_vector_allocation()
	_last_maximum_lift_twr = _get_maximum_lift_twr_at_current_mass()


func _apply_unified_actuator_allocator(
		body_basis: Basis,
		reference_force_newtons: float,
		redistribution_fraction: float,
		maximum_output_multiplier: float,
		suppress_manual_main_vector: bool = false,
		space_assist_force_world: Vector3 = Vector3.ZERO
) -> void:
	var local_direction: Vector3 = main_vector_direction_local(_last_vector_angle_degrees)
	if suppress_manual_main_vector:
		_last_main_direction_world = space_assist_force_world.normalized() if space_assist_force_world.length_squared() > MINIMUM_FORCE_SQUARED else Vector3.ZERO
	else:
		_last_main_direction_world = (body_basis * local_direction).normalized()
	if reference_force_newtons <= MINIMUM_FORCE_SQUARED:
		return

	var lift_capacity_twr: float = _get_main_vector_channel_capacity_twr(&"lift", Vector3.UP)
	var main_capacity_twr: float = _get_main_vector_channel_capacity_twr(&"main_thrust", Vector3.BACK)
	var lift_blend: float = clampf(_last_vector_angle_degrees / 90.0, 0.0, 1.0)
	var available_main_twr: float = lerpf(main_capacity_twr, lift_capacity_twr, lift_blend)
	var maximum_reference_twr: float = maxf(lift_capacity_twr, main_capacity_twr)
	if maximum_reference_twr <= MINIMUM_FORCE_SQUARED:
		return

	var center_of_mass_local: Vector3 = _ship.center_of_mass
	var characteristic_length_m: float = maxf(1.0, center_of_mass_local.length())
	var actuator_records: Array[Dictionary] = []
	var safe_maximum_multiplier: float = clampf(maximum_output_multiplier, 1.0, 1.5)
	var safe_redistribution_fraction: float = clampf(redistribution_fraction, 0.0, 1.0)
	var maneuver_multiplier: float = _last_maneuver_power_multiplier
	var allocator_reference_force: float = reference_force_newtons * maximum_reference_twr
	var target_main_force_local: Vector3 = Vector3.ZERO
	if suppress_manual_main_vector:
		target_main_force_local = body_basis.inverse() * space_assist_force_world
	elif _last_power_output > 0.000001 and available_main_twr > MINIMUM_FORCE_SQUARED:
		var pitch_roll_reserve: float = clampf(
			(absf(_last_pitch_command) + absf(_last_roll_command))
			* maneuver_authority_fraction,
			0.0,
			0.25
		)
		var propulsion_share: float = 1.0 - pitch_roll_reserve
		target_main_force_local = local_direction * (
			reference_force_newtons * available_main_twr * _last_power_output * propulsion_share
		)
	var main_datum_torque_local: Vector3 = (Vector3.ZERO - center_of_mass_local).cross(target_main_force_local)
	var active_channels: Array[StringName] = []
	if absf(target_main_force_local.x) > MINIMUM_FORCE_SQUARED:
		active_channels.append(&"translate_x")
	if absf(target_main_force_local.y) > MINIMUM_FORCE_SQUARED:
		active_channels.append(&"lift")
	if absf(target_main_force_local.z) > MINIMUM_FORCE_SQUARED:
		active_channels.append(&"main_thrust")
	if absf(_last_pitch_command) > 0.0001 or absf(main_datum_torque_local.x) > MINIMUM_FORCE_SQUARED:
		active_channels.append(&"pitch")
	if absf(_last_roll_command) > 0.0001 or absf(main_datum_torque_local.z) > MINIMUM_FORCE_SQUARED:
		active_channels.append(&"roll")
	if absf(_last_yaw_command) > 0.0001 or absf(main_datum_torque_local.y) > MINIMUM_FORCE_SQUARED:
		active_channels.append(&"yaw")

	for vane_id: StringName in _vane_controller.get_vane_ids():
		var definition: VaneDefinition = _vane_controller.get_vane_definition(vane_id)
		if not is_instance_valid(definition) or not definition.enabled:
			continue
		var effective_authority_twr: float = _vane_controller.get_vane_effective_authority_twr(vane_id)
		var axis_local: Vector3 = _vane_controller.get_vane_effective_thrust_axis_local(vane_id)
		if effective_authority_twr <= MINIMUM_FORCE_SQUARED or axis_local.length_squared() <= MINIMUM_FORCE_SQUARED:
			continue
		var has_active_weight: bool = false
		for active_channel: StringName in active_channels:
			if definition.get_control_weight(active_channel) > 0:
				has_active_weight = true
				break
		if not has_active_weight:
			continue
		var nominal: float = definition.nominal_authority_twr
		var spare: float = 0.0
		if _vane_controller.can_vane_receive_redistributed_authority(vane_id):
			spare = nominal * (safe_maximum_multiplier - 1.0)
		characteristic_length_m = maxf(
			characteristic_length_m,
			(definition.local_position - center_of_mass_local).length()
		)
		actuator_records.append({
			"id": vane_id,
			"definition": definition,
			"base_authority_twr": effective_authority_twr,
			"spare_headroom_twr": spare,
			"axis_local": axis_local.normalized(),
		})

	if actuator_records.is_empty() or active_channels.is_empty():
		if suppress_manual_main_vector and space_assist_force_world.length_squared() > MINIMUM_FORCE_SQUARED:
			var fallback_x_local: float = target_main_force_local.x
			if absf(fallback_x_local) > 0.01:
				var fallback_x_world: Vector3 = body_basis * Vector3(fallback_x_local, 0.0, 0.0)
				_ship.apply_force(fallback_x_world, Vector3.ZERO)
				_last_main_force = body_basis * target_main_force_local
				_last_total_force += fallback_x_world
				_last_force_vectors.append({
					"name": "SPACE ASSIST LATERAL",
					"kind": "main",
					"force_world": fallback_x_world,
					"application_point_world": _ship.global_position,
				})
		return

	var redistributed_by_vane: Dictionary = {}
	for record_value: Dictionary in actuator_records:
		var record: Dictionary = record_value
		redistributed_by_vane[record["id"]] = 0.0
	for active_channel: StringName in active_channels:
		var channel_damage_shortfall_twr: float = 0.0
		var channel_healthy_headroom_twr: float = 0.0
		for record_value: Dictionary in actuator_records:
			var record: Dictionary = record_value
			var definition: VaneDefinition = record["definition"]
			if definition.get_control_weight(active_channel) <= 0:
				continue
			channel_damage_shortfall_twr += maxf(
				definition.nominal_authority_twr - float(record["base_authority_twr"]),
				0.0
			)
			channel_healthy_headroom_twr += float(record["spare_headroom_twr"])
		if channel_healthy_headroom_twr <= MINIMUM_FORCE_SQUARED:
			continue
		var channel_redistribution_budget_twr: float = minf(
			channel_damage_shortfall_twr * safe_redistribution_fraction,
			channel_healthy_headroom_twr
		)
		if channel_redistribution_budget_twr <= MINIMUM_FORCE_SQUARED:
			continue
		for record_value: Dictionary in actuator_records:
			var record: Dictionary = record_value
			var definition: VaneDefinition = record["definition"]
			if definition.get_control_weight(active_channel) <= 0:
				continue
			var spare: float = float(record["spare_headroom_twr"])
			if spare <= 0.0:
				continue
			var share: float = channel_redistribution_budget_twr * spare / channel_healthy_headroom_twr
			var vane_id: StringName = record["id"]
			redistributed_by_vane[vane_id] = maxf(float(redistributed_by_vane[vane_id]), share)

	var actuators: Array[Dictionary] = []
	var pitch_capacity_torque_nm: float = 0.0
	var roll_capacity_torque_nm: float = 0.0
	var yaw_capacity_torque_nm: float = 0.0
	for record_value: Dictionary in actuator_records:
		var record: Dictionary = record_value
		var definition: VaneDefinition = record["definition"]
		var base_authority: float = float(record["base_authority_twr"])
		var redistributed: float = float(redistributed_by_vane.get(record["id"], 0.0))
		var effective_bound_twr: float = base_authority + redistributed
		var max_force_n: float = effective_bound_twr * reference_force_newtons * maneuver_multiplier
		var axis_local: Vector3 = record["axis_local"]
		var lever_arm: Vector3 = definition.local_position - center_of_mass_local
		var max_torque: Vector3 = lever_arm.cross(axis_local) * max_force_n
		if definition.get_control_weight(&"pitch") > 0:
			pitch_capacity_torque_nm += absf(max_torque.x)
		if definition.get_control_weight(&"roll") > 0:
			roll_capacity_torque_nm += absf(max_torque.z)
		if definition.get_control_weight(&"yaw") > 0:
			yaw_capacity_torque_nm += absf(max_torque.y)
		actuators.append({
			"id": record["id"],
			"position_local": definition.local_position,
			"axis_local": axis_local,
			"max_force_n": max_force_n,
			"control_weights": definition.control_weights,
			"enabled": true,
		})

	var maneuver_torque_local := Vector3(
		_last_pitch_command * maneuver_authority_fraction * pitch_capacity_torque_nm,
		-_last_yaw_command * yaw_capacity_torque_nm,
		-_last_roll_command * maneuver_authority_fraction * roll_capacity_torque_nm
	)
	var target_torque_local: Vector3 = main_datum_torque_local + maneuver_torque_local
	var wrench_reference: float = allocator_reference_force * characteristic_length_m
	if wrench_reference <= MINIMUM_FORCE_SQUARED:
		return

	var demands: Dictionary = {
		"translate_x": target_main_force_local.x / allocator_reference_force,
		"lift": target_main_force_local.y / allocator_reference_force,
		"main_thrust": -target_main_force_local.z / allocator_reference_force,
		"pitch": target_torque_local.x / wrench_reference,
		"yaw": -target_torque_local.y / wrench_reference,
		"roll": -target_torque_local.z / wrench_reference,
	}
	var allocation: Dictionary = VANE_ACTUATOR_ALLOCATOR_SCRIPT.allocate(
		actuators,
		demands,
		center_of_mass_local,
		allocator_reference_force,
		characteristic_length_m,
		128,
		MAIN_VECTOR_ALLOCATOR_REGULARIZATION
	)
	_last_main_vector_allocation = allocation
	if not bool(allocation.get("success", false)):
		_last_maneuver_allocation = allocation.duplicate(true)
		return

	_last_maneuver_allocation = allocation.duplicate(true)
	_last_maneuver_allocation["unified_eligible_actuator_count"] = int(
		allocation.get("eligible_actuator_count", 0)
	)
	_last_maneuver_allocation["eligible_actuator_count"] = _count_maneuver_eligible_outputs(
		allocation.get("actuator_outputs", [])
	)
	_last_maneuver_allocation["unified"] = true

	var achieved_force_local: Vector3 = allocation.get("achieved_force_local_n", Vector3.ZERO)
	_last_main_force = body_basis * target_main_force_local
	_last_total_force = body_basis * achieved_force_local
	var achieved_torque_local: Vector3 = allocation.get("achieved_torque_local_nm", Vector3.ZERO)
	_last_total_torque = body_basis * achieved_torque_local

	var maneuver_input_active: bool = (
		absf(_last_pitch_command) > 0.0001
		or absf(_last_roll_command) > 0.0001
		or absf(_last_yaw_command) > 0.0001
	)
	var main_reference_outputs: Dictionary = {}
	var main_reference_valid: bool = target_main_force_local.length_squared() <= MINIMUM_FORCE_SQUARED
	if maneuver_input_active and target_main_force_local.length_squared() > MINIMUM_FORCE_SQUARED:
		var main_reference_demands: Dictionary = {
			"translate_x": target_main_force_local.x / allocator_reference_force,
			"lift": target_main_force_local.y / allocator_reference_force,
			"main_thrust": -target_main_force_local.z / allocator_reference_force,
			"pitch": main_datum_torque_local.x / wrench_reference,
			"yaw": -main_datum_torque_local.y / wrench_reference,
			"roll": -main_datum_torque_local.z / wrench_reference,
		}
		var main_reference_allocation: Dictionary = VANE_ACTUATOR_ALLOCATOR_SCRIPT.allocate(
			actuators,
			main_reference_demands,
			center_of_mass_local,
			allocator_reference_force,
			characteristic_length_m,
			128,
			MAIN_VECTOR_ALLOCATOR_REGULARIZATION
		)
		if bool(main_reference_allocation.get("success", false)):
			var reference_force_error: Vector3 = main_reference_allocation.get(
				"force_residual_local_n", Vector3.ZERO
			)
			var reference_torque_error: Vector3 = main_reference_allocation.get(
				"torque_residual_local_nm", Vector3.ZERO
			)
			var force_tolerance: float = maxf(0.5, allocator_reference_force * 0.000001)
			var torque_tolerance: float = maxf(0.5, wrench_reference * 0.000001)
			main_reference_valid = (
				reference_force_error.length() <= force_tolerance
				and reference_torque_error.length() <= torque_tolerance
			)
			if main_reference_valid:
				for reference_output_value: Dictionary in main_reference_allocation.get("actuator_outputs", []):
					var reference_output: Dictionary = reference_output_value
					main_reference_outputs[StringName(str(reference_output.get("id", "")))] = float(
						reference_output.get("output", 0.0)
					)

	if target_main_force_local.length_squared() > MINIMUM_FORCE_SQUARED:
		if not maneuver_input_active or main_reference_valid:
			_last_force_vectors.append({
				"name": "MAIN FIELD VECTOR",
				"kind": "main",
				"force_world": body_basis * target_main_force_local,
				"application_point_world": _ship.global_position,
				"equivalent_resultant": true,
			})

	for output_value: Dictionary in allocation.get("actuator_outputs", []):
		var output_entry: Dictionary = output_value
		var output_id: StringName = StringName(str(output_entry.get("id", "")))
		var definition: VaneDefinition = _vane_controller.get_vane_definition(output_id)
		if not is_instance_valid(definition):
			continue
		var force_local: Vector3 = output_entry.get("force_local_n", Vector3.ZERO)
		var force_world: Vector3 = body_basis * force_local
		var application_offset_world: Vector3 = body_basis * definition.local_position
		var application_point_world: Vector3 = _ship.global_position + application_offset_world
		var torque_local: Vector3 = (definition.local_position - center_of_mass_local).cross(force_local)
		var torque_world: Vector3 = body_basis * torque_local
		_ship.apply_force(force_world, application_offset_world)
		var contribution: Dictionary = {
			"vane_id": output_id,
			"display_name": definition.display_name,
			"group_id": definition.group_id,
			"force_world": force_world,
			"torque_world": torque_world,
			"application_point_world": application_point_world,
			"lever_arm_world": body_basis * (definition.local_position - center_of_mass_local),
			"effective_authority_twr": float(output_entry.get("max_force_n", 0.0)) / maxf(reference_force_newtons * maneuver_multiplier, 0.0001),
			"allocation_weight": float(output_entry.get("control_weight", 0.0)),
			"actuator_output": float(output_entry.get("output", 0.0)),
		}
		_last_vane_contributions.append(contribution)
		if not maneuver_input_active:
			continue
		var effective_axis_local: Vector3 = _vane_controller.get_vane_effective_thrust_axis_local(output_id)
		var total_output: float = float(output_entry.get("output", 0.0))
		var main_output: float = float(main_reference_outputs.get(output_id, 0.0)) if main_reference_valid else 0.0
		var maneuver_output_delta: float = total_output - main_output
		var actuator_max_force_n: float = float(output_entry.get("max_force_n", 0.0))
		var maneuver_force_local: Vector3 = (
			effective_axis_local * actuator_max_force_n * maneuver_output_delta
		)
		var maneuver_noise_floor_n: float = maxf(0.05, actuator_max_force_n * 0.00001)
		if absf(maneuver_output_delta) <= 0.000005 or maneuver_force_local.length() <= maneuver_noise_floor_n:
			continue
		var maneuver_force_world: Vector3 = body_basis * maneuver_force_local
		var has_yaw: bool = definition.get_control_weight(&"yaw") > 0 and absf(_last_yaw_command) > 0.0001
		var has_pitch: bool = definition.get_control_weight(&"pitch") > 0 and absf(_last_pitch_command) > 0.0001
		var has_roll: bool = definition.get_control_weight(&"roll") > 0 and absf(_last_roll_command) > 0.0001
		var active_axis_count: int = (1 if has_yaw else 0) + (1 if has_pitch else 0) + (1 if has_roll else 0)
		var force_kind: String = "maneuver"
		if target_main_force_local.length_squared() > MINIMUM_FORCE_SQUARED and not main_reference_valid:
			force_kind = "combined"
		elif active_axis_count == 1:
			if has_pitch:
				force_kind = "pitch"
			elif has_roll:
				force_kind = "roll"
			else:
				force_kind = "yaw"
		elif active_axis_count == 0:
			force_kind = "combined"
		_last_force_vectors.append({
			"name": "%s %s" % [force_kind.to_upper(), String(output_id)],
			"kind": force_kind,
			"force_world": maneuver_force_world,
			"application_point_world": application_point_world,
			"equivalent_component": main_reference_valid,
			"actuator_output_delta": maneuver_output_delta,
		})

	if suppress_manual_main_vector:
		var residual_x_local_n: float = target_main_force_local.x - achieved_force_local.x
		if absf(residual_x_local_n) > 0.01:
			var residual_x_world: Vector3 = body_basis * Vector3(residual_x_local_n, 0.0, 0.0)
			_ship.apply_force(residual_x_world, Vector3.ZERO)
			_last_total_force += residual_x_world
			_last_force_vectors.append({
				"name": "SPACE ASSIST LATERAL",
				"kind": "main",
				"force_world": residual_x_world,
				"application_point_world": _ship.global_position,
			})
	_last_main_vector_allocation["unified"] = true
	_last_maneuver_allocation["unified"] = true


func _get_main_vector_channel_capacity_twr(channel: StringName, reference_axis_local: Vector3) -> float:
	var total_capacity_twr: float = 0.0
	for vane_id: StringName in _vane_controller.get_vane_ids():
		var definition: VaneDefinition = _vane_controller.get_vane_definition(vane_id)
		if not is_instance_valid(definition) or not definition.enabled or definition.get_control_weight(channel) <= 0:
			continue
		var effective_axis: Vector3 = _vane_controller.get_vane_effective_thrust_axis_local(vane_id)
		if effective_axis.length_squared() <= MINIMUM_FORCE_SQUARED:
			continue
		total_capacity_twr += (
			_vane_controller.get_vane_effective_authority_twr(vane_id)
			* absf(effective_axis.normalized().dot(reference_axis_local))
		)
	return total_capacity_twr


func _empty_main_vector_allocation() -> Dictionary:
	return {
		"success": true,
		"converged": true,
		"actuator_outputs": [],
		"eligible_actuator_count": 0,
		"normalized_error": 0.0,
		"target_force_local_n": Vector3.ZERO,
		"achieved_force_local_n": Vector3.ZERO,
		"force_residual_local_n": Vector3.ZERO,
		"target_torque_local_nm": Vector3.ZERO,
		"achieved_torque_local_nm": Vector3.ZERO,
		"torque_residual_local_nm": Vector3.ZERO,
	}


func _get_nominal_lift_channel_capacity_twr() -> float:
	if not is_instance_valid(_vane_controller):
		return 0.0
	var total: float = 0.0
	for vane_id: StringName in _vane_controller.get_vane_ids():
		var definition: VaneDefinition = _vane_controller.get_vane_definition(vane_id)
		if not is_instance_valid(definition) or not definition.enabled or definition.get_control_weight(&"lift") <= 0:
			continue
		var nominal_axis: Vector3 = definition.local_thrust_axis.normalized()
		total += definition.nominal_authority_twr * absf(nominal_axis.dot(Vector3.UP))
	return total


func _get_effective_lift_channel_capacity_twr() -> float:
	return _get_main_vector_channel_capacity_twr(&"lift", Vector3.UP)


func _get_active_maneuver_actuator_count() -> int:
	if not is_instance_valid(_vane_controller):
		return 0
	var count: int = 0
	for output_value: Dictionary in _last_maneuver_allocation.get("actuator_outputs", []):
		var output_entry: Dictionary = output_value
		var vane_id: StringName = StringName(str(output_entry.get("id", "")))
		var definition: VaneDefinition = _vane_controller.get_vane_definition(vane_id)
		if not is_instance_valid(definition):
			continue
		var eligible: bool = (
			(absf(_last_pitch_command) > 0.0001 and definition.get_control_weight(&"pitch") > 0)
			or (absf(_last_roll_command) > 0.0001 and definition.get_control_weight(&"roll") > 0)
			or (absf(_last_yaw_command) > 0.0001 and definition.get_control_weight(&"yaw") > 0)
		)
		if eligible:
			count += 1
	return count


func _count_maneuver_eligible_outputs(output_values: Array) -> int:
	if not is_instance_valid(_vane_controller):
		return 0
	var count: int = 0
	for output_value: Variant in output_values:
		if typeof(output_value) != TYPE_DICTIONARY:
			continue
		var output_entry: Dictionary = output_value
		var vane_id: StringName = StringName(str(output_entry.get("id", "")))
		var definition: VaneDefinition = _vane_controller.get_vane_definition(vane_id)
		if not is_instance_valid(definition):
			continue
		var eligible: bool = (
			(absf(_last_pitch_command) > 0.0001 and definition.get_control_weight(&"pitch") > 0)
			or (absf(_last_roll_command) > 0.0001 and definition.get_control_weight(&"roll") > 0)
			or (absf(_last_yaw_command) > 0.0001 and definition.get_control_weight(&"yaw") > 0)
		)
		if eligible:
			count += 1
	return count


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
		_get_nominal_lift_channel_capacity_twr()
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


func get_telemetry() -> Dictionary:
	var local_gravity_magnitude: float = _get_gravity_vector_world().length() if is_instance_valid(_ship) else 0.0
	var bottom_effective_twr: float = _get_effective_lift_channel_capacity_twr()
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
		"actuator_allocator": _last_main_vector_allocation.duplicate(true),
		"maneuver_allocator": _last_maneuver_allocation.duplicate(true),
		"maneuver_allocator_active_actuators": _get_active_maneuver_actuator_count(),
		"maneuver_allocator_normalized_error": float(_last_maneuver_allocation.get("normalized_error", 0.0)),
		"main_vector_allocator": _last_main_vector_allocation.duplicate(true),
		"main_vector_allocator_active_actuators": int(_last_main_vector_allocation.get("eligible_actuator_count", 0)),
		"main_vector_allocator_normalized_error": float(_last_main_vector_allocation.get("normalized_error", 0.0)),
		"reference_gravity_mps2": reference_gravity_mps2,
	}
	telemetry.merge(vane_telemetry, true)
	return telemetry
