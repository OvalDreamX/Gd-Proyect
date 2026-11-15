extends SceneTree

## Run: godot --headless --path . --script res://tests/ship_cockpit_control_bridge_test.gd
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
	var ship: Node = SHIP_SCENE.instantiate()
	root.add_child(ship)
	await process_frame
	ship.set("freeze", true)

	var flight_controller: Node = ship.get_node("FlightController")
	var fcc: Node = ship.get_node("FlightControlComputer")
	_expect(flight_controller.has_method("request_cockpit_control"), "The scene uses the inherited cockpit-control bridge")

	var pilot := FakePilot.new()
	pilot.add_to_group("player")
	root.add_child(pilot)
	ship.call("request_pilot", pilot)
	_expect(bool(ship.call("is_pilot_ready")), "The test pilot successfully claims the cockpit")

	var initial_assistance: bool = bool(fcc.get("assistance_enabled"))
	_expect(bool(flight_controller.call("request_cockpit_control", &"switch_field_assist", 1.0)), "Field-assist switch is accepted while piloting")
	_expect(bool(fcc.get("assistance_enabled")) != initial_assistance, "Field-assist switch changes the existing FCC assistance state")

	flight_controller.set("startup_duration_seconds", 0.05)
	_expect(bool(flight_controller.call("request_cockpit_control", &"switch_main_power", 1.0)), "Main-power switch requests the existing field startup")
	var startup_deadline_msec: int = Time.get_ticks_msec() + 2000
	while String(flight_controller.call("_field_state_name")) != "ONLINE" and Time.get_ticks_msec() < startup_deadline_msec:
		await physics_frame
	_expect(String(flight_controller.call("_field_state_name")) == "ONLINE", "Existing field startup reaches ONLINE")

	_expect(bool(flight_controller.call("request_cockpit_control", &"lever_throttle", 0.35)), "Throttle lever is accepted while the field is online")
	_expect(is_equal_approx(float(flight_controller.get("_field_power_command")), 0.35), "Throttle lever updates the existing field-power command")
	_expect(bool(flight_controller.call("request_cockpit_control", &"lever_vector_angle", 0.75)), "Vector lever is accepted while the field is online")
	_expect(is_equal_approx(float(flight_controller.get("_vector_distribution_degrees")), 82.5), "Vector lever maps normalized input to the existing 0–110 degree range")

	_expect(not bool(flight_controller.call("request_cockpit_control", &"button_landing_lights", 1.0)), "A control without an implemented subsystem remains rejected")
	_expect(bool(flight_controller.call("request_cockpit_control", &"switch_main_power", 1.0)), "Main-power switch can turn the field off")
	_expect(String(flight_controller.call("_field_state_name")) == "OFF", "Switching main power off uses the existing shutdown path")

	pilot.queue_free()
	await process_frame
	_expect(not bool(flight_controller.call("request_cockpit_control", &"switch_main_power", 1.0)), "Cockpit controls reject requests after the pilot leaves")

	print("Ship cockpit control bridge tests: %d checks, %d failures." % [_checks, _failures])
	ship.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
