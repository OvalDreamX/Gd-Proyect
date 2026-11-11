extends Node
class_name CargoSystem

## Independent cargo and mass subsystem for the Prototype Freighter.
## The ship scene is the single source of truth for dry mass and payload rating.
## Cargo modifies RigidBody3D mass and center_of_mass without moving vane mounts.

signal cargo_manifest_changed(manifest: Dictionary)

const MIN_CARGO_MASS_KG: float = 0.0

# Cargo hold physical bounds relative to ship origin (meters).
const CARGO_BAY_MIN: Vector3 = Vector3(-4.0, -1.0, -6.0)
const CARGO_BAY_MAX: Vector3 = Vector3(4.0, 1.0, 6.0)

var dry_mass_kg: float = 0.0
var max_payload_mass_kg: float = 0.0

@onready var _ship: ShipInteractable = get_parent() as ShipInteractable

var _cargo_mass_kg: float = 0.0
var _cargo_offset_m: Vector3 = Vector3.ZERO
var _current_preset: String = "EMPTY"


func _ready() -> void:
	if _ship == null:
		push_error("CargoSystem requires a ShipInteractable parent.")
		set_process(false)
		return

	# Do not duplicate ratings here: the ship's authored dry mass and payload
	# capacity are authoritative for propulsion, cargo limits and telemetry.
	dry_mass_kg = _ship.get_design_dry_mass_kg()
	max_payload_mass_kg = maxf(_ship.max_payload_mass_kg, 0.0)
	apply_manifest()


func get_cargo_mass_kg() -> float:
	return _cargo_mass_kg


func get_cargo_offset_m() -> Vector3:
	return _cargo_offset_m


func get_total_mass_kg() -> float:
	return dry_mass_kg + _cargo_mass_kg


## Combined center of mass relative to ship geometric origin:
## COM_combined = (M_dry * COM_dry + M_cargo * COM_cargo) / (M_dry + M_cargo)
## Assuming symmetrical empty hull COM is at Vector3.ZERO.
func get_combined_center_of_mass_m() -> Vector3:
	var total: float = get_total_mass_kg()
	if total <= 0.0001:
		return Vector3.ZERO
	return (_cargo_offset_m * _cargo_mass_kg) / total


## Nominal 1g hover estimate using the fixed 1.10 gross-TWR design rating.
## It intentionally excludes thermal derating, damage and local gravity changes.
func get_hover_throttle_estimate() -> float:
	var design_gross_mass: float = dry_mass_kg + max_payload_mass_kg
	var bottom_max_thrust_newtons: float = design_gross_mass * 9.81 * 1.10
	if bottom_max_thrust_newtons <= 0.001:
		return 0.50
	var required_lift_newtons: float = get_total_mass_kg() * 9.81
	return clampf(required_lift_newtons / bottom_max_thrust_newtons, 0.0, 1.0)


func set_cargo(mass_kg: float, offset_m: Vector3, preset_name: String = "CUSTOM") -> void:
	_cargo_mass_kg = clampf(mass_kg, MIN_CARGO_MASS_KG, max_payload_mass_kg)
	_cargo_offset_m = Vector3(
		clampf(offset_m.x, CARGO_BAY_MIN.x, CARGO_BAY_MAX.x),
		clampf(offset_m.y, CARGO_BAY_MIN.y, CARGO_BAY_MAX.y),
		clampf(offset_m.z, CARGO_BAY_MIN.z, CARGO_BAY_MAX.z)
	)
	_current_preset = preset_name
	apply_manifest()


func load_preset(preset_name: String) -> void:
	match preset_name.to_upper():
		"EMPTY":
			set_cargo(0.0, Vector3.ZERO, "EMPTY")
		"HALF_CENTERED":
			set_cargo(max_payload_mass_kg * 0.5, Vector3.ZERO, "HALF_CENTERED")
		"MAX_GROSS":
			set_cargo(max_payload_mass_kg, Vector3.ZERO, "MAX_GROSS")
		"PORT_HEAVY":
			set_cargo(20000.0, Vector3(-3.0, 0.0, 0.0), "PORT_HEAVY")
		"STARBOARD_HEAVY":
			set_cargo(20000.0, Vector3(3.0, 0.0, 0.0), "STARBOARD_HEAVY")
		"NOSE_HEAVY":
			set_cargo(20000.0, Vector3(0.0, 0.0, -4.0), "NOSE_HEAVY")
		"AFT_HEAVY":
			set_cargo(20000.0, Vector3(0.0, 0.0, 4.0), "AFT_HEAVY")
		_:
			push_warning("Unknown cargo preset: %s" % preset_name)


func apply_manifest() -> void:
	var total_mass: float = get_total_mass_kg()
	var com: Vector3 = get_combined_center_of_mass_m()

	if is_instance_valid(_ship):
		_ship.mass = total_mass
		_ship.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		_ship.center_of_mass = com

	cargo_manifest_changed.emit(get_telemetry())


func get_telemetry() -> Dictionary:
	return {
		"preset": _current_preset,
		"dry_mass_kg": dry_mass_kg,
		"cargo_mass_kg": _cargo_mass_kg,
		"total_mass_kg": get_total_mass_kg(),
		"cargo_offset_m": _cargo_offset_m,
		"center_of_mass_m": get_combined_center_of_mass_m(),
		"max_payload_kg": max_payload_mass_kg,
		"max_gross_kg": dry_mass_kg + max_payload_mass_kg,
		"load_fraction": _cargo_mass_kg / maxf(max_payload_mass_kg, 1.0),
		"hover_throttle_estimate": get_hover_throttle_estimate(),
	}
