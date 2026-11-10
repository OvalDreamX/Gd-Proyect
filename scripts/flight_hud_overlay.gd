extends Control
class_name FlightHUDOverlay

## Cockpit-only primary flight display. This script is presentation-only:
## it reads telemetry snapshots and never changes ship input or physics.

const COLOR_PRIMARY := Color(0.50, 1.00, 0.78, 0.92)
const COLOR_SECONDARY := Color(0.29, 0.69, 0.56, 0.76)
const COLOR_DIM := Color(0.20, 0.46, 0.39, 0.60)
const COLOR_COMMAND := Color(1.00, 0.77, 0.36, 0.96)
const COLOR_WARNING := Color(1.00, 0.48, 0.30, 0.96)
const COLOR_FLIGHT_PATH := Color(0.48, 0.88, 1.00, 0.96)
const HUD_CONTENT_SCALE: float = 0.90
const FLIGHT_PATH_MAX_ANGLE_DEGREES: float = 23.0
const BASE_WIDTH: float = 1280.0
const BASE_HEIGHT: float = 720.0
const WINDSHIELD_REFERENCE_DISTANCE_M: float = 0.91
const WINDSHIELD_WIDTH_M: float = 2.78
const WINDSHIELD_ACTIVE_HEIGHT_M: float = 1.56375
const PITCH_LADDER_LIMIT_PX: float = 158.0
const WINDSHIELD_FOCAL_X_PX: float = BASE_WIDTH * WINDSHIELD_REFERENCE_DISTANCE_M / WINDSHIELD_WIDTH_M
const WINDSHIELD_FOCAL_Y_PX: float = BASE_HEIGHT * WINDSHIELD_REFERENCE_DISTANCE_M / WINDSHIELD_ACTIVE_HEIGHT_M

## SIDES stays in the 2D display layer; WINDSHIELD is drawn into a SubViewport
## texture on a physical quad attached to the ship's forward cockpit window.
var render_mode: StringName = &"FULL"
var _telemetry: Dictionary = {}


func update_telemetry(telemetry: Dictionary) -> void:
	_telemetry = telemetry.duplicate(false)
	queue_redraw()


## Projects the ship's world-space velocity into the cockpit's forward view.
## The returned marker is relative to the nose reference, not the horizon.
## Reverse/sideways motion is intentionally hidden because it is outside this
## forward-looking HUD's useful projection range.
static func calculate_flight_path_marker(
		velocity_world: Vector3,
		reference_basis: Basis,
		hud_center: Vector2,
		focal_x_pixels: float = WINDSHIELD_FOCAL_X_PX,
		maximum_angle_degrees: float = FLIGHT_PATH_MAX_ANGLE_DEGREES,
		minimum_speed_mps: float = 2.0
) -> Dictionary:
	var result: Dictionary = {
		"visible": false,
		"position": hud_center,
		"speed_mps": velocity_world.length(),
		"lateral_angle_degrees": 0.0,
		"vertical_angle_degrees": 0.0,
		"clipped": false,
	}
	if velocity_world.length_squared() < minimum_speed_mps * minimum_speed_mps:
		return result

	var local_velocity: Vector3 = reference_basis.orthonormalized().inverse() * velocity_world
	var forward_speed: float = -local_velocity.z
	if forward_speed < 1.0:
		return result

	var lateral_angle: float = rad_to_deg(atan2(local_velocity.x, forward_speed))
	var vertical_reference_speed: float = sqrt(
		local_velocity.x * local_velocity.x + forward_speed * forward_speed
	)
	var vertical_angle: float = rad_to_deg(atan2(local_velocity.y, vertical_reference_speed))
	var clipped_lateral: float = clampf(lateral_angle, -maximum_angle_degrees, maximum_angle_degrees)
	var clipped_vertical: float = clampf(vertical_angle, -maximum_angle_degrees, maximum_angle_degrees)
	result["visible"] = true
	result["position"] = hud_center + Vector2(
		focal_x_pixels * tan(deg_to_rad(clipped_lateral)),
		-WINDSHIELD_FOCAL_Y_PX * tan(deg_to_rad(clipped_vertical))
	)
	result["lateral_angle_degrees"] = lateral_angle
	result["vertical_angle_degrees"] = vertical_angle
	result["clipped"] = not is_equal_approx(lateral_angle, clipped_lateral) or not is_equal_approx(vertical_angle, clipped_vertical)
	return result


