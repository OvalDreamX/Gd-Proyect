extends CanvasLayer
class_name FlightHUD

## Presentation-only HUD for Phase 2A.
## Receives telemetry snapshots from ShipFlightController; it does not read
## input, calculate forces, or change ship state.

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
var _mass_label: Label
var _physics_label: Label
var _pitch_roll_label: Label
var _instruction_label: Label


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
	var mass_kg: float = float(telemetry.get("ship_mass_kg", 0.0))
	var body_frozen: bool = bool(telemetry.get("rigid_body_frozen", true))
	var physics_connected: bool = bool(telemetry.get("physics_output_connected", false))
	var controls_armed: bool = bool(telemetry.get("controls_armed", true))
	
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
			if controls_armed:
				_instruction_label.text = "FIELD ONLINE  |  COMMANDS ARE NOT YET CONNECTED TO PHYSICS"
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
	_mass_label.text = "SHIP MASS         %s kg" % String.num(mass_kg, 0)

	if physics_connected:
		_physics_label.text = "FORCE OUTPUT      CONNECTED"
		_physics_label.add_theme_color_override("font_color", COLOR_ONLINE)
	else:
		_physics_label.text = "FORCE OUTPUT      DISABLED (PHASE 2A)"
		_physics_label.add_theme_color_override("font_color", COLOR_WARNING)

	_physics_label.text += "\nRIGID BODY        %s" % ("FROZEN" if body_frozen else "NOT FROZEN")


func _build_hud() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var system_panel := _create_panel(root, Vector2(20.0, 20.0), Vector2(360.0, 232.0))
	var system_content := _create_panel_content(system_panel)
	_add_label(system_content, "REPULSORLIFT CONTROL", 16, COLOR_ACCENT)
	_field_state_label = _add_label(system_content, "FIELD STATE       OFF", 15, COLOR_MUTED)
	_field_power_label = _add_label(system_content, "POWER SETPOINT       0.0%", 14, COLOR_TEXT)
	_field_power_output_label = _add_label(system_content, "POWER OUTPUT         0.0%", 14, COLOR_TEXT)
	_vector_label = _add_label(system_content, "VECTOR SETPOINT      0.0°", 14, COLOR_TEXT)
	_vector_output_label = _add_label(system_content, "VECTOR ACTUAL        0.0°", 14, COLOR_TEXT)
	_add_label(system_content, "0° MAIN  |  90° LIFT  |  110° COMBINED BRAKE", 11, COLOR_MUTED)
	_yaw_label = _add_label(system_content, "YAW COMMAND      +0.00", 14, COLOR_TEXT)

	var status_panel := _create_anchored_panel(root)
	var status_content := _create_panel_content(status_panel)
	_add_label(status_content, "PROTOTYPE STATUS", 16, COLOR_ACCENT)
	_mass_label = _add_label(status_content, "SHIP MASS         -- kg", 14, COLOR_TEXT)
	_physics_label = _add_label(status_content, "FORCE OUTPUT      DISABLED (PHASE 2A)", 13, COLOR_WARNING)
	_pitch_roll_label = _add_label(status_content, "PITCH / ROLL      INPUT ROUTING: PHASE 2B", 12, COLOR_MUTED)

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

	var instruction_panel := PanelContainer.new()
	instruction_panel.name = "InstructionPanel"
	instruction_panel.anchor_left = 0.5
	instruction_panel.anchor_right = 0.5
	instruction_panel.anchor_top = 1.0
	instruction_panel.anchor_bottom = 1.0
	instruction_panel.offset_left = -330.0
	instruction_panel.offset_right = 330.0
	instruction_panel.offset_top = -64.0
	instruction_panel.offset_bottom = -18.0
	instruction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	instruction_panel.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(instruction_panel)

	var instruction_content := _create_panel_content(instruction_panel)
	_instruction_label = _add_label(
		instruction_content,
		"F FIELD ON/OFF     W/S FIELD POWER     Q/E VECTOR     A/D YAW",
		12,
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
	panel.offset_bottom = 190.0
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
