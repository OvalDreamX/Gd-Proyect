extends SceneTree

## Run: godot --headless --path . --script res://tests/ship_anchor_integration_test.gd
## Creates temporary in-memory model roots; it does not need a committed GLB.
const SHIP_SCENE = preload("res://scenes/ship_ground_effect.tscn")
const ANCHOR_REGISTRY_SCRIPT = preload("res://scripts/ship_anchor_registry.gd")
const DEFINITION_LOADER_SCRIPT = preload("res://scripts/ship_definition_loader.gd")
const ANCHOR_INTEGRATION_SCRIPT = preload("res://scripts/ship_anchor_integration.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var ship: ShipInteractable = SHIP_SCENE.instantiate() as ShipInteractable
	root.add_child(ship)
	await process_frame

	var definition_result: Dictionary = DEFINITION_LOADER_SCRIPT.load_file(
		"res://data/ships/prototype_freighter/ship.json"
	)
	_expect(bool(definition_result.get("valid", false)), "Migrated prototype ship definition remains valid")
	var definition: ShipDefinition = definition_result.get("definition") as ShipDefinition
	var mount: Node = ship.get_node("Visuals/Exterior/ModelMount")
	var integration: Node = ship.get_node("AnchorIntegration") as Node
	_expect(
		integration.get_script() == ANCHOR_INTEGRATION_SCRIPT,
		"AnchorIntegration node uses the explicitly preloaded script resource"
	)
	var vane_controller: VaneController = ship.get_node("VaneController") as VaneController

	var ground_effect_system: Node = ship.get_node("RepulsorliftSystem")
	_expect(
		ground_effect_system is RepulsorliftGroundEffectSystem,
		"Ground-effect ship variant still overrides the correct node after AnchorIntegration was inserted"
	)

	var full_positions: Dictionary = {
		"pilot_seat": Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(14.0), 0.0)),
			Vector3(0.15, 0.92, -0.82)
		),
		"cockpit_camera": Transform3D(
			Basis.from_euler(Vector3(deg_to_rad(-3.0), deg_to_rad(9.0), 0.0)),
			Vector3(0.15, 1.13, -1.47)
		),
		"ground_probe_front_left": Vector3(-1.35, -0.72, -2.05),
		"ground_probe_front_right": Vector3(1.35, -0.72, -2.05),
		"ground_probe_rear_left": Vector3(-1.35, -0.72, 2.05),
		"ground_probe_rear_right": Vector3(1.35, -0.72, 2.05),
		"vane_vertical_a": Vector3(-1.1, -0.61, -1.55),
		"vane_vertical_b": Vector3(1.1, -0.61, -1.55),
		"vane_vertical_c": Vector3(-1.1, -0.61, 1.55),
		"vane_vertical_d": Vector3(1.1, -0.61, 1.55),
		"vane_horizontal_main_a": Vector3(0.0, 0.08, 2.78),
		"vane_horizontal_main_side_left": Vector3(-1.62, 0.04, 0.12),
		"vane_horizontal_main_side_right": Vector3(1.62, 0.04, 0.12),
	}
	var full_model: Dictionary = await _make_model_and_registry(mount, full_positions)
	var full_registry: ShipAnchorRegistry = full_model["registry"] as ShipAnchorRegistry
	var full_anchors: Dictionary = full_model["anchors"]
	var full_result: Dictionary = integration.call("configure_from_sources", full_registry, definition)

	_expect(bool(full_result.get("success", false)), "Full anchor set integrates successfully")
	_expect(
		_transforms_match(
			(ship.get_node("CockpitSeat") as Node3D).global_transform,
			(full_anchors["pilot_seat"] as Node3D).global_transform
		),
		"Blender pilot-seat anchor drives the complete runtime seat transform"
	)
	_expect(
		_transforms_match(
			(ship.get_node("CockpitSeat/CockpitCamera") as Camera3D).global_transform,
			(full_anchors["cockpit_camera"] as Node3D).global_transform
		),
		"Blender cockpit-camera anchor drives the complete runtime camera transform"
	)

	var left_vane_resource: Resource = _find_vane_resource(vane_controller, "bottom_front_left")
	var expected_left_vane: Vector3 = ship.global_transform.affine_inverse() * (
		full_anchors["vane_vertical_a"] as Node3D
	).global_position
	var actual_left_vane: Vector3 = left_vane_resource.get("local_position") if left_vane_resource != null else Vector3.ZERO
	_expect(
		left_vane_resource != null and actual_left_vane.is_equal_approx(expected_left_vane),
		"Blender vane anchor replaces the runtime application point"
	)
	var source_vane: Resource = load("res://data/vanes/bottom_front_left.tres") as Resource
	var source_vane_position: Vector3 = source_vane.get("local_position")
	_expect(
		source_vane_position.is_equal_approx(Vector3(-1.2, -0.65, -1.8)),
		"Applying a Blender anchor does not mutate the shared .tres vane definition"
	)
	_expect(
		(ship.get_node_or_null("ground_probe_front_left") as Marker3D) != null
		and (ship.get_node("ground_probe_front_left") as Marker3D).global_position.distance_to(
			(full_anchors["ground_probe_front_left"] as Node3D).global_position
		) < 0.0001,
		"Ground-probe alias exposes the Blender anchor to the existing ground-effect lookup"
	)
	var resolved_probe_nodes: Array = ground_effect_system.get("_ground_effect_probe_nodes")
	_expect(
		resolved_probe_nodes.size() == 4
		and resolved_probe_nodes[0] == ship.get_node("ground_probe_front_left"),
		"Ground-effect system resolves the generated probe alias rather than using the fallback point"
	)
	_expect(int(full_result.get("missing_count", -1)) == 0, "Complete Phase 2C anchor set reports no missing anchors")
	var left_vane_axis: Vector3 = left_vane_resource.get("local_thrust_axis") if left_vane_resource != null else Vector3.ZERO
	var left_vane_weights: Dictionary = left_vane_resource.get("control_weights") if left_vane_resource != null else {}
	_expect(
		left_vane_resource != null
		and StringName(str(left_vane_resource.get("axis_family"))) == &"vertical"
		and left_vane_axis.is_equal_approx(Vector3.UP)
		and int(left_vane_weights.get("pitch", 0)) == 100
		and int(left_vane_weights.get("lift", 0)) == 100,
		"Vane anchor naming defines its bidirectional local axis and JSON control weights are applied"
	)

	var port_yaw_vane: VaneDefinition = vane_controller.get_vane_definition(&"side_left")
	var starboard_yaw_vane: VaneDefinition = vane_controller.get_vane_definition(&"side_right")
	_expect(
		port_yaw_vane != null and starboard_yaw_vane != null
		and port_yaw_vane.axis_family == &"horizontal_main"
		and starboard_yaw_vane.axis_family == &"horizontal_main"
		and port_yaw_vane.local_thrust_axis.is_equal_approx(Vector3.BACK)
		and starboard_yaw_vane.local_thrust_axis.is_equal_approx(Vector3.BACK),
		"Side-mounted yaw anchors resolve to the longitudinal bidirectional thrust axis"
	)
	_expect(
		port_yaw_vane != null and starboard_yaw_vane != null
		and port_yaw_vane.local_position.x < 0.0
		and starboard_yaw_vane.local_position.x > 0.0,
		"Yaw vane anchors preserve the port/starboard lever-arm separation"
	)

	# A ship definition may declare more actuators than the prototype .tres set.
	# They must be registered without a fixed seven-vane assumption.
	var extra_anchor := Node3D.new()
	extra_anchor.name = "ANCHOR_vane_vertical_extra"
	extra_anchor.position = Vector3(0.0, -0.7, 0.0)
	(full_model["root"] as Node3D).add_child(extra_anchor)
	await process_frame
	# ShipDefinition is a RefCounted data object, not a Resource; it has no
	# built-in duplicate(). Copy the mutable vane array for this focused test,
	# temporarily assign it, then restore the original definition immediately.
	var base_vanes: Array[Dictionary] = []
	for vane_entry: Dictionary in definition.vanes:
		base_vanes.append(vane_entry.duplicate(true))
	var extended_vanes: Array[Dictionary] = []
	for vane_entry: Dictionary in base_vanes:
		extended_vanes.append(vane_entry.duplicate(true))
	extended_vanes.append({
		"id": "auxiliary_vertical",
		"display_name": "Auxiliary Vertical Actuator",
		"anchor": "ANCHOR_vane_vertical_extra",
		"group": "auxiliary",
		"authority_twr": 0.05,
		"control_weights": {"pitch": 25, "roll": 50, "yaw": 0, "lift": 75, "main_thrust": 0},
	})
	# Reconfiguration must not reset the live condition of existing actuators.
	vane_controller.set_vane_temperature(&"bottom_front_left", 87.0)
	definition.vanes = extended_vanes
	var extended_registry_result: Dictionary = full_registry.rebuild(full_model["root"] as Node3D)
	_expect(bool(extended_registry_result.get("valid", false)), "Registry accepts an additional named actuator anchor")
	var extended_result: Dictionary = integration.call("configure_from_sources", full_registry, definition)
	var extra_definition: VaneDefinition = vane_controller.get_vane_definition(&"auxiliary_vertical")
	var expected_extra_position: Vector3 = ship.global_transform.affine_inverse() * extra_anchor.global_position
	var extended_state_preserved: bool = is_equal_approx(
		vane_controller.get_vane_temperature(&"bottom_front_left"), 87.0
	)
	var extra_position: Vector3 = extra_definition.local_position if extra_definition != null else Vector3.ZERO
	var extra_axis_family: String = String(extra_definition.axis_family) if extra_definition != null else "<missing>"
	var extra_lift_weight: int = extra_definition.get_control_weight(&"lift") if extra_definition != null else -1
	var extra_registration_valid: bool = (
		vane_controller.get_vane_count() == 8
		and extra_definition != null
		and extra_axis_family == "vertical"
		and extra_definition.local_thrust_axis.is_equal_approx(Vector3.UP)
		and extra_position.is_equal_approx(expected_extra_position)
		and extra_definition.get_control_weight(&"pitch") == 25
		and extra_definition.get_control_weight(&"roll") == 50
		and extra_lift_weight == 75
	)
	_expect(bool(extended_result.get("success", false)), "Extended actuator configuration integrates successfully")
	_expect(
		extra_registration_valid,
		"JSON can add an eighth actuator (count=%d, family=%s, position=%s, expected=%s, lift_weight=%d)" % [
			vane_controller.get_vane_count(), extra_axis_family, str(extra_position), str(expected_extra_position), extra_lift_weight
		]
	)
	_expect(extended_state_preserved, "Reconfiguration preserves existing actuator thermal state by stable ID")

	# Restore the canonical definition before testing fallback behavior. Assert
	# both the count and the identity set: a matching count alone can hide a stale
	# actuator replacing a declared one.
	definition.vanes = base_vanes
	var restored_definition_result: Dictionary = integration.call("configure_from_sources", full_registry, definition)
	var restored_extra_definition: VaneDefinition = vane_controller.get_vane_definition(&"auxiliary_vertical")
	var restored_vane_ids: Array[StringName] = vane_controller.get_vane_ids()
	_expect(
		bool(restored_definition_result.get("success", false))
		and vane_controller.get_vane_count() == base_vanes.size()
		and restored_extra_definition == null
		and not restored_vane_ids.has(&"auxiliary_vertical"),
		"Base definition removes undeclared actuators (count=%d, extra_registered=%s)" % [
			vane_controller.get_vane_count(), str(restored_extra_definition != null)
		]
	)

	# An invalid candidate is rejected as a transaction. The active valid set is
	# retained instead of being partially cleared or partially replaced.
	# Godot JSON numeric values may be represented by int or float Variants.
	# Whole-valued floats are valid schema numbers; fractional values are not.
	var numeric_weight_candidate := VaneDefinition.new()
	numeric_weight_candidate.vane_id = &"numeric_weight_candidate"
	numeric_weight_candidate.group_id = &"test_group"
	numeric_weight_candidate.control_weights = {"pitch": 25.0, "roll": 50.0}
	var numeric_weight_resources: Array[Resource] = [numeric_weight_candidate]
	var numeric_weight_result: Dictionary = vane_controller.configure_vanes(numeric_weight_resources)
	_expect(
		bool(numeric_weight_result.get("success", false))
		and vane_controller.get_vane_definition(&"numeric_weight_candidate") != null
		and vane_controller.get_vane_definition(&"numeric_weight_candidate").get_control_weight(&"pitch") == 25,
		"Whole-valued JSON float control weights are accepted and read as integers"
	)
	# Return to the ship definition before exercising rejected candidates.
	var after_numeric_restore: Dictionary = integration.call("configure_from_sources", full_registry, definition)
	_expect(
		bool(after_numeric_restore.get("success", false))
		and vane_controller.get_vane_count() == base_vanes.size()
		and vane_controller.get_vane_definition(&"numeric_weight_candidate") == null,
		"Restoring ship definition removes temporary validation actuator"
	)

	var invalid_candidate := VaneDefinition.new()
	invalid_candidate.vane_id = &"invalid_candidate"
	invalid_candidate.group_id = &"test_group"
	invalid_candidate.control_weights = {"pitch": 101}
	var invalid_resources: Array[Resource] = [invalid_candidate]
	var invalid_configuration_result: Dictionary = vane_controller.configure_vanes(invalid_resources)
	_expect(
		not bool(invalid_configuration_result.get("success", true))
		and vane_controller.get_vane_count() == base_vanes.size()
		and vane_controller.get_vane_definition(&"invalid_candidate") == null,
		"Out-of-range actuator weights are rejected without disturbing the active valid set"
	)
	var fractional_candidate := VaneDefinition.new()
	fractional_candidate.vane_id = &"fractional_candidate"
	fractional_candidate.group_id = &"test_group"
	fractional_candidate.control_weights = {"pitch": 25.5}
	var fractional_resources: Array[Resource] = [fractional_candidate]
	var fractional_result: Dictionary = vane_controller.configure_vanes(fractional_resources)
	_expect(
		not bool(fractional_result.get("success", true))
		and vane_controller.get_vane_count() == base_vanes.size()
		and vane_controller.get_vane_definition(&"fractional_candidate") == null,
		"Fractional actuator weights are rejected without disturbing the active valid set"
	)
	vane_controller.set_vane_temperature(&"bottom_front_left", -10.0)

	# A partial model must not retain transforms from a previous model. It must
	# restore the TSCN/.tres fallbacks for every missing anchor.
	var full_root: Node3D = full_model["root"] as Node3D
	mount.remove_child(full_root)
	full_root.free()
	var partial_positions: Dictionary = {
		"pilot_seat": Vector3(-0.2, 0.88, -0.76),
	}
	var partial_model: Dictionary = await _make_model_and_registry(mount, partial_positions)
	var partial_registry: ShipAnchorRegistry = partial_model["registry"] as ShipAnchorRegistry
	var partial_result: Dictionary = integration.call("configure_from_sources", partial_registry, definition)

	_expect(bool(partial_result.get("success", false)), "Partial anchor set is accepted without rejecting the model")
	_expect(
		(ship.get_node("CockpitSeat") as Node3D).global_position.distance_to(
			(partial_model["anchors"]["pilot_seat"] as Node3D).global_position
		) < 0.0001,
		"Available seat anchor remains active in a partial model"
	)
	_expect(
		(ship.get_node("CockpitSeat/CockpitCamera") as Camera3D).position.is_equal_approx(Vector3(0.0, 0.12, -0.55)),
		"Missing camera anchor restores the scene-authored camera fallback"
	)
	source_vane = load("res://data/vanes/bottom_front_left.tres") as Resource
	var expected_fallback_vane: Vector3 = source_vane.get("local_position")
	left_vane_resource = _find_vane_resource(vane_controller, "bottom_front_left")
	var restored_vane_position: Vector3 = left_vane_resource.get("local_position") if left_vane_resource != null else Vector3.ZERO
	_expect(
		left_vane_resource != null and restored_vane_position.is_equal_approx(expected_fallback_vane),
		"Missing vane anchor restores the original .tres fallback rather than retaining stale model coordinates"
	)
	_expect(
		ship.get_node_or_null("ground_probe_front_left") == null,
		"Missing probe anchor removes the old model proxy so ground effect uses its configured fallback"
	)
	resolved_probe_nodes = ground_effect_system.get("_ground_effect_probe_nodes")
	_expect(
		resolved_probe_nodes.size() == 4 and resolved_probe_nodes[0] == null,
		"Ground-effect system is rebound to fallback mode when a model probe is absent"
	)
	_expect(int(partial_result.get("missing_count", 0)) >= 1, "Partial model reports missing required anchors")

	print("Ship anchor integration tests: %d checks, %d failures." % [_checks, _failures])
	ship.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _make_model_and_registry(mount: Node, positions: Dictionary) -> Dictionary:
	var model_root := Node3D.new()
	model_root.name = "SHIP_root"
	mount.add_child(model_root)

	var hull := MeshInstance3D.new()
	hull.name = "MESH_hull_main"
	hull.mesh = BoxMesh.new()
	model_root.add_child(hull)

	var anchors: Dictionary = {}
	for anchor_id_variant: Variant in positions.keys():
		var anchor_id: String = str(anchor_id_variant)
		var anchor := Node3D.new()
		anchor.name = "ANCHOR_" + anchor_id
		var authored_transform: Variant = positions[anchor_id_variant]
		if authored_transform is Transform3D:
			anchor.transform = authored_transform
		else:
			anchor.position = authored_transform
		model_root.add_child(anchor)
		anchors[anchor_id] = anchor

	await process_frame
	var registry := ANCHOR_REGISTRY_SCRIPT.new() as ShipAnchorRegistry
	var validation: Dictionary = registry.rebuild(model_root)
	_expect(bool(validation.get("valid", false)), "Synthetic GLB hierarchy satisfies the structural model validator")
	return {"root": model_root, "registry": registry, "anchors": anchors}


func _transforms_match(first: Transform3D, second: Transform3D, tolerance: float = 0.0001) -> bool:
	return (
		first.origin.distance_to(second.origin) <= tolerance
		and first.basis.x.distance_to(second.basis.x) <= tolerance
		and first.basis.y.distance_to(second.basis.y) <= tolerance
		and first.basis.z.distance_to(second.basis.z) <= tolerance
	)


func _find_vane_resource(controller: VaneController, vane_id: String) -> Resource:
	for resource_variant: Variant in controller.vane_definitions:
		if resource_variant is Resource and str((resource_variant as Resource).get("vane_id")) == vane_id:
			return resource_variant as Resource
	return null


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
