extends Node
class_name AtmosphericFlightModel

## Applies atmospheric drag and shield-generated lifting-body force as
## independent environmental effects. Both use the same air-density and
## air-relative-velocity sample, so wind cannot diverge between subsystems.
## Wind is fixed in world space (the test ship initially faces -Z).

@export_category("Atmosphere")
@export var atmosphere_enabled: bool = true
## World-space point defining zero altitude for the local atmosphere.
## The test range uses the ground plane at world Y = 0.
@export var atmosphere_reference_position_world: Vector3 = Vector3.ZERO
@export_range(0.0, 2.0, 0.001) var sea_level_density_kg_m3: float = 1.225
@export_range(100.0, 50000.0, 100.0) var density_scale_height_m: float = 8500.0

@export_category("Test-range wind")
## Mean wind direction is from the ship's front-left toward its rear-right
## at the initial test-range heading (-Z). This is world-space wind velocity,
## not the direction the wind comes from.
@export var atmosphere_velocity_world: Vector3 = Vector3(5.0, 0.0, 6.25)
@export var wind_turbulence_enabled: bool = true
@export_range(0.0, 3.0, 0.05) var wind_turbulence_amplitude_mps: float = 1.1
@export_range(0.01, 1.0, 0.01) var wind_turbulence_frequency: float = 0.18

@export_category("Hull drag")
## Initial tuning value, not a final aerodynamic coefficient.
@export_range(0.0, 3.0, 0.01) var drag_coefficient: float = 0.8
## Local X/Y/Z hull dimensions. Defaults match the current prototype collider.
@export var hull_dimensions_local_m: Vector3 = Vector3(3.6, 1.5, 5.2)
@export_range(0.0, 0.001, 0.00001) var minimum_density_kg_m3: float = 0.00001

@export_category("Shield-generated glide lift")
@export var shield_glide_lift_enabled: bool = true
## This is an effective field area, not a literal wing area. Tune after flight
## tests and after the final hull proportions are known.
@export_range(0.0, 200.0, 0.5) var shield_effective_lift_area_m2: float = 36.0
## Fraction of available shield lift; later this will be driven by shield condition.
@export_range(0.0, 1.0, 0.01) var shield_lift_effectiveness: float = 1.0
@export_range(0.1, 5.0, 0.05) var shield_max_lift_coefficient: float = 1.1
## Lift rises approximately linearly to this angle, then gradually fades.
@export_range(5.0, 45.0, 0.5) var shield_stall_angle_degrees: float = 20.0
## Smoothly suppresses lift around zero/very low airspeed without a hard force step.
@export_range(0.0, 30.0, 0.5) var lift_minimum_airspeed_mps: float = 5.0
@export_range(1.0, 60.0, 0.5) var lift_full_effective_airspeed_mps: float = 18.0

const MINIMUM_MASS_KG: float = 0.0001
const MINIMUM_SPEED_SQUARED: float = 0.000001
const MINIMUM_FORCE_SQUARED: float = 0.000001
const WIND_NOISE_SEED: int = 49217
const TURBULENCE_AXIS_SCALE := Vector3(0.7, 0.25, 0.7)

@onready var _ship: RigidBody3D = get_parent() as RigidBody3D

var _wind_noise: FastNoiseLite
var _wind_elapsed_seconds: float = 0.0
var _last_altitude_m: float = 0.0
var _last_density_kg_m3: float = 0.0
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


func _ready() -> void:
	if _ship == null:
		push_error("AtmosphericFlightModel must be a child of the ship's RigidBody3D.")
		set_physics_process(false)
		return

	_wind_noise = FastNoiseLite.new()
	_wind_noise.seed = WIND_NOISE_SEED
	_wind_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wind_noise.frequency = wind_turbulence_frequency
	_wind_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_wind_noise.fractal_octaves = 2
	_wind_noise.fractal_lacunarity = 2.0
	_wind_noise.fractal_gain = 0.5


