extends RefCounted
class_name AtmosphereModel

## Configurable real-physics scaled atmospheric model.
## Combines barometric/ISA lower layers with Jacchia-Roberts Bates-Walker
## thermosphere/exosphere scaling, Sutherland viscosity, speed of sound,
## mean free path, Knudsen flow regimes, convective efficiency attenuation,
## rarefied drag bridging, and optical column sky scattering.

const AVOGADRO: float = 6.02214076e23
const UNIVERSAL_GAS_CONSTANT: float = 8.314462618
const EARTH_REF_ALT_M: float = 180000.0

const PRESETS: Dictionary = {
	"DESERT_TATOOINE": {
		"preset_id": "DESERT_TATOOINE",
		"has_atmosphere": true,
		"sea_level_density_kg_m3": 1.225,
		"scale_height_m": 8500.0,
		"top_altitude_m": 45000.0,
		"surface_temp_c": 16.0,
		"tropopause_altitude_m": 14000.0,
		"tropopause_temp_c": -58.0,
		"exosphere_temp_c": -135.0,
		"jacchia_exospheric_temp_k": 950.0,
		"mean_molar_mass_kg_mol": 0.02896,
		"molecular_diameter_m": 3.7e-10,
		"gamma": 1.4,
		"ozone_warming_enabled": false,
		"characteristic_length_m": 4.0,
		"zenith_color": Color(0.20, 0.48, 0.80, 1.0),
		"horizon_color": Color(0.87, 0.84, 0.74, 1.0),
		"sunset_zenith_color": Color(0.14, 0.28, 0.56, 1.0),
		"sunset_horizon_color": Color(0.88, 0.68, 0.46, 1.0),
		"limb_rim_color": Color(0.16, 0.52, 1.0, 1.0),
		"rayleigh_strength": 1.0,
		"mie_dust_factor": 0.28,
	},
	"EARTH_STANDARD": {
		"preset_id": "EARTH_STANDARD",
		"has_atmosphere": true,
		"sea_level_density_kg_m3": 1.225,
		"scale_height_m": 8500.0,
		"top_altitude_m": 100000.0,
		"surface_temp_c": 15.0,
		"tropopause_altitude_m": 11000.0,
		"tropopause_temp_c": -56.5,
		"exosphere_temp_c": -135.0,
		"jacchia_exospheric_temp_k": 1050.0,
		"mean_molar_mass_kg_mol": 0.02896,
		"molecular_diameter_m": 3.7e-10,
		"gamma": 1.4,
		"ozone_warming_enabled": true,
		"characteristic_length_m": 4.0,
		"zenith_color": Color(0.14, 0.40, 0.82, 1.0),
		"horizon_color": Color(0.76, 0.86, 0.96, 1.0),
		"sunset_zenith_color": Color(0.10, 0.20, 0.48, 1.0),
		"sunset_horizon_color": Color(0.92, 0.55, 0.30, 1.0),
		"limb_rim_color": Color(0.22, 0.58, 1.0, 1.0),
		"rayleigh_strength": 1.05,
		"mie_dust_factor": 0.14,
	},
	"VENUS_DENSE": {
		"preset_id": "VENUS_DENSE",
		"has_atmosphere": true,
		"sea_level_density_kg_m3": 65.0,
		"scale_height_m": 15900.0,
		"top_altitude_m": 120000.0,
		"surface_temp_c": 464.0,
		"tropopause_altitude_m": 58000.0,
		"tropopause_temp_c": 15.0,
		"exosphere_temp_c": -140.0,
		"jacchia_exospheric_temp_k": 320.0,
		"mean_molar_mass_kg_mol": 0.04401,
		"molecular_diameter_m": 3.3e-10,
		"gamma": 1.29,
		"ozone_warming_enabled": false,
		"characteristic_length_m": 4.0,
		"zenith_color": Color(0.78, 0.62, 0.32, 1.0),
		"horizon_color": Color(0.92, 0.82, 0.56, 1.0),
		"sunset_zenith_color": Color(0.58, 0.36, 0.16, 1.0),
		"sunset_horizon_color": Color(0.90, 0.58, 0.28, 1.0),
		"limb_rim_color": Color(0.94, 0.78, 0.44, 1.0),
		"rayleigh_strength": 0.55,
		"mie_dust_factor": 0.85,
	},
	"GAS_GIANT": {
		"preset_id": "GAS_GIANT",
		"has_atmosphere": true,
		"sea_level_density_kg_m3": 0.45,
		"scale_height_m": 27000.0,
		"top_altitude_m": 220000.0,
		"surface_temp_c": -110.0,
		"tropopause_altitude_m": 55000.0,
		"tropopause_temp_c": -165.0,
		"exosphere_temp_c": -150.0,
		"jacchia_exospheric_temp_k": 900.0,
		"mean_molar_mass_kg_mol": 0.0022,
		"molecular_diameter_m": 2.89e-10,
		"gamma": 1.43,
		"ozone_warming_enabled": false,
		"characteristic_length_m": 4.0,
		"zenith_color": Color(0.28, 0.42, 0.58, 1.0),
		"horizon_color": Color(0.82, 0.72, 0.56, 1.0),
		"sunset_zenith_color": Color(0.20, 0.28, 0.44, 1.0),
		"sunset_horizon_color": Color(0.86, 0.62, 0.42, 1.0),
		"limb_rim_color": Color(0.52, 0.70, 0.92, 1.0),
		"rayleigh_strength": 0.85,
		"mie_dust_factor": 0.52,
	},
	"MARS_THIN": {
		"preset_id": "MARS_THIN",
		"has_atmosphere": true,
		"sea_level_density_kg_m3": 0.02,
		"scale_height_m": 11100.0,
		"top_altitude_m": 75000.0,
		"surface_temp_c": -63.0,
		"tropopause_altitude_m": 32000.0,
		"tropopause_temp_c": -128.0,
		"exosphere_temp_c": -145.0,
		"jacchia_exospheric_temp_k": 300.0,
		"mean_molar_mass_kg_mol": 0.04334,
		"molecular_diameter_m": 3.3e-10,
		"gamma": 1.3,
		"ozone_warming_enabled": false,
		"characteristic_length_m": 4.0,
		"zenith_color": Color(0.42, 0.32, 0.28, 1.0),
		"horizon_color": Color(0.78, 0.54, 0.40, 1.0),
		"sunset_zenith_color": Color(0.20, 0.30, 0.46, 1.0),
		"sunset_horizon_color": Color(0.68, 0.56, 0.58, 1.0),
		"limb_rim_color": Color(0.72, 0.58, 0.52, 1.0),
		"rayleigh_strength": 0.42,
		"mie_dust_factor": 0.68,
	},
	"MOON_VACUUM": {
		"preset_id": "MOON_VACUUM",
		"has_atmosphere": false,
		"sea_level_density_kg_m3": 0.0,
		"scale_height_m": 8500.0,
		"top_altitude_m": 0.0,
		"surface_temp_c": -135.0,
		"tropopause_altitude_m": 1000.0,
		"tropopause_temp_c": -135.0,
		"exosphere_temp_c": -135.0,
		"jacchia_exospheric_temp_k": 138.0,
		"mean_molar_mass_kg_mol": 0.02896,
		"molecular_diameter_m": 3.7e-10,
		"gamma": 1.4,
		"ozone_warming_enabled": false,
		"characteristic_length_m": 4.0,
		"zenith_color": Color(0.004, 0.006, 0.012, 1.0),
		"horizon_color": Color(0.004, 0.006, 0.012, 1.0),
		"sunset_zenith_color": Color(0.004, 0.006, 0.012, 1.0),
		"sunset_horizon_color": Color(0.004, 0.006, 0.012, 1.0),
		"limb_rim_color": Color(0.0, 0.0, 0.0, 1.0),
		"rayleigh_strength": 0.0,
		"mie_dust_factor": 0.0,
	},
}


