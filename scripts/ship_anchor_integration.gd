extends Node
class_name ShipAnchorIntegration

## Applies Blender-authored ANCHOR_ transforms to the prototype ship.
## A missing individual anchor never invalidates an otherwise valid GLB:
## the existing scene/Resource-derived position remains the fallback.
## This node must stay after Visuals (so ShipModelMount has loaded) and before
## CameraController, VaneController and RepulsorliftSystem in scenes/ship.tscn.

const DEFINITION_LOADER_SCRIPT = preload("res://scripts/ship_definition_loader.gd")
const PROBE_PROXY_GROUP: StringName = &"ship_model_anchor_proxy"

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable

var _base_seat_transform: Transform3D = Transform3D.IDENTITY
var _base_camera_transform: Transform3D = Transform3D.IDENTITY
var _has_base_transforms: bool = false
var _base_vane_definitions: Array[Resource] = []
var _base_vane_definitions_captured: bool = false
var _generated_probe_aliases: Array[Node3D] = []
var _anchor_registry: RefCounted = null
var _last_status: Dictionary = {}


func _ready() -> void:
	if not is_instance_valid(_ship):
		push_error("ShipAnchorIntegration must be a direct child of ShipInteractable.")
		set_process(false)
		return

	_capture_fallback_transforms()
	_capture_base_vane_definitions()
	refresh_from_mount()


## Loads the same definition/registry already selected by ShipModelMount.
## A missing or rejected GLB is an ordinary no-op; the prototype keeps its
## scene-authored cockpit and Resource-authored vane positions.
func refresh_from_mount() -> Dictionary:
	if not is_instance_valid(_ship):
		return _set_status(false, "Ship root is unavailable.", [], [])

	var mount: Node = _ship.get_node_or_null("Visuals/Exterior/ModelMount")
	if mount == null or not mount.has_method("get_anchor_registry"):
		return _set_status(false, "ShipModelMount is unavailable.", [], [])

	var registry_variant: Variant = mount.call("get_anchor_registry")
	if registry_variant == null or not (registry_variant is RefCounted):
		return _set_status(false, "No validated GLB anchor registry is available.", [], [])

	var definition_path: String = str(mount.get("ship_definition_path"))
	var definition_result: Dictionary = DEFINITION_LOADER_SCRIPT.load_file(definition_path)
	if not bool(definition_result.get("valid", false)):
		var errors: PackedStringArray = definition_result.get("errors", PackedStringArray())
		return _set_status(false, "Ship definition could not be read for anchor integration: %s" % "; ".join(errors), [], [])

	var definition: ShipDefinition = definition_result.get("definition") as ShipDefinition
	if not is_instance_valid(definition):
		return _set_status(false, "Ship definition loader returned no ShipDefinition.", [], [])

	return configure_from_sources(registry_variant as RefCounted, definition)


## Public entry point used by regression tests and by a future model-reload flow.
## `registry` must be a validated ShipAnchorRegistry for the supplied definition.
func configure_from_sources(registry: RefCounted, definition: ShipDefinition) -> Dictionary:
	if not is_instance_valid(_ship):
		return _set_status(false, "Ship root is unavailable.", [], [])
	if registry == null or not registry.has_method("get_anchor"):
		return _set_status(false, "Anchor registry does not expose get_anchor().", [], [])
	if not is_instance_valid(definition):
		return _set_status(false, "Ship definition is unavailable.", [], [])

	_anchor_registry = registry
	_restore_fallback_transforms()
	_clear_generated_probe_aliases()

	var applied: Array[String] = []
	var missing: Array[String] = []
	var missing_seen: Dictionary = {}
	var ship_inverse: Transform3D = _ship.global_transform.affine_inverse()

	_apply_cockpit_anchors(definition, ship_inverse, applied, missing, missing_seen)
	var vane_configuration_valid: bool = _apply_vane_anchors(
		definition, ship_inverse, applied, missing, missing_seen
	)
	_apply_ground_probe_anchors(definition, ship_inverse, applied, missing, missing_seen)
	_refresh_ground_effect_probe_bindings()

	if not vane_configuration_valid:
		return _set_status(false, "Vane configuration was rejected; the previous valid actuator set remains active.", applied, missing)

	if not missing.is_empty():
		push_warning(
			"ShipAnchorIntegration: Missing model anchors; scene/Resource fallbacks remain active for: %s" % ", ".join(missing)
		)

	return _set_status(true, "", applied, missing)


