extends Node
class_name ShipFlightController

const PHASE_2U_HUD_SCRIPT = preload("res://scripts/flight_hud_phase_2u.gd")
const JUMP_ENVELOPE_EVALUATOR_SCRIPT = preload("res://scripts/jump_envelope_evaluator.gd")

## Ship-owned input and field-state controller.
## FlightControlComputer interprets pilot intent (including Space Assist mode);
## RepulsorliftSystem remains the only component that submits forces.

enum FieldState {
	OFF,
	STARTING,
	ONLINE,
}

@export_category("Field startup")
@export_range(0.1, 5.0, 0.1) var startup_duration_seconds: float = 1.2

@export_category("Command response")
@export_range(0.05, 1.0, 0.05) var field_power_change_per_second: float = 0.35
@export_range(5.0, 90.0, 1.0) var vector_change_degrees_per_second: float = 35.0
@export_range(0.05, 1.0, 0.05) var field_power_output_rate_per_second: float = 0.20
@export_range(5.0, 90.0, 1.0) var vector_output_change_degrees_per_second: float = 22.0

@export_category("Mouse flight controls")
@export_range(0.0005, 0.02, 0.0005) var flight_control_mouse_sensitivity: float = 0.003

const MIN_VECTOR_DISTRIBUTION_DEGREES: float = 0.0
const MAX_VECTOR_DISTRIBUTION_DEGREES: float = 110.0
const DEFAULT_VECTOR_DISTRIBUTION_DEGREES: float = 90.0
const TELEMETRY_UPDATE_INTERVAL_SECONDS: float = 1.0 / 30.0
const COCKPIT_RECENTER_DELAY_SECONDS: float = 3.0

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable
@onready var _camera_controller: ShipCameraController = get_node("../CameraController") as ShipCameraController
@onready var _repulsorlift_system: RepulsorliftSystem = get_node("../RepulsorliftSystem") as RepulsorliftSystem
@onready var _fcc: FlightControlComputer = get_node("../FlightControlComputer") as FlightControlComputer
@onready var _atmospheric_flight_model: AtmosphericFlightModel = get_node_or_null("../AtmosphericFlightModel") as AtmosphericFlightModel
@onready var _flight_sensor_suite: FlightSensorSuite = get_node_or_null("../FlightSensorSuite") as FlightSensorSuite
@onready var _cargo_system: Node = get_node_or_null("../CargoSystem")
@onready var _vane_controller: Node = get_node_or_null("../VaneController")
@onready var _planetary_gravity_body: Node = get_node_or_null("../PlanetaryGravityBody")

var _hud: FlightHUD
var _environment_manager: Node
var _exclusion_origin: Node3D
var _station_environment: Node
var _planet_environment: Node
var _field_state: int = FieldState.OFF
var _startup_time_remaining: float = 0.0
var _field_power_command: float = 0.0
var _field_power_output: float = 0.0
var _vector_distribution_degrees: float = DEFAULT_VECTOR_DISTRIBUTION_DEGREES
var _vector_distribution_actual_degrees: float = DEFAULT_VECTOR_DISTRIBUTION_DEGREES
var _yaw_command: float = 0.0
var _roll_command: float = 0.0
var _pitch_command: float = 0.0
var _require_neutral_controls: bool = false
var _space_throttle_engaged: bool = false
var _space_brake_pressed: bool = false
var _camera_look_mode: bool = false
var _cockpit_recenter_time_remaining: float = -1.0
var _debug_interaction_mode: bool = false
var _debug_overview_enabled: bool = false
var _pilot_was_ready: bool = false
var _telemetry_time_remaining: float = 0.0
var _fcc_snapshot: Dictionary = {}
var _startup_misfire_message: String = ""
var _startup_misfire_time_remaining: float = 0.0


static func pitch_command_delta_from_mouse_y(screen_delta_y: float, sensitivity: float) -> float:
	return screen_delta_y * maxf(sensitivity, 0.0)


