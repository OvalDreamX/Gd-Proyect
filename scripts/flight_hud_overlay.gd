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
const FLIGHT_PATH_PIXELS_PER_DEGREE: float = 4.0
const FLIGHT_PATH_MAX_ANGLE_DEGREES: float = 23.0
const BASE_WIDTH: float = 1280.0
const BASE_HEIGHT: float = 720.0

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
		view_basis: Basis,
		hud_center: Vector2,
		pixels_per_degree: float = FLIGHT_PATH_PIXELS_PER_DEGREE,
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

	var local_velocity: Vector3 = view_basis.orthonormalized().inverse() * velocity_world
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
		clipped_lateral * pixels_per_degree,
		-clipped_vertical * pixels_per_degree
	)
	result["lateral_angle_degrees"] = lateral_angle
	result["vertical_angle_degrees"] = vertical_angle
	result["clipped"] = not is_equal_approx(lateral_angle, clipped_lateral) or not is_equal_approx(vertical_angle, clipped_vertical)
	return result


func _draw() -> void:
	if _telemetry.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return

	var fit_scale: float = minf(size.x / BASE_WIDTH, size.y / BASE_HEIGHT)
	var ui_scale: float = 1.0
	var display_settings: Node = get_node_or_null("/root/DisplaySettings")
	if display_settings != null and display_settings.has_method("get_hud_scale"):
		ui_scale = float(display_settings.call("get_hud_scale"))
	var scale_factor: float = fit_scale * clampf(ui_scale, 0.8, 1.0) * HUD_CONTENT_SCALE
	var logical_size: Vector2 = size / maxf(scale_factor, 0.001)
	var extra_space: Vector2 = logical_size - Vector2(BASE_WIDTH, BASE_HEIGHT)
	var draw_offset := extra_space * 0.5
	draw_set_transform(draw_offset, 0.0, Vector2.ONE * scale_factor)

	var font: Font = ThemeDB.fallback_font
	var basis: Basis = _telemetry.get("ship_global_basis", Basis.IDENTITY)
	basis = basis.orthonormalized()
	var view_basis: Basis = _telemetry.get("view_camera_global_basis", basis)
	view_basis = view_basis.orthonormalized()
	var position: Vector3 = _telemetry.get("ship_position", Vector3.ZERO)
	var velocity: Vector3 = _telemetry.get("ship_linear_velocity", Vector3.ZERO)
	var local_up_world: Vector3 = _telemetry.get("atmosphere_up_world", Vector3.UP)
	if local_up_world.length_squared() <= 0.000001:
		local_up_world = Vector3.UP
	else:
		local_up_world = local_up_world.normalized()
	var local_altitude: float = float(_telemetry.get("atmosphere_altitude_m", (position).dot(local_up_world)))
	var local_vertical_speed: float = velocity.dot(local_up_world)
	var atmosphere_enabled: bool = bool(_telemetry.get("atmosphere_enabled", false))
	var atmosphere_density: float = float(_telemetry.get("atmosphere_density_kg_m3", 0.0))
	var flight_path_velocity: Vector3 = velocity
	var speed_label: String = "SPEED"
	if atmosphere_enabled and atmosphere_density > 0.00001:
		flight_path_velocity = _telemetry.get("atmosphere_relative_velocity_world", velocity)
		speed_label = "AIRSPEED"
	var pitch_input: float = float(_telemetry.get("pitch_command", 0.0))
	var roll_input: float = float(_telemetry.get("roll_command", 0.0))
	var yaw_input: float = float(_telemetry.get("yaw_command", 0.0))
	var field_state: String = str(_telemetry.get("field_state", "OFF"))
	var assistance_enabled: bool = bool(_telemetry.get("fcc_assistance_enabled", true))

	var forward: Vector3 = -basis.z.normalized()
	var pitch_degrees: float = rad_to_deg(asin(clampf(forward.dot(local_up_world), -1.0, 1.0)))
	var roll_degrees: float = rad_to_deg(atan2(basis.x.dot(local_up_world), basis.y.dot(local_up_world)))
	var heading_degrees: float = fposmod(
		rad_to_deg(atan2(-forward.x, -forward.z)),
		360.0
	)

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

	_draw_top_status(font, field_state, assistance_enabled)
	_draw_heading_tape(font, heading_degrees)
	_draw_flight_data(font, flight_path_velocity, local_altitude, local_vertical_speed, speed_label, pitch_degrees, roll_degrees, heading_degrees)
	_draw_attitude_ladder(font, view_basis, local_up_world)
	_draw_flight_path_marker(flight_path_velocity, view_basis)
	_draw_input_indicators(font, pitch_input, roll_input, yaw_input)
	_draw_bottom_guidance(font)

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
	var half_width: float = 205.0
	draw_line(Vector2(center_x - half_width, y), Vector2(center_x + half_width, y), COLOR_DIM, 0.7)
	for offset in range(-60, 61, 5):
		var tick_x: float = center_x + float(offset) * 3.1
		var tick_height: float = 13.0 if posmod(offset, 10) == 0 else 6.0
		draw_line(Vector2(tick_x, y), Vector2(tick_x, y + tick_height), COLOR_SECONDARY, 0.7)
		if posmod(offset, 10) == 0:
			var label_heading: int = int(round(fposmod(heading_degrees + float(offset), 360.0)))
			_draw_text(font, Vector2(tick_x - 16.0, y - 8.0), "%03d" % label_heading, 9, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 32.0)
	draw_line(Vector2(center_x, y - 6.0), Vector2(center_x, y + 17.0), COLOR_PRIMARY, 1.3)
	_draw_text(font, Vector2(center_x - 42.0, 176.0), "%03d°" % int(round(heading_degrees)), 12, COLOR_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER, 84.0)