func get_integration_status() -> Dictionary:
	return _last_status.duplicate(true)


func _capture_fallback_transforms() -> void:
	var seat: Node3D = _ship.get_node_or_null("CockpitSeat") as Node3D
	var camera: Camera3D = _ship.get_node_or_null("CockpitSeat/CockpitCamera") as Camera3D
	if is_instance_valid(seat):
		_base_seat_transform = seat.transform
	if is_instance_valid(camera):
		_base_camera_transform = camera.transform
	_has_base_transforms = is_instance_valid(seat) and is_instance_valid(camera)


func _restore_fallback_transforms() -> void:
	if not _has_base_transforms:
		return
	var seat: Node3D = _ship.get_node_or_null("CockpitSeat") as Node3D
	var camera: Camera3D = _ship.get_node_or_null("CockpitSeat/CockpitCamera") as Camera3D
	if is_instance_valid(seat):
		seat.transform = _base_seat_transform
	if is_instance_valid(camera):
		camera.transform = _base_camera_transform


func _capture_base_vane_definitions() -> void:
	_base_vane_definitions.clear()
	var controller: VaneController = _ship.get_node_or_null("VaneController") as VaneController
	if is_instance_valid(controller):
		for resource_variant: Variant in controller.vane_definitions:
			if resource_variant is Resource:
				_base_vane_definitions.append((resource_variant as Resource).duplicate(true))
	_base_vane_definitions_captured = true


func _apply_cockpit_anchors(
		definition: ShipDefinition,
		ship_inverse: Transform3D,
		applied: Array[String],
		missing: Array[String],
		missing_seen: Dictionary
) -> void:
	var camera_config: Dictionary = definition.cameras
	var seat_anchor_id: String = _normalize_anchor_id(str(camera_config.get("seat_anchor", "pilot_seat")))
	var camera_anchor_id: String = _normalize_anchor_id(str(camera_config.get("cockpit_anchor", "cockpit_camera")))
	var seat: Node3D = _ship.get_node_or_null("CockpitSeat") as Node3D
	var camera: Camera3D = _ship.get_node_or_null("CockpitSeat/CockpitCamera") as Camera3D

	var seat_source: Node3D = _get_anchor(seat_anchor_id)
	if is_instance_valid(seat_source) and is_instance_valid(seat):
		seat.transform = ship_inverse * seat_source.global_transform
		applied.append(seat_anchor_id)
	else:
		_add_missing(seat_anchor_id, missing, missing_seen)

	var camera_source: Node3D = _get_anchor(camera_anchor_id)
	if is_instance_valid(camera_source) and is_instance_valid(camera) and is_instance_valid(seat):
		# The camera is a child of the seat Marker3D. Convert the authored ship-
		# local camera transform into that parent's local coordinate space.
		var camera_ship_transform: Transform3D = ship_inverse * camera_source.global_transform
		camera.transform = seat.transform.affine_inverse() * camera_ship_transform
		applied.append(camera_anchor_id)
	else:
		_add_missing(camera_anchor_id, missing, missing_seen)


