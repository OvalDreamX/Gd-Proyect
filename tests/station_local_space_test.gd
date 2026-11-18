extends SceneTree

## Headless SceneTree tests for Phase 3E Local-Space Cube Station environment.
## Run: godot --headless --path . --script res://tests/station_local_space_test.gd

const STATION_DEF_RES = preload("res://data/stations/orbital_cube_station.tres")
const STATION_SCENE = preload("res://scenes/station_local_space.tscn")

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_expect(STATION_DEF_RES != null, "OrbitalCubeStation StationDefinition resource loads")
	if STATION_DEF_RES != null:
		var def_val: Dictionary = STATION_DEF_RES.call("validate_definition")
		_expect(bool(def_val.get("valid", false)), "OrbitalCubeStation definition passes validation")
		_expect(str(STATION_DEF_RES.get("station_id")) == "station_orbital_cube_01", "Station ID matches station_orbital_cube_01")

	var world := STATION_SCENE.instantiate() as Node3D
	_expect(world != null, "StationLocalSpace scene instantiates")
	if world == null:
		quit(1)
		return

	root.add_child(world)
	await process_frame
	await physics_frame
	await physics_frame

	var env_manager := world.get_node_or_null("EnvironmentManager")
	var station_body := world.get_node_or_null("OrbitalStationBody") as StaticBody3D
	var docking_trigger := world.get_node_or_null("OrbitalStationBody/DockingArrivalTrigger") as Area3D
	var arrival_point := world.get_node_or_null("ShipArrivalPoint") as Marker3D
	var ship := world.get_node_or_null("Ship") as RigidBody3D
	var player := world.get_node_or_null("Player") as CharacterBody3D

	_expect(env_manager != null, "StationLocalSpace includes EnvironmentManager")
	_expect(station_body != null and station_body.get_node_or_null("StationCollision") != null, "OrbitalStationBody StaticBody3D and StationCollision exist")
	_expect(docking_trigger != null, "DockingArrivalTrigger Area3D exists")
	_expect(arrival_point != null, "ShipArrivalPoint Marker3D exists")
	_expect(ship != null and player != null, "Ship and Player are instanced in StationLocalSpace")

	if env_manager != null:
		_expect(str(env_manager.call("get_environment_id")) == "env_station_local_space", "Active environment ID matches env_station_local_space")
		_expect(str(env_manager.call("get_environment_type_name")) == "LOCAL_SPACE", "Active environment type is LOCAL_SPACE")

	if ship == null or docking_trigger == null or arrival_point == null:
		world.queue_free()
		quit(1)
		return

	var controller := ship.get_node_or_null("FlightController")
	var atmo := ship.get_node_or_null("AtmosphericFlightModel")
	var sensors := ship.get_node_or_null("FlightSensorSuite")
	_expect(controller != null and atmo != null and sensors != null, "Ship flight subsystems exist in StationLocalSpace")
	_expect(bool(ship.call("is_pilot_ready")), "Pilot is seated automatically upon entering StationLocalSpace")
	_expect(is_equal_approx(ship.gravity_scale, 0.0), "Ship keeps RigidBody3D.gravity_scale at 0.0 in station space")

	var atmo_data: Dictionary = atmo.call("get_telemetry")
	var sensor_data: Dictionary = sensors.call("get_instrument_snapshot")
	_expect(not bool(atmo_data["atmosphere_enabled"]), "StationLocalSpace disables atmospheric flight model")
	_expect(absf(float(atmo_data["atmosphere_density_kg_m3"])) < 0.0001, "StationLocalSpace supplies zero air density")
	_expect(float(sensor_data["instrument_gravity_world"].length()) < 0.001, "StationLocalSpace supplies zero planetary gravity")
	_expect(absf(float(sensor_data["instrument_ambient_temperature_celsius"]) - (-150.0)) < 0.1, "StationLocalSpace supplies -150 C ambient temperature")
	_expect(str(sensor_data["instrument_speed_label"]) == "SPEED", "Sensor suite uses inertial SPEED label in station space")

	# Verify arrival point (450 m > 250 m exclusion radius) grants READY once field is ONLINE.
	controller.set("_field_state", 2) # FieldState.ONLINE
	await physics_frame
	controller.call("_publish_telemetry")
	var hud = controller.get("_hud")
	var overlay = hud.get("_flight_display") if hud != null else null
	_expect(overlay != null, "FlightHUD overlay is present in StationLocalSpace")
	if overlay != null:
		var arrival_tele: Dictionary = overlay.get("_telemetry")
		_expect(bool(arrival_tele.get("jump_eligible", false)) and str(arrival_tele.get("jump_reason_code", "")) == "READY", "Arrival point at 450 m is outside 250 m exclusion zone and JUMP READY")
		_expect(str(arrival_tele.get("station_name", "")) == "Orbital Relay Cube 01", "HUD telemetry includes Orbital Relay Cube 01 station name")

	# Verify pure inertial drift without gravity drop or atmospheric slowdown.
	ship.linear_velocity = Vector3(0.0, 0.0, -25.0)
	for _tick in range(12):
		await physics_frame
	_expect(absf(ship.linear_velocity.y) < 0.005, "Ship does not fall under gravity while coasting in station space")
	_expect(absf(ship.linear_velocity.z - (-25.0)) < 0.01, "Ship retains inertial coast velocity in station space without drag")

	# Move inside the 250 m exclusion radius -> INSIDE_EXCLUSION_ZONE.
	ship.linear_velocity = Vector3.ZERO
	ship.global_position = Vector3(0.0, 0.0, 200.0)
	await physics_frame
	controller.call("_publish_telemetry")
	if overlay != null:
		var excl_tele: Dictionary = overlay.get("_telemetry")
		_expect(not bool(excl_tele.get("jump_eligible", true)) and str(excl_tele.get("jump_reason_code", "")) == "INSIDE_EXCLUSION_ZONE", "Inside 250 m station radius reports INSIDE_EXCLUSION_ZONE")

	# Enter DockingArrivalTrigger (+Z approach bay at z = 78) and verify repeatability.
	ship.global_position = Vector3(0.0, 0.0, 78.0)
	for _t in range(4):
		await physics_frame
	_expect(bool(world.call("is_ship_in_docking_zone")), "DockingArrivalTrigger detects ship arrival at +Z bay")
	_expect(int(world.call("get_docking_visit_count")) == 1, "Docking visit count increments on first approach")

	ship.global_position = Vector3(0.0, 0.0, 200.0)
	for _t in range(4):
		await physics_frame
	_expect(not bool(world.call("is_ship_in_docking_zone")), "DockingArrivalTrigger clears when ship backs out of bay")

	ship.global_position = Vector3(0.0, 0.0, 78.0)
	for _t in range(4):
		await physics_frame
	_expect(bool(world.call("is_ship_in_docking_zone")) and int(world.call("get_docking_visit_count")) == 2, "DockingArrivalTrigger works repeatedly on re-approach")

	# Verify F3 displays station telemetry.
	if hud != null and overlay != null:
		controller.call("_publish_telemetry")
		var dbg_tele: Dictionary = Dictionary(overlay.get("_telemetry")).duplicate(true)
		dbg_tele["debug_overview_enabled"] = true
		hud.call("update_telemetry", dbg_tele)
		var dbg_text: String = str(hud.get("_debug_text_label").text)
		_expect(dbg_text.contains("Station target: Orbital Relay Cube 01"), "F3 diagnostics renders Orbital Relay Cube 01 telemetry")

	# Verify reset_to_arrival_point() restores arrival position, zeroes velocity, and clears docking flag.
	world.call("reset_to_arrival_point")
	_expect(ship.global_position.distance_to(arrival_point.global_position) < 0.05, "reset_to_arrival_point restores ship to ShipArrivalPoint")
	_expect(ship.linear_velocity.length() < 0.001, "reset_to_arrival_point zeroes ship velocity")
	_expect(not bool(world.call("is_ship_in_docking_zone")), "reset_to_arrival_point clears docking zone flag")

	print("Station local space tests: %d checks, %d failures." % [_checks, _failures])
	world.queue_free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
