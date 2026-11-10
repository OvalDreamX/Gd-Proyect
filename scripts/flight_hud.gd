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
var _debug_text_label: TextEdit
var _settings_overlay: Control
var _display_mode_option: OptionButton
var _resolution_option: OptionButton
var _hud_scale_option: OptionButton
var _resolution_label: Label
var _settings_hint: Label
var _settings_open: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 20
	_build_hud()
	_build_display_settings_overlay()
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
	title.text = "FLIGHT / ATMOSPHERE / REPULSORLIFT / FCC DIAGNOSTICS"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "F3 CLOSES DIAGNOSTICS  |  SCROLL THE TEXT BELOW  |  SHIFT WHILE RMB-LOOKING RELEASES THE CURSOR"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(subtitle)

	var divider := HSeparator.new()
	content.add_child(divider)

	# TextEdit owns its own vertical scrollbar and has a concrete minimum
	# viewport size. This avoids the nested Label/ScrollContainer sizing failure
	# that could leave the F3 panel visible but apparently empty on some layouts.
	_debug_text_label = TextEdit.new()
	_debug_text_label.name = "DiagnosticsText"
	_debug_text_label.editable = false
	_debug_text_label.selecting_enabled = true
	_debug_text_label.context_menu_enabled = true
	_debug_text_label.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_debug_text_label.add_theme_font_size_override("font_size", 12)
	_debug_text_label.add_theme_color_override("font_color", COLOR_TEXT)
	_debug_text_label.add_theme_color_override("font_readonly_color", COLOR_TEXT)
	_debug_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_debug_text_label.custom_minimum_size = Vector2(0.0, 260.0)
	var transparent_style := StyleBoxEmpty.new()
	_debug_text_label.add_theme_stylebox_override("normal", transparent_style)
	_debug_text_label.add_theme_stylebox_override("focus", transparent_style)
	_debug_text_label.add_theme_stylebox_override("read_only", transparent_style)
	content.add_child(_debug_text_label)


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
	var local_up_world: Vector3 = telemetry.get("atmosphere_up_world", Vector3.UP)
	if local_up_world.length_squared() <= 0.000001:
		local_up_world = Vector3.UP
	else:
		local_up_world = local_up_world.normalized()
	var local_vertical_speed: float = velocity.dot(local_up_world)
	var local_altitude: float = float(telemetry.get("atmosphere_altitude_m", position.y))
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
	var atmosphere_enabled: bool = bool(telemetry.get("atmosphere_enabled", false))
	var atmosphere_altitude: float = float(telemetry.get("atmosphere_altitude_m", 0.0))
	var atmosphere_density: float = float(telemetry.get("atmosphere_density_kg_m3", 0.0))
	var atmosphere_airspeed: float = float(telemetry.get("atmosphere_airspeed_mps", 0.0))
	var atmosphere_wind: Vector3 = telemetry.get("atmosphere_velocity_world", Vector3.ZERO)
	var atmosphere_mean_wind: Vector3 = telemetry.get("atmosphere_mean_wind_velocity_world", atmosphere_wind)
	var atmosphere_turbulence: Vector3 = telemetry.get("atmosphere_turbulence_velocity_world", Vector3.ZERO)
	var atmosphere_relative_velocity: Vector3 = telemetry.get("atmosphere_relative_velocity_world", Vector3.ZERO)
	var atmosphere_projected_area: float = float(telemetry.get("atmosphere_projected_area_m2", 0.0))
	var atmosphere_drag_coefficient: float = float(telemetry.get("atmosphere_drag_coefficient", 0.0))
	var atmosphere_drag_force: Vector3 = telemetry.get("atmosphere_drag_force_world", Vector3.ZERO)
	var atmosphere_drag_magnitude: float = float(telemetry.get("atmosphere_drag_force_n", 0.0))
	var atmosphere_turbulence_enabled: bool = bool(telemetry.get("atmosphere_wind_turbulence_enabled", false))
	var atmosphere_turbulence_amplitude: float = float(telemetry.get("atmosphere_wind_turbulence_amplitude_mps", 0.0))
	var shield_lift_enabled: bool = bool(telemetry.get("shield_glide_lift_enabled", false))
	var shield_lift_force: Vector3 = telemetry.get("shield_lift_force_world", Vector3.ZERO)
	var shield_lift_magnitude: float = float(telemetry.get("shield_lift_force_n", 0.0))
	var shield_lift_aoa: float = float(telemetry.get("shield_lift_angle_of_attack_degrees", 0.0))
	var shield_lift_coefficient: float = float(telemetry.get("shield_lift_coefficient", 0.0))
	var shield_lift_speed_gate: float = float(telemetry.get("shield_lift_speed_gate", 0.0))
	var shield_lift_forward_flow: float = float(telemetry.get("shield_lift_forward_flow_fraction", 0.0))
	var shield_lift_effectiveness: float = float(telemetry.get("shield_lift_effectiveness", 0.0))
	var fcc_input_deadzone: float = float(telemetry.get("fcc_input_deadzone", 0.01))
	var fcc_input_curvature: float = float(telemetry.get("fcc_input_curvature", 0.18))
	var fcc_pitch_conditioned: float = float(telemetry.get("fcc_pitch_input_conditioned", pitch_command))
	var fcc_roll_conditioned: float = float(telemetry.get("fcc_roll_input_conditioned", roll_command))
	var fcc_yaw_conditioned: float = float(telemetry.get("fcc_yaw_input_conditioned", yaw_command))

	var hover_threshold_text: String = "UNREACHABLE"
	if hover_power >= 0.0:
		hover_threshold_text = "%.1f%%" % hover_power

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[ PILOT / VIEW ]")
	lines.append("Field state: %s | Main-vector throttle setpoint/output: %.1f%% / %.1f%% | Vector setpoint/output: %.1f° / %.1f°" % [field_state, power_command * 100.0, power_output * 100.0, vector_command, vector_actual])
	lines.append("Pilot commands: pitch %.3f | roll %.3f | yaw %.3f | Controls armed: %s" % [pitch_command, roll_command, yaw_command, str(bool(telemetry.get("controls_armed", false)))])
	lines.append("Camera: %s | Camera look yaw/pitch: %+.2f° / %+.2f° | Input mode: %s | Debug UI interaction: %s" % [camera_view, camera_yaw, camera_pitch, input_mode, str(bool(telemetry.get("debug_interaction_mode", false)))])
	lines.append("FCC: %s | Control available: %s | Output P/R/Y: %+.3f / %+.3f / %+.3f" % ["ASSISTED RATE CONTROL" if bool(telemetry.get("fcc_assistance_enabled", true)) else "DIRECT VANES", str(bool(telemetry.get("fcc_control_available", false))), fcc_output.x, fcc_output.z, fcc_output.y])
	lines.append("Input shaping: deadzone %.1f%% | curve %.0f%% | conditioned P/R/Y: %+.3f / %+.3f / %+.3f" % [fcc_input_deadzone * 100.0, fcc_input_curvature * 100.0, fcc_pitch_conditioned, fcc_roll_conditioned, fcc_yaw_conditioned])
	lines.append("Vane redistribution: %.0f%% of deficit | healthy-vane cap: %.2fx nominal" % [float(telemetry.get("fcc_vane_redistribution_fraction", 0.0)) * 100.0, float(telemetry.get("fcc_maximum_vane_output_multiplier", 1.0))])
	lines.append("")
	lines.append("[ FLIGHT STATE ]")
	lines.append("Mass: %.1f kg | Position: (%.2f, %.2f, %.2f) m | Local altitude: %.2f m" % [mass_kg, position.x, position.y, position.z, local_altitude])
	lines.append("Velocity: (%.3f, %.3f, %.3f) m/s | Ground speed: %.3f m/s | Local vertical speed: %+.3f m/s" % [velocity.x, velocity.y, velocity.z, velocity.length(), local_vertical_speed])
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
	lines.append("Maneuver authority: %.4f | Power multiplier: %.2fx | Idle reserve: %.0f%% | Reference gravity: %.3f m/s²" % [float(telemetry.get("maneuver_authority_fraction", 0.0)), float(telemetry.get("maneuver_power_multiplier", 0.0)), float(telemetry.get("maneuver_boost_at_zero_main_power", 0.0)) * 100.0, float(telemetry.get("reference_gravity_mps2", 9.81))])
	lines.append("")
	lines.append("[ ATMOSPHERE / DRAG ]")
	lines.append("Atmosphere enabled: %s | Local altitude above reference: %.2f m | Density: %.6f kg/m³" % [str(atmosphere_enabled), atmosphere_altitude, atmosphere_density])
	lines.append("Airspeed: %.3f m/s | Relative air velocity: %s m/s" % [atmosphere_airspeed, str(atmosphere_relative_velocity)])
	lines.append("Mean wind: %s m/s | Turbulence: %s m/s | Current wind: %s m/s" % [str(atmosphere_mean_wind), str(atmosphere_turbulence), str(atmosphere_wind)])
	lines.append("Turbulence: %s | Configured amplitude: %.2f m/s" % [str(atmosphere_turbulence_enabled), atmosphere_turbulence_amplitude])
	lines.append("Projected hull area: %.3f m² | Cd: %.3f | Drag force: %s N | Magnitude: %.2f N" % [atmosphere_projected_area, atmosphere_drag_coefficient, str(atmosphere_drag_force), atmosphere_drag_magnitude])
	lines.append("")
	lines.append("[ SHIELD / GLIDE LIFT ]")
	lines.append("Glide lift enabled: %s | Effectiveness: %.1f%% | Effective field area: %.2f m²" % [str(shield_lift_enabled), shield_lift_effectiveness * 100.0, float(telemetry.get("shield_effective_lift_area_m2", 0.0))])
	lines.append("Angle of attack: %+.2f° | CL: %+.3f | Speed gate: %.3f | Forward-flow factor: %.3f" % [shield_lift_aoa, shield_lift_coefficient, shield_lift_speed_gate, shield_lift_forward_flow])
	lines.append("Stall angle: %.1f° | Configured max CL: %.3f" % [float(telemetry.get("shield_stall_angle_degrees", 0.0)), float(telemetry.get("shield_max_lift_coefficient", 0.0))])
	lines.append("Lift force: %s N | Magnitude: %.2f N | Direction: %s" % [str(shield_lift_force), shield_lift_magnitude, str(telemetry.get("shield_lift_direction_world", Vector3.ZERO))])
	lines.append("Note: shield lift is an effective field model, not physical wing aerodynamics.")
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
		lines.append("%s | F=(%.1f, %.1f, %.1f) N | M=(%.2f, %.2f, %.2f) N·m | base=%.3f TWR | redistributed=%.3f TWR | point=%s" % [str(contribution.get("vane_id", "UNKNOWN")), vane_force.x, vane_force.y, vane_force.z, vane_torque.x, vane_torque.y, vane_torque.z, float(contribution.get("base_effective_authority_twr", contribution.get("effective_authority_twr", 0.0))), float(contribution.get("redistributed_authority_twr", 0.0)), str(contribution.get("application_point_world", Vector3.ZERO))])
	lines.append("")
	lines.append("[ APPLIED RESULTANT VECTORS ]")
	if force_vectors.is_empty():
		lines.append("No force vectors submitted on the current physics tick.")
	for force_value in force_vectors:
		var force_entry: Dictionary = force_value
		var applied_force: Vector3 = force_entry.get("force_world", Vector3.ZERO)
		lines.append("%s | kind=%s | magnitude=%.1f N | force=%s | application point=%s" % [str(force_entry.get("name", "FORCE")), str(force_entry.get("kind", "unknown")), applied_force.length(), str(applied_force), str(force_entry.get("application_point_world", Vector3.ZERO))])

	var previous_scroll: float = _debug_text_label.scroll_vertical
	_debug_text_label.text = "\n".join(lines)
	_debug_text_label.scroll_vertical = previous_scroll


