extends SceneTree

## Deterministic force-allocation and rigid-body smoke checks.
## Run from the project root:
## godot --headless --path . --script res://tests/flight_force_control_test.gd

const SHIP_SCENE = preload("res://scenes/ship.tscn")
const EPSILON: float = 0.01
const TEST_ALTITUDE: float = 100.0
const TEST_TICKS: int = 30

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_expect_near_vector(
		RepulsorliftSystem.main_vector_direction_local(0.0),
		Vector3.FORWARD,
		0.0001,
		"0 degrees points forward relative to the ship"
	)
	_expect_near_vector(
		RepulsorliftSystem.main_vector_direction_local(90.0),
		Vector3.UP,
		0.0001,
		"90 degrees points upward for VTOL hover"
	)
	var braking_direction: Vector3 = RepulsorliftSystem.main_vector_direction_local(110.0)
	_expect(braking_direction.y > 0.9 and braking_direction.z > 0.3, "110 degrees retains lift with a rearward braking component")

	var ship := SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate scenes/ship.tscn")
		quit(1)
		return
	ship.position = Vector3(0.0, TEST_ALTITUDE, 0.0)
	root.add_child(ship)
	await physics_frame

	var vane_controller := ship.get_node("VaneController") as VaneController
	var system := ship.get_node("RepulsorliftSystem") as RepulsorliftSystem
	if vane_controller == null or system == null:
		_fail("Ship scene is missing VaneController or RepulsorliftSystem")
		quit(1)
		return

	var telemetry: Dictionary = {}
	var main_force: Vector3 = Vector3.ZERO

	_expect(vane_controller.is_configuration_valid(), "Vane configuration is valid")
	_expect_near(ship.mass, 30000.0, EPSILON, "Prototype freighter starts at 30 tonnes dry mass")
	_expect_near(ship.max_payload_mass_kg, 25000.0, EPSILON, "Prototype freighter payload rating is 25 tonnes")
	_expect_near(ship.get_design_gross_mass_kg(), 55000.0, EPSILON, "Design gross mass is 55 tonnes")
	_expect_equal(vane_controller.get_vane_count(), 7, "Four bottom, one rear/main and two side vanes are registered")
	_expect_near(
		vane_controller.get_group_nominal_authority_twr(&"bottom_front")
		+ vane_controller.get_group_nominal_authority_twr(&"bottom_rear"),
		1.1,
		0.0001,
		"Bottom vane array preserves 1.1 nominal TWR"
	)

	# Vane TWR values are fixed force ratings at 55 t design gross mass.
	# At maximum payload the lift array has only 0.10 g of excess acceleration.
	var expected_max_lift_force: float = 55000.0 * 9.81 * 1.1
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(main_force.y, expected_max_lift_force, 0.1, "Maximum lift force is rated at 55-tonne gross mass")
	_expect_near(float(telemetry.get("lift_maximum_twr", 0.0)), expected_max_lift_force / (30000.0 * ship.get_gravity().length()), 0.001, "Empty 30-tonne ship has more physical lift TWR than its loaded limit")
	ship.mass = 55000.0
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(main_force.y, expected_max_lift_force, 0.1, "Adding cargo does not increase rated maximum lift force")
	var local_gravity_mps2: float = ship.get_gravity().length()
	var actual_loaded_twr: float = expected_max_lift_force / (55000.0 * maxf(local_gravity_mps2, 0.001))
	var expected_loaded_hover_percent: float = 100.0 / actual_loaded_twr
	_expect_near(float(telemetry.get("lift_actual_twr", 0.0)), actual_loaded_twr, 0.001, "Fully loaded lift authority is approximately 1.10 physical TWR")
	_expect_near(float(telemetry.get("lift_hover_power_percent", 0.0)), expected_loaded_hover_percent, 0.02, "Fully loaded ship needs about 91% main-vector output merely to hover")
	ship.mass = 30000.0

	# Neutral hover must produce a central upward force and no control torque.
	vane_controller.reset_all_vanes()
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var neutral_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect(main_force.y > 0.0 and absf(main_force.z) <= EPSILON, "90-degree main vector is pure ship-local vertical lift")
	_expect_near(neutral_torque.length(), 0.0, EPSILON, "Neutral healthy field has no unwanted baseline torque")

	# Main-vector throttle controls translation, not whether the online field
	# can maneuver. At zero throttle the main force is zero, but all control
	# groups remain available and receive a bounded 20% reserve boost.
	system.apply_flight_control_forces(true, 0.0, 90.0, 1.0, 1.0, 1.0, 0.5, 1.2)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(main_force.length(), 0.0, EPSILON, "Zero main-vector throttle produces no translational force")
	var idle_pitch_forces: Array[Dictionary] = _forces_of_kind(telemetry, "pitch")
	var idle_roll_forces: Array[Dictionary] = _forces_of_kind(telemetry, "roll")
	var idle_yaw_forces: Array[Dictionary] = _forces_of_kind(telemetry, "yaw")
	_expect_equal(idle_pitch_forces.size(), 2, "Pitch remains available with the field online and main-vector throttle at zero")
	_expect_equal(idle_roll_forces.size(), 2, "Roll remains available with the field online and main-vector throttle at zero")
	_expect_equal(idle_yaw_forces.size(), 2, "Yaw remains available with the field online and main-vector throttle at zero")
	_expect_near(float(telemetry.get("maneuver_power_multiplier", 0.0)), 1.2, EPSILON, "Idle main-vector allocation provides a capped 20% maneuver reserve")
	var idle_pitch_magnitude: float = _sum_force_magnitudes(idle_pitch_forces)
	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0, 0.5, 1.2)
	telemetry = system.get_telemetry()	
	var full_power_pitch_magnitude: float = _sum_force_magnitudes(_forces_of_kind(telemetry, "pitch"))
	_expect_near(idle_pitch_magnitude / maxf(full_power_pitch_magnitude, 0.001), 1.2, 0.01, "Idle throttle increases maneuver force by only the configured 20%")

	# Pitch: front pair up, rear pair down. Their translations cancel while
	# their separated application points produce positive nose-up pitch torque.
	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	var pitch_forces: Array[Dictionary] = _forces_of_kind(telemetry, "pitch")
	var pitch_pair_force: Vector3 = _sum_forces(pitch_forces)
	var pitch_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_equal(pitch_forces.size(), 2, "Pitch creates front and rear force vectors")
	_expect_near(pitch_pair_force.length(), 0.0, EPSILON, "Healthy pitch pair cancels net translation")
	_expect(pitch_torque.x > EPSILON, "Positive pitch command creates nose-up torque")

	# Roll: left pair up, right pair down.
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 1.0, 0.0)
	telemetry = system.get_telemetry()
	var roll_forces: Array[Dictionary] = _forces_of_kind(telemetry, "roll")
	var roll_pair_force: Vector3 = _sum_forces(roll_forces)
	var roll_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_equal(roll_forces.size(), 2, "Roll creates left and right force vectors")
	_expect_near(roll_pair_force.length(), 0.0, EPSILON, "Healthy roll pair cancels net translation")
	_expect(roll_torque.z < -EPSILON, "Positive roll command banks right")

	# Yaw uses the side-vane pair in opposite fore/aft directions.
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 1.0)
	telemetry = system.get_telemetry()
	var yaw_forces: Array[Dictionary] = _forces_of_kind(telemetry, "yaw")
	var yaw_pair_force: Vector3 = _sum_forces(yaw_forces)
	var yaw_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_equal(yaw_forces.size(), 2, "Yaw creates left and right side-vane force vectors")
	_expect_near(yaw_pair_force.length(), 0.0, EPSILON, "Healthy yaw pair cancels net translation")
	_expect(yaw_torque.y < -EPSILON, "Positive yaw command turns the nose right")

	# Q/E changes the ship-relative main force vector, not just a HUD value.
	system.apply_flight_control_forces(true, 1.0, 0.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect(main_force.z < 0.0 and absf(main_force.y) <= EPSILON, "0-degree vector produces forward translation")
	_expect_near(main_force.length(), 55000.0 * 9.81 * 1.5, 0.1, "Main propulsion is rated at 1.50 gross TWR")
	system.apply_flight_control_forces(true, 1.0, 110.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect(main_force.y > 0.0 and main_force.z > 0.0, "110-degree vector produces lift plus rearward braking")

	# The main vector follows ship orientation rather than remaining world-up.
	var rolled_basis := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	ship.freeze = true
	ship.global_transform = Transform3D(rolled_basis, Vector3(0.0, TEST_ALTITUDE, 0.0))
	ship.freeze = false
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var expected_ship_up: Vector3 = rolled_basis * Vector3.UP
	_expect_near_vector(main_force.normalized(), expected_ship_up, 0.0001, "Main lift vector rotates with the ship instead of staying world-up")
	ship.freeze = true
	ship.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, TEST_ALTITUDE, 0.0))
	ship.freeze = false

	# Field OFF must remove every primary and secondary force immediately.
	system.apply_flight_control_forces(false, 1.0, 90.0, 1.0, 1.0, 1.0)
	telemetry = system.get_telemetry()
	_expect_near(telemetry.get("lift_force_newtons", 0.0), 0.0, EPSILON, "Field OFF removes all generated forces")
	_expect_equal(telemetry.get("lift_force_vectors", []).size(), 0, "Field OFF leaves no active force-vector debug entries")

	# The damaged right-front vane shifts the front group's weighted point left,
	# lowers its force, and leaves the expected unwanted roll during pitch-up.
	vane_controller.reset_all_vanes()
	vane_controller.set_vane_integrity(&"bottom_front_right", 0.5)
	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	var damaged_pitch_forces: Array[Dictionary] = _forces_of_kind(telemetry, "pitch")
	var damaged_front: Dictionary = _find_force(damaged_pitch_forces, "PITCH FRONT")
	var damaged_roll_moment: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	var damaged_front_point: Vector3 = damaged_front.get("application_point_world", Vector3.ZERO)
	_expect(damaged_front_point.x < ship.global_position.x, "Front resultant shifts toward the healthy left-front vane")
	_expect(damaged_roll_moment.z < -EPSILON, "Asymmetric front damage produces the expected unwanted roll")
	var front_pair_ids: Array[StringName] = [&"bottom_front_left", &"bottom_front_right"]
	var damaged_no_compensation: Dictionary = vane_controller.calculate_vane_set_resultant(
		front_pair_ids, Vector3.UP, 1000.0, ship.global_transform, ship.center_of_mass, 0.0, 1.2
	)
	var damaged_with_compensation: Dictionary = vane_controller.calculate_vane_set_resultant(
		front_pair_ids, Vector3.UP, 1000.0, ship.global_transform, ship.center_of_mass, 0.5, 1.2
	)
	var compensated_authority: float = float(damaged_with_compensation.get("effective_authority_twr", 0.0))
	var uncompensated_authority: float = float(damaged_no_compensation.get("effective_authority_twr", 0.0))
	_expect(compensated_authority > uncompensated_authority, "FCC redistribution uses healthy spare vane authority to recover part of a damaged group's output")
	_expect(compensated_authority < float(damaged_with_compensation.get("nominal_authority_twr", 0.0)), "Bounded redistribution never conceals the entire damaged-vane deficit")
	var uncompensated_point: Vector3 = damaged_no_compensation.get("effective_application_point_world", Vector3.ZERO)
	var compensated_point: Vector3 = damaged_with_compensation.get("effective_application_point_world", Vector3.ZERO)
	_expect(compensated_point.x < uncompensated_point.x, "Redistribution shifts the resultant toward the healthy vane without restoring symmetry")

	# F3 controls only the visualization; it does not modify any force values.
	var debug_node := ship.get_node("ForceVectorDebug") as ForceVectorDebug
	system.set_debug_visualization_enabled(true)
	_expect(debug_node != null and debug_node.visible, "F3 debug activation shows force-vector arrows")
	system.set_debug_visualization_enabled(false)
	_expect(debug_node != null and not debug_node.visible, "Disabling F3 hides force-vector arrows")

	# One short live-physics smoke test verifies that the applied group forces
	# produce actual angular velocity on the single RigidBody3D.
	vane_controller.reset_all_vanes()
	ship.freeze = true
	ship.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, TEST_ALTITUDE, 0.0))
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.freeze = false
	ship.sleeping = false
	for _tick in range(TEST_TICKS):
		system.apply_flight_control_forces(true, 1.0, 90.0, 0.5, 0.0, 0.0)
		await physics_frame
	_expect(absf(ship.angular_velocity.x) > 0.001, "Pitch force pair produces physical angular velocity")

	print("Flight force-control tests: %d checks, %d failures." % [_checks, _failures])
	ship.queue_free()
	quit(1 if _failures > 0 else 0)


func _forces_of_kind(telemetry: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in telemetry.get("lift_force_vectors", []):
		var force_entry: Dictionary = entry
		if str(force_entry.get("kind", "")) == kind:
			result.append(force_entry)
	return result


func _sum_forces(entries: Array[Dictionary]) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	for entry in entries:
		total += entry.get("force_world", Vector3.ZERO)
	return total


func _sum_force_magnitudes(entries: Array[Dictionary]) -> float:
	var total: float = 0.0
	for entry in entries:
		var force: Vector3 = entry.get("force_world", Vector3.ZERO)
		total += force.length()
	return total


func _find_force(entries: Array[Dictionary], force_name: String) -> Dictionary:
	for entry in entries:
		if str(entry.get("name", "")) == force_name:
			return entry
	return {}


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_equal(actual: int, expected: int, description: String) -> void:
	_expect(actual == expected, "%s (actual %d, expected %d)" % [description, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance])


func _expect_near_vector(actual: Vector3, expected: Vector3, tolerance: float, description: String) -> void:
	_expect(actual.distance_to(expected) <= tolerance, "%s (actual %s, expected %s)" % [description, str(actual), str(expected)])


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
