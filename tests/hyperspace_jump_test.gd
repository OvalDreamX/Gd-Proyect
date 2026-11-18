extends SceneTree

## Headless pure + integration tests for Phase 3F Fixed Hyperspace Route & Transition Coordinator.
## Run: godot --headless --path . --script res://tests/hyperspace_jump_test.gd

const CLOCK_SCRIPT = preload("res://scripts/simulation_clock.gd")
const ROUTE_DEF_SCRIPT = preload("res://scripts/fixed_test_route_definition.gd")
const CALC_SCRIPT = preload("res://scripts/jump_calculator.gd")
const RESOLVER_SCRIPT = preload("res://scripts/arrival_resolver.gd")
const COORDINATOR_SCRIPT = preload("res://scripts/transition_coordinator.gd")

const ROUTE_OUTBOUND = preload("res://data/routes/route_planet_to_station.tres")
const ROUTE_RETURN = preload("res://data/routes/route_station_to_planet.tres")
const PLANET_SCENE = preload("res://scenes/planet_surface.tscn")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_run_pure_route_and_calculator_tests()
	await _run_live_transition_tests()
	print("Hyperspace jump tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _run_pure_route_and_calculator_tests() -> void:
	_expect(ROUTE_OUTBOUND != null and ROUTE_RETURN != null, "Both Phase 3F fixed route resources load")
	var out_val: Dictionary = ROUTE_OUTBOUND.call("validate_route")
	var ret_val: Dictionary = ROUTE_RETURN.call("validate_route")
	_expect(bool(out_val.get("valid", false)), "Outbound Planet -> Station route validates cleanly")
	_expect(bool(ret_val.get("valid", false)), "Return Station -> Planet route validates cleanly")

	var ready_env := {
		"jump_eligible": true,
		"jump_environment_id": "env_test_planet_surface",
		"jump_environment_type": "PLANET_SURFACE",
		"jump_reason_text": "JUMP READY",
	}
	var res_out: Dictionary = CALC_SCRIPT.calculate_jump(ROUTE_OUTBOUND, ready_env, 100.0, {"cargo_preset": "MAX_GROSS", "cargo_mass_kg": 25000.0})
	_expect(bool(res_out.get("valid", false)), "JumpCalculator validates outbound jump plan")
	_expect(absf(float(res_out.get("arrival_sim_time_s", 0.0)) - 520.0) < 0.001, "Arrival sim time equals departure + 420 s duration")
	var xform: Transform3D = res_out.get("arrival_transform", Transform3D.IDENTITY)
	_expect(xform.origin.distance_to(Vector3(0.0, 0.0, 450.0)) < 0.01, "Outbound arrival transform matches (0, 0, 450)")
	_expect(int(res_out.get("persistent_ship_state", {}).get("cargo_mass_kg", 0.0)) == 25000, "JumpResult preserves cargo mass without Node references")

	var mismatch_env := ready_env.duplicate()
	mismatch_env["jump_environment_id"] = "env_station_local_space"
	mismatch_env["jump_environment_type"] = "LOCAL_SPACE"
	var res_mismatch: Dictionary = CALC_SCRIPT.calculate_jump(ROUTE_OUTBOUND, mismatch_env, 0.0)
	_expect(not bool(res_mismatch.get("valid", true)) and str(res_mismatch.get("error_code", "")) == "ROUTE_ENV_MISMATCH", "JumpCalculator rejects wrong departure environment")

	var blocked_env := ready_env.duplicate()
	blocked_env["jump_eligible"] = false
	blocked_env["jump_reason_text"] = "BELOW JUMP ENVELOPE"
	var res_blocked: Dictionary = CALC_SCRIPT.calculate_jump(ROUTE_OUTBOUND, blocked_env, 0.0)
	_expect(not bool(res_blocked.get("valid", true)) and str(res_blocked.get("error_code", "")) == "ENVELOPE_REJECTED", "JumpCalculator rejects ineligible departure envelope")

	var bad_route = ROUTE_DEF_SCRIPT.new()
	bad_route.set("destination_scene_path", "res://scenes/does_not_exist_phase3f.tscn")
	var res_bad_scene: Dictionary = CALC_SCRIPT.calculate_jump(bad_route, ready_env, 0.0)
	_expect(not bool(res_bad_scene.get("valid", true)) and str(res_bad_scene.get("error_code", "")) == "SCENE_MISSING", "JumpCalculator rejects missing destination scene path")

func _run_live_transition_tests() -> void:
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

	# Instantiate PlanetSurface as starting world.
	var planet_world := PLANET_SCENE.instantiate() as Node3D
	_expect(planet_world != null, "PlanetSurface instantiates for live Phase 3F jump loop")
	get_root().add_child(planet_world)
	await process_frame
	await physics_frame

	var ship := planet_world.get_node_or_null("Ship") as RigidBody3D
	var controller := ship.get_node_or_null("FlightController")
	var cargo := ship.get_node_or_null("CargoSystem")
	planet_world.call("seat_pilot_immediately")
	cargo.call("load_preset", "MAX_GROSS")
	controller.set("_field_state", 2) # ONLINE
	await physics_frame

	# While on pad, jump request must fail cleanly without advancing clock or unloading scene.
	var pad_attempt: Dictionary = await coordinator.call("request_jump", ship, null, planet_world)
	_expect(not bool(pad_attempt.get("valid", true)), "Jump rejected while resting on StarportPad")
	_expect(absf(float(sim_clock.call("get_time_seconds"))) < 0.001, "Rejected jump does not advance SimulationClock")
	_expect(is_instance_valid(planet_world), "Rejected jump leaves PlanetSurface active")

	# Climb to 45,200 m (valid jump-entry envelope) and trigger outbound jump + duplicate guard test.
	ship.freeze = false
	ship.global_position = Vector3(0.0, 45200.0, 0.0)
	ship.linear_velocity = Vector3(0.0, 140.0, 0.0)
	await physics_frame
	await physics_frame

	# Launch outbound jump and immediately attempt duplicate request while in HYPERSPACE.
	var out_task = coordinator.call("request_jump", ship, null, planet_world)
	await process_frame
	var dup_attempt: Dictionary = await coordinator.call("request_jump", ship, null, planet_world)
	_expect(str(dup_attempt.get("error_code", "")) == "TRANSITION_IN_PROGRESS", "Duplicate J input during transition is blocked cleanly")

	var out_res: Dictionary = await out_task
	_expect(bool(out_res.get("valid", false)), "Outbound Planet -> Station jump commits successfully")
	var station_world := out_res.get("destination_scene") as Node3D
	_expect(station_world != null and is_instance_valid(station_world), "StationLocalSpace destination scene is active")
	_expect(absf(float(sim_clock.call("get_time_seconds")) - 420.0) < 0.01, "SimulationClock advances exactly once (+420 s) on outbound jump")
	_expect(int(sim_clock.call("get_jump_count")) == 1, "SimulationClock jump_count increments once on outbound jump")

	await process_frame
	await physics_frame

	var station_ship := station_world.get_node_or_null("Ship") as RigidBody3D
	_expect(station_ship != null and station_ship.global_position.distance_to(Vector3(0.0, 0.0, 450.0)) < 0.1, "Ship arrives deterministically at Station ShipArrivalPoint (0, 0, 450)")
	_expect(absf(station_ship.mass - 55000.0) < 1.0, "Ship gross mass (55,000 kg MAX_GROSS) survives outbound transition")
	_expect(bool(station_ship.call("is_pilot_ready")), "Pilot remains seated in cockpit after outbound jump")

	# Verify failed transition recovery (broken route) does NOT strand the player or advance SimulationClock.
	var broken_route = ROUTE_DEF_SCRIPT.new()
	broken_route.set("route_id", &"route_broken")
	broken_route.set("origin_location_id", &"env_station_local_space")
	broken_route.set("destination_location_id", &"env_test_planet_surface")
	broken_route.set("required_departure_env_type", "LOCAL_SPACE")
	broken_route.set("destination_scene_path", "res://scenes/nonexistent_recovery_test.tscn")
	var fail_res: Dictionary = await coordinator.call("request_jump", station_ship, broken_route, station_world)
	_expect(not bool(fail_res.get("valid", true)), "Invalid destination route fails cleanly")
	_expect(str(coordinator.call("get_state_name")) == "IDLE", "TransitionCoordinator recovers to IDLE state after failure")
	_expect(is_instance_valid(station_world) and not station_ship.freeze, "Failed transition keeps StationLocalSpace active and ship unfrozen")
	_expect(absf(float(sim_clock.call("get_time_seconds")) - 420.0) < 0.01, "Failed transition does not advance SimulationClock")

	# Trigger return jump Station -> Planet upper atmosphere!
	var ret_res: Dictionary = await coordinator.call("request_jump", station_ship, null, station_world)
	_expect(bool(ret_res.get("valid", false)), "Return Station -> Planet jump commits successfully")
	var returned_planet := ret_res.get("destination_scene") as Node3D
	_expect(returned_planet != null and is_instance_valid(returned_planet), "PlanetSurface scene is restored on return jump")
	_expect(absf(float(sim_clock.call("get_time_seconds")) - 840.0) < 0.01, "SimulationClock advances once more (+420 s -> 840 s) on return jump")
	_expect(int(sim_clock.call("get_jump_count")) == 2, "SimulationClock jump_count equals 2 after round trip")

	await process_frame
	await physics_frame

	var ret_ship := returned_planet.get_node_or_null("Ship") as RigidBody3D
	_expect(ret_ship != null and ret_ship.global_position.distance_to(Vector3(0.0, 46500.0, 1200.0)) < 0.5, "Return arrival places ship at upper-atmosphere approach (0, 46500, 1200)")
	_expect(absf(ret_ship.mass - 55000.0) < 1.0, "Ship gross mass (55,000 kg) survives return jump")
	_expect(bool(ret_ship.call("is_pilot_ready")), "Pilot remains seated in cockpit on return jump")
	_expect(float(returned_planet.call("get_sky_transition_progress")) > 0.99, "Returned upper-atmosphere sky immediately reflects deep space at 46,500 m")

	returned_planet.queue_free()

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
