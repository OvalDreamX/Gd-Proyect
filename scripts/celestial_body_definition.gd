extends Resource
class_name CelestialBodyDefinition

## Data-driven definition of a compact Phase 3 celestial body backed by the
## configurable scaled AtmosphereModel (Barometric lower + Jacchia-Roberts upper).

const ATMOSPHERE_MODEL = preload("res://scripts/atmosphere_model.gd")

@export var body_id: StringName = &"test_planet"
@export var display_name: String = "Test Planet"
@export_range(100.0, 100000000.0, 100.0) var radius_m: float = 60000.0
@export_range(0.0, 50.0, 0.01) var surface_gravity_mps2: float = 9.81
@export_range(0.0, 1000000.0, 10.0) var rotation_period_seconds: float = 0.0
@export var north_axis_local: Vector3 = Vector3(0.0, 0.0, -1.0)

@export_category("Atmosphere")
@export var atmosphere_preset: String = "DESERT_TATOOINE"
@export var has_atmosphere: bool = true
@export_range(0.0, 100.0, 0.001) var sea_level_density_kg_m3: float = 1.225
@export_range(100.0, 50000.0, 100.0) var atmosphere_scale_height_m: float = 8500.0
@export_range(0.0, 300000.0, 250.0) var atmosphere_top_altitude_m: float = 45000.0
@export var ambient_temperature_celsius: float = -10.0
@export var use_altitude_temperature_curve: bool = false
@export var surface_temperature_celsius: float = 16.0
@export_range(1000.0, 100000.0, 250.0) var tropopause_altitude_m: float = 14000.0
@export var tropopause_temperature_celsius: float = -58.0
@export var exosphere_temperature_celsius: float = -135.0

@export_category("Gas & Jacchia-Roberts Upper Atmosphere")
@export_range(100.0, 2000.0, 10.0) var jacchia_exospheric_temp_k: float = 950.0
@export_range(0.001, 0.1, 0.0001) var mean_molar_mass_kg_mol: float = 0.02896
@export_range(1e-10, 1e-9, 1e-11) var molecular_diameter_m: float = 3.7e-10
@export_range(1.1, 1.67, 0.01) var gas_gamma: float = 1.4
@export var ozone_warming_enabled: bool = false

@export_category("Atmosphere Optical Scattering")
@export var use_custom_atmosphere_colors: bool = false
@export var sky_zenith_color: Color = Color(0.20, 0.48, 0.80, 1.0)
@export var sky_horizon_color: Color = Color(0.87, 0.84, 0.74, 1.0)
@export var sunset_zenith_color: Color = Color(0.14, 0.28, 0.56, 1.0)
@export var sunset_horizon_color: Color = Color(0.88, 0.68, 0.46, 1.0)
@export var limb_rim_color: Color = Color(0.16, 0.52, 1.0, 1.0)
@export_range(0.0, 2.0, 0.02) var rayleigh_strength: float = 1.0
@export_range(0.0, 1.5, 0.02) var mie_dust_factor: float = 0.28

@export_category("Illumination")
@export var star_direction_local: Vector3 = Vector3(-0.45, -0.75, -0.48)
@export var star_color: Color = Color(1.0, 0.91, 0.78, 1.0)


func get_gravitational_parameter() -> float:
	return maxf(surface_gravity_mps2, 0.0) * pow(maxf(radius_m, 0.0), 2.0)


func calculate_gravity_magnitude_at_radius(radial_distance_m: float) -> float:
	if surface_gravity_mps2 <= 0.0 or radius_m <= 0.0 or radial_distance_m <= 0.0:
		return 0.0
	if radial_distance_m < radius_m:
		return surface_gravity_mps2 * (radial_distance_m / radius_m)
	var mu: float = get_gravitational_parameter()
	return mu / (radial_distance_m * radial_distance_m)


func calculate_gravity_magnitude_at_altitude(altitude_m: float) -> float:
	return calculate_gravity_magnitude_at_radius(maxf(radius_m + altitude_m, 0.0))


func get_atmosphere_config(characteristic_length_m: float = 4.0) -> Dictionary:
	var overrides: Dictionary = {
		"has_atmosphere": has_atmosphere,
		"sea_level_density_kg_m3": sea_level_density_kg_m3,
		"scale_height_m": atmosphere_scale_height_m,
		"top_altitude_m": atmosphere_top_altitude_m,
		"surface_temp_c": surface_temperature_celsius if use_altitude_temperature_curve else ambient_temperature_celsius,
		"tropopause_altitude_m": tropopause_altitude_m,
		"tropopause_temp_c": tropopause_temperature_celsius if use_altitude_temperature_curve else ambient_temperature_celsius,
		"exosphere_temp_c": exosphere_temperature_celsius if use_altitude_temperature_curve else ambient_temperature_celsius,
		"jacchia_exospheric_temp_k": jacchia_exospheric_temp_k,
		"mean_molar_mass_kg_mol": mean_molar_mass_kg_mol,
		"molecular_diameter_m": molecular_diameter_m,
		"gamma": gas_gamma,
		"ozone_warming_enabled": ozone_warming_enabled,
		"characteristic_length_m": maxf(characteristic_length_m, 0.5),
		"rayleigh_strength": rayleigh_strength,
		"mie_dust_factor": mie_dust_factor,
	}
	if use_custom_atmosphere_colors:
		overrides["zenith_color"] = sky_zenith_color
		overrides["horizon_color"] = sky_horizon_color
		overrides["sunset_zenith_color"] = sunset_zenith_color
		overrides["sunset_horizon_color"] = sunset_horizon_color
		overrides["limb_rim_color"] = limb_rim_color
	return ATMOSPHERE_MODEL.build_config(atmosphere_preset, overrides)


func get_atmosphere_sample(altitude_m: float, characteristic_length_m: float = 4.0) -> Dictionary:
	var cfg: Dictionary = get_atmosphere_config(characteristic_length_m)
	return ATMOSPHERE_MODEL.sample_atmosphere(cfg, altitude_m)


func calculate_temperature_celsius_at_altitude(altitude_m: float) -> float:
	if not has_atmosphere or not use_altitude_temperature_curve:
		return ambient_temperature_celsius
	return ATMOSPHERE_MODEL.compute_ambient_radiative_temp_c(get_atmosphere_config(), altitude_m)


func calculate_air_density_at_altitude(altitude_m: float) -> float:
	return ATMOSPHERE_MODEL.compute_air_density_kg_m3(get_atmosphere_config(), altitude_m)
