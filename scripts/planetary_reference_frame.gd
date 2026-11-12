extends Node3D
class_name PlanetaryReferenceFrame

## Shared local environment frame for every body operating near one planet.
## Local wind components use X=east, Y=up, Z=north. The node origin is the
## flat-surface datum or the spherical planet center, depending on geometry.

enum SurfaceGeometry {
	FLAT_PLANE,
	SPHERICAL,
}

@export_category("Reference surface")
@export var surface_geometry: SurfaceGeometry = SurfaceGeometry.FLAT_PLANE
@export_range(0.0, 100000000.0, 100.0) var surface_radius_m: float = 0.0
@export var north_reference_local: Vector3 = Vector3(0.0, 0.0, -1.0)

@export_category("Gravity")
@export_range(0.0, 50.0, 0.01) var surface_gravity_mps2: float = 9.81

const MINIMUM_VECTOR_SQUARED: float = 0.000001


func _ready() -> void:
	add_to_group("planetary_reference_frame")


## Returns a mutually orthogonal tangent frame and the environment values at
## world_position. At a geographic pole, north uses the node's local X axis as
## a deterministic fallback because true tangent north is undefined there.
func get_local_frame(world_position: Vector3) -> Dictionary:
	var reference_basis: Basis = global_basis.orthonormalized()
	var up_world: Vector3 = reference_basis.y.normalized()
	var altitude_m: float = (world_position - global_position).dot(up_world)
	var gravity_magnitude: float = maxf(surface_gravity_mps2, 0.0)

	if surface_geometry == SurfaceGeometry.SPHERICAL and surface_radius_m > 0.0:
		var radial: Vector3 = world_position - global_position
		var radial_distance: float = radial.length()
		if radial_distance > MINIMUM_VECTOR_SQUARED:
			up_world = radial / radial_distance
		altitude_m = radial_distance - surface_radius_m
		gravity_magnitude = calculate_spherical_gravity_magnitude(
			gravity_magnitude, surface_radius_m, radial_distance
		)

	var north_reference_world: Vector3 = reference_basis * north_reference_local
	var north_world: Vector3 = north_reference_world - up_world * north_reference_world.dot(up_world)
	if north_world.length_squared() <= MINIMUM_VECTOR_SQUARED:
		var fallback_axis: Vector3 = reference_basis.x
		north_world = fallback_axis - up_world * fallback_axis.dot(up_world)
	if north_world.length_squared() <= MINIMUM_VECTOR_SQUARED:
		var world_axis: Vector3 = Vector3.FORWARD if absf(up_world.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		north_world = world_axis - up_world * world_axis.dot(up_world)
	north_world = north_world.normalized()
	var east_world: Vector3 = north_world.cross(up_world).normalized()
	# Reconstruct north to remove any accumulated numerical non-orthogonality.
	north_world = up_world.cross(east_world).normalized()

	return {
		"valid": true,
		"up_world": up_world,
		"north_world": north_world,
		"east_world": east_world,
		"altitude_m": altitude_m,
		"gravity_world": -up_world * gravity_magnitude,
		"gravity_magnitude_mps2": gravity_magnitude,
		"surface_geometry": "SPHERICAL" if surface_geometry == SurfaceGeometry.SPHERICAL else "FLAT_PLANE",
		"surface_radius_m": surface_radius_m,
	}


## Point-mass inverse-square gravity is used above the surface. Inside the
## sphere, a uniform-density interior approximation gives linear falloff to
## zero at the center instead of a singular inverse-square field.
static func calculate_spherical_gravity_magnitude(
		surface_gravity_mps2: float,
		surface_radius_m: float,
		radial_distance_m: float
) -> float:
	if surface_gravity_mps2 <= 0.0 or surface_radius_m <= 0.0 or radial_distance_m <= 0.0:
		return 0.0
	if radial_distance_m < surface_radius_m:
		return surface_gravity_mps2 * radial_distance_m / surface_radius_m
	return surface_gravity_mps2 * pow(surface_radius_m / radial_distance_m, 2.0)


## Converts a local east/up/north vector into world coordinates at a position.
func local_vector_to_world(local_east_up_north: Vector3, world_position: Vector3) -> Vector3:
	var frame: Dictionary = get_local_frame(world_position)
	return (
		frame["east_world"] * local_east_up_north.x
		+ frame["up_world"] * local_east_up_north.y
		+ frame["north_world"] * local_east_up_north.z
	)


func get_gravity_vector_world(world_position: Vector3) -> Vector3:
	return get_local_frame(world_position).get("gravity_world", Vector3.DOWN * surface_gravity_mps2)