func _apply_vane_anchors(
		definition: ShipDefinition,
		ship_inverse: Transform3D,
		applied: Array[String],
		missing: Array[String],
		missing_seen: Dictionary
) -> bool:
	var controller: VaneController = _ship.get_node_or_null("VaneController") as VaneController
	if not is_instance_valid(controller):
		return true
	if not _base_vane_definitions_captured:
		_capture_base_vane_definitions()

	# Base .tres entries provide safe fallback positions and legacy tuning. JSON
	# is authoritative for which actuators exist; extra JSON entries are valid.
	var base_by_id: Dictionary = {}
	for base_resource: Resource in _base_vane_definitions:
		if not is_instance_valid(base_resource):
			continue
		base_by_id[StringName(str(base_resource.get("vane_id")))] = base_resource

	var runtime_definitions: Array[Resource] = []
	var registered_ids: Dictionary = {}
	var definition_errors: Array[String] = []
	for vane_variant: Variant in definition.vanes:
		if not (vane_variant is Dictionary):
			definition_errors.append("A vane entry is not an object.")
			continue
		var vane_data: Dictionary = vane_variant
		var vane_id: String = str(vane_data.get("id", "")).strip_edges()
		if vane_id.is_empty():
			definition_errors.append("A vane entry has an empty ID.")
			continue
		if registered_ids.has(vane_id):
			definition_errors.append("Duplicate vane ID '%s'." % vane_id)
			continue
		registered_ids[vane_id] = true

		var resource_id: StringName = StringName(vane_id)
		var runtime_resource: VaneDefinition
		if base_by_id.has(resource_id):
			runtime_resource = (base_by_id[resource_id] as Resource).duplicate(true) as VaneDefinition
		else:
			runtime_resource = VaneDefinition.new()
		runtime_resource.vane_id = resource_id
		runtime_resource.display_name = str(vane_data.get("display_name", vane_id))
		runtime_resource.group_id = StringName(str(vane_data.get("group", "")))
		runtime_resource.nominal_authority_twr = float(vane_data.get("authority_twr", runtime_resource.nominal_authority_twr))
		runtime_resource.enabled = bool(vane_data.get("enabled", runtime_resource.enabled))
		var weights_variant: Variant = vane_data.get("control_weights", runtime_resource.control_weights)
		if weights_variant is Dictionary:
			runtime_resource.control_weights = (weights_variant as Dictionary).duplicate(true)
		elif vane_data.has("control_weights"):
			definition_errors.append("Vane '%s' control_weights must be an object." % vane_id)

		var anchor_name: String = str(vane_data.get("anchor", "")).strip_edges()
		var anchor_id: String = _normalize_anchor_id(anchor_name)
		var axis_data: Dictionary = _axis_from_vane_anchor(anchor_name)
		if not axis_data.is_empty():
			runtime_resource.axis_family = StringName(axis_data["family"])
			runtime_resource.local_thrust_axis = axis_data["axis"]
		elif not base_by_id.has(resource_id):
			runtime_resource.enabled = false
			push_warning(
				"ShipAnchorIntegration: New vane '%s' has no recognized axis-family anchor prefix; it remains disabled." % vane_id
			)

		if not anchor_id.is_empty():
			var anchor_node: Node3D = _get_anchor(anchor_id)
			if is_instance_valid(anchor_node):
				runtime_resource.local_position = ship_inverse * anchor_node.global_position
				applied.append(anchor_id)
			elif not base_by_id.has(resource_id):
				# A new actuator with no authored anchor has no meaningful lever arm.
				# Keep it disabled, but reject no otherwise valid sibling actuator.
				runtime_resource.enabled = false
				_add_missing(anchor_id, missing, missing_seen)
			else:
				_add_missing(anchor_id, missing, missing_seen)
		else:
			if not base_by_id.has(resource_id):
				runtime_resource.enabled = false
				push_warning("ShipAnchorIntegration: New vane '%s' has no anchor name; it remains disabled." % vane_id)
			else:
				push_warning("ShipAnchorIntegration: Vane '%s' has no anchor name; its fallback position remains active." % vane_id)

		runtime_definitions.append(runtime_resource)

	if runtime_definitions.is_empty():
		definition_errors.append("Ship definition contains no usable vane entries.")

	if not definition_errors.is_empty():
		push_error("ShipAnchorIntegration: Vane definition rejected: %s" % "; ".join(definition_errors))
		return false

	# Use the controller's public transactional API. It validates the complete
	# candidate set and only swaps definitions after successful validation.
	var configuration_result: Dictionary = controller.configure_vanes(runtime_definitions)
	if not bool(configuration_result.get("success", false)):
		var controller_errors: PackedStringArray = configuration_result.get("errors", PackedStringArray())
		push_error("ShipAnchorIntegration: VaneController rejected the actuator set: %s" % "; ".join(controller_errors))
		return false
	return true


func _axis_from_vane_anchor(anchor_name: String) -> Dictionary:
	var normalized: String = anchor_name.strip_edges()
	if normalized.begins_with("ANCHOR_"):
		normalized = normalized.substr("ANCHOR_".length())
	if normalized.begins_with("vane_vertical_"):
		return {"family": "vertical", "axis": Vector3.UP}
	if normalized.begins_with("vane_horizontal_side_"):
		return {"family": "horizontal_side", "axis": Vector3.RIGHT}
	if normalized.begins_with("vane_horizontal_main_"):
		return {"family": "horizontal_main", "axis": Vector3.BACK}
	return {}


