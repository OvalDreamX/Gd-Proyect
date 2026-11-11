extends SceneTree

## Headless rigid-body integration check for the Phase 2F vane wrench.
## Run from the project root:
## godot --headless --path . --script res://tests/vane_physics_integration_test.gd

const SHIP_SCENE = preload("res://scenes/ship.tscn")

const TEST_ALTITUDE: float = 100.0
const TEST_POWER_OUTPUT: float = 1.0
const TEST_TICKS: int = 60
const HEALTHY_ANGULAR_SPEED_LIMIT: float = 0.02
const DAMAGED_ROLL_RATE_MINIMUM: float = 0.05

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var ship := SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate scenes/ship.tscn")
		quit(1)
		return

	# Keep the body clear of the test range floor. Only the ship scene is loaded.
	ship.position = Vector3(0.0, TEST_ALTITUDE, 0.0)
	root.add_child(ship)
	await physics_frame

	var vane_controller := ship.get_node("VaneController") as VaneController
	var repulsorlift := ship.get_node("RepulsorliftSystem") as RepulsorliftSystem
	if vane_controller == null or repulsorlift == null:
		_fail("Ship scene is missing VaneController or RepulsorliftSystem")
		quit(1)
		return

	_expect(vane_controller.is_configuration_valid(), "Ship vane configuration is valid")

	# Case 1: healthy symmetric vanes must not create unintended rotation.
	vane_controller.reset_all_vanes()
	_reset_body(ship)
	await _apply_for_ticks(repulsorlift, TEST_TICKS)
	var healthy_angular_speed: float = ship.angular_velocity.length()
	_expect(
		healthy_angular_speed <= HEALTHY_ANGULAR_SPEED_LIMIT,
		"Healthy symmetric vanes produce negligible angular velocity (%.5f rad/s)" % healthy_angular_speed
	)

	# Case 2: weaken right-front vane. The stronger left-front vane creates
	# the expected negative Z roll moment with the current local coordinate layout.
	vane_controller.reset_all_vanes()
	vane_controller.set_vane_integrity(&"bottom_front_right", 0.5)
	_reset_body(ship)
	await _apply_for_ticks(repulsorlift, TEST_TICKS)
	var right_damaged_roll_rate: float = ship.angular_velocity.z
	_expect(
		right_damaged_roll_rate < -DAMAGED_ROLL_RATE_MINIMUM,
		"50%-effective right-front vane produces the expected roll direction (%.5f rad/s)" % right_damaged_roll_rate
	)

	# Case 3: weaken the opposite vane. The roll direction must reverse.
	vane_controller.reset_all_vanes()
	vane_controller.set_vane_integrity(&"bottom_front_left", 0.5)
	_reset_body(ship)
	await _apply_for_ticks(repulsorlift, TEST_TICKS)
	var left_damaged_roll_rate: float = ship.angular_velocity.z
	_expect(
		left_damaged_roll_rate > DAMAGED_ROLL_RATE_MINIMUM,
		"50%-effective left-front vane reverses the roll direction (%.5f rad/s)" % left_damaged_roll_rate
	)

	print("Vane physics integration tests: %d checks, %d failures." % [_checks, _failures])
	ship.queue_free()
	quit(1 if _failures > 0 else 0)


func _reset_body(ship: RigidBody3D) -> void:
	# Freeze briefly so the test can reset transform and velocities safely.
	ship.freeze = true
	ship.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, TEST_ALTITUDE, 0.0))
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.freeze = false
	ship.sleeping = false


func _apply_for_ticks(system: RepulsorliftSystem, tick_count: int) -> void:
	for _tick in range(tick_count):
		system.apply_collective_lift(true, TEST_POWER_OUTPUT)
		await physics_frame


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
