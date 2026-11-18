extends Node
class_name AtmosphericFlightModel

## Applies atmospheric drag and shield-generated lifting-body force as
## independent environmental effects. Uses AtmosphereModel (ISA + Jacchia-Roberts
## upper-atmosphere rarefaction, Sutherland viscosity, Knudsen flow regime,
## convective efficiency attenuation, and rarefied drag bridging) synced with
## EnvironmentManager / PlanetaryReferenceFrame.

const ATMOSPHERE_MODEL = preload("res://scripts/atmosphere_model.gd")

@export_category("Environment")
@export var planetary_reference_frame_path: NodePath = NodePath("../../PlanetaryReferenceFrame")
@export var environment_manager_path: NodePath = NodePath("../../EnvironmentManager")

@export_category("Atmosphere")
@export var atmosphere_enabled: bool = true
@export var atmosphere_preset: String = "DESERT_TATOOINE"
@export var use_rarefied_drag_bridging: bool = true
@export var atmosphere_reference_position_world: Vector3 = Vector3.ZERO
@export_range(0.0, 100.0, 0.001) var sea_level_density_kg_m3: float = 1.225
@export_range(100.0, 50000.0, 100.0) var density_scale_height_m: float = 8500.0
## Optional hard ceiling for atmosphere density (0 = legacy unbounded exponential tail).
@export_range(0.0, 300000.0, 250.0) var atmosphere_top_altitude_m: float = 0.0

@export_category("Thermal environment")
@export var ambient_temperature_celsius: float = -10.0

@export_category("Test-range wind")
@export var atmosphere_velocity_world: Vector3 = Vector3(5.0, 0.0, 6.25)
@export var mean_wind_velocity_local_mps: Vector3 = Vector3(5.0, 0.0, -6.25)
@export var wind_turbulence_enabled: bool = true
@export_range(0.0, 3.0, 0.05) var wind_turbulence_amplitude_mps: float = 1.1
@export_range(0.01, 1.0, 0.01) var wind_turbulence_frequency: float = 0.18

@export_category("Hull drag")
@export_range(0.0, 3.0, 0.01) var drag_coefficient: float = 0.8
@export var hull_dimensions_local_m: Vector3 = Vector3(3.6, 1.5, 5.2)
@export_range(0.0, 0.001, 0.0000001) var minimum_density_kg_m3: float = 0.000001

@export_category("Shield-generated glide lift")
@export var shield_glide_lift_enabled: bool = true
@export_range(0.0, 200.0, 0.5) var shield_effective_lift_area_m2: float = 36.0
@export_range(0.0, 1.0, 0.01) var shield_lift_effectiveness: float = 1.0
@export_range(0.1, 5.0, 0.05) var shield_max_lift_coefficient: float = 1.1
@export_range(5.0, 45.0, 0.5) var shield_stall_angle_degrees: float = 20.0
@export_range(0.0, 30.0, 0.5) var lift_minimum_airspeed_mps: float = 5.0
@export_range(1.0, 60.0, 0.5) var lift_full_effective_airspeed_mps: float = 18.0
@export_range(0.0, 0.5, 0.01) var lift_induced_drag_factor: float = 0.0

const MINIMUM_MASS_KG: float = 0.0001
const MINIMUM_SPEED_SQUARED: float = 0.000001
const MINIMUM_FORCE_SQUARED: float = 0.000001
const WIND_NOISE_SEED: int = 49217
const TURBULENCE_AXIS_SCALE := Vector3(0.7, 0.25, 0.7)

@onready var _ship: RigidBody3D = get_parent() as RigidBody3D

var _planetary_reference_frame: PlanetaryReferenceFrame
var _environment_manager: Node
var _wind_noise: FastNoiseLite
var _wind_elapsed_seconds: float = 0.0