func apply_ship_definition(definition: ShipDefinition) -> void:
	if definition == null or definition.propulsion.is_empty():
		return
	var prop: Dictionary = definition.propulsion
	if prop.has("startup_duration_seconds"):
		startup_duration_seconds = clampf(float(prop.get("startup_duration_seconds", startup_duration_seconds)), 0.1, 5.0)
	if prop.has("field_power_output_rate_per_second"):
		field_power_output_rate_per_second = clampf(float(prop.get("field_power_output_rate_per_second", field_power_output_rate_per_second)), 0.05, 2.0)
	if prop.has("vector_output_change_degrees_per_second"):
		vector_output_change_degrees_per_second = clampf(float(prop.get("vector_output_change_degrees_per_second", vector_output_change_degrees_per_second)), 5.0, 180.0)
	_publish_telemetry()


func reset_controls_for_arrival(keep_field_online: bool = true) -> void:
	_startup_time_remaining = 0.0
	_startup_misfire_message = ""
	_startup_misfire_time_remaining = 0.0
	_field_power_command = 0.0
	_field_power_output = 0.0
	_vector_distribution_degrees = DEFAULT_VECTOR_DISTRIBUTION_DEGREES
	_vector_distribution_actual_degrees = DEFAULT_VECTOR_DISTRIBUTION_DEGREES
	_pitch_command = 0.0
	_roll_command = 0.0
	_yaw_command = 0.0
	_space_throttle_engaged = false
	_space_brake_pressed = false
	_require_neutral_controls = keep_field_online
	_field_state = FieldState.ONLINE if keep_field_online else FieldState.OFF
	if is_instance_valid(_fcc):
		_fcc.reset_integral_trim()
	_update_fcc_snapshot(keep_field_online and is_instance_valid(_ship) and not _ship.freeze)
	_publish_telemetry()


func _ready() -> void:
	if (
		_ship == null
		or _camera_controller == null
		or _repulsorlift_system == null
		or _fcc == null
		or _flight_sensor_suite == null
	):
		push_error(
			"ShipFlightController requires ShipInteractable, CameraController, "
			+ "RepulsorliftSystem, FlightControlComputer, and FlightSensorSuite."
		)
		set_process(false)
		set_process_unhandled_input(false)
		set_physics_process(false)
		return

	_ship.contact_monitor = true
	_ship.max_contacts_reported = maxi(_ship.max_contacts_reported, 4)
	_resolve_environment_manager()
	_hud = PHASE_2U_HUD_SCRIPT.new() as FlightHUD
	_hud.name = "FlightHUD"
	add_child(_hud)
	_hud.visible = false
	if is_instance_valid(_cargo_system):
		_hud.set_cargo_system(_cargo_system)
	_repulsorlift_system.set_debug_visualization_enabled(_debug_overview_enabled)
	_update_fcc_snapshot(false)
	_publish_telemetry()


