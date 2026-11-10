extends Resource
class_name VaneDefinition

## Immutable-by-convention configuration for one logical field-influence vane.
## Runtime condition is stored separately by VaneController per ship instance.

@export var vane_id: StringName = &""
@export var display_name: String = ""
@export var group_id: StringName = &""
## Position relative to the ship's local origin, in metres.
@export var local_position: Vector3 = Vector3.ZERO
## Nominal authority expressed as a fraction of ship weight (TWR).
## PLACEHOLDER values are tuned through the GDD's flight-model tests.
@export_range(0.0, 3.0, 0.005) var nominal_authority_twr: float = 0.0
@export var enabled: bool = true
