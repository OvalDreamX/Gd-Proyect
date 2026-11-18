extends SceneTree

## Headless pure + integration tests for Patch 0.4.1 AtmosphereModel,
## configurable planetary presets, Jacchia-Roberts upper rarefaction,
## Knudsen flow regimes, early convective vacuum taper, and radiator 1.0x fix.
## Run: godot --headless --path . --script res://tests/atmosphere_model_test.gd

const ATMO_MODEL = preload("res://scripts/atmosphere_model.gd")
const VANE_CONTROLLER_SCRIPT = preload("res://scripts/vane_controller.gd")
const LOADER_SCRIPT = preload("res://scripts/ship_definition_loader.gd")
const HUD_OVERLAY_SCRIPT = preload("res://scripts/flight_hud_overlay.gd")
const PLANET_SCENE = preload("res://scenes/planet_surface.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_run_preset_catalog_tests()
	_run_tatooine_jacchia_and_taper_tests()
	_run_configurable_gas_and_radiator_tests()
	await _run_planet_surface_integration_tests()
	print("Atmosphere model tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_preset_catalog_tests() -> void:
	var preset_ids: PackedStringArray = ATMO_MODEL.get_preset_ids()
	for required_id: String in ["DESERT_TATOOINE", "EARTH_STANDARD", "VENUS_DENSE", "GAS_GIANT", "MARS_THIN", "MOON_VACUUM"]:
		_expect(preset_ids.has(required_id), "AtmosphereModel exposes preset %s" % required_id)

	var tatooine_cfg: Dictionary = ATMO_MODEL.get_preset("DESERT_TATOOINE")
	var tatooine_sl: Dictionary = ATMO_MODEL.sample_atmosphere(tatooine_cfg, 0.0)
	var tatooine_tropo: Dictionary = ATMO_MODEL.sample_atmosphere(tatooine_cfg, 14000.0)
	_expect(absf(float(tatooine_sl.get("density_kg_m3", 0.0)) - 1.225) < 0.02, "Tatooine sea-level density starts at 1.225 kg/m3")
	_expect(float(tatooine_sl.get("ambient_temp_c", -99.0)) > 12.0, "Tatooine sea-level radiative ambient > +12C")
	_expect(float(tatooine_tropo.get("ambient_temp_c", 0.0)) < -50.0, "Tatooine 14 km tropopause hits cold cooling sweet spot")

	var venus_sl: Dictionary = ATMO_MODEL.sample_atmosphere(ATMO_MODEL.get_preset("VENUS_DENSE"), 0.0)
	var mars_sl: Dictionary = ATMO_MODEL.sample_atmosphere(ATMO_MODEL.get_preset("MARS_THIN"), 0.0)
	var gas_sl: Dictionary = ATMO_MODEL.sample_atmosphere(ATMO_MODEL.get_preset("GAS_GIANT"), 0.0)
	var moon_sl: Dictionary = ATMO_MODEL.sample_atmosphere(ATMO_MODEL.get_preset("MOON_VACUUM"), 0.0)

	_expect(float(venus_sl.get("density_kg_m3", 0.0)) > 50.0 and float(venus_sl.get("ambient_temp_c", 0.0)) > 400.0, "Venus preset produces supercritical dense hot CO2 surface atmosphere")
	_expect(float(mars_sl.get("density_kg_m3", 0.0)) > 0.01 and float(mars_sl.get("density_kg_m3", 1.0)) < 0.05, "Mars preset produces thin CO2 surface atmosphere")
	_expect(float(gas_sl.get("speed_of_sound_mps", 0.0)) > 750.0, "Gas Giant hydrogen/helium mix has elevated speed of sound")
	_expect(float(moon_sl.get("density_kg_m3", 1.0)) == 0.0 and str(moon_sl.get("flow_regime", "")) == "VACUUM", "Moon preset enforces pure vacuum and zero convective efficiency")

	var moon_sky: Dictionary = ATMO_MODEL.evaluate_sky_colors(ATMO_MODEL.get_preset("MOON_VACUUM"), 0.0, 25.0)
	_expect(float(moon_sky.get("star_visibility", 0.0)) >= 0.99, "Moon surface shows full starfield in daytime")


func _run_tatooine_jacchia_and_taper_tests() -> void:
	var cfg: Dictionary = ATMO_MODEL.get_preset("DESERT_TATOOINE")
	var s_0: Dictionary = ATMO_MODEL.sample_atmosphere(cfg, 0.0)
	var s_14: Dictionary = ATMO_MODEL.sample_atmosphere(cfg, 14000.0)
	var s_28: Dictionary = ATMO_MODEL.sample_atmosphere(cfg, 28000.0)
	var s_36: Dictionary = ATMO_MODEL.sample_atmosphere(cfg, 36000.0)
	var s_45: Dictionary = ATMO_MODEL.sample_atmosphere(cfg, 45000.0)

	var rho_0: float = float(s_0.get("density_kg_m3", 0.0))
	var rho_14: float = float(s_14.get("density_kg_m3", 0.0))
	var rho_28: float = float(s_28.get("density_kg_m3", 0.0))
	var rho_36: float = float(s_36.get("density_kg_m3", 0.0))
	var rho_45: float = float(s_45.get("density_kg_m3", 1.0))
	_expect(rho_0 > rho_14 and rho_14 > rho_28 and rho_28 > rho_36 and rho_36 > rho_45, "Tatooine density decreases strictly monotonically to 45 km top")
	_expect(rho_45 == 0.0, "Tatooine density reaches exact zero at 45 km atmosphere top")

	_expect(str(s_0.get("flow_regime", "")) == "CONTINUUM", "0 km operates in CONTINUUM flow regime")
	var kn_28: float = float(s_28.get("knudsen_number", 0.0))
	var kn_36: float = float(s_36.get("knudsen_number", 0.0))
	_expect(kn_36 > kn_28, "Knudsen number increases monotonically with upper-atmosphere rarefaction")
	_expect(str(s_45.get("flow_regime", "")) == "VACUUM", "45 km atmosphere top enters VACUUM flow regime")

	# Early 25-30 km convective taper toward vacuum dominance.
	var conv_14: float = float(s_14.get("convective_efficiency", 0.0))
	var conv_28: float = float(s_28.get("convective_efficiency", 1.0))
	var conv_36: float = float(s_36.get("convective_efficiency", 1.0))
	var conv_45: float = float(s_45.get("convective_efficiency", 1.0))
	_expect(conv_14 > 0.70, "14 km sweet spot preserves strong convective radiator efficiency (actual %.2f)" % conv_14)
	_expect(conv_28 < 0.25, "28 km upper stratosphere tapers convective efficiency sharply (actual %.3f)" % conv_28)
	_expect(conv_36 < 0.02, "36 km pitch-black upper rim approaches vacuum radiator dominance (actual %.4f)" % conv_36)
	_expect(conv_45 == 0.0, "45 km atmosphere top has zero air convection")

	# Optical sky transition from desert daytime to black space.
	var sky_sl: Dictionary = ATMO_MODEL.evaluate_sky_colors(cfg, 0.0, 20.0)
	var sky_hi: Dictionary = ATMO_MODEL.evaluate_sky_colors(cfg, 36000.0, 20.0)
	var sky_space: Dictionary = ATMO_MODEL.evaluate_sky_colors(cfg, 45500.0, 20.0)
	var top_sl: Color = sky_sl.get("sky_top_color", Color.BLACK) as Color
	var top_hi: Color = sky_hi.get("sky_top_color", Color.WHITE) as Color
	var hor_sl: Color = sky_sl.get("sky_horizon_color", Color.BLACK) as Color
	_expect(top_sl.b > top_sl.r and hor_sl.r > 0.65, "Sea-level desert zenith is cerulean blue while horizon glows warm sand ivory")
	_expect(top_hi.get_luminance() < 0.02 and float(sky_hi.get("star_visibility", 0.0)) > 0.85, "36 km sky turns near pitch-black with visible stars")
	_expect(float(sky_space.get("star_visibility", 0.0)) >= 0.99, "Above 45 km reaches 100%% star visibility")


func _run_configurable_gas_and_radiator_tests() -> void:
	var custom_cfg: Dictionary = ATMO_MODEL.build_config("EARTH_STANDARD", {
		"sky_zenith_color": Color(0.10, 0.72, 0.55, 1.0),
		"mie_dust_factor": 0.45,
		"sea_level_density_kg_m3": 1.8,
	})
	_expect(absf(float(custom_cfg.get("sea_level_density_kg_m3", 0.0)) - 1.8) < 0.001, "Custom config overrides sea-level density cleanly")
	var custom_sky: Dictionary = ATMO_MODEL.evaluate_sky_colors(custom_cfg, 0.0, 25.0)
	var custom_top: Color = custom_sky.get("sky_top_color", Color.BLACK) as Color
	_expect(custom_top.g > custom_top.r, "Custom zenith color propagates into AtmosphereModel optical evaluation")

	# Radiator vacuum 1.0x invariant at critical temperature.
	var load_res: Dictionary = LOADER_SCRIPT.load_file("res://data/ships/prototype_freighter/ship.json")
	var vc: VaneController = VANE_CONTROLLER_SCRIPT.new() as VaneController
	root.add_child(vc)
	if bool(load_res.get("valid", false)):
		vc.apply_ship_definition(load_res["definition"])
	var vac_cool_hot: Dictionary = vc.calculate_radiator_cooling_rate(260.0, 0.0, 600.0, 0.0)
	var rare_taper_cool: Dictionary = vc.calculate_radiator_cooling_rate(220.0, 0.02, 600.0, 0.0)
	_expect(absf(float(vac_cool_hot.get("convective_factor", 0.0)) - 1.0) < 0.0001, "Radiator reports exact 1.0x convective factor in vacuum even at 260C")
	_expect(absf(float(rare_taper_cool.get("convective_factor", 0.0)) - 1.0) < 0.0001, "Zero convective efficiency suppresses air convection cleanly to 1.0x")
	_expect(str(HUD_OVERLAY_SCRIPT.format_radiator_status_label(1.0, -135.0)).begins_with("RAD VAC"), "HUD overlay prints RAD VAC when convective factor is 1.0x")
	_expect(str(HUD_OVERLAY_SCRIPT.format_radiator_status_label(1.8, -58.0)).begins_with("RAD AIR"), "HUD overlay prints RAD AIR when convective factor > 1.02")
	vc.queue_free()


func _run_planet_surface_integration_tests() -> void:
	var world: Node3D = PLANET_SCENE.instantiate() as Node3D
	if world == null:
		_fail("PlanetSurface instantiates for atmosphere integration test")
		return
	root.add_child(world)
	await process_frame
	await physics_frame

	var ship: RigidBody3D = world.get_node_or_null("Ship") as RigidBody3D
	var atmo: AtmosphericFlightModel = ship.get_node_or_null("AtmosphericFlightModel") as AtmosphericFlightModel if ship != null else null
	var rep: RepulsorliftSystem = ship.get_node_or_null("RepulsorliftSystem") as RepulsorliftSystem if ship != null else null
	_expect(ship != null and atmo != null and rep != null, "PlanetSurface ship includes AtmosphericFlightModel and RepulsorliftSystem")

	if ship != null and atmo != null and rep != null:
		# High pitch-black altitude (38,000 m): radiator must already converge to ~1.0x vacuum factor!
		ship.freeze = true
		ship.global_position = Vector3(0.0, 38000.0, 0.0)
		ship.linear_velocity = Vector3(0.0, 0.0, -520.0)
		for _i in range(4):
			await physics_frame
		rep.apply_flight_control_forces(true, 1.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.2, 1.0 / 60.0)
		var atmo_hi: Dictionary = atmo.get_telemetry()
		var rep_hi: Dictionary = rep.get_telemetry()
		var conv_eff_hi: float = float(atmo_hi.get("atmosphere_convective_efficiency", 1.0))
		var rad_factor_hi: float = float(rep_hi.get("radiator_convective_factor", 99.0))
		_expect(str(atmo_hi.get("atmosphere_preset_id", "")) == "DESERT_TATOOINE", "PlanetSurface drives AtmosphericFlightModel with DESERT_TATOOINE preset")
		_expect(conv_eff_hi < 0.01, "38 km upper atmosphere drops convective efficiency below 0.01 (actual %.4f)" % conv_eff_hi)
		_expect(rad_factor_hi <= 1.01, "38 km upper atmosphere radiator converges to ~1.0x vacuum cooling (actual %.3fx)" % rad_factor_hi)
		_expect(str(HUD_OVERLAY_SCRIPT.format_radiator_status_label(rad_factor_hi, float(atmo_hi.get("atmosphere_temperature_celsius", -120.0)))).begins_with("RAD VAC"), "HUD displays RAD VAC in pitch-black 38 km sky")

	world.queue_free()
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
