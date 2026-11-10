extends Node
class_name RepulsorliftSystem

## Phase 2D: fixed-direction collective lift test.
##
## This component converts the generator's actual power output into one
## upward resultant force at the ship's center of mass. It does not model
## individual vanes, directional vectoring, torque, FCC, heat, or damage.
## The test direction is opposite the gravity vector so the lift remains
## vertical even if a later test uses a non-standard gravity direction.

@export_category("Collective lift")
## PLACEHOLDER from GDD Section 9.6: approximately 1.1 TWR for the four
## bottom vanes collectively. This is a prototype tuning value, not balance.
@export_range(0.1, 2.0, 0.05) var maximum_lift_twr: float = 1.1

const MINIMUM_GRAVITY_MAGNITUDE: float = 0.0001
const MINIMUM_MASS_KG: float = 0.0001

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable

var _last_field_online: bool = false
var _last_power_output: float = 0.0
var _last_force: Vector3 = Vector3.ZERO
var _last_gravity_magnitude: float = 0.0
var _last_actual_twr: float = 0.0


func _ready() -> void:
	if _ship == null:
		push_error("RepulsorliftSystem must be a child of ShipInteractable.")
		set_process(false)
		set_physics_process(false)


## Called exactly once per physics tick by ShipFlightController.
## Forces are not multiplied by delta: Godot expects a continuous force to be
## submitted every physics update and integrates it using the physics timestep.
func apply_collective_lift(field_online: bool, power_output: float) -> void:
	_last_field_online = field_online
	_last_power_output = clampf(power_output, 0.0, 1.0) if field_online else 0.0
	_last_force = Vector3.ZERO
	_last_gravity_magnitude = 0.0
	_last_actual_twr = 0.0

	if not is_instance_valid(_ship) or _ship.freeze:
		return
	if not field_online or _last_power_output <= 0.0:
		return
	if _ship.mass <= MINIMUM_MASS_KG:
		return

	# Use Godot's effective gravity vector so world gravity and Area3D gravity
	# overrides share the same reference used by the rigid-body simulation.
	var gravity: Vector3 = _ship.get_gravity()
	_last_gravity_magnitude = gravity.length()
	if _last_gravity_magnitude <= MINIMUM_GRAVITY_MAGNITUDE:
		return

	# A TWR of 1.0 exactly balances gravity. The 1.1 placeholder therefore
	# gives 10% excess force at maximum output, with hover near 90.9% output.
	_last_actual_twr = maximum_lift_twr * _last_power_output
	var maximum_force_newtons: float = _ship.mass * _last_gravity_magnitude * maximum_lift_twr
	_last_force = -gravity.normalized() * maximum_force_newtons * _last_power_output

	# Central force acts through the center of mass: collective lift creates
	# translation only and deliberately introduces no pitch/roll/yaw torque.
	_ship.apply_central_force(_last_force)


## Read-only values for HUD/debug telemetry. No simulation state is exposed
## for the HUD to modify.
func get_telemetry() -> Dictionary:
	var hover_power_percent: float = -1.0
	if maximum_lift_twr > 0.0:
		hover_power_percent = 100.0 / maximum_lift_twr

	return {
		"lift_field_online": _last_field_online,
		"lift_power_output": _last_power_output,
		"lift_force_vector": _last_force,
		"lift_force_newtons": _last_force.length(),
		"lift_actual_twr": _last_actual_twr,
		"lift_maximum_twr": maximum_lift_twr,
		"lift_hover_power_percent": hover_power_percent,
		"lift_gravity_magnitude": _last_gravity_magnitude,
	}
