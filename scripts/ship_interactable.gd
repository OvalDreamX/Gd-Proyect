extends RigidBody3D
class_name ShipInteractable

## Stationary placeholder freighter. The rigid-body root is retained so the scene
## can evolve into the later force-based ship without replacing its root node.

@onready var pilot_zone: Area3D = $PilotZone
@onready var seat_anchor: Marker3D = $CockpitSeat
@onready var cockpit_camera: Camera3D = $CockpitSeat/CockpitCamera
@onready var hull_visual: Node3D = $Visuals/Hull
@onready var cockpit_interior: Node3D = $Visuals/CockpitInterior

var _pilot_claimed: bool = false


func _ready() -> void:
	freeze = true
	can_sleep = false
	pilot_zone.body_entered.connect(_on_pilot_zone_body_entered)
	pilot_zone.body_exited.connect(_on_pilot_zone_body_exited)


func request_pilot(player: Node) -> void:
	if _pilot_claimed or not is_instance_valid(player):
		return
	if not player.is_in_group("player"):
		return
	if not player.has_method("enter_pilot_seat"):
		return

	_pilot_claimed = true
	if player.has_method("clear_nearby_ship"):
		player.clear_nearby_ship(self)
	player.enter_pilot_seat(seat_anchor, cockpit_camera, hull_visual, cockpit_interior)


func _on_pilot_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("set_nearby_ship"):
		body.set_nearby_ship(self)


func _on_pilot_zone_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("clear_nearby_ship"):
		body.clear_nearby_ship(self)
