extends RigidBody3D
class_name ShipInteractable
## Physics-enabled placeholder freighter. The single rigid-body root is retained
## for all flight forces, moments, collision response, and future cargo changes.

@onready var pilot_zone: Area3D = $PilotZone
@onready var seat_anchor: Marker3D = $CockpitSeat
@onready var cockpit_camera: Camera3D = $CockpitSeat/CockpitCamera
@onready var hull_visual: Node3D = $Visuals/Hull
@onready var cockpit_interior: Node3D = $Visuals/CockpitInterior

var _pilot_claimed: bool = false
var _active_pilot: Node = null


func _ready() -> void:
	# Angular damping belongs to the FCC in assisted mode. With assistance off,
	# rotational inertia is preserved just like linear inertia in space.
	freeze = false
	can_sleep = true
	sleeping = false
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	pilot_zone.body_entered.connect(_on_pilot_zone_body_entered)
	pilot_zone.body_exited.connect(_on_pilot_zone_body_exited)


func request_pilot(player: Node) -> void:
	if _pilot_claimed or not is_instance_valid(player):
		return
	if not player.is_in_group("player"):
		return
	if not player.has_method("enter_pilot_seat") or not player.has_method("is_piloting"):
		return

	var entry_accepted: bool = bool(
		player.call("enter_pilot_seat", seat_anchor, cockpit_camera, hull_visual, cockpit_interior)
	)
	if not entry_accepted:
		return

	_pilot_claimed = true
	_active_pilot = player
	if player.has_method("clear_nearby_ship"):
		player.clear_nearby_ship(self)


## Camera selection is deliberately not used as a pilot-occupancy test.
func is_pilot_ready() -> bool:
	return (
		_pilot_claimed
		and is_instance_valid(_active_pilot)
		and _active_pilot.has_method("is_piloting")
		and _active_pilot.is_piloting()
	)


func _on_pilot_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("set_nearby_ship"):
		body.set_nearby_ship(self)


func _on_pilot_zone_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("clear_nearby_ship"):
		body.clear_nearby_ship(self)
