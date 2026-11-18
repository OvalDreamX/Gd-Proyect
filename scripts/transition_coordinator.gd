extends Node

## Autoload TransitionCoordinator for Phase 3F fixed-route hyperspace jumps.
## Owns the transition state machine, duplicate-jump lock, hyperspace visual overlay,
## destination scene validation, ArrivalResolver placement, SimulationClock commit, and recovery.

const JUMP_CALCULATOR_SCRIPT = preload("res://scripts/jump_calculator.gd")
const ARRIVAL_RESOLVER_SCRIPT = preload("res://scripts/arrival_resolver.gd")
const JUMP_ENVELOPE_SCRIPT = preload("res://scripts/jump_envelope_evaluator.gd")

const ROUTE_PLANET_TO_STATION_PATH: String = "res://data/routes/route_planet_to_station.tres"
const ROUTE_STATION_TO_PLANET_PATH: String = "res://data/routes/route_station_to_planet.tres"

enum TransitionState {
	IDLE,
	VALIDATING,
	HYPERSPACE,
	LOADING,
	COMMITTING,
	FAILED_RECOVERY,
}

signal transition_state_changed(state_name: String)
signal jump_completed(jump_result: Dictionary)
signal jump_failed(error_code: String, error_message: String)
signal jump_finished(result: Dictionary)

var _state: TransitionState = TransitionState.IDLE
var _last_attempt_result: Dictionary = {}
var _last_jump_result: Dictionary = {}
var _last_error_code: String = ""
var _last_error_message: String = ""
var _overlay_layer: CanvasLayer
var _overlay_control: Control
var _overlay_streak_progress: float = 0.0
var _overlay_title: String = ""
var _overlay_subtitle: String = ""
var _overlay_is_error: bool = false
var _headless_fast_visual: bool = true

class HyperspaceCanvas extends Control:
	var streak_progress: float = 0.0
	var title_text: String = ""
	var subtitle_text: String = ""
	var is_error: bool = false

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.018, 0.035, 0.94), true)
		var center := size * 0.5
		var rng := RandomNumberGenerator.new()
		rng.seed = 303601
		var line_color: Color = Color(1.0, 0.38, 0.28, 0.7) if is_error else Color(0.45, 0.88, 1.0, 0.85)
		for idx in range(72):
			var angle: float = rng.randf_range(0.0, TAU)
			var base_r: float = rng.randf_range(28.0, minf(size.x, size.y) * 0.25)
			var travel: float = fposmod(base_r + streak_progress * 380.0, minf(size.x, size.y) * 0.65)
			var streak_len: float = 16.0 if is_error else (38.0 + travel * 0.35)
			var dir := Vector2(cos(angle), sin(angle))
			draw_line(center + dir * travel, center + dir * (travel + streak_len), line_color, 1.4)
		var font: Font = ThemeDB.fallback_font
		if font != null:
			draw_string(font, Vector2(0.0, center.y - 16.0), title_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, line_color)
			draw_string(font, Vector2(0.0, center.y + 14.0), subtitle_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Color(0.82, 0.92, 0.96, 0.92))

func _ready() -> void:
	_build_overlay()

func get_state() -> int:
	return _state

func get_state_name() -> String:
	match _state:
		TransitionState.IDLE:
			return "IDLE"
		TransitionState.VALIDATING:
			return "VALIDATING"
		TransitionState.HYPERSPACE:
			return "HYPERSPACE"
		TransitionState.LOADING:
			return "LOADING"
		TransitionState.COMMITTING:
			return "COMMITTING"
		TransitionState.FAILED_RECOVERY:
			return "FAILED_RECOVERY"
	return "UNKNOWN"

func is_transitioning() -> bool:
	return _state != TransitionState.IDLE

func get_last_jump_result() -> Dictionary:
	return _last_jump_result.duplicate(true)

func get_last_error() -> Dictionary:
	return {
		"error_code": _last_error_code,
		"error_message": _last_error_message,
	}

func get_default_route_for_environment(env_id: String, env_type: String) -> Resource:
	var path: String = ""
	if env_id == "env_test_planet_surface" or env_type == "PLANET_SURFACE":
		path = ROUTE_PLANET_TO_STATION_PATH
	elif env_id == "env_station_local_space" or env_type == "LOCAL_SPACE":
		path = ROUTE_STATION_TO_PLANET_PATH
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)

func get_telemetry() -> Dictionary:
	return {
		"transition_state": get_state_name(),
		"transition_active": is_transitioning(),
		"transition_last_error_code": _last_error_code,
		"transition_last_error_message": _last_error_message,
		"last_jump_route_id": str(_last_jump_result.get("route_id", "")),
		"last_jump_destination_id": str(_last_jump_result.get("destination_location_id", "")),
		"last_jump_arrival_sim_time_s": float(_last_jump_result.get("arrival_sim_time_s", 0.0)),
	}

