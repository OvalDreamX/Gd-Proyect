extends Node

## Runtime access to Blender-exported action_* clips inside the mounted ship GLB.
## The controller owns playback requests only; it does not decide when a ship
## mechanism should move. Gameplay systems will request actions in a later phase.

signal action_started(action_id: StringName)
signal action_finished(action_id: StringName)

const MODEL_MOUNT_PATH: NodePath = NodePath("../ModelMount")
const ACTION_PREFIX: String = "action_"
const BONE_PREFIX: String = "BONE_"
const ROOT_BONE_NAME: StringName = &"BONE_root"
const MINIMUM_ANIMATION_SPEED: float = 0.0001

var _model_root: Node = null
var _animation_players: Array[AnimationPlayer] = []
var _connected_player_callbacks: Array[Dictionary] = []
var _actions: Dictionary = {}
var _player_action_lookup: Dictionary = {}
var _status: Dictionary = {
	"state": "not_initialized",
	"valid": false,
	"rig_valid": false,
	"skeleton_count": 0,
	"bone_count": 0,
	"animation_player_count": 0,
	"action_count": 0,
	"action_names": PackedStringArray(),
	"warnings": PackedStringArray(),
	"errors": PackedStringArray(),
}


func _ready() -> void:
	refresh_from_mount()


## Re-discovers the model after ShipModelMount loads or reloads a GLB.
func refresh_from_mount() -> Dictionary:
	var mount: Node = get_node_or_null(MODEL_MOUNT_PATH)
	if mount == null or not mount.has_method("get_model_root"):
		return configure_from_model(null)
	var model_variant: Variant = mount.call("get_model_root")
	if not (model_variant is Node):
		return configure_from_model(null)
	return configure_from_model(model_variant as Node)


## Public test/modding entry point. Normally called by refresh_from_mount().
## A model with no armature is still valid for static geometry and node-based
## actions; two or more Skeleton3D nodes violate the shared-skeleton contract.
func configure_from_model(model_root: Node) -> Dictionary:
	_clear_runtime_state()
	_model_root = model_root
	if not is_instance_valid(_model_root):
		return _set_status(
			"waiting_for_model",
			false,
			0,
			0,
			0,
			[],
			["No validated ship model is currently mounted."],
			[]
		)

	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	_collect_animation_nodes(_model_root, skeletons, players)
	_animation_players = players

	var warnings: Array[String] = []
	var errors: Array[String] = []
	var bone_count: int = 0
	var rig_valid: bool = true

	if skeletons.size() > 1:
		errors.append(
			"Ship model contains %d Skeleton3D nodes; the ship rig must use one shared skeleton." % skeletons.size()
		)
		rig_valid = false
	elif skeletons.is_empty():
		warnings.append("No Skeleton3D was found; static geometry and node-based action clips can still be used.")
	else:
		var skeleton: Skeleton3D = skeletons[0]
		bone_count = skeleton.get_bone_count()
		if bone_count <= 0:
			errors.append("The shared Skeleton3D contains no bones.")
			rig_valid = false
		else:
			var root_bone_found: bool = false
			for bone_index: int in range(bone_count):
				var bone_name: StringName = skeleton.get_bone_name(bone_index)
				if bone_name == ROOT_BONE_NAME:
					root_bone_found = true
				if not String(bone_name).begins_with(BONE_PREFIX):
					warnings.append(
						"Bone '%s' does not use the required BONE_ prefix." % String(bone_name)
					)
			if not root_bone_found:
				warnings.append("Shared skeleton has no BONE_root bone at the ship datum.")

	var discovered_actions: int = 0
	if rig_valid:
		_discover_actions(players, warnings, errors)
		discovered_actions = _actions.size()
	else:
		warnings.append("Action playback is disabled until the model has a valid shared skeleton.")

	var result_state: String = "ready"
	if not rig_valid:
		result_state = "invalid_rig"
	elif players.is_empty():
		result_state = "no_animation_player"
	elif discovered_actions <= 0:
		result_state = "no_actions"

	return _set_status(
		result_state,
		rig_valid,
		skeletons.size(),
		bone_count,
		players.size(),
		_actions.keys(),
		warnings,
		errors
	)


