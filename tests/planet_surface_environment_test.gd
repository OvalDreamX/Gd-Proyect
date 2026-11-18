extends SceneTree

## Headless SceneTree tests for Phase 3C / 0.4.1a planetary surface environment,
## CockpitCamera 0.05 m near-plane preservation at high altitude, ExternalCamera
## clip-ratio clamping, and floating-origin rebase interpolation snap.
## Run: godot --headless --path . --script res://tests/planet_surface_environment_test.gd

const PLANET_SCENE = preload("res://scenes/planet_surface.tscn")
const ENV_SCRIPT = preload("res://scripts/planet_surface_environment.gd")

const EPSILON: float = 0.05

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_expect_near(float(ENV_SCRIPT.calculate_terrain_height_m(0.0, 0.0)), -0.02, 0.001, "Starport origin remains flat for landing pad")
	_expect(float(ENV_SCRIPT.calculate_terrain_height_m(1100.0, 0.0)) > 20.0, "Outer ring rises into distant ridges")

	var world: Node3D = PLANET_SCENE.instantiate() as Node3D
	_expect(world != null, "PlanetSurface scene instantiates")
	if world == null:
		quit(1)
		return

	root.add_child(world)
	await process_frame
	await physics_frame

	var env_manager: Node = world.get_node_or_null("EnvironmentManager")
	var ref_frame: Node3D = world.get_node_or_null("PlanetaryReferenceFrame") as Node3D
	var pad: StaticBody3D = world.get_node_or_null("StarportPad") as StaticBody3D
	var terrain: StaticBody3D = world.get_node_or_null("PlanetaryTerrain") as StaticBody3D
	var halo: MeshInstance3D = world.get_node_or_null("AtmosphereHalo") as MeshInstance3D
	var ship_spawn: Marker3D = world.get_node_or_null("ShipSpawnPoint") as Marker3D
	var player_spawn: Marker3D = world.get_node_or_null("PlayerSpawnPoint") as Marker3D
	var ship: RigidBody3D = world.get_node_or_null("Ship") as RigidBody3D
	var player: CharacterBody3D = world.get_node_or_null("Player") as CharacterBody3D

	_expect(world.process_physics_priority == -20, "PlanetSurfaceEnvironment schedules process_physics_priority = -20 before physics frames")
	_expect(world.process_priority == 20, "PlanetSurfaceEnvironment schedules process_priority = 20 after ship & camera")
	_expect(env_manager != null, "PlanetSurface includes EnvironmentManager")
	_expect(ref_frame != null, "PlanetSurface includes PlanetaryReferenceFrame")
	_expect(pad != null, "StarportPad StaticBody3D exists")
	_expect(terrain != null and terrain.get_node_or_null("TerrainCollision") != null, "PlanetaryTerrain generates static collision")
	_expect(halo != null and halo.material_override is ShaderMaterial, "AtmosphereHalo analytical limb shader exists")
	_expect(world.get_node_or_null("StarportStructures/ControlTowerBase") != null, "Starport control tower exists")
	_expect(world.get_node_or_null("StarportStructures/CargoHangarBody") != null, "Starport cargo hangar exists")
	_expect(world.get_node_or_null("ApproachBeacons/BeaconMast_0") != null, "Approach beacons exist")
	_expect(ship_spawn != null and player_spawn != null, "Ship and player spawn markers exist")
	_expect(ship != null and player != null, "Ship and Player are instanced in PlanetSurface")

	if env_manager != null:
		_expect(str(env_manager.call("get_environment_id")) == "env_test_planet_surface", "Active environment ID matches test_planet_surface")
		_expect(str(env_manager.call("get_environment_type_name")) == "PLANET_SURFACE", "Active environment type is PLANET_SURFACE")

	for _tick in range(12):
		await physics_frame

	if ship != null:
		_expect(ship.global_position.y > 0.65 and ship.global_position.y < 0.90, "Ship rests stably on StarportPad without falling through")
		_expect(ship.linear_velocity.length() < 0.15, "Ship settles cleanly on StarportPad")
		var atmo: Node = ship.get_node("AtmosphericFlightModel")
		var sensors: Node = ship.get_node("FlightSensorSuite")
		var atmo_data: Dictionary = atmo.call("get_telemetry") as Dictionary
		var sensor_data: Dictionary = sensors.call("get_instrument_snapshot") as Dictionary
		_expect(bool(atmo_data.get("atmosphere_enabled", false)), "PlanetSurface activates atmospheric flight model")
		_expect(float(atmo_data.get("atmosphere_density_kg_m3", 0.0)) > 1.2, "PlanetSurface supplies near-sea-level air density at starport")
		_expect((sensor_data.get("instrument_gravity_world", Vector3.ZERO) as Vector3).length() > 9.5, "PlanetSurface supplies ~9.81 m/s^2 gravity at starport")
		_expect_near(float(sensor_data.get("instrument_altitude_m", 0.0)), 0.755, 0.25, "Sensor altitude reads near 0 m on starport pad")
		var surface_sky_t: float = float(world.call("get_sky_transition_progress"))
		_expect(surface_sky_t < 0.05, "Sky transition begins near surface daylight at starport")

		# Verify external camera disables duplicate physics interpolation on top_level rig.
		var cam_ctrl: ShipCameraController = ship.get_node_or_null("CameraController") as ShipCameraController
		var cockpit_cam: Camera3D = ship.get_node_or_null("CockpitSeat/CockpitCamera") as Camera3D
		var ext_rig: Node3D = ship.get_node_or_null("CameraController/ExternalCameraRig") as Node3D
		var spring_arm: Node3D = ship.get_node_or_null("CameraController/ExternalCameraRig/SpringArm3D") as Node3D
		var ext_cam: Camera3D = ship.get_node_or_null("CameraController/ExternalCameraRig/SpringArm3D/ExternalCamera") as Camera3D
		_expect(ext_rig != null and ext_rig.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "ExternalCameraRig disables duplicate physics interpolation")
		_expect(spring_arm != null and spring_arm.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "SpringArm3D disables duplicate physics interpolation")
		_expect(ext_cam != null and ext_cam.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "ExternalCamera disables duplicate physics interpolation")

		# Verify repeatable reset_to_starport() recovery.
		ship.global_position = Vector3(120.0, 250.0, -300.0)
		ship.linear_velocity = Vector3(30.0, 12.0, -40.0)
		world.call("reset_to_starport")
		_expect(ship.global_position.distance_to(ship_spawn.global_position) < EPSILON, "reset_to_starport restores ship to ShipSpawnPoint")
		_expect(ship.linear_velocity.length() < 0.001, "reset_to_starport clears ship velocity immediately before gravity ticks")
		for _reset_tick in range(12):
			await physics_frame
		_expect(ship.linear_velocity.length() < 0.15, "Ship settles cleanly on StarportPad after reset_to_starport")

		# Verify high-altitude sky/fog transition, CockpitCamera near preservation, and ExternalCamera clip clamping.
		ship.freeze = true
		ship.global_position = Vector3(0.0, 45500.0, 0.0)
		await process_frame
		await process_frame
		var world_env: WorldEnvironment = world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		_expect(float(world.call("get_sky_transition_progress")) > 0.99, "Sky transition completes at atmosphere top")
		_expect(world_env != null and world_env.environment.fog_density < 0.00001, "Atmospheric fog fades to zero in space")
		_expect(halo != null and halo.visible, "AtmosphereHalo becomes visible at high orbital-edge altitude")
		if cockpit_cam != null:
			_expect(cockpit_cam.near <= 0.1, "High-altitude CockpitCamera preserves 0.05 m near clip so cockpit interior never vanishes (near=%.3f)" % cockpit_cam.near)
		if ext_cam != null:
			var clip_ratio: float = ext_cam.far / maxf(ext_cam.near, 0.001)
			_expect(ext_cam.near >= 0.35 and clip_ratio <= 230000.0, "High-altitude ExternalCamera clamps clip ratio against z-fighting (near=%.2f ratio=%.0f)" % [ext_cam.near, clip_ratio])

		# Verify floating-origin rebase snaps ExternalCameraRig without a stale interpolation frame jump.
		ship.global_position = Vector3(4200.0, 22000.0, 0.0)
		world.call("_rebase_world_origin", Vector3(-4200.0, 0.0, 0.0))
		await process_frame
		if cam_ctrl != null and ext_rig != null:
			var expected_rig_pos: Vector3 = ship.global_position + cam_ctrl.camera_focus_offset
			_expect(ext_rig.global_position.distance_to(expected_rig_pos) < 5.0, "Floating-origin rebase keeps ExternalCameraRig snapped onto ship without 0.5s flash")
		if cockpit_cam != null:
			_expect(cockpit_cam.near <= 0.1, "CockpitCamera near plane remains <= 0.1 m after floating-origin rebase")

	print("Planet surface environment tests: %d checks, %d failures." % [_checks, _failures])
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
