extends SceneTree

## F6 regression checks for geometry-derived yaw allocation.
## Run: godot --headless --path . --script res://tests/vane_yaw_geometry_test.gd

const SHIP_SCENE = preload("res://scenes/ship.tscn")
const ALLOCATOR = preload("res://scripts/vane_actuator_allocator.gd")

const EPSILON: float = 0.01

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_allocator_requires_real_yaw_geometry()
	await _test_runtime_yaw_and_group_independence()
	print("Vane yaw geometry tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_allocator_requires_real_yaw_geometry() -> void:
	var reference_force_n: float = 500.0
	var characteristic_length_m: float = 1.7
	var actuators: Array[Dictionary] = [
		{
			"id": &"port_lateral_axis",
			"position_local": Vector3(-1.7, 0.05, 0.0),
			"axis_local": Vector3.RIGHT,
			"max_force_n": 100.0,
			"control_weights": {"yaw": 100},
		},
		{
			"id": &"starboard_lateral_axis",
			"position_local": Vector3(1.7, 0.05, 0.0),
			"axis_local": Vector3.RIGHT,
			"max_force_n": 100.0,
			"control_weights": {"yaw": 100},
		},
	]
	var result: Dictionary = ALLOCATOR.allocate(
		actuators,
		{"yaw": 1.0},
		Vector3.ZERO,
		reference_force_n,
		characteristic_length_m
	)
	var achieved_torque: Vector3 = result.get("achieved_torque_local_nm", Vector3.ZERO)
	var residual_torque: Vector3 = result.get("torque_residual_local_nm", Vector3.ZERO)
	_expect(bool(result.get("success", false)), "Allocator accepts the deliberately lateral actuator set")
	_expect_near(achieved_torque.y, 0.0, EPSILON, "Parallel lateral thrust lines cannot create yaw around local Y")
	_expect(residual_torque.y < -EPSILON, "Allocator reports the unachievable yaw moment as residual demand")


func _test_runtime_yaw_and_group_independence() -> void:
	var ship: ShipInteractable = SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate the prototype ship scene")
		return
	ship.position = Vector3(0.0, 100.0, 0.0)
	root.add_child(ship)
	await physics_frame

	var controller: VaneController = ship.get_node("VaneController") as VaneController
	var system: RepulsorliftSystem = ship.get_node("RepulsorliftSystem") as RepulsorliftSystem
	if controller == null or system == null:
		_fail("Prototype ship is missing VaneController or RepulsorliftSystem")
		ship.queue_free()
		await process_frame
		return

	_expect(controller.is_configuration_valid(), "Prototype actuator configuration is valid")
	var port_definition: VaneDefinition = controller.get_vane_definition(&"side_left")
	var starboard_definition: VaneDefinition = controller.get_vane_definition(&"side_right")
	_expect(
		port_definition != null and starboard_definition != null
		and port_definition.local_thrust_axis.is_equal_approx(Vector3.BACK)
		and starboard_definition.local_thrust_axis.is_equal_approx(Vector3.BACK),
		"Both side-mounted yaw vanes are defined on the bidirectional local-Z axis"
	)
	_expect(
		port_definition != null and starboard_definition != null
		and port_definition.local_position.x < 0.0
		and starboard_definition.local_position.x > 0.0,
		"Port and starboard yaw actuators retain their separated application points"
	)

	# Make both vane group IDs identical and unrelated to the former hard-coded
	# side_left/side_right groups. Geometry allocation must remain unaffected.
	var original_definitions: Array[Resource] = []
	var regrouped_definitions: Array[Resource] = []
	for vane_id: StringName in controller.get_vane_ids():
		var source_definition: VaneDefinition = controller.get_vane_definition(vane_id)
		original_definitions.append(source_definition)
		var copy: VaneDefinition = source_definition.duplicate(true) as VaneDefinition
		if vane_id == &"side_left" or vane_id == &"side_right":
			copy.group_id = &"shared_yaw_actuator_group"
		regrouped_definitions.append(copy)
	var config_result: Dictionary = controller.configure_vanes(regrouped_definitions)
	_expect(bool(config_result.get("success", false)), "Yaw actuators accept arbitrary shared group IDs")

	controller.reset_all_vanes()
	_set_all_temperatures(controller, 60.0)
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 1.0)
	var telemetry: Dictionary = system.get_telemetry()
	var allocation: Dictionary = telemetry.get("maneuver_allocator", {})
	var yaw_forces: Array[Dictionary] = _forces_of_kind(telemetry, "yaw")
	var yaw_force_sum: Vector3 = _sum_forces(yaw_forces)
	var total_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect(bool(allocation.get("success", false)), "Runtime yaw request is solved by the geometry allocator")
	_expect(bool(allocation.get("converged", false)), "Runtime yaw allocation converges")
	_expect_equal(int(allocation.get("eligible_actuator_count", 0)), 2, "Yaw allocation discovers both configured side actuators")
	_expect_equal(yaw_forces.size(), 2, "Yaw produces one debug force vector for each side actuator")
	_expect_near(yaw_force_sum.length(), 0.0, EPSILON, "Healthy opposing yaw forces cancel net translation")
	_expect(total_torque.y < -EPSILON, "Positive yaw command creates the established nose-right negative-Y moment")
	_expect(absf(total_torque.x) <= EPSILON and absf(total_torque.z) <= EPSILON, "Symmetric yaw pair does not create pitch or roll")

	var port_force: Vector3 = _force_for_vane(telemetry, &"side_left")
	var starboard_force: Vector3 = _force_for_vane(telemetry, &"side_right")
	_expect(port_force.z < -EPSILON, "Positive yaw commands the port actuator forward")
	_expect(starboard_force.z > EPSILON, "Positive yaw commands the starboard actuator aft")
	_expect(
		allocation.get("force_residual_local_n", Vector3.ZERO).length() <= EPSILON,
		"Symmetric yaw allocation has negligible residual translation"
	)

	# Simultaneous inputs must still use exactly one bounded allocator pass; the
	# same per-actuator scalar is shared if a future definition mixes channels.
	_set_all_temperatures(controller, 60.0)
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.4, -0.3, 0.7)
	telemetry = system.get_telemetry()
	allocation = telemetry.get("maneuver_allocator", {})
	_expect_equal(int(allocation.get("eligible_actuator_count", 0)), 6, "Combined pitch/roll/yaw solve sees all six channel-eligible actuators")
	_expect(bool(allocation.get("converged", false)), "Combined three-axis maneuver allocation converges")
	_expect(_all_outputs_bounded(allocation.get("actuator_outputs", [])), "Combined allocator keeps every actuator within its own bidirectional bound")
	_expect_equal(_forces_of_kind(telemetry, "yaw").size(), 2, "Yaw-only side actuators remain separately identifiable in combined debug output")

	# Damage one yaw vane while all three rotational channels are commanded.
	# Redistribution must stay within the yaw-capable set: spare bottom-vane
	# pitch/roll capacity cannot compensate a missing longitudinal yaw moment.
	_set_all_temperatures(controller, 60.0)
	var prev_tiered_yaw: bool = bool(controller.get("tiered_integrity_enabled"))
	controller.set("tiered_integrity_enabled", false)
	controller.set_vane_integrity(&"side_left", 0.5)
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.4, -0.3, 0.7, 1.0, 1.2)
	telemetry = system.get_telemetry()
	allocation = telemetry.get("maneuver_allocator", {})
	var reference_force_n: float = float(telemetry.get("lift_rated_gross_mass_kg", 0.0)) * system.reference_gravity_mps2
	var side_right_max_force: float = _maximum_force_for_vane(allocation, &"side_right")
	var bottom_front_left_max_force: float = _maximum_force_for_vane(allocation, &"bottom_front_left")
	_expect_near(side_right_max_force, reference_force_n * 0.036, 1.0, "Damaged yaw actuator redistributes only into the healthy yaw actuator")
	_expect_near(bottom_front_left_max_force, reference_force_n * 0.275, 1.0, "Yaw damage does not consume unrelated bottom-actuator pitch/roll headroom")
	controller.set_vane_integrity(&"side_left", 1.0)
	controller.set("tiered_integrity_enabled", prev_tiered_yaw)

	var restore_result: Dictionary = controller.configure_vanes(original_definitions)
	_expect(bool(restore_result.get("success", false)), "Test restores the original prototype actuator definitions")
	ship.queue_free()
	await process_frame