static func get_preset_ids() -> PackedStringArray:
	return PackedStringArray([
		"DESERT_TATOOINE",
		"EARTH_STANDARD",
		"VENUS_DENSE",
		"GAS_GIANT",
		"MARS_THIN",
		"MOON_VACUUM",
	])


static func get_preset(preset_id: String) -> Dictionary:
	var key: String = preset_id.strip_edges().to_upper()
	if PRESETS.has(key):
		var raw: Dictionary = PRESETS[key] as Dictionary
		return raw.duplicate(true)
	var fallback: Dictionary = PRESETS["DESERT_TATOOINE"] as Dictionary
	return fallback.duplicate(true)


static func build_config(preset_id: String = "DESERT_TATOOINE", overrides: Dictionary = {}) -> Dictionary:
	var cfg: Dictionary = get_preset(preset_id)
	for key: Variant in overrides.keys():
		var k: String = str(key)
		cfg[k] = overrides[key]
	return cfg


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	if edge1 <= edge0:
		return 1.0 if x >= edge1 else 0.0
	var t: float = clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func compute_gas_kinetic_temp_k(config: Dictionary, altitude_m: float) -> float:
	var has_atmo: bool = bool(config.get("has_atmosphere", true))
	var top_alt_m: float = float(config.get("top_altitude_m", 45000.0))
	var surf_c: float = float(config.get("surface_temp_c", 16.0))
	if not has_atmo or top_alt_m <= 0.0:
		return maxf(surf_c + 273.15, 2.7)

	var alt: float = maxf(altitude_m, 0.0)
	var z_ref: float = (alt / top_alt_m) * EARTH_REF_ALT_M
	var t0_k: float = maxf(surf_c + 273.15, 40.0)
	var t_tropo_k: float = maxf(float(config.get("tropopause_temp_c", -58.0)) + 273.15, 40.0)
	var t_exo_k: float = maxf(float(config.get("jacchia_exospheric_temp_k", 950.0)), t_tropo_k)
	var ozone_on: bool = bool(config.get("ozone_warming_enabled", false))
	var strato_peak: float = maxf(t_tropo_k + 54.0, t0_k - 18.0) if ozone_on else (t_tropo_k + 18.0)
	var mesopause_k: float = maxf(t_tropo_k - 30.0, 165.0)

	if z_ref <= 20000.0:
		return lerpf(t0_k, t_tropo_k, _smoothstep(0.0, 20000.0, z_ref))
	if z_ref <= 50000.0:
		return lerpf(t_tropo_k, strato_peak, _smoothstep(20000.0, 50000.0, z_ref))
	if z_ref <= 90000.0:
		return lerpf(strato_peak, mesopause_k, _smoothstep(50000.0, 90000.0, z_ref))
	var tau_jr: float = 0.000036
	var d_z: float = maxf(z_ref - 90000.0, 0.0)
	return t_exo_k - (t_exo_k - mesopause_k) * exp(-tau_jr * d_z)


