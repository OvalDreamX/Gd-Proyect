extends SceneTree

## Projection and visibility checks for the cockpit flight-path marker.
## Run from the project root:
## godot --headless --path . --script res://tests/flight_path_marker_test.gd

const HUD_OVERLAY_SCRIPT = preload("res://scripts/flight_hud_overlay.gd")
const CENTER := Vector2(640.0, 348.0)
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

	# The active camera basis, not the ship body forward axis, is the projection reference.
	var yawed_view_basis := Basis(Vector3.UP, deg_to_rad(90.0))
	var camera_aligned: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(-30.0, 0.0, 0.0), yawed_view_basis, CENTER
	)
	_expect(bool(camera_aligned.get("visible", false)), "World velocity remains visible after camera-look rotation")
	_expect_near_vector(Vector2(camera_aligned.get("position", Vector2.ZERO)), CENTER, EPSILON, "Flight-path vector is projected relative to the active view")

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
	_expect_near(
		clipped_position.x,
		CENTER.x + 23.0 * 4.0,
		EPSILON,
		"Clipped marker stops at the configured lateral display limit"
	)

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