func _set_all_temperatures(controller: VaneController, temperature_celsius: float) -> void:
	for vane_id: StringName in controller.get_vane_ids():
		controller.set_vane_temperature(vane_id, temperature_celsius)


func _forces_of_kind(telemetry: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry_value: Variant in telemetry.get("lift_force_vectors", []):
		var entry: Dictionary = entry_value
		if str(entry.get("kind", "")) == kind:
			result.append(entry)
	return result


func _sum_forces(entries: Array[Dictionary]) -> Vector3:
	var result: Vector3 = Vector3.ZERO
	for entry: Dictionary in entries:
		result += entry.get("force_world", Vector3.ZERO)
	return result


func _force_for_vane(telemetry: Dictionary, vane_id: StringName) -> Vector3:
	for entry_value: Variant in telemetry.get("lift_vane_contributions", []):
		var entry: Dictionary = entry_value
		if StringName(str(entry.get("vane_id", ""))) == vane_id:
			return entry.get("force_world", Vector3.ZERO)
	return Vector3.ZERO


func _maximum_force_for_vane(allocation: Dictionary, vane_id: StringName) -> float:
	for output_value: Variant in allocation.get("actuator_outputs", []):
		var output: Dictionary = output_value
		if StringName(str(output.get("id", ""))) == vane_id:
			return float(output.get("max_force_n", 0.0))
	return 0.0


func _all_outputs_bounded(outputs: Array) -> bool:
	for entry_value: Variant in outputs:
		var entry: Dictionary = entry_value
		if absf(float(entry.get("output", 0.0))) > 1.0001:
			return false
	return true


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


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
