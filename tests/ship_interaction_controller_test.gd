extends SceneTree

## Run: godot --headless --path . --script res://tests/ship_interaction_controller_test.gd
## Synthetic mesh hierarchy; no Blender export is required.
const INTERACTION_CONTROLLER_SCRIPT = preload("res://scripts/ship_interaction_controller.gd")

class FakeFlightController extends Node:
	var received_requests: Array[Dictionary] = []
	const ACCEPTED_IDS: Array[String] = [
		"switch_main_power",
		"switch_field_assist",
		"lever_throttle",
		"lever_vector_angle",
	]

	func request_cockpit_control(control_id: StringName, value: float) -> bool:
		var id: String = String(control_id)
		if not ACCEPTED_IDS.has(id):
			return false
		received_requests.append({"id": id, "value": value})
		return true


var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var ship_root := Node3D.new()
	ship_root.name = "TestShip"
	root.add_child(ship_root)

	var fake_flight_controller := FakeFlightController.new()
	fake_flight_controller.name = "FakeFlightController"
	ship_root.add_child(fake_flight_controller)

	var controller := Node.new()
	controller.name = "InteractionController"
	controller.set_script(INTERACTION_CONTROLLER_SCRIPT)
	controller.set("flight_controller_path", NodePath("../FakeFlightController"))
	ship_root.add_child(controller)
	await process_frame

	var model_root := _make_valid_interaction_model()
	ship_root.add_child(model_root)
	await process_frame
	var configuration: Dictionary = controller.call("configure_from_model", model_root)
	_expect(bool(configuration.get("valid", false)), "A model with correctly named interaction pivots validates")
	_expect(int(configuration.get("interaction_count", 0)) == 5, "All five representative cockpit controls are discovered")
	_expect(int(configuration.get("hit_area_count", 0)) == 5, "A runtime hit area is generated for every valid interaction")
	_expect(
		controller.call("get_interaction_ids") == PackedStringArray([
			"button_landing_lights",
			"lever_throttle",
			"lever_vector_angle",
			"switch_field_assist",
			"switch_main_power",
		]),
		"Interaction IDs are exposed without the INTERACT_ prefix and sorted"
	)

	var throttle_info: Dictionary = controller.call("get_interaction_info", "lever_throttle")
	var throttle_area: Area3D = throttle_info.get("hit_area") as Area3D
	_expect(is_instance_valid(throttle_area), "The lever exposes its generated Area3D")
	if is_instance_valid(throttle_area):
		var throttle_shape := throttle_area.get_node("CollisionShape3D") as CollisionShape3D
		_expect(is_instance_valid(throttle_shape) and throttle_shape.shape is BoxShape3D, "Generated hit area uses a BoxShape3D")
		if is_instance_valid(throttle_shape) and throttle_shape.shape is BoxShape3D:
			var box := throttle_shape.shape as BoxShape3D
			_expect(
				box.size.is_equal_approx(Vector3(0.36, 0.56, 0.26)),
				"Hitbox bounds include mesh dimensions plus the configured 0.08 m padding"
			)
		_expect(throttle_area.collision_layer == (1 << 19), "Hit areas use the dedicated interaction collision layer")
		_expect(throttle_area.collision_mask == 0 and not throttle_area.monitoring, "Hit areas do not monitor or alter normal physics contacts")

	_expect(bool(controller.call("activate_interaction", "switch_main_power")), "Main-power switch dispatches through the fixed flight-controller API")
	_expect(bool(controller.call("activate_interaction", "switch_field_assist")), "Field-assist switch dispatches through the fixed flight-controller API")
	_expect(bool(controller.call("set_interaction_value", "lever_throttle", 0.35)), "Throttle lever accepts a normalized value")
	_expect(bool(controller.call("set_interaction_value", "lever_vector_angle", 0.75)), "Vector-angle lever accepts a normalized value")
	_expect(not bool(controller.call("activate_interaction", "button_landing_lights")), "An unimplemented landing-light button is rejected without inventing behavior")
	_expect(not bool(controller.call("get_interaction_info", "button_landing_lights").get("bound", true)), "The unsupported button is explicitly reported as unbound")
	_expect(not bool(controller.call("activate_interaction", "lever_throttle")), "A lever cannot be activated as a binary switch")
	_expect(not bool(controller.call("set_interaction_value", "switch_main_power", 0.5)), "A switch cannot be driven through the continuous lever API")
	_expect(not bool(controller.call("set_interaction_value", "lever_throttle", INF)), "Non-finite lever values are rejected")
	_expect(not fake_flight_controller.received_requests.is_empty(), "Accepted interactions reach the ship's fixed control bridge")
	if fake_flight_controller.received_requests.size() >= 4:
		_expect(is_equal_approx(float(fake_flight_controller.received_requests[2]["value"]), 0.35), "Throttle value is passed through unchanged")
		_expect(is_equal_approx(float(fake_flight_controller.received_requests[3]["value"]), 0.75), "Vector value is passed through unchanged")
	else:
		_expect(false, "All four bound control requests were recorded")

	var invalid_model := _make_invalid_interaction_model()
	ship_root.add_child(invalid_model)
	await process_frame
	var invalid_status: Dictionary = controller.call("configure_from_model", invalid_model)
	_expect(not bool(invalid_status.get("valid", true)), "Duplicate and malformed interaction pivots are reported as invalid")
	_expect(int(invalid_status.get("interaction_count", -1)) == 0, "Duplicate IDs, malformed categories and empty controls are skipped")
	_expect(int(invalid_status.get("hit_area_count", -1)) == 0, "Invalid controls do not leave generated hit areas behind")
	_expect(not invalid_status.get("errors", PackedStringArray()).is_empty(), "Invalid control structure produces explicit diagnostics")

	print("Ship interaction controller tests: %d checks, %d failures." % [_checks, _failures])
	ship_root.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _make_valid_interaction_model() -> Node3D:
	var model_root := Node3D.new()
	model_root.name = "SHIP_root"
	_add_interaction(model_root, "INTERACT_switch_main_power", Vector3(0.2, 0.4, 0.1), Vector3.ZERO)
	_add_interaction(model_root, "INTERACT_switch_field_assist", Vector3(0.2, 0.4, 0.1), Vector3.ZERO)
	_add_interaction(model_root, "INTERACT_lever_throttle", Vector3(0.2, 0.4, 0.1), Vector3(0.0, 0.2, 0.0))
	_add_interaction(model_root, "INTERACT_lever_vector_angle", Vector3(0.2, 0.4, 0.1), Vector3.ZERO)
	_add_interaction(model_root, "INTERACT_button_landing_lights", Vector3(0.2, 0.4, 0.1), Vector3.ZERO)
	return model_root


