extends Node
class_name ShipCameraController

## Camera-only component for Phase 2B / 0.4.1a.
## Disables double physics interpolation on ExternalCameraRig, SpringArm3D, and
## ExternalCamera, guards _get_interpolated_ship_origin() against >20 m rebase
## desyncs, and snaps transforms + resets subtree interpolation cleanly on
## origin rebases and view toggles.

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
@onready var _hull_visual: Node3D = get_node("../Visuals/Exterior") as Node3D
@onready var _cockpit_interior: Node3D = get_node("../Visuals/CockpitInterior") as Node3D

const DEFAULT_EXTERNAL_PITCH_RADIANS: float = -0.32
const REBASE_SNAP_THRESHOLD_SQ_M: float = 400.0

var _using_external_view: bool = false
var _external_yaw_radians: float = 0.0
var _external_pitch_radians: float = DEFAULT_EXTERNAL_PITCH_RADIANS
var _cockpit_base_rotation: Vector3 = Vector3.ZERO
var _cockpit_yaw_radians: float = 0.0
var _cockpit_pitch_radians: float = 0.0


func apply_ship_definition(definition: ShipDefinition) -> void:
	if definition == null or definition.cameras.is_empty():
		return
	var c: Dictionary = definition.cameras
	if c.has("external_distance_m"):
		external_camera_distance = clampf(float(c.get("external_distance_m", external_camera_distance)), minf(external_camera_min_distance, external_camera_max_distance), maxf(external_camera_min_distance, external_camera_max_distance))
		if is_instance_valid(_spring_arm):
			_spring_arm.spring_length = external_camera_distance
	if c.has("external_focus_offset_m") and c["external_focus_offset_m"] is Array:
		var off: Array = c["external_focus_offset_m"]
		if off.size() == 3:
			camera_focus_offset = Vector3(float(off[0]), float(off[1]), float(off[2]))
			if is_instance_valid(_external_camera_rig) and is_instance_valid(_ship):
				_external_camera_rig.global_position = _get_interpolated_ship_origin() + camera_focus_offset


func _ready() -> void:
	if _ship == null or _cockpit_camera == null or _external_camera == null:
		push_error("ShipCameraController is missing a required ship or camera reference.")
		set_process(false)
		return

	process_priority = 5
	# Disable physics interpolation on the top-level external rig and its children:
	# _get_interpolated_ship_origin() already yields the smoothed render-frame ship
	# origin, so enabling node physics interpolation on top causes stale-frame
	# extrapolation glitches and high-altitude flicker.
	_external_camera_rig.top_level = true
	_external_camera_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if is_instance_valid(_spring_arm):
		_spring_arm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_external_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

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


func _process(_delta: float) -> void:
	if is_instance_valid(_ship) and is_instance_valid(_external_camera_rig):
		_external_camera_rig.global_position = _get_interpolated_ship_origin() + camera_focus_offset


func _get_interpolated_ship_origin() -> Vector3:
	if not is_instance_valid(_ship):
		return Vector3.ZERO
	var phys_origin: Vector3 = _ship.global_position
	if _ship.is_inside_tree() and _ship.has_method("get_global_transform_interpolated"):
		var xform: Variant = _ship.call("get_global_transform_interpolated")
		if xform is Transform3D:
			var interp_origin: Vector3 = (xform as Transform3D).origin
			# If a floating-origin rebase or teleport happened this frame, snap
			# directly to the live ship origin rather than a stale pre-rebase position.
			if interp_origin.distance_squared_to(phys_origin) <= REBASE_SNAP_THRESHOLD_SQ_M:
				return interp_origin
	return phys_origin


func _reset_node_interpolation(node: Node) -> void:
	if is_instance_valid(node) and node.has_method("reset_physics_interpolation"):
		node.call("reset_physics_interpolation")


func notify_origin_shifted(delta_shift: Vector3) -> void:
	if is_instance_valid(_ship) and is_instance_valid(_external_camera_rig):
		_external_camera_rig.global_position = _ship.global_position + camera_focus_offset
		_external_camera_rig.force_update_transform()
	elif is_instance_valid(_external_camera_rig) and not delta_shift.is_zero_approx():
		_external_camera_rig.global_position += delta_shift
		_external_camera_rig.force_update_transform()
	_reset_node_interpolation(_ship)
	_reset_node_interpolation(_hull_visual)
	_reset_node_interpolation(_cockpit_interior)
	_reset_node_interpolation(_external_camera_rig)
	_reset_node_interpolation(_spring_arm)
	_reset_node_interpolation(_external_camera)
	_reset_node_interpolation(_cockpit_camera)