## Plays one exported action. Accepts either "gear_deploy" or
## "action_gear_deploy". The animation resource is duplicated before its loop
## mode is changed, so the imported source resource is not mutated.
func play_action(
		action_id: String,
		loop: bool = false,
		custom_speed: float = 1.0,
		from_end: bool = false,
		custom_blend: float = -1.0
) -> bool:
	var normalized_id: String = _normalize_action_id(action_id)
	if not _actions.has(normalized_id):
		return false
	if not is_finite(custom_speed) or absf(custom_speed) < MINIMUM_ANIMATION_SPEED:
		return false
	if not is_finite(custom_blend) or custom_blend < -1.0:
		return false

	var action_data: Dictionary = _actions[normalized_id]
	var player: AnimationPlayer = action_data.get("player") as AnimationPlayer
	var animation_key: StringName = action_data.get("animation_key", &"")
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if not _install_runtime_animation(action_data, loop):
		return false

	player.play(animation_key, custom_blend, custom_speed, from_end)
	action_started.emit(StringName(ACTION_PREFIX + normalized_id))
	return true


## Stops the requested action only if that action is currently active.
func stop_action(action_id: String) -> bool:
	var normalized_id: String = _normalize_action_id(action_id)
	if not _actions.has(normalized_id):
		return false
	var action_data: Dictionary = _actions[normalized_id]
	var player: AnimationPlayer = action_data.get("player") as AnimationPlayer
	var animation_key: StringName = action_data.get("animation_key", &"")
	if not is_instance_valid(player) or not player.is_playing():
		return false
	if player.current_animation != animation_key:
		return false
	player.stop()
	return true


func stop_all_actions() -> void:
	for player: AnimationPlayer in _animation_players:
		if is_instance_valid(player):
			player.stop()


func is_action_playing(action_id: String) -> bool:
	var normalized_id: String = _normalize_action_id(action_id)
	if not _actions.has(normalized_id):
		return false
	var action_data: Dictionary = _actions[normalized_id]
	var player: AnimationPlayer = action_data.get("player") as AnimationPlayer
	var animation_key: StringName = action_data.get("animation_key", &"")
	return is_instance_valid(player) and player.is_playing() and player.current_animation == animation_key


func get_available_actions() -> PackedStringArray:
	var action_names := PackedStringArray()
	for action_id_variant: Variant in _actions.keys():
		action_names.append(ACTION_PREFIX + String(action_id_variant))
	action_names.sort()
	return action_names


func get_animation_status() -> Dictionary:
	var result: Dictionary = _status.duplicate(true)
	result["action_names"] = get_available_actions()
	result["action_count"] = _actions.size()
	return result


func _discover_actions(
		players: Array[AnimationPlayer],
		warnings: Array[String],
		errors: Array[String]
) -> void:
	var duplicate_action_ids: Dictionary = {}
	for player: AnimationPlayer in players:
		# GLB actions are data, not startup behavior; the game requests every play.
		player.stop()
		var player_id: int = player.get_instance_id()
		var clip_lookup: Dictionary = {}
		_player_action_lookup[player_id] = clip_lookup
		var callback: Callable = Callable(self, "_on_animation_finished").bind(player)
		if not player.animation_finished.is_connected(callback):
			player.animation_finished.connect(callback)
		_connected_player_callbacks.append({"player": player, "callback": callback})

		for animation_key_variant: Variant in player.get_animation_list():
			var animation_key: String = String(animation_key_variant)
			var clip_name: String = _animation_key_basename(animation_key)
			if not clip_name.begins_with(ACTION_PREFIX):
				continue
			if not _is_valid_action_name(clip_name):
				errors.append(
					"Animation '%s' has an invalid action name; use action_lowercase_snake_case." % animation_key
				)
				continue

			var action_id: String = clip_name.substr(ACTION_PREFIX.length())
			if duplicate_action_ids.has(action_id):
				continue
			if _actions.has(action_id):
				errors.append(
					"Duplicate action clip '%s' was found in more than one animation library/player." % clip_name
				)
				_actions.erase(action_id)
				duplicate_action_ids[action_id] = true
				for existing_lookup_variant: Variant in _player_action_lookup.values():
					var existing_lookup: Dictionary = existing_lookup_variant
					for existing_key_variant: Variant in existing_lookup.keys():
						if String(existing_lookup[existing_key_variant]) == action_id:
							existing_lookup.erase(existing_key_variant)
				clip_lookup.erase(animation_key)
				continue

			var animation: Animation = player.get_animation(StringName(animation_key))
			if not is_instance_valid(animation):
				warnings.append("Animation '%s' could not be retrieved from its AnimationPlayer." % animation_key)
				continue

			_actions[action_id] = {
				"player": player,
				"animation_key": StringName(animation_key),
				"source_animation": animation.duplicate(true),
			}
			clip_lookup[animation_key] = action_id

	if players.is_empty():
		warnings.append("The mounted model contains no AnimationPlayer node.")
	elif _actions.is_empty():
		warnings.append("No valid action_* animation clips were found.")


