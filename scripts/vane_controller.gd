extends Node
class_name VaneController

## Owns shared vane definitions, per-ship runtime condition, and thermal simulation.
## This script calculates group resultants, weighted application points, and thermal/wear
## progression. It never applies forces directly to the ship rigid body.

class VaneRuntimeState:
	extends RefCounted
	var integrity: float = 1.0
	var failed: bool = false
	var alignment_offset_degrees: Vector3 = Vector3.ZERO
	var temperature_celsius: float = -10.0
	var load_fraction: float = 0.0
	var wear_rate_per_second: float = 0.0
	var thermal_status: StringName = &"COLD_STRAIN"
	var min_green_celsius: float = 60.0
	var max_green_celsius: float = 160.0
	var sputter_active: bool = false
	var sputter_timer: float = 0.0

	func reset(default_temp: float = -10.0) -> void:
		integrity = 1.0
		failed = false
		alignment_offset_degrees = Vector3.ZERO
		temperature_celsius = default_temp
		load_fraction = 0.0
		wear_rate_per_second = 0.0
		thermal_status = &"COLD_STRAIN"
		min_green_celsius = 60.0
		max_green_celsius = 160.0
		sputter_active = false
		sputter_timer = 0.0

	func authority_multiplier() -> float:
		if failed:
			return 0.0
		var base_mult: float = clampf(integrity, 0.0, 1.0)
		if sputter_active:
			base_mult *= 0.65
		# Cold temperature authority clamp:
		# Below nominal 60°C, cold crystal matrix cannot deliver full 100% force
		if temperature_celsius < 60.0:
			var warmup_progress: float = clampf((temperature_celsius - (-10.0)) / (60.0 - (-10.0)), 0.0, 1.0)
			var cold_clamp: float = lerpf(0.70, 1.0, warmup_progress)
			base_mult = minf(base_mult, cold_clamp)
		elif temperature_celsius > 180.0 and temperature_celsius <= 230.0:
			# Temporary overdrive output boost (1.05x) at the cost of rapid heat and wear
			base_mult *= 1.05
		return base_mult


@export_category("Vane configuration")
## Resources are configuration only. Runtime state is always local to this ship.
@export var vane_definitions: Array[Resource] = []

@export_category("Thermal & Degradation (Phase 2S)")
## Minimum nominal operating temperature for full 100% power without cold strain.
@export_range(20.0, 100.0, 1.0) var nominal_warmup_temp_c: float = 60.0
## Maximum continuous operating temperature before overheating starts.
@export_range(120.0, 240.0, 5.0) var max_continuous_temp_c: float = 180.0
## Critical threshold where sputtering, drift, and accelerated failure occur.
@export_range(200.0, 300.0, 5.0) var critical_temp_c: float = 230.0
## Baseline heating rate when the repulsorlift field is active at idle (°C/s).
@export_range(0.5, 10.0, 0.1) var base_online_heat_rate: float = 3.0
## Heating rate coefficient at 100% vane power (°C/s).
@export_range(5.0, 40.0, 0.5) var heat_rate_coefficient: float = 22.0
## Radiator and ambient cooling coefficient (1/s).
@export_range(0.01, 0.20, 0.005) var cooling_coefficient: float = 0.05
## Multiplier for quadratic degradation: wear = base + k * (deltaT)^2 * (load^2).
@export_range(0.000001, 0.0001, 0.000001) var quadratic_wear_coefficient: float = 0.000008
## Base operating wear per second in the green zone.
@export_range(0.0, 0.0001, 0.000001) var base_wear_rate_per_second: float = 0.000002

const MINIMUM_GROUP_AUTHORITY: float = 0.000001
const ALIGNMENT_DEGREES_TO_RADIANS: float = PI / 180.0
const MINIMUM_FORCE_WEIGHT: float = 0.000001

var _definitions_by_id: Dictionary = {}
var _runtime_states_by_id: Dictionary = {}
var _configuration_errors: PackedStringArray = PackedStringArray()
var _configuration_valid: bool = false


func _enter_tree() -> void:
	_rebuild_runtime_states()