var _last_altitude_m: float = 0.0
var _last_up_world: Vector3 = Vector3.UP
var _last_north_world: Vector3 = Vector3(0.0, 0.0, -1.0)
var _last_east_world: Vector3 = Vector3.RIGHT
var _last_gravity_world: Vector3 = Vector3.DOWN * 9.81
var _last_density_kg_m3: float = 0.0
var _last_atmosphere_preset_id: String = "DESERT_TATOOINE"
var _last_pressure_pa: float = 0.0
var _last_gas_kinetic_temp_k: float = 289.15
var _last_dynamic_viscosity_pa_s: float = 0.0
var _last_speed_of_sound_mps: float = 0.0
var _last_mach_number: float = 0.0
var _last_mean_free_path_m: float = 0.0
var _last_knudsen_number: float = 0.0
var _last_flow_regime: String = "CONTINUUM"
var _last_convective_efficiency: float = 1.0
var _last_rarefied_drag_multiplier: float = 1.0
var _last_mean_wind_velocity_world: Vector3 = Vector3.ZERO
var _last_wind_velocity_world: Vector3 = Vector3.ZERO
var _last_turbulence_velocity_world: Vector3 = Vector3.ZERO
var _last_relative_air_velocity_world: Vector3 = Vector3.ZERO
var _last_airspeed_mps: float = 0.0
var _last_projected_area_m2: float = 0.0
var _last_drag_force_world: Vector3 = Vector3.ZERO
var _last_angle_of_attack_degrees: float = 0.0
var _last_lift_coefficient: float = 0.0
var _last_lift_speed_gate: float = 0.0
var _last_forward_flow_fraction: float = 0.0
var _last_lift_direction_world: Vector3 = Vector3.ZERO
var _last_lift_force_world: Vector3 = Vector3.ZERO


func apply_ship_definition(definition: ShipDefinition) -> void:
	if definition == null or definition.aerodynamics.is_empty():
		return
	var aero: Dictionary = definition.aerodynamics
	drag_coefficient = maxf(float(aero.get("drag_coefficient", drag_coefficient)), 0.0)
	if aero.has("hull_dimensions_m") and aero["hull_dimensions_m"] is Array:
		var hd: Array = aero["hull_dimensions_m"]
		if hd.size() == 3:
			hull_dimensions_local_m = Vector3(maxf(float(hd[0]), 0.1), maxf(float(hd[1]), 0.1), maxf(float(hd[2]), 0.1))
	shield_glide_lift_enabled = bool(aero.get("shield_glide_lift_enabled", shield_glide_lift_enabled))
	shield_effective_lift_area_m2 = maxf(float(aero.get("shield_effective_lift_area_m2", shield_effective_lift_area_m2)), 0.0)
	shield_lift_effectiveness = clampf(float(aero.get("shield_lift_effectiveness", shield_lift_effectiveness)), 0.0, 1.0)
	shield_max_lift_coefficient = maxf(float(aero.get("shield_max_lift_coefficient", shield_max_lift_coefficient)), 0.1)
	shield_stall_angle_degrees = clampf(float(aero.get("shield_stall_angle_degrees", shield_stall_angle_degrees)), 5.0, 45.0)
	lift_minimum_airspeed_mps = maxf(float(aero.get("lift_minimum_airspeed_mps", lift_minimum_airspeed_mps)), 0.0)
	lift_full_effective_airspeed_mps = maxf(float(aero.get("lift_full_effective_airspeed_mps", lift_full_effective_airspeed_mps)), lift_minimum_airspeed_mps + 1.0)
	lift_induced_drag_factor = clampf(float(aero.get("lift_induced_drag_factor", lift_induced_drag_factor)), 0.0, 0.5)


func _ready() -> void:
	if _ship == null:
		push_error("AtmosphericFlightModel must be a child of the ship's RigidBody3D.")
		set_physics_process(false)
		return
	_planetary_reference_frame = get_node_or_null(planetary_reference_frame_path) as PlanetaryReferenceFrame
	_resolve_environment_manager()
	_wind_noise = FastNoiseLite.new()
	_wind_noise.seed = WIND_NOISE_SEED
	_wind_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wind_noise.frequency = wind_turbulence_frequency
	_wind_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_wind_noise.fractal_octaves = 2
	_wind_noise.fractal_lacunarity = 2.0
	_wind_noise.fractal_gain = 0.5


func _resolve_environment_manager() -> void:
	if not environment_manager_path.is_empty():
		_environment_manager = get_node_or_null(environment_manager_path)
	if not is_instance_valid(_environment_manager) and is_inside_tree():
		_environment_manager = get_tree().get_first_node_in_group("environment_manager")
	if is_instance_valid(_environment_manager):
		if _environment_manager.has_signal("environment_profile_changed"):
			var cb := Callable(self, "_on_environment_profile_changed")
			if not _environment_manager.is_connected("environment_profile_changed", cb):
				_environment_manager.connect("environment_profile_changed", cb)
		_sync_from_environment_manager()


