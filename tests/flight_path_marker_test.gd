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
	_expect_near_vector(Vector2(aligned.get("position", Vector2.ZERO)), CENTER, EPSILON, "Aligned velocity places the marker on the boresight")

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
	_expect(right_position.x > CENTER.x, "Rightward velocity places the marker right of the boresight")
	_expect(float(right_drift.get("lateral_angle_degrees", 0.0)) > 0.0, "Rightward drift reports a positive lateral flight-path angle")
	_expect(not bool(right_drift.get("clipped", true)), "Small drift remains inside the HUD field")

	# A level inertial track with the nose pitched up must appear below boresight.
	var nose_up_basis := Basis(Vector3.RIGHT, deg_to_rad(10.0))
	var horizontal_track: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 0.0, -40.0), nose_up_basis, CENTER
	)
	var horizontal_track_position: Vector2 = horizontal_track.get("position", CENTER)
	_expect(horizontal_track_position.y > CENTER.y, "Nose-up attitude with level travel places the marker below boresight")
	_expect(float(horizontal_track.get("vertical_angle_degrees", 0.0)) < 0.0, "Level travel relative to a nose-up ship has a negative local flight-path angle")

	var clipped: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(40.0, 0.0, -20.0), Basis.IDENTITY, CENTER
	)
	_expect(bool(clipped.get("clipped", false)), "Large sideslip clips the flight-path marker to the HUD boundary")
	var clipped_position: Vector2 = clipped.get("position", CENTER)
	_expect_near(clipped_position.x, 1022.0, EPSILON, "Clipped marker is held just inside the right HUD boundary")

	var diagonal_clipped: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(40.0, 20.0, -10.0), Basis.IDENTITY, CENTER
	)
	var diagonal_position: Vector2 = diagonal_clipped.get("position", CENTER)
	_expect(bool(diagonal_clipped.get("clipped", false)), "Diagonal velocity beyond the HUD becomes an edge cue")
	_expect_near(diagonal_position.x, 1022.0, EPSILON, "Diagonal cue intersects the first HUD edge, not the corner")
	_expect(diagonal_position.y > 148.0 and diagonal_position.y < 484.0, "Diagonal edge cue preserves its direction along the HUD boundary")

	# Perspective must follow the active camera FOV: a fixed angular offset occupies more pixels at a narrower FOV.
	var wide_fov_focal: float = 720.0 / (2.0 * tan(deg_to_rad(78.0) * 0.5))
	var narrow_fov_focal: float = 720.0 / (2.0 * tan(deg_to_rad(40.0) * 0.5))
	var wide: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 5.0, -30.0), Basis.IDENTITY, CENTER, wide_fov_focal
	)
	var zoomed: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 5.0, -30.0), Basis.IDENTITY, CENTER, narrow_fov_focal
	)
	var wide_offset: float = absf(Vector2(wide.get("position", CENTER)).y - CENTER.y)
	var zoomed_offset: float = absf(Vector2(zoomed.get("position", CENTER)).y - CENTER.y)
	_expect(zoomed_offset > wide_offset, "Narrower camera FOV magnifies the FPM using the camera's actual FOV")

	_expect(HUD_OVERLAY_SCRIPT.heading_label_degrees(359.6) == 0, "Compass rounds 359.6 degrees through north to 000")
	_expect(HUD_OVERLAY_SCRIPT.heading_label_degrees(0.0, -10.0) == 350, "Compass tape wraps negative offsets")

	var five_degree_offset: float = HUD_OVERLAY_SCRIPT.calculate_pitch_mark_offset_pixels(0.0, -5.0)
	var ten_degree_offset: float = HUD_OVERLAY_SCRIPT.calculate_pitch_mark_offset_pixels(0.0, -10.0)
	_expect(ten_degree_offset > five_degree_offset * 2.0, "Perspective ladder spacing increases with angular displacement")

	var stationary: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3.ZERO, Basis.IDENTITY, CENTER
	)
	_expect(not bool(stationary.get("visible", true)), "Stationary ship hides the flight-path marker")
	var reverse: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(0.0, 0.0, 12.0), Basis.IDENTITY, CENTER
	)
	_expect(bool(reverse.get("visible", false)), "Reverse travel still reports a velocity direction")
	_expect(bool(reverse.get("clipped", false)), "A velocity vector behind the camera is shown as an off-field cue")
	var reverse_position: Vector2 = reverse.get("position", CENTER)
	_expect_near(reverse_position.x, CENTER.x, EPSILON, "Directly aft velocity uses the bottom-center edge cue")
	_expect(reverse_position.y > CENTER.y, "Directly aft velocity is indicated below the boresight")
	var rear_right: Dictionary = HUD_OVERLAY_SCRIPT.calculate_flight_path_marker(
		Vector3(5.0, 0.0, 12.0), Basis.IDENTITY, CENTER
	)
	_expect(Vector2(rear_right.get("position", CENTER)).x > CENTER.x, "Rearward-right velocity retains its correct lateral edge direction")

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
