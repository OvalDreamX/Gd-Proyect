extends Node

## Discovers Blender-authored INTERACT_* pivots and builds data-only hit areas.
## No scripts from a mounted/modded model are loaded or executed. Every request
## is dispatched through the fixed ShipFlightController allowlist.

signal interaction_requested(interaction_id: StringName, interaction_kind: StringName, value: float)
signal interaction_dispatched(interaction_id: StringName, interaction_kind: StringName, value: float)
signal interaction_failed(interaction_id: StringName, reason: String)

const INTERACTION_PREFIX: String = "INTERACT_"
const HIT_AREA_NAME: StringName = &"GeneratedHitArea"
const HIT_SHAPE_NAME: StringName = &"CollisionShape3D"
const META_INTERACTION_ID: StringName = &"ship_interaction_id"
const META_GENERATED_HIT_AREA: StringName = &"ship_generated_interaction_hit_area"
const DEFAULT_INTERACTION_LAYER: int = 1 << 19
const SUPPORTED_CONTROL_IDS: Array[String] = [
	"switch_main_power",
	"switch_field_assist",
	"lever_throttle",
	"lever_vector_angle",
]

@export_category("Node paths")
@export var model_mount_path: NodePath = NodePath("../Visuals/Exterior/ModelMount")
@export var flight_controller_path: NodePath = NodePath("../FlightController")

@export_category("Generated hit areas")
## Dedicated physics layer used only by cockpit interaction hit areas.
## Ray queries should use this layer and set collide_with_areas=true.
@export_range(1, 2147483647, 1) var interaction_collision_layer: int = DEFAULT_INTERACTION_LAYER
@export_range(0.0, 0.5, 0.01) var hitbox_padding_m: float = 0.08
@export var minimum_hitbox_size_m: Vector3 = Vector3(0.08, 0.08, 0.08)
@export_range(0.5, 30.0, 0.5) var raycast_distance_m: float = 8.0

var _model_root: Node = null
var _entries: Dictionary = {}
var _generated_areas: Array[Area3D] = []
var _status: Dictionary = {
	"state": "not_initialized",
	"valid": false,
	"model_available": false,
	"interaction_count": 0,
	"hit_area_count": 0,
	"interaction_ids": PackedStringArray(),
	"unbound_ids": PackedStringArray(),
	"warnings": PackedStringArray(),
	"errors": PackedStringArray(),
}


func _ready() -> void:
	# ShipModelMount loads during its own _ready(). Deferring ensures the mount,
	# animation controller and flight controller have all completed setup.
	call_deferred("refresh_from_mount")


## Re-discovers the mounted model. Call this after an explicit model reload.
func refresh_from_mount() -> Dictionary:
	var mount: Node = get_node_or_null(model_mount_path)
	if mount == null or not mount.has_method("get_model_root"):
		return configure_from_model(null)
	var model_variant: Variant = mount.call("get_model_root")
	if not (model_variant is Node):
		return configure_from_model(null)
	return configure_from_model(model_variant as Node)


