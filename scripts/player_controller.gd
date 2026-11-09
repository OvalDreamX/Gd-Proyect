extends CharacterBody3D
class_name PlayerController
## Minimal first-person walking controller for the Phase 1 interaction prototype.
## This controller is intentionally separate from the future ship flight controller.

@export_category("Movement")
@export var walk_speed: float = 5.0
@export var ground_acceleration: float = 22.0
@export var ground_friction: float = 18.0
@export var jump_velocity: float = 4.5
@export_category("Look")
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.002
@export_range(60.0, 89.0, 1.0) var vertical_look_limit_degrees: float = 85.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var player_camera: Camera3D = $CameraPivot/Camera3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
var _nearby_ship: Node3D = null
var _transitioning: bool = false
var _piloting: bool = false
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

var _hud_layer: CanvasLayer
var _prompt_panel: PanelContainer
var _fade_rect: ColorRect
var _controls_label: Label


func _ready() -> void:
	add_to_group("player")
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning or _piloting:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		var limit_radians := deg_to_rad(vertical_look_limit_degrees)
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x, -limit_radians, limit_radians)
	if event.is_action_pressed("interact") and _nearby_ship != null:
		if is_instance_valid(_nearby_ship) and _nearby_ship.has_method("request_pilot"):
			get_viewport().set_input_as_handled()
			_nearby_ship.request_pilot(self)


func _physics_process(delta: float) -> void:
	if _transitioning or _piloting:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
	var input_vector := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)
	var wish_direction := (global_basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	if wish_direction.length_squared() > 0.0001:
		velocity.x = move_toward(velocity.x, wish_direction.x * walk_speed, ground_acceleration * delta)
		velocity.z = move_toward(velocity.z, wish_direction.z * walk_speed, ground_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)

	move_and_slide()


## Called by the ship's proximity Area3D when the player enters interaction range.
func set_nearby_ship(ship: Node3D) -> void:
	if _piloting or _transitioning:
		return
	_nearby_ship = ship
	_prompt_panel.visible = ship != null


## Clears the prompt only if the player is leaving the ship currently being advertised.
func clear_nearby_ship(ship: Node3D) -> void:
	if _nearby_ship == ship:
		_nearby_ship = null
		_prompt_panel.visible = false


## Public read-only occupancy query for ship systems. Camera mode is deliberately
## not used here: switching to an external camera must not make the pilot appear
## to have left the seat.
func is_piloting() -> bool:
	return _piloting and not _transitioning


## Runs the cockpit-entry transition, then hands the active view to the ship camera.
func enter_pilot_seat(seat_anchor: Node3D, cockpit_camera: Camera3D, hull_visual: Node3D, cockpit_interior: Node3D) -> bool:
	if _transitioning or _piloting:
		return false
	if not is_instance_valid(seat_anchor) or not is_instance_valid(cockpit_camera):
		push_error("Pilot transition cancelled: seat anchor or cockpit camera is missing.")
		return false

	_transitioning = true
	_nearby_ship = null
	_prompt_panel.visible = false
	# Dim the view, reveal the placeholder cockpit, then dolly the first-person
	# camera to the seat. A final brief fade masks the player-body teleport and
	# camera handoff, so the active view never visibly snaps.
	_fade_rect.visible = true
	_fade_rect.modulate.a = 0.0
	var target_camera_position: Vector3 = cockpit_camera.global_position
	var target_camera_rotation: Vector3 = cockpit_camera.global_rotation
	var transition_tween := create_tween()
	transition_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(_fade_rect, "modulate:a", 0.42, 0.16)
	transition_tween.tween_callback(func() -> void:
		if is_instance_valid(hull_visual):
			hull_visual.visible = false
		if is_instance_valid(cockpit_interior):
			cockpit_interior.visible = true
	)
	transition_tween.tween_property(player_camera, "global_position", target_camera_position, 0.58)
	transition_tween.parallel().tween_property(player_camera, "global_rotation", target_camera_rotation, 0.58)
	transition_tween.tween_property(_fade_rect, "modulate:a", 1.0, 0.13)
	transition_tween.tween_callback(func() -> void:
		global_transform = seat_anchor.global_transform
		velocity = Vector3.ZERO
		body_collision.set_deferred("disabled", true)
		set_physics_process(false)
		set_process_unhandled_input(false)
		player_camera.current = false
		cockpit_camera.make_current()
		_piloting = true
		# The ship now owns the cockpit readout. Hide the walking-only hint so
		# it does not overlap the ship's independent FlightHUD CanvasLayer.
		_controls_label.visible = false
	)
	transition_tween.tween_property(_fade_rect, "modulate:a", 0.0, 0.3)
	transition_tween.tween_callback(func() -> void:
		_fade_rect.visible = false
		_transitioning = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	)
	return true


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUD"
	_hud_layer.layer = 10
	add_child(_hud_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "TransitionFade"
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.z_index = 100
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_layer.add_child(_fade_rect)

	_controls_label = Label.new()
	_controls_label.name = "ControlsHint"
	_controls_label.text = "WASD  MOVE     MOUSE  LOOK     SPACE  JUMP     ESC  RELEASE MOUSE"
	_controls_label.position = Vector2(18.0, 16.0)
	_controls_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.9, 0.85))
	_controls_label.add_theme_font_size_override("font_size", 13)
	_hud_layer.add_child(_controls_label)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "PilotPrompt"
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.offset_left = -150.0
	_prompt_panel.offset_right = 150.0
	_prompt_panel.offset_top = -112.0
	_prompt_panel.offset_bottom = -54.0
	_prompt_panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.045, 0.06, 0.94)
	panel_style.border_color = Color(0.24, 0.62, 0.74, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	_prompt_panel.add_theme_stylebox_override("panel", panel_style)
	var prompt_label := Label.new()
	prompt_label.text = "PILOT SHIP     [ F ]"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.custom_minimum_size = Vector2(268.0, 38.0)
	prompt_label.add_theme_color_override("font_color", Color(0.91, 0.96, 0.98))
	prompt_label.add_theme_font_size_override("font_size", 17)
	_prompt_panel.add_child(prompt_label)
	_hud_layer.add_child(_prompt_panel)
