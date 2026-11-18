extends SceneTree

## Pure + integration tests for Phase 3D Departure Envelope & Ascent Pacing.
## Run: godot --headless --path . --script res://tests/jump_envelope_evaluator_test.gd

const EVALUATOR_SCRIPT = preload("res://scripts/jump_envelope_evaluator.gd")
const PLANET_SCENE = preload("res://scenes/planet_surface.tscn")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_run_pure_evaluator_tests()
	await _run_scene_integration_tests()
	print("Jump envelope evaluator tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _run_pure_evaluator_tests() -> void:
	var base_ctx := {
		"environment_id": "env_test_planet_surface",
		"environment_type": "PLANET_SURFACE",
		"environment_label": "Test Planet Surface",
		"jump_allowed": true,
		"min_altitude_m": 45000.0,
		"exclusion_radius_m": 0.0,
		"max_speed_mps": 0.0,
		"require_systems_online": true,
		"disallow_contact": true,
		"altitude_m": 46000.0,
		"altitude_valid": true,
		"radial_distance_m": 46000.0,
		"speed_mps": 180.0,
		"velocity_valid": true,
		"field_state": "ONLINE",
		"in_contact": false,
	}

	var ready_res: Dictionary = EVALUATOR_SCRIPT.evaluate(base_ctx)
	_expect(bool(ready_res["jump_eligible"]), "Evaluator grants JUMP READY inside planetary envelope")
	_expect(str(ready_res["jump_reason_code"]) == "READY", "Ready code matches READY")
	_expect(str(ready_res["jump_reason_text"]) == "JUMP READY", "Ready label matches JUMP READY")

	var disallowed_ctx: Dictionary = base_ctx.duplicate()
	disallowed_ctx["jump_allowed"] = false
	var disallowed_res: Dictionary = EVALUATOR_SCRIPT.evaluate(disallowed_ctx)
	_expect(not bool(disallowed_res["jump_eligible"]) and str(disallowed_res["jump_reason_code"]) == "ENV_DISALLOWED", "Disallowed environment rejects jump")

	var off_ctx: Dictionary = base_ctx.duplicate()
	off_ctx["field_state"] = "OFF"
	var off_res: Dictionary = EVALUATOR_SCRIPT.evaluate(off_ctx)
	_expect(not bool(off_res["jump_eligible"]) and str(off_res["jump_reason_code"]) == "SYSTEMS_OFFLINE", "Field OFF rejects jump with SYSTEMS_OFFLINE")
	_expect(str(off_res["jump_reason_text"]).contains("PRESS F"), "Field OFF tells pilot to press F")

	var contact_ctx: Dictionary = base_ctx.duplicate()
	contact_ctx["in_contact"] = true
	var contact_res: Dictionary = EVALUATOR_SCRIPT.evaluate(contact_ctx)
	_expect(not bool(contact_res["jump_eligible"]) and str(contact_res["jump_reason_code"]) == "SHIP_IN_CONTACT", "Landed/contact state rejects jump")

	var low_alt_ctx: Dictionary = base_ctx.duplicate()
	low_alt_ctx["altitude_m"] = 22500.0
	var low_alt_res: Dictionary = EVALUATOR_SCRIPT.evaluate(low_alt_ctx)
	_expect(not bool(low_alt_res["jump_eligible"]) and str(low_alt_res["jump_reason_code"]) == "BELOW_MIN_ALTITUDE", "Below 45,000 m rejects jump")
	_expect(absf(float(low_alt_res["jump_altitude_progress"]) - 0.5) < 0.01, "Altitude progress reports 0.5 at 22,500 / 45,000 m")

	var bad_alt_ctx: Dictionary = base_ctx.duplicate()
	bad_alt_ctx["altitude_valid"] = false
	var bad_alt_res: Dictionary = EVALUATOR_SCRIPT.evaluate(bad_alt_ctx)
	_expect(not bool(bad_alt_res["jump_eligible"]) and str(bad_alt_res["jump_reason_code"]) == "SENSOR_ALTITUDE_INVALID", "Invalid altitude sensor blocks surface jump")

	var space_excl_ctx: Dictionary = base_ctx.duplicate()
	space_excl_ctx["environment_type"] = "LOCAL_SPACE"
	space_excl_ctx["min_altitude_m"] = 0.0
	space_excl_ctx["exclusion_radius_m"] = 250.0
	space_excl_ctx["radial_distance_m"] = 120.0
	var excl_res: Dictionary = EVALUATOR_SCRIPT.evaluate(space_excl_ctx)
	_expect(not bool(excl_res["jump_eligible"]) and str(excl_res["jump_reason_code"]) == "INSIDE_EXCLUSION_ZONE", "Local space rejects inside exclusion radius")

	space_excl_ctx["radial_distance_m"] = 300.0
	var space_ready_res: Dictionary = EVALUATOR_SCRIPT.evaluate(space_excl_ctx)
	_expect(bool(space_ready_res["jump_eligible"]), "Local space allows jump outside exclusion radius")

	var speed_ctx: Dictionary = base_ctx.duplicate()
	speed_ctx["max_speed_mps"] = 350.0
	speed_ctx["speed_mps"] = 380.0
	var speed_res: Dictionary = EVALUATOR_SCRIPT.evaluate(speed_ctx)
	_expect(not bool(speed_res["jump_eligible"]) and str(speed_res["jump_reason_code"]) == "SPEED_ABOVE_LIMIT", "Optional speed cap rejects excessive jump speed")

func _run_scene_integration_tests() -> void:
	var world := PLANET_SCENE.instantiate() as Node3D
	_expect(world != null, "PlanetSurface instantiates for jump envelope integration test")
	if world == null:
		return
	root.add_child(world)
	await process_frame
	await physics_frame

	var ship := world.get_node_or_null("Ship") as RigidBody3D
	var player := world.get_node_or_null("Player") as CharacterBody3D
	var env_manager := world.get_node_or_null("EnvironmentManager")
	var sensors := ship.get_node_or_null("FlightSensorSuite") if ship != null else null
	var cargo := ship.get_node_or_null("CargoSystem") if ship != null else null
	var controller := ship.get_node_or_null("FlightController") if ship != null else null
	var repulsor := ship.get_node_or_null("RepulsorliftSystem") if ship != null else null

	_expect(ship != null and player != null and env_manager != null and sensors != null and cargo != null and controller != null and repulsor != null, "Ship and PlanetSurface subsystems exist")
	if ship == null or player == null or env_manager == null or sensors == null or cargo == null or controller == null or repulsor == null:
		world.queue_free()
		return

	# Seat the player immediately in cockpit mode so ShipFlightController preserves ONLINE field across frames.
	_seat_player_immediately_for_test(ship, player)
	await physics_frame
	_expect(bool(ship.call("is_pilot_ready")), "Pilot is seated and ready for envelope integration tests")

	for _tick in range(10):
		await physics_frame

	# 1. On pad with field OFF -> SYSTEMS_OFFLINE.
	controller.call("_publish_telemetry")
	var hud = controller.get("_hud")
	var overlay = hud.get("_flight_display") if hud != null else null
	_expect(overlay != null, "FlightHUD overlay is constructed on controller")
	if overlay != null:
		var pad_off_tele: Dictionary = overlay.get("_telemetry")
		_expect(not bool(pad_off_tele.get("jump_eligible", true)), "Ship on pad with field OFF cannot jump")
		_expect(str(pad_off_tele.get("jump_reason_code", "")) == "SYSTEMS_OFFLINE", "Pad telemetry reports SYSTEMS_OFFLINE when field OFF")

	# 2. On pad with field ONLINE -> SHIP_IN_CONTACT.
	controller.set("_field_state", 2) # FieldState.ONLINE
	controller.call("_publish_telemetry")
	if overlay != null:
		var pad_on_tele: Dictionary = overlay.get("_telemetry")
		_expect(not bool(pad_on_tele.get("jump_eligible", true)), "Ship resting on StarportPad with field ONLINE still cannot jump")
		_expect(str(pad_on_tele.get("jump_reason_code", "")) == "SHIP_IN_CONTACT", "Pad telemetry reports SHIP_IN_CONTACT while resting on pad")

	# 3. Verify climb capability (TWR > 1.0) and envelope checks across EMPTY, HALF_CENTERED, and MAX_GROSS.
	for preset_name in ["EMPTY", "HALF_CENTERED", "MAX_GROSS"]:
		cargo.call("load_preset", preset_name)
		await physics_frame
		var rep_tele: Dictionary = repulsor.call("get_telemetry")
		_expect(float(rep_tele.get("lift_maximum_twr", 0.0)) > 1.05, "Preset %s maintains positive vertical climb margin (TWR > 1.05)" % preset_name)

		# Mid-climb below 45,000 m -> BELOW_MIN_ALTITUDE.
		# Step once unfrozen in clear air so StarportPad contacts clear cleanly before freezing.
		ship.freeze = false
		ship.global_position = Vector3(0.0, 12000.0, 0.0)
		ship.linear_velocity = Vector3(0.0, 120.0, 0.0)
		await physics_frame
		ship.freeze = true
		ship.global_position = Vector3(0.0, 12000.0, 0.0)
		ship.linear_velocity = Vector3(0.0, 120.0, 0.0)
		await physics_frame
		controller.call("_publish_telemetry")
		if overlay != null:
			var climb_tele: Dictionary = overlay.get("_telemetry")
			_expect(not bool(climb_tele.get("jump_eligible", true)) and str(climb_tele.get("jump_reason_code", "")) == "BELOW_MIN_ALTITUDE", "Preset %s at 12,000 m reports BELOW_MIN_ALTITUDE" % preset_name)

		# Above 45,000 m -> READY.
		ship.global_position = Vector3(0.0, 45200.0, 0.0)
		await physics_frame
		controller.call("_publish_telemetry")
		if overlay != null:
			var ready_tele: Dictionary = overlay.get("_telemetry")
			_expect(bool(ready_tele.get("jump_eligible", false)) and str(ready_tele.get("jump_reason_code", "")) == "READY", "Preset %s at 45,200 m reports READY" % preset_name)

	# 4. Verify F3 diagnostics panel renders Phase 3D jump envelope section.
	if hud != null and overlay != null:
		var dbg_tele: Dictionary = Dictionary(overlay.get("_telemetry")).duplicate(true)
		dbg_tele["debug_overview_enabled"] = true
		hud.call("update_telemetry", dbg_tele)
		var dbg_text: String = str(hud.get("_debug_text_label").text)
		_expect(dbg_text.contains("[ ENVIRONMENT & JUMP ENVELOPE (PHASE 3D) ]"), "F3 diagnostics renders Phase 3D environment & jump envelope section")
		_expect(dbg_text.contains("JUMP READY"), "F3 diagnostics displays JUMP READY when eligible")

	world.queue_free()

func _seat_player_immediately_for_test(ship: RigidBody3D, player: CharacterBody3D) -> void:
	var seat_anchor := ship.get("seat_anchor") as Node3D
	var cockpit_camera := ship.get("cockpit_camera") as Camera3D
	var hull_visual := ship.get("hull_visual") as Node3D
	var cockpit_interior := ship.get("cockpit_interior") as Node3D
	var body_collision := player.get("body_collision") as CollisionShape3D
	var player_camera := player.get("player_camera") as Camera3D
	var controls_label := player.get("_controls_label") as Control
	var prompt_panel := player.get("_prompt_panel") as Control
	player.set("_piloting", true)
	player.set("_transitioning", false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.velocity = Vector3.ZERO
	if is_instance_valid(seat_anchor):
		player.global_transform = seat_anchor.global_transform
	if is_instance_valid(body_collision):
		body_collision.disabled = true
	if is_instance_valid(player_camera):
		player_camera.current = false
	if is_instance_valid(cockpit_camera):
		cockpit_camera.make_current()
	if is_instance_valid(controls_label):
		controls_label.visible = false
	if is_instance_valid(prompt_panel):
		prompt_panel.visible = false
	if is_instance_valid(hull_visual):
		hull_visual.visible = false
	if is_instance_valid(cockpit_interior):
		cockpit_interior.visible = true
	ship.set("_pilot_claimed", true)
	ship.set("_active_pilot", player)

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
