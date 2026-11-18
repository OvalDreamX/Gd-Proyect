extends SceneTree

## Geometry-based main-vector regression tests.
## Run: godot --headless --path . --script res://tests/main_vector_allocator_test.gd

const SHIP_SCENE = preload("res://scenes/ship.tscn")
const REFERENCE_GROSS_MASS_KG: float = 55000.0
const REFERENCE_GRAVITY_MPS2: float = 9.81
const FORCE_TOLERANCE_N: float = 0.5
const VECTOR_TOLERANCE: float = 0.00001

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var ship: ShipInteractable = SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate scenes/ship.tscn")
		quit(1)
		return
	root.add_child(ship)
	await physics_frame

	var vane_controller: VaneController = ship.get_node("VaneController") as VaneController
	var system: RepulsorliftSystem = ship.get_node("RepulsorliftSystem") as RepulsorliftSystem
	if not is_instance_valid(vane_controller) or not is_instance_valid(system):
		_fail("Ship scene is missing VaneController or RepulsorliftSystem")
		ship.queue_free()
		quit(1)
		return

	_expect(vane_controller.is_configuration_valid(), "Prototype actuator configuration is valid")
	_expect_near(ship.get_design_gross_mass_kg(), REFERENCE_GROSS_MASS_KG, 0.01, "Main-vector ratings use 55-tonne design gross mass")

	_test_forward_thrust(vane_controller, system)
	_test_vertical_lift(vane_controller, system)
	_test_intermediate_vector(vane_controller, system)
	_test_braking_vector(vane_controller, system)
	_test_offset_com_resultant(ship, vane_controller, system)
	_test_power_scaling(vane_controller, system)
	_test_damage_derating(vane_controller, system)
	_test_group_independence(vane_controller, system)

	print("Main-vector allocator tests: %d checks, %d failures." % [_checks, _failures])
	ship.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _test_forward_thrust(controller: VaneController, system: RepulsorliftSystem) -> void:
	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var telemetry: Dictionary = system.get_telemetry()
	var force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var expected_force: float = _reference_force_n() * 1.5
	var allocation: Dictionary = telemetry.get("main_vector_allocator", {})
	_expect_near_vector(force.normalized(), Vector3.FORWARD, VECTOR_TOLERANCE, "0-degree command allocates forward thrust along ship -Z")
	_expect_near(force.length(), expected_force, FORCE_TOLERANCE_N, "Forward thrust preserves 1.50 gross TWR")
	_expect_equal(int(allocation.get("eligible_actuator_count", 0)), 1, "Forward thrust recruits the configured main-thrust actuator, not lift vanes")
	_expect(bool(allocation.get("success", false)), "Forward-thrust geometry allocation succeeds")
	_expect(bool(allocation.get("converged", false)), "Forward-thrust geometry allocation converges")
	_expect_near(float(allocation.get("normalized_error", 1.0)), 0.0, 0.000001, "Forward-thrust request has negligible normalized residual")


func _test_vertical_lift(controller: VaneController, system: RepulsorliftSystem) -> void:
	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var telemetry: Dictionary = system.get_telemetry()
	var force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var expected_force: float = _reference_force_n() * 1.1
	var allocation: Dictionary = telemetry.get("main_vector_allocator", {})
	_expect_near_vector(force.normalized(), Vector3.UP, VECTOR_TOLERANCE, "90-degree command allocates pure ship-local vertical lift")
	_expect_near(force.length(), expected_force, FORCE_TOLERANCE_N, "Vertical lift preserves 1.10 gross TWR")
	_expect_equal(int(allocation.get("eligible_actuator_count", 0)), 4, "Vertical lift recruits all four configured lift actuators")
	var total_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_near(total_torque.length(), 0.0, 0.01, "Symmetric lift has no unwanted torque about the hull datum")

	var outputs: Array = allocation.get("actuator_outputs", [])
	var main_rear_output: float = _find_output(outputs, &"main_rear")
	_expect_near(main_rear_output, 0.0, 0.000001, "Vertical lift does not recruit the forward-thrust actuator")


func _test_intermediate_vector(controller: VaneController, system: RepulsorliftSystem) -> void:
	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 1.0, 45.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var telemetry: Dictionary = system.get_telemetry()
	var force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var expected_direction: Vector3 = RepulsorliftSystem.main_vector_direction_local(45.0)
	var expected_force: float = _reference_force_n() * lerpf(1.5, 1.1, 0.5)
	var allocation: Dictionary = telemetry.get("main_vector_allocator", {})
	_expect_near_vector(force.normalized(), expected_direction, VECTOR_TOLERANCE, "Intermediate vector is the geometry-allocated blend of forward and lift")
	_expect_near(force.length(), expected_force, FORCE_TOLERANCE_N, "45-degree vector preserves the established interpolated authority rating")
	_expect_equal(int(allocation.get("eligible_actuator_count", 0)), 5, "Intermediate vector recruits both thrust and lift actuator sets")


