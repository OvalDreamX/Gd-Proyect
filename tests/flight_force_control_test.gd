extends SceneTree

## Deterministic force-allocation and rigid-body smoke checks.
## Run from the project root:
## godot --headless --path . --script res://tests/flight_force_control_test.gd

const SHIP_SCENE = preload("res://scenes/ship.tscn")
const VANE_DEFINITION_SCRIPT = preload("res://scripts/vane_definition.gd")
const EPSILON: float = 0.01
## Godot Vector3 uses single-precision components. Summing large opposing force
## vectors can leave a sub-0.1 N diagnostic residual even when the wrench is
## balanced to better than 1e-7 of the rated ship force.
const FORCE_VECTOR_CANCELLATION_TOLERANCE_N: float = 0.1
const TEST_ALTITUDE: float = 100.0
const TEST_TICKS: int = 30

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_expect_near_vector(
		RepulsorliftSystem.main_vector_direction_local(0.0),
		Vector3.FORWARD,
		0.0001,
		"0 degrees points forward relative to the ship"
	)
	_expect_near_vector(
		RepulsorliftSystem.main_vector_direction_local(90.0),
		Vector3.UP,
		0.0001,
		"90 degrees points upward for VTOL hover"
	)
	var braking_direction: Vector3 = RepulsorliftSystem.main_vector_direction_local(110.0)
	_expect(braking_direction.y > 0.9 and braking_direction.z > 0.3, "110 degrees retains lift with a rearward braking component")

	var ship := SHIP_SCENE.instantiate() as ShipInteractable
	if ship == null:
		_fail("Could not instantiate scenes/ship.tscn")
		quit(1)
		return
	ship.position = Vector3(0.0, TEST_ALTITUDE, 0.0)
	root.add_child(ship)
	await physics_frame

	var vane_controller := ship.get_node("VaneController") as VaneController
	var system := ship.get_node("RepulsorliftSystem") as RepulsorliftSystem
	if vane_controller == null or system == null:
		_fail("Ship scene is missing VaneController or RepulsorliftSystem")
		quit(1)
		return

	var telemetry: Dictionary = {}
	var main_force: Vector3 = Vector3.ZERO

	_expect(vane_controller.is_configuration_valid(), "Vane configuration is valid")
	_set_all_vane_temperatures(vane_controller, 60.0)
	_expect_near(ship.mass, 30000.0, EPSILON, "Prototype freighter starts at 30 tonnes dry mass")
	_expect_near(ship.max_payload_mass_kg, 25000.0, EPSILON, "Prototype freighter payload rating is 25 tonnes")
	_expect_near(ship.get_design_gross_mass_kg(), 55000.0, EPSILON, "Design gross mass is 55 tonnes")
	_expect_equal(vane_controller.get_vane_count(), 7, "Four bottom, one rear/main and two side vanes are registered")
	_expect_near(
		vane_controller.get_group_nominal_authority_twr(&"bottom_front")
		+ vane_controller.get_group_nominal_authority_twr(&"bottom_rear"),
		1.1,
		0.0001,
		"Bottom vane array preserves 1.1 nominal TWR"
	)

	# Vane TWR values are fixed force ratings at 55 t design gross mass.
	# At maximum payload the lift array has only 0.10 g of excess acceleration.
	var expected_max_lift_force: float = 55000.0 * 9.81 * 1.1
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(main_force.y, expected_max_lift_force, 0.1, "Maximum lift force is rated at 55-tonne gross mass")
	_expect_near(float(telemetry.get("lift_maximum_twr", 0.0)), expected_max_lift_force / (30000.0 * ship.get_gravity().length()), 0.001, "Empty 30-tonne ship has more physical lift TWR than its loaded limit")
	ship.mass = 55000.0
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(main_force.y, expected_max_lift_force, 0.1, "Adding cargo does not increase rated maximum lift force")
	var local_gravity_mps2: float = ship.get_gravity().length()
	var actual_loaded_twr: float = expected_max_lift_force / (55000.0 * maxf(local_gravity_mps2, 0.001))
	var expected_loaded_hover_percent: float = 100.0 / actual_loaded_twr
	_expect_near(float(telemetry.get("lift_actual_twr", 0.0)), actual_loaded_twr, 0.001, "Fully loaded lift authority is approximately 1.10 physical TWR")
	_expect_near(float(telemetry.get("lift_hover_power_percent", 0.0)), expected_loaded_hover_percent, 0.02, "Fully loaded ship needs about 91% main-vector output merely to hover")
	ship.mass = 30000.0

	# Neutral hover must produce a central upward force and no control torque.
	vane_controller.reset_all_vanes()
	_set_all_vane_temperatures(vane_controller, 60.0)
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var neutral_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect(main_force.y > 0.0 and absf(main_force.z) <= EPSILON, "90-degree main vector is pure ship-local vertical lift")
	_expect_near(neutral_torque.length(), 0.0, EPSILON, "Neutral healthy field has no unwanted baseline torque")

	# Main-vector throttle controls translation, not whether the online field
	# can maneuver. At zero throttle the main force is zero, but all control
	# groups remain available and receive a bounded 20% reserve boost.
	system.apply_flight_control_forces(true, 0.0, 90.0, 1.0, 1.0, 1.0, 0.5, 1.2)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect_near(main_force.length(), 0.0, EPSILON, "Zero main-vector throttle produces no translational force")
	var combined_maneuver_forces: Array[Dictionary] = _forces_of_kind(telemetry, "maneuver")
	var idle_yaw_forces: Array[Dictionary] = _forces_of_kind(telemetry, "yaw")
	# With equal pitch and roll requests, the two diagonally opposed bottom
	# vanes form the minimum-force couple and generate both requested moments.
	# The other two bottom vanes remain eligible in the unified allocation but
	# correctly receive zero output for this particular command combination.
	_expect_equal(combined_maneuver_forces.size(), 2, "Combined equal pitch/roll demand uses the efficient diagonal actuator pair")
	var combined_idle_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect(absf(combined_idle_torque.x) > EPSILON and absf(combined_idle_torque.z) > EPSILON, "Diagonal allocation generates both pitch and roll moments")
	var combined_allocation: Dictionary = telemetry.get("maneuver_allocator", {})
	var bottom_vane_ids: Array[StringName] = [
		&"bottom_front_left", &"bottom_front_right", &"bottom_rear_left", &"bottom_rear_right"
	]
	_expect_equal(
		_count_outputs_for_vanes(combined_allocation.get("actuator_outputs", []), bottom_vane_ids),
		4,
		"All four bottom vanes remain eligible for combined pitch/roll allocation"
	)
	_expect_equal(idle_yaw_forces.size(), 2, "Yaw remains available through the legacy side-vane pair")
	_expect_near(float(telemetry.get("maneuver_power_multiplier", 0.0)), 1.2, EPSILON, "Idle main-vector allocation provides a capped 20% maneuver reserve")

	# Compare the same single-axis pitch allocation at zero and full main-vector
	# power; a shared actuator may contribute to pitch and roll, so combined
	# demands are reported as MANEUVER rather than double-counted per channel.
	system.apply_flight_control_forces(true, 0.0, 90.0, 1.0, 0.0, 0.0, 0.5, 1.2)
	telemetry = system.get_telemetry()
	var idle_pitch_forces: Array[Dictionary] = _forces_of_kind(telemetry, "pitch")
	var idle_pitch_magnitude: float = _sum_force_magnitudes(idle_pitch_forces)
	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0, 0.5, 1.2)
	telemetry = system.get_telemetry()
	var full_power_pitch_magnitude: float = _sum_force_magnitudes(_forces_of_kind(telemetry, "pitch"))
	_expect_equal(idle_pitch_forces.size(), 4, "Pitch demand is distributed over four geometric actuators")
	_expect_near(idle_pitch_magnitude / maxf(full_power_pitch_magnitude, 0.001), 1.2, 0.01, "Idle throttle increases maneuver force by only the configured 20%")

	# Pitch: front pair up, rear pair down. Their translations cancel while
	# their separated application points produce positive nose-up pitch torque.
	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	var pitch_forces: Array[Dictionary] = _forces_of_kind(telemetry, "pitch")
	var pitch_pair_force: Vector3 = _sum_forces(pitch_forces)
	var pitch_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_equal(pitch_forces.size(), 4, "Pitch allocation drives each eligible vane from its geometry")
	_expect_near(pitch_pair_force.length(), 0.0, FORCE_VECTOR_CANCELLATION_TOLERANCE_N, "Healthy pitch pair cancels net translation within Vector3 precision")
	_expect(pitch_torque.x > EPSILON, "Positive pitch command creates nose-up torque")
	var pitch_allocation: Dictionary = telemetry.get("maneuver_allocator", {})
	_expect(bool(pitch_allocation.get("success", false)), "Pitch actuator allocation succeeds")
	_expect(bool(pitch_allocation.get("converged", false)), "Pitch actuator allocation converges from its warm start")
	_expect_equal(int(telemetry.get("maneuver_allocator_active_actuators", 0)), 4, "Pitch allocation discovers all four configured bottom actuators")

	# Roll: left pair up, right pair down.
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 1.0, 0.0)
	telemetry = system.get_telemetry()
	var roll_forces: Array[Dictionary] = _forces_of_kind(telemetry, "roll")
	var roll_pair_force: Vector3 = _sum_forces(roll_forces)
	var roll_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_equal(roll_forces.size(), 4, "Roll allocation drives each eligible vane from its geometry")
	_expect_near(roll_pair_force.length(), 0.0, FORCE_VECTOR_CANCELLATION_TOLERANCE_N, "Healthy roll pair cancels net translation within Vector3 precision")
	_expect(roll_torque.z < -EPSILON, "Positive roll command banks right")

	# Yaw uses the side-vane pair in opposite fore/aft directions.
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 1.0)
	telemetry = system.get_telemetry()
	var yaw_forces: Array[Dictionary] = _forces_of_kind(telemetry, "yaw")
	var yaw_pair_force: Vector3 = _sum_forces(yaw_forces)
	var yaw_torque: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_equal(yaw_forces.size(), 2, "Yaw creates left and right side-vane force vectors")
	_expect_near(yaw_pair_force.length(), 0.0, EPSILON, "Healthy yaw pair cancels net translation")
	_expect(yaw_torque.y < -EPSILON, "Positive yaw command turns the nose right")

	# Q/E changes the ship-relative main force vector, not just a HUD value.
	# Earlier online test calls apply the controller's baseline operating wear
	# even when this vane is not carrying meaningful load. Restoring temperature
	# alone is insufficient: the accumulated integrity loss also derates output.
	# Reset both condition variables immediately before this nominal-rating test.
	_expect(
		vane_controller.set_vane_integrity(&"main_rear", 1.0),
		"Main propulsion actuator integrity is restored for its rated-force test"
	)
	_expect(
		vane_controller.set_vane_temperature(&"main_rear", 60.0),
		"Main propulsion actuator temperature is restored for its rated-force test"
	)
	_expect_near(
		vane_controller.get_vane_effective_authority_twr(&"main_rear"),
		1.5,
		0.0001,
		"Main propulsion actuator is at nominal 60 C authority before rated-force test"
	)
	system.apply_flight_control_forces(true, 1.0, 0.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect(main_force.z < 0.0 and absf(main_force.y) <= EPSILON, "0-degree vector produces forward translation")
	_expect_near(main_force.length(), 55000.0 * 9.81 * 1.5, 0.1, "Main propulsion is rated at 1.50 gross TWR")
	system.apply_flight_control_forces(true, 1.0, 110.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	_expect(main_force.y > 0.0 and main_force.z > 0.0, "110-degree vector produces lift plus rearward braking")

	# The main vector follows ship orientation rather than remaining world-up.
	var rolled_basis := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	ship.freeze = true
	ship.global_transform = Transform3D(rolled_basis, Vector3(0.0, TEST_ALTITUDE, 0.0))
	ship.freeze = false
	system.apply_flight_control_forces(true, 1.0, 90.0, 0.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	main_force = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var expected_ship_up: Vector3 = rolled_basis * Vector3.UP
	_expect_near_vector(main_force.normalized(), expected_ship_up, 0.0001, "Main lift vector rotates with the ship instead of staying world-up")
	ship.freeze = true
	ship.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, TEST_ALTITUDE, 0.0))
	ship.freeze = false

	# Field OFF must remove every primary and secondary force immediately.
	system.apply_flight_control_forces(false, 1.0, 90.0, 1.0, 1.0, 1.0)
	telemetry = system.get_telemetry()
	_expect_near(telemetry.get("lift_force_newtons", 0.0), 0.0, EPSILON, "Field OFF removes all generated forces")
	_expect_equal(telemetry.get("lift_force_vectors", []).size(), 0, "Field OFF leaves no active force-vector debug entries")

	# Isolate 0.2 linear 0.5-TWR math check from ship.json tiered integrity curve.
	var prev_tiered_ffc: bool = bool(vane_controller.get("tiered_integrity_enabled"))
	vane_controller.set("tiered_integrity_enabled", false)
	# A damaged asymmetric lift array cannot always be represented as a central
	# main force plus a torque-only maneuver delta. In that case the unified
	# solver correctly reports the physical actuator forces as COMBINED.
	vane_controller.reset_all_vanes()
	_set_all_vane_temperatures(vane_controller, 60.0)
	vane_controller.set_vane_integrity(&"bottom_front_right", 0.5)
	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0, 0.0, 1.2)
	telemetry = system.get_telemetry()
	var damaged_combined_forces: Array[Dictionary] = _forces_of_kind(telemetry, "combined")
	var damaged_roll_moment: Vector3 = telemetry.get("lift_torque_vector", Vector3.ZERO)
	_expect_equal(damaged_combined_forces.size(), 4, "Damaged lift and pitch are reported as combined forces when the main-only baseline is infeasible")
	_expect(damaged_roll_moment.z < -EPSILON, "Asymmetric vane damage creates the expected cross-axis roll moment")
	var uncompensated_authority: float = _sum_contribution_authority(telemetry.get("lift_vane_contributions", []))
	var damaged_right_authority: float = _find_contribution_authority(
		telemetry.get("lift_vane_contributions", []), &"bottom_front_right"
	)
	_expect_near(damaged_right_authority, 0.1375, 0.0001, "Damaged actuator output reflects its 50% integrity limit")

	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0, 0.5, 1.2)
	telemetry = system.get_telemetry()
	var compensated_authority: float = _sum_contribution_authority(telemetry.get("lift_vane_contributions", []))
	var compensated_right_authority: float = _find_contribution_authority(
		telemetry.get("lift_vane_contributions", []), &"bottom_front_right"
	)
	_expect(compensated_authority > uncompensated_authority, "Geometry allocator redistributes part of a damaged vane's lost capacity to healthy actuators")
	_expect(compensated_authority < 1.1, "Redistribution does not conceal the full damaged-vane deficit")
	_expect_near(compensated_right_authority, damaged_right_authority, 0.0001, "Damaged actuator does not redistribute authority to itself")

	vane_controller.set("tiered_integrity_enabled", prev_tiered_ffc)
	# F3 controls only the visualization; it does not modify any force values.
	var debug_node := ship.get_node("ForceVectorDebug") as ForceVectorDebug
	system.set_debug_visualization_enabled(true)
	_expect(debug_node != null and debug_node.visible, "F3 debug activation shows force-vector arrows")
	system.set_debug_visualization_enabled(false)
	_expect(debug_node != null and not debug_node.visible, "Disabling F3 hides force-vector arrows")

	# One short live-physics smoke test verifies that the applied group forces
	# produce actual angular velocity on the single RigidBody3D.
	vane_controller.reset_all_vanes()
	ship.freeze = true
	ship.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, TEST_ALTITUDE, 0.0))
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.freeze = false
	ship.sleeping = false
	for _tick in range(TEST_TICKS):
		system.apply_flight_control_forces(true, 1.0, 90.0, 0.5, 0.0, 0.0)
		await physics_frame
	_expect(absf(ship.angular_velocity.x) > 0.001, "Geometry-allocated pitch forces produce physical angular velocity")

	# Runtime discovery must not depend on a fixed FR/FL/RR/RL slot list. Add
	# one extra pitch-only actuator through the same transactional config API and
	# verify the allocator discovers and commands it without changing main lift.
	var extended_definitions: Array[Resource] = []
	for vane_id: StringName in vane_controller.get_vane_ids():
		var existing_definition: Resource = vane_controller.get_vane_definition(vane_id)
		extended_definitions.append(existing_definition.duplicate(true))
	var extra_vane: Resource = VANE_DEFINITION_SCRIPT.new()
	extra_vane.set("vane_id", &"aux_pitch_center")
	extra_vane.set("display_name", "Auxiliary Pitch Center")
	extra_vane.set("group_id", &"maneuver_auxiliary")
	extra_vane.set("axis_family", &"vertical")
	extra_vane.set("local_thrust_axis", Vector3.UP)
	extra_vane.set("control_weights", {
		"pitch": 100,
		"roll": 0,
		"yaw": 0,
		"lift": 0,
		"main_thrust": 0,
		"translate_x": 0,
		"translate_y": 0,
		"translate_z": 0,
	})
	extra_vane.set("local_position", Vector3(0.0, -0.65, -1.8))
	extra_vane.set("nominal_authority_twr", 0.05)
	extended_definitions.append(extra_vane)
	var extended_result: Dictionary = vane_controller.configure_vanes(extended_definitions)
	_expect(bool(extended_result.get("success", false)), "VaneController accepts a runtime-added geometry actuator")
	_set_all_vane_temperatures(vane_controller, 60.0)
	system.apply_flight_control_forces(true, 1.0, 90.0, 1.0, 0.0, 0.0)
	telemetry = system.get_telemetry()
	_expect_equal(int(telemetry.get("maneuver_allocator_active_actuators", 0)), 5, "Geometry allocator discovers a fifth actuator without fixed slot assumptions")
	_expect(_find_contribution_authority(telemetry.get("lift_vane_contributions", []), &"aux_pitch_center") > 0.0, "Runtime-added actuator receives a nonzero geometry-derived pitch allocation")

	print("Flight force-control tests: %d checks, %d failures." % [_checks, _failures])
	ship.queue_free()
	quit(1 if _failures > 0 else 0)


