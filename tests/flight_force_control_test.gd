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

	_expect(vane_controller.is_configuration_valid(), "Vane configuration is valid")
	_expect_equal(vane_controller.get_vane_count(), 7, "Four bottom, one rear/main and two side vanes are registered")
	_expect_near(
		vane_controller.get_group_nominal_authority_twr(&"bottom_front")
		+ vane_controller.get_group_nominal_authority_twr(&"bottom_rear"),
		1.1,
		0.0001,
		"Bottom vane array preserves 1.1 nominal TWR"
	)

	# Neutral hover must produce a central upward force and no control torque.
	vane_controller.reset_all_vanes()
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	var telemetry: Dictionary = system.get_telemetry()
	var main_force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var neutral_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect(main_force.y > 0.0 and absf(main_force.z) <= EPSILON, "90-degree main vector is pure ship-local vertical lift")
	_expect_near(neutral_torque.length(), 0.0, EPSILON, "Neutral healthy field has no unwanted baseline torque")

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