## Builds per-instance state without modifying the shared Resource definitions.
func _rebuild_runtime_states() -> void:
	_definitions_by_id.clear()
	_runtime_states_by_id.clear()
	_configuration_errors.clear()

	for resource in vane_definitions:
		if not resource is VaneDefinition:
			_configuration_errors.append("Vane entry is missing or is not a VaneDefinition Resource.")
			continue
		var definition := resource as VaneDefinition
		if definition.vane_id.is_empty():
			_configuration_errors.append("A vane definition has an empty vane_id.")
			continue
		if _definitions_by_id.has(definition.vane_id):
			_configuration_errors.append("Duplicate vane_id: %s" % String(definition.vane_id))
			continue
		if definition.group_id.is_empty():
			_configuration_errors.append("Vane %s has an empty group_id." % String(definition.vane_id))
			continue
		if definition.nominal_authority_twr < 0.0:
			_configuration_errors.append("Vane %s has negative nominal authority." % String(definition.vane_id))
			continue

		_definitions_by_id[definition.vane_id] = definition
		_runtime_states_by_id[definition.vane_id] = VaneRuntimeState.new()

	_configuration_valid = _configuration_errors.is_empty() and not _definitions_by_id.is_empty()
	if _definitions_by_id.is_empty():
		_configuration_errors.append("No valid vane definitions were registered.")
		_configuration_valid = false


func get_vane_count() -> int:
	return _definitions_by_id.size()


func get_healthy_vane_count() -> int:
	var healthy_count: int = 0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		if definition.enabled and not state.failed and state.integrity >= 0.999:
			healthy_count += 1
	return healthy_count


func is_configuration_valid() -> bool:
	return _configuration_valid


func get_configuration_errors() -> PackedStringArray:
	return _configuration_errors.duplicate()


