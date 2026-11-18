extends SceneTree

## Integration tests verifying EnvironmentManager switching between planet and
## local-space profiles on the same ship subsystems, plus test_range regression safety.
## Run: godot --headless --path . --script res://tests/environment_manager_test.gd

const MANAGER_SCRIPT = preload("res://scripts/environment_manager.gd")
const FRAME_SCRIPT = preload("res://scripts/planetary_reference_frame.gd")
const PLANET_PROFILE = preload("res://data/environments/test_planet_surface.tres")
const SPACE_PROFILE = preload("res://data/environments/station_local_space.tres")
const SHIP_SCENE = preload("res://scenes/ship_ground_effect.tscn")
const TEST_RANGE_SCENE = preload("res://scenes/test_range.tscn")

const EPSILON: float = 0.005

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var container := Node3D.new()
	container.name = "EnvTestWorld"
	root.add_child(container)

	var body_radius: float = float(PLANET_PROFILE.call("get_effective_surface_radius_m"))
	var ref_frame := Node3D.new()
	ref_frame.name = "PlanetaryReferenceFrame"
	ref_frame.set_script(FRAME_SCRIPT)
	# Place spherical planet center dynamically at -body_radius so local origin is surface altitude 0.
	ref_frame.position = Vector3(0.0, -body_radius, 0.0)
	container.add_child(ref_frame)

	var env_manager := Node.new()
	env_manager.name = "EnvironmentManager"
	env_manager.set_script(MANAGER_SCRIPT)
	env_manager.set("active_profile", PLANET_PROFILE)
	container.add_child(env_manager)

	var ship := SHIP_SCENE.instantiate() as RigidBody3D
	ship.position = Vector3(0.0, 5.0, 0.0)
	ship.linear_velocity = Vector3(40.0, 0.0, 0.0)
	container.add_child(ship)

	await process_frame
	await physics_frame

	var gravity_body := ship.get_node("PlanetaryGravityBody")
	var atmosphere := ship.get_node("AtmosphericFlightModel")
	var sensors := ship.get_node("FlightSensorSuite")

	_expect(is_equal_approx(ship.gravity_scale, 0.0), "Ship uses custom environment gravity rather than built-in world gravity")
	var planet_gravity: Vector3 = gravity_body.call("get_local_gravity_vector_world")
	_expect(planet_gravity.y < -9.5, "Planet profile applies downward gravity toward spherical planet center")
	var planet_atmo: Dictionary = atmosphere.call("get_telemetry")
	_expect(bool(planet_atmo["atmosphere_enabled"]), "Planet profile enables atmospheric flight model")
	_expect(float(planet_atmo["atmosphere_density_kg_m3"]) > 1.0, "Planet profile supplies near-surface air density")
	_expect(Vector3(planet_atmo["atmosphere_drag_force_world"]).length() > 1.0, "Ship moving in planet atmosphere experiences aerodynamic drag")

	var planet_snapshot: Dictionary = sensors.call("get_instrument_snapshot")
	_expect(str(planet_snapshot["instrument_environment_type"]) == "PLANET_SURFACE", "Sensor suite reports PLANET_SURFACE")
	_expect(bool(planet_snapshot["instrument_heading_valid"]), "Sensor heading is valid in planet surface profile")

	# Switch the same ship to LOCAL_SPACE.
	env_manager.call("set_active_profile", SPACE_PROFILE)
	ship.linear_velocity = Vector3(25.0, 0.0, 0.0)
	await process_frame
	await physics_frame

	var space_gravity: Vector3 = gravity_body.call("get_local_gravity_vector_world")
	_expect(space_gravity.length() <= EPSILON, "Space profile zeros planetary gravity on the ship")
	_expect(is_equal_approx(ship.gravity_scale, 0.0), "Space profile keeps RigidBody3D.gravity_scale at 0.0")
	var space_atmo: Dictionary = atmosphere.call("get_telemetry")
	_expect(not bool(space_atmo["atmosphere_enabled"]), "Space profile disables atmospheric flight model")
	_expect_near(float(space_atmo["atmosphere_density_kg_m3"]), 0.0, EPSILON, "Space profile has zero air density")
	_expect_near(float(space_atmo["atmosphere_drag_force_n"]), 0.0, EPSILON, "Space profile applies zero aerodynamic drag")
	_expect_near(float(space_atmo["atmosphere_temperature_celsius"]), -150.0, EPSILON, "Space profile updates ambient thermal temperature")

	var speed_before: float = ship.linear_velocity.x
	for _tick in range(5):
		await physics_frame
	_expect_near(ship.linear_velocity.y, 0.0, EPSILON, "Ship does not fall under hidden default gravity in LOCAL_SPACE")
	_expect_near(ship.linear_velocity.x, speed_before, EPSILON, "Ship preserves inertial velocity in LOCAL_SPACE")

	var space_snapshot: Dictionary = sensors.call("get_instrument_snapshot")
	_expect(str(space_snapshot["instrument_environment_type"]) == "LOCAL_SPACE", "Sensor suite reports LOCAL_SPACE")
	_expect(str(space_snapshot["instrument_speed_label"]) == "SPEED", "Sensor suite uses inertial SPEED label in space")

	container.queue_free()
	await process_frame

	# Verify test_range.tscn still works identically without an EnvironmentManager.
	var test_range := TEST_RANGE_SCENE.instantiate()
	root.add_child(test_range)
	await process_frame
	await physics_frame
	var range_ship := test_range.get_node("Ship") as RigidBody3D
	var range_atmo := range_ship.get_node("AtmosphericFlightModel")
	var range_atmo_data: Dictionary = range_atmo.call("get_telemetry")
	_expect(bool(range_atmo_data["atmosphere_enabled"]), "Existing test_range retains enabled atmosphere without EnvironmentManager")
	_expect(float(range_atmo_data["atmosphere_density_kg_m3"]) > 1.2, "Existing test_range retains sea-level density")
	test_range.queue_free()

	print("Environment manager tests: %d checks, %d failures." % [_checks, _failures])
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
