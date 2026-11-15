extends SceneTree

## Run: godot --headless --path . --script res://tests/ship_animation_controller_test.gd
## Synthetic scene fixture; no Blender model or imported GLB is required.
const ANIMATION_CONTROLLER_SCRIPT = preload("res://scripts/ship_animation_controller.gd")

var _checks: int = 0
var _failures: int = 0
var _finished_actions: PackedStringArray = PackedStringArray()
var _started_actions: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var controller_host := Node.new()
	root.add_child(controller_host)
	var controller := Node.new()
	controller.set_script(ANIMATION_CONTROLLER_SCRIPT)
	controller_host.add_child(controller)
	await process_frame

	var model_root: Node3D = _make_model_with_one_action()
	root.add_child(model_root)
	await process_frame

	var configuration: Dictionary = controller.call("configure_from_model", model_root)
	_expect(bool(configuration.get("valid", false)), "A model with one shared skeleton validates")
	_expect(int(configuration.get("skeleton_count", 0)) == 1, "Exactly one shared Skeleton3D is discovered")
	_expect(int(configuration.get("bone_count", 0)) == 1, "The shared skeleton bone count is reported")
	_expect(
		controller.call("get_available_actions") == PackedStringArray(["action_gear_deploy"]),
		"Only action_* clips are exposed through the action API"
	)

	controller.connect(
		"action_finished",
		func(action_id: StringName) -> void:
			_finished_actions.append(String(action_id))
	)
	controller.connect(
		"action_started",
		func(action_id: StringName) -> void:
			_started_actions.append(String(action_id))
	)
	_expect(
		bool(controller.call("play_action", "action_gear_deploy", false, 1.0, false)),
		"A one-shot action can be started using its full action_ name"
	)
	await create_timer(0.25).timeout
	var gear: Node3D = model_root.get_node("MESH_gear_nose") as Node3D
	_expect(_started_actions.has("action_gear_deploy"), "Accepted playback emits action_started")
	_expect(_finished_actions.has("action_gear_deploy"), "One-shot playback emits action_finished")
	_expect(gear.position.y > 0.5, "The AnimationPlayer applies the exported node transform track")
	_expect(
		not bool(controller.call("is_action_playing", "gear_deploy")),
		"A completed one-shot action is no longer playing"
	)

	_expect(
		bool(controller.call("play_action", "gear_deploy", true, 1.0, false)),
		"The action API accepts the short ID and enables looping"
	)
	await create_timer(0.25).timeout
	_expect(
		bool(controller.call("is_action_playing", "action_gear_deploy")),
		"A looped action remains active after multiple clip lengths"
	)
	_expect(
		bool(controller.call("stop_action", "gear_deploy")),
		"The active loop can be stopped by its short ID"
	)
	_expect(
		not bool(controller.call("is_action_playing", "gear_deploy")),
		"Stopping a loop clears its active playback state"
	)
	controller.call("play_action", "gear_deploy", true, 1.0, false)
	controller.call("stop_all_actions")
	_expect(
		not bool(controller.call("is_action_playing", "gear_deploy")),
		"stop_all_actions stops every discovered animation player"
	)

	var invalid_model := Node3D.new()
	invalid_model.name = "SHIP_root_invalid_rig"
	var first_skeleton := Skeleton3D.new()
	first_skeleton.add_bone("BONE_root")
	invalid_model.add_child(first_skeleton)
	var second_skeleton := Skeleton3D.new()
	second_skeleton.add_bone("BONE_root")
	invalid_model.add_child(second_skeleton)
	root.add_child(invalid_model)
	await process_frame
	var invalid_status: Dictionary = controller.call("configure_from_model", invalid_model)
	_expect(not bool(invalid_status.get("valid", true)), "A model with multiple Skeleton3D nodes is rejected for animation playback")
	_expect(
		String(invalid_status.get("state", "")) == "invalid_rig",
		"Multiple skeletons produce the explicit invalid_rig state"
	)
	_expect(
		controller.call("get_available_actions").is_empty(),
		"Actions are not exposed from an invalid multi-skeleton rig"
	)

	var duplicate_model: Node3D = _make_model_with_duplicate_action()
	root.add_child(duplicate_model)
	await process_frame
	var duplicate_status: Dictionary = controller.call("configure_from_model", duplicate_model)
	_expect(
		int(duplicate_status.get("action_count", -1)) == 0,
		"Duplicate action IDs are not exposed from multiple AnimationPlayers"
	)
	_expect(
		not duplicate_status.get("errors", PackedStringArray()).is_empty(),
		"Duplicate action IDs produce an explicit validation diagnostic"
	)

	var no_rig_model := Node3D.new()
	no_rig_model.name = "SHIP_root_static"
	var static_mesh := MeshInstance3D.new()
	static_mesh.name = "MESH_hull_main"
	static_mesh.mesh = BoxMesh.new()
	no_rig_model.add_child(static_mesh)
	root.add_child(no_rig_model)
	await process_frame
	var no_rig_status: Dictionary = controller.call("configure_from_model", no_rig_model)
	_expect(bool(no_rig_status.get("valid", false)), "A static greybox without an armature remains valid")
	_expect(int(no_rig_status.get("skeleton_count", -1)) == 0, "A missing skeleton is reported without rejecting static geometry")

	print("Ship animation controller tests: %d checks, %d failures." % [_checks, _failures])
	controller_host.queue_free()
	model_root.queue_free()
	invalid_model.queue_free()
	duplicate_model.queue_free()
	no_rig_model.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _make_model_with_one_action() -> Node3D:
	var model_root := Node3D.new()
	model_root.name = "SHIP_root"

	var skeleton := Skeleton3D.new()
	skeleton.name = "ARMATURE_ship"
	skeleton.add_bone("BONE_root")
	model_root.add_child(skeleton)

	var gear := Node3D.new()
	gear.name = "MESH_gear_nose"
	model_root.add_child(gear)

	var animation_player := AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.root_node = NodePath("..")
	model_root.add_child(animation_player)

	var animation := Animation.new()
	animation.length = 0.12
	var track_index: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, NodePath("MESH_gear_nose:position"))
	animation.track_insert_key(track_index, 0.0, Vector3.ZERO)
	animation.track_insert_key(track_index, 0.12, Vector3(0.0, 1.0, 0.0))
	var library: AnimationLibrary = _create_registered_default_library(animation_player)
	if library == null:
		return model_root
	library.add_animation("action_gear_deploy", animation)

	var non_action := Animation.new()
	non_action.length = 0.1
	library.add_animation("idle", non_action)
	return model_root


func _make_model_with_duplicate_action() -> Node3D:
	var model_root := Node3D.new()
	model_root.name = "SHIP_root_duplicate_actions"
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("BONE_root")
	model_root.add_child(skeleton)
	for player_index: int in range(2):
		var animation_player := AnimationPlayer.new()
		animation_player.name = "AnimationPlayer_%d" % player_index
		model_root.add_child(animation_player)
		var library: AnimationLibrary = _create_registered_default_library(animation_player)
		if library == null:
			continue
		var animation := Animation.new()
		animation.length = 0.1
		library.add_animation("action_gear_deploy", animation)
	return model_root


func _create_registered_default_library(animation_player: AnimationPlayer) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var registration_error: Error = animation_player.add_animation_library(&"", library)
	if registration_error != OK:
		_expect(false, "Synthetic AnimationPlayer accepts a default AnimationLibrary")
		return null

	var registered_library: AnimationLibrary = animation_player.get_animation_library(&"")
	_expect(
		registered_library == library,
		"Synthetic AnimationPlayer exposes its registered default AnimationLibrary"
	)
	if registered_library == null:
		return null
	return registered_library


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
