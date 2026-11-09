extends Node
class_name ShipFlightController

## Phase 2A only: collects ship commands and manages the repulsorlift
## generator's OFF -> STARTING -> ONLINE state.
##
## IMPORTANT: This script intentionally does not apply forces, impulses,
## torques, or modify the ship's transform/velocity. The rigid body remains
## frozen until the GDD's rigid-body and collective-lift milestones are tested.

enum FieldState {
	OFF,
	STARTING,
	ONLINE,
}

@export_category("Field startup")
@export_range(0.1, 5.0, 0.1) var startup_duration_seconds: float = 1.2

@export_category("Command response")
## Prototype tuning value: time needed to move the power command from 0 to 100%.
@export_range(0.05, 1.0, 0.05) var field_power_change_per_second: float = 0.35
## Prototype tuning value: rate of travel through the continuous 0-110 degree range.
@export_range(5.0, 90.0, 1.0) var vector_change_degrees_per_second: float = 35.0

## Maximum rate at which generated field output catches up with the power setpoint.
## Kept below the pilot command rate to create a visible, tunable spool response.
@export_range(0.05, 1.0, 0.05) var field_power_output_rate_per_second: float = 0.20
## Maximum rate at which actual field-vector distribution follows its setpoint.
@export_range(5.0, 90.0, 1.0) var vector_output_change_degrees_per_second: float = 22.0

const MIN_VECTOR_DISTRIBUTION_DEGREES: float = 0.0
const MAX_VECTOR_DISTRIBUTION_DEGREES: float = 110.0

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable

var _hud: FlightHUD
var _field_state: int = FieldState.OFF
var _startup_time_remaining: float = 0.0
# Pilot setpoints move in response to W/S and Q/E. Actual outputs lag behind
# these setpoints, representing generator spool-up and field-vector actuator response.
var _field_power_command: float = 0.0
var _field_power_output: float = 0.0
var _vector_distribution_degrees: float = MIN_VECTOR_DISTRIBUTION_DEGREES
var _vector_distribution_actual_degrees: float = MIN_VECTOR_DISTRIBUTION_DEGREES
var _yaw_command: float = 0.0
var _require_neutral_controls: bool = false


func _ready() -> void:
	if _ship == null:
		push_error("ShipFlightController must be a child of a ShipInteractable RigidBody3D.")
		set_process(false)
		set_process_unhandled_input(false)
		return

	_hud = FlightHUD.new()
	_hud.name = "FlightHUD"
	add_child(_hud)
	_hud.visible = false
	_publish_telemetry()


func _unhandled_input(event: InputEvent) -> void:
	# The player's explicit occupancy state becomes true only after the cockpit
	# entry transition completes. Camera switching in Phase 2B will not affect it.
	if not _ship.is_pilot_ready():
		return

	if event.is_action_pressed("ship_field_toggle"):
		_toggle_field_state()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var pilot_ready: bool = _ship.is_pilot_ready()
	if _hud.visible != pilot_ready:
		_hud.visible = pilot_ready

	if not pilot_ready:
		# Safe default for a future disembark implementation: the field is shut
		# down automatically when the cockpit camera is no longer occupied.
		if _field_state != FieldState.OFF:
			_turn_field_off()
		if not is_zero_approx(_yaw_command):
			_yaw_command = 0.0
			_publish_telemetry()
		return

	var telemetry_changed: bool = false

	if _field_state == FieldState.STARTING:
		_startup_time_remaining = maxf(_startup_time_remaining - delta, 0.0)
		if is_zero_approx(_startup_time_remaining):
			_set_field_state(FieldState.ONLINE)
			telemetry_changed = false # _set_field_state() already published.

	if _field_state == FieldState.ONLINE:
		telemetry_changed = _update_online_commands(delta) or telemetry_changed
		telemetry_changed = _update_actuator_outputs(delta) or telemetry_changed
	elif not is_zero_approx(_yaw_command):
		_yaw_command = 0.0
		telemetry_changed = true

	if telemetry_changed:
		_publish_telemetry()


func _toggle_field_state() -> void:
	match _field_state:
		FieldState.OFF:
			_startup_time_remaining = maxf(startup_duration_seconds, 0.1)
			_set_field_state(FieldState.STARTING)
		FieldState.STARTING, FieldState.ONLINE:
			_turn_field_off()


