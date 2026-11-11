extends SceneTree

## Instrument geometry and sensor-channel checks.
## Run: godot --headless --path . --script res://tests/flight_sensor_suite_test.gd

const SENSOR_SCRIPT = preload("res://scripts/flight_sensor_suite.gd")
const EPSILON: float = 0.001

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var heading: Dictionary = SENSOR_SCRIPT.calculate_heading_degrees(
		Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3(0.0, 0.0, -1.0)
	)
	_expect(bool(heading.get("valid", false)), "Northbound heading measurement is valid")
	_expect_near(float(heading.get("heading_degrees", -1.0)), 0.0, EPSILON, "North is 000 degrees")

	heading = SENSOR_SCRIPT.calculate_heading_degrees(
		Vector3.RIGHT, Vector3.UP, Vector3(0.0, 0.0, -1.0)
	)
	_expect_near(float(heading.get("heading_degrees", -1.0)), 90.0, EPSILON, "East is 090 degrees")

	heading = SENSOR_SCRIPT.calculate_heading_degrees(
		Vector3(0.0, 0.0, 1.0), Vector3.UP, Vector3(0.0, 0.0, -1.0)
	)
	_expect_near(float(heading.get("heading_degrees", -1.0)), 180.0, EPSILON, "South is 180 degrees")

	heading = SENSOR_SCRIPT.calculate_heading_degrees(
		Vector3.LEFT, Vector3.UP, Vector3(0.0, 0.0, -1.0)
	)
	_expect_near(float(heading.get("heading_degrees", -1.0)), 270.0, EPSILON, "West is 270 degrees")

	var pitched_north := Vector3(0.0, sin(deg_to_rad(35.0)), -cos(deg_to_rad(35.0)))
	heading = SENSOR_SCRIPT.calculate_heading_degrees(
		pitched_north, Vector3.UP, Vector3(0.0, 0.0, -1.0)
	)
	_expect_near(float(heading.get("heading_degrees", -1.0)), 0.0, EPSILON, "Pitch does not contaminate compass heading")

	var vertical_heading: Dictionary = SENSOR_SCRIPT.calculate_heading_degrees(
		Vector3.UP, Vector3.UP, Vector3(0.0, 0.0, -1.0)
	)
	_expect(not bool(vertical_heading.get("valid", true)), "Compass heading is invalid when the ship points vertically")

	var pitch_attitude: Dictionary = SENSOR_SCRIPT.calculate_attitude_angles(
		Basis(Vector3.RIGHT, deg_to_rad(15.0)), Vector3.UP
	)
	_expect_near(float(pitch_attitude.get("pitch_degrees", 0.0)), 15.0, 0.01, "Pitch instrument reports the true 15-degree attitude")
	_expect_near(float(pitch_attitude.get("bank_degrees", 0.0)), 0.0, 0.01, "Pure pitch does not appear as bank")

	var right_bank_basis := Basis(Vector3(0.0, 0.0, -1.0), deg_to_rad(30.0))
	var bank_attitude: Dictionary = SENSOR_SCRIPT.calculate_attitude_angles(right_bank_basis, Vector3.UP)
	_expect_near(float(bank_attitude.get("bank_degrees", 0.0)), 30.0, 0.01, "Right-wing-down rotation reports positive 30-degree bank")

	var body := RigidBody3D.new()
	root.add_child(body)
	var sensor = SENSOR_SCRIPT.new()
	body.add_child(sensor)
	await physics_frame
	body.linear_velocity = Vector3(0.0, 0.0, -12.0)
	await physics_frame
	var packet: Dictionary = sensor.get_instrument_snapshot()
	_expect(packet.has("instrument_attitude_basis_world"), "Sensor suite publishes an instrument packet")
	_expect(bool(packet.get("instrument_heading_valid", false)), "Heading channel starts nominal")
	_expect_near_vector(
		packet.get("instrument_inertial_velocity_world", Vector3.ZERO),
		body.linear_velocity,
		EPSILON,
		"Sensor packet exposes inertial velocity for the flight-path marker"
	)
	_expect_near_vector(
		packet.get("instrument_air_relative_velocity_world", Vector3.ZERO),
		body.linear_velocity,
		EPSILON,
		"In vacuum, the indicated velocity channel matches inertial velocity"
	)
	sensor.set_channel_available(&"heading", false)
	packet = sensor.get_instrument_snapshot()
	_expect(not bool(packet.get("instrument_heading_valid", true)), "Heading channel can be independently marked failed")
	_expect(bool(packet.get("instrument_attitude_valid", false)), "Heading failure does not invalidate attitude data")
	body.queue_free()

	print("Flight-sensor-suite tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_near_vector(actual: Vector3, expected: Vector3, tolerance: float, description: String) -> void:
	_expect(actual.distance_to(expected) <= tolerance, "%s (actual %s, expected %s)" % [description, str(actual), str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(
		absf(actual - expected) <= tolerance,
		"%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance]
	)


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