func is_display_settings_open() -> bool:
	return _settings_open


func toggle_display_settings() -> void:
	if _settings_open:
		close_display_settings()
		return

	_previous_mouse_mode = Input.mouse_mode
	_populate_display_settings()
	_settings_open = true
	_settings_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_display_settings() -> void:
	if not _settings_open:
		return
	_settings_open = false
	_settings_overlay.visible = false
	Input.mouse_mode = _previous_mouse_mode


func _build_display_settings_overlay() -> void:
	_settings_overlay = Control.new()
	_settings_overlay.name = "DisplaySettingsOverlay"
	_settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_overlay.z_index = 100
	_settings_overlay.visible = false
	add_child(_settings_overlay)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.005, 0.012, 0.018, 0.86)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.custom_minimum_size = Vector2(500.0, 360.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	var title := Label.new()
	title.text = "DISPLAY SETTINGS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "F10 or ESC closes this panel. Changes are saved automatically."
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(subtitle)

	var divider := HSeparator.new()
	content.add_child(divider)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(grid)

	var mode_label := Label.new()
	mode_label.text = "WINDOW MODE"
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(mode_label)
	_display_mode_option = OptionButton.new()
	_display_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display_mode_option.add_item("Windowed", 0)
	_display_mode_option.add_item("Borderless Fullscreen", 1)
	_display_mode_option.add_item("Exclusive Fullscreen", 2)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	grid.add_child(_display_mode_option)

	_resolution_label = Label.new()
	_resolution_label.text = "WINDOW RESOLUTION"
	_resolution_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(_resolution_label)
	_resolution_option = OptionButton.new()
	_resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_resolution_option)

	var scale_label := Label.new()
	scale_label.text = "HUD SCALE"
	scale_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(scale_label)
	_hud_scale_option = OptionButton.new()
	_hud_scale_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_scale_option.add_item("80%", 80)
	_hud_scale_option.add_item("90%", 90)
	_hud_scale_option.add_item("100%", 100)
	grid.add_child(_hud_scale_option)

	_settings_hint = Label.new()
	_settings_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_settings_hint.custom_minimum_size.y = 42.0
	_settings_hint.add_theme_font_size_override("font_size", 11)
	_settings_hint.add_theme_color_override("font_color", COLOR_MUTED)
	content.add_child(_settings_hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	content.add_child(buttons)

	var close_button := Button.new()
	close_button.text = "CANCEL"
	close_button.custom_minimum_size = Vector2(112.0, 36.0)
	close_button.pressed.connect(close_display_settings)
	buttons.add_child(close_button)

	var apply_button := Button.new()
	apply_button.text = "APPLY"
	apply_button.custom_minimum_size = Vector2(112.0, 36.0)
	apply_button.pressed.connect(_apply_display_settings_from_ui)
	buttons.add_child(apply_button)


func _populate_display_settings() -> void:
	var manager: Node = get_node_or_null("/root/DisplaySettings")
	var current_mode: String = "windowed"
	var current_resolution: Vector2i = Vector2i(1280, 720)
	var current_scale: float = 1.0
	if manager != null:
		current_mode = str(manager.call("get_display_mode"))
		current_resolution = manager.call("get_windowed_resolution")
		current_scale = float(manager.call("get_hud_scale"))

	var selected_mode_id: int = 0
	match current_mode:
		"borderless_fullscreen":
			selected_mode_id = 1
		"exclusive_fullscreen":
			selected_mode_id = 2
	_display_mode_option.select(_display_mode_option.get_item_index(selected_mode_id))

	_resolution_option.clear()
	var resolution_values: Array = []
	if manager != null:
		resolution_values = manager.call("get_windowed_resolution_options")
	else:
		resolution_values = [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
	var selected_resolution_index: int = 0
	for value: Variant in resolution_values:
		if not value is Vector2i:
			continue
		var resolution: Vector2i = value
		var item_index: int = _resolution_option.get_item_count()
		_resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])
		_resolution_option.set_item_metadata(item_index, resolution)
		if resolution == current_resolution:
			selected_resolution_index = item_index
	if _resolution_option.get_item_count() > 0:
		_resolution_option.select(selected_resolution_index)

	var scale_id: int = clampi(roundi(current_scale * 100.0 / 10.0) * 10, 80, 100)
	_hud_scale_option.select(_hud_scale_option.get_item_index(scale_id))
	_update_display_settings_hint()