func _turn_field_off() -> void:
	_startup_time_remaining = 0.0
	_field_power_command = 0.0
	_field_power_output = 0.0
	_yaw_command = 0.0
	_set_field_state(FieldState.OFF)


func _set_field_state(new_state: int) -> void:
	if _field_state == new_state:
		return
	_field_state = new_state
	_require_neutral_controls = new_state == FieldState.ONLINE
	_publish_telemetry()


func _update_online_commands(delta: float) -> bool:
	var changed: bool = false

	var power_axis: float = Input.get_axis(
		"ship_field_decrease",
		"ship_field_increase"
	)
	var vector_axis: float = Input.get_axis(
		"ship_vector_decrease",
		"ship_vector_increase"
	)
	var new_yaw: float = Input.get_axis("ship_yaw_left", "ship_yaw_right")

	# Require a neutral control state after startup. This prevents a key held
	# during the 1.2-second start sequence (or during cockpit entry) from
	# becoming an immediate command when the field reaches ONLINE.
	if _require_neutral_controls:
		if is_zero_approx(power_axis) and is_zero_approx(vector_axis) and is_zero_approx(new_yaw):
			_require_neutral_controls = false
			changed = true
		else:
			if not is_zero_approx(_yaw_command):
				_yaw_command = 0.0
				changed = true
			return changed

	# W/S changes a command setpoint only. Phase 2A has no propulsion model
	# connected, so this value cannot generate force or move the rigid body.
	if not is_zero_approx(power_axis):
		var new_power: float = clampf(
			_field_power_command + power_axis * field_power_change_per_second * delta,
			0.0,
			1.0
		)
		if not is_equal_approx(new_power, _field_power_command):
			_field_power_command = new_power
			changed = true

	# Q/E moves continuously through the agreed conceptual range. These are
	# not three discrete flight modes and no vane forces are calculated yet.
	if not is_zero_approx(vector_axis):
		var new_vector: float = clampf(
			_vector_distribution_degrees
				+ vector_axis * vector_change_degrees_per_second * delta,
			MIN_VECTOR_DISTRIBUTION_DEGREES,
			MAX_VECTOR_DISTRIBUTION_DEGREES
		)
		if not is_equal_approx(new_vector, _vector_distribution_degrees):
			_vector_distribution_degrees = new_vector
			changed = true

	if not is_equal_approx(new_yaw, _yaw_command):
		_yaw_command = new_yaw
		changed = true

	return changed


func _update_actuator_outputs(delta: float) -> bool:
	# Use a rate-limited response rather than directly copying the setpoints.
	# This is intentionally a simple, deterministic spool/actuator model; it is
	# not yet a thermal or electrical simulation of the fictional generator.
	var changed: bool = false

	var new_power_output: float = move_toward(
		_field_power_output,
		_field_power_command,
		field_power_output_rate_per_second * delta
	)
	if not is_equal_approx(new_power_output, _field_power_output):
		_field_power_output = new_power_output
		changed = true

	var new_vector_output: float = move_toward(
		_vector_distribution_actual_degrees,
		_vector_distribution_degrees,
		vector_output_change_degrees_per_second * delta
	)
	if not is_equal_approx(new_vector_output, _vector_distribution_actual_degrees):
		_vector_distribution_actual_degrees = new_vector_output
		changed = true

	return changed


func _publish_telemetry() -> void:
	if not is_instance_valid(_hud):
		return

	# This is an immutable-by-convention telemetry snapshot. The HUD receives
	# data only; it never reads input or calculates simulation values.
	var snapshot: Dictionary = {
		"field_state": _field_state_name(),
		"field_power_command": _field_power_command,
		"field_power_output": _field_power_output,
		"vector_distribution_degrees": _vector_distribution_degrees,
		"vector_distribution_actual_degrees": _vector_distribution_actual_degrees,
		"yaw_command": _yaw_command,
		"ship_mass_kg": _ship.mass,
		"rigid_body_frozen": _ship.freeze,
		"physics_output_connected": false,
		"controls_armed": not _require_neutral_controls,
	}
	_hud.update_telemetry(snapshot)


func _field_state_name() -> String:
	match _field_state:
		FieldState.OFF:
			return "OFF"
		FieldState.STARTING:
			return "STARTING"
		FieldState.ONLINE:
			return "ONLINE"
	return "UNKNOWN"
