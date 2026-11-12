extends RefCounted
class_name ShipDefinitionLoader

## Strict schema-v1 JSON parser. This phase only parses and validates definitions;
## it does not instantiate ships or load models yet.

const SUPPORTED_SCHEMA_VERSION: int = 1
const REQUIRED_TOP_LEVEL: PackedStringArray = ["schema_version", "id", "display_name", "model", "physics", "cargo", "propulsion"]

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure(["File does not exist: %s" % path])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(["Could not open file: %s (error %s)" % [path, error_string(FileAccess.get_open_error())]])
	var text: String = file.get_as_text()
	file.close()
	return parse_text(text, path)

static func parse_text(json_text: String, source_name: String = "<memory>") -> Dictionary:
	var parser := JSON.new()
	var parse_error: Error = parser.parse(json_text)
	if parse_error != OK:
		return _failure([
			"%s: JSON parse error at line %d: %s" % [source_name, parser.get_error_line(), parser.get_error_message()]
		])
	if not (parser.data is Dictionary):
		return _failure(["%s: root JSON value must be an object." % source_name])
	var data: Dictionary = parser.data
	var errors: PackedStringArray = validate(data)
	if not errors.is_empty():
		return _failure(errors)
	var definition := ShipDefinition.new()
	definition.configure(data)
	return {"valid": true, "definition": definition, "errors": PackedStringArray()}

static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: String in REQUIRED_TOP_LEVEL:
		if not data.has(key):
			errors.append("Missing required field: %s" % key)
	if not errors.is_empty():
		return errors

	var version: int = int(data.get("schema_version", -1))
	if version != SUPPORTED_SCHEMA_VERSION:
		errors.append("Unsupported schema_version %d; this build supports %d." % [version, SUPPORTED_SCHEMA_VERSION])
	var ship_id: String = str(data.get("id", "")).strip_edges()
	if ship_id.is_empty() or not _is_safe_id(ship_id):
		errors.append("id must be a non-empty lowercase identifier using letters, numbers, dots, underscores or hyphens.")
	if str(data.get("display_name", "")).strip_edges().is_empty():
		errors.append("display_name must not be empty.")
	var model_path: String = str(data.get("model", "")).strip_edges()
	if model_path.is_empty() or model_path.begins_with("/") or model_path.contains("..") or model_path.contains("\\") or not model_path.to_lower().ends_with(".glb"):
		errors.append("model must be a relative .glb path inside the ship mod folder.")

	for optional_section: String in ["identity", "handling", "aerodynamics", "ground_effect", "cameras"]:
		if data.has(optional_section) and not (data[optional_section] is Dictionary):
			errors.append("%s must be an object when provided." % optional_section)

	var physics_variant: Variant = data.get("physics")
	var cargo_variant: Variant = data.get("cargo")
	var propulsion_variant: Variant = data.get("propulsion")
	if not (physics_variant is Dictionary):
		errors.append("physics must be an object.")
	if not (cargo_variant is Dictionary):
		errors.append("cargo must be an object.")
	if not (propulsion_variant is Dictionary):
		errors.append("propulsion must be an object.")
	if not (physics_variant is Dictionary) or not (cargo_variant is Dictionary) or not (propulsion_variant is Dictionary) or not errors.is_empty():
		return errors
	var physics: Dictionary = physics_variant
	var cargo: Dictionary = cargo_variant
	var propulsion: Dictionary = propulsion_variant

	_validate_positive_number(physics, "dry_mass_kg", "physics", errors, true)
	_validate_vector3(physics, "dry_center_of_mass_m", "physics", errors, false)
	_validate_vector3(physics, "dry_hull_dimensions_m", "physics", errors, true)
	_validate_positive_number(physics, "max_payload_mass_kg", "physics", errors, false)
	_validate_vector3(cargo, "hold_min_m", "cargo", errors, false)
	_validate_vector3(cargo, "hold_max_m", "cargo", errors, false)
	if cargo.has("hold_min_m") and cargo.has("hold_max_m") and cargo["hold_min_m"] is Array and cargo["hold_max_m"] is Array:
		var hold_min_array: Array = cargo["hold_min_m"]
		var hold_max_array: Array = cargo["hold_max_m"]
		if hold_min_array.size() == 3 and hold_max_array.size() == 3:
			var hold_min: Vector3 = _array_to_vector3(hold_min_array)
			var hold_max: Vector3 = _array_to_vector3(hold_max_array)
			if hold_min.x >= hold_max.x or hold_min.y >= hold_max.y or hold_min.z >= hold_max.z:
				errors.append("cargo hold_min_m must be smaller than hold_max_m on every axis.")

	var vanes_variant: Variant = propulsion.get("vanes", null)
	if not (vanes_variant is Array) or (vanes_variant is Array and vanes_variant.is_empty()):
		errors.append("propulsion.vanes must be a non-empty array.")
	else:
		var seen_ids: Dictionary = {}
		var vanes_array: Array = vanes_variant
		for index: int in range(vanes_array.size()):
			var vane: Variant = vanes_array[index]
			if not (vane is Dictionary):
				errors.append("propulsion.vanes[%d] must be an object." % index)
				continue
			var vane_data: Dictionary = vane
			var vane_id: String = str(vane_data.get("id", "")).strip_edges()
			if vane_id.is_empty() or not _is_safe_id(vane_id):
				errors.append("propulsion.vanes[%d].id is missing or invalid." % index)
			elif seen_ids.has(vane_id):
				errors.append("Duplicate vane id: %s" % vane_id)
			else:
				seen_ids[vane_id] = true
			if str(vane_data.get("anchor", "")).strip_edges().is_empty():
				errors.append("propulsion.vanes[%d].anchor must not be empty." % index)
			if str(vane_data.get("group", "")).strip_edges().is_empty():
				errors.append("propulsion.vanes[%d].group must not be empty." % index)
			_validate_positive_number(vane_data, "authority_twr", "propulsion.vanes[%d]" % index, errors, false)

	if data.has("ground_effect"):
		var ground: Variant = data["ground_effect"]
		if not (ground is Dictionary):
			errors.append("ground_effect must be an object when provided.")
		else:
			_validate_positive_number(ground, "footprint_width_m", "ground_effect", errors, false)
			if ground.has("max_gain"):
				var gain: float = float(ground["max_gain"])
				if gain < 0.0 or gain > 1.0:
					errors.append("ground_effect.max_gain must be between 0 and 1.")
	return errors

