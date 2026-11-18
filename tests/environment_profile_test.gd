extends SceneTree

## Pure logic tests for CelestialBodyDefinition and EnvironmentProfile.
## Run: godot --headless --path . --script res://tests/environment_profile_test.gd

const BODY_RESOURCE = preload("res://data/celestial/test_planet.tres")
const PLANET_PROFILE = preload("res://data/environments/test_planet_surface.tres")
const SPACE_PROFILE = preload("res://data/environments/station_local_space.tres")

const EPSILON: float = 0.001

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_expect(BODY_RESOURCE != null, "Test planet CelestialBodyDefinition resource loads")
	_expect(PLANET_PROFILE != null, "Planet surface EnvironmentProfile resource loads")
	_expect(SPACE_PROFILE != null, "Station local space EnvironmentProfile resource loads")

	if BODY_RESOURCE != null:
		var body_radius: float = float(BODY_RESOURCE.get("radius_m"))
		var expected_mu: float = 9.81 * body_radius * body_radius
		_expect(body_radius >= 60000.0, "Body radius reads dynamically from CelestialBodyDefinition (%.0f m)" % body_radius)
		_expect_near(float(BODY_RESOURCE.call("get_gravitational_parameter")), expected_mu, 1.0, "Gravitational parameter mu equals g_surface * R^2")
		_expect_near(float(BODY_RESOURCE.call("calculate_gravity_magnitude_at_altitude", 0.0)), 9.81, EPSILON, "Surface gravity matches 9.81 m/s^2 at altitude 0")
		_expect_near(float(BODY_RESOURCE.call("calculate_gravity_magnitude_at_radius", body_radius * 2.0)), 9.81 * 0.25, EPSILON, "Gravity follows inverse-square law at 2R")
		_expect_near(float(BODY_RESOURCE.call("calculate_gravity_magnitude_at_radius", body_radius * 0.5)), 9.81 * 0.5, EPSILON, "Interior gravity falls off linearly inside R")
		_expect_near(float(BODY_RESOURCE.call("calculate_gravity_magnitude_at_radius", 0.0)), 0.0, EPSILON, "Gravity is zero at body center")
		_expect_near(float(BODY_RESOURCE.call("calculate_air_density_at_altitude", 0.0)), 1.225, EPSILON, "Sea-level air density matches 1.225 kg/m^3")
		_expect(float(BODY_RESOURCE.call("calculate_air_density_at_altitude", 8500.0)) < 0.5, "Air density decays exponentially with scale height")
		_expect_near(float(BODY_RESOURCE.call("calculate_air_density_at_altitude", 45000.0)), 0.0, EPSILON, "Air density reaches zero at atmosphere_top_altitude_m")

	if PLANET_PROFILE != null:
		_expect(str(PLANET_PROFILE.call("get_environment_type_name")) == "PLANET_SURFACE", "Planet profile reports PLANET_SURFACE")
		_expect_near(float(PLANET_PROFILE.call("get_effective_surface_gravity_mps2")), 9.81, EPSILON, "Planet profile inherits surface gravity from celestial body")
		_expect(bool(PLANET_PROFILE.call("is_atmosphere_active")), "Planet profile activates atmosphere")
		_expect_near(float(PLANET_PROFILE.call("calculate_air_density_kg_m3", 0.0)), 1.225, EPSILON, "Planet profile sea-level density matches body definition")

	if SPACE_PROFILE != null:
		_expect(str(SPACE_PROFILE.call("get_environment_type_name")) == "LOCAL_SPACE", "Space profile reports LOCAL_SPACE")
		_expect_near(float(SPACE_PROFILE.call("get_effective_surface_gravity_mps2")), 0.0, EPSILON, "Space profile forces zero surface gravity")
		_expect(not bool(SPACE_PROFILE.call("is_atmosphere_active")), "Space profile disables atmosphere")
		_expect_near(float(SPACE_PROFILE.call("calculate_air_density_kg_m3", 0.0)), 0.0, EPSILON, "Space profile reports zero air density")
		_expect(SPACE_PROFILE.call("get_effective_mean_wind_local_mps") == Vector3.ZERO, "Space profile zeros local wind")

	print("Environment profile tests: %d checks, %d failures." % [_checks, _failures])
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
