extends CanvasLayer
class_name FlightHUD

## The cockpit flight display is intentionally separate from diagnostics.
## All legacy force, vane, FCC and body telemetry is available only while F3
## is active. This CanvasLayer never reads input or modifies simulation state.

const HUD_OVERLAY_SCRIPT = preload("res://scripts/flight_hud_overlay.gd")

const COLOR_TEXT: Color = Color(0.78, 0.88, 0.92, 1.0)
const COLOR_MUTED: Color = Color(0.47, 0.64, 0.70, 1.0)
const COLOR_ACCENT: Color = Color(0.30, 0.83, 0.90, 1.0)

var _flight_display: Control
var _debug_panel: PanelContainer
var _debug_text_label: Label


func _ready() -> void:
	layer = 20
	_build_hud()
	visible = false


func update_telemetry(telemetry: Dictionary) -> void:
	if not is_instance_valid(_flight_display):
		return

	_flight_display.call("update_telemetry", telemetry)

	var debug_enabled: bool = bool(telemetry.get("debug_overview_enabled", false))
	var camera_view: String = str(telemetry.get("camera_view", "COCKPIT"))
	_flight_display.visible = camera_view == "COCKPIT" and not debug_enabled
	_debug_panel.visible = debug_enabled

	if debug_enabled:
		_update_debug_text(telemetry)


func _build_hud() -> void:
	_flight_display = Control.new()
	_flight_display.name = "CockpitFlightDisplay"
	_flight_display.set_script(HUD_OVERLAY_SCRIPT)
	_flight_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flight_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flight_display)

	_debug_panel = PanelContainer.new()
	_debug_panel.name = "F3DiagnosticsPanel"
	_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_panel.offset_left = 22.0
	_debug_panel.offset_top = 22.0
	_debug_panel.offset_right = -22.0
	_debug_panel.offset_bottom = -22.0
	_debug_panel.visible = false
	_debug_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_debug_panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_debug_panel.add_child(content)

	var title := Label.new()
	title.text = "FLIGHT / REPULSORLIFT / FCC DIAGNOSTICS"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "F3 CLOSES DIAGNOSTICS  |  FORCE ARROWS ARE SHOWN IN THE WORLD  |  SHIFT WHILE RMB-LOOKING RELEASES THE CURSOR"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(subtitle)

	var divider := HSeparator.new()
	content.add_child(divider)

	var scroll := ScrollContainer.new()
	scroll.name = "DiagnosticsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	_debug_text_label = Label.new()
	_debug_text_label.name = "DiagnosticsText"
	_debug_text_label.add_theme_font_size_override("font_size", 12)
	_debug_text_label.add_theme_color_override("font_color", COLOR_TEXT)
	_debug_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_text_label.custom_minimum_size = Vector2(0.0, 600.0)
	_debug_text_label.custom_maximum_size = Vector2(1180.0, 0.0)
	scroll.add_child(_debug_text_label)


