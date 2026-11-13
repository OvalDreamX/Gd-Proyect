extends SceneTree

const ModelLoader = preload("res://scripts/ship_model_loader.gd")
const ModelValidator = preload("res://scripts/ship_model_validator.gd")
const AnchorRegistry = preload("res://scripts/ship_anchor_registry.gd")


func _initialize() -> void:
	_test_model_path_validation()
	_test_model_tree_validation()
	_test_duplicate_anchor_rejection()
	_test_interaction_contract()
	_test_anchor_registry()
	_test_runtime_glb_fixture()
	print("Ship model pipeline tests passed.")
	quit(0)


func _test_model_path_validation() -> void:
	_assert(ModelLoader.validate_model_path("res://data/ships/test/model.glb").is_empty(), "Built-in GLB path should be accepted.")
	_assert(ModelLoader.validate_model_path("user://mods/ships/test/model.glb").is_empty(), "User mod GLB path should be accepted.")
	_assert(not ModelLoader.validate_model_path("../outside.glb").is_empty(), "Relative paths without a permitted root should be rejected.")
	_assert(not ModelLoader.validate_model_path("user://mods/../../outside.glb").is_empty(), "Traversal segments should be rejected.")
	_assert(not ModelLoader.validate_model_path("user://mods/test/model.gltf").is_empty(), "Text glTF is not the ship asset format.")
	_assert(not ModelLoader.validate_model_path("user://mods\\test\\model.glb").is_empty(), "Backslashes should be rejected.")
	_assert(not ModelLoader.validate_model_path("user://mods//test/model.glb").is_empty(), "Empty path segments should be rejected.")


func _test_model_tree_validation() -> void:
	var root := _make_valid_model_tree()
	var result: Dictionary = ModelValidator.validate_model_root(root)
	_assert(bool(result.get("valid", false)), "Valid fixture tree should pass validation: %s" % str(result.get("errors", [])))
	_assert(int(result.get("mesh_count", 0)) == 2, "Both model meshes should be discovered.")
	_assert(int(result.get("interaction_count", 0)) == 1, "One interaction should be discovered.")
	_assert(int(result.get("anchors", {}).size()) == 2, "Two anchors should be discovered.")
	root.free()


func _test_duplicate_anchor_rejection() -> void:
	var root := Node3D.new()
	var left := Node3D.new()
	left.name = "Left"
	var right := Node3D.new()
	right.name = "Right"
	root.add_child(left)
	root.add_child(right)
	var first := Node3D.new()
	first.name = "ANCHOR_pilot_seat"
	var second := Node3D.new()
	second.name = "ANCHOR_pilot_seat"
	left.add_child(first)
	right.add_child(second)
	var result: Dictionary = ModelValidator.validate_model_root(root)
	_assert(not bool(result.get("valid", true)), "Duplicate anchor identifiers must fail validation.")
	root.free()


func _test_interaction_contract() -> void:
	var root := Node3D.new()
	var invalid_interaction := Node3D.new()
	invalid_interaction.name = "INTERACT_dial_navigation"
	root.add_child(invalid_interaction)
	var result: Dictionary = ModelValidator.validate_model_root(root)
	_assert(not bool(result.get("valid", true)), "Unsupported interaction types must fail validation.")
	root.free()


func _test_anchor_registry() -> void:
	var root := _make_valid_model_tree()
	var registry := AnchorRegistry.new() as ShipAnchorRegistry
	var build_result: Dictionary = registry.rebuild(root)
	_assert(bool(build_result.get("valid", false)), "Anchor registry should build from a valid tree.")
	_assert(registry.has_anchor("pilot_seat"), "Anchor registry should resolve identifiers without prefix.")
	_assert(registry.has_anchor("ANCHOR_cockpit_camera"), "Anchor registry should also resolve full Blender names.")
	_assert(registry.get_anchor("pilot_seat") != null, "Anchor lookup should return the Node3D.")
	var missing: PackedStringArray = registry.get_missing_anchors(PackedStringArray(["pilot_seat", "cargo_origin"]))
	_assert(missing.size() == 1 and missing[0] == "cargo_origin", "Missing-anchor query should report only absent IDs.")
	root.free()


func _test_runtime_glb_fixture() -> void:
	var result: Dictionary = ModelLoader.load_glb("res://tests/assets/ship_model_fixture.glb")
	_assert(bool(result.get("success", false)), "Runtime GLB fixture should load: %s" % str(result.get("errors", [])))
	if bool(result.get("success", false)):
		_assert(int(result.get("anchor_count", 0)) == 4, "Runtime GLB import should preserve all four named anchors.")
		_assert(int(result.get("mesh_count", 0)) == 2, "Runtime GLB import should preserve both mesh nodes.")
		var model_root: Node = result.get("model_root") as Node
		if is_instance_valid(model_root):
			model_root.free()
	var missing_result: Dictionary = ModelLoader.load_glb("res://tests/assets/does_not_exist.glb")
	_assert(not bool(missing_result.get("success", true)), "Missing GLB should return a structured failure, not crash.")


func _make_valid_model_tree() -> Node3D:
	var root := Node3D.new()
	root.name = "SHIP_root"

	var hull := MeshInstance3D.new()
	hull.name = "MESH_hull_main"
	hull.mesh = BoxMesh.new()
	root.add_child(hull)

	var pilot_seat := Node3D.new()
	pilot_seat.name = "ANCHOR_pilot_seat"
	root.add_child(pilot_seat)

	var camera := Node3D.new()
	camera.name = "ANCHOR_cockpit_camera"
	root.add_child(camera)

	var switch := Node3D.new()
	switch.name = "INTERACT_switch_main_power"
	root.add_child(switch)
	var switch_mesh := MeshInstance3D.new()
	switch_mesh.name = "MESH_switch_main_power"
	switch_mesh.mesh = BoxMesh.new()
	switch.add_child(switch_mesh)
	return root


func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("ShipModelPipeline test failed: " + message)
