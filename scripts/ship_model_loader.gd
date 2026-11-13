extends RefCounted
class_name ShipModelLoader

## Loads a GLB directly from res:// or user:// at runtime.
## The returned model_root is unparented; the caller owns its lifetime.

const MODEL_VALIDATOR_SCRIPT = preload("res://scripts/ship_model_validator.gd")
const ANCHOR_REGISTRY_SCRIPT = preload("res://scripts/ship_anchor_registry.gd")


static func load_glb(path: String) -> Dictionary:
	var path_error: String = validate_model_path(path)
	if not path_error.is_empty():
		return _failure(path_error)
	if not FileAccess.file_exists(path):
		return _failure("Model file does not exist: %s" % path)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var import_error: Error = document.append_from_file(path, state)
	if import_error != OK:
		return _failure("GLB import failed for '%s': %s" % [path, error_string(import_error)])

	var generated_root: Node = document.generate_scene(state)
	if generated_root == null:
		return _failure("GLB import succeeded but Godot could not generate a scene for '%s'." % path)

	var validation: Dictionary = MODEL_VALIDATOR_SCRIPT.validate_model_root(generated_root)
	if not bool(validation.get("valid", false)):
		generated_root.free()
		return {
			"success": false,
			"model_root": null,
			"errors": validation.get("errors", PackedStringArray()),
			"warnings": validation.get("warnings", PackedStringArray()),
		}

	var registry := ANCHOR_REGISTRY_SCRIPT.new() as ShipAnchorRegistry
	var registry_result: Dictionary = registry.rebuild(generated_root)
	if not bool(registry_result.get("valid", false)):
		generated_root.free()
		return {
			"success": false,
			"model_root": null,
			"errors": registry_result.get("errors", PackedStringArray()),
			"warnings": registry_result.get("warnings", PackedStringArray()),
		}

	return {
		"success": true,
		"model_root": generated_root,
		"anchor_registry": registry,
		"errors": PackedStringArray(),
		"warnings": validation.get("warnings", PackedStringArray()),
		"mesh_count": int(validation.get("mesh_count", 0)),
		"anchor_count": registry.get_anchor_names().size(),
		"interaction_count": int(validation.get("interaction_count", 0)),
		"skeleton_count": int(validation.get("skeleton_count", 0)),
	}


static func validate_model_path(path: String) -> String:
	var candidate: String = path.strip_edges()
	if candidate.is_empty():
		return "Model path is empty."
	if candidate != path:
		return "Model path must not contain leading or trailing whitespace."
	if candidate.contains("\\"):
		return "Model path must use forward slashes."
	if not (candidate.begins_with("res://") or candidate.begins_with("user://")):
		return "Model path must begin with res:// or user://."
	if not candidate.to_lower().ends_with(".glb"):
		return "Ship model path must use the .glb extension."

	var relative_path: String = candidate.substr(6) if candidate.begins_with("res://") else candidate.substr(7)
	for segment: String in relative_path.split("/", true):
		if segment == ".." or segment == "." or segment.is_empty():
			return "Model path contains an unsafe or empty path segment."
	return ""


static func _failure(message: String) -> Dictionary:
	return {
		"success": false,
		"model_root": null,
		"errors": PackedStringArray([message]),
		"warnings": PackedStringArray(),
	}
