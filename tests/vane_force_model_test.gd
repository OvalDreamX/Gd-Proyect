extends SceneTree

## Deterministic, headless checks for VaneController's pure force/torque math.
## Run from the project root:
## godot --headless --path . --script res://tests/vane_force_model_test.gd

const VANE_CONTROLLER_SCRIPT = preload("res://scripts/vane_controller.gd")
const TEST_VANE_RESOURCES: Array[String] = [
	"res://data/vanes/bottom_front_left.tres",
	"res://data/vanes/bottom_front_right.tres",
	"res://data/vanes/bottom_rear_left.tres",
	"res://data/vanes/bottom_rear_right.tres",
	"res://data/vanes/main_rear.tres",
]

const TEST_RATED_GROSS_MASS_KG: float = 55000.0
const TEST_GRAVITY: float = 9.81
const EPSILON: float = 0.01

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var controller = VANE_CONTROLLER_SCRIPT.new()
	var loaded_definitions: Array[Resource] = []
	for path in TEST_VANE_RESOURCES:
		var resource: Resource = load(path)
		if resource == null:
			_fail("Could not load %s" % path)
		else:
			loaded_definitions.append(resource)

	controller.vane_definitions = loaded_definitions
	root.add_child(controller)
	await process_frame

	_expect(controller.is_configuration_valid(), "Vane configuration registers successfully")
	_expect_equal(controller.get_vane_count(), 5, "Five configured vanes are registered")
	_expect_near(
		controller.get_group_nominal_authority_twr(&"bottom_front")
		+ controller.get_group_nominal_authority_twr(&"bottom_rear"),
		1.1,
		0.0001,
		"Four bottom vanes total 1.1 nominal TWR"
	)
	_expect_near(controller.get_group_nominal_authority_twr(&"main_rear"), 1.5, 0.0001, "Main rear vane retains its 1.5 TWR placeholder")

	var force_scale: float = TEST_RATED_GROSS_MASS_KG * TEST_GRAVITY
	var front: Dictionary = _calculate(controller, &"bottom_front", Vector3.UP, force_scale)
	var rear: Dictionary = _calculate(controller, &"bottom_rear", Vector3.UP, force_scale)
	var healthy_force: Vector3 = front["net_force"] + rear["net_force"]
	var healthy_torque: Vector3 = front["net_torque"] + rear["net_torque"]
	_expect_near(healthy_force.y, TEST_RATED_GROSS_MASS_KG * TEST_GRAVITY * 1.1, 0.1, "Healthy vanes produce expected 1.1 gross-TWR collective force")
	_expect_near(healthy_torque.length(), 0.0, EPSILON, "Symmetric healthy vanes produce no unintended torque")

	controller.set_vane_integrity(&"bottom_front_right", 0.5)
	front = _calculate(controller, &"bottom_front", Vector3.UP, force_scale)
	rear = _calculate(controller, &"bottom_rear", Vector3.UP, force_scale)
	var damaged_force: Vector3 = front["net_force"] + rear["net_force"]
	var damaged_torque: Vector3 = front["net_torque"] + rear["net_torque"]
	_expect(damaged_force.length() < healthy_force.length(), "A 50%-effective vane reduces total available lift")
	_expect(absf(damaged_torque.z) > EPSILON, "Asymmetric front-vane condition creates an unintended roll moment")

	var front_entries: Array = front["contributions"]
	var weakened_front_right: Dictionary = {}
	for entry in front_entries:
		if StringName(entry["vane_id"]) == &"bottom_front_right":
			weakened_front_right = entry
	_expect_near(float(weakened_front_right.get("effective_authority_twr", -1.0)), 0.1375, 0.0001, "50% condition halves that vane's authority")

	controller.set_vane_failed(&"bottom_front_right", true)
	front = _calculate(controller, &"bottom_front", Vector3.UP, force_scale)
	var failed_entry: Dictionary = {}
	for entry in front["contributions"]:
		if StringName(entry["vane_id"]) == &"bottom_front_right":
			failed_entry = entry
	var failed_force: Vector3 = failed_entry.get("force_world", Vector3.ZERO)
	_expect_near(failed_force.length(), 0.0, EPSILON, "Failed vane contributes zero force")

	controller.reset_all_vanes()
	front = _calculate(controller, &"bottom_front", Vector3.UP, force_scale)
	rear = _calculate(controller, &"bottom_rear", Vector3.UP, force_scale)
	var reset_force: Vector3 = front["net_force"] + rear["net_force"]
	var reset_torque: Vector3 = front["net_torque"] + rear["net_torque"]
	_expect_near(reset_force.distance_to(healthy_force), 0.0, EPSILON, "Reset restores nominal total force")
	_expect_near(reset_torque.length(), 0.0, EPSILON, "Reset restores symmetric torque baseline")

	# Opposite front/rear forces must cancel translation while producing pitch
	# torque about the ship's X axis from the separation between groups.
	front = _calculate(controller, &"bottom_front", Vector3.DOWN, force_scale)
	rear = _calculate(controller, &"bottom_rear", Vector3.UP, force_scale)
	var opposing_force: Vector3 = front["net_force"] + rear["net_force"]
	var opposing_torque: Vector3 = front["net_torque"] + rear["net_torque"]
	_expect_near(opposing_force.length(), 0.0, EPSILON, "Equal opposing front/rear forces cancel net translation")
	_expect(absf(opposing_torque.x) > EPSILON, "Separated opposing groups produce pitch torque")

	print("Vane force-model tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _calculate(controller: Node, group_id: StringName, direction: Vector3, force_scale: float) -> Dictionary:
	return controller.calculate_group_resultant(
		group_id,
		direction,
		force_scale,
		Transform3D.IDENTITY,
		Vector3.ZERO
	)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_equal(actual: int, expected: int, description: String) -> void:
	_expect(actual == expected, "%s (actual %d, expected %d)" % [description, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance])


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
