extends SceneTree

## Headless pure + integration suite for Patch 0.3.11 (600 km Tatooine Planet,
## 64-bit radial terrain precision, Floating Origin anti-jitter, Post-Jump Reset,
## and GL Compatibility Fresnel AtmosphereHalo Shader).
## Run: godot --headless --path . --script res://tests/simple_planet_loop_test.gd

const PLANET_SCRIPT = preload("res://scripts/planet_surface_environment.gd")
const FRAME_SCRIPT = preload("res://scripts/planetary_reference_frame.gd")
const RESOLVER_SCRIPT = preload("res://scripts/arrival_resolver.gd")
const CLOCK_SCRIPT = preload("res://scripts/simulation_clock.gd")
const COORDINATOR_SCRIPT = preload("res://scripts/transition_coordinator.gd")

const TEST_PLANET_BODY = preload("res://data/celestial/test_planet.tres")
const PLANET_SCENE = preload("res://scenes/planet_surface.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_spherical_heightfield_and_winding()
	await _test_spherical_reference_frame_360()
	await _test_simple_planet_outpost_floating_origin_and_loop()
	print("Simple planet loop tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_spherical_heightfield_and_winding() -> void:
	_expect(absf(PLANET_SCRIPT.get_planet_radius_m() - 600000.0) < 0.1, "PlanetSurfaceEnvironment configures R = 600,000 m Tatooine globe")
	var h_pole: float = PLANET_SCRIPT.calculate_spherical_height_m(Vector3.UP)
	_expect(absf(h_pole - (-0.02)) < 0.05, "North Pole spherical height matches Starport flat pad (-0.02 m, actual %.4f)" % h_pole)

	var outpost_dir: Vector3 = PLANET_SCRIPT.get_outpost_direction()
	var h_outpost: float = PLANET_SCRIPT.calculate_spherical_height_m(outpost_dir)
	_expect(absf(h_outpost - 80.0) < 0.5, "Horizon Outpost sits on its 80 m leveled survey plateau (actual %.3f)" % h_outpost)

	var directions: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, -1.0, 0.0),
		Vector3(1.0, 1.0, 1.0).normalized(),
		Vector3(-1.0, 1.0, -1.0).normalized(),
		Vector3(1.0, -1.0, -1.0).normalized(),
		Vector3(-1.0, -1.0, 1.0).normalized(),
	]
	var all_finite: bool = true
	for dir in directions:
		var h: float = PLANET_SCRIPT.calculate_spherical_height_m(dir)
		if is_nan(h) or is_inf(h) or h < -50.0 or h > 2000.0:
			all_finite = false
	_expect(all_finite, "3D spherical heightfield evaluates bounded finite terrain across all 6 faces and cube corners")

	var faces_def: Array[Dictionary] = PLANET_SCRIPT.get_cube_face_definitions()
	_expect(faces_def.size() == 6, "Cube-sphere defines exactly 6 cube faces")
	var winding_ok: bool = true
	for face in faces_def:
		var n: Vector3 = face["normal"]
		var u_ax: Vector3 = face["u"]
		var v_ax: Vector3 = face["v"]
		if v_ax.cross(u_ax).dot(n) < 0.999:
			winding_ok = false
	_expect(winding_ok, "All 6 cube faces satisfy outward cross-product winding (v x u == normal)")


