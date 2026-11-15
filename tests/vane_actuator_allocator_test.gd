extends SceneTree

## Deterministic headless tests for the pure actuator wrench allocator.
## Run: godot --headless --path . --script res://tests/vane_actuator_allocator_test.gd

const ALLOCATOR = preload("res://scripts/vane_actuator_allocator.gd")
const VANE_CONTROLLER = preload("res://scripts/vane_controller.gd")
const VANE_DEFINITION = preload("res://scripts/vane_definition.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_symmetric_lift()
	_test_pitch_couple()
	_test_main_thrust()
	_test_three_axis_translation()
	_test_zero_weight_and_disabled_actuators()
	_test_control_weight_priority()
	_test_controller_accepts_translation_channels()
	_test_saturation()
	_test_validation()

	print("Vane actuator allocator tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_symmetric_lift() -> void:
	var actuators: Array[Dictionary] = [
		_actuator("lift_fl", Vector3(-1.0, -0.5, -2.0), Vector3.UP, 1000.0, {"lift": 100}),
		_actuator("lift_fr", Vector3(1.0, -0.5, -2.0), Vector3.UP, 1000.0, {"lift": 100}),
		_actuator("lift_rl", Vector3(-1.0, -0.5, 2.0), Vector3.UP, 1000.0, {"lift": 100}),
		_actuator("lift_rr", Vector3(1.0, -0.5, 2.0), Vector3.UP, 1000.0, {"lift": 100}),
	]
	var result: Dictionary = _allocate(actuators, {"lift": 0.8}, 4000.0, 2.0)
	var achieved_force: Vector3 = result["achieved_force_local_n"]
	var achieved_torque: Vector3 = result["achieved_torque_local_nm"]
	_expect(bool(result["success"]), "Symmetric lift allocation validates")
	_expect(bool(result["converged"]), "Symmetric lift solver reaches its output-change tolerance")
	_expect_near(achieved_force.y, 3200.0, 2.0, "Four vertical actuators achieve collective lift demand")
	_expect_near(achieved_torque.length(), 0.0, 1.0, "Symmetric lift does not introduce a net torque")
	_expect_equal(int(result["eligible_actuator_count"]), 4, "All four lift-weighted actuators are eligible")


func _test_pitch_couple() -> void:
	var actuators: Array[Dictionary] = [
		_actuator("pitch_front", Vector3(0.0, 0.0, -1.0), Vector3.UP, 500.0, {"pitch": 100}),
		_actuator("pitch_rear", Vector3(0.0, 0.0, 1.0), Vector3.UP, 500.0, {"pitch": 100}),
	]
	var result: Dictionary = _allocate(actuators, {"pitch": 0.5}, 1000.0, 1.0)
	var achieved_force: Vector3 = result["achieved_force_local_n"]
	var achieved_torque: Vector3 = result["achieved_torque_local_nm"]
	_expect_near(achieved_force.length(), 0.0, 1.0, "Opposing actuator forces cancel translation during pitch")
	_expect_near(achieved_torque.x, 500.0, 1.0, "Position geometry creates the requested positive pitch moment")
	_expect_near(achieved_torque.y, 0.0, 1.0, "Pitch allocation does not create yaw")
	_expect_near(achieved_torque.z, 0.0, 1.0, "Pitch allocation does not create roll")


func _test_main_thrust() -> void:
	var actuators: Array[Dictionary] = [
		_actuator("main", Vector3.ZERO, Vector3.FORWARD, 1000.0, {"main_thrust": 100}),
	]
	var result: Dictionary = _allocate(actuators, {"main_thrust": 0.6}, 1000.0, 1.0)
	var achieved_force: Vector3 = result["achieved_force_local_n"]
	_expect_near(achieved_force.z, -600.0, 1.0, "Main-thrust command follows the existing -Z forward convention")


func _test_three_axis_translation() -> void:
	var actuators: Array[Dictionary] = [
		_actuator("translate_x", Vector3.ZERO, Vector3.RIGHT, 1000.0, {"translate_x": 100}),
		_actuator("translate_y", Vector3.ZERO, Vector3.UP, 1000.0, {"translate_y": 100}),
		_actuator("translate_z", Vector3.ZERO, Vector3.BACK, 1000.0, {"translate_z": 100}),
	]
	var result: Dictionary = _allocate(
		actuators,
		{"translate_x": 0.3, "translate_y": -0.2, "translate_z": 0.4},
		1000.0,
		1.0
	)
	var force: Vector3 = result["achieved_force_local_n"]
	_expect_near(force.x, 300.0, 1.0, "X translation uses ship-local +X")
	_expect_near(force.y, -200.0, 1.0, "Y translation supports bidirectional vertical control")
	_expect_near(force.z, 400.0, 1.0, "Z translation uses ship-local +Z")


func _test_zero_weight_and_disabled_actuators() -> void:
	var actuators: Array[Dictionary] = [
		_actuator("not_for_lift", Vector3.ZERO, Vector3.UP, 1000.0, {"lift": 0, "pitch": 100}),
		_actuator("disabled_lift", Vector3.ZERO, Vector3.UP, 1000.0, {"lift": 100}, false),
	]
	var result: Dictionary = _allocate(actuators, {"lift": 1.0}, 1000.0, 1.0)
	var achieved_force: Vector3 = result["achieved_force_local_n"]
	var force_residual: Vector3 = result["force_residual_local_n"]
	_expect_equal(int(result["eligible_actuator_count"]), 0, "Zero-weight and disabled actuators are not recruited for lift")
	_expect_near(achieved_force.length(), 0.0, 0.001, "Ineligible actuators produce no commanded force")
	_expect_near(force_residual.y, 1000.0, 0.001, "Unachievable lift remains visible as residual demand")


func _test_control_weight_priority() -> void:
	# Stable-ID sorting must not decide which equivalent actuator receives the
	# larger share. Exercise both lexical orders so this catches the previous
	# zero-start coordinate-descent bias rather than merely array-order changes.
	_assert_control_weight_priority("a_priority_high", "z_priority_low")
	_assert_control_weight_priority("z_priority_high", "a_priority_low")


func _assert_control_weight_priority(high_id: String, low_id: String) -> void:
	var actuators: Array[Dictionary] = [
		_actuator(high_id, Vector3.ZERO, Vector3.UP, 500.0, {"lift": 100}),
		_actuator(low_id, Vector3.ZERO, Vector3.UP, 500.0, {"lift": 50}),
	]
	var result: Dictionary = _allocate(actuators, {"lift": 0.5}, 1000.0, 1.0)
	var outputs: Array = result["actuator_outputs"]
	var high_output: float = 0.0
	var low_output: float = 0.0
	for output_entry: Dictionary in outputs:
		if StringName(output_entry["id"]) == StringName(high_id):
			high_output = absf(float(output_entry["output"]))
		elif StringName(output_entry["id"]) == StringName(low_id):
			low_output = absf(float(output_entry["output"]))
	var achieved_force: Vector3 = result["achieved_force_local_n"]
	_expect(bool(result["success"]), "Priority allocation validates for ID order %s/%s" % [high_id, low_id])
	_expect(bool(result["converged"]), "Priority allocation converges for ID order %s/%s" % [high_id, low_id])
	_expect(high_output > low_output, "Higher control weight wins regardless of stable-ID order (%s/%s)" % [high_id, low_id])
	_expect_near(achieved_force.y, 500.0, 1.0, "Weight priority preserves achievable demand (%s/%s)" % [high_id, low_id])


func _test_controller_accepts_translation_channels() -> void:
	var definition: Resource = VANE_DEFINITION.new()
	definition.set("vane_id", &"translation_test")
	definition.set("group_id", &"translation_test")
	definition.set("nominal_authority_twr", 0.1)
	definition.set("control_weights", {
		"translate_x": 100,
		"translate_y": 100,
		"translate_z": 100,
	})
	var definitions: Array[Resource] = [definition]
	var controller: Node = VANE_CONTROLLER.new()
	root.add_child(controller)
	var result: Dictionary = controller.call("configure_vanes", definitions)
	_expect(bool(result.get("success", false)), "VaneController accepts the three translation control channels")
	controller.queue_free()


func _test_saturation() -> void:
	var actuators: Array[Dictionary] = [
		_actuator("limited", Vector3.ZERO, Vector3.UP, 250.0, {"lift": 100}),
	]
	var result: Dictionary = _allocate(actuators, {"lift": 1.0}, 1000.0, 1.0)
	var achieved_force: Vector3 = result["achieved_force_local_n"]
	var outputs: Array = result["actuator_outputs"]
	_expect_near(achieved_force.y, 250.0, 0.01, "Actuator cannot exceed its rated maximum force")
	_expect_equal(int(result["saturated_actuator_count"]), 1, "Saturated actuator is reported")
	_expect_near(float(outputs[0]["output"]), 1.0, 0.0001, "Normalized actuator output is bounded to +1")


func _test_validation() -> void:
	var duplicate_actuators: Array[Dictionary] = [
		_actuator("duplicate", Vector3.ZERO, Vector3.UP, 100.0, {"lift": 100}),
		_actuator("duplicate", Vector3.ZERO, Vector3.UP, 100.0, {"lift": 100}),
	]
	var duplicate_result: Dictionary = _allocate(duplicate_actuators, {"lift": 0.5}, 100.0, 1.0)
	_expect(not bool(duplicate_result["success"]), "Duplicate actuator IDs are rejected transactionally")

	var fractional_weight: Array[Dictionary] = [
		_actuator("fractional", Vector3.ZERO, Vector3.UP, 100.0, {"lift": 12.5}),
	]
	var fractional_result: Dictionary = _allocate(fractional_weight, {"lift": 0.5}, 100.0, 1.0)
	_expect(not bool(fractional_result["success"]), "Fractional control weights are rejected")

	var unknown_channel: Array[Dictionary] = [
		_actuator("unknown", Vector3.ZERO, Vector3.UP, 100.0, {"warp": 100}),
	]
	var unknown_result: Dictionary = _allocate(unknown_channel, {"lift": 0.5}, 100.0, 1.0)
	_expect(not bool(unknown_result["success"]), "Unknown actuator control channels are rejected")


func _actuator(
		actuator_id: String,
		position_local: Vector3,
		axis_local: Vector3,
		max_force_n: float,
		control_weights: Dictionary,
		enabled: bool = true
) -> Dictionary:
	return {
		"id": StringName(actuator_id),
		"position_local": position_local,
		"axis_local": axis_local,
		"max_force_n": max_force_n,
		"control_weights": control_weights,
		"enabled": enabled,
	}


func _allocate(
		actuators: Array[Dictionary],
		demands: Dictionary,
		reference_force_n: float,
		characteristic_length_m: float
) -> Dictionary:
	return ALLOCATOR.allocate(
		actuators,
		demands,
		Vector3.ZERO,
		reference_force_n,
		characteristic_length_m
	)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_equal(actual: int, expected: int, description: String) -> void:
	_expect(actual == expected, "%s (actual %d, expected %d)" % [description, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(
		absf(actual - expected) <= tolerance,
		"%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance]
	)


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