func _test_braking_vector(controller: VaneController, system: RepulsorliftSystem) -> void:
	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 1.0, 110.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var telemetry: Dictionary = system.get_telemetry()
	var force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var expected_direction: Vector3 = RepulsorliftSystem.main_vector_direction_local(110.0)
	var expected_force: float = _reference_force_n() * 1.1
	_expect_near_vector(force.normalized(), expected_direction, VECTOR_TOLERANCE, "110-degree command keeps lift while reversing the main-thrust channel for braking")
	_expect_near(force.length(), expected_force, FORCE_TOLERANCE_N, "Braking blend retains the established lift-authority magnitude")
	_expect(force.y > 0.0 and force.z > 0.0, "Braking vector has positive lift and rearward force")


func _test_offset_com_resultant(
		ship: ShipInteractable,
		controller: VaneController,
		system: RepulsorliftSystem
) -> void:
	var previous_com_mode: int = ship.center_of_mass_mode
	var previous_com: Vector3 = ship.center_of_mass
	ship.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	ship.center_of_mass = Vector3(1.0, 0.0, 0.0)
	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var telemetry: Dictionary = system.get_telemetry()
	var force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var expected_torque: Vector3 = (-ship.center_of_mass).cross(force)
	var actual_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_near_vector(actual_torque, expected_torque, 0.1, "Main resultant remains applied at the hull datum and preserves offset-COM torque")
	ship.center_of_mass = previous_com
	ship.center_of_mass_mode = previous_com_mode


func _test_power_scaling(controller: VaneController, system: RepulsorliftSystem) -> void:
	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var force: Vector3 = system.get_telemetry().get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(force.length(), _reference_force_n() * 1.5 * 0.5, FORCE_TOLERANCE_N, "Main-vector power output scales allocated force linearly")

	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 0.0, 90.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	force = system.get_telemetry().get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(force.length(), 0.0, 0.0001, "Zero main-vector power produces no main resultant")


func _test_damage_derating(controller: VaneController, system: RepulsorliftSystem) -> void:
	_restore_nominal_condition(controller)
	var prev_tiered: bool = bool(controller.get("tiered_integrity_enabled"))
	controller.set("tiered_integrity_enabled", false)
	_expect(controller.set_vane_integrity(&"main_rear", 0.5), "Main-thrust actuator accepts a 50% integrity test condition")
	_expect(controller.set_vane_temperature(&"main_rear", 60.0), "Main-thrust actuator is held at nominal operating temperature")
	system.apply_flight_control_forces(true, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var force: Vector3 = system.get_telemetry().get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(force.length(), _reference_force_n() * 1.5 * 0.5, FORCE_TOLERANCE_N, "Main-vector capacity follows current integrity derating")
	controller.set("tiered_integrity_enabled", prev_tiered)


func _test_group_independence(controller: VaneController, system: RepulsorliftSystem) -> void:
	_restore_nominal_condition(controller)
	var candidate_definitions: Array[Resource] = []
	for vane_id: StringName in controller.get_vane_ids():
		var definition: Resource = controller.get_vane_definition(vane_id).duplicate(true)
		definition.set("group_id", StringName("renamed_" + String(vane_id)))
		candidate_definitions.append(definition)
	var result: Dictionary = controller.configure_vanes(candidate_definitions)
	_expect(bool(result.get("success", false)), "Actuator groups may be renamed without changing the valid configuration")
	if not bool(result.get("success", false)):
		return

	_restore_nominal_condition(controller)
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.0 / 60.0)
	var telemetry: Dictionary = system.get_telemetry()
	var force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var allocation: Dictionary = telemetry.get("main_vector_allocator", {})
	_expect_near(force.length(), _reference_force_n() * 1.1, FORCE_TOLERANCE_N, "Main lift allocation uses control weights and geometry, not legacy group IDs")
	_expect_equal(int(allocation.get("eligible_actuator_count", 0)), 4, "Renamed lift actuators remain discoverable by channel metadata")


func _restore_nominal_condition(controller: VaneController) -> void:
	for vane_id: StringName in controller.get_vane_ids():
		controller.set_vane_integrity(vane_id, 1.0)
		controller.set_vane_temperature(vane_id, 60.0)


func _find_output(outputs: Array, vane_id: StringName) -> float:
	for output_value: Variant in outputs:
		var output_entry: Dictionary = output_value
		if StringName(str(output_entry.get("id", ""))) == vane_id:
			return float(output_entry.get("output", 0.0))
	return 0.0


func _reference_force_n() -> float:
	return REFERENCE_GROSS_MASS_KG * REFERENCE_GRAVITY_MPS2


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_equal(actual: int, expected: int, description: String) -> void:
	_expect(actual == expected, "%s (actual %d, expected %d)" % [description, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.6f, expected %.6f ± %.6f)" % [description, actual, expected, tolerance])


func _expect_near_vector(actual: Vector3, expected: Vector3, tolerance: float, description: String) -> void:
	_expect(actual.distance_to(expected) <= tolerance, "%s (actual %s, expected %s, tolerance %.6f)" % [description, str(actual), str(expected), tolerance])


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
