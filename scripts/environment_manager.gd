extends Node
class_name EnvironmentManager

## Scene-level provider for active environment conditions (gravity, local up/north/east,
## scaled Jacchia-Roberts atmospheric conditions, Knudsen convection & drag, and jump envelope).

const ATMOSPHERE_MODEL = preload("res://scripts/atmosphere_model.gd")

signal environment_profile_changed(profile: Resource)

@export var active_profile: Resource
@export var planetary_reference_frame_path: NodePath = NodePath("../PlanetaryReferenceFrame")

var _reference_frame: Node3D


func _enter_tree() -> void:
	add_to_group("environment_manager")


func _ready() -> void:
	_resolve_reference_frame()
	_sync_reference_frame()


func _resolve_reference_frame() -> void:
	if not planetary_reference_frame_path.is_empty():
		_reference_frame = get_node_or_null(planetary_reference_frame_path) as Node3D
	if not is_instance_valid(_reference_frame) and is_inside_tree():
		var group_frame: Node3D = get_tree().get_first_node_in_group("planetary_reference_frame") as Node3D
		if is_instance_valid(group_frame):
			_reference_frame = group_frame


func set_active_profile(profile: Resource) -> void:
	active_profile = profile
	_resolve_reference_frame()
	_sync_reference_frame()
	environment_profile_changed.emit(active_profile)


func get_active_profile() -> Resource:
	return active_profile


func _sync_reference_frame() -> void:
	if not is_instance_valid(_reference_frame) or active_profile == null:
		return
	if _reference_frame.has_method("apply_environment_profile"):
		_reference_frame.call("apply_environment_profile", active_profile)


func get_environment_id() -> StringName:
	if active_profile != null and "environment_id" in active_profile:
		return active_profile.get("environment_id") as StringName
	return &"unknown_environment"


func get_environment_type_name() -> String:
	if active_profile != null and active_profile.has_method("get_environment_type_name"):
		return str(active_profile.call("get_environment_type_name"))
	return "PLANET_SURFACE"


func get_display_label() -> String:
	if active_profile != null and "display_label" in active_profile:
		return str(active_profile.get("display_label"))
	return "Unassigned Environment"


func is_gravity_enabled() -> bool:
	if active_profile != null and active_profile.has_method("get_effective_surface_gravity_mps2"):
		return float(active_profile.call("get_effective_surface_gravity_mps2")) > 0.000001
	return true


func get_local_frame(world_position: Vector3) -> Dictionary:
	if active_profile != null and active_profile.has_method("is_space_environment") and bool(active_profile.call("is_space_environment")):
		var north_local: Vector3 = active_profile.call("get_effective_north_reference_local") as Vector3
		var up_world: Vector3 = Vector3.UP
		var north_world: Vector3 = (north_local - up_world * north_local.dot(up_world)).normalized()
		if north_world.length_squared() <= 0.000001:
			north_world = Vector3(0.0, 0.0, -1.0)
		var east_world: Vector3 = north_world.cross(up_world).normalized()
		return {
			"valid": true,
			"up_world": up_world,
			"north_world": north_world,
			"east_world": east_world,
			"altitude_m": 0.0,
			"gravity_world": Vector3.ZERO,
			"gravity_magnitude_mps2": 0.0,
			"surface_geometry": "LOCAL_SPACE",
			"surface_radius_m": 0.0,
		}
	if is_instance_valid(_reference_frame) and _reference_frame.has_method("get_local_frame"):
		var ref_frame: Dictionary = _reference_frame.call("get_local_frame", world_position) as Dictionary
		return ref_frame
	var gravity_mag: float = 0.0
	if active_profile != null and active_profile.has_method("get_effective_surface_gravity_mps2"):
		gravity_mag = float(active_profile.call("get_effective_surface_gravity_mps2"))
	return {
		"valid": true,
		"up_world": Vector3.UP,
		"north_world": Vector3(0.0, 0.0, -1.0),
		"east_world": Vector3.RIGHT,
		"altitude_m": world_position.y,
		"gravity_world": Vector3.DOWN * gravity_mag,
		"gravity_magnitude_mps2": gravity_mag,
		"surface_geometry": "FLAT_PLANE",
		"surface_radius_m": 0.0,
	}


func get_gravity_vector_world(world_position: Vector3) -> Vector3:
	var frame: Dictionary = get_local_frame(world_position)
	return frame.get("gravity_world", Vector3.ZERO) as Vector3


