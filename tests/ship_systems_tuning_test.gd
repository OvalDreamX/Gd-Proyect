extends SceneTree

## Headless pure + integration tests for Patch 0.3.7 / 0.4.1a:
## 1. Live ship.json hydration (modifying JSON values changes RigidBody3D, Atmo, FCC, Vanes).
## 2. Planetary altitude temperature profile & F-104 cold tropopause cooling sweet spot.
## 3. Convective air radiator boost vs exact 1.0x vacuum radiative factor (high-temp & exosphere).
## 4. 8-10 min sustained critical endurance vs 60+ min green cruise endurance.
## 5. Tiered 75% / 50% / 25% integrity degradation at nominal 60C, fault severity, lag, and startup reliability.
## 6. 14 km MAX_GROSS climb acceleration & thermal headroom.
## Run: godot --headless --path . --script res://tests/ship_systems_tuning_test.gd

const SHIP_SCENE = preload("res://scenes/ship_ground_effect.tscn")
const TEST_PLANET_BODY = preload("res://data/celestial/test_planet.tres")
const PLANET_SCENE = preload("res://scenes/planet_surface.tscn")
const LOADER_SCRIPT = preload("res://scripts/ship_definition_loader.gd")
const VANE_CONTROLLER_SCRIPT = preload("res://scripts/vane_controller.gd")
const HUD_OVERLAY_SCRIPT = preload("res://scripts/flight_hud_overlay.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_altitude_temperature_and_radiator_sweet_spot()
	_test_endurance_8_10_min_critical_vs_60_min_green()
	_test_integrity_tiers_75_50_25()
	await _test_live_ship_json_override_propagation()
	await _test_max_gross_climb_thermal_headroom()
	print("Ship systems tuning tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_altitude_temperature_and_radiator_sweet_spot() -> void:
	var t_sl: float = float(TEST_PLANET_BODY.call("calculate_temperature_celsius_at_altitude", 0.0))
	var t_tropo: float = float(TEST_PLANET_BODY.call("calculate_temperature_celsius_at_altitude", 14000.0))
	var t_top: float = float(TEST_PLANET_BODY.call("calculate_temperature_celsius_at_altitude", 46000.0))
	_expect(t_sl > 10.0 and t_tropo < -50.0 and t_top < -120.0, "Planet temperature curve hits +16C SL, -58C tropopause sweet spot, and -135C exosphere")

	var load_res: Dictionary = LOADER_SCRIPT.load_file("res://data/ships/prototype_freighter/ship.json")
	_expect(bool(load_res.get("valid", false)), "Default prototype_freighter/ship.json validates cleanly")
	var def: ShipDefinition = load_res.get("definition") as ShipDefinition

	var vc: VaneController = VANE_CONTROLLER_SCRIPT.new() as VaneController
	root.add_child(vc)
	vc.apply_ship_definition(def)
	vc.random_failures_enabled = false

	var vac_cool: Dictionary = vc.calculate_radiator_cooling_rate(160.0, 0.0, 0.0, 0.0)
	var hot_vac_cool: Dictionary = vc.calculate_radiator_cooling_rate(260.0, 0.0, 600.0, 0.0)
	var sweet_cool: Dictionary = vc.calculate_radiator_cooling_rate(160.0, 0.24, 500.0, 0.90)
	_expect(absf(float(vac_cool.get("convective_factor", 0.0)) - 1.0) < 0.0001, "Vacuum baseline convective factor equals 1.0x")
	_expect(absf(float(hot_vac_cool.get("convective_factor", 0.0)) - 1.0) < 0.0001, "High-temperature 260C vacuum radiative cooling keeps convective factor at 1.0x")
	_expect(float(sweet_cool.get("effective_cooling_per_s", 0.0)) > float(vac_cool.get("effective_cooling_per_s", 0.0)) * 1.5, "Mid-altitude high-speed convective radiator cools >1.5x faster than vacuum")
	_expect(str(HUD_OVERLAY_SCRIPT.format_radiator_status_label(1.0, -135.0)).begins_with("RAD VAC"), "HUD labels 1.0x exosphere/vacuum radiator as RAD VAC")
	_expect(str(HUD_OVERLAY_SCRIPT.format_radiator_status_label(1.8, -58.0)).begins_with("RAD AIR"), "HUD labels 1.8x tropopause air radiator as RAD AIR")
	vc.queue_free()


func _test_endurance_8_10_min_critical_vs_60_min_green() -> void:
	var load_res: Dictionary = LOADER_SCRIPT.load_file("res://data/ships/prototype_freighter/ship.json")
	var def: ShipDefinition = load_res.get("definition") as ShipDefinition
	var vc: VaneController = VANE_CONTROLLER_SCRIPT.new() as VaneController
	root.add_child(vc)
	vc.apply_ship_definition(def)
	vc.random_failures_enabled = false

	vc.reset_all_vanes(110.0)
	var cruise_loads: Dictionary = {&"main_rear": 0.70}
	for _s in range(360):
		vc.update_thermal_simulation(10.0, -58.0, true, cruise_loads, 0.24, 450.0, 0.90)
	var cruise_int: float = _get_vane_integrity(vc, &"main_rear")
	_expect(cruise_int > 0.85, "60 minutes of green-zone cruise keeps integrity > 85%% (actual %.3f)" % cruise_int)
	_expect(vc.get_vane_thermal_status(&"main_rear") == &"GREEN_ZONE", "Cruise at 14 km settles cleanly inside GREEN_ZONE")

	vc.reset_all_vanes(200.0)
	var push_loads: Dictionary = {&"main_rear": 1.0}
	for _s in range(60):
		vc.update_thermal_simulation(1.0, -135.0, true, push_loads, 0.0, 600.0, 0.0)
	var int_1min: float = _get_vane_integrity(vc, &"main_rear")
	_expect(int_1min > 0.95, "1 minute of full vacuum overboost preserves >95%% integrity (actual %.3f)" % int_1min)

	for _s in range(480):
		vc.update_thermal_simulation(1.0, -135.0, true, push_loads, 0.0, 600.0, 0.0)
	var int_9min: float = _get_vane_integrity(vc, &"main_rear")
	_expect(int_9min >= 0.65 and int_9min <= 0.82, "9 minutes of sustained critical push lands near 75%% integrity band (actual %.3f)" % int_9min)
	vc.queue_free()


func _test_integrity_tiers_75_50_25() -> void:
	var load_res: Dictionary = LOADER_SCRIPT.load_file("res://data/ships/prototype_freighter/ship.json")
	var def: ShipDefinition = load_res.get("definition") as ShipDefinition
	var vc: VaneController = VANE_CONTROLLER_SCRIPT.new() as VaneController
	root.add_child(vc)
	vc.apply_ship_definition(def)
	vc.random_failures_enabled = false
	# Warm vanes to nominal operating temperature (60C) so cold-start strain (0.70x)
	# does not mask the pure integrity-tier authority curve.
	vc.reset_all_vanes(60.0)

	_expect(absf(vc.calculate_fault_severity_for_integrity(0.85)) < 0.0001, "Above 75% integrity has zero fault drive")
	vc.set_vane_integrity(&"main_rear", 0.50)
	var tier_50: String = vc.get_integrity_tier_name()
	_expect(tier_50 == "WORN (<75%)" or tier_50 == "DEGRADED (<50%)", "50% integrity reports worn/degraded tier")
	var twr_50: float = vc.get_group_effective_authority_twr(&"main_rear") / 1.5
	_expect(twr_50 >= 0.80 and twr_50 <= 0.92, "At 50%% integrity TWR penalty stays gentle/flyable (~88%%, actual %.3f)" % twr_50)
	_expect(absf(vc.get_startup_reliability() - 1.0) < 0.001, "Startup reliability remains 100%% down to 25%% integrity")

	vc.set_vane_integrity(&"main_rear", 0.15)
	var twr_15: float = vc.get_group_effective_authority_twr(&"main_rear") / 1.5
	_expect(twr_15 < 0.65 and twr_15 > 0.45, "At 15%% integrity TWR droop is noticeable but above limp floor (actual %.3f)" % twr_15)
	_expect(vc.get_startup_reliability() < 0.80, "Below 25%% integrity reduces field startup reliability")
	_expect(vc.get_effective_lag_multiplier() > 0.40, "Below 25%% integrity introduces significant actuator lag")
	vc.queue_free()


func _test_live_ship_json_override_propagation() -> void:
	var ship: ShipInteractable = SHIP_SCENE.instantiate() as ShipInteractable
	ship.position = Vector3(0.0, 200.0, 0.0)
	root.add_child(ship)
	await process_frame

	var atmo: AtmosphericFlightModel = ship.get_node("AtmosphericFlightModel") as AtmosphericFlightModel
	var fcc: FlightControlComputer = ship.get_node("FlightControlComputer") as FlightControlComputer
	_expect(absf(atmo.drag_coefficient - 0.34) < 0.001, "Ship hydrates rebalanced Cd = 0.34 from ship.json")
	_expect(absf(fcc.maximum_pitch_rate_degrees_per_second - 36.0) < 0.01, "Ship hydrates FCC pitch rate 36 deg/s from ship.json")

	var custom_json: String = FileAccess.get_file_as_string("res://data/ships/prototype_freighter/ship.json")
	var parsed_var: Variant = JSON.parse_string(custom_json)
	var parsed: Dictionary = parsed_var as Dictionary if parsed_var is Dictionary else {}
	parsed["id"] = "spacetrucker.test_fighter"
	var physics_blk: Dictionary = parsed.get("physics", {}) as Dictionary
	physics_blk["dry_mass_kg"] = 12000.0
	physics_blk["max_payload_mass_kg"] = 2000.0
	parsed["physics"] = physics_blk
	var aero_blk: Dictionary = parsed.get("aerodynamics", {}) as Dictionary
	aero_blk["drag_coefficient"] = 0.19
	parsed["aerodynamics"] = aero_blk
	var handling_blk: Dictionary = parsed.get("handling", {}) as Dictionary
	handling_blk["maximum_pitch_rate_degrees_per_second"] = 72.0
	parsed["handling"] = handling_blk
	var prop_blk: Dictionary = parsed.get("propulsion", {}) as Dictionary
	var vanes_arr: Array = prop_blk.get("vanes", []) as Array
	if vanes_arr.size() > 4 and vanes_arr[4] is Dictionary:
		var v4: Dictionary = vanes_arr[4] as Dictionary
		v4["authority_twr"] = 3.2
		vanes_arr[4] = v4
	prop_blk["vanes"] = vanes_arr
	parsed["propulsion"] = prop_blk

	var res: Dictionary = LOADER_SCRIPT.parse_text(JSON.stringify(parsed), "fighter_override")
	_expect(bool(res.get("valid", false)), "Modified Fighter JSON parses cleanly")
	ship.set_ship_definition(res.get("definition") as ShipDefinition)
	await process_frame

	_expect(absf(ship.mass - 12000.0) < 0.5, "Changing JSON dry_mass_kg updates live RigidBody3D.mass (12,000 kg)")
	_expect(absf(ship.max_payload_mass_kg - 2000.0) < 0.5, "Changing JSON max_payload_mass_kg updates ShipInteractable")
	_expect(absf(atmo.drag_coefficient - 0.19) < 0.001, "Changing JSON drag_coefficient updates live AtmosphericFlightModel")
	_expect(absf(fcc.maximum_pitch_rate_degrees_per_second - 72.0) < 0.01, "Changing JSON handling updates live FlightControlComputer")
	var vc: VaneController = ship.get_node("VaneController") as VaneController
	_expect(absf(vc.get_group_nominal_authority_twr(&"main_rear") - 3.2) < 0.001, "Changing JSON main_rear authority_twr updates live VaneController (3.2 TWR)")
	ship.queue_free()


func _test_max_gross_climb_thermal_headroom() -> void:
	var world: Node3D = PLANET_SCENE.instantiate() as Node3D
	root.add_child(world)
	await process_frame
	var ship: RigidBody3D = world.get_node("Ship") as RigidBody3D
	var cargo: CargoSystem = ship.get_node("CargoSystem") as CargoSystem
	var vc: VaneController = ship.get_node("VaneController") as VaneController
	var rep: RepulsorliftSystem = ship.get_node("RepulsorliftSystem") as RepulsorliftSystem
	var ctrl: Node = ship.get_node_or_null("FlightController")
	if ctrl != null:
		ctrl.set_physics_process(false)
	vc.random_failures_enabled = false
	cargo.load_preset("MAX_GROSS")
	await physics_frame
	ship.global_position = Vector3(0.0, 14000.0, 0.0)
	ship.linear_velocity = Vector3(0.0, 0.0, -420.0)

	for _t in range(90):
		rep.apply_flight_control_forces(true, 1.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.2, 0.2)
		await physics_frame
	var main_temp: float = vc.get_vane_temperature(&"main_rear")
	var final_speed: float = ship.linear_velocity.length()
	_expect(main_temp < 185.0, "At 14 km sweet spot, 100%% forward thrust stabilizes below OVERHEAT (<185C, actual %.1fC)" % main_temp)
	_expect(final_speed > 435.0, "Lower 14 km drag allows MAX_GROSS freighter to accelerate past 435 m/s cleanly (actual %.1f m/s)" % final_speed)
	world.queue_free()


func _get_vane_integrity(vc: VaneController, vane_id: StringName) -> float:
	var tele: Dictionary = vc.get_telemetry()
	for entry_val: Variant in (tele.get("vane_states", []) as Array):
		var entry: Dictionary = entry_val as Dictionary
		if entry.get("vane_id") == vane_id:
			return float(entry.get("integrity", 0.0))
	return 0.0


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