func _draw() -> void:
	if _telemetry.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return

	var font: Font = ThemeDB.fallback_font
	var fit_scale: float = minf(size.x / BASE_WIDTH, size.y / BASE_HEIGHT)
	var scale_factor: float = fit_scale
	var draw_offset := Vector2.ZERO
	if render_mode != &"WINDSHIELD":
		var ui_scale: float = 1.0
		var display_settings: Node = get_node_or_null("/root/DisplaySettings")
		if display_settings != null and display_settings.has_method("get_hud_scale"):
			ui_scale = float(display_settings.call("get_hud_scale"))
		scale_factor *= clampf(ui_scale, 0.8, 1.0) * HUD_CONTENT_SCALE
		var logical_size: Vector2 = size / maxf(scale_factor, 0.001)
		draw_offset = (logical_size - Vector2(BASE_WIDTH, BASE_HEIGHT)) * 0.5
	draw_set_transform(draw_offset, 0.0, Vector2.ONE * scale_factor)

	var pitch_input: float = float(_telemetry.get("pitch_command", 0.0))
	var roll_input: float = float(_telemetry.get("roll_command", 0.0))
	var yaw_input: float = float(_telemetry.get("yaw_command", 0.0))

	if render_mode == &"SIDES":
		var extra_space: Vector2 = (size / maxf(scale_factor, 0.001)) - Vector2(BASE_WIDTH, BASE_HEIGHT)
		var left_gauge_x: float = 88.0 - extra_space.x * 0.5
		var right_gauge_x: float = 1178.0 + extra_space.x * 0.5
		_draw_side_gauge(
			font, left_gauge_x, "MAIN VECTOR", "OUTPUT",
			float(_telemetry.get("field_power_output", 0.0)),
			float(_telemetry.get("field_power_command", 0.0)),
			1.0, "%"
		)
		_draw_side_gauge(
			font, right_gauge_x, "VECTOR ANGLE", "ACTUATOR",
			float(_telemetry.get("vector_distribution_actual_degrees", 90.0)),
			float(_telemetry.get("vector_distribution_degrees", 90.0)),
			110.0, "°"
		)
		_draw_input_indicators(font, pitch_input, roll_input, yaw_input)
		_draw_bottom_guidance(font)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	# The normal windshield display consumes instrument outputs only. Its
	# renderer does not inspect RigidBody3D or atmosphere-model state directly.
	var attitude_basis: Basis = _telemetry.get("instrument_attitude_basis_world", Basis.IDENTITY)
	attitude_basis = attitude_basis.orthonormalized()
	var flight_velocity: Vector3 = _telemetry.get("instrument_velocity_world", Vector3.ZERO)
	var pitch_degrees: float = float(_telemetry.get("instrument_pitch_degrees", 0.0))
	var bank_degrees: float = float(_telemetry.get("instrument_bank_degrees", 0.0))
	var heading_degrees: float = float(_telemetry.get("instrument_heading_degrees", 0.0))
	var altitude_m: float = float(_telemetry.get("instrument_altitude_m", 0.0))
	var vertical_speed_mps: float = float(_telemetry.get("instrument_vertical_speed_mps", 0.0))
	var speed_label: String = str(_telemetry.get("instrument_speed_label", "SPEED"))
	var attitude_valid: bool = bool(_telemetry.get("instrument_attitude_valid", false))
	var heading_valid: bool = bool(_telemetry.get("instrument_heading_valid", false))
	var velocity_valid: bool = bool(_telemetry.get("instrument_velocity_valid", false))
	var altitude_valid: bool = bool(_telemetry.get("instrument_altitude_valid", false))
	var field_state: String = str(_telemetry.get("field_state", "OFF"))
	var assistance_enabled: bool = bool(_telemetry.get("fcc_assistance_enabled", true))

	_draw_top_status(font, field_state, assistance_enabled)
	if heading_valid:
		_draw_heading_tape(font, heading_degrees)
	else:
		_draw_text(font, Vector2(584.0, 176.0), "HDG ---", 12, COLOR_WARNING, HORIZONTAL_ALIGNMENT_CENTER, 112.0)
	_draw_flight_data(
		font,
		flight_velocity,
		altitude_m,
		vertical_speed_mps,
		speed_label,
		pitch_degrees,
		bank_degrees,
		heading_degrees,
		velocity_valid,
		altitude_valid,
		heading_valid
	)
	if attitude_valid:
		_draw_attitude_ladder(font, pitch_degrees, bank_degrees)
	else:
		_draw_text(font, Vector2(555.0, 368.0), "ATTITUDE FAIL", 13, COLOR_WARNING, HORIZONTAL_ALIGNMENT_CENTER, 170.0)
	if velocity_valid and attitude_valid:
		_draw_flight_path_marker(flight_velocity, attitude_basis)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_side_gauge(
		font: Font,
		center_x: float,
		gauge_name: String,
		gauge_subtitle: String,
		actual_value: float,
		command_value: float,
		maximum_value: float,
		unit: String
) -> void:
	var top: float = 188.0
	var bottom: float = 486.0
	var height: float = bottom - top
	var bar_width: float = 8.0
	var actual_fraction: float = clampf(actual_value / maxf(maximum_value, 0.001), 0.0, 1.0)
	var command_fraction: float = clampf(command_value / maxf(maximum_value, 0.001), 0.0, 1.0)
	var actual_y: float = bottom - actual_fraction * height
	var command_y: float = bottom - command_fraction * height
	var bar_rect := Rect2(center_x - bar_width * 0.5, top, bar_width, height)

	_draw_text(font, Vector2(center_x - 64.0, 132.0), gauge_name, 11, COLOR_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER, 128.0)
	_draw_text(font, Vector2(center_x - 64.0, 151.0), gauge_subtitle, 9, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 128.0)
	_draw_text(
		font,
		Vector2(center_x - 66.0, 177.0),
		"ACT %s%s" % [String.num(actual_value, 1), unit],
		10,
		COLOR_PRIMARY,
		HORIZONTAL_ALIGNMENT_CENTER,
		132.0
	)

	draw_rect(bar_rect, COLOR_DIM, false, 0.9)
	for tick_index in range(0, 5):
		var tick_fraction: float = float(tick_index) / 4.0
		var tick_y: float = bottom - tick_fraction * height
		draw_line(Vector2(center_x + 7.0, tick_y), Vector2(center_x + 13.0, tick_y), COLOR_DIM, 0.7)
		if gauge_name == "MAIN VECTOR":
			_draw_text(font, Vector2(center_x + 20.0, tick_y + 4.0), str(tick_index * 25), 9, COLOR_DIM)
		else:
			_draw_text(font, Vector2(center_x + 20.0, tick_y + 4.0), str(tick_index * 110 / 4), 9, COLOR_DIM)

	if actual_fraction > 0.001:
		draw_rect(
			Rect2(center_x - 2.0, actual_y, 4.0, bottom - actual_y),
			COLOR_PRIMARY,
			true
		)
		draw_line(Vector2(center_x - 7.0, actual_y), Vector2(center_x + 7.0, actual_y), COLOR_PRIMARY, 1.2)

	# The pilot command is an independent amber tick. The filled output bar
	# follows the actuator value and therefore visibly lags the command.
	draw_line(Vector2(center_x - 15.0, command_y), Vector2(center_x + 16.0, command_y), COLOR_COMMAND, 1.2)
	draw_line(Vector2(center_x - 15.0, command_y - 3.0), Vector2(center_x - 15.0, command_y + 3.0), COLOR_COMMAND, 1.0)
	var command_label: String = "SET %s%s" % [String.num(command_value, 1), unit]
	var label_y: float = clampf(command_y - 7.0, top + 10.0, bottom - 5.0)
	_draw_text(font, Vector2(center_x - 58.0, label_y), command_label, 10, COLOR_COMMAND, HORIZONTAL_ALIGNMENT_CENTER, 116.0)

	_draw_text(font, Vector2(center_x - 56.0, 512.0), "ACTUAL", 9, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 112.0)
	_draw_text(font, Vector2(center_x - 56.0, 528.0), "SETPOINT", 9, COLOR_COMMAND, HORIZONTAL_ALIGNMENT_CENTER, 112.0)