func get_vane_ids_for_group(group_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if definition.enabled and definition.group_id == group_id:
			result.append(vane_id)
	return result


func get_group_nominal_authority_twr(group_id: StringName) -> float:
	var total_authority: float = 0.0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if definition.enabled and definition.group_id == group_id:
			total_authority += definition.nominal_authority_twr
	return total_authority


## Effective authority includes disabled/failing/partially damaged/temperature-clamped runtime state.
func get_group_effective_authority_twr(group_id: StringName) -> float:
	var total_authority: float = 0.0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled or definition.group_id != group_id:
			continue
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		total_authority += definition.nominal_authority_twr * state.authority_multiplier()
	return total_authority


## Convenience wrapper: calculate all enabled vanes belonging to one logical group.
func calculate_group_resultant(
		group_id: StringName,
		force_direction_world: Vector3,
		force_newtons_per_twr: float,
		ship_global_transform: Transform3D,
		center_of_mass_local: Vector3,
		redistribution_fraction: float = 0.0,
		maximum_output_multiplier: float = 1.2) -> Dictionary:
	return calculate_vane_set_resultant(
		get_vane_ids_for_group(group_id),
		force_direction_world,
		force_newtons_per_twr,
		ship_global_transform,
		center_of_mass_local,
		redistribution_fraction,
		maximum_output_multiplier
	)


## Calculate a resultant for an arbitrary set of vane IDs.
## The returned application point is the force-magnitude-weighted centroid. For
## a group whose vanes share a direction, applying net_force at this point
## reproduces the sum of the individual vane moments exactly.
func calculate_vane_set_resultant(
		vane_ids: Array[StringName],
		force_direction_world: Vector3,
		force_newtons_per_twr: float,
		ship_global_transform: Transform3D,
		center_of_mass_local: Vector3,
		redistribution_fraction: float = 0.0,
		maximum_output_multiplier: float = 1.2) -> Dictionary:
	var net_force: Vector3 = Vector3.ZERO
	var net_torque: Vector3 = Vector3.ZERO
	var contributions: Array[Dictionary] = []
	var weighted_application_point: Vector3 = Vector3.ZERO
	var total_force_weight: float = 0.0
	var nominal_authority_twr: float = 0.0
	var effective_authority_twr: float = 0.0
	var seen_ids: Dictionary = {}
	var valid_vanes: Array[Dictionary] = []
	var total_damage_shortfall_twr: float = 0.0
	var total_healthy_headroom_twr: float = 0.0

	var body_basis: Basis = ship_global_transform.basis.orthonormalized()
	var body_origin: Vector3 = ship_global_transform.origin
	var center_of_mass_world: Vector3 = body_origin + body_basis * center_of_mass_local

	if force_direction_world.length_squared() <= MINIMUM_GROUP_AUTHORITY:
		return _make_resultant(
			net_force, net_torque, contributions, nominal_authority_twr,
			effective_authority_twr, center_of_mass_world
		)

	var local_reference_direction: Vector3 = body_basis.inverse() * force_direction_world.normalized()
	var non_negative_force_scale: float = maxf(force_newtons_per_twr, 0.0)
	var safe_redistribution_fraction: float = clampf(redistribution_fraction, 0.0, 1.0)
	var safe_maximum_multiplier: float = clampf(maximum_output_multiplier, 1.0, 1.5)

	# First measure the group's damage deficit and spare capacity. Only healthy,
	# non-failed vanes can receive redistributed output; damaged vanes are not
	# allowed to hide their own condition by amplifying themselves.
	for vane_id in vane_ids:
		if seen_ids.has(vane_id) or not _definitions_by_id.has(vane_id):
			continue
		seen_ids[vane_id] = true
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled:
			continue
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		var base_authority: float = definition.nominal_authority_twr * state.authority_multiplier()
		var spare_headroom: float = 0.0
		if not state.failed and state.integrity >= 0.999:
			spare_headroom = definition.nominal_authority_twr * (safe_maximum_multiplier - 1.0)
		total_damage_shortfall_twr += maxf(definition.nominal_authority_twr - base_authority, 0.0)
		total_healthy_headroom_twr += spare_headroom
		valid_vanes.append({
			"definition": definition,
			"state": state,
			"base_authority_twr": base_authority,
			"spare_headroom_twr": spare_headroom,
		})

	var redistribution_budget_twr: float = minf(
		total_damage_shortfall_twr * safe_redistribution_fraction,
		total_healthy_headroom_twr
	)

	for vane_entry_value in valid_vanes:
		var vane_entry: Dictionary = vane_entry_value
		var definition := vane_entry["definition"] as VaneDefinition
		var state := vane_entry["state"] as VaneRuntimeState
		var base_authority: float = float(vane_entry["base_authority_twr"])
		var spare_headroom: float = float(vane_entry["spare_headroom_twr"])
		var redistributed_authority: float = 0.0
		if total_healthy_headroom_twr > MINIMUM_FORCE_WEIGHT and spare_headroom > 0.0:
			redistributed_authority = redistribution_budget_twr * spare_headroom / total_healthy_headroom_twr
		var effective_vane_twr: float = base_authority + redistributed_authority

		var alignment_radians: Vector3 = state.alignment_offset_degrees * ALIGNMENT_DEGREES_TO_RADIANS
		var alignment_basis := Basis.from_euler(alignment_radians)
		var vane_direction_world: Vector3 = (
			body_basis * alignment_basis * local_reference_direction
		).normalized()

		var force_magnitude: float = non_negative_force_scale * effective_vane_twr
		var vane_force: Vector3 = vane_direction_world * force_magnitude
		var application_point_world: Vector3 = body_origin + body_basis * definition.local_position
		var lever_arm_world: Vector3 = application_point_world - center_of_mass_world
		var vane_torque: Vector3 = lever_arm_world.cross(vane_force)

		nominal_authority_twr += definition.nominal_authority_twr
		effective_authority_twr += effective_vane_twr
		net_force += vane_force
		net_torque += vane_torque

		if force_magnitude > MINIMUM_FORCE_WEIGHT:
			weighted_application_point += application_point_world * force_magnitude
			total_force_weight += force_magnitude

		contributions.append({
			"vane_id": definition.vane_id,
			"display_name": definition.display_name,
			"group_id": definition.group_id,
			"integrity": state.integrity,
			"failed": state.failed,
			"effective_authority_twr": effective_vane_twr,
			"base_effective_authority_twr": base_authority,
			"redistributed_authority_twr": redistributed_authority,
			"force_world": vane_force,
			"torque_world": vane_torque,
			"application_point_world": application_point_world,
			"lever_arm_world": lever_arm_world,
		})

	var effective_application_point_world: Vector3 = center_of_mass_world
	if total_force_weight > MINIMUM_FORCE_WEIGHT:
		effective_application_point_world = weighted_application_point / total_force_weight

	return _make_resultant(
		net_force, net_torque, contributions, nominal_authority_twr,
		effective_authority_twr, effective_application_point_world
	)


func _make_resultant(
		net_force: Vector3,
		net_torque: Vector3,
		contributions: Array[Dictionary],
		nominal_authority_twr: float,
		effective_authority_twr: float,
		effective_application_point_world: Vector3) -> Dictionary:
	return {
		"net_force": net_force,
		"net_torque": net_torque,
		"contributions": contributions,
		"nominal_authority_twr": nominal_authority_twr,
		"effective_authority_twr": effective_authority_twr,
		"effective_application_point_world": effective_application_point_world,
	}


## Phase 2S: Steps temperature, green zone limits, and quadratic degradation for all vanes.
func update_thermal_simulation(
		delta: float,
		ambient_temperature_celsius: float,
		field_online: bool,
		main_power_output: float,
		vector_angle_degrees: float,
		pitch_command: float = 0.0,
		roll_command: float = 0.0,
		yaw_command: float = 0.0) -> void:
	if delta <= 0.00001:
		return

	var lift_blend: float = clampf(vector_angle_degrees / 90.0, 0.0, 1.0)
	var forward_blend: float = 1.0 - lift_blend

	# Calculate per-vane demanded load from main vector plus maneuver inputs
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		if not definition.enabled:
			state.load_fraction = 0.0
			continue

		var load: float = 0.0
		if field_online:
			match definition.group_id:
				&"bottom_front":
					var base_lift: float = main_power_output * lift_blend
					# Pitch-down increases front bottom demand
					var pitch_extra: float = -pitch_command * 0.35
					# Roll demands
					var roll_extra: float = (roll_command if vane_id == &"bottom_front_left" else -roll_command) * 0.35
					load = clampf(base_lift + maxf(pitch_extra, 0.0) + maxf(roll_extra, 0.0), 0.0, 1.25)
				&"bottom_rear":
					var base_lift: float = main_power_output * lift_blend
					# Pitch-up increases rear bottom demand
					var pitch_extra: float = pitch_command * 0.35
					var roll_extra: float = (roll_command if vane_id == &"bottom_rear_left" else -roll_command) * 0.35
					load = clampf(base_lift + maxf(pitch_extra, 0.0) + maxf(roll_extra, 0.0), 0.0, 1.25)
				&"main_rear":
					load = clampf(main_power_output * forward_blend, 0.0, 1.25)
				&"side_left":
					var yaw_left: float = -yaw_command if yaw_command < 0.0 else 0.0
					load = clampf(yaw_left, 0.0, 1.25)
				&"side_right":
					var yaw_right: float = yaw_command if yaw_command > 0.0 else 0.0
					load = clampf(yaw_right, 0.0, 1.25)

		state.load_fraction = load
		_step_individual_vane_thermal(state, definition, delta, ambient_temperature_celsius, field_online)


func _step_individual_vane_thermal(
		state: VaneRuntimeState,
		_definition: VaneDefinition,
		delta: float,
		ambient_temperature_celsius: float,
		field_online: bool) -> void:
	var load: float = state.load_fraction

	# Heat Generation: base online heat + k_heat * (load^2)
	var heat_in: float = 0.0
	if field_online:
		heat_in = base_online_heat_rate + heat_rate_coefficient * (load * load)

	# Heat Dissipation (Radiators + ambient convective cooling)
	var heat_out: float = cooling_coefficient * (state.temperature_celsius - ambient_temperature_celsius)

	var d_temp: float = (heat_in - heat_out) * delta
	state.temperature_celsius += d_temp

	# Calculate Green Zone boundaries for this load level
	state.min_green_celsius = nominal_warmup_temp_c * pow(load, 0.7)
	state.max_green_celsius = max_continuous_temp_c - (load * 20.0)

	var delta_from_green: float = 0.0
	if state.temperature_celsius < state.min_green_celsius:
		state.thermal_status = &"COLD_STRAIN"
		delta_from_green = state.min_green_celsius - state.temperature_celsius
	elif state.temperature_celsius > critical_temp_c:
		state.thermal_status = &"CRITICAL"
		delta_from_green = state.temperature_celsius - state.max_green_celsius
	elif state.temperature_celsius > state.max_green_celsius:
		state.thermal_status = &"OVERHEAT"
		delta_from_green = state.temperature_celsius - state.max_green_celsius
	else:
		state.thermal_status = &"GREEN_ZONE"
		delta_from_green = 0.0

	# Quadratic degradation rate:
	# Inside green zone: minimal base wear
	# Outside green zone: base + k * (deltaT)^2 * (load^2)
	state.wear_rate_per_second = base_wear_rate_per_second
	if delta_from_green > 0.0 and load > 0.001:
		state.wear_rate_per_second += quadratic_wear_coefficient * (delta_from_green * delta_from_green) * (load * load)

	var wear_amount: float = state.wear_rate_per_second * delta
	state.integrity = maxf(0.0, state.integrity - wear_amount)

	if state.integrity <= 0.0001:
		state.failed = true
		state.integrity = 0.0

	# Sputtering under critical temperature or severe degradation
	if state.temperature_celsius > critical_temp_c or state.integrity < 0.20:
		state.sputter_timer -= delta
		if state.sputter_timer <= 0.0:
			state.sputter_active = not state.sputter_active
			state.sputter_timer = randf_range(0.15, 0.45)
	else:
		state.sputter_active = false
		state.sputter_timer = 0.0


func set_vane_integrity(vane_id: StringName, integrity: float) -> bool:
	if not _runtime_states_by_id.has(vane_id):
		return false
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	state.integrity = clampf(integrity, 0.0, 1.0)
	if state.integrity > 0.0:
		state.failed = false
	return true


func set_vane_temperature(vane_id: StringName, temperature_celsius: float) -> bool:
	if not _runtime_states_by_id.has(vane_id):
		return false
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	state.temperature_celsius = temperature_celsius
	return true


func get_vane_temperature(vane_id: StringName) -> float:
	if not _runtime_states_by_id.has(vane_id):
		return -10.0
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	return state.temperature_celsius


func get_vane_thermal_status(vane_id: StringName) -> StringName:
	if not _runtime_states_by_id.has(vane_id):
		return &"UNKNOWN"
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	return state.thermal_status


func get_vane_wear_rate(vane_id: StringName) -> float:
	if not _runtime_states_by_id.has(vane_id):
		return 0.0
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	return state.wear_rate_per_second


func set_vane_failed(vane_id: StringName, failed: bool) -> bool:
	if not _runtime_states_by_id.has(vane_id):
		return false
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	state.failed = failed
	return true


func set_vane_alignment_offset(vane_id: StringName, offset_degrees: Vector3) -> bool:
	if not _runtime_states_by_id.has(vane_id):
		return false
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	state.alignment_offset_degrees = offset_degrees
	return true


func reset_all_vanes(default_temperature: float = -10.0) -> void:
	for vane_id in _runtime_states_by_id:
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		state.reset(default_temperature)


func get_telemetry() -> Dictionary:
	var vane_states: Array[Dictionary] = []
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		vane_states.append({
			"vane_id": definition.vane_id,
			"display_name": definition.display_name,
			"group_id": definition.group_id,
			"enabled": definition.enabled,
			"local_position": definition.local_position,
			"nominal_authority_twr": definition.nominal_authority_twr,
			"effective_authority_twr": definition.nominal_authority_twr * state.authority_multiplier(),
			"integrity": state.integrity,
			"failed": state.failed,
			"alignment_offset_degrees": state.alignment_offset_degrees,
			"temperature_celsius": state.temperature_celsius,
			"load_fraction": state.load_fraction,
			"thermal_status": state.thermal_status,
			"wear_rate_per_second": state.wear_rate_per_second,
			"min_green_celsius": state.min_green_celsius,
			"max_green_celsius": state.max_green_celsius,
			"sputter_active": state.sputter_active,
		})
	return {
		"vane_count": get_vane_count(),
		"vane_healthy_count": get_healthy_vane_count(),
		"vane_configuration_valid": _configuration_valid,
		"vane_configuration_errors": get_configuration_errors(),
		"vane_states": vane_states,
		"thermal_nominal_warmup_temp_c": nominal_warmup_temp_c,
		"thermal_max_continuous_temp_c": max_continuous_temp_c,
		"thermal_critical_temp_c": critical_temp_c,
	}
