extends Node
class_name CargoSystem

## Independent cargo and mass subsystem for the Prototype Freighter.
## The ship scene is the single source of truth for dry mass and payload rating.
## Cargo modifies mass, center of mass and the body-axis diagonal inertia.
## The prototype represents the dry hull and consolidated cargo as aligned cuboids.

signal cargo_manifest_changed(manifest: Dictionary)

const MIN_CARGO_MASS_KG: float = 0.0

# Cargo hold physical bounds relative to ship origin (meters).
const CARGO_BAY_MIN: Vector3 = Vector3(-4.0, -1.0, -6.0)
const CARGO_BAY_MAX: Vector3 = Vector3(4.0, 1.0, 6.0)
const FALLBACK_DRY_HULL_DIMENSIONS_LOCAL_M: Vector3 = Vector3(3.6, 1.5, 5.2)
@export_category("Cargo inertia approximation")
## Maximum consolidated cargo envelope at full payload. Smaller manifests scale
## all three dimensions by the cube root of their load fraction.
@export var payload_distribution_dimensions_local_m: Vector3 = Vector3(2.0, 1.0, 3.0)

var dry_mass_kg: float = 0.0
var max_payload_mass_kg: float = 0.0
var _dry_hull_dimensions_local_m: Vector3 = FALLBACK_DRY_HULL_DIMENSIONS_LOCAL_M

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
	_dry_hull_dimensions_local_m = _read_dry_hull_box_dimensions()
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


## Reads the current prototype hull collider so its mass distribution follows the
## authored shape instead of duplicating dimensions in another subsystem.
func _read_dry_hull_box_dimensions() -> Vector3:
	var collision_shape := _ship.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null and collision_shape.shape is BoxShape3D:
		if (
			collision_shape.position.length_squared() > 0.000001
			or collision_shape.rotation.length_squared() > 0.000001
		):
			push_warning("Cargo inertia expects the dry hull BoxShape3D to be centered and axis-aligned; using fallback dimensions.")
			return FALLBACK_DRY_HULL_DIMENSIONS_LOCAL_M
		var box := collision_shape.shape as BoxShape3D
		return Vector3(
			absf(box.size.x * collision_shape.scale.x),
			absf(box.size.y * collision_shape.scale.y),
			absf(box.size.z * collision_shape.scale.z)
		)
	push_warning("Cargo inertia could not read a centered BoxShape3D; using the prototype hull dimensions.")
	return FALLBACK_DRY_HULL_DIMENSIONS_LOCAL_M


func _get_scaled_cargo_dimensions_local_m() -> Vector3:
	if _cargo_mass_kg <= 0.0001 or max_payload_mass_kg <= 0.0001:
		return Vector3.ZERO
	var load_fraction: float = clampf(_cargo_mass_kg / max_payload_mass_kg, 0.0, 1.0)
	var linear_scale: float = pow(load_fraction, 1.0 / 3.0)
	var maximum_bay_dimensions: Vector3 = CARGO_BAY_MAX - CARGO_BAY_MIN
	var safe_dimensions := Vector3(
		clampf(payload_distribution_dimensions_local_m.x, 0.0, maximum_bay_dimensions.x),
		clampf(payload_distribution_dimensions_local_m.y, 0.0, maximum_bay_dimensions.y),
		clampf(payload_distribution_dimensions_local_m.z, 0.0, maximum_bay_dimensions.z)
	)
	return safe_dimensions * linear_scale


static func calculate_box_inertia_diagonal(mass_kg: float, dimensions_local_m: Vector3) -> Vector3:
	var mass: float = maxf(mass_kg, 0.0)
	var dimensions := Vector3(
		absf(dimensions_local_m.x),
		absf(dimensions_local_m.y),
		absf(dimensions_local_m.z)
	)
	return Vector3(
		mass * (dimensions.y * dimensions.y + dimensions.z * dimensions.z) / 12.0,
		mass * (dimensions.x * dimensions.x + dimensions.z * dimensions.z) / 12.0,
		mass * (dimensions.x * dimensions.x + dimensions.y * dimensions.y) / 12.0
	)