func _on_environment_profile_changed(_profile: Resource) -> void:
	_sync_from_environment_manager()


func _sync_from_environment_manager() -> void:
	if not is_instance_valid(_environment_manager) or not _environment_manager.has_method("get_atmosphere_conditions"):
		return
	var char_len: float = maxf(maxf(hull_dimensions_local_m.x, hull_dimensions_local_m.z), 1.0)
	var atmo: Dictionary = _environment_manager.call("get_atmosphere_conditions", _last_altitude_m, char_len) as Dictionary
	if not bool(atmo.get("has_profile", false)):
		return
	atmosphere_enabled = bool(atmo.get("atmosphere_enabled", false))
	atmosphere_preset = str(atmo.get("atmosphere_preset_id", atmosphere_preset))
	_last_atmosphere_preset_id = atmosphere_preset
	sea_level_density_kg_m3 = float(atmo.get("sea_level_density_kg_m3", 0.0))
	density_scale_height_m = float(atmo.get("density_scale_height_m", 8500.0))
	atmosphere_top_altitude_m = float(atmo.get("atmosphere_top_altitude_m", 0.0))
	mean_wind_velocity_local_mps = atmo.get("mean_wind_velocity_local_mps", Vector3.ZERO) as Vector3
	wind_turbulence_enabled = bool(atmo.get("wind_turbulence_enabled", false))
	wind_turbulence_amplitude_mps = float(atmo.get("wind_turbulence_amplitude_mps", 0.0))
	ambient_temperature_celsius = float(atmo.get("ambient_temperature_celsius", -10.0))