func _on_display_mode_selected(_index: int) -> void:
	_update_display_settings_hint()


func _update_display_settings_hint() -> void:
	var selected_mode: int = _display_mode_option.get_selected_id()
	var windowed: bool = selected_mode == 0
	_resolution_option.disabled = not windowed
	_resolution_label.modulate = Color.WHITE if windowed else COLOR_MUTED
	var manager: Node = get_node_or_null("/root/DisplaySettings")
	var desktop_resolution := Vector2i(1280, 720)
	if manager != null:
		desktop_resolution = manager.call("get_desktop_resolution")
	var desktop_text: String = "%d × %d" % [desktop_resolution.x, desktop_resolution.y]
	if windowed:
		_settings_hint.text = "Windowed mode uses the selected size. The window can also be resized with its borders."
	else:
		_settings_hint.text = "Fullscreen uses the monitor's current desktop resolution (%s). The display's video mode is not changed." % desktop_text


func _apply_display_settings_from_ui() -> void:
	var manager: Node = get_node_or_null("/root/DisplaySettings")
	if manager == null:
		push_error("DisplaySettings autoload is missing. Check the [autoload] entry in project.godot.")
		return

	var mode: String = "windowed"
	match _display_mode_option.get_selected_id():
		1:
			mode = "borderless_fullscreen"
		2:
			mode = "exclusive_fullscreen"
	var resolution: Vector2i = manager.call("get_windowed_resolution")
	if _resolution_option.get_item_count() > 0:
		var selected_metadata: Variant = _resolution_option.get_item_metadata(_resolution_option.get_selected())
		if selected_metadata is Vector2i:
			resolution = selected_metadata
	var selected_hud_scale: float = float(_hud_scale_option.get_selected_id()) / 100.0
	manager.call("apply_display_settings", mode, resolution, selected_hud_scale)
	close_display_settings()


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
