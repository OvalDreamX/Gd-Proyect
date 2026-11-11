extends SceneTree

## Regression tests for bounded FCC integral trim and anti-windup.
## Run: godot --headless --path . --script res://tests/flight_control_trim_test.gd

const FCC_SCRIPT = preload("res://scripts/flight_control_computer.gd")
const EPSILON: float = 0.0005

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var fcc = FCC_SCRIPT.new()
	var persistent_roll_rate := Vector3(0.0, 0.0, 0.20)

	# A persistent disturbance should build a small trim term over time.
	for _tick in range(30):
		fcc.calculate_control_outputs(
			0.0, 0.0, 0.0,
			persistent_roll_rate,
			Basis.IDENTITY,
			true,
			0.1
		)
	var trim_after_disturbance: Vector3 = fcc._integral_trim_output_by_axis
	_expect(trim_after_disturbance.z > 0.02, "Persistent roll-rate error accumulates positive counter-torque trim")
	_expect(trim_after_disturbance.length() <= fcc.maximum_integral_trim_output + EPSILON, "Integral trim remains within its configured per-axis bound")

	# Once the angular rate is damped, the integral term must retain a bounded
	# output that counters the persistent external moment.
	var neutral_snapshot: Dictionary = fcc.calculate_control_outputs(
		0.0, 0.0, 0.0,
		Vector3.ZERO,
		Basis.IDENTITY,
		true,
		0.1
	)
	var neutral_output: Vector3 = neutral_snapshot.get("fcc_control_output_by_axis", Vector3.ZERO)
	_expect(neutral_output.z > 0.02, "Stored integral trim remains active after angular rate reaches zero")
	_expect(bool(neutral_snapshot.get("fcc_trim_active", false)), "FCC reports active integral trim")

	# Reset and drive the proportional term beyond the output cap. The integrator
	# must not wind further into saturation.
	fcc.reset_integral_trim()
	var excessive_rate := Vector3(0.0, 0.0, 10.0)
	for _tick in range(50):
		fcc.calculate_control_outputs(
			0.0, 0.0, 0.0,
			excessive_rate,
			Basis.IDENTITY,
			true,
			0.1
		)
	_expect_near(fcc._integral_trim_output_by_axis.z, 0.0, EPSILON, "Anti-windup blocks integral growth into output saturation")

	# Losing the field or disabling assistance clears retained trim immediately.
	fcc.calculate_control_outputs(
		0.0, 0.0, 0.0, persistent_roll_rate,
		Basis.IDENTITY, true, 0.1
	)
	fcc.calculate_control_outputs(
		0.0, 0.0, 0.0, Vector3.ZERO,
		Basis.IDENTITY, false, 0.1
	)
	_expect_near_vector(fcc._integral_trim_output_by_axis, Vector3.ZERO, EPSILON, "Unavailable control authority clears retained trim")

	fcc.calculate_control_outputs(
		0.0, 0.0, 0.0, persistent_roll_rate,
		Basis.IDENTITY, true, 0.1
	)
	fcc.set_assistance_enabled(false)
	_expect_near_vector(fcc._integral_trim_output_by_axis, Vector3.ZERO, EPSILON, "Switching to direct-vane mode clears the integral term")

	print("FCC trim tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(
		absf(actual - expected) <= tolerance,
		"%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance]
	)


func _expect_near_vector(actual: Vector3, expected: Vector3, tolerance: float, description: String) -> void:
	_expect(
		actual.distance_to(expected) <= tolerance,
		"%s (actual %s, expected %s)" % [description, str(actual), str(expected)]
	)


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
