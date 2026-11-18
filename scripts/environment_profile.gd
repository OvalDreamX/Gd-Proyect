extends Resource
class_name EnvironmentProfile

## Physical and visual condition profile for an active local environment.
## Propagates configurable AtmosphereModel presets, custom gas/optical attributes,
## wind, gravity, and jump departure envelopes into EnvironmentManager.

const ATMOSPHERE_MODEL = preload("res://scripts/atmosphere_model.gd")

enum EnvironmentType {
	PLANET_SURFACE,
	LOCAL_SPACE,
}

enum SurfaceGeometryMode {
	FLAT_PLANE = 0,
	SPHERICAL = 1,
}

@export var environment_id: StringName = &"env_test_planet_surface"
@export var environment_type: EnvironmentType = EnvironmentType.PLANET_SURFACE
@export var display_label: String = "Test Planet Surface"
@export var celestial_body: Resource

@export_category("Local Reference & Gravity")
@export var surface_geometry_mode: SurfaceGeometryMode = SurfaceGeometryMode.SPHERICAL
@export var gravity_enabled: bool = true
@export_range(0.0, 50.0, 0.01) var fallback_surface_gravity_mps2: float = 9.81
@export_range(0.0, 100000000.0, 100.0) var fallback_surface_radius_m: float = 0.0
@export var north_reference_local: Vector3 = Vector3(0.0, 0.0, -1.0)

@export_category("Atmosphere & Wind")
@export var atmosphere_enabled: bool = true
@export var override_body_atmosphere: bool = false
@export var atmosphere_preset: String = "DESERT_TATOOINE"
@export_range(0.0, 100.0, 0.001) var sea_level_density_kg_m3: float = 1.225
@export_range(100.0, 50000.0, 100.0) var density_scale_height_m: float = 8500.0
@export_range(0.0, 300000.0, 250.0) var atmosphere_top_altitude_m: float = 45000.0
@export var mean_wind_velocity_local_mps: Vector3 = Vector3(5.0, 0.0, -6.25)
@export var wind_turbulence_enabled: bool = true
@export_range(0.0, 3.0, 0.05) var wind_turbulence_amplitude_mps: float = 1.1
@export var ambient_temperature_celsius: float = -10.0

@export_category("Presentation Defaults")
@export var sky_clear_color: Color = Color(0.87, 0.84, 0.74, 1.0)
@export var ambient_light_color: Color = Color(0.76, 0.72, 0.62, 1.0)
@export_range(0.0, 4.0, 0.05) var ambient_light_energy: float = 0.68

@export_category("Jump Departure Envelope")
@export var jump_allowed: bool = true
@export_range(0.0, 500000.0, 250.0) var jump_min_altitude_m: float = 45000.0
@export_range(0.0, 50000.0, 50.0) var jump_exclusion_radius_m: float = 0.0
@export_range(0.0, 5000.0, 10.0) var jump_max_speed_mps: float = 0.0
@export var jump_require_systems_online: bool = true
@export var jump_disallow_contact: bool = true


func is_space_environment() -> bool:
	return environment_type == EnvironmentType.LOCAL_SPACE


func get_environment_type_name() -> String:
	return "LOCAL_SPACE" if is_space_environment() else "PLANET_SURFACE"


func get_effective_surface_gravity_mps2() -> float:
	if not gravity_enabled or is_space_environment():
		return 0.0
	if celestial_body != null and "surface_gravity_mps2" in celestial_body:
		return maxf(float(celestial_body.get("surface_gravity_mps2")), 0.0)
	return maxf(fallback_surface_gravity_mps2, 0.0)


func get_effective_surface_radius_m() -> float:
	if is_space_environment():
		return 0.0
	if celestial_body != null and "radius_m" in celestial_body:
		return maxf(float(celestial_body.get("radius_m")), 0.0)
	return maxf(fallback_surface_radius_m, 0.0)


func get_effective_north_reference_local() -> Vector3:
	if celestial_body != null and "north_axis_local" in celestial_body:
		var axis: Vector3 = celestial_body.get("north_axis_local") as Vector3
		if axis.length_squared() > 0.000001:
			return axis.normalized()
	if north_reference_local.length_squared() > 0.000001:
		return north_reference_local.normalized()
	return Vector3(0.0, 0.0, -1.0)


func is_atmosphere_active() -> bool:
	if is_space_environment() or not atmosphere_enabled:
		return false
	if not override_body_atmosphere and celestial_body != null and "has_atmosphere" in celestial_body:
		return bool(celestial_body.get("has_atmosphere"))
	return true