func _physics_process(delta: float) -> void:
	_reset_frame_telemetry()
	if not is_instance_valid(_ship):
		return

	_wind_elapsed_seconds += maxf(delta, 0.0)
	_update_wind_sample()

	var gravity_world: Vector3 = _ship.get_gravity()
	var up_world: Vector3 = -gravity_world.normalized() if gravity_world.length_squared() > 0.000001 else Vector3.UP
	# The body origin is the altitude reference for this low-altitude prototype.
	# It avoids reading RigidBody3D.center_of_mass in AUTO mode, where that
	# property does not expose the solver's computed center of mass.
	_last_altitude_m = maxf(
		(_ship.global_position - atmosphere_reference_position_world).dot(up_world),
		0.0
	)
	_last_relative_air_velocity_world = _ship.linear_velocity - _last_wind_velocity_world
	_last_airspeed_mps = _last_relative_air_velocity_world.length()

	if not atmosphere_enabled:
		return

	_last_density_kg_m3 = calculate_air_density(
		sea_level_density_kg_m3,
		_last_altitude_m,
		density_scale_height_m
	)

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
	_last_drag_force_world = calculate_drag_force(
		_last_relative_air_velocity_world,
		_last_density_kg_m3,
		drag_coefficient,
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
	_last_lift_direction_world = lift_result.get("lift_direction_world", Vector3.ZERO)
	_last_lift_force_world = lift_result.get("lift_force_world", Vector3.ZERO)

	if _ship.freeze:
		return

	# Environmental forces are continuous and central in this first model.
	# This keeps them independent of the vane/repulsorlift torque allocator.
	if _last_drag_force_world.length_squared() > MINIMUM_FORCE_SQUARED:
		_ship.apply_central_force(_last_drag_force_world)
	if _last_lift_force_world.length_squared() > MINIMUM_FORCE_SQUARED:
		_ship.apply_central_force(_last_lift_force_world)


func _update_wind_sample() -> void:
	_last_turbulence_velocity_world = Vector3.ZERO
	if wind_turbulence_enabled and wind_turbulence_amplitude_mps > 0.0 and _wind_noise != null:
		# Three separated samples of one seeded coherent-noise field give smooth,
		# deterministic gust variation without frame-to-frame random impulses.
		var time_sample: float = _wind_elapsed_seconds
		var noise_sample := Vector3(
			_wind_noise.get_noise_1d(time_sample),
			_wind_noise.get_noise_1d(time_sample + 37.1),
			_wind_noise.get_noise_1d(time_sample + 83.7)
		)
		_last_turbulence_velocity_world = Vector3(
			noise_sample.x * TURBULENCE_AXIS_SCALE.x,
			noise_sample.y * TURBULENCE_AXIS_SCALE.y,
			noise_sample.z * TURBULENCE_AXIS_SCALE.z
		) * wind_turbulence_amplitude_mps
	_last_wind_velocity_world = atmosphere_velocity_world + _last_turbulence_velocity_world


func _reset_frame_telemetry() -> void:
	_last_altitude_m = 0.0
	_last_density_kg_m3 = 0.0
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


## Exponential atmosphere approximation. Altitude is above the local reference
## point; density never rises above its sea-level value.
static func calculate_air_density(
		sea_level_density: float,
		altitude_above_reference_m: float,
		scale_height_m: float
) -> float:
	if sea_level_density <= 0.0 or scale_height_m <= 0.0:
		return 0.0
	var altitude: float = maxf(altitude_above_reference_m, 0.0)
	return sea_level_density * exp(-altitude / scale_height_m)


## Orthographic projection area of a box onto a plane perpendicular to airflow.
## The input direction is in ship-local coordinates and dimensions are local
## X/Y/Z extents. No mesh queries or per-frame allocations are required.
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


## Quadratic drag. The returned vector always opposes air-relative velocity.
## F = -0.5 * rho * Cd * A * |v_rel| * v_rel
static func calculate_drag_force(
		relative_air_velocity_world: Vector3,
		air_density_kg_m3: float,
		coefficient_of_drag: float,
		projected_area_m2: float
) -> Vector3:
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


## Angle between the ship's forward axis and air-relative flight path.
## Positive values mean the nose is above the flight path (positive AoA).
static func calculate_angle_of_attack_degrees(
		relative_air_velocity_world: Vector3,
		ship_basis: Basis
) -> float:
	if relative_air_velocity_world.length_squared() <= MINIMUM_SPEED_SQUARED:
		return 0.0
	var local_velocity: Vector3 = ship_basis.orthonormalized().inverse() * relative_air_velocity_world
	if local_velocity.z >= -0.001:
		return 0.0 # No meaningful forward airflow; don't invent a lift angle.
	return rad_to_deg(atan2(-local_velocity.y, -local_velocity.z))


## Bounded lift curve. It rises linearly to the configured stall angle, then
## smoothly fades toward zero by twice that angle rather than growing forever.
static func calculate_shield_lift_coefficient(
		angle_of_attack_degrees: float,
		maximum_lift_coefficient: float,
		stall_angle_degrees: float
) -> float:
	if maximum_lift_coefficient <= 0.0 or stall_angle_degrees <= 0.0:
		return 0.0
	var normalized_angle: float = absf(angle_of_attack_degrees) / stall_angle_degrees
	var magnitude: float = minf(normalized_angle, 1.0) * maximum_lift_coefficient
	if normalized_angle > 1.0:
		var post_stall_fraction: float = clampf(normalized_angle - 1.0, 0.0, 1.0)
		var smooth_fade: float = post_stall_fraction * post_stall_fraction * (3.0 - 2.0 * post_stall_fraction)
		magnitude *= 1.0 - smooth_fade
	return signf(angle_of_attack_degrees) * magnitude


## Calculates a shield-generated lifting-body force from airspeed, density,
## angle of attack and ship attitude. Returns a telemetry dictionary so the
## HUD and tests can inspect each stage without reading mutable physics state.
static func calculate_shield_lift(
		relative_air_velocity_world: Vector3,
		ship_basis: Basis,
		air_density_kg_m3: float,
		effective_area_m2: float,
		maximum_lift_coefficient: float,
		stall_angle_degrees: float,
		effectiveness: float,
		minimum_airspeed_mps: float,
		full_effective_airspeed_mps: float
) -> Dictionary:
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
		return result # Lift is not generated from rearward airflow.

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


## Read-only snapshot for the 30 Hz diagnostic HUD. No physics state is changed.
func get_telemetry() -> Dictionary:
	return {
		"atmosphere_enabled": atmosphere_enabled,
		"atmosphere_altitude_m": _last_altitude_m,
		"atmosphere_density_kg_m3": _last_density_kg_m3,
		"atmosphere_velocity_world": _last_wind_velocity_world,
		"atmosphere_mean_wind_velocity_world": atmosphere_velocity_world,
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