## Test/modding entry point. The model remains data-only: only Node3D pivots and
## visible MeshInstance3D bounds are inspected.
func configure_from_model(model_root: Node) -> Dictionary:
	_clear_generated_areas()
	_entries.clear()
	_model_root = model_root

	if not is_instance_valid(_model_root):
		return _set_status(
			"waiting_for_model",
			true,
			false,
			[],
			["No validated ship model is currently mounted."]
		)

	var candidates: Array[Dictionary] = []
	var errors: Array[String] = []
	var warnings: Array[String] = []
	_collect_interaction_candidates(_model_root, candidates)
	if candidates.is_empty():
		return _set_status(
			"no_interactions",
			true,
			true,
			[],
			["No INTERACT_* nodes were found; the ship remains usable with its existing controls."]
		)

	var id_counts: Dictionary = {}
	for candidate: Dictionary in candidates:
		var candidate_id: String = str(candidate.get("id", ""))
		id_counts[candidate_id] = int(id_counts.get(candidate_id, 0)) + 1

	for candidate: Dictionary in candidates:
		var interaction_id: String = str(candidate.get("id", ""))
		if int(id_counts.get(interaction_id, 0)) > 1:
			errors.append("Duplicate interaction ID '%s'; all nodes with this ID were skipped." % interaction_id)
			continue

		var kind: String = str(candidate.get("kind", ""))
		if kind.is_empty():
			errors.append("Interaction ID '%s' must begin with switch_, lever_ or button_ and use lowercase snake_case." % interaction_id)
			continue

		var interaction_node: Node3D = candidate.get("node") as Node3D
		if not is_instance_valid(interaction_node):
			errors.append("Interaction '%s' is not a Node3D pivot." % interaction_id)
			continue

		var mesh_nodes: Array[MeshInstance3D] = []
		_collect_renderable_meshes(interaction_node, mesh_nodes)
		if mesh_nodes.is_empty():
			errors.append("Interaction '%s' has no renderable MeshInstance3D descendants." % interaction_id)
			continue

		var bounds_result: Dictionary = _calculate_local_mesh_bounds(interaction_node, mesh_nodes)
		if not bool(bounds_result.get("valid", false)):
			errors.append("Interaction '%s' has no usable mesh bounds." % interaction_id)
			continue

		var bounds: AABB = bounds_result.get("bounds", AABB())
		var hit_area: Area3D = _create_hit_area(interaction_node, interaction_id, bounds)
		if not is_instance_valid(hit_area):
			errors.append("Interaction '%s' could not create its runtime hit area." % interaction_id)
			continue

		_entries[interaction_id] = {
			"id": interaction_id,
			"kind": kind,
			"node": interaction_node,
			"hit_area": hit_area,
			"mesh_count": mesh_nodes.size(),
			"hitbox_size": bounds.size,
		}
		if not SUPPORTED_CONTROL_IDS.has(interaction_id):
			warnings.append(
				"Interaction '%s' has no built-in gameplay binding; its hit area is available for future systems." % interaction_id
			)

	var state: String = "ready" if errors.is_empty() else "partial"
	if _entries.is_empty() and not errors.is_empty():
		state = "invalid_interactions"
	return _set_status(state, errors.is_empty(), true, errors, warnings)


func get_interaction_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id_variant: Variant in _entries.keys():
		ids.append(String(id_variant))
	ids.sort()
	return ids


func get_interaction_info(interaction_id: String) -> Dictionary:
	var normalized_id: String = interaction_id.strip_edges()
	if normalized_id.begins_with(INTERACTION_PREFIX):
		normalized_id = normalized_id.substr(INTERACTION_PREFIX.length())
	if not _entries.has(normalized_id):
		return {}
	var entry: Dictionary = _entries[normalized_id].duplicate()
	entry["bound"] = _is_control_bound(normalized_id)
	return entry


func get_interaction_status() -> Dictionary:
	var result: Dictionary = _status.duplicate(true)
	result["interaction_ids"] = get_interaction_ids()
	result["interaction_count"] = _entries.size()
	result["hit_area_count"] = _generated_areas.size()
	return result


## Ray-tests only the dedicated interaction layer. The ray queries Area3D
## objects, not the ship's rigid body or the normal collision geometry.
func pick_interaction_from_camera(
		camera: Camera3D,
		screen_position: Vector2,
		max_distance: float = -1.0
) -> Dictionary:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return {}
	var world: World3D = camera.get_world_3d()
	if not is_instance_valid(world):
		return {}
	var distance: float = raycast_distance_m if max_distance <= 0.0 else max_distance
	if not is_finite(distance) or distance <= 0.0:
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen_position) * distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		interaction_collision_layer
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.hit_from_inside = true
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider_variant: Variant = hit.get("collider")
	if not (collider_variant is Area3D):
		return {}
	var area: Area3D = collider_variant as Area3D
	if not area.has_meta(META_INTERACTION_ID):
		return {}
	var interaction_id: String = str(area.get_meta(META_INTERACTION_ID, ""))
	if not _entries.has(interaction_id):
		return {}
	var entry: Dictionary = _entries[interaction_id]
	return {
		"interaction_id": interaction_id,
		"kind": StringName(str(entry.get("kind", ""))),
		"position": hit.get("position", Vector3.ZERO),
		"normal": hit.get("normal", Vector3.ZERO),
		"distance": ray_origin.distance_to(hit.get("position", ray_origin)),
	}


