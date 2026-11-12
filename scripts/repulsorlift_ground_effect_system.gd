extends RepulsorliftSystem
class_name RepulsorliftGroundEffectSystem

## Ground effect is a bounded increase to the upward component of the main
## repulsorlift resultant. It is independent of atmospheric density and does
## not modify the ship's horizontal thrust or manoeuvring-vane forces.

const DEFAULT_SHIP_DEFINITION_PATH: String = "res://data/ships/prototype_freighter/ship.json"
const MINIMUM_VECTOR_SQUARED: float = 0.000001

var _ground_effect_enabled: bool = false
var _ground_effect_gain: float = 0.15
var _ground_effect_footprint_width_m: float = 5.0
var _ground_effect_probe_start_offset_m: float = 0.15
var _ground_effect_minimum_valid_probes: int = 3
var _ground_effect_normal_alignment_min: float = 0.65
var _ground_effect_collision_mask: int = 1
var _ground_effect_probe_anchor_names: PackedStringArray = PackedStringArray()
var _ground_effect_probe_local_positions: Array[Vector3] = []
var _ground_effect_probe_nodes: Array[Node3D] = []
var _ground_effect_last_valid_probe_count: int = 0
var _ground_effect_last_average_clearance_m: float = -1.0
var _ground_effect_last_proximity: float = 0.0
var _ground_effect_last_multiplier: float = 1.0
var _ground_effect_last_up_world: Vector3 = Vector3.UP
var _ground_effect_last_force_world: Vector3 = Vector3.ZERO
var _ground_effect_definition_errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	super._ready()
	_load_ground_effect_definition()


func apply_flight_control_forces(
		field_online: bool,
		power_output: float,
		vector_angle_degrees: float,
		pitch_command: float,
		roll_command: float,
		yaw_command: float,
		vane_redistribution_fraction: float = 0.0,
		maximum_vane_output_multiplier: float = 1.2,
		delta_seconds: float = 0.0
) -> void:
	_ground_effect_last_force_world = Vector3.ZERO
	_ground_effect_last_valid_probe_count = 0
	_ground_effect_last_average_clearance_m = -1.0
	_ground_effect_last_proximity = 0.0
	_ground_effect_last_multiplier = 1.0

	# Keep the parent system as the sole owner of normal repulsorlift allocation.
	super.apply_flight_control_forces(
		field_online,
		power_output,
		vector_angle_degrees,
		pitch_command,
		roll_command,
		yaw_command,
		vane_redistribution_fraction,
		maximum_vane_output_multiplier,
		delta_seconds
	)

	if not _ground_effect_enabled or not field_online or _ship == null or _ship.freeze:
		return
	if _last_main_force.length_squared() <= MINIMUM_VECTOR_SQUARED:
		return

	var up_world: Vector3 = _get_local_up_world()
	if up_world.length_squared() <= MINIMUM_VECTOR_SQUARED:
		return
	_ground_effect_last_up_world = up_world

	var clearance_result: Dictionary = _sample_probe_clearances(up_world)
	_ground_effect_last_valid_probe_count = int(clearance_result.get("valid_probe_count", 0))
	_ground_effect_last_average_clearance_m = float(clearance_result.get("average_clearance_m", -1.0))
	if _ground_effect_last_valid_probe_count < _ground_effect_minimum_valid_probes:
		return

	_ground_effect_last_proximity = calculate_proximity_factor(
		_ground_effect_last_average_clearance_m,
		_ground_effect_footprint_width_m
	)
	if _ground_effect_last_proximity <= 0.0:
		return

	# Only force directed away from the local surface receives the gain.
	# Forward thrust and lateral/rotational control remain unchanged.
	var upward_main_force_n: float = maxf(_last_main_force.dot(up_world), 0.0)
	if upward_main_force_n <= 0.0:
		return
	_ground_effect_last_force_world = calculate_additional_force(
		_last_main_force,
		up_world,
		_ground_effect_gain,
		_ground_effect_last_proximity
	)
	_ground_effect_last_multiplier = 1.0 + _ground_effect_last_force_world.length() / upward_main_force_n

	_ship.apply_central_force(_ground_effect_last_force_world)
	_last_total_force += _ground_effect_last_force_world
	_last_vertical_twr = maxf(
		_last_total_force.dot(up_world), 0.0
	) / maxf(_ship.mass * _get_gravity_vector_world().length(), 0.0001)
	_last_force_vectors.append({
		"name": "GROUND EFFECT",
		"kind": "ground_effect",
		"force_world": _ground_effect_last_force_world,
		"application_point_world": _ship.global_position,
	})
	_update_force_debug(true)


