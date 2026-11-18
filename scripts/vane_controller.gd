extends Node
class_name VaneController

## Per-ship actuator registry, 6-DOF control metadata, convective thermal
## simulation with Knudsen convective_efficiency taper, tiered integrity
## degradation (75% / 50% / 25%), and failure injection.

class VaneRuntimeState:
	var integrity: float = 1.0
	var failed: bool = false
	var alignment_offset_degrees: Vector3 = Vector3.ZERO
	var dynamic_misalignment_degrees: Vector3 = Vector3.ZERO
	var temperature_celsius: float = -10.0
	var load_fraction: float = 0.0
	var thermal_status: StringName = &"COLD_STRAIN"
	var wear_rate_per_second: float = 0.0
	var min_green_celsius: float = 0.0
	var max_green_celsius: float = 180.0
	var sputter_active: bool = false
	var sputter_output_scale: float = 1.0
	var sputter_timer: float = 0.0
	var misalignment_timer: float = 0.0
	var radiator_cooling_per_second: float = 0.05

	func authority_multiplier() -> float:
		if failed:
			return 0.0
		var temp_clamp: float = 1.0
		if temperature_celsius < 10.0:
			temp_clamp = clampf(0.70 + 0.30 * ((temperature_celsius + 10.0) / 20.0), 0.70, 1.0)
		var cond: float = clampf(integrity, 0.0, 1.0) * temp_clamp
		if sputter_active:
			cond *= clampf(sputter_output_scale, 0.0, 1.0)
		return cond

	func reset(default_temp: float = -10.0) -> void:
		integrity = 1.0
		failed = false
		alignment_offset_degrees = Vector3.ZERO
		dynamic_misalignment_degrees = Vector3.ZERO
		temperature_celsius = default_temp
		load_fraction = 0.0
		thermal_status = &"COLD_STRAIN"
		wear_rate_per_second = 0.0
		sputter_active = false
		sputter_output_scale = 1.0
		sputter_timer = 0.0
		misalignment_timer = 0.0

## Configuration only. Runtime state is always local to this ship instance.
@export var vane_definitions: Array[Resource] = []

@export_category("Thermal & Degradation (Legacy fallback / JSON overridable)")
@export_range(20.0, 100.0, 1.0) var nominal_warmup_temp_c: float = 60.0
@export_range(120.0, 260.0, 5.0) var max_continuous_temp_c: float = 180.0
@export_range(180.0, 320.0, 5.0) var critical_temp_c: float = 230.0
@export_range(0.5, 10.0, 0.1) var base_online_heat_rate: float = 3.0
@export_range(5.0, 40.0, 0.5) var heat_rate_coefficient: float = 22.0
@export_range(0.5, 3.0, 0.05) var heat_load_exponent: float = 2.0
@export_range(0.01, 0.25, 0.005) var cooling_coefficient: float = 0.05
@export_range(0.000001, 0.001, 0.000001) var quadratic_wear_coefficient: float = 0.000008
@export_range(0.0, 0.001, 0.000001) var base_wear_rate_per_second: float = 0.000002

@export_category("Phase 3G Radiator & Tiered Integrity")
@export var tiered_integrity_enabled: bool = false
@export var random_failures_enabled: bool = true
@export var air_convection_enabled: bool = false
@export_range(0.005, 0.25, 0.002) var radiator_vacuum_cooling_coeff: float = 0.029
@export_range(0.0, 0.25, 0.002) var radiator_air_cooling_coeff: float = 0.042
@export_range(0.2, 1.5, 0.05) var air_density_exponent: float = 0.65
@export_range(0.0, 2.5, 0.05) var airspeed_cooling_gain: float = 1.35
@export_range(50.0, 1000.0, 10.0) var airspeed_reference_mps: float = 300.0
@export_range(120.0, 260.0, 5.0) var high_temp_radiation_threshold_c: float = 180.0
@export_range(0.0, 0.15, 0.005) var high_temp_radiation_bonus: float = 0.011

@export_range(0.0, 0.01, 0.00001) var overheat_wear_rate_per_second: float = 0.00018
@export_range(0.0, 0.01, 0.00001) var critical_wear_rate_per_second: float = 0.00043
@export_range(0.0, 0.005, 0.00001) var cold_strain_wear_coefficient: float = 0.000025
@export_range(0.0, 8.0, 0.1) var below_50_wear_exp_gain: float = 2.5

