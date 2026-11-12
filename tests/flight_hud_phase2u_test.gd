extends SceneTree

## UI regression checks for Phase 2U cargo/trim wording.
## Run: godot --headless --path . --script res://tests/flight_hud_phase2u_test.gd

const SHIP_SCENE = preload("res://scenes/ship.tscn")
const HUD_SCRIPT = preload("res://scripts/flight_hud_phase_2u.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var ship := SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate ship")
		_finish()
		return
	root.add_child(ship)
	await process_frame

	var cargo := ship.get_node_or_null("CargoSystem") as CargoSystem
	if cargo == null:
		_fail("Ship is missing CargoSystem")
		ship.queue_free()
		_finish()
		return

	var hud := HUD_SCRIPT.new() as FlightHUD
	root.add_child(hud)
	await process_frame
	hud.set_cargo_system(cargo)

	cargo.load_preset("PORT_HEAVY")
	hud._update_cargo_labels()
	_expect(hud._cargo_status_label.text.contains("residual rotation is possible"), "F4 warns that asymmetric-load trim is bounded")
	_expect(not hud._cargo_status_label.text.to_lower().contains("gravity moment"), "F4 does not claim gravity creates the cargo moment")
	_expect(not hud._cargo_status_label.text.contains("hold attitude"), "F4 does not promise perfect attitude hold")

	var telemetry := {
		"center_of_mass_m": Vector3(-1.2, 0.0, 0.0),
		"fcc_assistance_enabled": true,
		"fcc_trim_active": true,
		"fcc_any_axis_saturated": false,
		"fcc_integral_trim_output_by_axis": Vector3(0.0, 0.0, 0.12),
		"fcc_rate_integral_gain": 0.12,
		"fcc_maximum_integral_trim_output": 0.25,
		"fcc_maximum_control_output": 0.8,
	}
	var scroll_test_lines: PackedStringArray = PackedStringArray()
	for line_index in range(80):
		scroll_test_lines.append("PHASE 2U SCROLL TEST LINE %03d" % line_index)
	hud._debug_text_label.text = "\n".join(scroll_test_lines)
	await process_frame
	hud._debug_text_label.scroll_vertical = 8.0
	await process_frame
	var scroll_before_refresh: float = hud._debug_text_label.scroll_vertical

	hud._update_debug_text(telemetry)
	await process_frame
	_expect(
		is_equal_approx(hud._debug_text_label.scroll_vertical, scroll_before_refresh),
		"Phase 2U diagnostics preserve the reader's scroll position"
	)
	_expect(hud._debug_text_label.text.contains("INTEGRAL TRIM COMMAND ACTIVE"), "F3 reports bounded integral trim when active")
	_expect(not hud._debug_text_label.text.contains("FCC ACTIVE TRIM COMPENSATION"), "F3 removes the old unconditional compensation claim")
	_expect(hud._debug_text_label.text.contains("does not command a return to level"), "F3 explains that FCC trim is not attitude hold")

	ship.queue_free()
	hud.queue_free()
	_finish()


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)


func _finish() -> void:
	print("Phase 2U HUD tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