func _load_ground_effect_definition() -> void:
	var result: Dictionary = ShipDefinitionLoader.load_file(DEFAULT_SHIP_DEFINITION_PATH)
	if not bool(result.get("valid", false)):
		_ground_effect_definition_errors = result.get("errors", PackedStringArray())
		push_warning("Ground effect disabled: prototype ship definition failed validation: %s" % "; ".join(_ground_effect_definition_errors))
		return

	var definition: ShipDefinition = result.get("definition") as ShipDefinition
	if definition == null:
		push_warning("Ground effect disabled: ship definition did not produce a ShipDefinition.")
		return
	var config: Dictionary = definition.ground_effect
	if config.is_empty() or not bool(config.get("enabled", false)):
		return

	_ground_effect_probe_anchor_names.clear()
	var anchors_variant: Variant = config.get("probe_anchors", [])
	if not (anchors_variant is Array) or anchors_variant.size() < 3:
		push_warning("Ground effect disabled: at least three probe_anchors are required.")
		return
	for anchor_variant: Variant in anchors_variant:
		var anchor_name: String = str(anchor_variant).strip_edges()
		if anchor_name.is_empty():
			push_warning("Ground effect disabled: probe anchor names cannot be empty.")
			return
		_ground_effect_probe_anchor_names.append(anchor_name)

	_ground_effect_footprint_width_m = maxf(float(config.get("footprint_width_m", 0.0)), 0.0)
	_ground_effect_gain = clampf(float(config.get("max_gain", 0.0)), 0.0, 1.0)
	_ground_effect_probe_start_offset_m = maxf(float(config.get("probe_ray_start_offset_m", 0.15)), 0.0)
	_ground_effect_minimum_valid_probes = clampi(
		int(config.get("minimum_valid_probes", 3)), 1, _ground_effect_probe_anchor_names.size()
	)
	_ground_effect_normal_alignment_min = clampf(float(config.get("surface_normal_alignment_min", 0.65)), 0.0, 1.0)
	_ground_effect_collision_mask = maxi(int(config.get("collision_mask", 1)), 0)
	if _ground_effect_footprint_width_m <= 0.0 or _ground_effect_gain <= 0.0 or _ground_effect_collision_mask == 0:
		return

	_build_probe_fallback_positions(definition)
	_resolve_probe_nodes()
	_ground_effect_enabled = true


func _build_probe_fallback_positions(definition: ShipDefinition) -> void:
	_ground_effect_probe_local_positions.clear()
	var dimensions_array: Array = definition.physics.get("dry_hull_dimensions_m", [3.6, 1.5, 5.2])
	var dimensions := Vector3(
		maxf(float(dimensions_array[0]), 0.1),
		maxf(float(dimensions_array[1]), 0.1),
		maxf(float(dimensions_array[2]), 0.1)
	)
	var x_extent: float = dimensions.x * 0.40
	var z_extent: float = dimensions.z * 0.40
	var y_bottom: float = -dimensions.y * 0.5
	var fallback_positions: Array[Vector3] = [
		Vector3(-x_extent, y_bottom, -z_extent),
		Vector3(x_extent, y_bottom, -z_extent),
		Vector3(-x_extent, y_bottom, z_extent),
		Vector3(x_extent, y_bottom, z_extent),
	]
	for index: int in range(_ground_effect_probe_anchor_names.size()):
		_ground_effect_probe_local_positions.append(fallback_positions[index % fallback_positions.size()])


func _resolve_probe_nodes() -> void:
	_ground_effect_probe_nodes.clear()
	for anchor_name: String in _ground_effect_probe_anchor_names:
		var anchor_node: Node3D = _ship.get_node_or_null(NodePath(anchor_name)) as Node3D
		_ground_effect_probe_nodes.append(anchor_node)


func _get_local_up_world() -> Vector3:
	if is_instance_valid(_planetary_gravity_body) and _planetary_gravity_body.has_method("get_planetary_reference_frame"):
		var frame: PlanetaryReferenceFrame = _planetary_gravity_body.call("get_planetary_reference_frame") as PlanetaryReferenceFrame
		if is_instance_valid(frame):
			var frame_data: Dictionary = frame.get_local_frame(_ship.global_position)
			var frame_up: Vector3 = frame_data.get("up_world", Vector3.UP)
			if frame_up.length_squared() > MINIMUM_VECTOR_SQUARED:
				return frame_up.normalized()
	var gravity: Vector3 = _get_gravity_vector_world()
	if gravity.length_squared() > MINIMUM_VECTOR_SQUARED:
		return -gravity.normalized()
	return Vector3.UP