func get_atmosphere_conditions(altitude_m: float = 0.0, characteristic_length_m: float = 4.0) -> Dictionary:
	if active_profile == null:
		return {
			"has_profile": false,
			"atmosphere_enabled": false,
			"atmosphere_preset_id": "MOON_VACUUM",
			"sea_level_density_kg_m3": 0.0,
			"density_scale_height_m": 8500.0,
			"atmosphere_top_altitude_m": 0.0,
			"density_kg_m3": 0.0,
			"pressure_pa": 0.0,
			"gas_kinetic_temp_k": 2.7,
			"dynamic_viscosity_pa_s": 0.0,
			"speed_of_sound_mps": 0.0,
			"mean_free_path_m": 1.0e9,
			"knudsen_number": 1.0e9,
			"flow_regime": "VACUUM",
			"convective_efficiency": 0.0,
			"rarefied_drag_multiplier": 0.0,
			"optical_column_fraction": 0.0,
			"sky_transition_progress": 1.0,
			"atmosphere_config": ATMOSPHERE_MODEL.get_preset("MOON_VACUUM"),
			"mean_wind_velocity_local_mps": Vector3.ZERO,
			"wind_turbulence_enabled": false,
			"wind_turbulence_amplitude_mps": 0.0,
			"ambient_temperature_celsius": -10.0,
		}

	var atmo_active: bool = bool(active_profile.call("is_atmosphere_active"))
	var cfg: Dictionary = active_profile.call("get_atmosphere_config", characteristic_length_m) as Dictionary if active_profile.has_method("get_atmosphere_config") else ATMOSPHERE_MODEL.get_preset("DESERT_TATOOINE")
	var sample: Dictionary = ATMOSPHERE_MODEL.sample_atmosphere(cfg, altitude_m)
	var density_val: float = float(sample.get("density_kg_m3", 0.0)) if atmo_active else 0.0
	var conv_eff: float = float(sample.get("convective_efficiency", 0.0)) if atmo_active else 0.0
	var flow_reg: String = str(sample.get("flow_regime", "VACUUM")) if atmo_active else "VACUUM"
	return {
		"has_profile": true,
		"atmosphere_enabled": atmo_active,
		"atmosphere_preset_id": str(sample.get("preset_id", "DESERT_TATOOINE")),
		"sea_level_density_kg_m3": float(active_profile.call("get_effective_sea_level_density_kg_m3")),
		"density_scale_height_m": float(active_profile.call("get_effective_scale_height_m")),
		"atmosphere_top_altitude_m": float(active_profile.call("get_effective_atmosphere_top_altitude_m")),
		"density_kg_m3": density_val,
		"pressure_pa": float(sample.get("pressure_pa", 0.0)) if atmo_active else 0.0,
		"gas_kinetic_temp_k": float(sample.get("gas_kinetic_temp_k", 138.0)),
		"dynamic_viscosity_pa_s": float(sample.get("dynamic_viscosity_pa_s", 0.0)) if atmo_active else 0.0,
		"speed_of_sound_mps": float(sample.get("speed_of_sound_mps", 0.0)) if atmo_active else 0.0,
		"mean_free_path_m": float(sample.get("mean_free_path_m", 1.0e9)) if atmo_active else 1.0e9,
		"knudsen_number": float(sample.get("knudsen_number", 1.0e9)) if atmo_active else 1.0e9,
		"flow_regime": flow_reg,
		"convective_efficiency": conv_eff,
		"rarefied_drag_multiplier": float(sample.get("rarefied_drag_multiplier", 0.0)) if atmo_active else 0.0,
		"optical_column_fraction": float(sample.get("optical_column_fraction", 0.0)) if atmo_active else 0.0,
		"sky_transition_progress": float(sample.get("sky_transition_progress", 1.0)) if atmo_active else 1.0,
		"atmosphere_config": cfg,
		"mean_wind_velocity_local_mps": active_profile.call("get_effective_mean_wind_local_mps") as Vector3,
		"wind_turbulence_enabled": bool(active_profile.call("is_wind_turbulence_active")),
		"wind_turbulence_amplitude_mps": float(active_profile.call("get_effective_turbulence_amplitude_mps")),
		"ambient_temperature_celsius": float(active_profile.call("get_effective_ambient_temperature_celsius", altitude_m)),
	}


func get_jump_envelope_config() -> Dictionary:
	if active_profile != null and active_profile.has_method("get_jump_envelope_config"):
		var cfg: Dictionary = active_profile.call("get_jump_envelope_config") as Dictionary
		return cfg
	return {
		"jump_allowed": false,
		"min_altitude_m": 0.0,
		"exclusion_radius_m": 0.0,
		"max_speed_mps": 0.0,
		"require_systems_online": true,
		"disallow_contact": true,
	}


func get_telemetry(world_position: Vector3 = Vector3.ZERO) -> Dictionary:
	var frame: Dictionary = get_local_frame(world_position)
	var alt_m: float = float(frame.get("altitude_m", 0.0))
	var atmo: Dictionary = get_atmosphere_conditions(alt_m)
	return {
		"environment_id": String(get_environment_id()),
		"environment_type": get_environment_type_name(),
		"environment_label": get_display_label(),
		"gravity_magnitude_mps2": float(frame.get("gravity_magnitude_mps2", 0.0)),
		"gravity_world": frame.get("gravity_world", Vector3.ZERO),
		"local_up_world": frame.get("up_world", Vector3.UP),
		"local_north_world": frame.get("north_world", Vector3(0.0, 0.0, -1.0)),
		"altitude_m": alt_m,
		"atmosphere_enabled": bool(atmo.get("atmosphere_enabled", false)),
		"atmosphere_preset_id": str(atmo.get("atmosphere_preset_id", "DESERT_TATOOINE")),
		"atmosphere_density_kg_m3": float(atmo.get("density_kg_m3", 0.0)),
		"atmosphere_convective_efficiency": float(atmo.get("convective_efficiency", 0.0)),
		"atmosphere_knudsen_number": float(atmo.get("knudsen_number", 1.0e9)),
		"atmosphere_flow_regime": str(atmo.get("flow_regime", "VACUUM")),
		"ambient_temperature_celsius": float(atmo.get("ambient_temperature_celsius", -10.0)),
		"jump_envelope": get_jump_envelope_config(),
	}
