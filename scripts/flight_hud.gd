extends CanvasLayer
class_name FlightHUD

## Presentation-only HUD. Receives telemetry snapshots from
## ShipFlightController; it does not read input or calculate simulation values.

const COLOR_TEXT: Color = Color(0.78, 0.88, 0.92, 1.0)
const COLOR_MUTED: Color = Color(0.47, 0.64, 0.70, 1.0)
const COLOR_ACCENT: Color = Color(0.30, 0.83, 0.90, 1.0)
const COLOR_WARNING: Color = Color(0.98, 0.72, 0.32, 1.0)
const COLOR_ONLINE: Color = Color(0.43, 0.90, 0.64, 1.0)

var _field_state_label: Label
var _field_power_label: Label
var _field_power_output_label: Label
var _vector_label: Label
var _vector_output_label: Label
var _yaw_label: Label
var _fcc_mode_label: Label
var _fcc_output_label: Label
var _mass_label: Label
var _physics_label: Label
var _pitch_roll_label: Label
var _camera_mode_label: Label
var _body_state_label: Label
var _linear_velocity_label: Label
var _angular_velocity_label: Label
var _com_mode_label: Label
var _lift_force_label: Label
var _lift_twr_label: Label
var _hover_power_label: Label
var _vane_status_label: Label
var _torque_output_label: Label
var _instruction_label: Label
var _debug_overview_panel: PanelContainer
var _debug_overview_label: Label


func _ready() -> void:
	layer = 20
	_build_hud()
	visible = false


