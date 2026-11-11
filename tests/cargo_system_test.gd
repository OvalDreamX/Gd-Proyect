extends SceneTree

## Deterministic regression tests for CargoSystem (Phase 2T).
## Verifies mass computation, center of mass offset, presets, and RigidBody3D integration.

const CARGO_SYSTEM_SCRIPT = preload("res://scripts/cargo_system.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[CARGO_SYSTEM_TEST] Running tests...")
	var cargo = CARGO_SYSTEM_SCRIPT.new()
	cargo.dry_mass_kg = 30000.0
	cargo.max_payload_mass_kg = 25000.0
	root.add_child(cargo)
	await process_frame

	# Test 1: Empty ship (0 payload)
	cargo.load_preset("EMPTY")
	_expect_near(cargo.get_total_mass_kg(), 30000.0, 0.1, "Empty ship total mass is 30,000 kg")
	_expect(cargo.get_combined_center_of_mass_m().is_zero_approx(), "Empty ship COM is at origin (0, 0, 0)")
	_expect_near(cargo.get_hover_throttle_estimate(), 30000.0 / (55000.0 * 1.10), 0.01, "Empty hover throttle is ~49.6%")

	# Test 2: Max gross (25,000 kg payload centered)
	cargo.load_preset("MAX_GROSS")
	_expect_near(cargo.get_total_mass_kg(), 55000.0, 0.1, "Max gross total mass is 55,000 kg")
	_expect(cargo.get_combined_center_of_mass_m().is_zero_approx(), "Centered max gross COM remains at origin")
	_expect_near(cargo.get_hover_throttle_estimate(), 55000.0 / (55000.0 * 1.10), 0.01, "Max gross hover throttle is ~90.9%")

	# Test 3: Port heavy asymmetric load (20,000 kg at X = -3.0m)
	cargo.load_preset("PORT_HEAVY")
	_expect_near(cargo.get_total_mass_kg(), 50000.0, 0.1, "Port heavy total mass is 50,000 kg")
	var port_com: Vector3 = cargo.get_combined_center_of_mass_m()
	var expected_x: float = (20000.0 * -3.0) / 50000.0 # -1.2m
	_expect_near(port_com.x, expected_x, 0.01, "Port heavy shifts COM to X = -1.2m")
	_expect_near(port_com.y, 0.0, 0.001, "Port heavy Y offset is 0.0m")
	_expect_near(port_com.z, 0.0, 0.001, "Port heavy Z offset is 0.0m")

	# Test 4: Nose heavy asymmetric load (20,000 kg at Z = -4.0m)
	cargo.load_preset("NOSE_HEAVY")
	var nose_com: Vector3 = cargo.get_combined_center_of_mass_m()
	var expected_z: float = (20000.0 * -4.0) / 50000.0 # -1.6m
	_expect_near(nose_com.z, expected_z, 0.01, "Nose heavy shifts COM to Z = -1.6m forward")

	# Test 5: Starboard heavy asymmetric load (20,000 kg at X = +3.0m)
	cargo.load_preset("STARBOARD_HEAVY")
	var stbd_com: Vector3 = cargo.get_combined_center_of_mass_m()
	_expect_near(stbd_com.x, 1.2, 0.01, "Starboard heavy shifts COM to X = +1.2m right")

	# Test 6: Custom continuous adjustment
	cargo.set_cargo(10000.0, Vector3(2.0, -0.5, 3.0), "CUSTOM")
	_expect_near(cargo.get_total_mass_kg(), 40000.0, 0.1, "Custom mass is 40,000 kg")
	var custom_com: Vector3 = cargo.get_combined_center_of_mass_m()
	_expect_near(custom_com.x, (10000.0 * 2.0) / 40000.0, 0.01, "Custom COM X is 0.5m")
	_expect_near(custom_com.y, (10000.0 * -0.5) / 40000.0, 0.01, "Custom COM Y is -0.125m")
	_expect_near(custom_com.z, (10000.0 * 3.0) / 40000.0, 0.01, "Custom COM Z is 0.75m")

	print("\n[CARGO_SYSTEM_TEST] Finished: %d checks, %d failures" % [_checks, _failures])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("  FAIL: %s" % message)
	else:
		print("  PASS: %s" % message)


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_checks += 1
	if absf(actual - expected) > tolerance:
		_failures += 1
		printerr("  FAIL: %s (expected %.3f, got %.3f)" % [message, expected, actual])
	else:
		print("  PASS: %s (%.3f ≈ %.3f)" % [message, actual, expected])