@export_range(0.5, 0.9, 0.05) var worn_threshold: float = 0.75
@export_range(0.3, 0.7, 0.05) var degraded_threshold: float = 0.50
@export_range(0.1, 0.45, 0.05) var critical_threshold: float = 0.25
@export_range(0.6, 1.0, 0.01) var twr_at_50_percent: float = 0.88
@export_range(0.4, 0.9, 0.01) var twr_at_25_percent: float = 0.68
@export_range(0.2, 0.7, 0.01) var twr_floor_above_zero: float = 0.48
@export_range(0.0, 0.9, 0.02) var max_response_lag_multiplier: float = 0.72
@export_range(0.0, 2.0, 0.02) var max_fault_chance_per_second_at_75_to_50: float = 0.22
@export_range(0.0, 5.0, 0.05) var max_fault_chance_per_second_below_25: float = 1.40
@export_range(0.0, 25.0, 0.5) var max_misalignment_degrees: float = 8.5
@export_range(0.05, 1.0, 0.05) var startup_min_reliability_below_25: float = 0.35

const MINIMUM_GROUP_AUTHORITY: float = 0.000001
const ALIGNMENT_DEGREES_TO_RADIANS: float = PI / 180.0
const MINIMUM_FORCE_WEIGHT: float = 0.000001
const MAX_THERMAL_LOAD_FRACTION: float = 1.5
const SEA_LEVEL_AIR_DENSITY_REF: float = 1.225
const VALID_CONTROL_CHANNELS: Array[StringName] = [
	&"pitch", &"roll", &"yaw", &"lift", &"main_thrust",
	&"translate_x", &"translate_y", &"translate_z"
]

var _definitions_by_id: Dictionary = {}
var _runtime_states_by_id: Dictionary = {}
var _configuration_errors: PackedStringArray = PackedStringArray()
var _configuration_valid: bool = false
var _last_air_density_kg_m3: float = 0.0
var _last_airspeed_mps: float = 0.0
var _last_convective_efficiency: float = 1.0
var _last_convective_factor: float = 1.0
var _last_effective_cooling_per_s: float = 0.05
var _last_ambient_temperature_c: float = -10.0


func _enter_tree() -> void:
	_rebuild_runtime_states()


