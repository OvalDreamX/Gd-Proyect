extends Node
class_name PlanetaryGravityBody

## Adapts a RigidBody3D to the world's shared planetary gravity field. When a
## reference frame is present, built-in world-axis gravity is disabled and a
## central force is applied once per physics tick. Without a frame, the body's
## original gravity_scale and default Godot gravity remain untouched.

@export var planetary_reference_frame_path: NodePath = NodePath("../../PlanetaryReferenceFrame")

var _body: RigidBody3D
var _reference_frame: PlanetaryReferenceFrame
var _original_gravity_scale: float = 1.0
var _custom_gravity_active: bool = false
var _last_gravity_vector_world: Vector3 = Vector3.ZERO
var _has_gravity_sample: bool = false


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("PlanetaryGravityBody requires a RigidBody3D parent.")
		set_physics_process(false)
		return
	_original_gravity_scale = _body.gravity_scale
	_reference_frame = get_node_or_null(planetary_reference_frame_path) as PlanetaryReferenceFrame
	if is_instance_valid(_reference_frame):
		_body.gravity_scale = 0.0
		_custom_gravity_active = true
	else:
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_body):
		return
	if is_instance_valid(_reference_frame):
		var gravity_world: Vector3 = get_local_gravity_vector_world()
		var gravity_changed: bool = (
			not _has_gravity_sample
			or gravity_world.distance_squared_to(_last_gravity_vector_world) > 0.000001
		)
		_last_gravity_vector_world = gravity_world
		_has_gravity_sample = true
		if gravity_changed and _body.sleeping and not _body.freeze:
			_body.sleeping = false
		# Do not submit a constant scripted force to a settled sleeping body.
		# External force/collision or a changed gravity vector wakes it; local
		# gravity resumes on the next physics tick.
		if not _body.freeze and not _body.sleeping and _body.mass > 0.0001:
			_body.apply_central_force(gravity_world * _body.mass)
	elif _custom_gravity_active:
		# If the environment node is removed at runtime, resume normal world gravity.
		_body.gravity_scale = _original_gravity_scale
		_custom_gravity_active = false
		set_physics_process(false)


func get_local_gravity_vector_world() -> Vector3:
	if is_instance_valid(_reference_frame) and is_instance_valid(_body):
		return _reference_frame.get_gravity_vector_world(_body.global_position)
	if is_instance_valid(_body):
		return _body.get_gravity()
	return Vector3.ZERO


func get_planetary_reference_frame() -> PlanetaryReferenceFrame:
	return _reference_frame if is_instance_valid(_reference_frame) else null