func _physics_process(delta: float) -> void:
	_reset_frame_telemetry()
	if not is_instance_valid(_ship):
		return
	if is_instance_valid(_environment_manager):
		_sync_from_environment_manager()
	_wind_elapsed_seconds += maxf(delta, 0.0)
	var environment_frame: Dictionary = {}
	var gravity_world: Vector3 = _ship.get_gravity()
	if is_instance_valid(_environment_manager) and _environment_manager.has_method("get_local_frame"):
		environment_frame = _environment_manager.call("get_local_frame", _ship.global_position) as Dictionary
		gravity_world = environment_frame.get("gravity_world", gravity_world) as Vector3
		_last_up_world = environment_frame.get("up_world", Vector3.UP) as Vector3
		_last_north_world = environment_frame.get("north_world", Vector3(0.0, 0.0, -1.0)) as Vector3
		_last_east_world = environment_frame.get("east_world", Vector3.RIGHT) as Vector3
		_last_altitude_m = maxf(float(environment_frame.get("altitude_m", 0.0)), 0.0)
	elif is_instance_valid(_planetary_reference_frame):
		environment_frame = _planetary_reference_frame.get_local_frame(_ship.global_position)
		gravity_world = environment_frame.get("gravity_world", gravity_world) as Vector3
		_last_up_world = environment_frame.get("up_world", Vector3.UP) as Vector3
		_last_north_world = environment_frame.get("north_world", Vector3(0.0, 0.0, -1.0)) as Vector3
		_last_east_world = environment_frame.get("east_world", Vector3.RIGHT) as Vector3
		_last_altitude_m = maxf(float(environment_frame.get("altitude_m", 0.0)), 0.0)
	else:
		var up_world: Vector3 = -gravity_world.normalized() if gravity_world.length_squared() > 0.000001 else Vector3.UP
		_last_up_world = up_world
		_last_north_world = Vector3(0.0, 0.0, -1.0)
		_last_east_world = Vector3.RIGHT
		_last_altitude_m = maxf(
			(_ship.global_position - atmosphere_reference_position_world).dot(up_world),
			0.0
		)
	_last_gravity_world = gravity_world

	var char_len: float = maxf(maxf(hull_dimensions_local_m.x, hull_dimensions_local_m.z), 1.0)
	_update_wind_sample(environment_frame)
	_last_relative_air_velocity_world = _ship.linear_velocity - _last_wind_velocity_world
	_last_airspeed_mps = _last_relative_air_velocity_world.length()

	if not atmosphere_enabled:
		_last_density_kg_m3 = 0.0
		_last_convective_efficiency = 0.0
		_last_flow_regime = "VACUUM"
		_last_knudsen_number = 1.0e9
		_last_mean_free_path_m = 1.0e9
		_last_rarefied_drag_multiplier = 0.0
		return

	if is_instance_valid(_environment_manager) and _environment_manager.has_method("get_atmosphere_conditions"):
		var alt_atmo: Dictionary = _environment_manager.call("get_atmosphere_conditions", _last_altitude_m, char_len) as Dictionary
		if bool(alt_atmo.get("has_profile", false)):
			ambient_temperature_celsius = float(alt_atmo.get("ambient_temperature_celsius", ambient_temperature_celsius))
			_last_atmosphere_preset_id = str(alt_atmo.get("atmosphere_preset_id", atmosphere_preset))
			_last_density_kg_m3 = float(alt_atmo.get("density_kg_m3", 0.0))
			_last_pressure_pa = float(alt_atmo.get("pressure_pa", 0.0))
			_last_gas_kinetic_temp_k = float(alt_atmo.get("gas_kinetic_temp_k", 138.0))
			_last_dynamic_viscosity_pa_s = float(alt_atmo.get("dynamic_viscosity_pa_s", 0.0))
			_last_speed_of_sound_mps = float(alt_atmo.get("speed_of_sound_mps", 0.0))
			_last_mean_free_path_m = float(alt_atmo.get("mean_free_path_m", 1.0e9))
			_last_knudsen_number = float(alt_atmo.get("knudsen_number", 1.0e9))
			_last_flow_regime = str(alt_atmo.get("flow_regime", "VACUUM"))
			_last_convective_efficiency = float(alt_atmo.get("convective_efficiency", 0.0))
			_last_rarefied_drag_multiplier = float(alt_atmo.get("rarefied_drag_multiplier", 0.0))
	elif atmosphere_top_altitude_m > 0.0:
		var local_cfg: Dictionary = ATMOSPHERE_MODEL.build_config(atmosphere_preset, {
			"has_atmosphere": true,
			"sea_level_density_kg_m3": sea_level_density_kg_m3,
			"scale_height_m": density_scale_height_m,
			"top_altitude_m": atmosphere_top_altitude_m,
			"characteristic_length_m": char_len,
		})
		var sample: Dictionary = ATMOSPHERE_MODEL.sample_atmosphere(local_cfg, _last_altitude_m)
		_last_atmosphere_preset_id = str(sample.get("preset_id", atmosphere_preset))
		_last_density_kg_m3 = float(sample.get("density_kg_m3", 0.0))
		_last_pressure_pa = float(sample.get("pressure_pa", 0.0))
		_last_gas_kinetic_temp_k = float(sample.get("gas_kinetic_temp_k", 289.15))
		_last_dynamic_viscosity_pa_s = float(sample.get("dynamic_viscosity_pa_s", 0.0))
		_last_speed_of_sound_mps = float(sample.get("speed_of_sound_mps", 0.0))
		_last_mean_free_path_m = float(sample.get("mean_free_path_m", 1.0e9))
		_last_knudsen_number = float(sample.get("knudsen_number", 1.0e9))
		_last_flow_regime = str(sample.get("flow_regime", "VACUUM"))
		_last_convective_efficiency = float(sample.get("convective_efficiency", 0.0))
		_last_rarefied_drag_multiplier = float(sample.get("rarefied_drag_multiplier", 0.0))
	else:
		_last_density_kg_m3 = calculate_air_density(
			sea_level_density_kg_m3,
			_last_altitude_m,
			density_scale_height_m,
			0.0
		)
		_last_atmosphere_preset_id = atmosphere_preset
		_last_gas_kinetic_temp_k = maxf(ambient_temperature_celsius + 273.15, 40.0)
		_last_pressure_pa = _last_density_kg_m3 * 287.05 * _last_gas_kinetic_temp_k
		_last_speed_of_sound_mps = sqrt(maxf(1.4 * 287.05 * _last_gas_kinetic_temp_k, 0.0))
		_last_dynamic_viscosity_pa_s = 1.716e-5 * pow(_last_gas_kinetic_temp_k / 273.15, 1.5) * (383.55 / (_last_gas_kinetic_temp_k + 110.4))
		_last_mean_free_path_m = 6.8e-8 * (1.225 / maxf(_last_density_kg_m3, 1e-12))
		_last_knudsen_number = _last_mean_free_path_m / char_len
		_last_flow_regime = "CONTINUUM" if _last_density_kg_m3 > minimum_density_kg_m3 else "VACUUM"
		_last_convective_efficiency = 1.0 if _last_density_kg_m3 > minimum_density_kg_m3 else 0.0
		_last_rarefied_drag_multiplier = 1.0 if _last_density_kg_m3 > minimum_density_kg_m3 else 0.0

	_last_mach_number = _last_airspeed_mps / maxf(_last_speed_of_sound_mps, 1.0) if _last_speed_of_sound_mps > 1.0 else 0.0

	if (
		_ship.mass <= MINIMUM_MASS_KG
		or _last_density_kg_m3 <= minimum_density_kg_m3
		or _last_relative_air_velocity_world.length_squared() <= MINIMUM_SPEED_SQUARED
	):
		return

	var body_basis: Basis = _ship.global_basis.orthonormalized()
	var local_airflow_direction: Vector3 = body_basis.inverse() * _last_relative_air_velocity_world.normalized()
	_last_projected_area_m2 = calculate_projected_box_area(
		local_airflow_direction,
		hull_dimensions_local_m
	)
	var effective_cd: float = drag_coefficient * (_last_rarefied_drag_multiplier if use_rarefied_drag_bridging else 1.0)
	_last_drag_force_world = calculate_drag_force(
		_last_relative_air_velocity_world,
		_last_density_kg_m3,
		effective_cd,
		_last_projected_area_m2
	)
	var lift_result: Dictionary = calculate_shield_lift(
		_last_relative_air_velocity_world,
		body_basis,
		_last_density_kg_m3,
		shield_effective_lift_area_m2,
		shield_max_lift_coefficient,
		shield_stall_angle_degrees,
		shield_lift_effectiveness,
		lift_minimum_airspeed_mps,
		lift_full_effective_airspeed_mps
	) if shield_glide_lift_enabled else {}
	_last_angle_of_attack_degrees = float(lift_result.get("angle_of_attack_degrees", 0.0))
	_last_lift_coefficient = float(lift_result.get("lift_coefficient", 0.0))
	_last_lift_speed_gate = float(lift_result.get("speed_gate", 0.0))
	_last_forward_flow_fraction = float(lift_result.get("forward_flow_fraction", 0.0))
	_last_lift_direction_world = lift_result.get("lift_direction_world", Vector3.ZERO) as Vector3
	_last_lift_force_world = lift_result.get("lift_force_world", Vector3.ZERO) as Vector3
	if lift_induced_drag_factor > 0.0 and _last_lift_force_world.length_squared() > MINIMUM_FORCE_SQUARED:
		var dyn_q: float = 0.5 * _last_density_kg_m3 * _last_relative_air_velocity_world.length_squared()
		var induced_mag: float = dyn_q * shield_effective_lift_area_m2 * (_last_lift_coefficient * _last_lift_coefficient) * lift_induced_drag_factor
		_last_drag_force_world -= _last_relative_air_velocity_world.normalized() * induced_mag
	if _ship.freeze:
		return
	if _last_drag_force_world.length_squared() > MINIMUM_FORCE_SQUARED:
		_ship.apply_central_force(_last_drag_force_world)
	if _last_lift_force_world.length_squared() > MINIMUM_FORCE_SQUARED:
		_ship.apply_central_force(_last_lift_force_world)


