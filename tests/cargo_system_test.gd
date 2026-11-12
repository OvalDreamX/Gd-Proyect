extends SceneTree

## Deterministic integration tests for CargoSystem (Phase 2T/2U).
## Verifies manifest calculations against the actual ship RigidBody3D.

const SHIP_SCENE = preload("res://scenes/ship.tscn")
const CARGO_SCRIPT = preload("res://scripts/cargo_system.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[CARGO_SYSTEM_TEST] Running ship integration tests...")
	var ship := SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate the prototype freighter")
		_finish()
		return

	root.add_child(ship)
	await process_frame
	await physics_frame

	var cargo := ship.get_node_or_null("CargoSystem") as CargoSystem
	var repulsorlift := ship.get_node_or_null("RepulsorliftSystem") as RepulsorliftSystem
	if cargo == null or repulsorlift == null:
		_fail("Ship scene is missing CargoSystem or RepulsorliftSystem")
		ship.queue_free()
		_finish()
		return

	_expect_near(cargo.dry_mass_kg, ship.get_design_dry_mass_kg(), 0.1, "Cargo subsystem derives dry mass from its parent ship")
	_expect_near(cargo.max_payload_mass_kg, ship.max_payload_mass_kg, 0.1, "Cargo subsystem derives payload capacity from its parent ship")

	cargo.load_preset("EMPTY")
	_expect_near(cargo.get_total_mass_kg(), 30000.0, 0.1, "Empty ship total mass is 30,000 kg")
	_expect_near(ship.mass, 30000.0, 0.1, "Empty manifest updates the actual RigidBody3D mass")
	_expect(ship.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM, "Cargo system selects custom center of mass")
	_expect(ship.center_of_mass.is_zero_approx(), "Empty ship COM is at the origin")
	var empty_box_inertia: Vector3 = CARGO_SCRIPT.calculate_box_inertia_diagonal(30000.0, Vector3(3.6, 1.5, 5.2))
	_expect_near_vector(ship.inertia, empty_box_inertia, 0.1, "Empty ship inertia matches the authored hull box")
	_expect_near(cargo.get_hover_throttle_estimate(), 30000.0 / (55000.0 * 1.10), 0.01, "Empty hover estimate is ~49.6%")

	cargo.load_preset("MAX_GROSS")
	_expect_near(cargo.get_total_mass_kg(), 55000.0, 0.1, "Maximum payload produces 55,000 kg gross mass")
	_expect_near(ship.mass, 55000.0, 0.1, "Maximum payload updates actual rigid-body mass")
	_expect(ship.center_of_mass.is_zero_approx(), "Centered maximum payload leaves COM at origin")
	var max_payload_dimensions: Vector3 = Vector3(2.0, 1.0, 3.0)
	var centered_gross_inertia: Dictionary = CARGO_SCRIPT.calculate_combined_inertia(
		30000.0, Vector3(3.6, 1.5, 5.2), 25000.0, max_payload_dimensions, Vector3.ZERO
	)
	_expect_near_vector(ship.inertia, centered_gross_inertia["diagonal"], 0.1, "Centered payload contributes its own rotational inertia")
	_expect(ship.inertia.x > empty_box_inertia.x and ship.inertia.y > empty_box_inertia.y and ship.inertia.z > empty_box_inertia.z, "Centered payload increases all three principal-axis moments")
	_expect_near(cargo.get_hover_throttle_estimate(), 1.0 / 1.10, 0.01, "Maximum gross hover estimate is ~90.9%")

	cargo.load_preset("PORT_HEAVY")
	var port_com: Vector3 = cargo.get_combined_center_of_mass_m()
	_expect_near(cargo.get_total_mass_kg(), 50000.0, 0.1, "Port-heavy preset produces 50,000 kg gross mass")
	_expect_near(port_com.x, -1.2, 0.01, "Port-heavy cargo shifts COM to X = -1.2m")
	_expect_near(ship.center_of_mass.x, -1.2, 0.01, "Port-heavy COM is applied to the actual RigidBody3D")
	var port_cargo_dimensions: Vector3 = cargo.get_telemetry().get("cargo_distribution_dimensions_local_m", Vector3.ZERO)
	var port_inertia_data: Dictionary = CARGO_SCRIPT.calculate_combined_inertia(
		30000.0, Vector3(3.6, 1.5, 5.2), 20000.0,
		port_cargo_dimensions, Vector3(-3.0, 0.0, 0.0)
	)
	_expect_near_vector(ship.inertia, port_inertia_data["diagonal"], 0.1, "Offset cargo inertia includes parallel-axis contributions about the combined COM")
	_expect(Vector3(cargo.get_telemetry()["inertia_products_kg_m2"]).length() < 0.001, "Single-axis offset has no omitted cross-axis products")

	# The main field force is applied at the fixed hull datum, so this shifted
	# COM creates a real moment. Gravity itself acts through the COM and is not
	# incorrectly treated as a torque source.
	repulsorlift.apply_flight_control_forces(
		true, 0.9, 90.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0
	)
	var lift_telemetry: Dictionary = repulsorlift.get_telemetry()
	var lift_torque: Vector3 = lift_telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect(lift_torque.z > 10000.0, "Offset COM produces a measurable roll moment from the main lift resultant")

	cargo.load_preset("NOSE_HEAVY")
	var nose_com: Vector3 = cargo.get_combined_center_of_mass_m()
	_expect_near(nose_com.z, -1.6, 0.01, "Nose-heavy cargo shifts COM to Z = -1.6m")
	_expect_near(ship.center_of_mass.z, -1.6, 0.01, "Nose-heavy COM is applied to the actual rigid body")

	cargo.load_preset("STARBOARD_HEAVY")
	_expect_near(ship.center_of_mass.x, 1.2, 0.01, "Starboard-heavy COM is applied to the actual rigid body")

	cargo.set_cargo(10000.0, Vector3(2.0, -0.5, 3.0), "CUSTOM")
	var custom_com: Vector3 = cargo.get_combined_center_of_mass_m()
	_expect_near(cargo.get_total_mass_kg(), 40000.0, 0.1, "Custom manifest produces 40,000 kg gross mass")
	_expect_near(ship.mass, 40000.0, 0.1, "Custom manifest updates rigid-body mass")
	_expect_near(custom_com.x, 0.5, 0.01, "Custom COM X is 0.5m")
	_expect_near(custom_com.y, -0.125, 0.01, "Custom COM Y is -0.125m")
	_expect_near(custom_com.z, 0.75, 0.01, "Custom COM Z is 0.75m")
	_expect_near_vector(ship.center_of_mass, custom_com, 0.001, "Custom COM is written to the RigidBody3D")
	var custom_products: Vector3 = cargo.get_telemetry()["inertia_products_kg_m2"]
	_expect(custom_products.length() > 0.001, "Three-axis cargo offsets report the non-diagonal products the solver cannot represent")
	_expect(ship.inertia.x > 0.0 and ship.inertia.y > 0.0 and ship.inertia.z > 0.0, "Combined inertia remains positive for a three-axis offset load")

	# The subsystem must never exceed the parent ship's current payload rating.
	cargo.set_cargo(99999.0, Vector3.ZERO, "OVERLOAD_TEST")
	_expect_near(cargo.get_cargo_mass_kg(), ship.max_payload_mass_kg, 0.1, "Custom payload is clamped to the ship-authored capacity")
	_expect_near(ship.mass, ship.get_design_dry_mass_kg() + ship.max_payload_mass_kg, 0.1, "Clamped payload keeps gross mass within design rating")

	# Thermal state must continue cooling through the RepulsorliftSystem call
	# path even when the field is offline.
	var vane_controller := ship.get_node_or_null("VaneController") as VaneController
	if vane_controller == null:
		_fail("Ship scene is missing VaneController for offline thermal integration test")
	else:
		vane_controller.set_vane_temperature(&"bottom_front_left", 120.0)
		var initial_integrity: float = _vane_integrity(vane_controller, &"bottom_front_left")
		for _tick in range(120):
			repulsorlift.apply_flight_control_forces(
				false, 0.0, 90.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0
			)
		var cooled_temperature: float = vane_controller.get_vane_temperature(&"bottom_front_left")
		_expect(cooled_temperature < 120.0, "Repulsorlift integration cools vanes while field is offline")
		_expect_near(vane_controller.get_vane_wear_rate(&"bottom_front_left"), 0.0, 0.000001, "Offline thermal integration accrues no operating wear")
		_expect_near(_vane_integrity(vane_controller, &"bottom_front_left"), initial_integrity, 0.000001, "Offline cooling preserves vane integrity")

	ship.queue_free()
	print("[CARGO_SYSTEM_TEST] Finished: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _vane_integrity(controller: VaneController, vane_id: StringName) -> float:
	for vane_value in controller.get_telemetry().get("vane_states", []):
		var vane: Dictionary = vane_value
		if vane.get("vane_id") == vane_id:
			return float(vane.get("integrity", 0.0))
	return 0.0


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: %s" % message)
	else:
		print("PASS: %s" % message)


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (expected %.3f, got %.3f)" % [message, actual, expected])


func _expect_near_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	_expect(actual.distance_to(expected) <= tolerance, "%s (actual %s, expected %s)" % [message, str(actual), str(expected)])


func _fail(message: String) -> void:
	_failures += 1
	printerr("FAIL: %s" % message)


func _finish() -> void:
	print("[CARGO_SYSTEM_TEST] Finished: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
