extends SceneTree

## Shared environmental-frame checks.
## Run: godot --headless --path . --script res://tests/planetary_reference_frame_test.gd

const FRAME_SCRIPT = preload("res://scripts/planetary_reference_frame.gd")
const GRAVITY_BODY_SCRIPT = preload("res://scripts/planetary_gravity_body.gd")
const TEST_RANGE_SCENE = preload("res://scenes/test_range.tscn")
const EPSILON: float = 0.001

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var frame := Node3D.new()
	frame.name = "PlanetaryReferenceFrame"
	frame.set_script(FRAME_SCRIPT)
	root.add_child(frame)
	await process_frame

	var flat: Dictionary = frame.call("get_local_frame", Vector3(100.0, 25.0, -80.0))
	_expect_near(float(flat["altitude_m"]), 25.0, EPSILON, "Flat-plane altitude is measured along the frame's local up")
	_expect_near_vector(flat["up_world"], Vector3.UP, EPSILON, "Default flat frame up is world +Y")
	_expect_near_vector(flat["north_world"], Vector3(0.0, 0.0, -1.0), EPSILON, "Default tangent north is world -Z")
	_expect_near_vector(flat["east_world"], Vector3.RIGHT, EPSILON, "Default tangent east is world +X")
	_expect_near_vector(flat["gravity_world"], Vector3.DOWN * 9.81, EPSILON, "Flat frame gravity points opposite local up")

	var mapped_wind: Vector3 = frame.call("local_vector_to_world", Vector3(5.0, 0.0, -6.25), Vector3.ZERO)
	_expect_near_vector(mapped_wind, Vector3(5.0, 0.0, 6.25), EPSILON, "East/up/north wind components map to the expected test-range world vector")

	var rotated_frame := Node3D.new()
	rotated_frame.name = "RotatedReferenceFrame"
	rotated_frame.set_script(FRAME_SCRIPT)
	rotated_frame.rotation.y = deg_to_rad(90.0)
	root.add_child(rotated_frame)
	await process_frame
	var rotated_data: Dictionary = rotated_frame.call("get_local_frame", Vector3.ZERO)
	_expect_near_vector(rotated_data["north_world"], Vector3.LEFT, EPSILON, "Tangent north follows the planetary frame's rotated orientation")
	_expect_near_vector(rotated_data["east_world"], Vector3(0.0, 0.0, -1.0), EPSILON, "Tangent east follows the rotated frame")
	var rotated_wind: Vector3 = rotated_frame.call("local_vector_to_world", Vector3(5.0, 0.0, -6.25), Vector3.ZERO)
	_expect_near_vector(rotated_wind, Vector3(6.25, 0.0, -5.0), EPSILON, "Local wind remains local when the planet's frame rotates")
	rotated_frame.queue_free()
	await process_frame

	frame.set("surface_geometry", 1)
	frame.set("surface_radius_m", 1000.0)
	var spherical: Dictionary = frame.call("get_local_frame", Vector3(0.0, 1100.0, 0.0))
	_expect_near(float(spherical["altitude_m"]), 100.0, EPSILON, "Spherical altitude is radius minus surface radius")
	_expect_near_vector(spherical["up_world"], Vector3.UP, EPSILON, "Spherical local up is radial")
	_expect_near(float(spherical["gravity_magnitude_mps2"]), 9.81 * pow(1000.0 / 1100.0, 2.0), EPSILON, "Spherical gravity follows inverse-square radial falloff")
	_expect_near(
		FRAME_SCRIPT.calculate_spherical_gravity_magnitude(9.81, 1000.0, 500.0),
		4.905,
		EPSILON,
		"Interior gravity follows the finite uniform-density approximation"
	)
	_expect_near(
		FRAME_SCRIPT.calculate_spherical_gravity_magnitude(9.81, 1000.0, 0.0),
		0.0,
		EPSILON,
		"Gravity is finite and zero at the spherical center"
	)

	var pole_frame: Dictionary = frame.call("get_local_frame", Vector3(0.0, 0.0, 1100.0))
	var pole_up: Vector3 = pole_frame["up_world"]
	var pole_north: Vector3 = pole_frame["north_world"]
	var pole_east: Vector3 = pole_frame["east_world"]
	_expect(absf(pole_north.dot(pole_up)) < EPSILON, "Pole fallback north remains tangent to the surface")
	_expect(absf(pole_east.dot(pole_up)) < EPSILON and absf(pole_east.dot(pole_north)) < EPSILON, "Pole fallback east remains orthogonal to north and up")

	# Live adapter test in a minimal scene tree. Switch back to flat gravity.
	frame.set("surface_geometry", 0)
	frame.set("surface_radius_m", 0.0)
	var body := RigidBody3D.new()
	body.mass = 1000.0
	body.gravity_scale = 1.0
	body.position = Vector3(0.0, 20.0, 0.0)
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	collision.shape = sphere
	body.add_child(collision)
	root.add_child(body)
	var gravity_adapter := Node.new()
	gravity_adapter.name = "PlanetaryGravityBody"
	gravity_adapter.set_script(GRAVITY_BODY_SCRIPT)
	body.add_child(gravity_adapter)
	await process_frame
	_expect_near(body.gravity_scale, 0.0, EPSILON, "Planetary adapter disables duplicate world-axis gravity")
	var initial_vertical_speed: float = body.linear_velocity.y
	for _tick in range(8):
		await physics_frame
	_expect(body.linear_velocity.y < initial_vertical_speed - 0.5, "Reference-frame gravity accelerates the rigid body once each physics tick")
	_expect_near_vector(gravity_adapter.call("get_local_gravity_vector_world"), Vector3.DOWN * 9.81, EPSILON, "Gravity adapter exposes the same local gravity vector used by physics")
	body.sleeping = true
	await physics_frame
	_expect(body.sleeping, "Settled bodies are not continuously awakened by scripted gravity")
	body.queue_free()
	frame.queue_free()
	await process_frame

	# Validate that the actual test-range scene wires the same provider into the
	# ship, atmosphere, sensors and walking controller.
	var world := TEST_RANGE_SCENE.instantiate()
	root.add_child(world)
	await process_frame
	await physics_frame
	var ship := world.get_node("Ship") as RigidBody3D
	var atmosphere := ship.get_node("AtmosphericFlightModel")
	var sensors := ship.get_node("FlightSensorSuite")
	var player := world.get_node("Player")
	var world_frame := world.get_node("PlanetaryReferenceFrame") as Node3D
	_expect(is_instance_valid(ship.get_node_or_null("PlanetaryGravityBody")), "Test-range ship includes the planetary gravity adapter")
	_expect(is_equal_approx(ship.gravity_scale, 0.0), "Test-range ship uses the shared local gravity field")
	var atmosphere_data: Dictionary = atmosphere.call("get_telemetry")
	_expect(Vector3(atmosphere_data["atmosphere_mean_wind_velocity_world"]).x > 0.0 and Vector3(atmosphere_data["atmosphere_mean_wind_velocity_world"]).z > 0.0, "Atmosphere wind is converted from local east/north into the shared world frame")
	var instrument_data: Dictionary = sensors.call("get_instrument_snapshot")
	_expect_near_vector(instrument_data["instrument_local_up_world"], Vector3.UP, EPSILON, "Flight instruments consume the shared local up vector")
	_expect(bool(instrument_data["instrument_heading_valid"]), "Compass remains valid when using the shared tangent north")
	_expect_near_vector(player.call("_get_local_up_world"), world_frame.global_basis.y.normalized(), EPSILON, "Walking controller uses the same planetary reference frame")

	print("Planetary reference-frame tests: %d checks, %d failures." % [_checks, _failures])
	world.queue_free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance])


func _expect_near_vector(actual: Vector3, expected: Vector3, tolerance: float, description: String) -> void:
	_expect(actual.distance_to(expected) <= tolerance, "%s (actual %s, expected %s)" % [description, str(actual), str(expected)])
