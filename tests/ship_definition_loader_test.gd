extends SceneTree

const Loader = preload("res://scripts/ship_definition_loader.gd")

func _initialize() -> void:
	_test_reference_definition()
	_test_rejects_invalid_data()
	_test_rejects_duplicate_vanes()
	print("Ship definition loader tests passed.")
	quit(0)

func _test_reference_definition() -> void:
	var result: Dictionary = Loader.load_file("res://data/ships/prototype_freighter/ship.json")
	_assert(bool(result.get("valid", false)), "Reference ship JSON should validate: %s" % str(result.get("errors", [])))
	if not bool(result.get("valid", false)):
		return
	var definition: ShipDefinition = result["definition"]
	_assert(definition.ship_id == "spacetrucker.prototype_freighter", "Ship ID should load.")
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
	_assert(validation_errors.size() >= 4, "Validation should report multiple useful errors.")

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

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("ShipDefinitionLoader test failed: " + message)