func _draw_top_status(font: Font, field_state: String, assistance_enabled: bool) -> void:
	var state_color: Color = COLOR_PRIMARY
	if field_state == "OFF":
		state_color = COLOR_DIM
	elif field_state == "STARTING":
		state_color = COLOR_COMMAND
	_draw_text(font, Vector2(440.0, 82.0), "REPULSORLIFT  //  %s" % field_state, 12, state_color, HORIZONTAL_ALIGNMENT_CENTER, 400.0)
	_draw_text(
		font,
		Vector2(520.0, 105.0),
		"FCC ASSIST  %s" % ("ON" if assistance_enabled else "OFF / DIRECT"),
		10,
		COLOR_PRIMARY if assistance_enabled else COLOR_COMMAND,
		HORIZONTAL_ALIGNMENT_CENTER,
		240.0
	)
	_draw_corner_frame()


func _draw_corner_frame() -> void:
	var frame_color: Color = COLOR_DIM
	var corners: Array[Vector2] = [
		Vector2(238.0, 126.0), Vector2(1042.0, 126.0),
		Vector2(238.0, 506.0), Vector2(1042.0, 506.0),
	]
	var arm: float = 18.0
	# Short frame segments leave the center visually open.
	draw_line(corners[0], corners[0] + Vector2(arm, 0), frame_color, 0.7)
	draw_line(corners[0], corners[0] + Vector2(0, arm), frame_color, 0.7)
	draw_line(corners[1], corners[1] - Vector2(arm, 0), frame_color, 0.7)
	draw_line(corners[1], corners[1] + Vector2(0, arm), frame_color, 0.7)
	draw_line(corners[2], corners[2] + Vector2(arm, 0), frame_color, 0.7)
	draw_line(corners[2], corners[2] - Vector2(0, arm), frame_color, 0.7)
	draw_line(corners[3], corners[3] - Vector2(arm, 0), frame_color, 0.7)
	draw_line(corners[3], corners[3] - Vector2(0, arm), frame_color, 0.7)