## Parallel-axis theorem about the combined COM. The returned Vector3 is the
## diagonal in ship-local axes. Vector3 products hold Ixy, Ixz and Iyz; Godot's
## RigidBody3D.inertia property cannot encode those off-diagonal terms.
static func calculate_combined_inertia(
		dry_mass: float,
		dry_dimensions_local_m: Vector3,
		cargo_mass: float,
		cargo_dimensions_local_m: Vector3,
		cargo_center_local_m: Vector3
) -> Dictionary:
	var safe_dry_mass: float = maxf(dry_mass, 0.0)
	var safe_cargo_mass: float = maxf(cargo_mass, 0.0)
	var total_mass: float = safe_dry_mass + safe_cargo_mass
	if total_mass <= 0.0001:
		return {"diagonal": Vector3.ZERO, "products": Vector3.ZERO, "center_of_mass": Vector3.ZERO}

	var combined_com: Vector3 = cargo_center_local_m * (safe_cargo_mass / total_mass)
	var dry_delta: Vector3 = -combined_com
	var cargo_delta: Vector3 = cargo_center_local_m - combined_com
	var dry_intrinsic: Vector3 = calculate_box_inertia_diagonal(safe_dry_mass, dry_dimensions_local_m)
	var cargo_intrinsic: Vector3 = calculate_box_inertia_diagonal(safe_cargo_mass, cargo_dimensions_local_m)
	var diagonal := dry_intrinsic + cargo_intrinsic + Vector3(
		safe_dry_mass * (dry_delta.y * dry_delta.y + dry_delta.z * dry_delta.z)
			+ safe_cargo_mass * (cargo_delta.y * cargo_delta.y + cargo_delta.z * cargo_delta.z),
		safe_dry_mass * (dry_delta.x * dry_delta.x + dry_delta.z * dry_delta.z)
			+ safe_cargo_mass * (cargo_delta.x * cargo_delta.x + cargo_delta.z * cargo_delta.z),
		safe_dry_mass * (dry_delta.x * dry_delta.x + dry_delta.y * dry_delta.y)
			+ safe_cargo_mass * (cargo_delta.x * cargo_delta.x + cargo_delta.y * cargo_delta.y)
	)
	var products := Vector3(
		-(safe_dry_mass * dry_delta.x * dry_delta.y + safe_cargo_mass * cargo_delta.x * cargo_delta.y),
		-(safe_dry_mass * dry_delta.x * dry_delta.z + safe_cargo_mass * cargo_delta.x * cargo_delta.z),
		-(safe_dry_mass * dry_delta.y * dry_delta.z + safe_cargo_mass * cargo_delta.y * cargo_delta.z)
	)
	return {"diagonal": diagonal, "products": products, "center_of_mass": combined_com}


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
	if _cargo_mass_kg <= 0.0001:
		_cargo_offset_m = Vector3.ZERO
	else:
		var half_envelope: Vector3 = _get_scaled_cargo_dimensions_local_m() * 0.5
		_cargo_offset_m = Vector3(
			clampf(offset_m.x, CARGO_BAY_MIN.x + half_envelope.x, CARGO_BAY_MAX.x - half_envelope.x),
			clampf(offset_m.y, CARGO_BAY_MIN.y + half_envelope.y, CARGO_BAY_MAX.y - half_envelope.y),
			clampf(offset_m.z, CARGO_BAY_MIN.z + half_envelope.z, CARGO_BAY_MAX.z - half_envelope.z)
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

	var inertia_data: Dictionary = calculate_combined_inertia(
		dry_mass_kg,
		_dry_hull_dimensions_local_m,
		_cargo_mass_kg,
		_get_scaled_cargo_dimensions_local_m(),
		_cargo_offset_m
	)
	if is_instance_valid(_ship):
		_ship.mass = total_mass
		_ship.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		_ship.center_of_mass = com
		# Godot's RigidBody3D.inertia is the body-axis diagonal in kg·m².
		# Off-diagonal products are preserved in telemetry for future full-tensor work.
		var diagonal: Vector3 = inertia_data.get("diagonal", Vector3.ZERO)
		_ship.inertia = Vector3(maxf(diagonal.x, 0.001), maxf(diagonal.y, 0.001), maxf(diagonal.z, 0.001))
		# A changed mass distribution must refresh solver state on the next tick.
		_ship.sleeping = false

	cargo_manifest_changed.emit(get_telemetry())


func get_telemetry() -> Dictionary:
	return {
		"preset": _current_preset,
		"dry_mass_kg": dry_mass_kg,
		"cargo_mass_kg": _cargo_mass_kg,
		"total_mass_kg": get_total_mass_kg(),
		"cargo_offset_m": _cargo_offset_m,
		"center_of_mass_m": get_combined_center_of_mass_m(),
		"cargo_distribution_dimensions_local_m": _get_scaled_cargo_dimensions_local_m(),
		"dry_hull_dimensions_local_m": _dry_hull_dimensions_local_m,
		"inertia_diagonal_kg_m2": _ship.inertia if is_instance_valid(_ship) else Vector3.ZERO,
		"inertia_products_kg_m2": calculate_combined_inertia(
			dry_mass_kg, _dry_hull_dimensions_local_m, _cargo_mass_kg,
			_get_scaled_cargo_dimensions_local_m(), _cargo_offset_m
		).get("products", Vector3.ZERO),
		"inertia_model": "ALIGNED_BOXES_DIAGONAL_APPROXIMATION",
		"inertia_products_omitted_from_solver": true,
		"max_payload_kg": max_payload_mass_kg,
		"max_gross_kg": dry_mass_kg + max_payload_mass_kg,
		"load_fraction": _cargo_mass_kg / maxf(max_payload_mass_kg, 1.0),
		"hover_throttle_estimate": get_hover_throttle_estimate(),
	}
