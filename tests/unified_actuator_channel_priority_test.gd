extends SceneTree

## Deterministic regression test for channel-local actuator recruitment.
## Run: godot --headless --path . --script res://tests/unified_actuator_channel_priority_test.gd

const ALLOCATOR = preload("res://scripts/vane_actuator_allocator.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var actuators: Array[Dictionary] = [
		_actuator("lift_fl", Vector3(-1.0, 0.0, -1.0), Vector3.UP, 300.0, {"lift": 100}),
		_actuator("lift_fr", Vector3(1.0, 0.0, -1.0), Vector3.UP, 300.0, {"lift": 100}),
		_actuator("lift_rl", Vector3(-1.0, 0.0, 1.0), Vector3.UP, 300.0, {"lift": 100}),
		_actuator("lift_rr", Vector3(1.0, 0.0, 1.0), Vector3.UP, 300.0, {"lift": 100}),
		_actuator("yaw_port", Vector3(-1.0, 0.0, 0.0), Vector3.BACK, 1000.0, {"yaw": 100}),
		_actuator("yaw_starboard", Vector3(1.0, 0.0, 0.0), Vector3.BACK, 1000.0, {"yaw": 100}),
	]
	var result: Dictionary = ALLOCATOR.allocate(
		actuators,
		{"lift": 0.8, "yaw": 0.1},
		Vector3.ZERO,
		1000.0,
		1.0,
		160,
		0.00000001
	)

	_expect(bool(result.get("success", false)), "Simultaneous lift/yaw allocation validates")
	_expect(bool(result.get("converged", false)), "Simultaneous lift/yaw allocation converges")
	var outputs: Array = result.get("actuator_outputs", [])
	_expect_equal(outputs.size(), 6, "All six channel-eligible actuators are included")

	var ids: Dictionary = {}
	var yaw_weights: Array[float] = []
	for output_value: Variant in outputs:
		var output: Dictionary = output_value
		var actuator_id: StringName = StringName(str(output.get("id", "")))
		ids[actuator_id] = true
		_expect(
			absf(float(output.get("output", 0.0))) <= 1.0 + 0.000001,
			"Actuator %s remains within its single bidirectional output bound" % String(actuator_id)
		)
		if actuator_id == &"yaw_port" or actuator_id == &"yaw_starboard":
			yaw_weights.append(float(output.get("control_weight", 0.0)))
	_expect_equal(ids.size(), outputs.size(), "Each physical actuator appears exactly once in the allocation")
	_expect_equal(yaw_weights.size(), 2, "Both yaw-only actuators retain separate outputs")
	for priority: float in yaw_weights:
		_expect_near(priority, 100.0, 0.0001, "Unrelated lift demand does not dilute yaw recruitment priority")

	var achieved_force: Vector3 = result.get("achieved_force_local_n", Vector3.ZERO)
	var achieved_torque: Vector3 = result.get("achieved_torque_local_nm", Vector3.ZERO)
	_expect_near(achieved_force.x, 0.0, 0.0001, "Combined lift/yaw does not introduce lateral translation")
	_expect_near(achieved_force.y, 800.0, 0.0001, "Combined allocation preserves the requested lift resultant")
	_expect_near(achieved_force.z, 0.0, 0.0001, "Opposing yaw forces cancel longitudinal translation")
	_expect_near(achieved_torque.x, 0.0, 0.0001, "Yaw-only side vanes do not add pitch")
	_expect_near(achieved_torque.y, -100.0, 0.0001, "Yaw-only side vanes achieve the requested negative-Y moment")
	_expect_near(achieved_torque.z, 0.0, 0.0001, "Symmetric lift does not add roll")
	var force_residual: Vector3 = result.get("force_residual_local_n", Vector3.ZERO)
	var torque_residual: Vector3 = result.get("torque_residual_local_nm", Vector3.ZERO)
	_expect_near(force_residual.length(), 0.0, 0.0001, "Combined force residual remains negligible")
	_expect_near(torque_residual.length(), 0.0, 0.0001, "Combined torque residual remains negligible")

	print("Unified actuator channel-priority tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _actuator(
		actuator_id: String,
		position_local: Vector3,
		axis_local: Vector3,
		max_force_n: float,
		control_weights: Dictionary
) -> Dictionary:
	return {
		"id": StringName(actuator_id),
		"position_local": position_local,
		"axis_local": axis_local,
		"max_force_n": max_force_n,
		"control_weights": control_weights,
		"enabled": true,
	}


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
		"%s (actual %.8f, expected %.8f ± %.8f)" % [description, actual, expected, tolerance]
	)


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