func _update_wind_sample(environment_frame: Dictionary) -> void:
	if not atmosphere_enabled:
		_last_mean_wind_velocity_world = Vector3.ZERO
		_last_turbulence_velocity_world = Vector3.ZERO
		_last_wind_velocity_world = Vector3.ZERO
		return
	_last_turbulence_velocity_world = Vector3.ZERO
	var turbulence_local := Vector3.ZERO
	if wind_turbulence_enabled and wind_turbulence_amplitude_mps > 0.0 and _wind_noise != null:
		var time_sample: float = _wind_elapsed_seconds
		var noise_sample := Vector3(
			_wind_noise.get_noise_1d(time_sample),
			_wind_noise.get_noise_1d(time_sample + 37.1),
			_wind_noise.get_noise_1d(time_sample + 83.7)
		)
		turbulence_local = Vector3(
			noise_sample.x * TURBULENCE_AXIS_SCALE.x,
			noise_sample.y * TURBULENCE_AXIS_SCALE.y,
			noise_sample.z * TURBULENCE_AXIS_SCALE.z
		) * wind_turbulence_amplitude_mps

	if not environment_frame.is_empty():
		var east: Vector3 = environment_frame.get("east_world", Vector3.RIGHT) as Vector3
		var up: Vector3 = environment_frame.get("up_world", Vector3.UP) as Vector3
		var north: Vector3 = environment_frame.get("north_world", Vector3(0.0, 0.0, -1.0)) as Vector3
		_last_mean_wind_velocity_world = east * mean_wind_velocity_local_mps.x + up * mean_wind_velocity_local_mps.y + north * mean_wind_velocity_local_mps.z
		_last_turbulence_velocity_world = east * turbulence_local.x + up * turbulence_local.y + north * turbulence_local.z
	else:
		_last_mean_wind_velocity_world = atmosphere_velocity_world
		_last_turbulence_velocity_world = turbulence_local
	_last_wind_velocity_world = _last_mean_wind_velocity_world + _last_turbulence_velocity_world


