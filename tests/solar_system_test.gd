extends SceneTree

## Headless pure + integration tests for Phase 3I Simple Solar System,
## 1:1 star lighting, late-afternoon starting epoch, planet spin & orbit, and station orbit.
## Run: godot --headless --path . --script res://tests/solar_system_test.gd

const LOADER_SCRIPT = preload("res://scripts/solar_system_loader.gd")
const CLOCK_SCRIPT = preload("res://scripts/simulation_clock.gd")
const PLANET_SCENE = preload("res://scenes/planet_surface.tscn")
const STATION_SCENE = preload("res://scenes/station_local_space.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_run_json_loader_and_kinematic_tests()
	_run_clock_continuity_tests()
	await _run_dual_scene_integration_tests()
	print("Solar system tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_json_loader_and_kinematic_tests() -> void:
	var loaded: Dictionary = LOADER_SCRIPT.load_system_from_file("res://data/systems/test_system.json")
	_expect(bool(loaded.get("valid", false)), "data/systems/test_system.json loads and validates cleanly")
	var sys: Dictionary = loaded.get("system", {})

	var bad_missing_star: Dictionary = LOADER_SCRIPT.parse_and_validate_json('{"system_id":"bad","stars":[],"planets":[],"stations":[]}')
	_expect(not bool(bad_missing_star.get("valid", true)), "Validator rejects empty stars array")

	var bad_neg_intensity: Dictionary = LOADER_SCRIPT.parse_and_validate_json('{"system_id":"bad","stars":[{"star_id":"s1","light_color":[1,1,1],"light_intensity":-0.5}],"planets":[{"planet_id":"p1","planet_type":"TERRESTRIAL","parent_star_id":"s1","radius_m":100000,"orbital_radius_m":1000000,"orbital_period_seconds":1000,"rotation_period_seconds":500}],"stations":[]}')
	_expect(not bool(bad_neg_intensity.get("valid", true)), "Validator rejects negative star light_intensity")

	var bad_orphan_station: Dictionary = LOADER_SCRIPT.parse_and_validate_json('{"system_id":"bad","stars":[{"star_id":"s1","light_color":[1,1,1],"light_intensity":1.0}],"planets":[{"planet_id":"p1","planet_type":"TERRESTRIAL","parent_star_id":"s1","radius_m":100000,"orbital_radius_m":1000000,"orbital_period_seconds":1000,"rotation_period_seconds":500}],"stations":[{"station_id":"st1","orbit_parent_id":"missing_planet","orbital_radius_m":180000,"orbital_period_seconds":900}]}')
	_expect(not bool(bad_orphan_station.get("valid", true)), "Validator rejects station referencing missing orbit_parent_id")

	var state0: Dictionary = LOADER_SCRIPT.evaluate_system_state(sys, 0.0)
	_expect(bool(state0.get("valid", false)), "SolarSystemLoader evaluates initial state cleanly")
	_expect(absf(float(state0.get("star_light_intensity", 0.0)) - 1.0) < 0.001, "Star light_intensity calibrates 1:1 to 1.0")

	var l_col: Color = Color(state0.get("star_light_color", Color.BLACK))
	_expect(l_col.r > 0.95 and l_col.g > 0.90 and l_col.b > 0.85, "Star has normal neutral white-warm solar color")

	var elev0: float = float(state0.get("surface_solar_elevation_deg", 0.0))
	var az0: float = float(state0.get("surface_solar_azimuth_deg", 0.0))
	_expect(elev0 >= 12.0 and elev0 <= 24.0, "Initial planet surface starts in late afternoon (~18 deg elevation, actual %.2f deg)" % elev0)
	_expect(az0 >= 180.0 and az0 <= 300.0, "Initial late-afternoon sun is in western sky (azimuth %.1f deg)" % az0)

	# Advance 90 seconds (1.5 min): sun should drop downward toward sunset, planet should spin/orbit, station should orbit.
	var state90: Dictionary = LOADER_SCRIPT.evaluate_system_state(sys, 90.0)
	var elev90: float = float(state90.get("surface_solar_elevation_deg", 0.0))
	_expect(elev90 < elev0 - 4.0, "Advancing time drops late-afternoon sun toward sunset (%.2f -> %.2f deg)" % [elev0, elev90])
	_expect(absf(float(state90.get("planet_rotation_angle_deg", 0.0)) - float(state0.get("planet_rotation_angle_deg", 0.0))) > 10.0, "Planet rotation advances over 90 s")
	_expect(absf(float(state90.get("planet_orbital_angle_deg", 0.0)) - float(state0.get("planet_orbital_angle_deg", 0.0))) > 2.0, "Planet orbit angle advances over 90 s")
	_expect(absf(float(state90.get("station_orbital_angle_deg", 0.0)) - float(state0.get("station_orbital_angle_deg", 0.0))) > 20.0, "Station orbit angle advances over 90 s")

	# Advance 260 seconds: sun dips below horizon (nighttime extinction).
	var state_night: Dictionary = LOADER_SCRIPT.evaluate_system_state(sys, 260.0)
	_expect(float(state_night.get("surface_solar_elevation_deg", 0.0)) < -3.0, "Advancing past sunset reaches nighttime below horizon (actual %.2f deg)" % float(state_night.get("surface_solar_elevation_deg", 0.0)))


func _run_clock_continuity_tests() -> void:
	var clock = CLOCK_SCRIPT.new()
	clock.call("reset_clock", 0.0)
	clock.call("advance_realtime", 15.5)
	_expect(absf(float(clock.call("get_time_seconds"))) < 0.001, "SimulationClock.get_time_seconds() preserves discrete jump time invariant")
	_expect(absf(float(clock.call("get_total_celestial_time_seconds")) - 15.5) < 0.001, "SimulationClock.get_total_celestial_time_seconds() includes real-time progress")
	clock.call("advance_time", 420.0)
	_expect(absf(float(clock.call("get_time_seconds")) - 420.0) < 0.001, "Discrete jump advances get_time_seconds() by 420 s")
	_expect(absf(float(clock.call("get_total_celestial_time_seconds")) - 435.5) < 0.001, "Celestial time combines real-time elapsed + jump delta (435.5 s)")
	clock.free()


func _run_dual_scene_integration_tests() -> void:
	# 1. PlanetSurface lighting, StarDisc, late afternoon -> sunset attenuation, and camera-relative Floating Origin immunity.
	var planet_world := PLANET_SCENE.instantiate() as Node3D
	_expect(planet_world != null, "PlanetSurface scene instantiates for solar system test")
	root.add_child(planet_world)
	await process_frame
	await physics_frame

	planet_world.call("set_celestial_time_override", 0.0)
	var sun_light := planet_world.get_node_or_null("Sun") as DirectionalLight3D
	var star_disc_surface := planet_world.get_node_or_null("CelestialSkyRig/StarDisc") as MeshInstance3D
	_expect(sun_light != null, "PlanetSurface Sun DirectionalLight3D exists")
	_expect(star_disc_surface != null and star_disc_surface.visible, "PlanetSurface StarDisc renders in late afternoon")

	if sun_light != null:
		var p_tele0: Dictionary = planet_world.call("get_celestial_telemetry")
		var light_dir0: Vector3 = Vector3(p_tele0.get("surface_sun_light_dir", Vector3.DOWN)).normalized()
		var actual_ray0: Vector3 = (-sun_light.global_basis.z).normalized()
		_expect(actual_ray0.dot(light_dir0) > 0.999, "PlanetSurface Sun DirectionalLight3D shines accurately from the star vector")
		_expect(absf(sun_light.light_energy - 1.0) < 0.01, "PlanetSurface Sun light_energy matches JSON 1.0 1:1 in late afternoon (actual %.3f)" % sun_light.light_energy)

		# Step to nighttime and verify smooth sunset extinction.
		planet_world.call("set_celestial_time_override", 260.0)
		_expect(sun_light.light_energy < 0.01, "PlanetSurface Sun fades to 0 energy once below horizon at night (actual %.3f)" % sun_light.light_energy)

	planet_world.queue_free()
	await process_frame

	# 2. StationLocalSpace KeyLight 1:1 energy, RimFillLight off, StarDisc, and orbiting/rotating planet globe.
	var station_world := STATION_SCENE.instantiate() as Node3D
	_expect(station_world != null, "StationLocalSpace scene instantiates for solar system test")
	root.add_child(station_world)
	await process_frame
	await physics_frame

	station_world.call("set_celestial_time_override", 0.0)
	var key_light := station_world.get_node_or_null("KeyLight") as DirectionalLight3D
	var rim_light := station_world.get_node_or_null("RimFillLight") as DirectionalLight3D
	var star_disc_station := station_world.get_node_or_null("SpaceBackdrop/StarDisc") as MeshInstance3D
	var planet_visual := station_world.get_node_or_null("SpaceBackdrop/OrbitingPlanetVisual") as Node3D
	_expect(key_light != null, "StationLocalSpace KeyLight exists")
	_expect(rim_light == null or rim_light.light_energy <= 0.001, "Artificial RimFillLight is disabled so lighting comes solely from the sun")
	_expect(star_disc_station != null and star_disc_station.visible, "StationLocalSpace StarDisc exists and is visible")
	_expect(planet_visual != null, "StationLocalSpace OrbitingPlanetVisual exists")

	if key_light != null and planet_visual != null:
		var s_tele0: Dictionary = station_world.call("get_celestial_telemetry")
		var st_to_star0: Vector3 = Vector3(s_tele0.get("station_to_star_dir", Vector3.RIGHT)).normalized()
		var key_ray0: Vector3 = (-key_light.global_basis.z).normalized()
		_expect(key_ray0.dot(-st_to_star0) > 0.999, "Station KeyLight rays point directly from the live star vector")
		_expect(absf(key_light.light_energy - 1.0) < 0.001, "Station KeyLight light_energy matches JSON 1.0 1:1")

		var p_pos0: Vector3 = planet_visual.position
		var p_basis0: Basis = planet_visual.basis

		# Advance 180 seconds in station space -> both planet spin basis and orbital position must advance.
		station_world.call("set_celestial_time_override", 180.0)
		var p_pos1: Vector3 = planet_visual.position
		var p_basis1: Basis = planet_visual.basis
		_expect(p_pos0.distance_to(p_pos1) > 200.0, "OrbitingPlanetVisual sweeps along orbit around station (delta %.1f m)" % p_pos0.distance_to(p_pos1))
		_expect((p_basis0.x - p_basis1.x).length() > 0.1, "OrbitingPlanetVisual rotates continuously around its tilted spin axis")

	station_world.queue_free()


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