func _install_runtime_animation(action_data: Dictionary, loop: bool) -> bool:
	var player: AnimationPlayer = action_data.get("player") as AnimationPlayer
	var animation_key: String = String(action_data.get("animation_key", ""))
	var source_animation: Animation = action_data.get("source_animation") as Animation
	if not is_instance_valid(player) or not is_instance_valid(source_animation):
		return false

	var split_index: int = animation_key.rfind("/")
	var library_name: String = animation_key.substr(0, split_index) if split_index >= 0 else ""
	var local_animation_name: String = animation_key.substr(split_index + 1)
	var library: AnimationLibrary = player.get_animation_library(StringName(library_name))
	if not is_instance_valid(library) or not library.has_animation(StringName(local_animation_name)):
		return false

	var runtime_animation: Animation = source_animation.duplicate(true) as Animation
	if not is_instance_valid(runtime_animation):
		return false
	runtime_animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE

	var previous_animation: Animation = library.get_animation(StringName(local_animation_name))
	library.remove_animation(StringName(local_animation_name))
	var add_error: Error = library.add_animation(StringName(local_animation_name), runtime_animation)
	if add_error != OK:
		if is_instance_valid(previous_animation):
			library.add_animation(StringName(local_animation_name), previous_animation)
		push_error(
			"ShipAnimationController: Could not install runtime loop settings for '%s' (%s)." % [animation_key, error_string(add_error)]
		)
		return false
	return true


func _on_animation_finished(animation_name: StringName, source_player: AnimationPlayer) -> void:
	if not is_instance_valid(source_player):
		return
	var player_id: int = source_player.get_instance_id()
	var clip_lookup: Dictionary = _player_action_lookup.get(player_id, {})
	var signal_key: String = String(animation_name)
	var action_id: String = String(clip_lookup.get(signal_key, ""))
	if action_id.is_empty():
		# AnimationMixer normally reports the full library/key string. Retain a
		# basename match for imported clips whose signal omits the library name.
		for key_variant: Variant in clip_lookup.keys():
			var candidate_key: String = String(key_variant)
			if _animation_key_basename(candidate_key) == signal_key:
				action_id = String(clip_lookup[key_variant])
				break
	if action_id.is_empty():
		return
	action_finished.emit(StringName(ACTION_PREFIX + action_id))


func _collect_animation_nodes(
		node: Node,
		skeletons: Array[Skeleton3D],
		players: Array[AnimationPlayer]
) -> void:
	if node is Skeleton3D:
		skeletons.append(node as Skeleton3D)
	if node is AnimationPlayer:
		players.append(node as AnimationPlayer)
	for child: Node in node.get_children():
		_collect_animation_nodes(child, skeletons, players)


func _clear_runtime_state() -> void:
	stop_all_actions()
	for connection: Dictionary in _connected_player_callbacks:
		var player: AnimationPlayer = connection.get("player") as AnimationPlayer
		var callback: Callable = connection.get("callback", Callable())
		if is_instance_valid(player) and player.animation_finished.is_connected(callback):
			player.animation_finished.disconnect(callback)
	_connected_player_callbacks.clear()
	_animation_players.clear()
	_actions.clear()
	_player_action_lookup.clear()


func _set_status(
		state: String,
		valid: bool,
		skeleton_count: int,
		bone_count: int,
		animation_player_count: int,
		action_ids: Array,
		warnings: Array[String],
		errors: Array[String]
) -> Dictionary:
	var action_names := PackedStringArray()
	for action_id_variant: Variant in action_ids:
		action_names.append(ACTION_PREFIX + String(action_id_variant))
	action_names.sort()
	_status = {
		"state": state,
		"valid": valid and errors.is_empty(),
		"rig_valid": valid,
		"skeleton_count": skeleton_count,
		"bone_count": bone_count,
		"animation_player_count": animation_player_count,
		"action_count": _actions.size(),
		"action_names": action_names,
		"warnings": PackedStringArray(warnings),
		"errors": PackedStringArray(errors),
	}
	return _status.duplicate(true)


func _normalize_action_id(action_id: String) -> String:
	var normalized: String = action_id.strip_edges()
	if normalized.begins_with(ACTION_PREFIX):
		normalized = normalized.substr(ACTION_PREFIX.length())
	return normalized


func _animation_key_basename(animation_key: String) -> String:
	var separator_index: int = animation_key.rfind("/")
	return animation_key.substr(separator_index + 1) if separator_index >= 0 else animation_key


func _is_valid_action_name(clip_name: String) -> bool:
	if not clip_name.begins_with(ACTION_PREFIX):
		return false
	var identifier: String = clip_name.substr(ACTION_PREFIX.length())
	if identifier.is_empty() or identifier.begins_with("_") or identifier.ends_with("_") or identifier.contains("__"):
		return false
	for character: String in identifier:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"):
			return false
	return true
