extends Node
class_name VaneController

## Owns immutable vane definitions and per-ship runtime condition.
## Calculates group force/torque resultants but never applies them to physics.

class VaneRuntimeState:
	extends RefCounted
	var integrity: float = 1.0
	var failed: bool = false
	var alignment_offset_degrees: Vector3 = Vector3.ZERO

	func reset() -> void:
		integrity = 1.0
		failed = false
		alignment_offset_degrees = Vector3.ZERO

	func authority_multiplier() -> float:
		return 0.0 if failed else clampf(integrity, 0.0, 1.0)


@export_category("Vane configuration")
## Resource definitions may be shared; runtime state below is always per instance.
@export var vane_definitions: Array[Resource] = []

const MINIMUM_GROUP_AUTHORITY: float = 0.000001
const ALIGNMENT_DEGREES_TO_RADIANS: float = PI / 180.0

var _definitions_by_id: Dictionary = {}
var _runtime_states_by_id: Dictionary = {}
var _configuration_errors: PackedStringArray = PackedStringArray()
var _configuration_valid: bool = false


func _enter_tree() -> void:
	# Definitions are already deserialized when the node enters the tree.
	# Build here so sibling systems can safely query us from their _ready().
	_rebuild_runtime_states()


## Rebuilds this ship's runtime state from the configured Resources.
## Does not modify the Resources themselves.
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


func get_group_nominal_authority_twr(group_id: StringName) -> float:
	var total_authority: float = 0.0
	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if definition.enabled and definition.group_id == group_id:
			total_authority += definition.nominal_authority_twr
	return total_authority


## Calculate a group's resultant from its individual vane contributions.
## force_newtons_per_twr is normally ship_mass * gravity_magnitude * field_output.
## Force direction is supplied by the caller; alignment offsets rotate it in the
## ship's local frame. No physics API is called here.
func calculate_group_resultant(
		group_id: StringName,
		force_direction_world: Vector3,
		force_newtons_per_twr: float,
		ship_global_transform: Transform3D,
		center_of_mass_local: Vector3
) -> Dictionary:
	var net_force: Vector3 = Vector3.ZERO
	var net_torque: Vector3 = Vector3.ZERO
	var contributions: Array[Dictionary] = []

	var group_authority_twr: float = get_group_nominal_authority_twr(group_id)
	if group_authority_twr <= MINIMUM_GROUP_AUTHORITY:
		return _make_resultant(net_force, net_torque, contributions, group_authority_twr)
	if force_direction_world.length_squared() <= MINIMUM_GROUP_AUTHORITY:
		return _make_resultant(net_force, net_torque, contributions, group_authority_twr)

	var body_basis: Basis = ship_global_transform.basis.orthonormalized()
	var local_reference_direction: Vector3 = body_basis.inverse() * force_direction_world.normalized()

	for vane_id in _definitions_by_id:
		var definition := _definitions_by_id[vane_id] as VaneDefinition
		if not definition.enabled or definition.group_id != group_id:
			continue

		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		var authority_multiplier: float = state.authority_multiplier()
		var alignment_radians: Vector3 = state.alignment_offset_degrees * ALIGNMENT_DEGREES_TO_RADIANS
		var alignment_basis := Basis.from_euler(alignment_radians)
		var vane_direction_world: Vector3 = (
			body_basis * alignment_basis * local_reference_direction
		).normalized()

		var effective_authority_twr: float = definition.nominal_authority_twr * authority_multiplier
		var force_magnitude: float = maxf(force_newtons_per_twr, 0.0) * effective_authority_twr
		var vane_force: Vector3 = vane_direction_world * force_magnitude

		# Vane positions and center of mass are both ship-local. Transform only
		# the lever arm to world space; cross products are then in world space.
		var lever_arm_world: Vector3 = body_basis * (definition.local_position - center_of_mass_local)
		var vane_torque: Vector3 = lever_arm_world.cross(vane_force)

		net_force += vane_force
		net_torque += vane_torque
		contributions.append({
			"vane_id": definition.vane_id,
			"display_name": definition.display_name,
			"group_id": definition.group_id,
			"integrity": state.integrity,
			"failed": state.failed,
			"effective_authority_twr": effective_authority_twr,
			"force_world": vane_force,
			"torque_world": vane_torque,
			"lever_arm_world": lever_arm_world,
		})

	return _make_resultant(net_force, net_torque, contributions, group_authority_twr)


func _make_resultant(
		net_force: Vector3,
		net_torque: Vector3,
		contributions: Array[Dictionary],
		group_authority_twr: float
) -> Dictionary:
	return {
		"net_force": net_force,
		"net_torque": net_torque,
		"contributions": contributions,
		"nominal_authority_twr": group_authority_twr,
	}


func set_vane_integrity(vane_id: StringName, integrity: float) -> bool:
	if not _runtime_states_by_id.has(vane_id):
		return false
	var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
	state.integrity = clampf(integrity, 0.0, 1.0)
	return true


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


func reset_all_vanes() -> void:
	for vane_id in _runtime_states_by_id:
		var state := _runtime_states_by_id[vane_id] as VaneRuntimeState
		state.reset()


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
			"nominal_authority_twr": definition.nominal_authority_twr,
			"effective_authority_twr": definition.nominal_authority_twr * state.authority_multiplier(),
			"integrity": state.integrity,
			"failed": state.failed,
			"alignment_offset_degrees": state.alignment_offset_degrees,
		})

	return {
		"vane_count": get_vane_count(),
		"vane_healthy_count": get_healthy_vane_count(),
		"vane_configuration_valid": _configuration_valid,
		"vane_configuration_errors": get_configuration_errors(),
		"vane_states": vane_states,
	}