func _test_spherical_reference_frame_360() -> void:
	var planet_center := Vector3(0.0, -600000.0, 0.0)
	var g_surf: float = FRAME_SCRIPT.calculate_spherical_gravity_magnitude(9.81, 600000.0, 600000.0)
	_expect(absf(g_surf - 9.81) < 0.05, "Spherical surface gravity equals ~9.81 m/s^2 at North Pole (actual %.3f)" % g_surf)

	var g_alt: float = FRAME_SCRIPT.calculate_spherical_gravity_magnitude(9.81, 600000.0, 600000.0 + 45000.0)
	var g_body_alt: float = float(TEST_PLANET_BODY.call("calculate_gravity_magnitude_at_altitude", 45000.0))
	_expect(g_alt > 8.3 and g_alt < 8.7 and absf(g_alt - g_body_alt) < 0.001, "Inverse-square gravity evaluates to ~8.49 m/s^2 at 45 km jump altitude on 600 km planet (actual %.3f)" % g_alt)

	var ref_frame := FRAME_SCRIPT.new()
	ref_frame.surface_geometry = FRAME_SCRIPT.SurfaceGeometry.SPHERICAL
	ref_frame.surface_radius_m = 600000.0
	ref_frame.surface_gravity_mps2 = 9.81
	ref_frame.north_reference_local = Vector3(0.0, 0.0, -1.0)
	ref_frame.position = planet_center
	get_root().add_child(ref_frame)
	await process_frame

	var sample_dirs: Array[Vector3] = [
		Vector3.UP,
		Vector3.RIGHT,
		Vector3.LEFT,
		Vector3.BACK,
		Vector3.FORWARD,
		Vector3.DOWN,
		PLANET_SCRIPT.get_outpost_direction(),
	]
	var ortho_ok: bool = true
	for dir in sample_dirs:
		var world_pt: Vector3 = planet_center + dir * 600050.0
		var frame: Dictionary = ref_frame.get_local_frame(world_pt)
		var up_v: Vector3 = frame["up_world"]
		var north_v: Vector3 = frame["north_world"]
		var east_v: Vector3 = frame["east_world"]
		if up_v.dot(dir) < 0.999:
			ortho_ok = false
		if absf(up_v.dot(north_v)) > 0.001 or absf(up_v.dot(east_v)) > 0.001 or absf(north_v.dot(east_v)) > 0.001:
			ortho_ok = false
		var grav_v: Vector3 = ref_frame.get_gravity_vector_world(world_pt)
		if grav_v.normalized().dot(-dir) < 0.999:
			ortho_ok = false
	_expect(ortho_ok, "PlanetaryReferenceFrame produces orthogonal radial (up, north, east) and center-pointing gravity around 360°")

	ref_frame.queue_free()
	await process_frame