func _forces_of_kind(telemetry: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in telemetry.get("lift_force_vectors", []):
		var force_entry: Dictionary = entry
		if str(force_entry.get("kind", "")) == kind:
			result.append(force_entry)
	return result


func _count_outputs_for_vanes(output_values: Array, vane_ids: Array[StringName]) -> int:
	var count: int = 0
	for output_value: Variant in output_values:
		if typeof(output_value) != TYPE_DICTIONARY:
			continue
		var output_entry: Dictionary = output_value
		var output_id := StringName(str(output_entry.get("id", "")))
		if vane_ids.has(output_id):
			count += 1
	return count


func _sum_forces(entries: Array[Dictionary]) -> Vector3:
	var total: Vector3 = Vector3.ZERO
	for entry in entries:
		total += entry.get("force_world", Vector3.ZERO)
	return total


func _sum_force_magnitudes(entries: Array[Dictionary]) -> float:
	var total: float = 0.0
	for entry in entries:
		var force: Vector3 = entry.get("force_world", Vector3.ZERO)
		total += force.length()
	return total


func _set_all_vane_temperatures(controller: VaneController, temperature_celsius: float) -> void:
	for vane_id: StringName in controller.get_vane_ids():
		controller.set_vane_temperature(vane_id, temperature_celsius)


func _sum_contribution_authority(contributions: Array) -> float:
	var total: float = 0.0
	for contribution_value: Variant in contributions:
		var contribution: Dictionary = contribution_value
		total += float(contribution.get("effective_authority_twr", 0.0))
	return total


func _find_contribution_authority(contributions: Array, vane_id: StringName) -> float:
	for contribution_value: Variant in contributions:
		var contribution: Dictionary = contribution_value
		if StringName(contribution.get("vane_id", &"")) == vane_id:
			return float(contribution.get("effective_authority_twr", 0.0))
	return 0.0


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_equal(actual: int, expected: int, description: String) -> void:
	_expect(actual == expected, "%s (actual %d, expected %d)" % [description, actual, expected])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.5f, expected %.5f ± %.5f)" % [description, actual, expected, tolerance])


func _expect_near_vector(actual: Vector3, expected: Vector3, tolerance: float, description: String) -> void:
	_expect(actual.distance_to(expected) <= tolerance, "%s (actual %s, expected %s)" % [description, str(actual), str(expected)])


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