func _reset_frame_telemetry() -> void:
	_last_altitude_m = 0.0
	_last_up_world = Vector3.UP
	_last_north_world = Vector3(0.0, 0.0, -1.0)
	_last_east_world = Vector3.RIGHT
	_last_gravity_world = Vector3.DOWN * 9.81
	_last_density_kg_m3 = 0.0
	_last_atmosphere_preset_id = atmosphere_preset
	_last_pressure_pa = 0.0
	_last_gas_kinetic_temp_k = 289.15
	_last_dynamic_viscosity_pa_s = 0.0
	_last_speed_of_sound_mps = 0.0
	_last_mach_number = 0.0
	_last_mean_free_path_m = 1.0e9
	_last_knudsen_number = 1.0e9
	_last_flow_regime = "VACUUM"
	_last_convective_efficiency = 0.0
	_last_rarefied_drag_multiplier = 0.0
	_last_mean_wind_velocity_world = Vector3.ZERO
	_last_wind_velocity_world = Vector3.ZERO
	_last_turbulence_velocity_world = Vector3.ZERO
	_last_relative_air_velocity_world = Vector3.ZERO
	_last_airspeed_mps = 0.0
	_last_projected_area_m2 = 0.0
	_last_drag_force_world = Vector3.ZERO
	_last_angle_of_attack_degrees = 0.0
	_last_lift_coefficient = 0.0
	_last_lift_speed_gate = 0.0
	_last_forward_flow_fraction = 0.0
	_last_lift_direction_world = Vector3.ZERO
	_last_lift_force_world = Vector3.ZERO


static func calculate_air_density(
		sea_level_density: float,
		altitude_above_reference_m: float,
		scale_height_m: float,
		top_altitude_m: float = 0.0) -> float:
	if sea_level_density <= 0.0 or scale_height_m <= 0.0:
		return 0.0
	var altitude: float = maxf(altitude_above_reference_m, 0.0)
	if top_altitude_m <= 0.0:
		return sea_level_density * exp(-altitude / scale_height_m)
	var cfg: Dictionary = {
		"has_atmosphere": true,
		"sea_level_density_kg_m3": sea_level_density,
		"scale_height_m": scale_height_m,
		"top_altitude_m": top_altitude_m,
	}
	return ATMOSPHERE_MODEL.compute_air_density_kg_m3(cfg, altitude)


static func calculate_projected_box_area(direction_local: Vector3, dimensions_local: Vector3) -> float:
	if direction_local.length_squared() <= MINIMUM_SPEED_SQUARED:
		return 0.0
	var dimensions := Vector3(
		maxf(dimensions_local.x, 0.0),
		maxf(dimensions_local.y, 0.0),
		maxf(dimensions_local.z, 0.0)
	)
	var direction: Vector3 = direction_local.normalized()
	return (
		absf(direction.x) * dimensions.y * dimensions.z
		+ absf(direction.y) * dimensions.x * dimensions.z
		+ absf(direction.z) * dimensions.x * dimensions.y
	)