func activate_cockpit_view() -> void:
	_using_external_view = false
	_apply_view_visibility()
	_reset_node_interpolation(_cockpit_interior)
	_reset_node_interpolation(_cockpit_camera)
	_cockpit_camera.make_current()


func toggle_view() -> void:
	_using_external_view = not _using_external_view
	_apply_view_visibility()
	if _using_external_view:
		if is_instance_valid(_external_camera_rig) and is_instance_valid(_ship):
			_external_camera_rig.global_position = _get_interpolated_ship_origin() + camera_focus_offset
			_external_camera_rig.rotation = Vector3(
				_external_pitch_radians,
				_external_yaw_radians,
				0.0
			)
			_external_camera_rig.force_update_transform()
		_reset_node_interpolation(_hull_visual)
		_reset_node_interpolation(_external_camera_rig)
		_reset_node_interpolation(_spring_arm)
		_reset_node_interpolation(_external_camera)
		_external_camera.make_current()
	else:
		_reset_node_interpolation(_cockpit_interior)
		_reset_node_interpolation(_cockpit_camera)
		_cockpit_camera.make_current()


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


func get_cockpit_fov_degrees() -> float:
	return _cockpit_camera.fov if is_instance_valid(_cockpit_camera) else 78.0


func apply_mouse_look(screen_relative: Vector2) -> void:
	if _using_external_view:
		_external_yaw_radians = wrapf(
			_external_yaw_radians - screen_relative.x * mouse_sensitivity,
			-PI,
			PI
		)
		var external_pitch_limit: float = deg_to_rad(external_pitch_limit_degrees)
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
		var cockpit_pitch_limit: float = deg_to_rad(cockpit_pitch_limit_degrees)
		var cockpit_yaw_limit: float = deg_to_rad(cockpit_yaw_limit_degrees)
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


func recenter_cockpit_camera(delta: float, response: float = 7.0) -> bool:
	if _using_external_view:
		return false
	var blend: float = 1.0 - exp(-maxf(response, 0.1) * maxf(delta, 0.0))
	_cockpit_yaw_radians = lerpf(_cockpit_yaw_radians, 0.0, blend)
	_cockpit_pitch_radians = lerpf(_cockpit_pitch_radians, 0.0, blend)
	if absf(_cockpit_yaw_radians) < deg_to_rad(0.08):
		_cockpit_yaw_radians = 0.0
	if absf(_cockpit_pitch_radians) < deg_to_rad(0.08):
		_cockpit_pitch_radians = 0.0
	_cockpit_camera.rotation = _cockpit_base_rotation + Vector3(_cockpit_pitch_radians, _cockpit_yaw_radians, 0.0)
	return not is_zero_approx(_cockpit_yaw_radians) or not is_zero_approx(_cockpit_pitch_radians)


func is_cockpit_camera_centered(tolerance_degrees: float = 0.5) -> bool:
	if _using_external_view:
		return false
	var tolerance: float = deg_to_rad(maxf(tolerance_degrees, 0.0))
	return absf(_cockpit_yaw_radians) <= tolerance and absf(_cockpit_pitch_radians) <= tolerance


func is_external_view() -> bool:
	return _using_external_view


func get_view_name() -> String:
	return "EXTERNAL" if _using_external_view else "COCKPIT"


func get_active_camera_global_basis() -> Basis:
	var active_camera: Camera3D = _external_camera if _using_external_view else _cockpit_camera
	return active_camera.global_basis.orthonormalized()


func get_look_angles_degrees() -> Vector2:
	if _using_external_view:
		return Vector2(rad_to_deg(_external_yaw_radians), rad_to_deg(_external_pitch_radians))
	return Vector2(rad_to_deg(_cockpit_yaw_radians), rad_to_deg(_cockpit_pitch_radians))


func _apply_view_visibility() -> void:
	_hull_visual.visible = _using_external_view
	_cockpit_interior.visible = not _using_external_view