func request_jump(ship: RigidBody3D, route_override: Resource = null, source_world_override: Node = null) -> Dictionary:
	if _state != TransitionState.IDLE:
		return {
			"accepted": false,
			"valid": false,
			"error_code": "TRANSITION_IN_PROGRESS",
			"error_message": "Jump transition already in progress.",
		}

	if not is_instance_valid(ship):
		return _fail_before_load("SHIP_MISSING", "No active ship available for jump transition.")

	_set_state(TransitionState.VALIDATING)
	var source_world: Node = source_world_override if is_instance_valid(source_world_override) else _resolve_source_world(ship)
	var env_manager: Node = _resolve_env_manager(source_world)
	var exclusion_origin: Node3D = get_tree().get_first_node_in_group("jump_exclusion_origin") as Node3D if is_inside_tree() else null
	var sensors := ship.get_node_or_null("FlightSensorSuite")
	var sensor_snap: Dictionary = sensors.call("get_instrument_snapshot") if is_instance_valid(sensors) and sensors.has_method("get_instrument_snapshot") else {}
	var controller := ship.get_node_or_null("FlightController")
	var field_state_name: String = str(controller.call("_field_state_name")) if is_instance_valid(controller) and controller.has_method("_field_state_name") else "OFF"
	var excl_pos: Vector3 = exclusion_origin.global_position if is_instance_valid(exclusion_origin) else Vector3.ZERO
	var envelope_ctx: Dictionary = JUMP_ENVELOPE_SCRIPT.build_context_from_nodes(ship, sensor_snap, env_manager, field_state_name, excl_pos)
	var envelope_res: Dictionary = JUMP_ENVELOPE_SCRIPT.evaluate(envelope_ctx)

	var env_id: String = str(envelope_res.get("jump_environment_id", ""))
	var env_type: String = str(envelope_res.get("jump_environment_type", ""))
	var route: Resource = route_override if route_override != null else get_default_route_for_environment(env_id, env_type)

	var sim_clock: Node = get_node_or_null("/root/SimulationClock")
	var departure_time: float = float(sim_clock.call("get_time_seconds")) if is_instance_valid(sim_clock) else 0.0
	var persistent_state: Dictionary = _capture_persistent_ship_state(ship, controller)
	var jump_result: Dictionary = JUMP_CALCULATOR_SCRIPT.calculate_jump(route, envelope_res, departure_time, persistent_state)

	if not bool(jump_result.get("valid", false)):
		var err_code: String = str(jump_result.get("error_code", "JUMP_REJECTED"))
		var err_msg: String = str(jump_result.get("error_message", "Jump rejected."))
		return _fail_with_recovery(ship, err_code, err_msg)

	# Lock ship physics during hyperspace and loading so no physics ticks mutate departing ship.
	var prev_freeze: bool = ship.freeze
	ship.freeze = true

	_set_state(TransitionState.HYPERSPACE)
	var visual_time: float = 0.06 if (_headless_fast_visual and DisplayServer.get_name() == "headless") else float(jump_result.get("visual_transition_s", 1.6))
	await _play_hyperspace_visual(str(jump_result.get("route_display_name", "HYPERSPACE TRANSIT")), visual_time)

	_set_state(TransitionState.LOADING)
	var dest_path: String = str(jump_result.get("destination_scene_path", ""))
	var packed_res: Resource = ResourceLoader.load(dest_path) if ResourceLoader.exists(dest_path) else null
	if not (packed_res is PackedScene):
		ship.freeze = prev_freeze
		return _fail_with_recovery(ship, "SCENE_LOAD_FAILED", "Failed to load destination scene: %s" % dest_path)

	var next_scene: Node = (packed_res as PackedScene).instantiate()
	if not _validate_destination_scene(next_scene):
		if is_instance_valid(next_scene):
			next_scene.queue_free()
		ship.freeze = prev_freeze
		return _fail_with_recovery(ship, "SCENE_VALIDATION_FAILED", "Destination scene missing required nodes: %s" % dest_path)

	_set_state(TransitionState.COMMITTING)
	var tree := get_tree()
	var was_current_scene: bool = tree != null and tree.current_scene == source_world
	tree.root.add_child(next_scene)
	if was_current_scene:
		tree.current_scene = next_scene

	var apply_res: Dictionary = ARRIVAL_RESOLVER_SCRIPT.apply_arrival_to_scene(next_scene, jump_result)
	if not bool(apply_res.get("valid", false)):
		next_scene.queue_free()
		if was_current_scene and is_instance_valid(source_world):
			tree.current_scene = source_world
		ship.freeze = prev_freeze
		return _fail_with_recovery(ship, "ARRIVAL_APPLY_FAILED", str(apply_res.get("error", "Arrival failed.")))

	# Commit SimulationClock strictly once after destination scene and ship state are ready.
	if is_instance_valid(sim_clock) and sim_clock.has_method("advance_time"):
		sim_clock.call("advance_time", float(jump_result.get("jump_duration_s", 0.0)))

	if is_instance_valid(source_world) and source_world != next_scene:
		source_world.queue_free()

	_last_error_code = ""
	_last_error_message = ""
	_last_jump_result = jump_result.duplicate(true)
	_hide_overlay()
	_set_state(TransitionState.IDLE)
	jump_completed.emit(_last_jump_result)
	return {
		"accepted": true,
		"valid": true,
		"jump_result": _last_jump_result,
		"destination_scene": next_scene,
	}

