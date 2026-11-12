extends RefCounted
class_name ShipDefinition

## Runtime-independent, validated ship configuration.
## The loader owns parsing/validation; simulation systems consume this object.

var schema_version: int = 1
var ship_id: String = ""
var display_name: String = ""
var manufacturer: String = ""
var ship_class: String = ""
var physics: Dictionary = {}
var cargo: Dictionary = {}
var propulsion: Dictionary = {}
var handling: Dictionary = {}
var aerodynamics: Dictionary = {}
var ground_effect: Dictionary = {}
var cameras: Dictionary = {}
var vanes: Array[Dictionary] = []

func configure(source: Dictionary) -> void:
	schema_version = int(source.get("schema_version", 1))
	ship_id = str(source.get("id", ""))
	display_name = str(source.get("display_name", ""))
	var identity: Dictionary = source.get("identity", {})
	manufacturer = str(identity.get("manufacturer", ""))
	ship_class = str(identity.get("class", ""))
	physics = source.get("physics", {}).duplicate(true)
	cargo = source.get("cargo", {}).duplicate(true)
	propulsion = source.get("propulsion", {}).duplicate(true)
	handling = source.get("handling", {}).duplicate(true)
	aerodynamics = source.get("aerodynamics", {}).duplicate(true)
	ground_effect = source.get("ground_effect", {}).duplicate(true)
	cameras = source.get("cameras", {}).duplicate(true)
	vanes.clear()
	for vane_variant: Variant in propulsion.get("vanes", []):
		if vane_variant is Dictionary:
			vanes.append(vane_variant.duplicate(true))