static func calculate_drag_force(
		relative_air_velocity_world: Vector3,
		air_density_kg_m3: float,
		coefficient_of_drag: float,
		projected_area_m2: float) -> Vector3:
	if (
		air_density_kg_m3 <= 0.0
		or coefficient_of_drag <= 0.0
		or projected_area_m2 <= 0.0
		or relative_air_velocity_world.length_squared() <= MINIMUM_SPEED_SQUARED
	):
		return Vector3.ZERO
	var speed: float = relative_air_velocity_world.length()
	var force_scale: float = 0.5 * air_density_kg_m3 * coefficient_of_drag * projected_area_m2 * speed
	return -relative_air_velocity_world * force_scale


static func calculate_angle_of_attack_degrees(
		relative_air_velocity_world: Vector3,
		ship_basis: Basis) -> float:
	if relative_air_velocity_world.length_squared() <= MINIMUM_SPEED_SQUARED:
		return 0.0
	var local_velocity: Vector3 = ship_basis.orthonormalized().inverse() * relative_air_velocity_world
	if local_velocity.z >= -0.001:
		return 0.0
	return rad_to_deg(atan2(-local_velocity.y, -local_velocity.z))


static func calculate_shield_lift_coefficient(
		angle_of_attack_degrees: float,
		maximum_lift_coefficient: float,
		stall_angle_degrees: float) -> float:
	if maximum_lift_coefficient <= 0.0 or stall_angle_degrees <= 0.0:
		return 0.0
	var normalized_angle: float = absf(angle_of_attack_degrees) / stall_angle_degrees
	var magnitude: float = minf(normalized_angle, 1.0) * maximum_lift_coefficient
	if normalized_angle > 1.0:
		var post_stall_fraction: float = clampf(normalized_angle - 1.0, 0.0, 1.0)
		var smooth_fade: float = post_stall_fraction * post_stall_fraction * (3.0 - 2.0 * post_stall_fraction)
		magnitude *= 1.0 - smooth_fade
	return signf(angle_of_attack_degrees) * magnitude


static func calculate_shield_lift(
		relative_air_velocity_world: Vector3,
		ship_basis: Basis,
		air_density_kg_m3: float,
		effective_area_m2: float,
		maximum_lift_coefficient: float,
		stall_angle_degrees: float,
		effectiveness: float,
		minimum_airspeed_mps: float,
		full_effective_airspeed_mps: float) -> Dictionary:
	var result: Dictionary = {
		"angle_of_attack_degrees": 0.0,
		"lift_coefficient": 0.0,
		"speed_gate": 0.0,
		"forward_flow_fraction": 0.0,
		"lift_direction_world": Vector3.ZERO,
		"lift_force_world": Vector3.ZERO,
	}
	var speed_squared: float = relative_air_velocity_world.length_squared()
	if (
		air_density_kg_m3 <= 0.0
		or effective_area_m2 <= 0.0
		or speed_squared <= MINIMUM_SPEED_SQUARED
		or effectiveness <= 0.0
	):
		return result
	var safe_basis: Basis = ship_basis.orthonormalized()
	var local_velocity: Vector3 = safe_basis.inverse() * relative_air_velocity_world
	if local_velocity.z >= -0.001:
		return result
	var airspeed: float = sqrt(speed_squared)
	var angle_of_attack: float = calculate_angle_of_attack_degrees(relative_air_velocity_world, safe_basis)
	var lift_coefficient: float = calculate_shield_lift_coefficient(
		angle_of_attack,
		maximum_lift_coefficient,
		stall_angle_degrees
	)
	var forward_flow_fraction: float = clampf(-local_velocity.normalized().z, 0.0, 1.0)
	var speed_gate: float = _smoothstep_range(minimum_airspeed_mps, full_effective_airspeed_mps, airspeed)
	var local_up_world: Vector3 = safe_basis * Vector3.UP
	var air_direction_world: Vector3 = relative_air_velocity_world / airspeed
	var lift_direction_world: Vector3 = local_up_world - air_direction_world * local_up_world.dot(air_direction_world)
	if lift_direction_world.length_squared() <= MINIMUM_SPEED_SQUARED:
		return result
	lift_direction_world = lift_direction_world.normalized()
	var dynamic_pressure: float = 0.5 * air_density_kg_m3 * speed_squared
	var force_magnitude: float = (
		dynamic_pressure
		* effective_area_m2
		* lift_coefficient
		* clampf(effectiveness, 0.0, 1.0)
		* speed_gate
		* forward_flow_fraction
	)
	var lift_force_world: Vector3 = lift_direction_world * force_magnitude
	result["angle_of_attack_degrees"] = angle_of_attack
	result["lift_coefficient"] = lift_coefficient
	result["speed_gate"] = speed_gate
	result["forward_flow_fraction"] = forward_flow_fraction
	result["lift_direction_world"] = lift_direction_world
	result["lift_force_world"] = lift_force_world
	return result