static func compute_ambient_radiative_temp_c(config: Dictionary, altitude_m: float) -> float:
	var has_atmo: bool = bool(config.get("has_atmosphere", true))
	var top_alt_m: float = float(config.get("top_altitude_m", 45000.0))
	var exo_c: float = float(config.get("exosphere_temp_c", -135.0))
	if not has_atmo or top_alt_m <= 0.0:
		return exo_c
	var alt: float = maxf(altitude_m, 0.0)
	var surf_c: float = float(config.get("surface_temp_c", 16.0))
	var tropo: float = maxf(float(config.get("tropopause_altitude_m", 14000.0)), 1000.0)
	var tropo_c: float = float(config.get("tropopause_temp_c", -58.0))
	if alt <= tropo:
		return lerpf(surf_c, tropo_c, _smoothstep(0.0, tropo, alt))
	var top_clamped: float = maxf(top_alt_m, tropo + 1000.0)
	return lerpf(tropo_c, exo_c, _smoothstep(tropo, top_clamped, alt))


static func compute_air_density_kg_m3(config: Dictionary, altitude_m: float) -> float:
	var has_atmo: bool = bool(config.get("has_atmosphere", true))
	var rho_0: float = float(config.get("sea_level_density_kg_m3", 1.225))
	var scale_h: float = float(config.get("scale_height_m", 8500.0))
	var top_alt_m: float = float(config.get("top_altitude_m", 45000.0))
	if not has_atmo or rho_0 <= 0.0 or scale_h <= 0.0:
		return 0.0
	var alt: float = maxf(altitude_m, 0.0)
	if top_alt_m > 0.0 and alt >= top_alt_m:
		return 0.0
	var rho_baro: float = rho_0 * exp(-alt / scale_h)
	if top_alt_m <= 0.0:
		return rho_baro
	var u: float = clampf(alt / top_alt_m, 0.0, 1.0)
	var jr_active: float = _smoothstep(0.36, 0.85, u)
	var jr_decay_exp: float = 14.5 * jr_active * maxf(u - 0.36, 0.0)
	var taper: float = 1.0 - _smoothstep(0.84 * top_alt_m, top_alt_m, alt)
	return rho_baro * exp(-jr_decay_exp) * taper