func apply_ship_definition(definition: ShipDefinition) -> void:
	if definition == null:
		return
	if not definition.vanes.is_empty():
		var updated_definitions: Array[Resource] = []
		for vane_data: Dictionary in definition.vanes:
			var id_str: String = str(vane_data.get("id", ""))
			if id_str.is_empty():
				continue
			var id_sn := StringName(id_str)
			var cloned_def: VaneDefinition = null
			if _definitions_by_id.has(id_sn):
				cloned_def = (_definitions_by_id[id_sn] as VaneDefinition).duplicate(true) as VaneDefinition
			else:
				cloned_def = VaneDefinition.new()
				cloned_def.vane_id = id_sn
				var group_str: String = str(vane_data.get("group", ""))
				if group_str == "main_rear" or group_str.begins_with("side_"):
					cloned_def.axis_family = &"horizontal_main"
					cloned_def.local_thrust_axis = Vector3.BACK
				else:
					cloned_def.axis_family = &"vertical"
					cloned_def.local_thrust_axis = Vector3.UP
				if vane_data.has("local_position_m") and vane_data["local_position_m"] is Array:
					var lp: Array = vane_data["local_position_m"]
					if lp.size() == 3:
						cloned_def.local_position = Vector3(float(lp[0]), float(lp[1]), float(lp[2]))
			cloned_def.display_name = str(vane_data.get("display_name", cloned_def.display_name))
			cloned_def.group_id = StringName(str(vane_data.get("group", String(cloned_def.group_id))))
			cloned_def.nominal_authority_twr = maxf(float(vane_data.get("authority_twr", cloned_def.nominal_authority_twr)), 0.0)
			cloned_def.enabled = bool(vane_data.get("enabled", cloned_def.enabled))
			if vane_data.has("control_weights") and vane_data["control_weights"] is Dictionary:
				cloned_def.control_weights = (vane_data["control_weights"] as Dictionary).duplicate(true)
			elif cloned_def.control_weights.is_empty():
				if cloned_def.group_id == &"main_rear":
					cloned_def.control_weights = {"pitch": 0, "roll": 0, "yaw": 0, "lift": 0, "main_thrust": 100, "translate_x": 0, "translate_y": 0, "translate_z": 0}
				elif String(cloned_def.group_id).begins_with("side_"):
					cloned_def.control_weights = {"pitch": 0, "roll": 0, "yaw": 100, "lift": 0, "main_thrust": 0, "translate_x": 0, "translate_y": 0, "translate_z": 0}
				else:
					cloned_def.control_weights = {"pitch": 100, "roll": 100, "yaw": 0, "lift": 100, "main_thrust": 0, "translate_x": 0, "translate_y": 0, "translate_z": 0}
			updated_definitions.append(cloned_def)
		if not updated_definitions.is_empty():
			configure_vanes(updated_definitions)

	var ti: Dictionary = definition.thermal_and_integrity
	if not ti.is_empty() and bool(ti.get("enabled", true)):
		tiered_integrity_enabled = true
		air_convection_enabled = true
		nominal_warmup_temp_c = float(ti.get("nominal_warmup_temp_c", nominal_warmup_temp_c))
		max_continuous_temp_c = float(ti.get("max_continuous_temp_c", max_continuous_temp_c))
		critical_temp_c = float(ti.get("critical_temp_c", critical_temp_c))
		base_online_heat_rate = float(ti.get("base_online_heat_rate", base_online_heat_rate))
		heat_rate_coefficient = float(ti.get("heat_rate_coefficient", heat_rate_coefficient))
		heat_load_exponent = float(ti.get("load_exponent", heat_load_exponent))
		if ti.has("radiator") and ti["radiator"] is Dictionary:
			var rad: Dictionary = ti["radiator"]
			radiator_vacuum_cooling_coeff = float(rad.get("vacuum_cooling_coeff", radiator_vacuum_cooling_coeff))
			radiator_air_cooling_coeff = float(rad.get("air_cooling_coeff", radiator_air_cooling_coeff))
			air_density_exponent = float(rad.get("air_density_exponent", air_density_exponent))
			airspeed_cooling_gain = float(rad.get("airspeed_cooling_gain", airspeed_cooling_gain))
			airspeed_reference_mps = maxf(float(rad.get("airspeed_reference_mps", airspeed_reference_mps)), 10.0)
			high_temp_radiation_threshold_c = float(rad.get("high_temp_radiation_threshold_c", high_temp_radiation_threshold_c))
			high_temp_radiation_bonus = float(rad.get("high_temp_radiation_bonus", high_temp_radiation_bonus))
		if ti.has("wear") and ti["wear"] is Dictionary:
			var wear: Dictionary = ti["wear"]
			base_wear_rate_per_second = float(wear.get("base_wear_rate_per_second", base_wear_rate_per_second))
			overheat_wear_rate_per_second = float(wear.get("overheat_wear_rate_per_second", overheat_wear_rate_per_second))
			critical_wear_rate_per_second = float(wear.get("critical_wear_rate_per_second", critical_wear_rate_per_second))
			cold_strain_wear_coefficient = float(wear.get("cold_strain_wear_coefficient", cold_strain_wear_coefficient))
			below_50_wear_exp_gain = float(wear.get("below_50_wear_exp_gain", below_50_wear_exp_gain))
		if ti.has("integrity_tiers") and ti["integrity_tiers"] is Dictionary:
			var tiers: Dictionary = ti["integrity_tiers"]
			worn_threshold = clampf(float(tiers.get("worn_threshold", worn_threshold)), 0.1, 0.99)
			degraded_threshold = clampf(float(tiers.get("degraded_threshold", degraded_threshold)), 0.05, worn_threshold)
			critical_threshold = clampf(float(tiers.get("critical_threshold", critical_threshold)), 0.01, degraded_threshold)
			twr_at_50_percent = clampf(float(tiers.get("twr_at_50_percent", twr_at_50_percent)), 0.3, 1.0)
			twr_at_25_percent = clampf(float(tiers.get("twr_at_25_percent", twr_at_25_percent)), 0.2, twr_at_50_percent)
			twr_floor_above_zero = clampf(float(tiers.get("twr_floor_above_zero", twr_floor_above_zero)), 0.1, twr_at_25_percent)
			max_response_lag_multiplier = clampf(float(tiers.get("max_response_lag_multiplier", max_response_lag_multiplier)), 0.0, 0.9)
			max_fault_chance_per_second_at_75_to_50 = maxf(float(tiers.get("max_fault_chance_per_second_at_75_to_50", max_fault_chance_per_second_at_75_to_50)), 0.0)
			max_fault_chance_per_second_below_25 = maxf(float(tiers.get("max_fault_chance_per_second_below_25", max_fault_chance_per_second_below_25)), 0.0)
			max_misalignment_degrees = maxf(float(tiers.get("max_misalignment_degrees", max_misalignment_degrees)), 0.0)
			startup_min_reliability_below_25 = clampf(float(tiers.get("startup_min_reliability_below_25", startup_min_reliability_below_25)), 0.05, 1.0)


