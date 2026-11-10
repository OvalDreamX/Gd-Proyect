extends SceneTree

## UI integration checks. Run from the project root:
## godot --headless --path . --script res://tests/flight_hud_layout_test.gd

const FLIGHT_HUD_SCRIPT = preload("res://scripts/flight_hud.gd")

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
		"fcc_assistance_enabled": true,
	}

	hud.update_telemetry(sample_telemetry)
	_expect(flight_display.visible, "Cockpit HUD is visible in cockpit view when F3 is off")
	_expect(not debug_panel.visible, "Diagnostics remain hidden during normal flight")
	var displayed_telemetry: Dictionary = flight_display.get("_telemetry")
	_expect(is_equal_approx(float(displayed_telemetry.get("field_power_output", -1.0)), 0.65), "HUD receives actual field output for the live gauge")
	_expect(is_equal_approx(float(displayed_telemetry.get("field_power_command", -1.0)), 0.8), "HUD receives the separate field-power setpoint")

	var debug_telemetry: Dictionary = sample_telemetry.duplicate(true)
	debug_telemetry["debug_overview_enabled"] = true
	hud.update_telemetry(debug_telemetry)
	_expect(not flight_display.visible, "Normal HUD is hidden while F3 diagnostics are active")
	_expect(debug_panel.visible, "F3 opens the diagnostics page")
	var diagnostics_label := debug_panel.find_child("DiagnosticsText", true, false) as Label
	_expect(diagnostics_label != null and diagnostics_label.text.contains("Power setpoint/output"), "F3 page contains the former flight telemetry")

	var external_debug_telemetry: Dictionary = debug_telemetry.duplicate(true)
	external_debug_telemetry["camera_view"] = "EXTERNAL"
	hud.update_telemetry(external_debug_telemetry)
	_expect(not flight_display.visible, "Cockpit HUD remains hidden in external view while debugging")
	_expect(debug_panel.visible, "F3 diagnostics remain available in external view")

	var external_telemetry: Dictionary = sample_telemetry.duplicate(true)
	external_telemetry["camera_view"] = "EXTERNAL"
	external_telemetry["debug_overview_enabled"] = false
	hud.update_telemetry(external_telemetry)
	_expect(not flight_display.visible, "Cockpit HUD is hidden in external camera view")
	_expect(not debug_panel.visible, "F3 diagnostics close when debug mode is disabled")

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
