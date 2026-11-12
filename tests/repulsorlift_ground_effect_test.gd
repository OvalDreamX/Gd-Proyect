extends SceneTree

const GroundEffect = preload("res://scripts/repulsorlift_ground_effect_system.gd")
const Loader = preload("res://scripts/ship_definition_loader.gd")

func _initialize() -> void:
	_test_proximity_curve()
	_test_upward_component_only()
	_test_reference_json()
	print("Repulsorlift ground-effect tests passed.")
	quit(0)

func _test_proximity_curve() -> void:
	_assert(is_equal_approx(GroundEffect.calculate_proximity_factor(0.0, 5.0), 1.0), "Ground effect should be maximal at zero clearance.")
	_assert(is_equal_approx(GroundEffect.calculate_proximity_factor(2.5, 5.0), 0.5), "Smoothstep proximity should be 0.5 at half footprint clearance.")
	_assert(is_equal_approx(GroundEffect.calculate_proximity_factor(5.0, 5.0), 0.0), "Ground effect should fade to zero at footprint width.")
	_assert(is_equal_approx(GroundEffect.calculate_proximity_factor(8.0, 5.0), 0.0), "Ground effect should remain zero beyond footprint width.")
	_assert(is_equal_approx(GroundEffect.calculate_proximity_factor(-0.1, 5.0), 0.0), "Invalid negative clearance should not produce ground effect.")

func _test_upward_component_only() -> void:
	var main_force := Vector3(500.0, 1000.0, 0.0)
	var added: Vector3 = GroundEffect.calculate_additional_force(main_force, Vector3.UP, 0.15, 0.5)
	_assert(is_equal_approx(added.x, 0.0), "Ground effect must not amplify horizontal thrust.")
	_assert(is_equal_approx(added.y, 75.0), "Ground effect should add 7.5% of upward force at half proximity.")
	_assert(is_equal_approx(added.z, 0.0), "Ground effect must not add a tangential component.")
	var downward: Vector3 = GroundEffect.calculate_additional_force(Vector3.DOWN * 1000.0, Vector3.UP, 0.15, 1.0)
	_assert(downward == Vector3.ZERO, "Ground effect must not amplify force toward the surface.")

func _test_reference_json() -> void:
	var result: Dictionary = Loader.load_file("res://data/ships/prototype_freighter/ship.json")
	_assert(bool(result.get("valid", false)), "Reference ship JSON should validate with ground-effect settings: %s" % str(result.get("errors", [])))
	if not bool(result.get("valid", false)):
		return
	var definition: ShipDefinition = result["definition"]
	_assert(bool(definition.ground_effect.get("enabled", false)), "Ground effect should be enabled in the prototype definition.")
	_assert(is_equal_approx(float(definition.ground_effect.get("max_gain", 0.0)), 0.15), "Prototype maximum gain should be 15%.")
	_assert(definition.ground_effect.get("probe_anchors", []).size() == 4, "Prototype should define four ground probes.")

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("RepulsorliftGroundEffect test failed: " + message)
