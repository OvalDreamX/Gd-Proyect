extends SceneTree

## Headless pure + integration tests for Phase 3J / 0.4.1a FCC Space Mode,
## AOA-bounded vector following, retrograde braking, V-key direct drift toggle,
## F7C unified actuator allocator routing, Star Wars low-orbit Tatooine scale,
## external camera interpolation safety, and space 1.0x vacuum radiator telemetry.
## Run: godot --headless --path . --script res://tests/fcc_space_mode_test.gd

const FCC_SCRIPT = preload("res://scripts/flight_control_computer.gd")
const STATION_SCENE = preload("res://scenes/station_local_space.tscn")
const HUD_OVERLAY_SCRIPT = preload("res://scripts/flight_hud_overlay.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_run_pure_space_assist_tests()
	await _run_station_integration_tests()
	print("FCC space mode tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_pure_space_assist_tests() -> void:
	var fcc: FlightControlComputer = FCC_SCRIPT.new() as FlightControlComputer
	var basis_id: Basis = Basis.IDENTITY

	# 1. Atmospheric fallback when space_mode_active = false.
	var atmo_cmd: Dictionary = fcc.calculate_space_assist_command(
		Vector3(0.0, 0.0, -30.0), basis_id, 30000.0, 55000.0, 9.81, 1.8,
		false, 0.5, true, false, true
	)
	_expect(str(atmo_cmd.get("fcc_mode_label", "")) == "ATMO RATE ASSIST", "Space assist stays inactive outside LOCAL_SPACE")
	_expect((atmo_cmd.get("fcc_space_assist_force_world", Vector3.ONE) as Vector3).length() < 0.001, "No space assist force generated when space_mode_active is false")

	# 2. Pre-throttle standby invariant in LOCAL_SPACE.
	var standby_cmd: Dictionary = fcc.calculate_space_assist_command(
		Vector3(0.0, 0.0, -25.0), basis_id, 30000.0, 55000.0, 9.81, 1.8,
		true, 0.0, false, false, true
	)
	_expect(str(standby_cmd.get("fcc_mode_label", "")) == "SPACE STANDBY", "0% untouched throttle in space enters SPACE STANDBY")
	_expect(not bool(standby_cmd.get("fcc_space_mode_engaged", true)), "Pre-throttle standby keeps engaged flag false for arrival drift")
	_expect((standby_cmd.get("fcc_space_assist_force_world", Vector3.ONE) as Vector3).length() < 0.001, "Standby generates zero assist force so arrival drift coasts cleanly")

	# 3. Forward acceleration toward target speed (50% -> 60 m/s).
	var accel_cmd: Dictionary = fcc.calculate_space_assist_command(
		Vector3.ZERO, basis_id, 30000.0, 55000.0, 9.81, 1.8,
		true, 0.5, true, false, true
	)
	var accel_force: Vector3 = accel_cmd.get("fcc_space_assist_force_world", Vector3.ZERO) as Vector3
	_expect(str(accel_cmd.get("fcc_mode_label", "")) == "SPACE VECTOR", "Engaged throttle enters SPACE VECTOR mode")
	_expect(absf(float(accel_cmd.get("fcc_space_target_speed_mps", 0.0)) - 60.0) < 0.1, "50% space throttle maps to 60.0 m/s setpoint")
	_expect(accel_force.z < -100000.0 and absf(accel_force.x) < 1.0, "Zero-velocity acceleration drives straight along ship forward (-Z)")

	# 4. AOA-bounded lateral velocity damping when nose turns 30 deg left away from velocity vector.
	var yaw_left_basis: Basis = Basis(Vector3.UP, deg_to_rad(30.0))
	var turn_cmd: Dictionary = fcc.calculate_space_assist_command(
		Vector3(0.0, 0.0, -60.0), yaw_left_basis, 30000.0, 55000.0, 9.81, 1.8,
		true, 0.5, true, false, true
	)
	var turn_force: Vector3 = turn_cmd.get("fcc_space_assist_force_world", Vector3.ZERO) as Vector3
	var fwd_turned: Vector3 = (-yaw_left_basis.z).normalized()
	var v_world: Vector3 = Vector3(0.0, 0.0, -60.0)
	var v_perp: Vector3 = v_world - fwd_turned * v_world.dot(fwd_turned)
	_expect(float(turn_cmd.get("fcc_space_slip_angle_deg", 0.0)) > 25.0, "Turned nose detects ~30 deg slip angle")
	_expect(turn_force.dot(v_perp) < -50000.0, "Space assist actively damps perpendicular velocity slip onto turned heading")
	_expect(turn_force.dot(fwd_turned) > 10000.0, "Space assist restores forward speed deficit along new heading")

	# 5. Retrograde braking opposes arbitrary 3D inertial velocity cleanly.
	var brake_vel: Vector3 = Vector3(18.0, -6.0, -45.0)
	var brake_cmd: Dictionary = fcc.calculate_space_assist_command(
		brake_vel, basis_id, 30000.0, 55000.0, 9.81, 1.8,
		true, 0.5, true, true, true
	)
	var brake_force: Vector3 = brake_cmd.get("fcc_space_assist_force_world", Vector3.ZERO) as Vector3
	_expect(str(brake_cmd.get("fcc_mode_label", "")) == "SPACE BRAKE" and bool(brake_cmd.get("fcc_space_brake_active", false)), "Brake request switches mode to SPACE BRAKE")
	_expect(brake_force.normalized().dot(-brake_vel.normalized()) > 0.90, "SPACE BRAKE pushes directly opposite inertial velocity vector")

	# 6. Direct mode bypasses assist.
	fcc.set_assistance_enabled(false)
	var direct_cmd: Dictionary = fcc.calculate_space_assist_command(
		brake_vel, basis_id, 30000.0, 55000.0, 9.81, 1.8,
		true, 0.5, true, false, true
	)
	_expect(str(direct_cmd.get("fcc_mode_label", "")) == "SPACE DRIFT // DIRECT", "V-key disable reports SPACE DRIFT // DIRECT")
	_expect((direct_cmd.get("fcc_space_assist_force_world", Vector3.ONE) as Vector3).length() < 0.001, "Direct mode produces zero FCC space assist force")

	fcc.free()


func _run_station_integration_tests() -> void:
	var station: Node3D = STATION_SCENE.instantiate() as Node3D
	_expect(station != null, "StationLocalSpace instantiates for FCC Space Mode test")
	if station == null:
		return
	root.add_child(station)
	await process_frame
	await physics_frame
	await physics_frame

	# Verify Star Wars orbital Tatooine smooth shader mesh & rim framing.
	var planet_visual: Node3D = station.get_node_or_null("SpaceBackdrop/OrbitingPlanetVisual") as Node3D
	var globe_mesh: MeshInstance3D = station.get_node_or_null("SpaceBackdrop/OrbitingPlanetVisual/PlanetGlobeMesh") as MeshInstance3D
	var rim_mesh: MeshInstance3D = station.get_node_or_null("SpaceBackdrop/OrbitingPlanetVisual/PlanetAtmosphereRim") as MeshInstance3D
	var planet_scale_m: float = planet_visual.basis.get_scale().x if planet_visual != null else 0.0
	_expect(station.process_priority == 20, "StationLocalSpaceEnvironment sets process_priority = 20")
	_expect(planet_visual != null and planet_scale_m > 5000.0, "OrbitingPlanetVisual renders full low-orbit Tatooine scale (scale %.0f m)" % planet_scale_m)
	_expect(globe_mesh != null and globe_mesh.material_override is ShaderMaterial, "PlanetGlobeMesh uses GL Compatibility ShaderMaterial")
	_expect(rim_mesh != null and rim_mesh.material_override is ShaderMaterial and (rim_mesh.material_override as ShaderMaterial).render_priority >= 1, "PlanetAtmosphereRim uses additive Fresnel ShaderMaterial with render_priority >= 1")

	var ship: RigidBody3D = station.get_node_or_null("Ship") as RigidBody3D
	var rep: RepulsorliftSystem = ship.get_node_or_null("RepulsorliftSystem") as RepulsorliftSystem if ship != null else null
	var ctrl: Node = ship.get_node_or_null("FlightController") if ship != null else null
	var fcc: FlightControlComputer = ship.get_node_or_null("FlightControlComputer") as FlightControlComputer if ship != null else null
	var hud: Node = ctrl.get("_hud") as Node if ctrl != null else null
	var overlay: Control = hud.get("_flight_display") as Control if hud != null else null
	_expect(ship != null and rep != null and ctrl != null and fcc != null and overlay != null, "Station ship, RepulsorliftSystem, FCC, controller, and HUD overlay exist")

	var ext_rig: Node3D = ship.get_node_or_null("CameraController/ExternalCameraRig") as Node3D if ship != null else null
	_expect(ext_rig != null and ext_rig.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Station ship external camera rig disables duplicate physics interpolation")

	if ship == null or rep == null or ctrl == null or fcc == null or overlay == null:
		station.queue_free()
		await process_frame
		return

	# Turn field ONLINE and verify pre-throttle coasting remains pure inertial drift.
	ctrl.set("_field_state", 2)
	ctrl.set("_require_neutral_controls", false)
	ship.linear_velocity = Vector3(0.0, 0.0, -25.0)
	for _i in range(10):
		await physics_frame
	ctrl.call("_publish_telemetry")
	var standby_tele: Dictionary = overlay.get("_telemetry") as Dictionary
	_expect(str(standby_tele.get("fcc_mode_label", "")) == "SPACE STANDBY", "Station HUD reports SPACE STANDBY before throttle input")
	_expect(absf(ship.linear_velocity.z - (-25.0)) < 0.05, "Pre-throttle arrival drift stays untouched in StationLocalSpace")

	# Engage 50% space speed setpoint (60 m/s) -> accelerates smoothly along -Z (allowing -10C cold-start vane warmup ticks).
	ship.linear_velocity = Vector3.ZERO
	ctrl.set("_space_throttle_engaged", true)
	ctrl.set("_field_power_command", 0.5)
	ctrl.set("_field_power_output", 0.5)
	for _i in range(105):
		await physics_frame
	var fwd_speed: float = -ship.linear_velocity.z
	_expect(fwd_speed > 25.0 and fwd_speed <= 65.0, "Station space throttle accelerates ship cleanly toward 60 m/s setpoint (actual %.1f m/s)" % fwd_speed)
	var vec_tele: Dictionary = rep.get_telemetry()
	var vec_alloc: Dictionary = vec_tele.get("main_vector_allocator", {}) as Dictionary
	_expect(bool(vec_alloc.get("unified", false)) and int(vec_tele.get("main_vector_allocator_active_actuators", 0)) >= 1, "SPACE VECTOR routes thrust through the F7C unified actuator allocator")
	_expect(not (vec_tele.get("lift_vane_contributions", []) as Array).is_empty(), "SPACE VECTOR records real physical vane contributions (main_rear)")
	_expect(absf(float(vec_tele.get("radiator_convective_factor", 0.0)) - 1.0) < 0.0001, "LOCAL_SPACE radiator convective factor stays at exact 1.0x vacuum")
	_expect(str(HUD_OVERLAY_SCRIPT.format_radiator_status_label(float(vec_tele.get("radiator_convective_factor", 1.0)), -10.0)).begins_with("RAD VAC"), "Space HUD radiator label shows RAD VAC")

	# Rotate nose 25 deg left and verify AOA-bounded lateral velocity alignment onto new heading.
	ship.global_basis = Basis(Vector3.UP, deg_to_rad(25.0))
	ship.angular_velocity = Vector3.ZERO
	for _i in range(40):
		await physics_frame
	var turned_fwd: Vector3 = (-ship.global_basis.z).normalized()
	var vel_dir: Vector3 = ship.linear_velocity.normalized()
	_expect(vel_dir.dot(turned_fwd) > 0.96, "Turning nose aligns inertial velocity vector smoothly onto new heading (cos=%.3f)" % vel_dir.dot(turned_fwd))

	# Engage Space Brake -> kills speed substantially toward zero.
	var pre_brake_speed: float = ship.linear_velocity.length()
	ctrl.set("_space_brake_pressed", true)
	for _i in range(80):
		await physics_frame
	var post_brake_speed: float = ship.linear_velocity.length()
	_expect(post_brake_speed < pre_brake_speed * 0.45, "Space Brake arrests inertial velocity smoothly (%.1f -> %.1f m/s)" % [pre_brake_speed, post_brake_speed])
	var brk_tele: Dictionary = rep.get_telemetry()
	var brk_alloc: Dictionary = brk_tele.get("main_vector_allocator", {}) as Dictionary
	_expect(bool(brk_alloc.get("unified", false)), "SPACE BRAKE routes braking thrust through the F7C unified actuator allocator")

	# Verify F3 diagnostics displays Phase 3J Space Mode telemetry.
	ctrl.set("_space_brake_pressed", false)
	ctrl.call("_publish_telemetry")
	var dbg_tele: Dictionary = (overlay.get("_telemetry") as Dictionary).duplicate(true)
	dbg_tele["debug_overview_enabled"] = true
	hud.call("update_telemetry", dbg_tele)
	var dbg_edit: TextEdit = hud.get("_debug_text_label") as TextEdit
	var dbg_text: String = dbg_edit.text if dbg_edit != null else ""
	_expect(dbg_text.contains("[ FCC SPACE MODE (PHASE 3J) ]"), "F3 diagnostics renders FCC Space Mode telemetry section")

	station.queue_free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
