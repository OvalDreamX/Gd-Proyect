extends SceneTree

## Verifies that propulsion force and maneuver torque can be solved together
## with one bounded scalar output per physical actuator.
## Run: godot --headless --path . --script res://tests/unified_actuator_wrench_test.gd

const ALLOCATOR = preload("res://scripts/vane_actuator_allocator.gd")
const EPSILON: float = 0.1

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var weights := {
		"lift": 100,
		"pitch": 100,
		"roll": 0,
		"yaw": 0,
		"main_thrust": 0,
		"translate_x": 0,
		"translate_y": 0,
		"translate_z": 0,
	}
	var actuators: Array[Dictionary] = [
		{"id": &"front_left", "position_local": Vector3(-1.0, 0.0, -1.0), "axis_local": Vector3.UP, "max_force_n": 300.0, "control_weights": weights},
		{"id": &"front_right", "position_local": Vector3(1.0, 0.0, -1.0), "axis_local": Vector3.UP, "max_force_n": 300.0, "control_weights": weights},
		{"id": &"rear_left", "position_local": Vector3(-1.0, 0.0, 1.0), "axis_local": Vector3.UP, "max_force_n": 300.0, "control_weights": weights},
		{"id": &"rear_right", "position_local": Vector3(1.0, 0.0, 1.0), "axis_local": Vector3.UP, "max_force_n": 300.0, "control_weights": weights},
	]
	var allocation: Dictionary = ALLOCATOR.allocate(
		actuators,
		{"lift": 1.0, "pitch": 0.1},
		Vector3.ZERO,
		1000.0,
		1.0,
		160,
		0.00000001
	)
	_expect(bool(allocation.get("success", false)), "Combined lift and pitch request is accepted")
	_expect(bool(allocation.get("converged", false)), "Combined wrench allocation converges")
	var outputs: Array = allocation.get("actuator_outputs", [])
	_expect_equal(outputs.size(), 4, "Each eligible physical actuator receives one output record")
	for output_value: Variant in outputs:
		var output_entry: Dictionary = output_value
		var scalar_output: float = float(output_entry.get("output", 2.0))
		_expect(absf(scalar_output) <= 1.0 + 0.000001, "Actuator scalar output remains inside its single physical bound")
	var achieved_force: Vector3 = allocation.get("achieved_force_local_n", Vector3.ZERO)
	var achieved_torque: Vector3 = allocation.get("achieved_torque_local_nm", Vector3.ZERO)
	_expect_near(
		achieved_force.y,
		1000.0,
		EPSILON,
		"Combined allocation retains the requested propulsion resultant"
	)
	_expect_near(
		achieved_torque.x,
		100.0,
		EPSILON,
		"Combined allocation produces the requested pitch moment"
	)
	print("Unified actuator wrench tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)


func _expect_equal(actual: int, expected: int, description: String) -> void:
	_expect(actual == expected, "%s (actual %d, expected %d)" % [description, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance])