func _apply_ground_probe_anchors(
		definition: ShipDefinition,
		ship_inverse: Transform3D,
		applied: Array[String],
		missing: Array[String],
		missing_seen: Dictionary
) -> void:
	var ground_config: Dictionary = definition.ground_effect
	if ground_config.is_empty() or not bool(ground_config.get("enabled", false)):
		return
	var probe_names_variant: Variant = ground_config.get("probe_anchors", [])
	if not (probe_names_variant is Array):
		return

	for probe_name_variant: Variant in probe_names_variant:
		var anchor_id: String = _normalize_anchor_id(str(probe_name_variant))
		if anchor_id.is_empty():
			continue
		var anchor_node: Node3D = _get_anchor(anchor_id)
		if not is_instance_valid(anchor_node):
			_add_missing(anchor_id, missing, missing_seen)
			continue
		if _create_ground_probe_alias(anchor_id, ship_inverse * anchor_node.global_transform):
			applied.append(anchor_id)
		else:
			_add_missing(anchor_id, missing, missing_seen)


func _create_ground_probe_alias(anchor_id: String, local_transform: Transform3D) -> bool:
	# RepulsorliftGroundEffectSystem resolves configured probe names as direct
	# ship children. These invisible Marker3D aliases preserve that API while
	# their transforms come from the nested GLB anchor registry.
	var existing: Node = _ship.get_node_or_null(NodePath(anchor_id))
	var proxy: Marker3D = existing as Marker3D
	if existing != null and not is_instance_valid(proxy):
		push_warning("ShipAnchorIntegration: Cannot create probe alias '%s'; a non-Marker3D child already uses that name." % anchor_id)
		return false
	if is_instance_valid(proxy) and not proxy.is_in_group(PROBE_PROXY_GROUP):
		push_warning("ShipAnchorIntegration: Cannot replace user-authored child '%s' with a model anchor alias." % anchor_id)
		return false
	if not is_instance_valid(proxy):
		proxy = Marker3D.new()
		proxy.name = anchor_id
		proxy.add_to_group(PROBE_PROXY_GROUP)
		_ship.add_child(proxy)
		_generated_probe_aliases.append(proxy)
	proxy.transform = local_transform
	return true


func _refresh_ground_effect_probe_bindings() -> void:
	var ground_effect_system: Node = _ship.get_node_or_null("RepulsorliftSystem")
	if is_instance_valid(ground_effect_system) and ground_effect_system.has_method("_resolve_probe_nodes"):
		# Before the ground-effect node's _ready this is a harmless empty refresh;
		# when called after a model reload it rebinds its cached Node3D references.
		ground_effect_system.call("_resolve_probe_nodes")


func _clear_generated_probe_aliases() -> void:
	for proxy: Node3D in _generated_probe_aliases:
		if is_instance_valid(proxy) and proxy.get_parent() == _ship:
			_ship.remove_child(proxy)
			proxy.free()
	_generated_probe_aliases.clear()


func _get_anchor(anchor_id_or_name: String) -> Node3D:
	if _anchor_registry == null or not _anchor_registry.has_method("get_anchor"):
		return null
	var anchor_id: String = _normalize_anchor_id(anchor_id_or_name)
	if anchor_id.is_empty():
		return null
	return _anchor_registry.call("get_anchor", anchor_id) as Node3D


func _normalize_anchor_id(anchor_id_or_name: String) -> String:
	var value: String = anchor_id_or_name.strip_edges()
	if value.begins_with("ANCHOR_"):
		return value.substr("ANCHOR_".length())
	return value


func _add_missing(anchor_id: String, missing: Array[String], seen: Dictionary) -> void:
	if anchor_id.is_empty() or seen.has(anchor_id):
		return
	seen[anchor_id] = true
	missing.append(anchor_id)


func _set_status(success: bool, reason: String, applied: Array[String], missing: Array[String]) -> Dictionary:
	_last_status = {
		"success": success,
		"reason": reason,
		"applied_anchor_ids": PackedStringArray(applied),
		"missing_anchor_ids": PackedStringArray(missing),
		"applied_count": applied.size(),
		"missing_count": missing.size(),
	}
	return _last_status.duplicate(true)