func _update_debug_text(telemetry: Dictionary) -> void:
	var to_degrees: float = 180.0 / PI
	var field_state: String = str(telemetry.get("field_state", "OFF"))
	var power_command: float = float(telemetry.get("field_power_command", 0.0))
	var power_output: float = float(telemetry.get("field_power_output", 0.0))
	var vector_command: float = float(telemetry.get("vector_distribution_degrees", 90.0))
	var vector_actual: float = float(telemetry.get("vector_distribution_actual_degrees", 90.0))
	var pitch_command: float = float(telemetry.get("pitch_command", 0.0))
	var roll_command: float = float(telemetry.get("roll_command", 0.0))
	var yaw_command: float = float(telemetry.get("yaw_command", 0.0))
	var input_mode: String = str(telemetry.get("input_mode", "FLIGHT CONTROL"))
	var camera_view: String = str(telemetry.get("camera_view", "COCKPIT"))
	var camera_yaw: float = float(telemetry.get("camera_yaw_degrees", 0.0))
	var camera_pitch: float = float(telemetry.get("camera_pitch_degrees", 0.0))
	var mass_kg: float = float(telemetry.get("ship_mass_kg", 0.0))
	var position: Vector3 = telemetry.get("ship_position", Vector3.ZERO)
	var velocity: Vector3 = telemetry.get("ship_linear_velocity", Vector3.ZERO)
	var angular_velocity: Vector3 = telemetry.get("ship_angular_velocity", Vector3.ZERO)
	var basis: Basis = telemetry.get("ship_global_basis", Basis.IDENTITY)
	basis = basis.orthonormalized()
	var pitch_attitude: float = rad_to_deg(asin(clampf(-basis.z.y, -1.0, 1.0)))
	var roll_attitude: float = rad_to_deg(atan2(basis.x.y, basis.y.y))
	var forward: Vector3 = -basis.z.normalized()
	var heading: float = fposmod(rad_to_deg(atan2(-forward.x, -forward.z)), 360.0)
	var gravity: float = float(telemetry.get("lift_gravity_magnitude", 0.0))
	var net_force: Vector3 = telemetry.get("lift_force_vector", Vector3.ZERO)
	var net_force_newtons: float = float(telemetry.get("lift_force_newtons", 0.0))
	var net_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	var main_direction: Vector3 = telemetry.get("lift_main_direction_world", Vector3.ZERO)
	var actual_twr: float = float(telemetry.get("lift_actual_twr", 0.0))
	var maximum_twr: float = float(telemetry.get("lift_maximum_twr", 0.0))
	var hover_power: float = float(telemetry.get("lift_hover_power_percent", -1.0))
	var vane_states: Array = telemetry.get("vane_states", [])
	var vane_contributions: Array = telemetry.get("lift_vane_contributions", [])
	var force_vectors: Array = telemetry.get("lift_force_vectors", [])
	var fcc_desired: Vector3 = telemetry.get("fcc_desired_rate_local_rad_s", Vector3.ZERO)
	var fcc_actual: Vector3 = telemetry.get("fcc_actual_rate_local_rad_s", Vector3.ZERO)
	var fcc_error: Vector3 = telemetry.get("fcc_rate_error_local_rad_s", Vector3.ZERO)
	var fcc_output: Vector3 = telemetry.get("fcc_control_output_by_axis", Vector3.ZERO)
	var fcc_saturated_axes: PackedStringArray = PackedStringArray()
	if bool(telemetry.get("fcc_pitch_saturated", false)):
		fcc_saturated_axes.append("PITCH")
	if bool(telemetry.get("fcc_roll_saturated", false)):
		fcc_saturated_axes.append("ROLL")
	if bool(telemetry.get("fcc_yaw_saturated", false)):
		fcc_saturated_axes.append("YAW")
	var saturation_text: String = ", ".join(fcc_saturated_axes) if not fcc_saturated_axes.is_empty() else "NONE"

	var hover_threshold_text: String = "UNREACHABLE"
	if hover_power >= 0.0:
		hover_threshold_text = "%.1f%%" % hover_power

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[ PILOT / VIEW ]")
	lines.append("Field state: %s | Power setpoint/output: %.1f%% / %.1f%% | Vector setpoint/output: %.1f° / %.1f°" % [field_state, power_command * 100.0, power_output * 100.0, vector_command, vector_actual])
	lines.append("Pilot commands: pitch %.3f | roll %.3f | yaw %.3f | Controls armed: %s" % [pitch_command, roll_command, yaw_command, str(bool(telemetry.get("controls_armed", false)))])
	lines.append("Camera: %s | Camera look yaw/pitch: %+.2f° / %+.2f° | Input mode: %s | Debug UI interaction: %s" % [camera_view, camera_yaw, camera_pitch, input_mode, str(bool(telemetry.get("debug_interaction_mode", false)))])
	lines.append("FCC: %s | Control available: %s | Output P/R/Y: %+.3f / %+.3f / %+.3f" % ["ASSISTED RATE CONTROL" if bool(telemetry.get("fcc_assistance_enabled", true)) else "DIRECT VANES", str(bool(telemetry.get("fcc_control_available", false))), fcc_output.x, fcc_output.z, fcc_output.y])
	lines.append("")
	lines.append("[ FLIGHT STATE ]")
	lines.append("Mass: %.1f kg | Position: (%.2f, %.2f, %.2f) m | Local altitude: %.2f m" % [mass_kg, position.x, position.y, position.z, position.y])
	lines.append("Velocity: (%.3f, %.3f, %.3f) m/s | Speed: %.3f m/s | Vertical speed: %+.3f m/s" % [velocity.x, velocity.y, velocity.z, velocity.length(), velocity.y])
	lines.append("Attitude: pitch %+.2f° | roll %+.2f° | heading %03.0f°" % [pitch_attitude, roll_attitude, heading])
	lines.append("Angular velocity world: (%.4f, %.4f, %.4f) rad/s | Magnitude: %.4f rad/s" % [angular_velocity.x, angular_velocity.y, angular_velocity.z, angular_velocity.length()])
	lines.append("Rigid body frozen: %s | Sleeping: %s | COM mode: %s | Physics output connected: %s" % [str(bool(telemetry.get("rigid_body_frozen", false))), str(bool(telemetry.get("ship_is_sleeping", false))), str(telemetry.get("center_of_mass_mode", "AUTO")), str(bool(telemetry.get("physics_output_connected", false)))])
	lines.append("")
	lines.append("[ FCC RATE LOOP ]")
	lines.append("Requested local rate P/R/Y: %+.2f / %+.2f / %+.2f deg/s" % [fcc_desired.x * to_degrees, fcc_desired.z * to_degrees, fcc_desired.y * to_degrees])
	lines.append("Actual local rate P/R/Y: %+.2f / %+.2f / %+.2f deg/s" % [fcc_actual.x * to_degrees, fcc_actual.z * to_degrees, fcc_actual.y * to_degrees])
	lines.append("Rate error P/R/Y: %+.2f / %+.2f / %+.2f deg/s | Saturation: %s" % [fcc_error.x * to_degrees, fcc_error.z * to_degrees, fcc_error.y * to_degrees, saturation_text])
	lines.append("Rate gain: %.3f | Maximum FCC output: %.3f" % [float(telemetry.get("fcc_rate_response_gain", 0.0)), float(telemetry.get("fcc_maximum_control_output", 0.0))])
	lines.append("")
	lines.append("[ FORCE / LIFT ]")
	lines.append("Total force: (%.1f, %.1f, %.1f) N | Magnitude: %.1f N" % [net_force.x, net_force.y, net_force.z, net_force_newtons])
	lines.append("Main vector world: (%.3f, %.3f, %.3f) | Applied torque: (%.2f, %.2f, %.2f) N·m" % [main_direction.x, main_direction.y, main_direction.z, net_torque.x, net_torque.y, net_torque.z])
	lines.append("Main vector convention: 0° forward (-Z) | 90° ship-up (+Y) | 110° up/rearward blend")
	lines.append("Vertical TWR: %.3f / %.3f | Gravity: %.3f m/s² | Hover threshold: %s" % [actual_twr, maximum_twr, gravity, hover_threshold_text])
	lines.append("Maneuver authority fraction: %.4f | Reference gravity: %.3f m/s²" % [float(telemetry.get("maneuver_authority_fraction", 0.0)), float(telemetry.get("reference_gravity_mps2", 9.81))])
	lines.append("")
	lines.append("[ VANE CONFIGURATION / CONDITION ]")
	lines.append("Configuration valid: %s | Vane count: %d | Healthy count: %d" % [str(bool(telemetry.get("vane_configuration_valid", false))), int(telemetry.get("vane_count", 0)), int(telemetry.get("vane_healthy_count", 0))])
	for vane_value in vane_states:
		var vane: Dictionary = vane_value
		lines.append("%s | group=%s | enabled=%s | integrity=%.3f | failed=%s | nominal=%.3f TWR | effective=%.3f TWR | local pos=%s" % [str(vane.get("vane_id", "UNKNOWN")), str(vane.get("group_id", "UNKNOWN")), str(vane.get("enabled", true)), float(vane.get("integrity", 0.0)), str(vane.get("failed", false)), float(vane.get("nominal_authority_twr", 0.0)), float(vane.get("effective_authority_twr", 0.0)), str(vane.get("local_position", Vector3.ZERO))])
	lines.append("")
	lines.append("[ INDIVIDUAL VANE CONTRIBUTIONS ]")
	if vane_contributions.is_empty():
		lines.append("No individual vane forces submitted on the current physics tick.")
	for contribution_value in vane_contributions:
		var contribution: Dictionary = contribution_value
		var vane_force: Vector3 = contribution.get("force_world", Vector3.ZERO)
		var vane_torque: Vector3 = contribution.get("torque_world", Vector3.ZERO)
		lines.append("%s | F=(%.1f, %.1f, %.1f) N | M=(%.2f, %.2f, %.2f) N·m | point=%s" % [str(contribution.get("vane_id", "UNKNOWN")), vane_force.x, vane_force.y, vane_force.z, vane_torque.x, vane_torque.y, vane_torque.z, str(contribution.get("application_point_world", Vector3.ZERO))])
	lines.append("")
	lines.append("[ APPLIED RESULTANT VECTORS ]")
	if force_vectors.is_empty():
		lines.append("No force vectors submitted on the current physics tick.")
	for force_value in force_vectors:
		var force_entry: Dictionary = force_value
		var applied_force: Vector3 = force_entry.get("force_world", Vector3.ZERO)
		lines.append("%s | kind=%s | magnitude=%.1f N | force=%s | application point=%s" % [str(force_entry.get("name", "FORCE")), str(force_entry.get("kind", "unknown")), applied_force.length(), str(applied_force), str(force_entry.get("application_point_world", Vector3.ZERO))])

	_debug_text_label.text = "\n".join(lines)
	_debug_text_label.custom_minimum_size.y = maxf(600.0, float(lines.size()) * 19.0)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.027, 0.038, 0.94)
	style.border_color = Color(0.16, 0.49, 0.57, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 11.0
	style.content_margin_bottom = 11.0
	return style
