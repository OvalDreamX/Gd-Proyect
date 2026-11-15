extends Node3D
class_name ShipModelMount

## Loads the ship's JSON-selected GLB under this mount. The sibling placeholder
## remains visible unless import and structural validation both succeed.
## Physics, collision, pilot-seat and flight-system nodes are not modified here.

const DEFINITION_LOADER_SCRIPT = preload("res://scripts/ship_definition_loader.gd")
const MODEL_LOADER_SCRIPT = preload("res://scripts/ship_model_loader.gd")

@export_category("Ship asset")
@export_file("*.json") var ship_definition_path: String = "res://data/ships/prototype_freighter/ship.json"
@export var placeholder_node_path: NodePath = NodePath("../PlaceholderModel")

var _load_state: String = "not_started"
var _resolved_model_path: String = ""
var _last_error: String = ""
var _warnings: PackedStringArray = PackedStringArray()
var _model_root: Node3D = null
var _anchor_registry: RefCounted = null
var _model_stats: Dictionary = {}

@onready var _placeholder_model: Node3D = get_node_or_null(placeholder_node_path) as Node3D


func _ready() -> void:
	if is_instance_valid(_placeholder_model):
		_placeholder_model.visible = true
	_load_from_definition()


func _load_from_definition() -> void:
	_load_state = "loading_definition"
	_last_error = ""
	_warnings.clear()
	_model_stats.clear()
	if not FileAccess.file_exists(ship_definition_path):
		_set_fallback("fallback_missing_definition", "Ship definition does not exist: %s" % ship_definition_path, true)
		return

	var definition_result: Dictionary = DEFINITION_LOADER_SCRIPT.load_file(ship_definition_path)
	if not bool(definition_result.get("valid", false)):
		_set_fallback("fallback_invalid_definition", "; ".join(definition_result.get("errors", PackedStringArray())), false)
		return
	var definition: ShipDefinition = definition_result.get("definition") as ShipDefinition
	if not is_instance_valid(definition):
		_set_fallback("fallback_invalid_definition", "Definition loader returned no ShipDefinition.", false)
		return

	var relative_model_path: String = definition.model_path
	_resolved_model_path = ship_definition_path.get_base_dir().path_join(relative_model_path)
	var path_error: String = MODEL_LOADER_SCRIPT.validate_model_path(_resolved_model_path)
	if not path_error.is_empty():
		_set_fallback("fallback_invalid_model_path", path_error, false)
		return
	if not FileAccess.file_exists(_resolved_model_path):
		_set_fallback(
			"fallback_missing_model",
			"Model file is not present: %s" % _resolved_model_path,
			true
		)
		return

	var model_result: Dictionary = MODEL_LOADER_SCRIPT.load_glb(_resolved_model_path)
	_warnings = model_result.get("warnings", PackedStringArray()).duplicate()
	if not bool(model_result.get("success", false)):
		_set_fallback("fallback_invalid_model", "; ".join(model_result.get("errors", PackedStringArray())), false)
		return

	var model_variant: Variant = model_result.get("model_root")
	if not (model_variant is Node3D):
		_set_fallback("fallback_invalid_model", "GLB loader returned no Node3D model root.", false)
		return
	_model_root = model_variant as Node3D
	_model_root.name = "ImportedShipModel"
	add_child(_model_root)
	_anchor_registry = model_result.get("anchor_registry") as RefCounted
	_model_stats = {
		"mesh_count": int(model_result.get("mesh_count", 0)),
		"anchor_count": int(model_result.get("anchor_count", 0)),
		"interaction_count": int(model_result.get("interaction_count", 0)),
		"skeleton_count": int(model_result.get("skeleton_count", 0)),
	}
	if is_instance_valid(_placeholder_model):
		_placeholder_model.visible = false
	_load_state = "loaded"
	if not _warnings.is_empty():
		for warning: String in _warnings:
			push_warning("ShipModelMount: " + warning)


func _set_fallback(state: String, reason: String, expected_missing_asset: bool) -> void:
	_load_state = state
	_last_error = reason
	if is_instance_valid(_placeholder_model):
		_placeholder_model.visible = true
	if expected_missing_asset:
		print("ShipModelMount: %s; keeping placeholder visible." % reason)
	else:
		push_warning("ShipModelMount: %s; keeping placeholder visible." % reason)


## Public status snapshot for diagnostics and later mod-catalogue reporting.
func get_load_status() -> Dictionary:
	return {
		"state": _load_state,
		"loaded": _load_state == "loaded",
		"definition_path": ship_definition_path,
		"model_path": _resolved_model_path,
		"error": _last_error,
		"warnings": _warnings.duplicate(),
		"stats": _model_stats.duplicate(true),
	}


func get_model_root() -> Node3D:
	return _model_root if is_instance_valid(_model_root) else null


func get_anchor_registry() -> RefCounted:
	return _anchor_registry if is_instance_valid(_anchor_registry) else null


func retry_load() -> void:
	if is_instance_valid(_model_root):
		remove_child(_model_root)
		_model_root.queue_free()
	_model_root = null
	_anchor_registry = null
	_model_stats.clear()
	if is_instance_valid(_placeholder_model):
		_placeholder_model.visible = true
	_load_from_definition()
