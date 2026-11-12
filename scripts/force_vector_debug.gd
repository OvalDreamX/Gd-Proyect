extends Node3D
class_name ForceVectorDebug

## Draws the actual force resultants submitted to the ship's RigidBody3D.
## Arrow start = world application point; arrow length = force magnitude.
## Enabled only by the F3 debug overview.

@export_category("Arrow display")
@export_range(2.0, 20.0, 0.5) var arrow_length_per_twr_m: float = 12.0
@export_range(1.0, 15.0, 0.5) var maximum_arrow_length_m: float = 8.0
@export_range(0.02, 0.5, 0.01) var minimum_arrow_length_m: float = 0.08

var _immediate_mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _materials: Dictionary = {}


func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ForceArrows"
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	visible = false
	_materials["main"] = _make_material(Color(0.25, 0.9, 1.0, 1.0))
	_materials["pitch"] = _make_material(Color(0.35, 1.0, 0.45, 1.0))
	_materials["roll"] = _make_material(Color(1.0, 0.8, 0.2, 1.0))
	_materials["yaw"] = _make_material(Color(1.0, 0.35, 0.85, 1.0))
	_materials["ground_effect"] = _make_material(Color(1.0, 0.42, 0.12, 1.0))


func update_force_vectors(
		force_vectors: Array[Dictionary],
		ship_global_transform: Transform3D,
		reference_force_newtons: float
) -> void:
	if not visible or not is_instance_valid(_immediate_mesh):
		return

	_immediate_mesh.clear_surfaces()
	var body_inverse: Transform3D = ship_global_transform.affine_inverse()
	var safe_reference_force: float = maxf(reference_force_newtons, 1.0)

	_draw_category("main", force_vectors, body_inverse, safe_reference_force)
	_draw_category("pitch", force_vectors, body_inverse, safe_reference_force)
	_draw_category("roll", force_vectors, body_inverse, safe_reference_force)
	_draw_category("yaw", force_vectors, body_inverse, safe_reference_force)
	_draw_category("ground_effect", force_vectors, body_inverse, safe_reference_force)


func _draw_category(
		kind: String,
		force_vectors: Array[Dictionary],
		body_inverse: Transform3D,
		reference_force_newtons: float
) -> void:
	var matching_entries: Array[Dictionary] = []
	for force_entry in force_vectors:
		if str(force_entry.get("kind", "")) == kind:
			var force_world: Vector3 = force_entry.get("force_world", Vector3.ZERO)
			if force_world.length_squared() > 0.000001:
				matching_entries.append(force_entry)
	if matching_entries.is_empty():
		return

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _materials[kind])
	for force_entry in matching_entries:
		var force_world: Vector3 = force_entry.get("force_world", Vector3.ZERO)
		var application_point_world: Vector3 = force_entry.get("application_point_world", Vector3.ZERO)
		var start_local: Vector3 = body_inverse * application_point_world
		var direction_world: Vector3 = force_world.normalized()
		var direction_local: Vector3 = (body_inverse.basis * direction_world).normalized()
		var force_twr_equivalent: float = force_world.length() / reference_force_newtons
		var arrow_length: float = clampf(
			force_twr_equivalent * arrow_length_per_twr_m,
			minimum_arrow_length_m,
			maximum_arrow_length_m
		)
		_draw_arrow(start_local, direction_local, arrow_length)
	_immediate_mesh.surface_end()


func _draw_arrow(start: Vector3, direction: Vector3, length: float) -> void:
	var end: Vector3 = start + direction * length
	_immediate_mesh.surface_add_vertex(start)
	_immediate_mesh.surface_add_vertex(end)

	var reference_axis: Vector3 = Vector3.UP
	if absf(direction.dot(reference_axis)) > 0.92:
		reference_axis = Vector3.RIGHT
	var side: Vector3 = direction.cross(reference_axis).normalized()
	var up: Vector3 = direction.cross(side).normalized()
	var head_length: float = minf(length * 0.28, 0.38)
	var head_width: float = head_length * 0.45
	var head_base: Vector3 = end - direction * head_length

	_immediate_mesh.surface_add_vertex(end)
	_immediate_mesh.surface_add_vertex(head_base + side * head_width)
	_immediate_mesh.surface_add_vertex(end)
	_immediate_mesh.surface_add_vertex(head_base - side * head_width)
	_immediate_mesh.surface_add_vertex(end)
	_immediate_mesh.surface_add_vertex(head_base + up * head_width)
	_immediate_mesh.surface_add_vertex(end)
	_immediate_mesh.surface_add_vertex(head_base - up * head_width)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material