func _make_invalid_interaction_model() -> Node3D:
	var model_root := Node3D.new()
	model_root.name = "SHIP_root_invalid_interactions"
	var left_group := Node3D.new()
	left_group.name = "LeftGroup"
	model_root.add_child(left_group)
	var right_group := Node3D.new()
	right_group.name = "RightGroup"
	model_root.add_child(right_group)
	_add_interaction(left_group, "INTERACT_switch_duplicate", Vector3(0.2, 0.2, 0.2), Vector3.ZERO)
	_add_interaction(right_group, "INTERACT_switch_duplicate", Vector3(0.2, 0.2, 0.2), Vector3.ZERO)
	_add_interaction(model_root, "INTERACT_knob_fuel", Vector3(0.2, 0.2, 0.2), Vector3.ZERO)
	var empty_interaction := Node3D.new()
	empty_interaction.name = "INTERACT_button_cargo_release"
	model_root.add_child(empty_interaction)
	return model_root


func _add_interaction(parent: Node, interaction_name: String, mesh_size: Vector3, mesh_offset: Vector3) -> Node3D:
	var interaction := Node3D.new()
	interaction.name = interaction_name
	parent.add_child(interaction)
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.name = "MESH_control"
	var box := BoxMesh.new()
	box.size = mesh_size
	visible_mesh.mesh = box
	visible_mesh.position = mesh_offset
	interaction.add_child(visible_mesh)
	return interaction


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
