extends SceneTree

## Deterministic regression tests for VaneController Phase 2S thermal and degradation model.
## Run from the project root:
## godot --headless --path . --script res://tests/vane_thermal_model_test.gd

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
		var res: Resource = load(path)
		if res == null:
			_fail("Could not load %s" % path)
		else:
			loaded_definitions.append(res)
	controller.vane_definitions = loaded_definitions
	root.add_child(controller)
	await process_frame

	_expect(controller.is_configuration_valid(), "Vane configuration is valid")

	# Test 1: Initial cold state at -10°C
	var fl_temp: float = controller.get_vane_temperature(&"bottom_front_left")
	_expect_near(fl_temp, -10.0, 0.1, "Bottom front left vane initializes at -10°C ambient")
	_expect(controller.get_vane_thermal_status(&"bottom_front_left") == &"COLD_STRAIN", "Initial thermal status is COLD_STRAIN")

	# Test 2: Cold temperature clamps maximum available authority (< nominal)
	var cold_effective_twr: float = controller.get_group_effective_authority_twr(&"bottom_front")
	var nominal_twr: float = controller.get_group_nominal_authority_twr(&"bottom_front")
	_expect(cold_effective_twr < nominal_twr * 0.75, "Cold vane authority is clamped to ~70% of nominal")

	# Test 3: Demanding 100% power while cold causes immediate quadratic cold-strain wear
	controller.update_thermal_simulation(1.0, -10.0, true, 1.0, 90.0)
	var fl_wear: float = controller.get_vane_wear_rate(&"bottom_front_left")
	_expect(fl_wear > 0.001, "100% load at -10°C produces high quadratic cold-strain wear rate")
	var telemetry: Dictionary = controller.get_telemetry()
	var fl_state: Dictionary = {}
	for v in telemetry.get("vane_states", []):
		if v.get("vane_id") == &"bottom_front_left":
			fl_state = v
			break
	_expect(float(fl_state.get("integrity", 1.0)) < 1.0, "Integrity drops after cold shock")

	# Test 4: Gentle warmup at 0.35 power reaches nominal 60°C within 10-20 seconds with minimal wear
	controller.reset_all_vanes(-10.0)
	var warmup_seconds: float = 0.0
	var delta_step: float = 0.5
	while controller.get_vane_temperature(&"bottom_front_left") < 60.0 and warmup_seconds < 30.0:
		controller.update_thermal_simulation(delta_step, -10.0, true, 0.35, 90.0)
		warmup_seconds += delta_step

	_expect(warmup_seconds >= 10.0 and warmup_seconds <= 25.0, "Warmup to 60°C takes 10 to 25 seconds (took %.1fs)" % warmup_seconds)
	var post_warmup_integ: float = 1.0
	for v in controller.get_telemetry().get("vane_states", []):
		if v.get("vane_id") == &"bottom_front_left":
			post_warmup_integ = float(v.get("integrity", 1.0))
			break
	_expect(post_warmup_integ > 0.985, "Gentle warmup preserves >98.5% integrity (got %.3f)" % post_warmup_integ)

	# Test 5: In Green Zone (e.g. 80°C with 0.60 power), wear rate is minimal base wear
	controller.set_vane_temperature(&"bottom_front_left", 80.0)
	controller.update_thermal_simulation(0.1, -10.0, true, 0.60, 90.0)
	_expect(controller.get_vane_thermal_status(&"bottom_front_left") == &"GREEN_ZONE", "80°C at 0.60 power is GREEN_ZONE")
	var green_wear: float = controller.get_vane_wear_rate(&"bottom_front_left")
	_expect(green_wear <= 0.00001, "Green zone wear rate is minimal base operating wear")

	# Test 6: Sustained 100% power overheats past 180°C into OVERHEAT
	controller.set_vane_temperature(&"bottom_front_left", 140.0)
	for i in range(25):
		controller.update_thermal_simulation(1.0, -10.0, true, 1.0, 90.0)
	var overheat_temp: float = controller.get_vane_temperature(&"bottom_front_left")
	_expect(overheat_temp > 180.0, "Sustained 100% power overheats past 180°C (got %.1f°C)" % overheat_temp)
	_expect(controller.get_vane_thermal_status(&"bottom_front_left") in [&"OVERHEAT", &"CRITICAL"], "Status becomes OVERHEAT or CRITICAL")

	controller.queue_free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: %s" % message)
	else:
		print("PASS: %s" % message)


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: %s" % message)


func _finish() -> void:
	print("--- Vane Thermal Model Test Summary ---")
	print("Total checks: %d, Failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