static func _smoothstep_range(edge_low: float, edge_high: float, value: float) -> float:
	if edge_high <= edge_low:
		return 1.0 if value >= edge_high else 0.0
	var t: float = clampf((value - edge_low) / (edge_high - edge_low), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func get_telemetry() -> Dictionary:
	return {
		"atmosphere_enabled": atmosphere_enabled,
		"atmosphere_preset_id": _last_atmosphere_preset_id,
		"atmosphere_temperature_celsius": ambient_temperature_celsius,
		"atmosphere_altitude_m": _last_altitude_m,
		"atmosphere_up_world": _last_up_world,
		"atmosphere_north_world": _last_north_world,
		"atmosphere_east_world": _last_east_world,
		"atmosphere_gravity_world": _last_gravity_world,
		"atmosphere_density_kg_m3": _last_density_kg_m3,
		"atmosphere_pressure_pa": _last_pressure_pa,
		"atmosphere_gas_kinetic_temp_k": _last_gas_kinetic_temp_k,
		"atmosphere_dynamic_viscosity_pa_s": _last_dynamic_viscosity_pa_s,
		"atmosphere_speed_of_sound_mps": _last_speed_of_sound_mps,
		"atmosphere_mach_number": _last_mach_number,
		"atmosphere_mean_free_path_m": _last_mean_free_path_m,
		"atmosphere_knudsen_number": _last_knudsen_number,
		"atmosphere_flow_regime": _last_flow_regime,
		"atmosphere_convective_efficiency": _last_convective_efficiency,
		"atmosphere_rarefied_drag_multiplier": _last_rarefied_drag_multiplier,
		"atmosphere_velocity_world": _last_wind_velocity_world,
		"atmosphere_mean_wind_velocity_world": _last_mean_wind_velocity_world,
		"atmosphere_mean_wind_velocity_local_mps": mean_wind_velocity_local_mps,
		"atmosphere_turbulence_velocity_world": _last_turbulence_velocity_world,
		"atmosphere_relative_velocity_world": _last_relative_air_velocity_world,
		"atmosphere_airspeed_mps": _last_airspeed_mps,
		"atmosphere_projected_area_m2": _last_projected_area_m2,
		"atmosphere_drag_coefficient": drag_coefficient,
		"atmosphere_drag_force_world": _last_drag_force_world,
		"atmosphere_drag_force_n": _last_drag_force_world.length(),
		"shield_glide_lift_enabled": shield_glide_lift_enabled,
		"shield_lift_effectiveness": shield_lift_effectiveness,
		"shield_effective_lift_area_m2": shield_effective_lift_area_m2,
		"shield_max_lift_coefficient": shield_max_lift_coefficient,
		"shield_lift_angle_of_attack_degrees": _last_angle_of_attack_degrees,
		"shield_lift_coefficient": _last_lift_coefficient,
		"shield_lift_speed_gate": _last_lift_speed_gate,
		"shield_lift_forward_flow_fraction": _last_forward_flow_fraction,
		"shield_lift_direction_world": _last_lift_direction_world,
		"shield_lift_force_world": _last_lift_force_world,
		"shield_lift_force_n": _last_lift_force_world.length(),
		"shield_stall_angle_degrees": shield_stall_angle_degrees,
		"atmosphere_wind_turbulence_enabled": wind_turbulence_enabled,
		"atmosphere_wind_turbulence_amplitude_mps": wind_turbulence_amplitude_mps,
	}