func update_telemetry(telemetry: Dictionary) -> void:
	if not is_instance_valid(_field_state_label):
		return

	var field_state: String = str(telemetry.get("field_state", "OFF"))
	var power_command: float = float(telemetry.get("field_power_command", 0.0))
	var power_output: float = float(telemetry.get("field_power_output", 0.0))
	var vector_command_degrees: float = float(telemetry.get("vector_distribution_degrees", 0.0))
	var vector_actual_degrees: float = float(telemetry.get("vector_distribution_actual_degrees", 0.0))
	var yaw: float = float(telemetry.get("yaw_command", 0.0))
	var pitch: float = float(telemetry.get("pitch_command", 0.0))
	var roll: float = float(telemetry.get("roll_command", 0.0))
	var mass_kg: float = float(telemetry.get("ship_mass_kg", 0.0))
	var body_frozen: bool = bool(telemetry.get("rigid_body_frozen", true))
	var camera_view: String = str(telemetry.get("camera_view", "COCKPIT"))
	var input_mode: String = str(telemetry.get("input_mode", "FLIGHT CONTROL"))
	var camera_yaw: float = float(telemetry.get("camera_yaw_degrees", 0.0))
	var camera_pitch: float = float(telemetry.get("camera_pitch_degrees", 0.0))
	var debug_enabled: bool = bool(telemetry.get("debug_overview_enabled", false))
	var debug_interaction: bool = bool(telemetry.get("debug_interaction_mode", false))
	var ship_position: Vector3 = telemetry.get("ship_position", Vector3.ZERO)
	var linear_velocity: Vector3 = telemetry.get("ship_linear_velocity", Vector3.ZERO)
	var angular_velocity: Vector3 = telemetry.get("ship_angular_velocity", Vector3.ZERO)
	var is_sleeping: bool = bool(telemetry.get("ship_is_sleeping", false))
	var com_mode: String = str(telemetry.get("center_of_mass_mode", "AUTO"))
	var lift_force_vector: Vector3 = telemetry.get("lift_force_vector", Vector3.ZERO)
	var lift_force_n: float = float(telemetry.get("lift_force_newtons", 0.0))
	var actual_lift_twr: float = float(telemetry.get("lift_actual_twr", 0.0))
	var maximum_lift_twr: float = float(telemetry.get("lift_maximum_twr", 0.0))
	var hover_power_percent: float = float(telemetry.get("lift_hover_power_percent", -1.0))
	var gravity_magnitude: float = float(telemetry.get("lift_gravity_magnitude", 0.0))
	var field_online: bool = bool(telemetry.get("lift_field_online", false))
	var main_direction_world: Vector3 = telemetry.get("lift_main_direction_world", Vector3.UP)
	var applied_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	var torque_applied: bool = bool(telemetry.get("lift_torque_applied", false))
	var vane_count: int = int(telemetry.get("vane_count", 0))
	var vane_healthy_count: int = int(telemetry.get("vane_healthy_count", 0))
	var vane_configuration_valid: bool = bool(telemetry.get("vane_configuration_valid", false))
	var vane_states: Array = telemetry.get("vane_states", [])
	var vane_contributions: Array = telemetry.get("lift_vane_contributions", [])

	var fcc_assistance_enabled: bool = bool(telemetry.get("fcc_assistance_enabled", true))
	var fcc_control_available: bool = bool(telemetry.get("fcc_control_available", false))
	var fcc_desired_rate: Vector3 = telemetry.get("fcc_desired_rate_local_rad_s", Vector3.ZERO)
	var fcc_actual_rate: Vector3 = telemetry.get("fcc_actual_rate_local_rad_s", Vector3.ZERO)
	var fcc_rate_error: Vector3 = telemetry.get("fcc_rate_error_local_rad_s", Vector3.ZERO)
	var fcc_output: Vector3 = telemetry.get("fcc_control_output_by_axis", Vector3.ZERO)
	var fcc_any_saturated: bool = bool(telemetry.get("fcc_any_axis_saturated", false))
	var fcc_pitch_saturated: bool = bool(telemetry.get("fcc_pitch_saturated", false))
	var fcc_roll_saturated: bool = bool(telemetry.get("fcc_roll_saturated", false))
	var fcc_yaw_saturated: bool = bool(telemetry.get("fcc_yaw_saturated", false))

	_field_state_label.text = "FIELD STATE       %s" % field_state
	match field_state:
		"OFF":
			_field_state_label.add_theme_color_override("font_color", COLOR_MUTED)
			_instruction_label.text = "PRESS F TO START THE REPULSORLIFT GENERATOR"
		"STARTING":
			_field_state_label.add_theme_color_override("font_color", COLOR_WARNING)
			_instruction_label.text = "GENERATOR STARTING..."
		"ONLINE":
			_field_state_label.add_theme_color_override("font_color", COLOR_ONLINE)
			if bool(telemetry.get("controls_armed", true)):
				_instruction_label.text = (
					"FIELD ONLINE  |  MOUSE REQUESTS PITCH / ROLL RATE  |  A/D YAW"
				)
			else:
				_instruction_label.text = "RELEASE W/S, Q/E AND A/D TO ARM THE COMMAND INPUTS"
		_:
			_field_state_label.add_theme_color_override("font_color", COLOR_MUTED)
			_instruction_label.text = "FIELD STATE UNKNOWN"

	_field_power_label.text = "POWER SETPOINT       " + String.num(power_command * 100.0, 1) + "%"
	_field_power_output_label.text = "POWER OUTPUT         " + String.num(power_output * 100.0, 1) + "%"
	_vector_label.text = "VECTOR SETPOINT      " + String.num(vector_command_degrees, 1) + "°"
	_vector_output_label.text = "VECTOR ACTUAL        " + String.num(vector_actual_degrees, 1) + "°"
	_yaw_label.text = "YAW COMMAND      %s" % String.num(yaw, 2)

	_fcc_mode_label.text = "FCC ASSIST        %s" % (
		"ON / RATE CONTROL" if fcc_assistance_enabled else "OFF / DIRECT VANES"
	)
	_fcc_mode_label.add_theme_color_override(
		"font_color", COLOR_ONLINE if fcc_assistance_enabled else COLOR_WARNING
	)
	_fcc_output_label.text = "FCC OUTPUT P/R/Y  %+.2f / %+.2f / %+.2f" % [
		fcc_output.x, fcc_output.z, fcc_output.y
	]
	if fcc_any_saturated:
		_fcc_output_label.add_theme_color_override("font_color", COLOR_WARNING)
	else:
		_fcc_output_label.add_theme_color_override("font_color", COLOR_TEXT)

	_mass_label.text = "SHIP MASS         %s kg" % String.num(mass_kg, 0)
	_pitch_roll_label.text = "PITCH %+.2f    ROLL %+.2f" % [pitch, roll]
	_camera_mode_label.text = "VIEW %s    INPUT %s" % [camera_view, input_mode]
	_body_state_label.text = "BODY STATE        %s" % ("SLEEPING" if is_sleeping else "ACTIVE")
	_linear_velocity_label.text = "LINEAR SPEED      %.3f m/s" % linear_velocity.length()
	_angular_velocity_label.text = "ANGULAR SPEED     %.3f rad/s" % angular_velocity.length()
	_com_mode_label.text = "CENTER OF MASS    %s" % com_mode
	_lift_force_label.text = "TOTAL FORCE       %s N" % String.num(lift_force_n, 0)
	_lift_twr_label.text = "VERTICAL TWR      %.2f / %.2f" % [actual_lift_twr, maximum_lift_twr]
	_vane_status_label.text = "VANE ARRAY        %d REGISTERED / %d HEALTHY" % [vane_count, vane_healthy_count]
	_vane_status_label.add_theme_color_override(
		"font_color", COLOR_ONLINE if vane_configuration_valid else COLOR_WARNING
	)
	_torque_output_label.text = "TOTAL TORQUE      %.1f N·m %s" % [
		applied_torque.length(),
		"APPLIED" if torque_applied else "ZERO / STANDBY",
	]
	if hover_power_percent >= 0.0 and hover_power_percent <= 100.0:
		_hover_power_label.text = "HOVER THRESHOLD   %.1f%% OUTPUT" % hover_power_percent
	else:
		_hover_power_label.text = "HOVER THRESHOLD   UNREACHABLE"

	if field_online:
		_physics_label.text = "VANE FIELD        ONLINE"
		_physics_label.add_theme_color_override("font_color", COLOR_ONLINE)
	else:
		_physics_label.text = "VANE FIELD        STANDBY"
		_physics_label.add_theme_color_override("font_color", COLOR_MUTED)
	_physics_label.text += "\nRIGID BODY        %s" % ("FROZEN" if body_frozen else "ACTIVE")

	_debug_overview_panel.visible = debug_enabled
	if debug_enabled:
		var to_degrees: float = 180.0 / PI
		var saturation_text: String = "NONE"
		if fcc_any_saturated:
			var saturated_axes: PackedStringArray = PackedStringArray()
			if fcc_pitch_saturated:
				saturated_axes.append("PITCH")
			if fcc_roll_saturated:
				saturated_axes.append("ROLL")
			if fcc_yaw_saturated:
				saturated_axes.append("YAW")
			saturation_text = ", ".join(saturated_axes)

		var debug_text: String = (
			"VIEW: %s     INPUT: %s\n" % [camera_view, input_mode]
			+ "VIRTUAL PITCH: %+.3f     ROLL: %+.3f\n" % [pitch, roll]
			+ "CAMERA YAW: %+.1f°     PITCH: %+.1f°\n" % [camera_yaw, camera_pitch]
			+ "DEBUG UI INTERACTION: %s\n" % ("ACTIVE" if debug_interaction else "INACTIVE")
			+ "FCC MODE: %s     CONTROL AVAILABLE: %s\n" % [
				"ASSISTED RATE CONTROL" if fcc_assistance_enabled else "DIRECT VANE CONTROL",
				"YES" if fcc_control_available else "NO",
			]
			+ "FCC RATE TARGET P/R/Y: %+.1f / %+.1f / %+.1f deg/s\n" % [
				fcc_desired_rate.x * to_degrees,
				fcc_desired_rate.z * to_degrees,
				fcc_desired_rate.y * to_degrees,
			]
			+ "FCC RATE ACTUAL P/R/Y: %+.1f / %+.1f / %+.1f deg/s\n" % [
				fcc_actual_rate.x * to_degrees,
				fcc_actual_rate.z * to_degrees,
				fcc_actual_rate.y * to_degrees,
			]
			+ "FCC RATE ERROR P/R/Y: %+.1f / %+.1f / %+.1f deg/s\n" % [
				fcc_rate_error.x * to_degrees,
				fcc_rate_error.z * to_degrees,
				fcc_rate_error.y * to_degrees,
			]
			+ "FCC OUTPUT P/R/Y: %+.2f / %+.2f / %+.2f\n" % [
				fcc_output.x, fcc_output.z, fcc_output.y,
			]
			+ "FCC SATURATION: %s\n" % saturation_text
			+ "WORLD POS: (%.3f, %.3f, %.3f) m\n" % [ship_position.x, ship_position.y, ship_position.z]
			+ "LINEAR VEL: (%.3f, %.3f, %.3f) m/s\n" % [linear_velocity.x, linear_velocity.y, linear_velocity.z]
			+ "ANGULAR VEL: (%.3f, %.3f, %.3f) rad/s\n" % [angular_velocity.x, angular_velocity.y, angular_velocity.z]
			+ "NET FORCE: (%.0f, %.0f, %.0f) N\n" % [lift_force_vector.x, lift_force_vector.y, lift_force_vector.z]
			+ "LIFT TWR: %.2f / %.2f    GRAVITY: %.2f m/s²\n" % [actual_lift_twr, maximum_lift_twr, gravity_magnitude]
			+ "APPLIED TORQUE: (%.1f, %.1f, %.1f) N·m\n" % [applied_torque.x, applied_torque.y, applied_torque.z]
			+ "MAIN VECTOR: (%.2f, %.2f, %.2f)\n" % [main_direction_world.x, main_direction_world.y, main_direction_world.z]
			+ "MANEUVER AUTHORITY: %.3f / axis\n" % float(telemetry.get("maneuver_authority_fraction", 0.0))
			+ "VANE CONFIG: %s (%d registered)\n" % ["VALID" if vane_configuration_valid else "INVALID", vane_count]
		)
		for vane_state in vane_states:
			var state: Dictionary = vane_state
			debug_text += "%s [%s] integrity %.2f failed=%s authority %.3f TWR\n" % [
				str(state.get("vane_id", "UNKNOWN")),
				str(state.get("group_id", "UNKNOWN")),
				float(state.get("integrity", 0.0)),
				str(state.get("failed", false)),
				float(state.get("effective_authority_twr", 0.0)),
			]
		for vane_contribution in vane_contributions:
			var contribution: Dictionary = vane_contribution
			var vane_force: Vector3 = contribution.get("force_world", Vector3.ZERO)
			var vane_torque: Vector3 = contribution.get("torque_world", Vector3.ZERO)
			debug_text += "  VANE %s: F(%.0f, %.0f, %.0f) N | M(%.1f, %.1f, %.1f)\n" % [
				str(contribution.get("vane_id", "UNKNOWN")),
				vane_force.x, vane_force.y, vane_force.z,
				vane_torque.x, vane_torque.y, vane_torque.z,
			]
		for force_entry in telemetry.get("lift_force_vectors", []):
			var force_data: Dictionary = force_entry
			var applied_force: Vector3 = force_data.get("force_world", Vector3.ZERO)
			var applied_point: Vector3 = force_data.get("application_point_world", Vector3.ZERO)
			debug_text += "APPLIED %-13s | F %.0f N | P(%.2f, %.2f, %.2f)\n" % [
				str(force_data.get("name", "FORCE")), applied_force.length(),
				applied_point.x, applied_point.y, applied_point.z,
			]
		debug_text += "BODY: %s    COM MODE: %s" % ["SLEEPING" if is_sleeping else "ACTIVE", com_mode]
		_debug_overview_label.text = debug_text