func _test_simple_planet_outpost_floating_origin_and_loop() -> void:
	var sim_clock := get_root().get_node_or_null("SimulationClock")
	if sim_clock == null:
		sim_clock = CLOCK_SCRIPT.new()
		sim_clock.name = "SimulationClock"
		get_root().add_child(sim_clock)
	sim_clock.call("reset_clock", 0.0)

	var coordinator := get_root().get_node_or_null("TransitionCoordinator")
	if coordinator == null:
		coordinator = COORDINATOR_SCRIPT.new()
		coordinator.name = "TransitionCoordinator"
		get_root().add_child(coordinator)
	await process_frame

	var planet := PLANET_SCENE.instantiate() as Node3D
	_expect(planet != null, "PlanetSurface scene instantiates cleanly")
	get_root().add_child(planet)
	await process_frame
	await physics_frame

	var terrain_body := planet.get_node_or_null("PlanetaryTerrain") as StaticBody3D
	var sphere_mesh_node := terrain_body.get_node_or_null("SphereTerrainMesh") as MeshInstance3D if terrain_body else null
	var sphere_col_node := terrain_body.get_node_or_null("SphereTerrainCollision") as CollisionShape3D if terrain_body else null
	_expect(sphere_mesh_node != null and sphere_col_node != null, "Closed SphereTerrainMesh and SphereTerrainCollision exist on PlanetaryTerrain")
	if sphere_mesh_node != null and sphere_mesh_node.mesh != null:
		var arrays: Array = sphere_mesh_node.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var center: Vector3 = planet.call("get_planet_center")
		var outward_ok: bool = not verts.is_empty() and verts.size() == norms.size()
		for i in range(0, verts.size(), 97):
			var radial: Vector3 = (verts[i] - center).normalized()
			if norms[i].dot(radial) <= 0.1:
				outward_ok = false
				break
		_expect(outward_ok, "Generated 600 km cube-sphere vertex normals consistently face radially outward")

	var outpost := planet.get_node_or_null("HorizonOutpost") as Node3D
	var outpost_pad := outpost.get_node_or_null("OutpostPad") as StaticBody3D if outpost else null
	_expect(outpost != null and outpost_pad != null, "HorizonOutpost and OutpostPad collision exist on the planet")
	if outpost != null:
		var expected_dir: Vector3 = PLANET_SCRIPT.get_outpost_direction()
		_expect(outpost.global_basis.y.normalized().dot(expected_dir) > 0.999, "HorizonOutpost Y-up aligns cleanly with local spherical normal")

	var ship := planet.get_node_or_null("Ship") as RigidBody3D
	var nav_outpost: Dictionary = planet.call("get_surface_navigation_telemetry", ship.global_position, ship.global_basis)
	var dist_km: float = float(nav_outpost.get("nav_surface_distance_m", 0.0)) / 1000.0
	var brg_deg: float = float(nav_outpost.get("nav_target_bearing_deg", -1.0))
	_expect(str(nav_outpost.get("nav_target_name", "")) == "HORIZON OUTPOST", "Default surface nav target is HORIZON OUTPOST")
	_expect(dist_km > 38.0 and dist_km < 42.0, "Great-circle distance to Horizon Outpost reads ~39.9 km on 600 km planet (actual %.2f km)" % dist_km)
	_expect(brg_deg >= 0.0 and brg_deg <= 360.0, "Surface nav target bearing is a valid compass angle (%.1f deg)" % brg_deg)

	planet.call("cycle_surface_waypoint")
	var nav_starport: Dictionary = planet.call("get_surface_navigation_telemetry", ship.global_position, ship.global_basis)
	_expect(str(nav_starport.get("nav_target_name", "")) == "STARPORT ALPHA", "cycle_surface_waypoint() toggles surface target to STARPORT ALPHA")

	var halo := planet.get_node_or_null("AtmosphereHalo") as MeshInstance3D
	_expect(halo != null and not halo.visible, "AtmosphereHalo is hidden while resting on Starport Alpha")

	var outpost_surf: Vector3 = PLANET_SCRIPT.get_spherical_surface_point(PLANET_SCRIPT.get_outpost_direction())
	var planet_center: Vector3 = PLANET_SCRIPT.get_planet_center()
	var outpost_unit: Vector3 = (outpost_surf - planet_center).normalized()
	var underground_pt: Vector3 = outpost_surf - outpost_unit * 10.0
	var resolved_offpole: Dictionary = RESOLVER_SCRIPT.resolve_arrival_transform(planet, {"arrival_transform": Transform3D(Basis.IDENTITY, underground_pt)})
	var safe_origin: Vector3 = Transform3D(resolved_offpole.get("transform", Transform3D.IDENTITY)).origin
	var safe_clearance: float = (safe_origin - planet_center).length() - (outpost_surf - planet_center).length()
	_expect(bool(resolved_offpole.get("adjusted", false)) and safe_clearance >= 24.9, "ArrivalResolver radially lifts off-pole underground arrivals >= +25 m above local terrain")

	var controller := ship.get_node_or_null("FlightController")
	var cargo := ship.get_node_or_null("CargoSystem")
	planet.call("seat_pilot_immediately")
	cargo.call("load_preset", "MAX_GROSS")
	controller.set("_field_state", 2)
	controller.set("_field_power_command", 0.78)
	controller.set("_field_power_output", 0.72)
	controller.set("_vector_distribution_degrees", 15.0)
	controller.set("_vector_distribution_actual_degrees", 18.0)
	controller.set("_pitch_command", 0.35)
	controller.set("_roll_command", -0.25)
	controller.set("_yaw_command", 0.40)
	ship.freeze = false
	ship.global_position = Vector3(0.0, 45200.0, 0.0)
	ship.linear_velocity = Vector3(0.0, 120.0, 0.0)
	await physics_frame
	await physics_frame

	var out_res: Dictionary = await coordinator.call("request_jump", ship, null, planet)
	_expect(bool(out_res.get("valid", false)), "Outbound jump Planet -> Station succeeds from 600 km planet 45.2 km envelope")
	var station_world := out_res.get("destination_scene") as Node3D
	await process_frame
	await physics_frame

	var station_ship := station_world.get_node_or_null("Ship") as RigidBody3D
	var station_ctrl := station_ship.get_node_or_null("FlightController") if station_ship else null
	_expect(station_ship != null and absf(station_ship.mass - 55000.0) < 1.0, "Station arrival preserves MAX_GROSS 55,000 kg mass")
	_expect(_are_controls_reset(station_ctrl), "Flight controls reset to neutral on Station arrival (0% power, 90° vector, 0 P/R/Y)")
	_expect(absf(float(sim_clock.call("get_time_seconds")) - 420.0) < 0.01, "SimulationClock stands at 420 s after outbound jump")

	station_ctrl.set("_field_power_command", 0.55)
	station_ctrl.set("_field_power_output", 0.55)
	station_ctrl.set("_vector_distribution_degrees", 10.0)
	station_ctrl.set("_pitch_command", -0.4)
	var ret_res: Dictionary = await coordinator.call("request_jump", station_ship, null, station_world)
	_expect(bool(ret_res.get("valid", false)), "Return jump Station -> Simple Planet succeeds")
	var returned_planet := ret_res.get("destination_scene") as Node3D
	await process_frame
	await physics_frame

	var ret_ship := returned_planet.get_node_or_null("Ship") as RigidBody3D
	var ret_ctrl := ret_ship.get_node_or_null("FlightController") if ret_ship else null
	var ret_halo := returned_planet.get_node_or_null("AtmosphereHalo") as MeshInstance3D
	var ret_cockpit_cam := ret_ship.find_child("CockpitCamera", true, false) as Camera3D if ret_ship else null
	_expect(_are_controls_reset(ret_ctrl), "Flight controls reset to neutral on Planet return arrival (0% power, 90° vector, 0 P/R/Y)")
	_expect(ret_halo != null and ret_halo.visible, "AtmosphereHalo limb glow is visible upon upper-atmosphere return at 46,500 m")
	var halo_mat := ret_halo.material_override as ShaderMaterial if ret_halo else null
	var halo_alpha_val: float = float(halo_mat.get_shader_parameter("halo_alpha")) if halo_mat != null else 0.0
	_expect(halo_mat != null and halo_alpha_val > 0.05, "AtmosphereHalo shader halo_alpha exceeds 0.05 in upper orbit (actual %.3f)" % halo_alpha_val)
	_expect(ret_cockpit_cam != null and ret_cockpit_cam.far >= 120000.0, "CockpitCamera.far dynamically scales >= 120,000 m at 46.5 km orbital view")
	_expect(int(sim_clock.call("get_jump_count")) == 2 and absf(float(sim_clock.call("get_time_seconds")) - 840.0) < 0.01, "SimulationClock records 2 jumps (840 s) after full round trip")

	await create_timer(0.32).timeout
	await process_frame
	var rebased_scene_dist: float = ret_ship.global_position.length()
	var logical_pos: Vector3 = returned_planet.call("get_logical_planet_position", ret_ship.global_position)
	var logical_alt_m: float = (logical_pos - PLANET_SCRIPT.get_planet_center()).length() - PLANET_SCRIPT.get_planet_radius_m()
	_expect(rebased_scene_dist < 50.0, "Floating Origin rebases Ship back near world (0,0,0) at 46.5 km altitude (actual %.2f m)" % rebased_scene_dist)
	_expect(logical_alt_m > 44000.0 and logical_alt_m < 48000.0, "Floating Origin preserves exact logical planetary altitude after rebase (actual %.0f m)" % logical_alt_m)
	_expect(ret_halo.visible, "AtmosphereHalo remains visible after Floating Origin rebase")

	returned_planet.call("reset_to_starport")
	await physics_frame
	await physics_frame
	var restored_offset := Vector3(returned_planet.call("get_world_origin_offset"))
	_expect(restored_offset.length() < 0.01, "reset_to_starport() resets Floating Origin offset back to ZERO")
	_expect(ret_ship.global_position.length() < 5.0 and not ret_halo.visible, "reset_to_starport() returns ship cleanly to Starport Alpha pad and hides AtmosphereHalo")

	returned_planet.queue_free()
	await process_frame


func _are_controls_reset(ctrl: Node) -> bool:
	if ctrl == null:
		return false
	return (
		int(ctrl.get("_field_state")) == 2
		and is_zero_approx(float(ctrl.get("_field_power_command")))
		and is_zero_approx(float(ctrl.get("_field_power_output")))
		and absf(float(ctrl.get("_vector_distribution_degrees")) - 90.0) < 0.01
		and absf(float(ctrl.get("_vector_distribution_actual_degrees")) - 90.0) < 0.01
		and is_zero_approx(float(ctrl.get("_pitch_command")))
		and is_zero_approx(float(ctrl.get("_roll_command")))
		and is_zero_approx(float(ctrl.get("_yaw_command")))
	)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
