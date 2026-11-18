extends RigidBody3D
class_name ShipInteractable

## Physics-enabled ship root. Hydrates mass, cargo capacity, propulsion, handling,
## aerodynamics, cameras, and thermal/integrity curves from ship.json when available,
## while keeping scene-authored defaults as deterministic fallbacks for standalone tests.

signal ship_definition_applied(definition: ShipDefinition)

const DEFAULT_SHIP_DEFINITION_PATH: String = "res://data/ships/prototype_freighter/ship.json"

@export_category("Ship definition")
@export_file("*.json") var ship_definition_path: String = DEFAULT_SHIP_DEFINITION_PATH

@export_category("Mass and cargo rating")
## Maximum abstract cargo payload. This is a design limit, not current cargo.
@export_range(0.0, 100000.0, 250.0) var max_payload_mass_kg: float = 25000.0

var _design_dry_mass_kg: float = 0.0
var _ship_definition: ShipDefinition = null
var _ship_definition_errors: PackedStringArray = PackedStringArray()

@onready var pilot_zone: Area3D = $PilotZone
@onready var seat_anchor: Marker3D = $CockpitSeat
@onready var cockpit_camera: Camera3D = $CockpitSeat/CockpitCamera
@onready var hull_visual: Node3D = $Visuals/Exterior
@onready var cockpit_interior: Node3D = $Visuals/CockpitInterior

var _pilot_claimed: bool = false
var _active_pilot: Node = null

func _enter_tree() -> void:
	_design_dry_mass_kg = mass
	_load_default_definition()

func _load_default_definition() -> void:
	if ship_definition_path.is_empty():
		return
	if not ResourceLoader.exists(ship_definition_path) and not FileAccess.file_exists(ship_definition_path):
		return
	var result: Dictionary = ShipDefinitionLoader.load_file(ship_definition_path)
	if bool(result.get("valid", false)):
		var def := result.get("definition") as ShipDefinition
		if def != null:
			_ship_definition = def
			_ship_definition_errors.clear()
			_apply_mass_from_definition(def)
	else:
		_ship_definition_errors = result.get("errors", PackedStringArray())
		push_warning("ShipInteractable ignored invalid ship.json (%s): %s" % [ship_definition_path, "; ".join(_ship_definition_errors)])

func _apply_mass_from_definition(def: ShipDefinition) -> void:
	if def == null:
		return
	if def.physics.has("dry_mass_kg"):
		_design_dry_mass_kg = maxf(float(def.physics.get("dry_mass_kg", _design_dry_mass_kg)), 1.0)
		mass = _design_dry_mass_kg
	if def.physics.has("max_payload_mass_kg"):
		max_payload_mass_kg = maxf(float(def.physics.get("max_payload_mass_kg", max_payload_mass_kg)), 0.0)
	if def.physics.has("dry_hull_dimensions_m") and def.physics["dry_hull_dimensions_m"] is Array:
		var dims_arr: Array = def.physics["dry_hull_dimensions_m"]
		if dims_arr.size() == 3:
			var hull_col := get_node_or_null("CollisionShape3D") as CollisionShape3D
			if is_instance_valid(hull_col) and hull_col.shape is BoxShape3D:
				var box := (hull_col.shape as BoxShape3D).duplicate() as BoxShape3D
				box.size = Vector3(maxf(float(dims_arr[0]), 0.1), maxf(float(dims_arr[1]), 0.1), maxf(float(dims_arr[2]), 0.1))
				hull_col.shape = box

func get_ship_definition() -> ShipDefinition:
	return _ship_definition

func get_ship_definition_errors() -> PackedStringArray:
	return _ship_definition_errors

func load_ship_definition_file(path: String) -> Dictionary:
	var result: Dictionary = ShipDefinitionLoader.load_file(path)
	if bool(result.get("valid", false)):
		ship_definition_path = path
		set_ship_definition(result.get("definition") as ShipDefinition)
	return result

func set_ship_definition(definition: ShipDefinition) -> void:
	_ship_definition = definition
	_ship_definition_errors.clear()
	if _ship_definition != null:
		_apply_mass_from_definition(_ship_definition)
		_propagate_ship_definition(_ship_definition)
		ship_definition_applied.emit(_ship_definition)

func _propagate_ship_definition(def: ShipDefinition) -> void:
	if def == null:
		return
	for child: Node in get_children():
		if child.has_method("apply_ship_definition"):
			child.call("apply_ship_definition", def)

func get_design_dry_mass_kg() -> float:
	return _design_dry_mass_kg if _design_dry_mass_kg > 0.0 else mass

func get_design_gross_mass_kg() -> float:
	return get_design_dry_mass_kg() + maxf(max_payload_mass_kg, 0.0)

func get_cargo_system() -> Node:
	return get_node_or_null("CargoSystem")

func _ready() -> void:
	# Angular damping belongs to the FCC in assisted mode. With assistance off,
	# rotational inertia is preserved just like linear inertia in space.
	freeze = false
	can_sleep = true
	sleeping = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	if _ship_definition != null:
		_propagate_ship_definition(_ship_definition)
		ship_definition_applied.emit(_ship_definition)
	if is_instance_valid(pilot_zone):
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
	player.tree_exiting.connect(_on_active_pilot_tree_exiting, CONNECT_ONE_SHOT)
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

## Releases the seat if its owner is removed without a normal disembark flow.
func _on_active_pilot_tree_exiting() -> void:
	_pilot_claimed = false
	_active_pilot = null
	if is_instance_valid(hull_visual):
		hull_visual.visible = true
	if is_instance_valid(cockpit_interior):
		cockpit_interior.visible = false