func _validate_destination_scene(scene_root: Node) -> bool:
	if not is_instance_valid(scene_root):
		return false
	var has_env: bool = scene_root.get_node_or_null("EnvironmentManager") != null
	var has_ship: bool = scene_root.get_node_or_null("Ship") is RigidBody3D
	var has_player: bool = scene_root.get_node_or_null("Player") != null
	return has_env and has_ship and has_player

func _capture_persistent_ship_state(ship: RigidBody3D, controller: Node) -> Dictionary:
	var state: Dictionary = {
		"cargo_preset": "EMPTY",
		"cargo_mass_kg": 0.0,
		"cargo_offset_m": Vector3.ZERO,
		"field_power_command": 0.0,
		"field_power_output": 0.0,
		"vector_distribution_degrees": 90.0,
		"vector_distribution_actual_degrees": 90.0,
		"fcc_assistance_enabled": true,
	}
	var cargo := ship.get_node_or_null("CargoSystem")
	if is_instance_valid(cargo) and cargo.has_method("get_telemetry"):
		var c_tele: Dictionary = cargo.call("get_telemetry")
		state["cargo_preset"] = str(c_tele.get("preset", "EMPTY"))
		state["cargo_mass_kg"] = float(c_tele.get("cargo_mass_kg", 0.0))
		state["cargo_offset_m"] = Vector3(c_tele.get("cargo_offset_m", Vector3.ZERO))
	if is_instance_valid(controller):
		state["field_power_command"] = float(controller.get("_field_power_command"))
		state["field_power_output"] = float(controller.get("_field_power_output"))
		state["vector_distribution_degrees"] = float(controller.get("_vector_distribution_degrees"))
		state["vector_distribution_actual_degrees"] = float(controller.get("_vector_distribution_actual_degrees"))
	var fcc := ship.get_node_or_null("FlightControlComputer")
	if is_instance_valid(fcc):
		state["fcc_assistance_enabled"] = bool(fcc.get("assistance_enabled"))
	return state

func _resolve_source_world(ship: RigidBody3D) -> Node:
	var tree := get_tree()
	if tree != null and is_instance_valid(tree.current_scene):
		return tree.current_scene
	var parent: Node = ship.get_parent()
	return parent

func _resolve_env_manager(source_world: Node) -> Node:
	if is_instance_valid(source_world):
		var local_env: Node = source_world.get_node_or_null("EnvironmentManager")
		if is_instance_valid(local_env):
			return local_env
	if is_inside_tree():
		return get_tree().get_first_node_in_group("environment_manager")
	return null

func _fail_before_load(code: String, message: String) -> Dictionary:
	_last_error_code = code
	_last_error_message = message
	_set_state(TransitionState.IDLE)
	jump_failed.emit(code, message)
	return {
		"accepted": false,
		"valid": false,
		"error_code": code,
		"error_message": message,
	}

func _fail_with_recovery(ship: RigidBody3D, code: String, message: String) -> Dictionary:
	_set_state(TransitionState.FAILED_RECOVERY)
	_last_error_code = code
	_last_error_message = message
	if is_instance_valid(ship):
		ship.freeze = false
	_hide_overlay()
	_set_state(TransitionState.IDLE)
	jump_failed.emit(code, message)
	return {
		"accepted": false,
		"valid": false,
		"error_code": code,
		"error_message": message,
	}

func _set_state(new_state: TransitionState) -> void:
	if _state == new_state:
		return
	_state = new_state
	transition_state_changed.emit(get_state_name())

func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "HyperspaceOverlayLayer"
	_overlay_layer.layer = 90
	_overlay_layer.visible = false
	add_child(_overlay_layer)

	_overlay_control = HyperspaceCanvas.new()
	_overlay_control.name = "HyperspaceCanvas"
	_overlay_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_overlay_control)

func _play_hyperspace_visual(route_label: String, duration_s: float) -> void:
	if not is_instance_valid(_overlay_layer) or not is_instance_valid(_overlay_control):
		return
	_overlay_control.set("title_text", "HYPERSPACE TRANSIT")
	_overlay_control.set("subtitle_text", route_label.to_upper())
	_overlay_control.set("is_error", false)
	_overlay_layer.visible = true
	var elapsed: float = 0.0
	var safe_dur: float = maxf(duration_s, 0.02)
	while elapsed < safe_dur and is_inside_tree():
		_overlay_control.set("streak_progress", elapsed / safe_dur)
		_overlay_control.queue_redraw()
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _hide_overlay() -> void:
	if is_instance_valid(_overlay_layer):
		_overlay_layer.visible = false
