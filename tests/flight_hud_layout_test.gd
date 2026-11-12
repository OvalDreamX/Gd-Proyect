extends SceneTree

## UI integration checks. Run from the project root:
## godot --headless --path . --script res://tests/flight_hud_layout_test.gd

const FLIGHT_HUD_SCRIPT = preload("res://scripts/flight_hud.gd")
const HUD_OVERLAY_SCRIPT = preload("res://scripts/flight_hud_overlay.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var hud = FLIGHT_HUD_SCRIPT.new()
	hud.name = "TestFlightHUD"
	root.add_child(hud)
	await process_frame

	var flight_display := hud.get_node_or_null("CockpitFlightDisplay") as Control
	var debug_panel := hud.get_node_or_null("F3DiagnosticsPanel") as PanelContainer
	var settings_overlay := hud.get_node_or_null("DisplaySettingsOverlay") as Control
	_expect(flight_display != null, "Cockpit flight display is created")
	_expect(debug_panel != null, "F3 diagnostics panel is created")
	_expect(settings_overlay != null, "Display settings overlay is created")
	if flight_display == null or debug_panel == null or settings_overlay == null:
		hud.queue_free()
		quit(1)
		return

	var sample_telemetry: Dictionary = {
		"camera_view": "COCKPIT",
		"cockpit_camera_centered": true,
		"debug_overview_enabled": false,
		"field_state": "ONLINE",
		"field_power_command": 0.8,
		"field_power_output": 0.65,
		"vector_distribution_degrees": 100.0,
		"vector_distribution_actual_degrees": 92.0,
		"pitch_command": 0.25,
		"roll_command": -0.4,
		"yaw_command": 0.5,
		"ship_position": Vector3(0.0, 120.0, 0.0),
		"ship_linear_velocity": Vector3(0.0, 3.0, -30.0),
		"ship_global_basis": Basis.IDENTITY,
		"instrument_pitch_degrees": 0.0,
		"instrument_bank_degrees": 0.0,
		"instrument_heading_degrees": 0.0,
		"instrument_heading_valid": true,
		"instrument_air_relative_velocity_world": Vector3(0.0, 0.0, -30.0),
		"instrument_inertial_velocity_world": Vector3(0.0, 0.0, -30.0),
		"instrument_speed_label": "AIRSPEED",
		"instrument_speed_mps": 30.0,
		"instrument_vertical_speed_mps": 0.0,
		"instrument_altitude_m": 120.0,
		"instrument_attitude_valid": true,
		"instrument_velocity_valid": true,
		"instrument_altitude_valid": true,
		"cockpit_camera_fov_degrees": 78.0,
		"fcc_assistance_enabled": true,
		"atmosphere_enabled": true,
		"atmosphere_altitude_m": 120.0,
		"atmosphere_density_kg_m3": 1.208,
		"atmosphere_airspeed_mps": 30.0,
		"atmosphere_drag_force_n": 4200.0,
		"atmosphere_mean_wind_velocity_world": Vector3(3.5, 0.0, 4.2),
		"atmosphere_turbulence_velocity_world": Vector3(0.2, 0.0, -0.1),
		"atmosphere_velocity_world": Vector3(3.7, 0.0, 4.1),
		"atmosphere_wind_turbulence_enabled": true,
		"atmosphere_wind_turbulence_amplitude_mps": 0.9,
		"fcc_input_deadzone": 0.01,
		"fcc_input_curvature": 0.18,
		"fcc_pitch_input_conditioned": 0.4,
		"fcc_roll_input_conditioned": -0.2,
		"fcc_yaw_input_conditioned": 0.3,
	}

	hud.update_telemetry(sample_telemetry)
	_expect(flight_display.visible, "Screen-space HUD is visible in cockpit view when F3 is off")
	_expect(HUD_OVERLAY_SCRIPT.is_central_hud_visible(sample_telemetry), "Central symbology is visible with the cockpit camera centered")
	_expect(not debug_panel.visible, "Diagnostics remain hidden during normal flight")
	var displayed_telemetry: Dictionary = flight_display.get("_telemetry")
	_expect(is_equal_approx(float(displayed_telemetry.get("field_power_output", -1.0)), 0.65), "HUD receives actual field output for the live gauge")
	_expect(is_equal_approx(float(displayed_telemetry.get("field_power_command", -1.0)), 0.8), "HUD receives the separate field-power setpoint")
	var letterbox_offset: Vector2 = HUD_OVERLAY_SCRIPT.calculate_letterbox_offset(Vector2(1920.0, 1080.0), 1.35)
	_expect(is_equal_approx(letterbox_offset.x, 96.0) and is_equal_approx(letterbox_offset.y, 54.0), "HUD letterbox translation is expressed in viewport pixels after scaling")
	_expect(HUD_OVERLAY_SCRIPT.heading_label_degrees(359.6) == 0, "HUD heading wraps rounded 360 degrees to 000")
	_expect(HUD_OVERLAY_SCRIPT.heading_label_degrees(-0.6) == 359, "HUD heading wraps negative values into 000–359")

	var debug_telemetry: Dictionary = sample_telemetry.duplicate(true)
	debug_telemetry["debug_overview_enabled"] = true
	hud.update_telemetry(debug_telemetry)
	_expect(not flight_display.visible, "Normal HUD is hidden while F3 diagnostics are active")
	_expect(debug_panel.visible, "F3 opens the diagnostics page")
	var diagnostics_view := debug_panel.find_child("DiagnosticsText", true, false) as TextEdit
	_expect(diagnostics_view != null, "F3 diagnostics use a dedicated scrollable text viewport")
	_expect(diagnostics_view != null and diagnostics_view.custom_minimum_size.y >= 200.0, "F3 diagnostics text viewport has a non-zero layout height")
	_expect(diagnostics_view != null and diagnostics_view.text.contains("Power setpoint/output"), "F3 page contains the former flight telemetry")
	_expect(diagnostics_view != null and diagnostics_view.text.contains("ATMOSPHERE / DRAG"), "F3 page includes atmospheric density and drag diagnostics")
	_expect(diagnostics_view != null and diagnostics_view.text.contains("Input shaping"), "F3 page reports FCC deadzone and curve settings")
	_expect(diagnostics_view != null and diagnostics_view.text.contains("Mean wind"), "F3 page reports mean wind and turbulence")

	var external_debug_telemetry: Dictionary = debug_telemetry.duplicate(true)
	external_debug_telemetry["camera_view"] = "EXTERNAL"
	hud.update_telemetry(external_debug_telemetry)
	_expect(not flight_display.visible, "Cockpit HUD remains hidden in external view while debugging")
	_expect(debug_panel.visible, "F3 diagnostics remain available in external view")

	var external_telemetry: Dictionary = sample_telemetry.duplicate(true)
	external_telemetry["camera_view"] = "EXTERNAL"
	external_telemetry["debug_overview_enabled"] = false
	hud.update_telemetry(external_telemetry)
	_expect(flight_display.visible, "Side instruments remain visible in external camera view")
	_expect(not HUD_OVERLAY_SCRIPT.is_central_hud_visible(external_telemetry), "Central symbology is hidden in external camera view")
	_expect(not debug_panel.visible, "F3 diagnostics close when debug mode is disabled")

	var off_axis_telemetry: Dictionary = sample_telemetry.duplicate(true)
	off_axis_telemetry["cockpit_camera_centered"] = false
	_expect(not HUD_OVERLAY_SCRIPT.is_central_hud_visible(off_axis_telemetry), "Central symbology hides when cockpit camera looks away from boresight")

	hud.toggle_display_settings()
	_expect(hud.is_display_settings_open(), "F10 display settings open state is enabled")
	_expect(settings_overlay.visible, "Display settings overlay is visible when opened")
	hud.close_display_settings()
	_expect(not hud.is_display_settings_open(), "Display settings close cleanly")
	_expect(not settings_overlay.visible, "Display settings overlay is hidden when closed")

	print("Flight HUD layout tests: %d checks, %d failures." % [_checks, _failures])
	hud.queue_free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
