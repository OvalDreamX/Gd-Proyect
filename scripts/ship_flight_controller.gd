extends Node
class_name ShipFlightController

## Ship-owned input and field-state controller.
## Converts keyboard/mouse events into commanded values, while
## RepulsorliftSystem owns all physical force calculations and applications.

enum FieldState {
	OFF,
	STARTING,
	ONLINE,
}

@export_category("Field startup")
@export_range(0.1, 5.0, 0.1) var startup_duration_seconds: float = 1.2

@export_category("Command response")
## Pilot setpoint rate: time required for W/S to move from 0 to 100%.
@export_range(0.05, 1.0, 0.05) var field_power_change_per_second: float = 0.35
## Pilot setpoint rate through the continuous 0-110 degree vector range.
@export_range(5.0, 90.0, 1.0) var vector_change_degrees_per_second: float = 35.0
## Rate at which actual field output catches up with the power setpoint.
@export_range(0.05, 1.0, 0.05) var field_power_output_rate_per_second: float = 0.20
## Rate at which actual field-vector distribution follows its setpoint.
@export_range(5.0, 90.0, 1.0) var vector_output_change_degrees_per_second: float = 22.0

@export_category("Mouse flight controls")
## Normalized virtual-stick units per unscaled screen pixel. No auto-centering:
## mouse displacement persists until the pilot moves the virtual stick back.
@export_range(0.0005, 0.02, 0.0005) var flight_control_mouse_sensitivity: float = 0.003

const MIN_VECTOR_DISTRIBUTION_DEGREES: float = 0.0
const MAX_VECTOR_DISTRIBUTION_DEGREES: float = 110.0
const DEFAULT_VECTOR_DISTRIBUTION_DEGREES: float = 90.0
const TELEMETRY_UPDATE_INTERVAL_SECONDS: float = 0.1

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable
@onready var _camera_controller: ShipCameraController = get_node("../CameraController") as ShipCameraController
@onready var _repulsorlift_system: RepulsorliftSystem = get_node("../RepulsorliftSystem") as RepulsorliftSystem

var _hud: FlightHUD
var _field_state: int = FieldState.OFF
var _startup_time_remaining: float = 0.0
var _field_power_command: float = 0.0
var _field_power_output: float = 0.0
# Start in the 90-degree VTOL/hover setting so the existing takeoff test remains
# intuitive. Q/E can move the main vector continuously in either direction.
var _vector_distribution_degrees: float = DEFAULT_VECTOR_DISTRIBUTION_DEGREES
var _vector_distribution_actual_degrees: float = DEFAULT_VECTOR_DISTRIBUTION_DEGREES
var _yaw_command: float = 0.0
# x = roll, y = pitch. These are normalized pilot commands, not ship attitude.
var _roll_command: float = 0.0
var _pitch_command: float = 0.0
var _require_neutral_controls: bool = false
var _camera_look_mode: bool = false
var _debug_interaction_mode: bool = false
var _debug_overview_enabled: bool = false
var _pilot_was_ready: bool = false
var _telemetry_time_remaining: float = 0.0


func _ready() -> void:
	if _ship == null or _camera_controller == null or _repulsorlift_system == null:
		push_error("ShipFlightController requires ShipInteractable, CameraController, and RepulsorliftSystem.")
		set_process(false)
		set_process_unhandled_input(false)
		set_physics_process(false)
		return

	_hud = FlightHUD.new()
	_hud.name = "FlightHUD"
	add_child(_hud)
	_hud.visible = false
	_repulsorlift_system.set_debug_visualization_enabled(_debug_overview_enabled)
	_publish_telemetry()


func _unhandled_input(event: InputEvent) -> void:
	if not _ship.is_pilot_ready():
		return

	if event.is_action_pressed("ship_camera_toggle") and not _debug_interaction_mode:
		_camera_controller.toggle_view()
		_publish_telemetry()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ship_field_toggle") and not _debug_interaction_mode:
		_toggle_field_state()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_camera_look_mode = not _camera_look_mode
			if _debug_interaction_mode:
				_require_neutral_controls = true
				_debug_interaction_mode = false
			_update_mouse_mode()
			_publish_telemetry()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _debug_interaction_mode:
				get_viewport().set_input_as_handled()
				return
			if _camera_controller.is_external_view():
				var zoom_direction: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				_camera_controller.zoom_external(zoom_direction, event.factor)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventKey:
		if _is_shift_key(event) and _camera_look_mode:
			var was_debug_interaction: bool = _debug_interaction_mode
			_debug_interaction_mode = event.pressed
			if was_debug_interaction and not _debug_interaction_mode:
				_require_neutral_controls = true
			_update_mouse_mode()
			_publish_telemetry()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_F3 or event.physical_keycode == KEY_F3:
			if event.pressed and not event.echo:
				_debug_overview_enabled = not _debug_overview_enabled
				_repulsorlift_system.set_debug_visualization_enabled(_debug_overview_enabled)
				_publish_telemetry()
				get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if _debug_interaction_mode:
			get_viewport().set_input_as_handled()
			return

		if _camera_look_mode:
			_camera_controller.apply_mouse_look(event.screen_relative)
			_publish_telemetry()
			get_viewport().set_input_as_handled()
			return

		# Flight-control position is independent from camera rotation and remains
		# unchanged while the player is in camera-look mode.
		if _field_state == FieldState.ONLINE and not _require_neutral_controls:
			var next_roll := clampf(
				_roll_command + event.screen_relative.x * flight_control_mouse_sensitivity,
				-1.0,
				1.0
			)
			var next_pitch := clampf(
				_pitch_command - event.screen_relative.y * flight_control_mouse_sensitivity,
				-1.0,
				1.0
			)
			if not is_equal_approx(next_roll, _roll_command) or not is_equal_approx(next_pitch, _pitch_command):
				_roll_command = next_roll
				_pitch_command = next_pitch
				_publish_telemetry()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var pilot_ready: bool = _ship.is_pilot_ready()
	if _hud.visible != pilot_ready:
		_hud.visible = pilot_ready

	if pilot_ready and not _pilot_was_ready:
		_pilot_was_ready = true
		_camera_look_mode = false
		_debug_interaction_mode = false
		_camera_controller.activate_cockpit_view()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_publish_telemetry()
	elif not pilot_ready and _pilot_was_ready:
		_pilot_was_ready = false
		_camera_look_mode = false
		_debug_interaction_mode = false
		_roll_command = 0.0
		_pitch_command = 0.0
		_camera_controller.reset_camera_state()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_publish_telemetry()

	if not pilot_ready:
		if _field_state != FieldState.OFF:
			_turn_field_off()
		_repulsorlift_system.apply_flight_control_forces(false, 0.0, DEFAULT_VECTOR_DISTRIBUTION_DEGREES, 0.0, 0.0, 0.0)
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

	# All six pilot values are now passed to the force allocator. Main vector
	# direction is ship-relative; pitch/roll/yaw are separate vane force pairs.
	_repulsorlift_system.apply_flight_control_forces(
		_field_state == FieldState.ONLINE,
		_field_power_output,
		_vector_distribution_actual_degrees,
		_pitch_command,
		_roll_command,
		_yaw_command
	)

	if telemetry_changed:
		_publish_telemetry()

	_telemetry_time_remaining -= delta
	if _telemetry_time_remaining <= 0.0:
		_telemetry_time_remaining = TELEMETRY_UPDATE_INTERVAL_SECONDS
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
	_pitch_command = 0.0
	_roll_command = 0.0
	_repulsorlift_system.apply_flight_control_forces(false, 0.0, _vector_distribution_actual_degrees, 0.0, 0.0, 0.0)
	_set_field_state(FieldState.OFF)


