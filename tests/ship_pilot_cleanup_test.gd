extends SceneTree

## Run: godot --headless --path . --script res://tests/ship_pilot_cleanup_test.gd
const SHIP_SCENE = preload("res://scenes/ship.tscn")

class FakePilot extends Node:
	func enter_pilot_seat(_seat_anchor: Node3D, _cockpit_camera: Camera3D, _hull_visual: Node3D, _cockpit_interior: Node3D) -> bool:
		return true

	func is_piloting() -> bool:
		return true

	func clear_nearby_ship(_ship: Node3D) -> void:
		pass

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var ship: ShipInteractable = SHIP_SCENE.instantiate() as ShipInteractable
	root.add_child(ship)
	await process_frame

	var first_pilot := FakePilot.new()
	first_pilot.add_to_group("player")
	root.add_child(first_pilot)
	ship.request_pilot(first_pilot)
	_expect(ship.is_pilot_ready(), "First player acquires the pilot claim")

	var hull: Node3D = ship.get_node("Visuals/Hull") as Node3D
	var interior: Node3D = ship.get_node("Visuals/CockpitInterior") as Node3D
	hull.visible = false
	interior.visible = true
	first_pilot.queue_free()
	await process_frame
	_expect(hull.visible and not interior.visible, "Unexpected pilot exit restores exterior and hides cockpit interior")

	var replacement_pilot := FakePilot.new()
	replacement_pilot.add_to_group("player")
	root.add_child(replacement_pilot)
	ship.request_pilot(replacement_pilot)
	_expect(ship.is_pilot_ready(), "Replacement player can claim the seat after the previous pilot exits")

	print("Ship pilot cleanup tests: %d checks, %d failures." % [_checks, _failures])
	replacement_pilot.queue_free()
	ship.queue_free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
