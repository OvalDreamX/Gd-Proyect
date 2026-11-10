extends SceneTree

## Projection and visibility checks for the cockpit flight-path marker.
## Run from the project root:
## godot --headless --path . --script res://tests/flight_path_marker_test.gd

const HUD_OVERLAY_SCRIPT = preload("res://scripts/flight_hud_overlay.gd")
const CENTER := Vector2(640.0, 360.0)
const EPSILON: float = 0.001

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var aligned: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 0.0, -30.0), Basis.IDENTITY, CENTER
	)
	_expect(bool(aligned.get("visible", false)), "Forward motion displays the flight-path marker")
	var aligned_position: Vector2 = aligned.get("position", Vector2.ZERO)
	_expect_near_vector(aligned_position, CENTER, EPSILON, "Aligned velocity places the marker on the nose reference")

	# The combiner is ship-mounted, so marker projection uses the measured ship
	# attitude. Camera head-look is deliberately not an input to this function.
	var ship_reference_basis := Basis.IDENTITY
	var head_look_basis := Basis(Vector3.UP, deg_to_rad(90.0))
	var head_look_independent: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 0.0, -30.0), ship_reference_basis, CENTER
	)
	_expect(bool(head_look_independent.get("visible", false)), "Flight-path marker remains valid while the pilot looks away")
	_expect_near_vector(Vector2(head_look_independent.get("position", Vector2.ZERO)), CENTER, EPSILON, "Marker alignment is measured against ship boresight, not camera head-look")
	_expect(head_look_basis != ship_reference_basis, "Head-look orientation is independent from ship instrument attitude")

	var right_drift: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(8.0, 0.0, -30.0), Basis.IDENTITY, CENTER
	)
	var right_position: Vector2 = right_drift.get("position", CENTER)
	_expect(right_position.x > CENTER.x, "Rightward velocity places the marker right of the nose reference")
	_expect(float(right_drift.get("lateral_angle_degrees", 0.0)) > 0.0, "Rightward drift reports a positive lateral flight-path angle")

	# With the nose pitched up but the world-space velocity horizontal, the
	# velocity marker must sit below the fixed nose reference (positive AoA).
	var nose_up_basis := Basis(Vector3.RIGHT, deg_to_rad(10.0))
	var horizontal_track: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 0.0, -40.0), nose_up_basis, CENTER
	)
	var horizontal_track_position: Vector2 = horizontal_track.get("position", CENTER)
	_expect(horizontal_track_position.y > CENTER.y, "Nose-up attitude with level travel places the marker below the nose reference")
	_expect(float(horizontal_track.get("vertical_angle_degrees", 0.0)) < 0.0, "Level travel relative to a nose-up ship has a negative local flight-path angle")

	var clipped: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(25.0, 0.0, -20.0), Basis.IDENTITY, CENTER
	)
	_expect(bool(clipped.get("clipped", false)), "Large sideslip is clamped to the visible HUD field")
	var clipped_position: Vector2 = clipped.get("position", CENTER)
	var projected_limit: float = 1280.0 * 0.90 / 2.78 * tan(deg_to_rad(23.0))
	_expect_near(
		clipped_position.x,
		CENTER.x + projected_limit,
		EPSILON,
		"Clipped marker stops at the angularly projected windshield limit"
	)

	# The pitch ladder uses perspective projection onto the windshield rather
	# than a linear approximation, so each mark corresponds to its true angle.
	var zero_pitch_offset: float = HUD_OVERLAY_SCRIPT.calculate_pitch_mark_offset_pixels(0.0, 0.0)
	var ten_degree_offset: float = HUD_OVERLAY_SCRIPT.calculate_pitch_mark_offset_pixels(10.0, 0.0)
	var twenty_degree_offset: float = HUD_OVERLAY_SCRIPT.calculate_pitch_mark_offset_pixels(20.0, 0.0)
	var matching_mark_offset: float = HUD_OVERLAY_SCRIPT.calculate_pitch_mark_offset_pixels(10.0, 10.0)
	_expect_near(zero_pitch_offset, 0.0, EPSILON, "Zero-degree pitch mark aligns with the aircraft reference at level attitude")
	_expect(ten_degree_offset > 0.0, "Nose-up pitch moves the horizon reference down the windshield")
	_expect_near(matching_mark_offset, 0.0, EPSILON, "A 10-degree pitch attitude aligns the +10-degree ladder mark with the reference")
	_expect(twenty_degree_offset > ten_degree_offset * 2.0, "Angular ladder spacing follows tangent projection, not a linear pixel scale")

	var stationary: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3.ZERO, Basis.IDENTITY, CENTER
	)
	_expect(not bool(stationary.get("visible", true)), "Stationary ship hides the flight-path marker")
	var reverse: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 0.0, 12.0), Basis.IDENTITY, CENTER
	)
	_expect(not bool(reverse.get("visible", true)), "Reverse travel hides the forward-looking flight-path marker")

	print("Flight-path marker tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_fail(description)


func _expect_near_vector(actual: Vector2, expected: Vector2, tolerance: float, description: String) -> void:
	_expect(actual.distance_to(expected) <= tolerance, "%s (actual %s, expected %s)" % [description, str(actual), str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual %.4f, expected %.4f)" % [description, actual, expected])


func _fail(description: String) -> void:
	_failures += 1
	push_error("FAIL: %s" % description)