func _unhandled_input(event: InputEvent) -> void:
	if not _ship.is_pilot_ready():
		return

	if _hud.is_cargo_manifest_open():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F4 or event.physical_keycode == KEY_F4 or event.keycode == KEY_ESCAPE:
				_hud.close_cargo_manifest()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and (event.keycode == KEY_F4 or event.physical_keycode == KEY_F4):
		if event.pressed and not event.echo:
			_hud.toggle_cargo_manifest()
			get_viewport().set_input_as_handled()
		return

	if _hud.is_display_settings_open():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F10 or event.physical_keycode == KEY_F10 or event.keycode == KEY_ESCAPE:
				_hud.close_display_settings()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and (event.keycode == KEY_F10 or event.physical_keycode == KEY_F10):
		if event.pressed and not event.echo:
			_hud.toggle_display_settings()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ship_camera_toggle") and not _debug_interaction_mode:
		_camera_controller.toggle_view()
		_cockpit_recenter_time_remaining = -1.0
		_publish_telemetry()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ship_field_toggle") and not _debug_interaction_mode:
		_toggle_field_state()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ship_assist_toggle") and not _debug_interaction_mode:
		var next_assist: bool = not _fcc.assistance_enabled
		_fcc.set_assistance_enabled(next_assist)
		if next_assist and _field_power_command <= 0.005 and not _space_brake_pressed:
			_space_throttle_engaged = false
		_update_fcc_snapshot(
			_field_state == FieldState.ONLINE and not _ship.freeze
		)
		_publish_telemetry()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and not _debug_interaction_mode:
		if event.keycode == KEY_B or event.physical_keycode == KEY_B:
			_space_brake_pressed = event.pressed
			if event.pressed and _is_space_mode_environment() and _field_state == FieldState.ONLINE:
				_space_throttle_engaged = true
				_field_power_command = 0.0
			_publish_telemetry()
			get_viewport().set_input_as_handled()
			return

	var jump_pressed: bool = (InputMap.has_action("ship_jump") and event.is_action_pressed("ship_jump")) or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_J or event.physical_keycode == KEY_J))
	if jump_pressed and not _debug_interaction_mode:
		_trigger_fixed_jump()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_N or event.physical_keycode == KEY_N) and not _debug_interaction_mode:
		_resolve_environment_manager()
		if is_instance_valid(_planet_environment) and _planet_environment.has_method("cycle_surface_waypoint"):
			_planet_environment.call("cycle_surface_waypoint")
			_publish_telemetry()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_camera_look_mode = not _camera_look_mode
			if _camera_look_mode:
				_cockpit_recenter_time_remaining = -1.0
			elif not _camera_controller.is_external_view():
				_cockpit_recenter_time_remaining = COCKPIT_RECENTER_DELAY_SECONDS
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

		if _field_state == FieldState.ONLINE and not _require_neutral_controls:
			var next_roll := clampf(
				_roll_command + event.screen_relative.x * flight_control_mouse_sensitivity,
				-1.0,
				1.0
			)
			var next_pitch := clampf(
				_pitch_command + pitch_command_delta_from_mouse_y(
					event.screen_relative.y,
					flight_control_mouse_sensitivity
				),
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
		_cockpit_recenter_time_remaining = -1.0
		_debug_interaction_mode = false
		_camera_controller.activate_cockpit_view()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_publish_telemetry()
	elif not pilot_ready and _pilot_was_ready:
		_pilot_was_ready = false
		_camera_look_mode = false
		_cockpit_recenter_time_remaining = -1.0
		_debug_interaction_mode = false
		_roll_command = 0.0
		_pitch_command = 0.0
		_space_throttle_engaged = false
		_space_brake_pressed = false
		_camera_controller.reset_camera_state()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_publish_telemetry()

	if pilot_ready and not _camera_look_mode and not _camera_controller.is_external_view() and _cockpit_recenter_time_remaining >= 0.0:
		if _cockpit_recenter_time_remaining > 0.0:
			_cockpit_recenter_time_remaining = maxf(_cockpit_recenter_time_remaining - delta, 0.0)
		elif _camera_controller.recenter_cockpit_camera(delta):
			_publish_telemetry()
		else:
			_cockpit_recenter_time_remaining = -1.0
			_publish_telemetry()

	if not pilot_ready:
		if _hud.is_display_settings_open():
			_hud.close_display_settings()
		if _field_state != FieldState.OFF:
			_turn_field_off()
		_update_fcc_snapshot(false)
		if _repulsorlift_system.has_method("set_space_assist_override"):
			_repulsorlift_system.call("set_space_assist_override", false)
		_repulsorlift_system.apply_flight_control_forces(
			false, 0.0, DEFAULT_VECTOR_DISTRIBUTION_DEGREES, 0.0, 0.0, 0.0,
			0.0, 1.2, delta
		)
		return

	var telemetry_changed: bool = false

	if _startup_misfire_time_remaining > 0.0:
		_startup_misfire_time_remaining = maxf(_startup_misfire_time_remaining - delta, 0.0)
		if _startup_misfire_time_remaining <= 0.0:
			_startup_misfire_message = ""
			telemetry_changed = true

	if _field_state == FieldState.STARTING:
		_startup_time_remaining = maxf(_startup_time_remaining - delta, 0.0)
		if _startup_time_remaining <= 0.0:
			var ignition_ok: bool = true
			if is_instance_valid(_vane_controller) and _vane_controller.has_method("roll_startup_success"):
				ignition_ok = bool(_vane_controller.call("roll_startup_success"))
			if ignition_ok:
				_startup_misfire_message = ""
				_startup_misfire_time_remaining = 0.0
				_set_field_state(FieldState.ONLINE)
				telemetry_changed = false
			else:
				_startup_misfire_message = "FIELD STARTUP MISFIRE (<25% VANE INTEGRITY) — RETRY (F)"
				_startup_misfire_time_remaining = 4.5
				_turn_field_off()
				telemetry_changed = false

	if _field_state == FieldState.ONLINE:
		if not _hud.is_display_settings_open() and not _hud.is_cargo_manifest_open():
			telemetry_changed = _update_online_commands(delta) or telemetry_changed
		telemetry_changed = _update_actuator_outputs(delta) or telemetry_changed
	elif not is_zero_approx(_yaw_command):
		_yaw_command = 0.0
		telemetry_changed = true

	var control_available: bool = (
		_field_state == FieldState.ONLINE
		and not _ship.freeze
	)
	_update_fcc_snapshot(control_available, delta)

	var space_assist_active: bool = bool(_fcc_snapshot.get("fcc_space_mode_active", false)) and _fcc.assistance_enabled
	var space_assist_force: Vector3 = Vector3(_fcc_snapshot.get("fcc_space_assist_force_world", Vector3.ZERO))
	if _repulsorlift_system.has_method("set_space_assist_override"):
		_repulsorlift_system.call("set_space_assist_override", space_assist_active, space_assist_force)

	_repulsorlift_system.apply_flight_control_forces(
		_field_state == FieldState.ONLINE,
		_field_power_output,
		_vector_distribution_actual_degrees,
		float(_fcc_snapshot.get("fcc_pitch_output", 0.0)),
		float(_fcc_snapshot.get("fcc_roll_output", 0.0)),
		float(_fcc_snapshot.get("fcc_yaw_output", 0.0)),
		float(_fcc_snapshot.get("fcc_vane_redistribution_fraction", 0.0)),
		float(_fcc_snapshot.get("fcc_maximum_vane_output_multiplier", 1.2)),
		delta
	)

	if telemetry_changed:
		_publish_telemetry()

	_telemetry_time_remaining -= delta
	if _telemetry_time_remaining <= 0.0:
		_telemetry_time_remaining = TELEMETRY_UPDATE_INTERVAL_SECONDS
		_publish_telemetry()


func _is_space_mode_environment() -> bool:
	if not is_instance_valid(_environment_manager):
		_resolve_environment_manager()
	if is_instance_valid(_environment_manager):
		if _environment_manager.has_method("get_environment_type_name"):
			if str(_environment_manager.call("get_environment_type_name")) == "LOCAL_SPACE":
				return true
		if _environment_manager.has_method("is_atmosphere_enabled") and not bool(_environment_manager.call("is_atmosphere_enabled")):
			var grav_mag: float = _planetary_gravity_body.call("get_local_gravity_vector_world").length() if is_instance_valid(_planetary_gravity_body) and _planetary_gravity_body.has_method("get_local_gravity_vector_world") else 0.0
			if grav_mag < 0.5:
				return true
	return false


func _update_fcc_snapshot(control_available: bool, delta_seconds: float = 0.0) -> void:
	if not is_instance_valid(_fcc) or not is_instance_valid(_ship):
		_fcc_snapshot.clear()
		return
	_fcc_snapshot = _fcc.calculate_control_outputs(
		_pitch_command,
		_roll_command,
		_yaw_command,
		_ship.angular_velocity,
		_ship.global_basis,
		control_available,
		delta_seconds
	)
	var in_space: bool = _is_space_mode_environment()
	var brake_req: bool = _space_brake_pressed or _vector_distribution_degrees > 95.0
	if in_space and control_available and (_field_power_command > 0.005 or brake_req):
		_space_throttle_engaged = true
	var rated_gross: float = _ship.get_design_gross_mass_kg() if _ship.has_method("get_design_gross_mass_kg") else _ship.mass
	var ref_g: float = _repulsorlift_system.reference_gravity_mps2 if is_instance_valid(_repulsorlift_system) else 9.81
	var main_twr: float = _repulsorlift_system.get_main_rear_effective_authority_twr() if is_instance_valid(_repulsorlift_system) and _repulsorlift_system.has_method("get_main_rear_effective_authority_twr") else 1.5
	var space_snap: Dictionary = _fcc.calculate_space_assist_command(
		_ship.linear_velocity,
		_ship.global_basis,
		_ship.mass,
		rated_gross,
		ref_g,
		main_twr,
		in_space,
		_field_power_command,
		_space_throttle_engaged,
		brake_req,
		control_available
	)
	_fcc_snapshot.merge(space_snap, true)


func _toggle_field_state() -> void:
	match _field_state:
		FieldState.OFF:
			var lag_delay: float = float(_vane_controller.call("get_effective_lag_multiplier")) if is_instance_valid(_vane_controller) and _vane_controller.has_method("get_effective_lag_multiplier") else 0.0
			_startup_time_remaining = maxf(startup_duration_seconds * (1.0 + lag_delay * 1.1), 0.1)
			_startup_misfire_message = ""
			_startup_misfire_time_remaining = 0.0
			_space_throttle_engaged = false
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
	_space_throttle_engaged = false
	_space_brake_pressed = false
	_update_fcc_snapshot(false)
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
		if _is_space_mode_environment():
			_space_throttle_engaged = true
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
		if _is_space_mode_environment() and _vector_distribution_degrees > 95.0:
			_space_throttle_engaged = true

	if not is_equal_approx(new_yaw, _yaw_command):
		_yaw_command = new_yaw
		changed = true

	return changed


func _update_actuator_outputs(delta: float) -> bool:
	var changed: bool = false
	var lag_mult: float = float(_vane_controller.call("get_effective_lag_multiplier")) if is_instance_valid(_vane_controller) and _vane_controller.has_method("get_effective_lag_multiplier") else 0.0
	var response_scale: float = clampf(1.0 - lag_mult, 0.20, 1.0)
	var new_power_output: float = move_toward(
		_field_power_output,
		_field_power_command,
		field_power_output_rate_per_second * response_scale * delta
	)
	if not is_equal_approx(new_power_output, _field_power_output):
		_field_power_output = new_power_output
		changed = true

	var new_vector_output: float = move_toward(
		_vector_distribution_actual_degrees,
		_vector_distribution_degrees,
		vector_output_change_degrees_per_second * response_scale * delta
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
		"cockpit_camera_centered": _camera_controller.is_cockpit_camera_centered(),
		"cockpit_camera_fov_degrees": _camera_controller.get_cockpit_fov_degrees(),
		"debug_overview_enabled": _debug_overview_enabled,
		"debug_interaction_mode": _debug_interaction_mode,
		"ship_mass_kg": _ship.mass,
		"ship_position": _ship.global_position,
		"ship_linear_velocity": _ship.linear_velocity,
		"ship_angular_velocity": _ship.angular_velocity,
		"ship_global_basis": _ship.global_basis,
		"view_camera_global_basis": _camera_controller.get_active_camera_global_basis(),
		"ship_gravity_world": _planetary_gravity_body.call("get_local_gravity_vector_world") if is_instance_valid(_planetary_gravity_body) else _ship.get_gravity(),
		"ship_is_sleeping": _ship.sleeping,
		"center_of_mass_mode": "AUTO" if _ship.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_AUTO else "CUSTOM",
		"rigid_body_frozen": _ship.freeze,
		"physics_output_connected": true,
		"controls_armed": not _require_neutral_controls,
		"startup_misfire_message": _startup_misfire_message,
		"ship_definition_id": _ship.get_ship_definition().ship_id if _ship.has_method("get_ship_definition") and _ship.get_ship_definition() != null else "",
	}
	snapshot.merge(_fcc_snapshot, true)
	snapshot.merge(_repulsorlift_system.get_telemetry(), true)
	if is_instance_valid(_atmospheric_flight_model):
		snapshot.merge(_atmospheric_flight_model.get_telemetry(), true)
	if is_instance_valid(_flight_sensor_suite):
		snapshot.merge(_flight_sensor_suite.get_instrument_snapshot(), true)
	if is_instance_valid(_cargo_system):
		snapshot.merge(_cargo_system.call("get_telemetry"), true)
	if not is_instance_valid(_environment_manager) or not is_instance_valid(_exclusion_origin) or not is_instance_valid(_station_environment) or not is_instance_valid(_planet_environment):
		_resolve_environment_manager()
	var exclusion_pos: Vector3 = _exclusion_origin.global_position if is_instance_valid(_exclusion_origin) else Vector3.ZERO
	var jump_context: Dictionary = JUMP_ENVELOPE_EVALUATOR_SCRIPT.build_context_from_nodes(
		_ship, snapshot, _environment_manager, _field_state_name(), exclusion_pos
	)
	snapshot.merge(JUMP_ENVELOPE_EVALUATOR_SCRIPT.evaluate(jump_context), true)
	if is_instance_valid(_station_environment):
		if _station_environment.has_method("get_station_telemetry"):
			snapshot.merge(_station_environment.call("get_station_telemetry"), true)
		if _station_environment.has_method("get_celestial_telemetry"):
			snapshot.merge(_station_environment.call("get_celestial_telemetry"), true)
	if is_instance_valid(_planet_environment):
		if _planet_environment.has_method("get_surface_navigation_telemetry"):
			snapshot.merge(_planet_environment.call("get_surface_navigation_telemetry", _ship.global_position, _ship.global_basis), true)
		if _planet_environment.has_method("get_celestial_telemetry"):
			snapshot.merge(_planet_environment.call("get_celestial_telemetry"), true)
	var sim_clock: Node = get_node_or_null("/root/SimulationClock")
	if is_instance_valid(sim_clock):
		snapshot["sim_clock_seconds"] = float(sim_clock.call("get_time_seconds"))
		snapshot["sim_clock_formatted"] = str(sim_clock.call("get_formatted_clock"))
		snapshot["sim_clock_jumps"] = int(sim_clock.call("get_jump_count"))
		if sim_clock.has_method("get_total_celestial_time_seconds"):
			snapshot["celestial_clock_seconds"] = float(sim_clock.call("get_total_celestial_time_seconds"))
			snapshot["celestial_clock_formatted"] = str(sim_clock.call("get_formatted_celestial_clock"))
	var coordinator: Node = get_node_or_null("/root/TransitionCoordinator")
	if is_instance_valid(coordinator):
		snapshot.merge(coordinator.call("get_telemetry"), true)
		var active_route: Resource = coordinator.call("get_default_route_for_environment", str(snapshot.get("jump_environment_id", "")), str(snapshot.get("jump_environment_type", "")))
		if active_route != null:
			snapshot["route_id"] = str(active_route.get("route_id"))
			snapshot["route_display_name"] = str(active_route.get("display_name"))
			snapshot["route_destination_id"] = str(active_route.get("destination_location_id"))
	_hud.update_telemetry(snapshot)


func _trigger_fixed_jump() -> void:
	var coordinator: Node = get_node_or_null("/root/TransitionCoordinator")
	if is_instance_valid(coordinator) and coordinator.has_method("request_jump"):
		coordinator.call("request_jump", _ship)
		_publish_telemetry()


func _resolve_environment_manager() -> void:
	var world_root: Node = _ship.get_parent() if is_instance_valid(_ship) else get_node_or_null("../..")
	if not is_instance_valid(_environment_manager):
		if is_instance_valid(world_root):
			_environment_manager = world_root.get_node_or_null("EnvironmentManager")
		if not is_instance_valid(_environment_manager) and is_inside_tree():
			_environment_manager = get_tree().get_first_node_in_group("environment_manager")
	if not is_instance_valid(_exclusion_origin) and is_instance_valid(world_root):
		_exclusion_origin = world_root.get_node_or_null("OrbitalStationBody") as Node3D
	if not is_instance_valid(_station_environment) and is_instance_valid(world_root) and world_root.is_in_group("station_environment"):
		_station_environment = world_root
	if not is_instance_valid(_planet_environment) and is_instance_valid(world_root) and world_root.has_method("get_surface_navigation_telemetry"):
		_planet_environment = world_root


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