func _build_hud() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var system_panel := _create_panel(root, Vector2(20.0, 20.0), Vector2(390.0, 270.0))
	var system_content := _create_panel_content(system_panel)
	_add_label(system_content, "REPULSORLIFT CONTROL", 16, COLOR_ACCENT)
	_field_state_label = _add_label(system_content, "FIELD STATE       OFF", 15, COLOR_MUTED)
	_field_power_label = _add_label(system_content, "POWER SETPOINT       0.0%", 14, COLOR_TEXT)
	_field_power_output_label = _add_label(system_content, "POWER OUTPUT         0.0%", 14, COLOR_TEXT)
	_vector_label = _add_label(system_content, "VECTOR SETPOINT      0.0°", 14, COLOR_TEXT)
	_vector_output_label = _add_label(system_content, "VECTOR ACTUAL        0.0°", 14, COLOR_TEXT)
	_add_label(system_content, "0° MAIN  |  90° LIFT  |  110° COMBINED BRAKE", 11, COLOR_MUTED)
	_yaw_label = _add_label(system_content, "YAW COMMAND      +0.00", 14, COLOR_TEXT)
	_fcc_mode_label = _add_label(system_content, "FCC ASSIST        ON / RATE CONTROL", 13, COLOR_ONLINE)
	_fcc_output_label = _add_label(system_content, "FCC OUTPUT P/R/Y  +0.00 / +0.00 / +0.00", 12, COLOR_TEXT)

	var status_panel := _create_anchored_panel(root)
	var status_content := _create_panel_content(status_panel)
	_add_label(status_content, "PROTOTYPE STATUS", 16, COLOR_ACCENT)
	_mass_label = _add_label(status_content, "SHIP MASS         -- kg", 14, COLOR_TEXT)
	_physics_label = _add_label(status_content, "VANE FIELD        STANDBY", 13, COLOR_MUTED)
	_pitch_roll_label = _add_label(status_content, "PITCH +0.00    ROLL +0.00", 12, COLOR_MUTED)
	_camera_mode_label = _add_label(status_content, "VIEW COCKPIT    INPUT FLIGHT CONTROL", 12, COLOR_MUTED)
	_body_state_label = _add_label(status_content, "BODY STATE        ACTIVE", 12, COLOR_TEXT)
	_linear_velocity_label = _add_label(status_content, "LINEAR SPEED      0.000 m/s", 12, COLOR_TEXT)
	_angular_velocity_label = _add_label(status_content, "ANGULAR SPEED     0.000 rad/s", 12, COLOR_TEXT)
	_com_mode_label = _add_label(status_content, "CENTER OF MASS    AUTO", 12, COLOR_TEXT)
	_lift_force_label = _add_label(status_content, "NET FORCE         0 N", 12, COLOR_TEXT)
	_lift_twr_label = _add_label(status_content, "LIFT TWR          0.00 / 1.10", 12, COLOR_TEXT)
	_hover_power_label = _add_label(status_content, "HOVER THRESHOLD   90.9% OUTPUT", 12, COLOR_TEXT)
	_vane_status_label = _add_label(status_content, "VANE ARRAY        7 REGISTERED / 7 HEALTHY", 12, COLOR_TEXT)
	_torque_output_label = _add_label(status_content, "NET TORQUE        0.0 N·m ZERO / STANDBY", 12, COLOR_MUTED)

	var reticle := Label.new()
	reticle.name = "AttitudeReferencePlaceholder"
	reticle.text = "+"
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.add_theme_color_override("font_color", Color(0.48, 0.78, 0.82, 0.65))
	reticle.add_theme_font_size_override("font_size", 24)
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.offset_left = -12.0
	reticle.offset_top = -12.0
	reticle.offset_right = 12.0
	reticle.offset_bottom = 12.0
	root.add_child(reticle)

	_debug_overview_panel = _create_panel(root, Vector2(20.0, 305.0), Vector2(600.0, 400.0))
	_debug_overview_panel.name = "DebugOverviewPanel"
	_debug_overview_panel.visible = false
	var debug_content := _create_panel_content(_debug_overview_panel)
	_add_label(debug_content, "FLIGHT / FCC / VANE DEBUG OVERVIEW", 13, COLOR_ACCENT)
	_debug_overview_label = _add_label(debug_content, "VIEW: COCKPIT", 12, COLOR_TEXT)

	var instruction_panel := PanelContainer.new()
	instruction_panel.name = "InstructionPanel"
	instruction_panel.anchor_left = 0.5
	instruction_panel.anchor_right = 0.5
	instruction_panel.anchor_top = 1.0
	instruction_panel.anchor_bottom = 1.0
	instruction_panel.offset_left = -430.0
	instruction_panel.offset_right = 430.0
	instruction_panel.offset_top = -64.0
	instruction_panel.offset_bottom = -18.0
	instruction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instruction_panel.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(instruction_panel)

	var instruction_content := _create_panel_content(instruction_panel)
	_instruction_label = _add_label(
		instruction_content,
		"F FIELD  |  W/S POWER  |  Q/E VECTOR  |  A/D YAW  |  MOUSE P/R RATE  |  V FCC ASSIST  |  C VIEW  |  RMB LOOK  |  SHIFT UI  |  F3 DEBUG",
		10,
		COLOR_TEXT
	)
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _create_panel(parent: Control, panel_position: Vector2, panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(panel)
	return panel


func _create_anchored_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PrototypeStatusPanel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -380.0
	panel.offset_right = -20.0
	panel.offset_top = 20.0
	panel.offset_bottom = 440.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	parent.add_child(panel)
	return panel


func _create_panel_content(panel: PanelContainer) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	panel.add_child(content)
	return content


func _add_label(parent: Container, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.027, 0.038, 0.86)
	style.border_color = Color(0.16, 0.49, 0.57, 0.88)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style
