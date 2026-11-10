extends Node
class_name AtmosphericFlightModel

## Applies atmospheric drag as an independent environmental force. A mild
## test-range wind is included so the player can verify that the ship responds
## to air-relative velocity even while the repulsorlift field is OFF.
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
		_ship.freeze
		or _ship.mass <= MINIMUM_MASS_KG
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

	if _last_drag_force_world.length_squared() > MINIMUM_FORCE_SQUARED:
		# Continuous force, once per physics tick. Never multiply by delta and
		# never use impulses for this continuously acting environmental effect.
		# Applying it centrally prevents artificial aerodynamic torque.
		_ship.apply_central_force(_last_drag_force_world)


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
		"atmosphere_wind_turbulence_enabled": wind_turbulence_enabled,
		"atmosphere_wind_turbulence_amplitude_mps": wind_turbulence_amplitude_mps,
	}
