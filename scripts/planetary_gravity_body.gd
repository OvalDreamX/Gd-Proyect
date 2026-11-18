extends Node
class_name PlanetaryGravityBody

## Adapts a RigidBody3D to the world's shared planetary gravity field or active
## EnvironmentManager. When either provider is present, built-in world-axis
## gravity is disabled and central gravity is applied once per physics tick
## (or held at zero in LOCAL_SPACE, with linear_damp forced to 0.0 so linear
## inertia is preserved). Without a provider, default Godot gravity remains
## untouched.

@export var planetary_reference_frame_path: NodePath = NodePath("../../PlanetaryReferenceFrame")
@export var environment_manager_path: NodePath = NodePath("../../EnvironmentManager")

var _body: RigidBody3D
var _reference_frame: PlanetaryReferenceFrame
var _environment_manager: Node
var _original_gravity_scale: float = 1.0
var _original_linear_damp_mode: int = RigidBody3D.DAMP_MODE_COMBINE
var _original_linear_damp: float = 0.0
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
	_original_linear_damp_mode = _body.linear_damp_mode
	_original_linear_damp = _body.linear_damp
	_resolve_environment_providers()
	if is_instance_valid(_environment_manager) or is_instance_valid(_reference_frame):
		_body.gravity_scale = 0.0
		_custom_gravity_active = true
		_sync_linear_damping()
	else:
		set_physics_process(false)

func _resolve_environment_providers() -> void:
	if not environment_manager_path.is_empty():
		_environment_manager = get_node_or_null(environment_manager_path)
	if not is_instance_valid(_environment_manager) and is_inside_tree():
		_environment_manager = get_tree().get_first_node_in_group("environment_manager")
	if is_instance_valid(_environment_manager) and _environment_manager.has_signal("environment_profile_changed"):
		var cb := Callable(self, "_on_environment_profile_changed")
		if not _environment_manager.is_connected("environment_profile_changed", cb):
			_environment_manager.connect("environment_profile_changed", cb)
	if not planetary_reference_frame_path.is_empty():
		_reference_frame = get_node_or_null(planetary_reference_frame_path) as PlanetaryReferenceFrame

func _on_environment_profile_changed(_profile: Resource) -> void:
	_sync_linear_damping()

func _sync_linear_damping() -> void:
	if not is_instance_valid(_body):
		return
	# AtmosphericFlightModel owns all aerodynamic drag; never let Godot's
	# default_linear_damp=0.1 impose a fake terminal-velocity cap on PLANET_SURFACE.
	_body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_body.linear_damp = 0.0

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_body):
		return
	if is_instance_valid(_environment_manager) or is_instance_valid(_reference_frame):
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
		# In zero-g space, gravity_world is Vector3.ZERO so no force is applied.
		if not _body.freeze and not _body.sleeping and _body.mass > 0.0001 and gravity_world.length_squared() > 0.000001:
			_body.apply_central_force(gravity_world * _body.mass)
	elif _custom_gravity_active:
		# If the environment node is removed at runtime, resume normal world gravity.
		_body.gravity_scale = _original_gravity_scale
		_body.linear_damp_mode = _original_linear_damp_mode as RigidBody3D.DampMode
		_body.linear_damp = _original_linear_damp
		_custom_gravity_active = false
		set_physics_process(false)

func get_local_gravity_vector_world() -> Vector3:
	if is_instance_valid(_environment_manager) and is_instance_valid(_body) and _environment_manager.has_method("get_gravity_vector_world"):
		return _environment_manager.call("get_gravity_vector_world", _body.global_position)
	if is_instance_valid(_reference_frame) and is_instance_valid(_body):
		return _reference_frame.get_gravity_vector_world(_body.global_position)
	if is_instance_valid(_body):
		return _body.get_gravity()
	return Vector3.ZERO

func get_planetary_reference_frame() -> PlanetaryReferenceFrame:
	return _reference_frame if is_instance_valid(_reference_frame) else null

func get_environment_manager() -> Node:
	return _environment_manager if is_instance_valid(_environment_manager) else null