static func sample_atmosphere(config: Dictionary, altitude_m: float) -> Dictionary:
	var alt: float = maxf(altitude_m, 0.0)
	var has_atmo: bool = bool(config.get("has_atmosphere", true))
	var top_alt_m: float = float(config.get("top_altitude_m", 45000.0))
	var density: float = compute_air_density_kg_m3(config, alt)
	var ambient_temp_c: float = compute_ambient_radiative_temp_c(config, alt)
	var kinetic_k: float = compute_gas_kinetic_temp_k(config, alt)

	if not has_atmo or density <= 1e-12 or top_alt_m <= 0.0:
		return {
			"preset_id": str(config.get("preset_id", "DESERT_TATOOINE")),
			"altitude_m": alt,
			"density_kg_m3": 0.0,
			"pressure_pa": 0.0,
			"ambient_temp_c": float(config.get("exosphere_temp_c", -135.0)),
			"gas_kinetic_temp_k": kinetic_k,
			"dynamic_viscosity_pa_s": 0.0,
			"speed_of_sound_mps": 0.0,
			"mean_free_path_m": 1.0e9,
			"knudsen_number": 1.0e9,
			"flow_regime": "VACUUM",
			"convective_efficiency": 0.0,
			"rarefied_drag_multiplier": 0.0,
			"optical_column_fraction": 0.0,
			"sky_transition_progress": 1.0,
		}

	var molar_mass: float = maxf(float(config.get("mean_molar_mass_kg_mol", 0.02896)), 0.001)
	var mol_diam: float = maxf(float(config.get("molecular_diameter_m", 3.7e-10)), 1e-11)
	var gamma: float = float(config.get("gamma", 1.4))
	var char_len: float = maxf(float(config.get("characteristic_length_m", 4.0)), 0.5)
	var rho_0: float = float(config.get("sea_level_density_kg_m3", 1.225))
	var scale_h: float = maxf(float(config.get("scale_height_m", 8500.0)), 1.0)

	var r_specific: float = UNIVERSAL_GAS_CONSTANT / molar_mass
	var pressure_pa: float = density * r_specific * kinetic_k
	var speed_of_sound_mps: float = sqrt(maxf(gamma * r_specific * kinetic_k, 0.0))

	var suth_s: float = 110.4
	var mu_0: float = 1.716e-5
	var t_ref: float = 273.15
	var dynamic_viscosity: float = mu_0 * pow(kinetic_k / t_ref, 1.5) * ((t_ref + suth_s) / (kinetic_k + suth_s))

	var u: float = clampf(alt / top_alt_m, 0.0, 1.0)
	var z_ref: float = u * EARTH_REF_ALT_M
	var n_number: float = (density * AVOGADRO) / molar_mass
	var lambda_physical: float = 1.0 / (sqrt(2.0) * PI * mol_diam * mol_diam * maxf(n_number, 1.0))
	var jr_kn_boost: float = exp((z_ref - 65000.0) / 3100.0) if z_ref > 65000.0 else 1.0
	var mean_free_path_m: float = lambda_physical * jr_kn_boost
	var knudsen: float = mean_free_path_m / char_len

	var flow_regime: String = "CONTINUUM"
	if knudsen >= 10.0:
		flow_regime = "FREE_MOLECULAR"
	elif knudsen >= 0.1:
		flow_regime = "TRANSITION"
	elif knudsen >= 0.01:
		flow_regime = "SLIP"

	var boundary_fade: float = 1.0 - _smoothstep(0.56 * top_alt_m, 0.72 * top_alt_m, alt)
	var convective_eff: float = (1.0 / (1.0 + pow(knudsen / 0.08, 1.25))) * boundary_fade
	var bridging: float = _smoothstep(0.01, 10.0, knudsen)
	var rarefied_drag_mult: float = lerpf(1.0, 1.8, bridging)

	var optical_baro: float = rho_0 * exp(-alt / scale_h)
	var optical_col: float = clampf(
		pow(optical_baro / maxf(rho_0, 0.001), 0.78) * (1.0 - _smoothstep(0.55 * top_alt_m, 0.86 * top_alt_m, alt)),
		0.0,
		1.0
	)
	var sky_t: float = clampf(1.0 - pow(optical_col, 0.85), 0.0, 1.0)

	return {
		"preset_id": str(config.get("preset_id", "DESERT_TATOOINE")),
		"altitude_m": alt,
		"density_kg_m3": density,
		"pressure_pa": pressure_pa,
		"ambient_temp_c": ambient_temp_c,
		"gas_kinetic_temp_k": kinetic_k,
		"dynamic_viscosity_pa_s": dynamic_viscosity,
		"speed_of_sound_mps": speed_of_sound_mps,
		"mean_free_path_m": mean_free_path_m,
		"knudsen_number": knudsen,
		"flow_regime": flow_regime,
		"convective_efficiency": convective_eff,
		"rarefied_drag_multiplier": rarefied_drag_mult,
		"optical_column_fraction": optical_col,
		"sky_transition_progress": sky_t,
	}


