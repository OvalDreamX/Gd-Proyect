extends SceneTree

const Loader = preload("res://scripts/ship_definition_loader.gd")
var _failure_count: int = 0


func _initialize() -> void:
	_test_reference_definition()
	_test_rejects_invalid_data()
	_test_rejects_duplicate_vanes()
	if _failure_count > 0:
		push_error("Ship definition loader tests failed: %d assertion(s)." % _failure_count)
		quit(1)
	else:
		print("Ship definition loader tests passed.")
		quit(0)


func _test_reference_definition() -> void:
	var result: Dictionary = Loader.load_file("res://data/ships/prototype_freighter/ship.json")
	_assert(bool(result.get("valid", false)), "Reference ship JSON should validate: %s" % str(result.get("errors", [])))
	if not bool(result.get("valid", false)):
		return
	var definition: ShipDefinition = result["definition"]
	_assert(definition.ship_id == "spacetrucker.prototype_freighter", "Ship ID should load.")
	_assert(definition.model_path == "model.glb", "Relative model path should be retained in the typed definition.")
	_assert(is_equal_approx(float(definition.physics["dry_mass_kg"]), 30000.0), "Dry mass should load.")
	_assert(definition.vanes.size() == 7, "All seven prototype vanes should load.")


func _test_rejects_invalid_data() -> void:
	var invalid_json := """
	{
	  "schema_version": 1,
	  "id": "../escape",
	  "display_name": "Broken",
	  "model": "../outside.glb",
	  "physics": {"dry_mass_kg": -1, "dry_center_of_mass_m": [0,0,0], "dry_hull_dimensions_m": [1,1,1], "max_payload_mass_kg": 0},
	  "cargo": {"hold_min_m": [1,1,1], "hold_max_m": [0,0,0]},
	  "propulsion": {"vanes": []}
	}
	"""
	var result: Dictionary = Loader.parse_text(invalid_json, "invalid_test")
	_assert(not bool(result.get("valid", true)), "Invalid definition should be rejected.")
	var validation_errors: PackedStringArray = result.get("errors", PackedStringArray())
	_assert(validation_errors.size() >= 5, "Validation should report independent identity, path, mass, cargo and vane errors. Actual: %s" % str(validation_errors))
	_assert(_errors_contain(validation_errors, "id must"), "Invalid ship ID should have a useful diagnostic.")
	_assert(_errors_contain(validation_errors, "model must"), "Invalid model path should have a useful diagnostic.")
	_assert(_errors_contain(validation_errors, "dry_mass_kg"), "Invalid dry mass should have a useful diagnostic.")
	_assert(_errors_contain(validation_errors, "hold_min_m"), "Inverted cargo bounds should have a useful diagnostic.")
	_assert(_errors_contain(validation_errors, "propulsion.vanes"), "Empty vane list should have a useful diagnostic.")


func _test_rejects_duplicate_vanes() -> void:
	var duplicate_json := """
	{
	  "schema_version": 1,
	  "id": "test.duplicate",
	  "display_name": "Duplicate",
	  "model": "model.glb",
	  "physics": {"dry_mass_kg": 100, "dry_center_of_mass_m": [0,0,0], "dry_hull_dimensions_m": [1,1,1], "max_payload_mass_kg": 0},
	  "cargo": {"hold_min_m": [-1,-1,-1], "hold_max_m": [1,1,1]},
	  "propulsion": {"vanes": [
	    {"id":"v1", "anchor":"A", "group":"G", "authority_twr":0.1},
	    {"id":"v1", "anchor":"B", "group":"G", "authority_twr":0.1}
	  ]}
	}
	"""
	var result: Dictionary = Loader.parse_text(duplicate_json, "duplicate_test")
	_assert(not bool(result.get("valid", true)), "Duplicate vane IDs should be rejected.")
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	_assert(_errors_contain(errors, "Duplicate vane id"), "Duplicate vane IDs should be identified by name.")


func _errors_contain(errors: PackedStringArray, fragment: String) -> bool:
	for message: String in errors:
		if message.contains(fragment):
			return true
	return false


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error("ShipDefinitionLoader test failed: " + message)
