extends SceneTree

## Deterministic regression tests for Phase 2S thermal operation.
## Run: godot --headless --path . --script res://tests/vane_thermal_model_test.gd

const VANE_CONTROLLER_SCRIPT = preload("res://scripts/vane_controller.gd")
const TEST_VANE_RESOURCES: Array[String] = [
	"res://data/vanes/bottom_front_left.tres",
	"res://data/vanes/bottom_front_right.tres",
	"res://data/vanes/bottom_rear_left.tres",
	"res://data/vanes/bottom_rear_right.tres",
	"res://data/vanes/main_rear.tres",
]

var _checks: int = 0
var _failures: int = 0


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

	_expect(controller.is_configuration_valid(), "Vane configuration is valid")
	_expect_near(controller.get_vane_temperature(&"bottom_front_left"), -10.0, 0.1, "Vane initializes at -10°C ambient")
	_expect(controller.get_vane_thermal_status(&"bottom_front_left") == &"COLD_STRAIN", "Initial thermal status is COLD_STRAIN")

	# Thermal load is derived from force magnitude / vane nominal force rating.
	var rated_force_per_twr: float = 55000.0 * 9.81
	var nominal_vane_force: float = controller.get_vane_nominal_authority_twr(&"bottom_front_left") * rated_force_per_twr
	var contribution: Dictionary = {
		"vane_id": &"bottom_front_left",
		"force_world": Vector3.UP * nominal_vane_force * 0.5,
	}
	var derived_loads: Dictionary = controller.calculate_thermal_loads(
		0.0, 90.0, [contribution], rated_force_per_twr
	)
	_expect_near(float(derived_loads.get(&"bottom_front_left", 0.0)), 0.5, 0.001, "Actual vane force produces the correct normalized thermal load")

	# The collective main-vector demand is apportioned to the corresponding vane groups.
	derived_loads = controller.calculate_thermal_loads(0.6, 90.0, [], rated_force_per_twr)
	_expect_near(float(derived_loads.get(&"bottom_front_left", 0.0)), 0.6, 0.001, "Main lift demand is assigned to each bottom vane")
	_expect_near(float(derived_loads.get(&"main_rear", 1.0)), 0.0, 0.001, "Vertical vector does not load the rear propulsion vane")

	# Cold shock at full commanded load causes quadratic degradation.
	var full_load: Dictionary = {&"bottom_front_left": 1.0}
	controller.update_thermal_simulation(1.0, -10.0, true, full_load)
	_expect(controller.get_vane_wear_rate(&"bottom_front_left") > 0.001, "Full-load cold operation causes accelerated wear")
	var integrity_after_shock: float = _vane_integrity(controller, &"bottom_front_left")
	_expect(integrity_after_shock < 1.0, "Integrity drops after cold shock")

	# Gentle 0.35 load warms a cold vane to 60°C in the current model's test envelope.
	controller.reset_all_vanes(-10.0)
	var warmup_loads: Dictionary = {&"bottom_front_left": 0.35}
	var warmup_seconds: float = 0.0
	while controller.get_vane_temperature(&"bottom_front_left") < 60.0 and warmup_seconds < 30.0:
		controller.update_thermal_simulation(0.5, -10.0, true, warmup_loads)
		warmup_seconds += 0.5
	_expect(warmup_seconds >= 10.0 and warmup_seconds <= 25.0, "0.35 load warmup reaches 60°C in the expected range")
	_expect(_vane_integrity(controller, &"bottom_front_left") > 0.985, "Gentle warmup preserves vane integrity")

	# A stable 80°C vane at 0.60 load is inside its green zone.
	controller.set_vane_temperature(&"bottom_front_left", 80.0)
	controller.update_thermal_simulation(0.1, -10.0, true, {&"bottom_front_left": 0.60})
	_expect(controller.get_vane_thermal_status(&"bottom_front_left") == &"GREEN_ZONE", "80°C at 0.60 load is GREEN_ZONE")
	_expect(controller.get_vane_wear_rate(&"bottom_front_left") <= 0.00001, "Green-zone wear remains at the minimal baseline")

	# Sustained maximum demand reaches overheat/critical state.
	controller.set_vane_temperature(&"bottom_front_left", 140.0)
	for _tick in range(25):
		controller.update_thermal_simulation(1.0, -10.0, true, full_load)
	_expect(controller.get_vane_temperature(&"bottom_front_left") > 180.0, "Sustained full load overheats the vane")
	_expect(
		controller.get_vane_thermal_status(&"bottom_front_left") in [&"OVERHEAT", &"CRITICAL"],
		"Thermal status reports OVERHEAT or CRITICAL"
	)

	# Offline operation must cool continuously and must not accumulate operating wear.
	controller.set_vane_temperature(&"bottom_front_left", 120.0)
	var integrity_before_cooldown: float = _vane_integrity(controller, &"bottom_front_left")
	controller.update_thermal_simulation(10.0, -10.0, false, {})
	_expect(controller.get_vane_temperature(&"bottom_front_left") < 120.0, "Field-off thermal update cools the vane")
	_expect_near(controller.get_vane_wear_rate(&"bottom_front_left"), 0.0, 0.000001, "Field-off cooldown does not accrue operating wear")
	_expect_near(_vane_integrity(controller, &"bottom_front_left"), integrity_before_cooldown, 0.000001, "Field-off cooldown preserves integrity")

	controller.queue_free()
	print("Vane thermal model tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _vane_integrity(controller: Node, vane_id: StringName) -> float:
	for vane_value in controller.get_telemetry().get("vane_states", []):
		var vane: Dictionary = vane_value
		if vane.get("vane_id") == vane_id:
			return float(vane.get("integrity", 0.0))
	return 0.0


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.6f, expected %.6f)" % [description, actual, expected])


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