func get_effective_atmosphere_preset() -> String:
	if not is_atmosphere_active():
		return "MOON_VACUUM"
	if not override_body_atmosphere and celestial_body != null and "atmosphere_preset" in celestial_body:
		return str(celestial_body.get("atmosphere_preset"))
	return atmosphere_preset


func get_effective_sea_level_density_kg_m3() -> float:
	if not is_atmosphere_active():
		return 0.0
	if not override_body_atmosphere and celestial_body != null and "sea_level_density_kg_m3" in celestial_body:
		return maxf(float(celestial_body.get("sea_level_density_kg_m3")), 0.0)
	return maxf(sea_level_density_kg_m3, 0.0)


func get_effective_scale_height_m() -> float:
	if not override_body_atmosphere and celestial_body != null and "atmosphere_scale_height_m" in celestial_body:
		return maxf(float(celestial_body.get("atmosphere_scale_height_m")), 1.0)
	return maxf(density_scale_height_m, 1.0)


func get_effective_atmosphere_top_altitude_m() -> float:
	if not is_atmosphere_active():
		return 0.0
	if not override_body_atmosphere and celestial_body != null and "atmosphere_top_altitude_m" in celestial_body:
		return maxf(float(celestial_body.get("atmosphere_top_altitude_m")), 0.0)
	return maxf(atmosphere_top_altitude_m, 0.0)


func get_effective_mean_wind_local_mps() -> Vector3:
	if not is_atmosphere_active():
		return Vector3.ZERO
	return mean_wind_velocity_local_mps


func is_wind_turbulence_active() -> bool:
	return is_atmosphere_active() and wind_turbulence_enabled


func get_effective_turbulence_amplitude_mps() -> float:
	if not is_wind_turbulence_active():
		return 0.0
	return maxf(wind_turbulence_amplitude_mps, 0.0)


func get_atmosphere_config(characteristic_length_m: float = 4.0) -> Dictionary:
	if not is_atmosphere_active():
		return ATMOSPHERE_MODEL.build_config("MOON_VACUUM", {"characteristic_length_m": maxf(characteristic_length_m, 0.5)})
	if not override_body_atmosphere and celestial_body != null and celestial_body.has_method("get_atmosphere_config"):
		var body_cfg: Dictionary = celestial_body.call("get_atmosphere_config", characteristic_length_m) as Dictionary
		return body_cfg
	var overrides: Dictionary = {
		"has_atmosphere": true,
		"sea_level_density_kg_m3": sea_level_density_kg_m3,
		"scale_height_m": density_scale_height_m,
		"top_altitude_m": atmosphere_top_altitude_m,
		"characteristic_length_m": maxf(characteristic_length_m, 0.5),
	}
	return ATMOSPHERE_MODEL.build_config(atmosphere_preset, overrides)


func get_atmosphere_sample(altitude_m: float, characteristic_length_m: float = 4.0) -> Dictionary:
	var cfg: Dictionary = get_atmosphere_config(characteristic_length_m)
	return ATMOSPHERE_MODEL.sample_atmosphere(cfg, altitude_m)


func get_effective_ambient_temperature_celsius(altitude_m: float = 0.0) -> float:
	if not override_body_atmosphere and celestial_body != null:
		if not is_space_environment():
			if celestial_body.has_method("calculate_temperature_celsius_at_altitude"):
				return float(celestial_body.call("calculate_temperature_celsius_at_altitude", altitude_m))
			if "ambient_temperature_celsius" in celestial_body:
				return float(celestial_body.get("ambient_temperature_celsius"))
	return ambient_temperature_celsius


func calculate_air_density_kg_m3(altitude_m: float) -> float:
	if not is_atmosphere_active():
		return 0.0
	var cfg: Dictionary = get_atmosphere_config()
	return ATMOSPHERE_MODEL.compute_air_density_kg_m3(cfg, altitude_m)


func get_jump_envelope_config() -> Dictionary:
	return {
		"jump_allowed": jump_allowed,
		"min_altitude_m": 0.0 if is_space_environment() else maxf(jump_min_altitude_m, 0.0),
		"exclusion_radius_m": maxf(jump_exclusion_radius_m, 0.0),
		"max_speed_mps": maxf(jump_max_speed_mps, 0.0),
		"require_systems_online": jump_require_systems_online,
		"disallow_contact": jump_disallow_contact,
	}