func _sample_probe_clearances(up_world: Vector3) -> Dictionary:
	var valid_clearance_sum: float = 0.0
	var valid_probe_count: int = 0
	var world: World3D = _ship.get_world_3d()
	if world == null:
		return {"valid_probe_count": 0, "average_clearance_m": -1.0}
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var excluded: Array[RID] = [_ship.get_rid()]

	for index: int in range(_ground_effect_probe_anchor_names.size()):
		var probe_node: Node3D = _ground_effect_probe_nodes[index]
		var probe_position: Vector3 = (
			probe_node.global_position
			if is_instance_valid(probe_node)
			else _ship.global_transform * _ground_effect_probe_local_positions[index]
		)
		var probe_up: Vector3 = up_world
		if is_instance_valid(_planetary_gravity_body) and _planetary_gravity_body.has_method("get_planetary_reference_frame"):
			var frame: PlanetaryReferenceFrame = _planetary_gravity_body.call("get_planetary_reference_frame") as PlanetaryReferenceFrame
			if is_instance_valid(frame):
				var local_frame: Dictionary = frame.get_local_frame(probe_position)
				probe_up = local_frame.get("up_world", up_world).normalized()

		var ray_start: Vector3 = probe_position + probe_up * _ground_effect_probe_start_offset_m
		var ray_end: Vector3 = ray_start - probe_up * (_ground_effect_footprint_width_m + _ground_effect_probe_start_offset_m)
		var query := PhysicsRayQueryParameters3D.create(
			ray_start,
			ray_end,
			_ground_effect_collision_mask,
			excluded
		)
		query.hit_from_inside = false
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
		if hit_normal.length_squared() <= MINIMUM_VECTOR_SQUARED:
			continue
		if hit_normal.normalized().dot(probe_up) < _ground_effect_normal_alignment_min:
			continue
		var hit_position: Vector3 = hit.get("position", ray_end)
		var clearance_m: float = maxf((probe_position - hit_position).dot(probe_up), 0.0)
		valid_clearance_sum += clearance_m
		valid_probe_count += 1

	var average_clearance_m: float = valid_clearance_sum / float(valid_probe_count) if valid_probe_count > 0 else -1.0
	return {"valid_probe_count": valid_probe_count, "average_clearance_m": average_clearance_m}


## Smooth proximity curve: 1 at the surface, 0 at/above fade_distance.
static func calculate_proximity_factor(clearance_m: float, fade_distance_m: float) -> float:
	if fade_distance_m <= 0.0 or clearance_m < 0.0:
		return 0.0
	var t: float = clampf(clearance_m / fade_distance_m, 0.0, 1.0)
	return 1.0 - (t * t * (3.0 - 2.0 * t))


## Returns only the extra force along surface-up; tangential thrust is untouched.
static func calculate_additional_force(
		main_force_world: Vector3,
		up_world: Vector3,
		maximum_gain: float,
		proximity: float
) -> Vector3:
	if up_world.length_squared() <= MINIMUM_VECTOR_SQUARED:
		return Vector3.ZERO
	var up: Vector3 = up_world.normalized()
	var upward_force_n: float = maxf(main_force_world.dot(up), 0.0)
	var gain: float = clampf(maximum_gain, 0.0, 1.0) * clampf(proximity, 0.0, 1.0)
	return up * upward_force_n * gain


func get_telemetry() -> Dictionary:
	var telemetry: Dictionary = super.get_telemetry()
	telemetry.merge({
		"ground_effect_enabled": _ground_effect_enabled,
		"ground_effect_probe_anchor_names": _ground_effect_probe_anchor_names,
		"ground_effect_valid_probe_count": _ground_effect_last_valid_probe_count,
		"ground_effect_minimum_valid_probes": _ground_effect_minimum_valid_probes,
		"ground_effect_average_clearance_m": _ground_effect_last_average_clearance_m,
		"ground_effect_footprint_width_m": _ground_effect_footprint_width_m,
		"ground_effect_proximity": _ground_effect_last_proximity,
		"ground_effect_max_gain": _ground_effect_gain,
		"ground_effect_multiplier": _ground_effect_last_multiplier,
		"ground_effect_up_world": _ground_effect_last_up_world,
		"ground_effect_force_world": _ground_effect_last_force_world,
		"ground_effect_force_n": _ground_effect_last_force_world.length(),
		"ground_effect_definition_errors": _ground_effect_definition_errors,
	}, true)
	return telemetry