func _draw_heading_tape(font: Font, heading_degrees: float) -> void:
	var center_x: float = 640.0
	var y: float = 151.0
	var edge_angle: float = 40.0
	var left_x: float = center_x + WINDSHIELD_FOCAL_X_PX * tan(deg_to_rad(-edge_angle))
	var right_x: float = center_x + WINDSHIELD_FOCAL_X_PX * tan(deg_to_rad(edge_angle))
	draw_line(Vector2(left_x, y), Vector2(right_x, y), COLOR_DIM, 0.7)
	for offset in range(-40, 41, 5):
		var tick_x: float = center_x + WINDSHIELD_FOCAL_X_PX * tan(deg_to_rad(float(offset)))
		var tick_height: float = 13.0 if posmod(offset, 10) == 0 else 6.0
		draw_line(Vector2(tick_x, y), Vector2(tick_x, y + tick_height), COLOR_SECONDARY, 0.7)
		if posmod(offset, 10) == 0:
			var label_heading: int = int(round(fposmod(heading_degrees + float(offset), 360.0)))
			_draw_text(font, Vector2(tick_x - 16.0, y - 8.0), "%03d" % label_heading, 9, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 32.0)
	draw_line(Vector2(center_x, y - 6.0), Vector2(center_x, y + 17.0), COLOR_PRIMARY, 1.3)
	draw_line(Vector2(center_x - 5.0, y - 6.0), Vector2(center_x + 5.0, y - 6.0), COLOR_PRIMARY, 1.1)
	_draw_text(font, Vector2(center_x - 42.0, 176.0), "%03d°" % (int(round(heading_degrees)) % 360), 12, COLOR_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER, 84.0)


