extends SceneTree

## Scene wiring and visual-reference checks for the enhanced test range.
## Run from the project root:
## godot --headless --path . --script res://tests/test_range_environment_test.gd

const TEST_RANGE_SCENE = preload("res://scenes/test_range.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var test_range := TEST_RANGE_SCENE.instantiate() as Node3D
	_expect(test_range != null, "Test range scene instantiates")
	if test_range == null:
		quit(1)
		return
	root.add_child(test_range)
	await process_frame
	await physics_frame

	var ground := test_range.get_node_or_null("Ground") as StaticBody3D
	var ground_mesh := test_range.get_node_or_null("Ground/GroundMesh") as MeshInstance3D
	_expect(ground != null, "Test range retains its ground StaticBody3D")
	_expect(ground_mesh != null and ground_mesh.mesh is PlaneMesh, "Ground has a procedural-material plane mesh")
	if ground_mesh != null and ground_mesh.mesh is PlaneMesh:
		var plane := ground_mesh.mesh as PlaneMesh
		_expect(plane.size.x >= 900.0 and plane.size.y >= 900.0, "Visual ground provides a large continuous frame of reference")

	var collision_count: int = 0
	if ground != null:
		for child in ground.get_children():
			if child is CollisionShape3D:
				collision_count += 1
	_expect(collision_count == 4, "Ground keeps four collision strips and leaves the physical landing pad opening")
	_expect(test_range.get_node_or_null("SurveyGrid20m") != null, "Survey grid is generated")
	_expect(test_range.get_node_or_null("LandingPadMarkings") != null, "Landing pad markings are generated")
	_expect(test_range.get_node_or_null("ApproachLane") != null, "Approach lane and distance references are generated")
	_expect(test_range.get_node_or_null("WindReference") != null, "Mean wind direction has a visible ground reference")

	var ridge_count: int = 0
	for child in test_range.get_children():
		if str(child.name).begins_with("DistantRidge_"):
			ridge_count += 1
	_expect(ridge_count >= 8, "Distant ridge landmarks form a visible horizon")

	print("Test-range environment tests: %d checks, %d failures." % [_checks, _failures])
	test_range.queue_free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