static func evaluate_sky_colors(config: Dictionary, altitude_m: float, solar_elevation_deg: float) -> Dictionary:
	var sample: Dictionary = sample_atmosphere(config, altitude_m)
	var sky_t: float = float(sample.get("sky_transition_progress", 0.0))
	var opt_col: float = float(sample.get("optical_column_fraction", 1.0))
	var has_atmo: bool = bool(config.get("has_atmosphere", true))

	var zenith_day: Color = config.get("zenith_color", Color(0.20, 0.48, 0.80, 1.0)) as Color
	var horizon_day: Color = config.get("horizon_color", Color(0.87, 0.84, 0.74, 1.0)) as Color
	var zenith_sunset: Color = config.get("sunset_zenith_color", Color(0.14, 0.28, 0.56, 1.0)) as Color
	var horizon_sunset: Color = config.get("sunset_horizon_color", Color(0.88, 0.68, 0.46, 1.0)) as Color
	var limb_col: Color = config.get("limb_rim_color", Color(0.16, 0.52, 1.0, 1.0)) as Color

	var afternoon_t: float = clampf((18.0 - solar_elevation_deg) / 22.0, 0.0, 1.0)
	var sunset_t: float = clampf((8.0 - solar_elevation_deg) / 11.0, 0.0, 1.0)
	var night_t: float = clampf((-solar_elevation_deg + 1.0) / 11.0, 0.0, 1.0)
	var space_color: Color = Color(0.004, 0.006, 0.012, 1.0)

	if not has_atmo:
		return {
			"sky_top_color": space_color,
			"sky_horizon_color": space_color,
			"ground_horizon_color": Color(0.16, 0.16, 0.18, 1.0),
			"ground_bottom_color": Color(0.03, 0.03, 0.035, 1.0),
			"sky_curve": 0.08,
			"fog_density_factor": 0.0,
			"ambient_light_energy": 0.24,
			"star_visibility": 1.0,
			"halo_alpha": 0.0,
			"limb_rim_color": limb_col,
			"sky_transition_progress": 1.0,
		}

	var night_top: Color = Color(0.010, 0.015, 0.032, 1.0)
	var night_horizon: Color = Color(0.025, 0.035, 0.070, 1.0)
	var surface_top: Color = zenith_day.lerp(zenith_sunset, afternoon_t).lerp(night_top, night_t)
	var surface_horizon: Color = horizon_day.lerp(horizon_sunset, sunset_t).lerp(night_horizon, night_t)

	var space_horizon_tint: Color = Color(0.015, 0.024, 0.045, 1.0)
	var current_top: Color = surface_top.lerp(space_color, sky_t)
	var current_horizon: Color = surface_horizon.lerp(space_horizon_tint, sky_t)

	var mie_dust: float = clampf(float(config.get("mie_dust_factor", 0.28)), 0.0, 1.5)
	var ground_day_hor: Color = Color(0.84, 0.77, 0.62, 1.0).lerp(horizon_day, 0.35)
	var ground_hor: Color = ground_day_hor.lerp(horizon_sunset * 0.88, sunset_t).lerp(Color(0.03, 0.035, 0.05, 1.0), maxf(night_t, sky_t))
	var ground_bot: Color = Color(0.56, 0.44, 0.28, 1.0).lerp(Color(0.008, 0.01, 0.014, 1.0), maxf(night_t, sky_t))

	var rayleigh_str: float = clampf(float(config.get("rayleigh_strength", 1.0)), 0.0, 2.0)
	var top_alt_m: float = maxf(float(config.get("top_altitude_m", 45000.0)), 1.0)
	var alt_clamped: float = clampf(altitude_m, 0.0, top_alt_m)
	var halo_alpha: float = clampf((alt_clamped - 6000.0) / 28000.0, 0.0, 1.0) * 0.58 * clampf(rayleigh_str, 0.25, 1.2) * lerpf(1.0, 0.35, night_t)
	var star_vis: float = clampf(maxf(night_t, (sky_t - 0.32) / 0.55), 0.0, 1.0)
	var fog_factor: float = opt_col * (0.45 + 0.55 * mie_dust) * (1.0 - clampf(alt_clamped / top_alt_m, 0.0, 1.0))
	if alt_clamped >= top_alt_m * 0.96:
		fog_factor = 0.0

	return {
		"sky_top_color": current_top,
		"sky_horizon_color": current_horizon,
		"ground_horizon_color": ground_hor,
		"ground_bottom_color": ground_bot,
		"sky_curve": lerpf(0.085, 0.14, mie_dust),
		"fog_density_factor": maxf(fog_factor, 0.0),
		"ambient_light_energy": lerpf(lerpf(0.68, 0.14, night_t), 0.24, sky_t),
		"star_visibility": star_vis,
		"halo_alpha": halo_alpha,
		"limb_rim_color": limb_col,
		"sky_transition_progress": sky_t,
	}