func _set_field_state(new_state: int) -> void:
	if _field_state == new_state:
		return
	_field_state = new_state
	_require_neutral_controls = new_state == FieldState.ONLINE
	_publish_telemetry()


func _update_online_commands(delta: float) -> bool:
	if _debug_interaction_mode:
		return false

	var changed: bool = false
	var power_axis: float = Input.get_axis("ship_field_decrease", "ship_field_increase")
	var vector_axis: float = Input.get_axis("ship_vector_decrease", "ship_vector_increase")
	var new_yaw: float = Input.get_axis("ship_yaw_left", "ship_yaw_right")

	# Do not arm keys held during cockpit entry or the startup interval.
	if _require_neutral_controls:
		if is_zero_approx(power_axis) and is_zero_approx(vector_axis) and is_zero_approx(new_yaw):
			_require_neutral_controls = false
			changed = true
		else:
			if not is_zero_approx(_yaw_command):
				_yaw_command = 0.0
				changed = true
			return changed

	if not is_zero_approx(power_axis):
		var new_power: float = clampf(
			_field_power_command + power_axis * field_power_change_per_second * delta,
			0.0,
			1.0
		)
		if not is_equal_approx(new_power, _field_power_command):
			_field_power_command = new_power
			changed = true

	if not is_zero_approx(vector_axis):
		var new_vector: float = clampf(
			_vector_distribution_degrees + vector_axis * vector_change_degrees_per_second * delta,
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


func _update_mouse_mode() -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if _camera_look_mode and _debug_interaction_mode
		else Input.MOUSE_MODE_CAPTURED
	)


func _is_shift_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_SHIFT or event.physical_keycode == KEY_SHIFT


func _publish_telemetry() -> void:
	if not is_instance_valid(_hud):
		return

	var camera_angles: Vector2 = _camera_controller.get_look_angles_degrees()
	var snapshot: Dictionary = {
		"field_state": _field_state_name(),
		"field_power_command": _field_power_command,
		"field_power_output": _field_power_output,
		"vector_distribution_degrees": _vector_distribution_degrees,
		"vector_distribution_actual_degrees": _vector_distribution_actual_degrees,
		"yaw_command": _yaw_command,
		"pitch_command": _pitch_command,
		"roll_command": _roll_command,
		"camera_view": _camera_controller.get_view_name(),
		"input_mode": _input_mode_name(),
		"camera_yaw_degrees": camera_angles.x,
		"camera_pitch_degrees": camera_angles.y,
		"debug_overview_enabled": _debug_overview_enabled,
		"debug_interaction_mode": _debug_interaction_mode,
		"ship_mass_kg": _ship.mass,
		"ship_position": _ship.global_position,
		"ship_linear_velocity": _ship.linear_velocity,
		"ship_angular_velocity": _ship.angular_velocity,
		"ship_is_sleeping": _ship.sleeping,
		"center_of_mass_mode": "AUTO" if _ship.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_AUTO else "CUSTOM",
		"rigid_body_frozen": _ship.freeze,
		"physics_output_connected": true,
		"controls_armed": not _require_neutral_controls,
	}
	snapshot.merge(_repulsorlift_system.get_telemetry(), true)
	_hud.update_telemetry(snapshot)


func _input_mode_name() -> String:
	if _debug_interaction_mode:
		return "DEBUG UI"
	return "CAMERA LOOK" if _camera_look_mode else "FLIGHT CONTROL"


func _field_state_name() -> String:
	match _field_state:
		FieldState.OFF:
			return "OFF"
		FieldState.STARTING:
			return "STARTING"
		FieldState.ONLINE:
			return "ONLINE"
	return "UNKNOWN"
