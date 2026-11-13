extends RefCounted
class_name ShipModelValidator

## Structural validation for a generated GLB scene. This class deliberately
## validates only the asset contract; gameplay-specific required anchors are
## checked by the owning subsystem when those integrations are added.

const ANCHOR_PREFIX: String = "ANCHOR_"
const MESH_PREFIX: String = "MESH_"
const INTERACT_PREFIX: String = "INTERACT_"


static func validate_model_root(model_root: Node) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var anchors: Dictionary = {}
	var counts: Dictionary = {
		"mesh_count": 0,
		"named_mesh_count": 0,
		"interaction_count": 0,
		"skeleton_count": 0,
	}

	if model_root == null:
		errors.append("Generated model root is null.")
		return _make_result(errors, warnings, anchors, counts)
	if not model_root is Node3D:
		errors.append("GLB scene root must be Node3D; received %s." % model_root.get_class())
		return _make_result(errors, warnings, anchors, counts)

	if String(model_root.name) != "SHIP_root":
		warnings.append("Model root is named %s; the contract name is SHIP_root." % String(model_root.name))

	_scan_node(model_root, anchors, errors, warnings, counts)

	if int(counts["mesh_count"]) == 0:
		warnings.append("Model contains no MeshInstance3D nodes; it may be intentionally invisible.")
	if int(counts["skeleton_count"]) > 1:
		warnings.append("Model contains multiple Skeleton3D nodes; the ship standard expects one shared armature.")
	if anchors.is_empty():
		warnings.append("Model contains no ANCHOR_ nodes.")

	return _make_result(errors, warnings, anchors, counts)


static func _scan_node(
		node: Node,
		anchors: Dictionary,
		errors: Array[String],
		warnings: Array[String],
		counts: Dictionary
) -> void:
	var node_name: String = String(node.name)

	if node is MeshInstance3D:
		counts["mesh_count"] = int(counts["mesh_count"]) + 1
	if node is Skeleton3D:
		counts["skeleton_count"] = int(counts["skeleton_count"]) + 1

	if node_name.begins_with(ANCHOR_PREFIX):
		var anchor_id: String = node_name.substr(ANCHOR_PREFIX.length())
		if not node is Node3D:
			errors.append("%s must be a Node3D (normally exported from a Blender Empty)." % node_name)
		elif not _is_valid_identifier(anchor_id):
			errors.append("Invalid anchor name '%s'; use ANCHOR_lowercase_snake_case." % node_name)
		elif anchors.has(anchor_id):
			errors.append("Duplicate anchor identifier '%s'." % anchor_id)
		else:
			anchors[anchor_id] = node

	if node_name.begins_with(MESH_PREFIX):
		if not node is MeshInstance3D:
			errors.append("%s must import as MeshInstance3D." % node_name)
		else:
			counts["named_mesh_count"] = int(counts["named_mesh_count"]) + 1

	if node_name.begins_with(INTERACT_PREFIX):
		var interaction_id: String = node_name.substr(INTERACT_PREFIX.length())
		if not node is Node3D:
			errors.append("%s must import as Node3D." % node_name)
		elif not _is_valid_interaction_identifier(interaction_id):
			errors.append("Invalid interaction name '%s'; expected switch_*, lever_* or button_*." % node_name)
		elif not _contains_mesh_instance(node):
			errors.append("%s has no MeshInstance3D visual child; add the visible control beneath its pivot node." % node_name)
		else:
			counts["interaction_count"] = int(counts["interaction_count"]) + 1

	for child: Node in node.get_children():
		_scan_node(child, anchors, errors, warnings, counts)


static func _contains_mesh_instance(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child: Node in node.get_children():
		if _contains_mesh_instance(child):
			return true
	return false


static func _is_valid_interaction_identifier(identifier: String) -> bool:
	return (
		(identifier.begins_with("switch_")
		or identifier.begins_with("lever_")
		or identifier.begins_with("button_"))
		and _is_valid_identifier(identifier)
	)


static func _is_valid_identifier(identifier: String) -> bool:
	if identifier.is_empty() or identifier.begins_with("_") or identifier.ends_with("_") or identifier.contains("__"):
		return false
	for character: String in identifier:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"):
			return false
	return true


static func _make_result(
		errors: Array[String],
		warnings: Array[String],
		anchors: Dictionary,
		counts: Dictionary
) -> Dictionary:
	return {
		"valid": errors.is_empty(),
		"errors": PackedStringArray(errors),
		"warnings": PackedStringArray(warnings),
		"anchors": anchors.duplicate(),
		"mesh_count": int(counts["mesh_count"]),
		"named_mesh_count": int(counts["named_mesh_count"]),
		"interaction_count": int(counts["interaction_count"]),
		"skeleton_count": int(counts["skeleton_count"]),
	}