## Convenience for switches/buttons. Lever values are set explicitly through
## set_interaction_value() so a click cannot unexpectedly slam a lever to 100%.
func interact_at_screen_position(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	var hit: Dictionary = pick_interaction_from_camera(camera, screen_position)
	if hit.is_empty():
		return {"hit": false, "dispatched": false}
	var interaction_id: String = str(hit.get("interaction_id", ""))
	var entry: Dictionary = _entries.get(interaction_id, {})
	if str(entry.get("kind", "")) == "lever":
		hit["hit"] = true
		hit["dispatched"] = false
		hit["reason"] = "lever_requires_value"
		return hit
	hit["hit"] = true
	hit["dispatched"] = activate_interaction(interaction_id)
	return hit


func activate_interaction(interaction_id: String) -> bool:
	var normalized_id: String = _normalize_interaction_id(interaction_id)
	if not _entries.has(normalized_id):
		return _reject(normalized_id, "Interaction was not discovered or validated.")
	var entry: Dictionary = _entries[normalized_id]
	var kind: String = str(entry.get("kind", ""))
	if kind == "lever":
		return _reject(normalized_id, "Lever controls require set_interaction_value().")
	if kind != "switch" and kind != "button":
		return _reject(normalized_id, "Unsupported interaction kind '%s'." % kind)
	return _dispatch_control(normalized_id, kind, 1.0)


## Sets a lever with a normalized value in [0, 1]. The flight-controller bridge
## maps that value to the existing field-power or vector-distribution range.
func set_interaction_value(interaction_id: String, normalized_value: float) -> bool:
	var normalized_id: String = _normalize_interaction_id(interaction_id)
	if not _entries.has(normalized_id):
		return _reject(normalized_id, "Interaction was not discovered or validated.")
	var entry: Dictionary = _entries[normalized_id]
	if str(entry.get("kind", "")) != "lever":
		return _reject(normalized_id, "Only lever controls accept continuous values.")
	if not is_finite(normalized_value):
		return _reject(normalized_id, "Lever value must be finite.")
	return _dispatch_control(normalized_id, "lever", clampf(normalized_value, 0.0, 1.0))


func _dispatch_control(interaction_id: String, kind: String, value: float) -> bool:
	interaction_requested.emit(StringName(interaction_id), StringName(kind), value)
	var flight_controller: Node = get_node_or_null(flight_controller_path)
	if flight_controller == null or not flight_controller.has_method("request_cockpit_control"):
		return _reject(interaction_id, "ShipFlightController does not expose request_cockpit_control().")
	var accepted: bool = bool(
		flight_controller.call("request_cockpit_control", StringName(interaction_id), value)
	)
	if not accepted:
		return _reject(
			interaction_id,
			"The bound ship system rejected this request (pilot unavailable, system unavailable, or control unbound)."
		)
	interaction_dispatched.emit(StringName(interaction_id), StringName(kind), value)
	return true


func _reject(interaction_id: String, reason: String) -> bool:
	interaction_failed.emit(StringName(interaction_id), reason)
	return false


func _is_control_bound(interaction_id: String) -> bool:
	if not SUPPORTED_CONTROL_IDS.has(interaction_id):
		return false
	var flight_controller: Node = get_node_or_null(flight_controller_path)
	return flight_controller != null and flight_controller.has_method("request_cockpit_control")


func _normalize_interaction_id(interaction_id: String) -> String:
	var normalized: String = interaction_id.strip_edges()
	if normalized.begins_with(INTERACTION_PREFIX):
		normalized = normalized.substr(INTERACTION_PREFIX.length())
	return normalized


func _collect_interaction_candidates(node: Node, output: Array[Dictionary]) -> void:
	var full_name: String = String(node.name)
	if full_name.begins_with(INTERACTION_PREFIX):
		var interaction_id: String = full_name.substr(INTERACTION_PREFIX.length())
		var kind: String = _interaction_kind(interaction_id)
		if kind.is_empty() or not _is_valid_identifier(interaction_id):
			output.append({"id": interaction_id, "kind": "", "node": node})
		else:
			output.append({"id": interaction_id, "kind": kind, "node": node})
	for child: Node in node.get_children():
		_collect_interaction_candidates(child, output)


func _collect_renderable_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if is_instance_valid(mesh_instance.mesh) and mesh_instance.mesh.get_surface_count() > 0:
			output.append(mesh_instance)
	for child: Node in node.get_children():
		# Do not let a generated collider or nested control contribute to the
		# bounds of its parent interaction.
		if child is Area3D and child.has_meta(META_GENERATED_HIT_AREA):
			continue
		if String(child.name).begins_with(INTERACTION_PREFIX):
			continue
		_collect_renderable_meshes(child, output)


func _calculate_local_mesh_bounds(
		interaction_node: Node3D,
		mesh_nodes: Array[MeshInstance3D]
) -> Dictionary:
	var has_bounds: bool = false
	var combined_bounds: AABB = AABB()
	var interaction_inverse: Transform3D = interaction_node.global_transform.affine_inverse()
	for mesh_instance: MeshInstance3D in mesh_nodes:
		if not is_instance_valid(mesh_instance) or not is_instance_valid(mesh_instance.mesh):
			continue
		var mesh_bounds: AABB = mesh_instance.get_aabb()
		var mesh_to_interaction: Transform3D = interaction_inverse * mesh_instance.global_transform
		var transformed_bounds: AABB = _transform_aabb(mesh_bounds, mesh_to_interaction)
		if not has_bounds:
			combined_bounds = transformed_bounds
			has_bounds = true
		else:
			combined_bounds = combined_bounds.merge(transformed_bounds)
	if not has_bounds:
		return {"valid": false, "bounds": AABB()}

	combined_bounds = combined_bounds.grow(maxf(hitbox_padding_m, 0.0))
	var size: Vector3 = combined_bounds.size
	var minimum_size := Vector3(
		maxf(minimum_hitbox_size_m.x, 0.01),
		maxf(minimum_hitbox_size_m.y, 0.01),
		maxf(minimum_hitbox_size_m.z, 0.01)
	)
	var safe_size := Vector3(
		maxf(size.x, minimum_size.x),
		maxf(size.y, minimum_size.y),
		maxf(size.z, minimum_size.z)
	)
	combined_bounds = AABB(combined_bounds.get_center() - safe_size * 0.5, safe_size)
	return {"valid": true, "bounds": combined_bounds}


func _transform_aabb(source: AABB, transform: Transform3D) -> AABB:
	var x0: float = source.position.x
	var y0: float = source.position.y
	var z0: float = source.position.z
	var x1: float = source.end.x
	var y1: float = source.end.y
	var z1: float = source.end.z
	var corners: Array[Vector3] = [
		Vector3(x0, y0, z0),
		Vector3(x0, y0, z1),
		Vector3(x0, y1, z0),
		Vector3(x0, y1, z1),
		Vector3(x1, y0, z0),
		Vector3(x1, y0, z1),
		Vector3(x1, y1, z0),
		Vector3(x1, y1, z1),
	]
	var result: AABB = AABB()
	var first_point: bool = true
	for corner: Vector3 in corners:
		var transformed_point: Vector3 = transform * corner
		if first_point:
			result = AABB(transformed_point, Vector3.ZERO)
			first_point = false
		else:
			result = result.expand(transformed_point)
	return result


func _create_hit_area(interaction_node: Node3D, interaction_id: String, bounds: AABB) -> Area3D:
	var area := Area3D.new()
	area.name = HIT_AREA_NAME
	area.collision_layer = interaction_collision_layer if interaction_collision_layer > 0 else DEFAULT_INTERACTION_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.input_ray_pickable = true
	area.set_meta(META_INTERACTION_ID, interaction_id)
	area.set_meta(META_GENERATED_HIT_AREA, true)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = HIT_SHAPE_NAME
	var box_shape := BoxShape3D.new()
	box_shape.size = bounds.size
	collision_shape.shape = box_shape
	area.position = bounds.get_center()
	area.add_child(collision_shape)
	interaction_node.add_child(area)
	_generated_areas.append(area)
	return area


func _clear_generated_areas() -> void:
	for area: Area3D in _generated_areas:
		if is_instance_valid(area) and is_instance_valid(area.get_parent()):
			area.get_parent().remove_child(area)
			area.queue_free()
	_generated_areas.clear()


func _set_status(
		state: String,
		valid: bool,
		model_available: bool,
		errors: Array[String],
		warnings: Array[String]
) -> Dictionary:
	var ids := PackedStringArray()
	var unbound := PackedStringArray()
	for id_variant: Variant in _entries.keys():
		var interaction_id: String = String(id_variant)
		ids.append(interaction_id)
		if not _is_control_bound(interaction_id):
			unbound.append(interaction_id)
	ids.sort()
	unbound.sort()
	_status = {
		"state": state,
		"valid": valid,
		"model_available": model_available,
		"interaction_count": _entries.size(),
		"hit_area_count": _generated_areas.size(),
		"interaction_ids": ids,
		"unbound_ids": unbound,
		"warnings": PackedStringArray(warnings),
		"errors": PackedStringArray(errors),
	}
	return _status.duplicate(true)


func _interaction_kind(interaction_id: String) -> String:
	if interaction_id.begins_with("switch_"):
		return "switch"
	if interaction_id.begins_with("lever_"):
		return "lever"
	if interaction_id.begins_with("button_"):
		return "button"
	return ""


func _is_valid_identifier(identifier: String) -> bool:
	if identifier.is_empty() or identifier.begins_with("_") or identifier.ends_with("_") or identifier.contains("__"):
		return false
	for character: String in identifier:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character == "_"
		):
			return false
	return true
