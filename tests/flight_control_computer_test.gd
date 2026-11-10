extends SceneTree

## Deterministic FCC tests. Run from the project root:
## godot --headless --path . --script res://tests/flight_control_computer_test.gd

const EPSILON: float = 0.0005
const SHIP_SCENE = preload("res://scenes/ship.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var computer := FlightControlComputer.new()

	_expect(computer.assistance_enabled, "FCC assistance is enabled by default")

	# Pilot requests are converted into ship-local angular-rate setpoints.
	var snapshot: Dictionary = computer.calculate_control_outputs(
		0.5, -0.25, 0.4, Vector3.ZERO, Basis.IDENTITY, true
	)
	var desired: Vector3 = snapshot.get("fcc_desired_rate_local_rad_s", Vector3.ZERO)
	_expect_near(desired.x, deg_to_rad(16.0), EPSILON, "Half pitch input requests half the configured pitch rate")
	_expect_near(desired.y, -deg_to_rad(9.6), EPSILON, "Yaw input maps to the local Y angular axis")
	_expect_near(desired.z, deg_to_rad(8.0), EPSILON, "Negative roll input requests positive local Z angular velocity")
	var initial_output: Vector3 = snapshot.get("fcc_control_output_by_axis", Vector3.ZERO)
	_expect_near_vector(
		initial_output,
		Vector3(0.4, 0.32, -0.2),
		EPSILON,
		"FCC output sign agrees with the established pitch/yaw/roll vane-force convention"
	)

	# At the requested rate, no further control force is needed.
	var at_target_world := Vector3(
		deg_to_rad(16.0), -deg_to_rad(9.6), deg_to_rad(8.0)
	)
	snapshot = computer.calculate_control_outputs(
		0.5, -0.25, 0.4, at_target_world, Basis.IDENTITY, true
	)
	var output: Vector3 = snapshot.get("fcc_control_output_by_axis", Vector3.ONE)
	_expect_near_vector(output, Vector3.ZERO, EPSILON, "FCC output falls to zero at the requested angular rates")

	# Zero stick requests zero rate and actively damps an existing spin.
	snapshot = computer.calculate_control_outputs(
		0.0, 0.0, 0.0, Vector3(deg_to_rad(16.0), 0.0, 0.0), Basis.IDENTITY, true
	)
	output = snapshot.get("fcc_control_output_by_axis", Vector3.ZERO)
	_expect(output.x < 0.0, "Neutral pitch request commands counter-torque against positive pitch rate")
	_expect_near(output.y, 0.0, EPSILON, "Neutral yaw axis remains uncommanded without yaw rate")

	# The controller saturates instead of requesting unlimited force.
	snapshot = computer.calculate_control_outputs(
		1.0, 0.0, 0.0, Vector3(-deg_to_rad(32.0), 0.0, 0.0), Basis.IDENTITY, true
	)
	output = snapshot.get("fcc_control_output_by_axis", Vector3.ZERO)
	_expect_near(output.x, 0.8, EPSILON, "Pitch output is bounded by the configured assisted-mode limit")
	_expect(bool(snapshot.get("fcc_pitch_saturated", false)), "Pitch saturation is reported to telemetry")

	# Local-rate extraction remains correct when the ship is rotated in world space.
	var rotated_basis := Basis(Vector3.UP, deg_to_rad(90.0))
	var expected_local_rate := Vector3(deg_to_rad(8.0), -deg_to_rad(4.0), deg_to_rad(4.0))
	var rotated_world_rate: Vector3 = rotated_basis * expected_local_rate
	snapshot = computer.calculate_control_outputs(
		0.25, -0.125, 1.0 / 6.0, rotated_world_rate, rotated_basis, true
	)
	var measured_local_rate: Vector3 = snapshot.get("fcc_actual_rate_local_rad_s", Vector3.ZERO)
	_expect_near_vector(
		measured_local_rate,
		expected_local_rate,
		EPSILON,
		"World angular velocity is converted to ship-local pitch/yaw/roll axes"
	)
	output = snapshot.get("fcc_control_output_by_axis", Vector3.ONE)
	_expect_near_vector(output, Vector3.ZERO, EPSILON, "Rotated ship still tracks local angular-rate requests")

	# Assistance OFF restores the direct Phase 2F command mapping.
	computer.set_assistance_enabled(false)
	snapshot = computer.calculate_control_outputs(
		0.3, 0.2, -0.6, Vector3(1.0, -2.0, 0.5), Basis.IDENTITY, true
	)
	output = snapshot.get("fcc_control_output_by_axis", Vector3.ZERO)
	_expect_near_vector(
		output,
		Vector3(0.3, -0.6, 0.2),
		EPSILON,
		"Assistance OFF passes pitch/yaw/roll commands directly to the vane allocator"
	)
	_expect(not bool(snapshot.get("fcc_any_axis_saturated", true)), "Direct mode does not report FCC saturation")

	# An unavailable field cannot generate stabilizing or pilot vane commands.
	snapshot = computer.calculate_control_outputs(
		1.0, 1.0, 1.0, Vector3.ZERO, Basis.IDENTITY, false
	)
	output = snapshot.get("fcc_control_output_by_axis", Vector3.ONE)
	_expect_near_vector(output, Vector3.ZERO, EPSILON, "No FCC control output is sent while the field is unavailable")

	# The output cap is an explicit tunable boundary on automatic correction.
	computer.set_assistance_enabled(true)
	computer.maximum_control_output = 0.4
	computer.rate_response_gain = 2.0
	snapshot = computer.calculate_control_outputs(
		1.0, 0.0, 0.0, Vector3.ZERO, Basis.IDENTITY, true
	)
	output = snapshot.get("fcc_control_output_by_axis", Vector3.ZERO)
	_expect_near(output.x, 0.4, EPSILON, "Inspector output limit bounds automatic correction")
	_expect(bool(snapshot.get("fcc_pitch_saturated", false)), "Tunable output cap exposes control saturation")

	# Small input noise is removed at the command deadzone.
	computer.maximum_control_output = 1.0
	computer.rate_response_gain = 0.8
	snapshot = computer.calculate_control_outputs(
		0.01, 0.0, 0.0, Vector3.ZERO, Basis.IDENTITY, true
	)
	desired = snapshot.get("fcc_desired_rate_local_rad_s", Vector3.ONE)
	_expect_near(desired.x, 0.0, EPSILON, "Mouse noise inside the deadzone produces no rate request")

	# Live integration smoke test: FCC output is passed to the actual Phase 2F
	# force allocator, producing pitch rate; neutral input must then reduce it.
	var ship := SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate ship scene for live FCC integration test")
		quit(1)
		return
	ship.position = Vector3(0.0, 100.0, 0.0)
	root.add_child(ship)
	await physics_frame

	var live_fcc := ship.get_node("FlightControlComputer") as FlightControlComputer
	var repulsorlift := ship.get_node("RepulsorliftSystem") as RepulsorliftSystem
	var live_flight_controller := ship.get_node_or_null("FlightController") as Node
	if live_fcc == null or repulsorlift == null or live_flight_controller == null:
		_fail("Ship is missing FCC, FlightController or RepulsorliftSystem for live integration test")
		ship.queue_free()
		quit(1)
		return

	# This test supplies the pilot values directly. Disable the scene's normal
	# cockpit controller so its no-pilot safety branch cannot replace them.
	live_flight_controller.set_physics_process(false)
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.sleeping = false
	for _tick in range(90):
		var live_snapshot: Dictionary = live_fcc.calculate_control_outputs(
			0.5, 0.0, 0.0, ship.angular_velocity, ship.global_basis, true
		)
		repulsorlift.apply_flight_control_forces(
			true, 1.0, 90.0,
			float(live_snapshot.get("fcc_pitch_output", 0.0)),
			float(live_snapshot.get("fcc_roll_output", 0.0)),
			float(live_snapshot.get("fcc_yaw_output", 0.0))
		)
		await physics_frame

	var local_basis: Basis = ship.global_basis.orthonormalized()
	var peak_pitch_rate: float = (local_basis.inverse() * ship.angular_velocity).x
	_expect(peak_pitch_rate > deg_to_rad(1.0), "Live FCC output creates physical pitch rotation through the vane allocator")

	for _tick in range(150):
		var neutral_snapshot: Dictionary = live_fcc.calculate_control_outputs(
			0.0, 0.0, 0.0, ship.angular_velocity, ship.global_basis, true
		)
		repulsorlift.apply_flight_control_forces(
			true, 1.0, 90.0,
			float(neutral_snapshot.get("fcc_pitch_output", 0.0)),
			float(neutral_snapshot.get("fcc_roll_output", 0.0)),
			float(neutral_snapshot.get("fcc_yaw_output", 0.0))
		)
		await physics_frame

	local_basis = ship.global_basis.orthonormalized()
	var settled_pitch_rate: float = (local_basis.inverse() * ship.angular_velocity).x
	_expect(
		absf(settled_pitch_rate) < absf(peak_pitch_rate) * 0.75,
		"Neutral stick causes the live FCC to reduce the ship's physical pitch rate"
	)

	ship.queue_free()
	print("Flight-control-computer tests: %d checks, %d failures." % [_checks, _failures])
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