func configure_vanes(candidate_definitions: Array[Resource]) -> Dictionary:
	var candidate_by_id: Dictionary = {}
	var candidate_states: Dictionary = {}
	var errors := PackedStringArray()

	for resource_variant: Variant in candidate_definitions:
		if not (resource_variant is VaneDefinition):
			errors.append("Vane entry is missing or is not a VaneDefinition Resource.")
			continue

		var definition: VaneDefinition = resource_variant as VaneDefinition
		var vane_id: StringName = definition.vane_id
		if vane_id.is_empty():
			errors.append("A vane definition has an empty vane_id.")
			continue
		if candidate_by_id.has(vane_id):
			errors.append("Duplicate vane_id: %s" % String(vane_id))
			continue
		if definition.group_id.is_empty():
			errors.append("Vane %s has an empty group_id." % String(vane_id))
			continue
		if not is_finite(definition.nominal_authority_twr) or definition.nominal_authority_twr < 0.0:
			errors.append("Vane %s has invalid nominal authority; expected a finite value >= 0." % String(vane_id))
			continue
		if not _is_finite_vector3(definition.local_position):
			errors.append("Vane %s has a non-finite local position." % String(vane_id))
			continue
		if (
			not _is_finite_vector3(definition.local_thrust_axis)
			or definition.local_thrust_axis.length_squared() <= 0.000001
		):
			errors.append("Vane %s has an invalid or zero local thrust axis." % String(vane_id))
			continue

		var invalid_weights := false
		for channel_variant: Variant in definition.control_weights.keys():
			var channel_name: StringName = StringName(str(channel_variant))
			var weight_variant: Variant = definition.control_weights[channel_variant]
			if not VALID_CONTROL_CHANNELS.has(channel_name):
				errors.append(
					"Vane %s has unknown control channel '%s'." % [String(vane_id), str(channel_variant)]
				)
				invalid_weights = true
				continue
			if not _is_whole_control_weight(weight_variant):
				errors.append(
					"Vane %s has invalid %s control weight; expected a whole number from 0 to 100."
					% [String(vane_id), str(channel_variant)]
				)
				invalid_weights = true
		if invalid_weights:
			continue

		candidate_by_id[vane_id] = definition
		var existing_state: VaneRuntimeState = _runtime_states_by_id.get(vane_id) as VaneRuntimeState
		candidate_states[vane_id] = existing_state if is_instance_valid(existing_state) else VaneRuntimeState.new()

	if candidate_by_id.is_empty():
		errors.append("No valid vane definitions were provided.")
	if not errors.is_empty():
		return {
			"success": false,
			"errors": errors,
			"active_vane_count": _definitions_by_id.size(),
		}

	var committed_definitions: Array[Resource] = []
	for definition_resource: Resource in candidate_definitions:
		committed_definitions.append(definition_resource)
	vane_definitions = committed_definitions
	_definitions_by_id = candidate_by_id
	_runtime_states_by_id = candidate_states
	_configuration_errors.clear()
	_configuration_valid = true
	return {
		"success": true,
		"errors": PackedStringArray(),
		"active_vane_count": _definitions_by_id.size(),
	}


func _rebuild_runtime_states() -> void:
	var result: Dictionary = configure_vanes(vane_definitions)
	if not bool(result.get("success", false)):
		_configuration_errors = result.get("errors", PackedStringArray())
		_configuration_valid = false


