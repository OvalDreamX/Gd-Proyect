extends Resource
class_name VaneDefinition

## Immutable-by-convention configuration for one logical field-influence vane.
## Runtime condition is stored separately by VaneController per ship instance.

@export var vane_id: StringName = &""
@export var display_name: String = ""
@export var group_id: StringName = &""
## Blender anchor family; this describes the available ship-local thrust axis,
## not an exclusive maneuver role.
@export var axis_family: StringName = &"unspecified"
## Bidirectional thrust axis in ship-local coordinates. The allocator may use
## either sign; the anchor name selects the axis family, not the sign.
@export var local_thrust_axis: Vector3 = Vector3.UP
## Integer control-mixing weights (0..100). These are intent weights, not
## percentages of physical force. Geometry and authority determine actual output.
@export var control_weights: Dictionary = {
	"pitch": 0,
	"roll": 0,
	"yaw": 0,
	"lift": 0,
	"main_thrust": 0,
	"translate_x": 0,
	"translate_y": 0,
	"translate_z": 0,
}
## Position relative to the ship's local origin, in metres.
@export var local_position: Vector3 = Vector3.ZERO
## Nominal authority as a fraction of maximum design gross weight. The
## RepulsorliftSystem converts this gross-mass TWR into fixed rated force.
## PLACEHOLDER values are tuned through the GDD's flight-model tests.
@export_range(0.0, 3.0, 0.005) var nominal_authority_twr: float = 0.0
@export var enabled: bool = true


func get_control_weight(channel: StringName) -> int:
	return clampi(int(control_weights.get(String(channel), 0)), 0, 100)
