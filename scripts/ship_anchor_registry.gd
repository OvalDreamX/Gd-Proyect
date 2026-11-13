extends RefCounted
class_name ShipAnchorRegistry

## Runtime lookup for Blender-authored ANCHOR_ nodes.
## Keys are the identifier after the ANCHOR_ prefix, e.g. "pilot_seat".

const MODEL_VALIDATOR_SCRIPT = preload("res://scripts/ship_model_validator.gd")

var _anchors: Dictionary = {}


func rebuild(model_root: Node) -> Dictionary:
	_anchors.clear()
	var validation: Dictionary = MODEL_VALIDATOR_SCRIPT.validate_model_root(model_root)
	if not bool(validation.get("valid", false)):
		return {
			"valid": false,
			"errors": validation.get("errors", PackedStringArray()),
			"warnings": validation.get("warnings", PackedStringArray()),
		}

	var discovered: Dictionary = validation.get("anchors", {})
	for anchor_id: Variant in discovered:
		var anchor_node: Node3D = discovered[anchor_id] as Node3D
		if is_instance_valid(anchor_node):
			_anchors[String(anchor_id)] = anchor_node

	return {
		"valid": true,
		"errors": PackedStringArray(),
		"warnings": validation.get("warnings", PackedStringArray()),
		"anchor_count": _anchors.size(),
	}


func has_anchor(anchor_id_or_name: String) -> bool:
	return _anchors.has(_normalize_anchor_id(anchor_id_or_name))


func get_anchor(anchor_id_or_name: String) -> Node3D:
	var anchor_id: String = _normalize_anchor_id(anchor_id_or_name)
	var value: Variant = _anchors.get(anchor_id)
	if value is Node3D and is_instance_valid(value):
		return value as Node3D
	return null


func get_anchor_names() -> PackedStringArray:
	var names := PackedStringArray()
	for anchor_id: Variant in _anchors.keys():
		names.append(String(anchor_id))
	names.sort()
	return names


func get_missing_anchors(required_ids_or_names: PackedStringArray) -> PackedStringArray:
	var missing := PackedStringArray()
	for requested_name: String in required_ids_or_names:
		var anchor_id: String = _normalize_anchor_id(requested_name)
		if not _anchors.has(anchor_id):
			missing.append(anchor_id)
	return missing


func clear() -> void:
	_anchors.clear()


func _normalize_anchor_id(anchor_id_or_name: String) -> String:
	if anchor_id_or_name.begins_with("ANCHOR_"):
		return anchor_id_or_name.substr("ANCHOR_".length())
	return anchor_id_or_name