func _draw_flight_data(
		font: Font,
		flight_velocity: Vector3,
		local_altitude: float,
		local_vertical_speed: float,
		speed_label: String,
		pitch_degrees: float,
		roll_degrees: float,
		heading_degrees: float
) -> void:
	var speed: float = flight_velocity.length()
	_draw_data_block(font, Vector2(278.0, 230.0), speed_label, String.num(speed, 1), "m/s")
	_draw_data_block(font, Vector2(892.0, 230.0), "LOCAL ALT", String.num(local_altitude, 1), "m")
	_draw_data_block(font, Vector2(278.0, 466.0), "VERT SPEED", "%+.1f" % local_vertical_speed, "m/s")
	_draw_data_block(font, Vector2(892.0, 466.0), "ATTITUDE", "%+.1f / %+.1f" % [pitch_degrees, roll_degrees], "PITCH / BANK")
	_draw_text(font, Vector2(570.0, 493.0), "HDG %03d°" % int(round(heading_degrees)), 11, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 140.0)


func _draw_data_block(font: Font, origin: Vector2, title: String, value: String, unit: String) -> void:
	_draw_text(font, origin, title, 11, COLOR_SECONDARY)
	_draw_text(font, origin + Vector2(0.0, 25.0), value, 20, COLOR_PRIMARY)
	_draw_text(font, origin + Vector2(0.0, 41.0), unit, 8, COLOR_SECONDARY)


func _draw_attitude_ladder(font: Font, view_basis: Basis, local_up_world: Vector3) -> void:
	# The HUD stays fixed to the screen. Its moving ladder is projected from the
	# active camera against local world-up, so head-look does not detach cues
	# from the visible horizon. The fixed aircraft reference remains at screen center.
	var view_forward: Vector3 = -view_basis.z.normalized()
	var pitch_degrees: float = rad_to_deg(asin(clampf(view_forward.dot(local_up_world), -1.0, 1.0)))
	var roll_degrees: float = rad_to_deg(atan2(view_basis.x.dot(local_up_world), view_basis.y.dot(local_up_world)))
	var center := Vector2(640.0, 348.0)
	var half_width: float = 148.0
	var pitch_scale: float = 2.8
	var clipped_pitch: float = clampf(pitch_degrees, -40.0, 40.0)

	# Draw the pitch ladder in a ship-relative frame. Rotate its endpoints
	# mathematically so the HUD's overall viewport scaling/offset remains intact.
	var roll_radians: float = deg_to_rad(roll_degrees)
	for mark in range(-30, 31, 5):
		var line_y: float = (clipped_pitch - float(mark)) * pitch_scale
		if absf(line_y) > 118.0:
			continue
		var long_mark: bool = posmod(mark, 10) == 0
		var line_half_width: float = half_width if long_mark else half_width * 0.48
		var line_color: Color = COLOR_PRIMARY if mark == 0 else COLOR_SECONDARY
		var local_start := Vector2(-line_half_width, line_y)
		var local_end := Vector2(line_half_width, line_y)
		draw_line(_rotate_point(local_start, center, roll_radians), _rotate_point(local_end, center, roll_radians), line_color, 0.9 if long_mark else 0.6)
		if long_mark and mark != 0:
			var label_text: String = "%+d" % mark
			var left_label_point := _rotate_point(Vector2(-line_half_width - 36.0, line_y + 4.0), center, roll_radians)
			var right_label_point := _rotate_point(Vector2(line_half_width + 9.0, line_y + 4.0), center, roll_radians)
			_draw_text(font, left_label_point, label_text, 10, COLOR_SECONDARY)
			_draw_text(font, right_label_point, label_text, 10, COLOR_SECONDARY)
	draw_rect(Rect2(408.0, 236.0, 464.0, 224.0), COLOR_DIM, false, 0.7)

	# Fixed aircraft reference: two wings and a central aiming mark.
	draw_line(Vector2(573.0, center.y), Vector2(619.0, center.y), COLOR_PRIMARY, 1.6)
	draw_line(Vector2(661.0, center.y), Vector2(707.0, center.y), COLOR_PRIMARY, 1.6)
	draw_line(Vector2(619.0, center.y), Vector2(630.0, center.y + 7.0), COLOR_PRIMARY, 1.3)
	draw_line(Vector2(661.0, center.y), Vector2(650.0, center.y + 7.0), COLOR_PRIMARY, 1.3)
	draw_circle(center, 2.0, COLOR_PRIMARY)
	# Bank reference ticks above the ladder.
	draw_arc(Vector2(640.0, 242.0), 42.0, PI * 1.18, PI * 1.82, 32, COLOR_DIM, 0.7)
	draw_line(Vector2(640.0, 194.0), Vector2(640.0, 205.0), COLOR_PRIMARY, 1.0)
	_draw_text(font, Vector2(585.0, 220.0), "BANK", 9, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 110.0)


func _draw_flight_path_marker(velocity_world: Vector3, ship_basis: Basis) -> void:
	var center := Vector2(640.0, 348.0)
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
