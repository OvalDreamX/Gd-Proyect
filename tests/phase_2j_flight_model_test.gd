extends SceneTree

## Deterministic atmosphere checks, wind/turbulence checks and a RigidBody3D drag smoke test.
## Run from the project root with Godot 4.7.2:
## godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd

const ATMOSPHERIC_MODEL_SCRIPT = preload("res://scripts/atmospheric_flight_model.gd")
const FLIGHT_CONTROLLER_SCRIPT = preload("res://scripts/ship_flight_controller.gd")
const EPSILON: float = 0.0001

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	# Mouse movement now behaves like a physical flight stick.
	var mouse_up_delta: float = FLIGHT_CONTROLLER_SCRIPT.pitch_command_delta_from_mouse_y(-100.0, 0.003)
	var mouse_down_delta: float = FLIGHT_CONTROLLER_SCRIPT.pitch_command_delta_from_mouse_y(100.0, 0.003)
	_expect(mouse_up_delta < 0.0, "Pushing the mouse up commands nose-down pitch")
	_expect(mouse_down_delta > 0.0, "Pulling the mouse down commands nose-up pitch")
	_expect_near(mouse_up_delta, -0.3, EPSILON, "Mouse pitch sensitivity preserves the configured scale")

	# Exponential atmosphere profile.
	var sea_level_density: float = ATMOSPHERIC_MODEL_SCRIPT.calculate_air_density(1.225, 0.0, 8500.0)
	var one_scale_height_density: float = ATMOSPHERIC_MODEL_SCRIPT.calculate_air_density(1.225, 8500.0, 8500.0)
	var below_reference_density: float = ATMOSPHERIC_MODEL_SCRIPT.calculate_air_density(1.225, -100.0, 8500.0)
	_expect_near(sea_level_density, 1.225, EPSILON, "Air density equals the configured sea-level value at the reference altitude")
	_expect_near(one_scale_height_density, 1.225 / exp(1.0), EPSILON, "Air density falls exponentially by one scale height")
	_expect_near(below_reference_density, 1.225, EPSILON, "Density does not exceed sea-level density below the reference point")
	_expect_near(ATMOSPHERIC_MODEL_SCRIPT.calculate_air_density(1.225, 1000.0, 0.0), 0.0, EPSILON, "Invalid scale height safely disables density calculation")

	# Projected area for the prototype hull: 3.6 x 1.5 x 5.2 m.
	var hull_dimensions := Vector3(3.6, 1.5, 5.2)
	_expect_near(
		ATMOSPHERIC_MODEL_SCRIPT.calculate_projected_box_area(Vector3.FORWARD, hull_dimensions),
		5.4,
		EPSILON,
		"Nose-on projected area uses hull width times height"
	)
	_expect_near(
		ATMOSPHERIC_MODEL_SCRIPT.calculate_projected_box_area(Vector3.RIGHT, hull_dimensions),
		7.8,
		EPSILON,
		"Side-on projected area uses hull length times height"
	)
	_expect_near(
		ATMOSPHERIC_MODEL_SCRIPT.calculate_projected_box_area(Vector3.UP, hull_dimensions),
		18.72,
		EPSILON,
		"Vertical projected area uses hull length times width"
	)
	_expect_near(
		ATMOSPHERIC_MODEL_SCRIPT.calculate_projected_box_area(Vector3.ZERO, hull_dimensions),
		0.0,
		EPSILON,
		"Zero airflow direction produces no projected area"
	)

	# Drag direction and its quadratic speed relationship.
	var velocity: Vector3 = Vector3(0.0, 0.0, -20.0)
	var drag_at_20: Vector3 = ATMOSPHERIC_MODEL_SCRIPT.calculate_drag_force(velocity, 1.225, 0.8, 5.4)
	var drag_at_40: Vector3 = ATMOSPHERIC_MODEL_SCRIPT.calculate_drag_force(velocity * 2.0, 1.225, 0.8, 5.4)
	_expect(drag_at_20.z > 0.0, "Drag opposes forward air-relative velocity")
	_expect_near(drag_at_40.length() / drag_at_20.length(), 4.0, EPSILON, "Doubling airspeed quadruples quadratic drag")
	_expect_near(
		ATMOSPHERIC_MODEL_SCRIPT.calculate_drag_force(Vector3.ZERO, 1.225, 0.8, 5.4).length(),
		0.0,
		EPSILON,
		"Zero airspeed produces no drag"
	)
	_expect_near(
		ATMOSPHERIC_MODEL_SCRIPT.calculate_drag_force(velocity, 0.0, 0.8, 5.4).length(),
		0.0,
		EPSILON,
		"Zero atmospheric density produces no drag"
	)

	await _test_live_rigid_body_drag()

	print("Phase 2J/2K flight-model tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_live_rigid_body_drag() -> void:
	var body := RigidBody3D.new()
	body.name = "AtmosphericDragTestBody"
	body.mass = 12000.0
	body.gravity_scale = 0.0
	body.can_sleep = false
	body.linear_velocity = Vector3(0.0, 0.0, -50.0)
	var collision := CollisionShape3D.new()
	var collision_sphere := SphereShape3D.new()
	collision_sphere.radius = 1.0
	collision.shape = collision_sphere
	body.add_child(collision)

	var model := Node.new()
	model.name = "AtmosphericFlightModel"
	model.set_script(ATMOSPHERIC_MODEL_SCRIPT)
	body.add_child(model)
	root.add_child(body)

	await physics_frame
	await physics_frame

	var telemetry: Dictionary = model.call("get_telemetry")
	var drag_force: Vector3 = telemetry.get("atmosphere_drag_force_world", Vector3.ZERO)
	var mean_wind: Vector3 = telemetry.get("atmosphere_mean_wind_velocity_world", Vector3.ZERO)
	var actual_wind: Vector3 = telemetry.get("atmosphere_velocity_world", Vector3.ZERO)
	var turbulence: Vector3 = telemetry.get("atmosphere_turbulence_velocity_world", Vector3.ZERO)
	_expect(drag_force.z > 0.0, "Atmospheric subsystem submits drag opposing forward air-relative velocity")
	_expect(drag_force.x > 0.0, "Front-left crosswind creates a measurable lateral drag force")
	_expect(float(telemetry.get("atmosphere_density_kg_m3", 0.0)) > 1.2, "Live subsystem samples near sea-level density")
	_expect(float(telemetry.get("atmosphere_drag_force_n", 0.0)) > 0.0, "Live subsystem exposes drag magnitude for diagnostics")
	_expect(mean_wind.x > 0.0 and mean_wind.z > 0.0, "Mean wind flows from the ship's front-left toward its rear-right")
	_expect(actual_wind.distance_to(mean_wind) <= 1.15, "Smooth turbulence remains within its configured amplitude envelope")
	_expect(absf(body.linear_velocity.z) < 50.0, "Live drag force reduces the ship's forward speed")
	var initial_turbulence: Vector3 = turbulence
	for _tick in range(60):
		await physics_frame
	var later_telemetry: Dictionary = model.call("get_telemetry")
	var later_turbulence: Vector3 = later_telemetry.get("atmosphere_turbulence_velocity_world", Vector3.ZERO)
	_expect(initial_turbulence.distance_to(later_turbulence) > 0.0001, "Coherent turbulence varies over time instead of applying frame-random impulses")

	model.set("atmosphere_enabled", false)
	model.call("_physics_process", 1.0 / 60.0)
	telemetry = model.call("get_telemetry")
	_expect_near(float(telemetry.get("atmosphere_drag_force_n", -1.0)), 0.0, EPSILON, "Disabling the local atmosphere removes the drag force")
	body.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.6f, expected %.6f ± %.6f)" % [description, actual, expected, tolerance])


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
