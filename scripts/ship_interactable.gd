extends RigidBody3D
class_name ShipInteractable
## Stationary placeholder freighter. The rigid-body root is retained so the scene
## can evolve into the later force-based ship without replacing its root.

@onready var pilot_zone: Area3D = $PilotZone
@onready var seat_anchor: Marker3D = $CockpitSeat
@onready var cockpit_camera: Camera3D = $CockpitSeat/CockpitCamera
@onready var hull_visual: Node3D = $Visuals/Hull
@onready var cockpit_interior: Node3D = $Visuals/CockpitInterior

var _pilot_claimed: bool = false
var _active_pilot: Node = null


func _ready() -> void:
	# Phase 2A deliberately retains the stationary test fixture. A later
	# rigid-body milestone will explicitly remove this freeze after validating
	# gravity, collision response, and resting stability.
	freeze = true
	can_sleep = false
	pilot_zone.body_entered.connect(_on_pilot_zone_body_entered)
	pilot_zone.body_exited.connect(_on_pilot_zone_body_exited)


func request_pilot(player: Node) -> void:
	if _pilot_claimed or not is_instance_valid(player):
		return
	if not player.is_in_group("player"):
		return
	if not player.has_method("enter_pilot_seat") or not player.has_method("is_piloting"):
		return

	# Claim the seat only if the player controller actually accepted the
	# transition. This prevents a rejected/busy player from locking the ship.
	var entry_accepted: bool = bool(
		player.call("enter_pilot_seat", seat_anchor, cockpit_camera, hull_visual, cockpit_interior)
	)
	if not entry_accepted:
		return

	_pilot_claimed = true
	_active_pilot = player
	if player.has_method("clear_nearby_ship"):
		player.clear_nearby_ship(self)


## True only after the player has claimed the seat and the entry transition has
## fully completed. This queries pilot occupancy, not the active camera:
## cockpit/external camera switching must not change ship-system ownership.
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