func _draw_flight_data(
		font: Font,
		flight_velocity: Vector3,
		local_altitude: float,
		local_vertical_speed: float,
		speed_label: String,
		pitch_degrees: float,
		bank_degrees: float,
		heading_degrees: float,
		velocity_valid: bool,
		altitude_valid: bool,
		heading_valid: bool
) -> void:
	var speed_text: String = String.num(flight_velocity.length(), 1) if velocity_valid else "---.-"
	var altitude_text: String = String.num(local_altitude, 1) if altitude_valid else "----"
	var vertical_text: String = "%+.1f" % local_vertical_speed if velocity_valid else "---.-"
	var attitude_text: String = "%+.1f / %+.1f" % [pitch_degrees, bank_degrees] if bool(_telemetry.get("instrument_attitude_valid", false)) else "--- / ---"
	_draw_data_block(font, Vector2(278.0, 230.0), speed_label, speed_text, "m/s")
	_draw_data_block(font, Vector2(892.0, 230.0), "LOCAL ALT", altitude_text, "m")
	_draw_data_block(font, Vector2(278.0, 390.0), "VERT SPEED", vertical_text, "m/s")
	_draw_data_block(font, Vector2(892.0, 390.0), "ATTITUDE", attitude_text, "PITCH / BANK")
	var heading_text: String = "HDG %03d°" % (int(round(heading_degrees)) % 360) if heading_valid else "HDG ---"
	_draw_text(font, Vector2(570.0, 430.0), heading_text, 11, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 140.0)


func _draw_data_block(font: Font, origin: Vector2, title: String, value: String, unit: String) -> void:
	_draw_text(font, origin, title, 11, COLOR_SECONDARY)
	_draw_text(font, origin + Vector2(0.0, 25.0), value, 20, COLOR_PRIMARY)
	_draw_text(font, origin + Vector2(0.0, 41.0), unit, 8, COLOR_SECONDARY)


static func calculate_pitch_mark_offset_pixels(
		ship_pitch_degrees: float,
		pitch_mark_degrees: float,
		focal_pixels: float = WINDSHIELD_FOCAL_Y_PX
) -> float:
	return focal_pixels * tan(deg_to_rad(ship_pitch_degrees - pitch_mark_degrees))


