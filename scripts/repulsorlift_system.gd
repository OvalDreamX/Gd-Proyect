extends Node
class_name RepulsorliftSystem

## Phase 2E: per-vane collective-lift force and torque calculation.
##
## The four bottom vanes are evaluated individually and grouped into front
## and rear resultants. Their net force is still applied centrally so this
## milestone preserves the already-tested hover behavior. The calculated
## torque is telemetry only until the rotational integration test is approved.

@export_category("Collective lift")
## PLACEHOLDER from GDD Section 9.6: four bottom vanes produce approximately
## 1.1 TWR collectively. Per-vane authority is stored in VaneDefinition.

const BOTTOM_FRONT_GROUP: StringName = &"bottom_front"
const BOTTOM_REAR_GROUP: StringName = &"bottom_rear"
const MINIMUM_GRAVITY_MAGNITUDE: float = 0.0001
const MINIMUM_MASS_KG: float = 0.0001

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable
@onready var _vane_controller: VaneController = get_node("../VaneController") as VaneController

var _last_field_online: bool = false
var _last_power_output: float = 0.0
var _last_force: Vector3 = Vector3.ZERO
var _last_predicted_torque: Vector3 = Vector3.ZERO
var _last_gravity_magnitude: float = 0.0
var _last_actual_twr: float = 0.0
var _last_maximum_lift_twr: float = 0.0
var _last_vane_contributions: Array[Dictionary] = []


func _ready() -> void:
	if _ship == null or _vane_controller == null:
		push_error("RepulsorliftSystem requires ShipInteractable and VaneController siblings.")
		set_process(false)
		set_physics_process(false)
		return

	_last_maximum_lift_twr = _get_configured_maximum_lift_twr()
	if not _vane_controller.is_configuration_valid():
		push_error("Vane configuration is invalid: %s" % "; ".join(_vane_controller.get_configuration_errors()))


## Called exactly once per physics tick by ShipFlightController.
## Continuous forces are not multiplied by delta; Godot integrates them using
## the physics timestep. No torque is applied in this validation milestone.
func apply_collective_lift(field_online: bool, power_output: float) -> void:
	_last_field_online = field_online
	_last_power_output = clampf(power_output, 0.0, 1.0) if field_online else 0.0
	_last_force = Vector3.ZERO
	_last_predicted_torque = Vector3.ZERO
	_last_gravity_magnitude = 0.0
	_last_actual_twr = 0.0
	_last_vane_contributions.clear()
	_last_maximum_lift_twr = _get_configured_maximum_lift_twr()

	if not is_instance_valid(_ship) or not is_instance_valid(_vane_controller) or _ship.freeze:
		return
	if not field_online or _last_power_output <= 0.0:
		return
	if _ship.mass <= MINIMUM_MASS_KG:
		return
	if not _vane_controller.is_configuration_valid():
		return

	# Use the same effective gravity vector as the rigid body, including Area3D
	# overrides. Aligned vanes therefore preserve the existing anti-gravity lift.
	var gravity: Vector3 = _ship.get_gravity()
	_last_gravity_magnitude = gravity.length()
	if _last_gravity_magnitude <= MINIMUM_GRAVITY_MAGNITUDE:
		return

	var force_newtons_per_twr: float = _ship.mass * _last_gravity_magnitude * _last_power_output
	var desired_lift_direction: Vector3 = -gravity.normalized()

	# Calculate independent front/rear group resultants. The definitions carry
	# individual nominal TWR values; condition affects each vane's contribution.
	var front_resultant: Dictionary = _vane_controller.calculate_group_resultant(
		BOTTOM_FRONT_GROUP,
		desired_lift_direction,
		force_newtons_per_twr,
		_ship.global_transform,
		_ship.center_of_mass
	)
	var rear_resultant: Dictionary = _vane_controller.calculate_group_resultant(
		BOTTOM_REAR_GROUP,
		desired_lift_direction,
		force_newtons_per_twr,
		_ship.global_transform,
		_ship.center_of_mass
	)

	_last_force = front_resultant["net_force"] + rear_resultant["net_force"]
	_last_predicted_torque = front_resultant["net_torque"] + rear_resultant["net_torque"]
	_last_vane_contributions.append_array(front_resultant["contributions"])
	_last_vane_contributions.append_array(rear_resultant["contributions"])
	_last_actual_twr = _last_force.length() / (_ship.mass * _last_gravity_magnitude)

	# Deliberate safety boundary: apply the already-validated net translation
	# force at the center of mass. Predicted vane torque is calculated and
	# exposed, but not integrated into rotation until the next test milestone.
	_ship.apply_central_force(_last_force)


func _get_configured_maximum_lift_twr() -> float:
	if not is_instance_valid(_vane_controller):
		return 0.0
	return (
		_vane_controller.get_group_nominal_authority_twr(BOTTOM_FRONT_GROUP)
		+ _vane_controller.get_group_nominal_authority_twr(BOTTOM_REAR_GROUP)
	)


## Read-only telemetry snapshot for the HUD and test tools.
func get_telemetry() -> Dictionary:
	var hover_power_percent: float = -1.0
	if _last_maximum_lift_twr > 0.0:
		hover_power_percent = 100.0 / _last_maximum_lift_twr

	var vane_telemetry: Dictionary = {}
	if is_instance_valid(_vane_controller):
		vane_telemetry = _vane_controller.get_telemetry()

	var result: Dictionary = {
		"lift_field_online": _last_field_online,
		"lift_power_output": _last_power_output,
		"lift_force_vector": _last_force,
		"lift_force_newtons": _last_force.length(),
		"lift_actual_twr": _last_actual_twr,
		"lift_maximum_twr": _last_maximum_lift_twr,
		"lift_hover_power_percent": hover_power_percent,
		"lift_gravity_magnitude": _last_gravity_magnitude,
		"lift_predicted_torque_vector": _last_predicted_torque,
		"lift_predicted_torque_magnitude": _last_predicted_torque.length(),
		"lift_vane_contributions": _last_vane_contributions.duplicate(true),
	}
	result.merge(vane_telemetry, true)
	return result