func _is_finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_whole_control_weight(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var numeric_value: float = float(value)
	return (
		is_finite(numeric_value)
		and numeric_value >= 0.0
		and numeric_value <= 100.0
		and is_equal_approx(numeric_value, roundf(numeric_value))
	)


func get_vane_count() -> int:
	return _definitions_by_id.size()


func get_vane_definition(vane_id: StringName) -> VaneDefinition:
	return _definitions_by_id.get(vane_id) as VaneDefinition


func get_vane_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for vane_id_variant: Variant in _definitions_by_id.keys():
		result.append(StringName(str(vane_id_variant)))
	return result


func get_healthy_vane_count() -> int:
	var count: int = 0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		var healthy_limit: float = worn_threshold if tiered_integrity_enabled else 0.999
		if definition.enabled and not state.failed and state.integrity >= healthy_limit:
			count += 1
	return count


func get_lowest_active_integrity() -> float:
	var lowest: float = 1.0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled:
			continue
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		lowest = minf(lowest, 0.0 if state.failed else state.integrity)
	return lowest


func get_average_active_integrity() -> float:
	var sum_val: float = 0.0
	var count: int = 0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled:
			continue
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		sum_val += (0.0 if state.failed else state.integrity)
		count += 1
	return (sum_val / float(count)) if count > 0 else 1.0


func get_integrity_tier_name(integrity_val: float = -1.0) -> String:
	var check_val: float = get_lowest_active_integrity() if integrity_val < 0.0 else integrity_val
	if check_val <= 0.0001:
		return "FAILED"
	if check_val < critical_threshold:
		return "CRITICAL (<25%)"
	if check_val < degraded_threshold:
		return "DEGRADED (<50%)"
	if check_val < worn_threshold:
		return "WORN (<75%)"
	return "HEALTHY"


func get_effective_lag_multiplier() -> float:
	if not tiered_integrity_enabled:
		return 0.0
	var lowest: float = get_lowest_active_integrity()
	if lowest >= worn_threshold:
		return 0.0
	var frac: float = clampf((worn_threshold - lowest) / maxf(worn_threshold, 0.01), 0.0, 1.0)
	return clampf(frac * max_response_lag_multiplier, 0.0, 0.85)


func get_startup_reliability() -> float:
	if not tiered_integrity_enabled:
		return 1.0
	var lowest: float = get_lowest_active_integrity()
	if lowest <= 0.0001:
		return 0.05
	if lowest >= critical_threshold:
		return 1.0
	var deficit: float = clampf((critical_threshold - lowest) / maxf(critical_threshold, 0.01), 0.0, 1.0)
	return lerpf(0.92, startup_min_reliability_below_25, deficit)


func roll_startup_success() -> bool:
	var reliability: float = get_startup_reliability()
	if not random_failures_enabled or reliability >= 0.999:
		return reliability > 0.05
	return randf() <= reliability


func calculate_authority_multiplier_for_state(state: VaneRuntimeState) -> float:
	if state == null or state.failed or state.integrity <= 0.0:
		return 0.0
	var base_mult: float = 1.0
	if tiered_integrity_enabled:
		var integ: float = clampf(state.integrity, 0.0, 1.0)
		if integ >= worn_threshold:
			base_mult = 1.0
		elif integ >= degraded_threshold:
			var t: float = (worn_threshold - integ) / maxf(worn_threshold - degraded_threshold, 0.01)
			base_mult = lerpf(1.0, twr_at_50_percent, t)
		elif integ >= critical_threshold:
			var t: float = (degraded_threshold - integ) / maxf(degraded_threshold - critical_threshold, 0.01)
			base_mult = lerpf(twr_at_50_percent, twr_at_25_percent, t)
		else:
			var t: float = clampf((critical_threshold - integ) / maxf(critical_threshold, 0.01), 0.0, 1.0)
			base_mult = lerpf(twr_at_25_percent, twr_floor_above_zero, t)
	else:
		base_mult = clampf(state.integrity, 0.0, 1.0)

	var temp_clamp: float = 1.0
	if state.temperature_celsius < 10.0:
		temp_clamp = clampf(0.70 + 0.30 * ((state.temperature_celsius + 10.0) / 20.0), 0.70, 1.0)
	base_mult *= temp_clamp

	if state.sputter_active:
		base_mult *= clampf(state.sputter_output_scale, 0.0, 1.0)
	return clampf(base_mult, 0.0, 1.0)


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


func get_group_effective_authority_twr(group_id: StringName) -> float:
	var total_authority: float = 0.0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled or definition.group_id != group_id:
			continue
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		total_authority += definition.nominal_authority_twr * calculate_authority_multiplier_for_state(state)
	return total_authority


func get_vane_nominal_authority_twr(vane_id: StringName) -> float:
	if not _definitions_by_id.has(vane_id):
		return 0.0
	var definition := _definitions_by_id[vane_id] as VaneDefinition
	return definition.nominal_authority_twr


func get_vane_effective_authority_twr(vane_id: StringName) -> float:
	if not _definitions_by_id.has(vane_id):
		return 0.0
	var definition := _definitions_by_id[vane_id] as VaneDefinition
	if not definition.enabled:
		return 0.0
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	return definition.nominal_authority_twr * calculate_authority_multiplier_for_state(state)


func get_vane_effective_thrust_axis_local(vane_id: StringName) -> Vector3:
	if not _definitions_by_id.has(vane_id):
		return Vector3.ZERO
	var definition := _definitions_by_id[vane_id] as VaneDefinition
	if not definition.enabled:
		return Vector3.ZERO
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	var total_offset: Vector3 = state.alignment_offset_degrees + state.dynamic_misalignment_degrees
	var alignment_radians: Vector3 = total_offset * ALIGNMENT_DEGREES_TO_RADIANS
	var alignment_basis: Basis = Basis.from_euler(alignment_radians)
	return (alignment_basis * definition.local_thrust_axis).normalized()


func can_vane_receive_redistributed_authority(vane_id: StringName) -> bool:
	if not _definitions_by_id.has(vane_id):
		return false
	var definition := _definitions_by_id[vane_id] as VaneDefinition
	if not definition.enabled:
		return false
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	return not state.failed and state.integrity >= 0.999


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

	for vane_id in vane_ids:
		if seen_ids.has(vane_id) or not _definitions_by_id.has(vane_id):
			continue
		seen_ids[vane_id] = true
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled:
			continue
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		var base_authority: float = definition.nominal_authority_twr * calculate_authority_multiplier_for_state(state)
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

		var alignment_radians: Vector3 = (state.alignment_offset_degrees + state.dynamic_misalignment_degrees) * ALIGNMENT_DEGREES_TO_RADIANS
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


func calculate_thermal_loads(
		main_power_output: float,
		vector_angle_degrees: float,
		maneuver_contributions: Array[Dictionary],
		force_newtons_per_twr: float) -> Dictionary:
	var loads: Dictionary = {}
	var lift_blend: float = clampf(vector_angle_degrees / 90.0, 0.0, 1.0)
	var forward_blend: float = 1.0 - lift_blend
	var power: float = clampf(main_power_output, 0.0, 1.0)

	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled:
			loads[vane_id] = 0.0
			continue
		var base_load: float = 0.0
		match definition.group_id:
			&"bottom_front", &"bottom_rear":
				base_load = power * lift_blend
			&"main_rear":
				base_load = power * forward_blend
		loads[vane_id] = base_load

	for contribution_value in maneuver_contributions:
		var contribution: Dictionary = contribution_value
		var vane_id: StringName = contribution.get("vane_id", &"")
		if not _definitions_by_id.has(vane_id):
			continue
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		var rated_force: float = definition.nominal_authority_twr * maxf(force_newtons_per_twr, 0.0)
		if rated_force <= MINIMUM_FORCE_WEIGHT:
			continue
		var force_world: Vector3 = contribution.get("force_world", Vector3.ZERO)
		var added_load: float = force_world.length() / rated_force
		loads[vane_id] = float(loads.get(vane_id, 0.0)) + added_load

	for vane_id in loads:
		loads[vane_id] = clampf(float(loads[vane_id]), 0.0, MAX_THERMAL_LOAD_FRACTION)
	return loads


func calculate_radiator_cooling_rate(
		temperature_c: float,
		air_density_kg_m3: float = 0.0,
		airspeed_mps: float = 0.0,
		convective_efficiency: float = 1.0) -> Dictionary:
	if not air_convection_enabled:
		return {
			"effective_cooling_per_s": cooling_coefficient,
			"convective_factor": 1.0,
			"vacuum_cooling_per_s": cooling_coefficient,
			"air_cooling_per_s": 0.0,
		}
	var eff: float = clampf(convective_efficiency, 0.0, 1.0)
	var rho_ratio: float = clampf(air_density_kg_m3 / SEA_LEVEL_AIR_DENSITY_REF, 0.0, 2.5)
	var speed_ratio: float = minf(maxf(airspeed_mps, 0.0) / maxf(airspeed_reference_mps, 10.0), 2.5)
	var airflow_boost: float = 1.0 + airspeed_cooling_gain * speed_ratio
	var air_cooling: float = radiator_air_cooling_coeff * pow(rho_ratio, air_density_exponent) * airflow_boost * eff
	var high_temp_rad: float = 0.0
	if temperature_c > high_temp_radiation_threshold_c:
		var hot_frac: float = clampf((temperature_c - high_temp_radiation_threshold_c) / 100.0, 0.0, 1.5)
		high_temp_rad = high_temp_radiation_bonus * hot_frac
	var total_cooling: float = radiator_vacuum_cooling_coeff + air_cooling + high_temp_rad
	var conv_factor: float = 1.0 + (air_cooling / maxf(radiator_vacuum_cooling_coeff, 0.001))
	return {
		"effective_cooling_per_s": total_cooling,
		"convective_factor": conv_factor,
		"vacuum_cooling_per_s": radiator_vacuum_cooling_coeff + high_temp_rad,
		"air_cooling_per_s": air_cooling,
	}


func update_thermal_simulation(
		delta: float,
		ambient_temperature_celsius: float,
		field_online: bool,
		vane_loads: Dictionary = {},
		air_density_kg_m3: float = 0.0,
		airspeed_mps: float = 0.0,
		convective_efficiency: float = 1.0) -> void:
	if delta <= 0.00001:
		return
	_last_air_density_kg_m3 = maxf(air_density_kg_m3, 0.0)
	_last_airspeed_mps = maxf(airspeed_mps, 0.0)
	_last_convective_efficiency = clampf(convective_efficiency, 0.0, 1.0)
	_last_ambient_temperature_c = ambient_temperature_celsius
	var sum_cooling: float = 0.0
	var sum_conv: float = 0.0
	var active_cnt: int = 0

	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		var load: float = 0.0
		if field_online and definition.enabled:
			load = clampf(float(vane_loads.get(vane_id, 0.0)), 0.0, MAX_THERMAL_LOAD_FRACTION)
		state.load_fraction = load
		var rad_info: Dictionary = _step_individual_vane_thermal(
			state, delta, ambient_temperature_celsius, field_online,
			_last_air_density_kg_m3, _last_airspeed_mps, _last_convective_efficiency
		)
		sum_cooling += float(rad_info.get("effective_cooling_per_s", cooling_coefficient))
		sum_conv += float(rad_info.get("convective_factor", 1.0))
		active_cnt += 1
	if active_cnt > 0:
		_last_effective_cooling_per_s = sum_cooling / float(active_cnt)
		_last_convective_factor = sum_conv / float(active_cnt)


func _step_individual_vane_thermal(
		state: VaneRuntimeState,
		delta: float,
		ambient_temperature_celsius: float,
		field_online: bool,
		air_density_kg_m3: float,
		airspeed_mps: float,
		convective_efficiency: float = 1.0) -> Dictionary:
	var load: float = state.load_fraction
	var heat_in: float = 0.0
	if field_online:
		heat_in = base_online_heat_rate + heat_rate_coefficient * pow(maxf(load, 0.0), heat_load_exponent)

	var rad_info: Dictionary = calculate_radiator_cooling_rate(
		state.temperature_celsius, air_density_kg_m3, airspeed_mps, convective_efficiency
	)
	var effective_cooling: float = float(rad_info.get("effective_cooling_per_s", cooling_coefficient))
	state.radiator_cooling_per_second = effective_cooling
	var heat_out: float = effective_cooling * (state.temperature_celsius - ambient_temperature_celsius)
	state.temperature_celsius += (heat_in - heat_out) * delta

	state.min_green_celsius = nominal_warmup_temp_c * pow(maxf(load, 0.0), 0.7)
	state.max_green_celsius = max_continuous_temp_c - (load * 15.0 if tiered_integrity_enabled else load * 20.0)

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

	if not field_online:
		state.wear_rate_per_second = 0.0
	else:
		if tiered_integrity_enabled:
			var wear_rate: float = base_wear_rate_per_second * (0.25 + 0.75 * clampf(load, 0.0, 1.2))
			if state.thermal_status == &"COLD_STRAIN" and load > 0.05:
				var cold_frac: float = clampf(delta_from_green / maxf(nominal_warmup_temp_c, 1.0), 0.0, 2.0)
				wear_rate += cold_strain_wear_coefficient * cold_frac * load * load
			elif state.thermal_status == &"OVERHEAT":
				var band: float = maxf(critical_temp_c - state.max_green_celsius, 10.0)
				var over_frac: float = clampf((state.temperature_celsius - state.max_green_celsius) / band, 0.0, 1.0)
				wear_rate += overheat_wear_rate_per_second * over_frac * maxf(load, 0.25)
			elif state.thermal_status == &"CRITICAL":
				var crit_excess: float = clampf((state.temperature_celsius - critical_temp_c) / 50.0, 0.15, 2.5)
				wear_rate += overheat_wear_rate_per_second + critical_wear_rate_per_second * crit_excess * maxf(load, 0.4)
			if state.integrity < degraded_threshold:
				var deep_frac: float = clampf((degraded_threshold - state.integrity) / maxf(degraded_threshold, 0.05), 0.0, 1.0)
				wear_rate *= (1.0 + below_50_wear_exp_gain * deep_frac * deep_frac)
			state.wear_rate_per_second = wear_rate
		else:
			state.wear_rate_per_second = base_wear_rate_per_second
			if delta_from_green > 0.0 and load > 0.001:
				state.wear_rate_per_second += quadratic_wear_coefficient * (delta_from_green * delta_from_green) * (load * load)

	state.integrity = maxf(0.0, state.integrity - state.wear_rate_per_second * delta)
	if state.integrity <= 0.0001:
		state.failed = true
		state.integrity = 0.0

	_update_stochastic_faults(state, delta, field_online)
	return rad_info


func _update_stochastic_faults(state: VaneRuntimeState, delta: float, field_online: bool) -> void:
	if not field_online or state.failed:
		state.sputter_active = false
		state.sputter_output_scale = 1.0
		state.sputter_timer = 0.0
		state.dynamic_misalignment_degrees = Vector3.ZERO
		state.misalignment_timer = 0.0
		return

	if not tiered_integrity_enabled:
		if state.temperature_celsius > critical_temp_c or state.integrity < 0.20:
			state.sputter_timer -= delta
			if state.sputter_timer <= 0.0:
				state.sputter_active = not state.sputter_active
				state.sputter_output_scale = 0.0 if state.sputter_active else 1.0
				state.sputter_timer = randf_range(0.15, 0.45)
		else:
			state.sputter_active = false
			state.sputter_output_scale = 1.0
			state.sputter_timer = 0.0
		return

	var fault_severity: float = calculate_fault_severity_for_integrity(state.integrity)
	var thermal_push: float = 0.0
	if state.temperature_celsius > critical_temp_c:
		thermal_push = clampf((state.temperature_celsius - critical_temp_c) / 60.0, 0.0, 1.0) * 0.35
	var total_fault_drive: float = clampf(fault_severity + thermal_push, 0.0, 1.5)
	if not random_failures_enabled or (state.integrity >= worn_threshold and thermal_push <= 0.001):
		state.sputter_active = false
		state.sputter_output_scale = 1.0
		state.sputter_timer = 0.0
		state.dynamic_misalignment_degrees = Vector3.ZERO
		state.misalignment_timer = 0.0
		return

	if state.sputter_timer > 0.0:
		state.sputter_timer -= delta
		if state.sputter_timer <= 0.0:
			state.sputter_active = false
			state.sputter_output_scale = 1.0
	else:
		var chance_per_s: float = lerpf(
			max_fault_chance_per_second_at_75_to_50,
			max_fault_chance_per_second_below_25,
			clampf(total_fault_drive * total_fault_drive, 0.0, 1.0)
		) * clampf(total_fault_drive / 0.35, 0.0, 1.0)
		if randf() < chance_per_s * delta:
			state.sputter_active = true
			var dip: float = clampf(0.18 + total_fault_drive * 0.42, 0.12, 0.72)
			state.sputter_output_scale = 1.0 - dip
			state.sputter_timer = randf_range(0.12, 0.36)

	if state.misalignment_timer > 0.0:
		state.misalignment_timer -= delta
		if state.misalignment_timer <= 0.0:
			state.dynamic_misalignment_degrees = Vector3.ZERO
	else:
		if state.integrity < worn_threshold and randf() < (0.14 * total_fault_drive * delta):
			var deg_amp: float = max_misalignment_degrees * clampf(total_fault_drive, 0.05, 1.0)
			state.dynamic_misalignment_degrees = Vector3(
				randf_range(-deg_amp, deg_amp),
				randf_range(-deg_amp, deg_amp),
				randf_range(-deg_amp * 0.5, deg_amp * 0.5)
			)
			state.misalignment_timer = randf_range(0.4, 1.4)


func calculate_fault_severity_for_integrity(integ: float) -> float:
	var c: float = clampf(integ, 0.0, 1.0)
	if c >= worn_threshold:
		return 0.0
	if c >= degraded_threshold:
		return ((worn_threshold - c) / maxf(worn_threshold - degraded_threshold, 0.01)) * 0.35
	var mid_depth: float = (degraded_threshold - c) / maxf(degraded_threshold, 0.01)
	return 0.35 + mid_depth * mid_depth * 0.95


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


func get_vane_load_fraction(vane_id: StringName) -> float:
	if not _runtime_states_by_id.has(vane_id):
		return 0.0
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	return state.load_fraction


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
			"effective_authority_twr": definition.nominal_authority_twr * calculate_authority_multiplier_for_state(state),
			"integrity": state.integrity,
			"failed": state.failed,
			"alignment_offset_degrees": state.alignment_offset_degrees,
			"dynamic_misalignment_degrees": state.dynamic_misalignment_degrees,
			"temperature_celsius": state.temperature_celsius,
			"load_fraction": state.load_fraction,
			"thermal_status": state.thermal_status,
			"wear_rate_per_second": state.wear_rate_per_second,
			"min_green_celsius": state.min_green_celsius,
			"max_green_celsius": state.max_green_celsius,
			"sputter_active": state.sputter_active,
			"radiator_cooling_per_second": state.radiator_cooling_per_second,
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
		"vane_lowest_integrity": get_lowest_active_integrity(),
		"vane_average_integrity": get_average_active_integrity(),
		"vane_integrity_tier": get_integrity_tier_name(),
		"vane_response_lag_multiplier": get_effective_lag_multiplier(),
		"vane_startup_reliability": get_startup_reliability(),
		"radiator_air_convection_enabled": air_convection_enabled,
		"radiator_air_density_kg_m3": _last_air_density_kg_m3,
		"radiator_airspeed_mps": _last_airspeed_mps,
		"radiator_convective_efficiency": _last_convective_efficiency,
		"radiator_convective_factor": _last_convective_factor,
		"radiator_effective_cooling_per_s": _last_effective_cooling_per_s,
	}