func _draw_attitude_ladder(font: Font, pitch_degrees: float, bank_degrees: float) -> void:
	# The ladder is calibrated as a perspective projection onto the windshield
	# plane. The focal length is derived from the eye-to-glass distance and the
	# physical display height, rather than an arbitrary pixels-per-degree value.
	var center := Vector2(640.0, 360.0)
	var focal_pixels: float = WINDSHIELD_FOCAL_Y_PX
	var ladder_rotation: float = deg_to_rad(-bank_degrees)

	for mark in range(-40, 41, 5):
		var line_y: float = calculate_pitch_mark_offset_pixels(pitch_degrees, float(mark), focal_pixels)
		if absf(line_y) > PITCH_LADDER_LIMIT_PX:
			continue

		var is_major: bool = posmod(abs(mark), 10) == 0
		var is_horizon: bool = mark == 0
		var half_width: float = 148.0 if is_horizon else (112.0 if is_major else 58.0)
		var color: Color = COLOR_PRIMARY if is_horizon else COLOR_SECONDARY
		var local_start := Vector2(-half_width, line_y)
		var local_end := Vector2(half_width, line_y)
		var start_point: Vector2 = _rotate_point(local_start, center, ladder_rotation)
		var end_point: Vector2 = _rotate_point(local_end, center, ladder_rotation)

		# Positive pitch marks are solid; negative marks are broken, matching
		# the familiar fighter-HUD convention for climb/dive cues.
		if mark < 0 and not is_horizon:
			_draw_broken_line(start_point, end_point, color, 0.8, 8.0, 5.0)
		else:
			draw_line(start_point, end_point, color, 1.0 if is_horizon else (0.8 if is_major else 0.65))

		if is_major and not is_horizon:
			var label_text: String = str(abs(mark))
			var left_label: Vector2 = _rotate_point(Vector2(-half_width - 25.0, line_y + 4.0), center, ladder_rotation)
			var right_label: Vector2 = _rotate_point(Vector2(half_width + 8.0, line_y + 4.0), center, ladder_rotation)
			_draw_text(font, left_label, label_text, 10, COLOR_SECONDARY)
			_draw_text(font, right_label, label_text, 10, COLOR_SECONDARY)

	# Bank scale: fixed to the window, with the moving index showing measured bank.
	var bank_center := Vector2(640.0, 230.0)
	var bank_radius: float = 52.0
	for angle_degrees in range(-60, 61, 10):
		var angle_radians: float = deg_to_rad(-90.0 + float(angle_degrees))
		var direction := Vector2(cos(angle_radians), sin(angle_radians))
		var outer: Vector2 = bank_center + direction * bank_radius
		var inner: Vector2 = bank_center + direction * (bank_radius - (13.0 if posmod(angle_degrees, 30) == 0 else 7.0))
		draw_line(inner, outer, COLOR_SECONDARY, 0.7)
	var pointer_angle: float = deg_to_rad(-90.0 - clampf(bank_degrees, -60.0, 60.0))
	var pointer_direction := Vector2(cos(pointer_angle), sin(pointer_angle))
	var pointer_base := bank_center + pointer_direction * (bank_radius - 19.0)
	var pointer_tip := bank_center + pointer_direction * (bank_radius + 1.0)
	draw_line(pointer_base, pointer_tip, COLOR_PRIMARY, 1.5)

	# Fixed aircraft reference / boresight. Unlike the ladder, this does not move.
	draw_line(Vector2(573.0, center.y), Vector2(619.0, center.y), COLOR_PRIMARY, 1.6)
	draw_line(Vector2(661.0, center.y), Vector2(707.0, center.y), COLOR_PRIMARY, 1.6)
	draw_line(Vector2(619.0, center.y), Vector2(630.0, center.y + 7.0), COLOR_PRIMARY, 1.3)
	draw_line(Vector2(661.0, center.y), Vector2(650.0, center.y + 7.0), COLOR_PRIMARY, 1.3)
	draw_circle(center, 2.0, COLOR_PRIMARY)


func _draw_broken_line(
		start_point: Vector2,
		end_point: Vector2,
		color: Color,
		width: float,
		dash_length: float,
		gap_length: float
) -> void:
	var total_length: float = start_point.distance_to(end_point)
	if total_length <= 0.001:
		return
	var direction: Vector2 = (end_point - start_point) / total_length
	var cursor: float = 0.0
	while cursor < total_length:
		var segment_end: float = minf(cursor + dash_length, total_length)
		draw_line(start_point + direction * cursor, start_point + direction * segment_end, color, width)
		cursor = segment_end + gap_length


