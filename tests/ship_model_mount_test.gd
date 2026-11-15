extends SceneTree

const ShipModelMountScript = preload("res://scripts/ship_model_mount.gd")

# Keep intentionally non-renderable GLB test data outside res://. Godot's editor
# auto-imports files under res://, and an empty GLB can trigger importer-side
# renderer diagnostics before the test is ever run.
const TEMP_DIRECTORY: String = "user://space_trucker_ship_model_mount_test"
const TEMP_DEFINITION_PATH: String = TEMP_DIRECTORY + "/ship.json"
const TEMP_MODEL_PATH: String = TEMP_DIRECTORY + "/non_renderable.glb"
const NON_RENDERABLE_GLB_BASE64: String = "Z2xURgIAAACsAAAAmAAAAEpTT057ImFzc2V0Ijp7InZlcnNpb24iOiIyLjAiLCJnZW5lcmF0b3IiOiJTcGFjZSBUcnVja2VyIGVtcHR5LW1vZGVsIGZhbGxiYWNrIGZpeHR1cmUifSwic2NlbmUiOjAsInNjZW5lcyI6W3sibm9kZXMiOlswXX1dLCJub2RlcyI6W3sibmFtZSI6IlNISVBfcm9vdCJ9XX0gIA=="

var _failure_count: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_missing_model_keeps_placeholder()
	_test_non_renderable_model_keeps_placeholder()
	_test_valid_model_replaces_placeholder()
	_cleanup_temporary_fixture()
	if _failure_count > 0:
		push_error("Ship model mount tests failed: %d assertion(s)." % _failure_count)
		quit(1)
	else:
		print("Ship model mount tests passed.")
		quit(0)


func _test_missing_model_keeps_placeholder() -> void:
	var fixture: Dictionary = _make_mount("res://tests/assets/ship_model_missing_fixture.json")
	var mount: ShipModelMount = fixture["mount"] as ShipModelMount
	var placeholder: Node3D = fixture["placeholder"]
	var status: Dictionary = mount.get_load_status()
	_assert(String(status.get("state", "")) == "fallback_missing_model", "Missing model should use fallback: %s" % str(status))
	_assert(placeholder.visible, "Fallback placeholder must remain visible when the model is missing.")
	_assert(not bool(status.get("loaded", true)), "Missing model must not report loaded.")
	(fixture["parent"] as Node).free()


func _test_non_renderable_model_keeps_placeholder() -> void:
	if not _write_non_renderable_fixture():
		_assert(false, "Could not create temporary non-renderable GLB test fixture.")
		return

	var fixture: Dictionary = _make_mount(TEMP_DEFINITION_PATH)
	var mount: ShipModelMount = fixture["mount"] as ShipModelMount
	var placeholder: Node3D = fixture["placeholder"]
	var status: Dictionary = mount.get_load_status()
	_assert(
		String(status.get("state", "")) == "fallback_invalid_model",
		"GLB without renderable meshes should use fallback: %s" % str(status)
	)
	_assert(placeholder.visible, "Fallback placeholder must remain visible when GLB contains no renderable geometry.")
	_assert(not bool(status.get("loaded", true)), "A non-renderable GLB must not report loaded.")
	(fixture["parent"] as Node).free()


func _test_valid_model_replaces_placeholder() -> void:
	var fixture: Dictionary = _make_mount("res://tests/assets/ship_model_mount_fixture.json")
	var mount: ShipModelMount = fixture["mount"] as ShipModelMount
	var placeholder: Node3D = fixture["placeholder"]
	var status: Dictionary = mount.get_load_status()
	_assert(String(status.get("state", "")) == "loaded", "Valid GLB should load through the mount: %s" % str(status))
	_assert(not placeholder.visible, "Placeholder must hide only after a valid model is attached.")
	_assert(mount.get_model_root() != null, "Loaded model root should be exposed to the ship.")
	var registry: RefCounted = mount.get_anchor_registry()
	_assert(is_instance_valid(registry), "Loaded model should retain its anchor registry.")
	if is_instance_valid(registry) and registry.has_method("has_anchor"):
		_assert(bool(registry.call("has_anchor", "ground_probe_front_left")), "Imported model anchors should remain discoverable.")
	(fixture["parent"] as Node).free()


func _write_non_renderable_fixture() -> bool:
	var absolute_directory: String = ProjectSettings.globalize_path(TEMP_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Could not create temporary model-test directory: %s" % error_string(directory_error))
		return false

	var model_file := FileAccess.open(TEMP_MODEL_PATH, FileAccess.WRITE)
	if model_file == null:
		push_error("Could not write temporary GLB fixture: %s" % error_string(FileAccess.get_open_error()))
		return false
	model_file.store_buffer(Marshalls.base64_to_raw(NON_RENDERABLE_GLB_BASE64))
	model_file.close()

	var definition: Dictionary = {
		"schema_version": 1,
		"id": "test.ship_model_mount_non_renderable",
		"display_name": "Non-renderable Test Model",
		"model": "non_renderable.glb",
		"physics": {
			"dry_mass_kg": 1000.0,
			"dry_center_of_mass_m": [0.0, 0.0, 0.0],
			"dry_hull_dimensions_m": [2.0, 1.0, 3.0],
			"max_payload_mass_kg": 0.0,
		},
		"cargo": {
			"hold_min_m": [-0.5, -0.25, -0.75],
			"hold_max_m": [0.5, 0.25, 0.75],
		},
		"propulsion": {
			"vanes": [{
				"id": "test_vane",
				"anchor": "ANCHOR_vane_test",
				"group": "test",
				"authority_twr": 0.1,
			}],
		},
	}
	var definition_file := FileAccess.open(TEMP_DEFINITION_PATH, FileAccess.WRITE)
	if definition_file == null:
		push_error("Could not write temporary ship definition: %s" % error_string(FileAccess.get_open_error()))
		return false
	definition_file.store_string(JSON.stringify(definition, "\t"))
	definition_file.close()
	return true


func _cleanup_temporary_fixture() -> void:
	for path: String in [TEMP_DEFINITION_PATH, TEMP_MODEL_PATH]:
		var absolute_path: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute_path)
	var absolute_directory: String = ProjectSettings.globalize_path(TEMP_DIRECTORY)
	DirAccess.remove_absolute(absolute_directory)


func _make_mount(definition_path: String) -> Dictionary:
	var test_parent := Node3D.new()
	test_parent.name = "TestShip"
	root.add_child(test_parent)
	var placeholder := Node3D.new()
	placeholder.name = "PlaceholderModel"
	test_parent.add_child(placeholder)
	var mount: ShipModelMount = ShipModelMountScript.new() as ShipModelMount
	mount.name = "ModelMount"
	mount.ship_definition_path = definition_path
	mount.placeholder_node_path = NodePath("../PlaceholderModel")
	test_parent.add_child(mount)
	return {"parent": test_parent, "placeholder": placeholder, "mount": mount}


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error("ShipModelMount test failed: " + message)