static func _validate_positive_number(source: Dictionary, key: String, section: String, errors: PackedStringArray, strictly_positive: bool) -> void:
	if not source.has(key) or not (source[key] is int or source[key] is float):
		errors.append("%s.%s must be a number." % [section, key])
		return
	var value: float = float(source[key])
	if not is_finite(value) or (value <= 0.0 if strictly_positive else value < 0.0):
		errors.append("%s.%s must be %s." % [section, key, "greater than zero" if strictly_positive else "zero or greater"])

static func _validate_vector3(source: Dictionary, key: String, section: String, errors: PackedStringArray, positive: bool) -> void:
	if not source.has(key) or not (source[key] is Array) or source[key].size() != 3:
		errors.append("%s.%s must be an array of exactly three numbers." % [section, key])
		return
	for component: Variant in source[key]:
		if not (component is int or component is float) or not is_finite(float(component)):
			errors.append("%s.%s must contain only finite numbers." % [section, key])
			return
	if positive:
		var vector: Vector3 = _array_to_vector3(source[key])
		if vector.x <= 0.0 or vector.y <= 0.0 or vector.z <= 0.0:
			errors.append("%s.%s components must all be greater than zero." % [section, key])

static func _array_to_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _is_safe_id(value: String) -> bool:
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		var valid: bool = (code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 46 or code == 95 or code == 45
		if not valid:
			return false
	return true

static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"valid": false, "definition": null, "errors": errors}