func _draw_flight_path_marker(velocity_world: Vector3, ship_basis: Basis) -> void:
	var center := Vector2(640.0, 360.0)
	var marker: Dictionary = calculate_flight_path_marker(velocity_world, ship_basis, center)
	if not bool(marker.get("visible", false)):
		return

	var point: Vector2 = marker.get("position", center)
	var wing_span: float = 10.0
	var tail_length: float = 6.0
	# Distinct cyan flight-path symbol; the fixed green aircraft reference remains
	# the nose/boresight. Their separation visualizes angle of attack and drift.
	draw_line(point + Vector2(-wing_span, 0.0), point + Vector2(-3.0, 0.0), COLOR_FLIGHT_PATH, 1.1)
	draw_line(point + Vector2(3.0, 0.0), point + Vector2(wing_span, 0.0), COLOR_FLIGHT_PATH, 1.1)
	draw_line(point + Vector2(0.0, -3.0), point + Vector2(0.0, -tail_length), COLOR_FLIGHT_PATH, 0.9)
	draw_arc(point, 3.0, 0.0, TAU, 20, COLOR_FLIGHT_PATH, 1.0)


func _draw_input_indicators(font: Font, pitch_input: float, roll_input: float, yaw_input: float) -> void:
	var square := Rect2(532.0, 558.0, 104.0, 104.0)
	var center: Vector2 = square.position + square.size * 0.5
	draw_rect(square, COLOR_SECONDARY, false, 0.8)
	draw_line(Vector2(center.x, square.position.y + 5.0), Vector2(center.x, square.end.y - 5.0), COLOR_DIM, 0.7)
	draw_line(Vector2(square.position.x + 5.0, center.y), Vector2(square.end.x - 5.0, center.y), COLOR_DIM, 0.7)
	draw_line(Vector2(square.position.x + 10.0, center.y), Vector2(square.end.x - 10.0, center.y), COLOR_SECONDARY, 1.0)
	draw_line(Vector2(center.x, square.position.y + 10.0), Vector2(center.x, square.end.y - 10.0), COLOR_SECONDARY, 1.0)
	var stick_position := Vector2(
		center.x + clampf(roll_input, -1.0, 1.0) * 48.0,
		center.y + clampf(pitch_input, -1.0, 1.0) * 48.0
	)
	draw_circle(stick_position, 5.0, COLOR_PRIMARY)
	draw_circle(stick_position, 8.0, COLOR_SECONDARY, false, 0.7)
	_draw_text(font, Vector2(516.0, 684.0), "PITCH / ROLL", 10, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 136.0)

	# Rudder command is a laterally moving, thick vertical marker.
	var rudder_axis_center_x: float = 730.0
	draw_line(Vector2(rudder_axis_center_x - 38.0, 608.0), Vector2(rudder_axis_center_x + 38.0, 608.0), COLOR_DIM, 0.7)
	var rudder_x: float = rudder_axis_center_x + clampf(yaw_input, -1.0, 1.0) * 36.0
	draw_line(Vector2(rudder_x, 566.0), Vector2(rudder_x, 652.0), COLOR_PRIMARY, 2.0)
	_draw_text(font, Vector2(680.0, 684.0), "RUDDER", 10, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 100.0)


func _draw_bottom_guidance(font: Font) -> void:
	_draw_text(
		font,
		Vector2(350.0, 711.0),
		"F FIELD   W/S THROTTLE   Q/E VECTOR   MOUSE P/R   A/D RUDDER   V FCC   C VIEW   RMB LOOK   F3 DEBUG   F10 DISPLAY",
		9,
		COLOR_DIM,
		HORIZONTAL_ALIGNMENT_CENTER,
		580.0
	)


func _rotate_point(local_point: Vector2, center: Vector2, angle_radians: float) -> Vector2:
	var cosine: float = cos(angle_radians)
	var sine: float = sin(angle_radians)
	return center + Vector2(
		local_point.x * cosine - local_point.y * sine,
		local_point.x * sine + local_point.y * cosine
	)


func _draw_text(
		font: Font,
		position: Vector2,
		text: String,
		font_size: int,
		color: Color,
		alignment: int = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1.0
) -> void:
	if font == null:
		return
	draw_string(font, position, text, alignment, width, font_size, color)
