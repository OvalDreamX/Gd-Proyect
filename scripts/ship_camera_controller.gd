extends Node
class_name ShipCameraController

## Camera-only component for Phase 2B.
## It changes camera selection and camera transforms; it never rotates or moves
## the ship's RigidBody3D. The external rig follows ship position only.

@export_category("External camera")
@export_range(3.0, 30.0, 0.5) var external_camera_distance: float = 11.0
@export var camera_focus_offset: Vector3 = Vector3(0.0, 0.45, 0.0)

@export_category("External camera zoom")
@export_range(2.0, 10.0, 0.5) var external_camera_min_distance: float = 4.0
@export_range(10.0, 40.0, 0.5) var external_camera_max_distance: float = 24.0
@export_range(0.25, 4.0, 0.25) var external_camera_zoom_step: float = 1.5

@export_category("Camera look")
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0025
@export_range(20.0, 89.0, 1.0) var cockpit_pitch_limit_degrees: float = 80.0
@export_range(30.0, 150.0, 1.0) var cockpit_yaw_limit_degrees: float = 105.0
@export_range(5.0, 85.0, 1.0) var external_pitch_limit_degrees: float = 75.0

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable
@onready var _cockpit_camera: Camera3D = get_node("../CockpitSeat/CockpitCamera") as Camera3D
@onready var _external_camera_rig: Node3D = $ExternalCameraRig
@onready var _spring_arm: SpringArm3D = $ExternalCameraRig/SpringArm3D
@onready var _external_camera: Camera3D = $ExternalCameraRig/SpringArm3D/ExternalCamera
@onready var _hull_visual: Node3D = get_node("../Visuals/Hull") as Node3D
@onready var _cockpit_interior: Node3D = get_node("../Visuals/CockpitInterior") as Node3D

const DEFAULT_EXTERNAL_PITCH_RADIANS: float = -0.32

var _using_external_view: bool = false
var _external_yaw_radians: float = 0.0
var _external_pitch_radians: float = DEFAULT_EXTERNAL_PITCH_RADIANS
var _cockpit_base_rotation: Vector3 = Vector3.ZERO
var _cockpit_yaw_radians: float = 0.0
var _cockpit_pitch_radians: float = 0.0


func _ready() -> void:
	if _ship == null or _cockpit_camera == null or _external_camera == null:
		push_error("ShipCameraController is missing a required ship or camera reference.")
		set_process(false)
		return

	# This node is a child of the ship for scene ownership, but top_level keeps
	# its basis independent from ship rotation. Its position is synchronized below.
	_external_camera_rig.top_level = true
	_external_camera_rig.global_position = _ship.global_position + camera_focus_offset
	_external_camera_rig.rotation = Vector3(
		_external_pitch_radians,
		_external_yaw_radians,
		0.0
	)
	_spring_arm.spring_length = clampf(
		external_camera_distance,
		minf(external_camera_min_distance, external_camera_max_distance),
		maxf(external_camera_min_distance, external_camera_max_distance)
	)
	_spring_arm.add_excluded_object(_ship.get_rid())
	_external_camera.current = false
	_cockpit_base_rotation = _cockpit_camera.rotation
	# Preserve the scene-authored initial state: exterior visible, cockpit interior hidden.


func _process(_delta: float) -> void:
	if is_instance_valid(_ship):
		# Follow translation only. Never inherit the ship's physical attitude.
		_external_camera_rig.global_position = _ship.global_position + camera_focus_offset


## Called once the player has completed the cockpit-entry transition.
func activate_cockpit_view() -> void:
	_using_external_view = false
	_apply_view_visibility()
	_cockpit_camera.make_current()


## Switches between cockpit and external views without touching ship state.
func toggle_view() -> void:
	_using_external_view = not _using_external_view
	_apply_view_visibility()
	if _using_external_view:
		_external_camera.make_current()
	else:
		_cockpit_camera.make_current()


## Wheel-up zooms in; wheel-down zooms out. Called by the ship input router so
## the camera does not own or intercept unrelated player/flight input.
func zoom_external(direction: float, event_factor: float = 1.0) -> void:
	if not _using_external_view or is_zero_approx(direction):
		return

	var min_distance: float = minf(external_camera_min_distance, external_camera_max_distance)
	var max_distance: float = maxf(external_camera_min_distance, external_camera_max_distance)
	var scroll_factor: float = event_factor if event_factor > 0.0 else 1.0
	var zoom_delta: float = signf(direction) * external_camera_zoom_step * scroll_factor
	_spring_arm.spring_length = clampf(
		_spring_arm.spring_length - zoom_delta,
		min_distance,
		max_distance
	)


## Routes captured mouse motion to the currently selected camera only.
func apply_mouse_look(screen_relative: Vector2) -> void:
	if _using_external_view:
		_external_yaw_radians = wrapf(
			_external_yaw_radians - screen_relative.x * mouse_sensitivity,
			-PI,
			PI
		)
		var external_pitch_limit := deg_to_rad(external_pitch_limit_degrees)
		_external_pitch_radians = clampf(
			_external_pitch_radians + screen_relative.y * mouse_sensitivity,
			-external_pitch_limit,
			external_pitch_limit
		)
		_external_camera_rig.rotation = Vector3(
			_external_pitch_radians,
			_external_yaw_radians,
			0.0
		)
	else:
		var cockpit_pitch_limit := deg_to_rad(cockpit_pitch_limit_degrees)
		var cockpit_yaw_limit := deg_to_rad(cockpit_yaw_limit_degrees)
		_cockpit_yaw_radians = clampf(
			_cockpit_yaw_radians - screen_relative.x * mouse_sensitivity,
			-cockpit_yaw_limit,
			cockpit_yaw_limit
		)
		_cockpit_pitch_radians = clampf(
			_cockpit_pitch_radians - screen_relative.y * mouse_sensitivity,
			-cockpit_pitch_limit,
			cockpit_pitch_limit
		)
		_cockpit_camera.rotation = _cockpit_base_rotation + Vector3(
			_cockpit_pitch_radians,
			_cockpit_yaw_radians,
			0.0
		)


## Restores camera-local state when pilot occupancy ends.
func reset_camera_state() -> void:
	_using_external_view = false
	_external_yaw_radians = 0.0
	_external_pitch_radians = DEFAULT_EXTERNAL_PITCH_RADIANS
	_cockpit_yaw_radians = 0.0
	_cockpit_pitch_radians = 0.0
	_cockpit_camera.rotation = _cockpit_base_rotation
	_external_camera_rig.rotation = Vector3(
		_external_pitch_radians,
		_external_yaw_radians,
		0.0
	)
	_apply_view_visibility()


func is_external_view() -> bool:
	return _using_external_view


func get_view_name() -> String:
	return "EXTERNAL" if _using_external_view else "COCKPIT"


func get_look_angles_degrees() -> Vector2:
	if _using_external_view:
		return Vector2(rad_to_deg(_external_yaw_radians), rad_to_deg(_external_pitch_radians))
	return Vector2(rad_to_deg(_cockpit_yaw_radians), rad_to_deg(_cockpit_pitch_radians))


func _apply_view_visibility() -> void:
	# The placeholder hull is hidden only while the cockpit view is active.
	# The external camera restores the ship exterior just like a normal view switch.
	_hull_visual.visible = _using_external_view
	_cockpit_interior.visible = not _using_external_view
