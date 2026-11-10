extends Control
class_name FlightHUDOverlay

## Cockpit-only primary flight display. This script is presentation-only:
## it reads telemetry snapshots and never changes ship input or physics.

const COLOR_PRIMARY := Color(0.50, 1.00, 0.78, 0.92)
const COLOR_SECONDARY := Color(0.29, 0.69, 0.56, 0.76)
const COLOR_DIM := Color(0.20, 0.46, 0.39, 0.60)
const COLOR_COMMAND := Color(1.00, 0.77, 0.36, 0.96)
const COLOR_WARNING := Color(1.00, 0.48, 0.30, 0.96)
const BASE_WIDTH: float = 1280.0
const BASE_HEIGHT: float = 720.0

var _telemetry: Dictionary = {}


func update_telemetry(telemetry: Dictionary) -> void:
	_telemetry = telemetry.duplicate(false)
	queue_redraw()


func _draw() -> void:
	if _telemetry.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return

	var fit_scale: float = minf(size.x / BASE_WIDTH, size.y / BASE_HEIGHT)
	var ui_scale: float = 1.0
	var display_settings: Node = get_node_or_null("/root/DisplaySettings")
	if display_settings != null and display_settings.has_method("get_hud_scale"):
		ui_scale = float(display_settings.call("get_hud_scale"))
	var scale_factor: float = fit_scale * clampf(ui_scale, 0.8, 1.0)
	var logical_size: Vector2 = size / maxf(scale_factor, 0.001)
	var extra_space: Vector2 = logical_size - Vector2(BASE_WIDTH, BASE_HEIGHT)
	var draw_offset := extra_space * 0.5
	draw_set_transform(draw_offset, 0.0, Vector2.ONE * scale_factor)

	var font: Font = ThemeDB.fallback_font
	var basis: Basis = _telemetry.get("ship_global_basis", Basis.IDENTITY)
	basis = basis.orthonormalized()
	var position: Vector3 = _telemetry.get("ship_position", Vector3.ZERO)
	var velocity: Vector3 = _telemetry.get("ship_linear_velocity", Vector3.ZERO)
	var pitch_input: float = float(_telemetry.get("pitch_command", 0.0))
	var roll_input: float = float(_telemetry.get("roll_command", 0.0))
	var yaw_input: float = float(_telemetry.get("yaw_command", 0.0))
	var field_state: String = str(_telemetry.get("field_state", "OFF"))
	var assistance_enabled: bool = bool(_telemetry.get("fcc_assistance_enabled", true))

	var forward: Vector3 = -basis.z.normalized()
	var pitch_degrees: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	var roll_degrees: float = rad_to_deg(atan2(basis.x.y, basis.y.y))
	var heading_degrees: float = fposmod(
		rad_to_deg(atan2(-forward.x, -forward.z)),
		360.0
	)

	var left_gauge_x: float = 88.0 - extra_space.x * 0.5
	var right_gauge_x: float = 1178.0 + extra_space.x * 0.5
	_draw_side_gauge(
		font, left_gauge_x, "FIELD POWER", "OUTPUT",
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
	_draw_flight_data(font, velocity, position, pitch_degrees, roll_degrees, heading_degrees)
	_draw_attitude_ladder(font, pitch_degrees, roll_degrees)
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
	var bar_width: float = 12.0
	var actual_fraction: float = clampf(actual_value / maxf(maximum_value, 0.001), 0.0, 1.0)
	var command_fraction: float = clampf(command_value / maxf(maximum_value, 0.001), 0.0, 1.0)
	var actual_y: float = bottom - actual_fraction * height
	var command_y: float = bottom - command_fraction * height
	var bar_rect := Rect2(center_x - bar_width * 0.5, top, bar_width, height)

	_draw_text(font, Vector2(center_x - 64.0, 132.0), gauge_name, 13, COLOR_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER, 128.0)
	_draw_text(font, Vector2(center_x - 64.0, 151.0), gauge_subtitle, 10, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 128.0)
	_draw_text(
		font,
		Vector2(center_x - 66.0, 177.0),
		"ACT %s%s" % [String.num(actual_value, 1), unit],
		12,
		COLOR_PRIMARY,
		HORIZONTAL_ALIGNMENT_CENTER,
		132.0
	)

	draw_rect(bar_rect, COLOR_DIM, false, 1.4)
	for tick_index in range(0, 5):
		var tick_fraction: float = float(tick_index) / 4.0
		var tick_y: float = bottom - tick_fraction * height
		draw_line(Vector2(center_x + 9.0, tick_y), Vector2(center_x + 17.0, tick_y), COLOR_DIM, 1.0)
		if gauge_name == "FIELD POWER":
			_draw_text(font, Vector2(center_x + 20.0, tick_y + 4.0), str(tick_index * 25), 9, COLOR_DIM)
		else:
			_draw_text(font, Vector2(center_x + 20.0, tick_y + 4.0), str(tick_index * 110 / 4), 9, COLOR_DIM)

	if actual_fraction > 0.001:
		draw_rect(
			Rect2(center_x - 3.0, actual_y, 6.0, bottom - actual_y),
			COLOR_PRIMARY,
			true
		)
		draw_line(Vector2(center_x - 9.0, actual_y), Vector2(center_x + 9.0, actual_y), COLOR_PRIMARY, 2.0)

	# The pilot command is an independent amber tick. The filled output bar
	# follows the actuator value and therefore visibly lags the command.
	draw_line(Vector2(center_x - 19.0, command_y), Vector2(center_x + 21.0, command_y), COLOR_COMMAND, 2.0)
	draw_line(Vector2(center_x - 19.0, command_y - 4.0), Vector2(center_x - 19.0, command_y + 4.0), COLOR_COMMAND, 1.5)
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
	_draw_text(font, Vector2(440.0, 82.0), "REPULSORLIFT  //  %s" % field_state, 15, state_color, HORIZONTAL_ALIGNMENT_CENTER, 400.0)
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
	draw_line(corners[0], corners[0] + Vector2(arm, 0), frame_color, 1.0)
	draw_line(corners[0], corners[0] + Vector2(0, arm), frame_color, 1.0)
	draw_line(corners[1], corners[1] - Vector2(arm, 0), frame_color, 1.0)
	draw_line(corners[1], corners[1] + Vector2(0, arm), frame_color, 1.0)
	draw_line(corners[2], corners[2] + Vector2(arm, 0), frame_color, 1.0)
	draw_line(corners[2], corners[2] - Vector2(0, arm), frame_color, 1.0)
	draw_line(corners[3], corners[3] - Vector2(arm, 0), frame_color, 1.0)
	draw_line(corners[3], corners[3] - Vector2(0, arm), frame_color, 1.0)


func _draw_heading_tape(font: Font, heading_degrees: float) -> void:
	var center_x: float = 640.0
	var y: float = 151.0
	var half_width: float = 205.0
	draw_line(Vector2(center_x - half_width, y), Vector2(center_x + half_width, y), COLOR_DIM, 1.0)
	for offset in range(-60, 61, 5):
		var tick_x: float = center_x + float(offset) * 3.1
		var tick_height: float = 13.0 if posmod(offset, 10) == 0 else 6.0
		draw_line(Vector2(tick_x, y), Vector2(tick_x, y + tick_height), COLOR_SECONDARY, 1.0)
		if posmod(offset, 10) == 0:
			var label_heading: int = int(round(fposmod(heading_degrees + float(offset), 360.0)))
			_draw_text(font, Vector2(tick_x - 16.0, y - 8.0), "%03d" % label_heading, 9, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 32.0)
	draw_line(Vector2(center_x, y - 6.0), Vector2(center_x, y + 17.0), COLOR_PRIMARY, 2.0)
	_draw_text(font, Vector2(center_x - 42.0, 176.0), "%03d°" % int(round(heading_degrees)), 14, COLOR_PRIMARY, HORIZONTAL_ALIGNMENT_CENTER, 84.0)


func _draw_flight_data(
		font: Font,
		velocity: Vector3,
		position: Vector3,
		pitch_degrees: float,
		roll_degrees: float,
		heading_degrees: float
) -> void:
	var speed: float = velocity.length()
	var vertical_speed: float = velocity.y
	_draw_data_block(font, Vector2(278.0, 230.0), "SPEED", String.num(speed, 1), "m/s")
	_draw_data_block(font, Vector2(892.0, 230.0), "LOCAL ALT", String.num(position.y, 1), "m")
	_draw_data_block(font, Vector2(278.0, 466.0), "VERT SPEED", "%+.1f" % vertical_speed, "m/s")
	_draw_data_block(font, Vector2(892.0, 466.0), "ATTITUDE", "%+.1f / %+.1f" % [pitch_degrees, roll_degrees], "PITCH / BANK")
	_draw_text(font, Vector2(570.0, 493.0), "HDG %03d°" % int(round(heading_degrees)), 11, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 140.0)


func _draw_data_block(font: Font, origin: Vector2, title: String, value: String, unit: String) -> void:
	_draw_text(font, origin, title, 11, COLOR_SECONDARY)
	_draw_text(font, origin + Vector2(0.0, 29.0), value, 24, COLOR_PRIMARY)
	_draw_text(font, origin + Vector2(0.0, 47.0), unit, 9, COLOR_SECONDARY)


func _draw_attitude_ladder(font: Font, pitch_degrees: float, roll_degrees: float) -> void:
	var center := Vector2(640.0, 348.0)
	var half_width: float = 168.0
	var pitch_scale: float = 3.2
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
		draw_line(_rotate_point(local_start, center, roll_radians), _rotate_point(local_end, center, roll_radians), line_color, 1.3 if long_mark else 0.8)
		if long_mark and mark != 0:
			var label_text: String = "%+d" % mark
			var left_label_point := _rotate_point(Vector2(-line_half_width - 36.0, line_y + 4.0), center, roll_radians)
			var right_label_point := _rotate_point(Vector2(line_half_width + 9.0, line_y + 4.0), center, roll_radians)
			_draw_text(font, left_label_point, label_text, 10, COLOR_SECONDARY)
			_draw_text(font, right_label_point, label_text, 10, COLOR_SECONDARY)
	draw_rect(Rect2(408.0, 236.0, 464.0, 224.0), COLOR_DIM, false, 1.0)

	# Fixed aircraft reference: two wings and a central aiming mark.
	draw_line(Vector2(573.0, center.y), Vector2(619.0, center.y), COLOR_PRIMARY, 2.6)
	draw_line(Vector2(661.0, center.y), Vector2(707.0, center.y), COLOR_PRIMARY, 2.6)
	draw_line(Vector2(619.0, center.y), Vector2(630.0, center.y + 7.0), COLOR_PRIMARY, 2.0)
	draw_line(Vector2(661.0, center.y), Vector2(650.0, center.y + 7.0), COLOR_PRIMARY, 2.0)
	draw_circle(center, 3.0, COLOR_PRIMARY)
	# Bank reference ticks above the ladder.
	draw_arc(Vector2(640.0, 242.0), 42.0, PI * 1.18, PI * 1.82, 32, COLOR_DIM, 1.0)
	draw_line(Vector2(640.0, 194.0), Vector2(640.0, 205.0), COLOR_PRIMARY, 1.5)
	_draw_text(font, Vector2(585.0, 220.0), "BANK", 9, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 110.0)


func _draw_input_indicators(font: Font, pitch_input: float, roll_input: float, yaw_input: float) -> void:
	var square := Rect2(526.0, 550.0, 116.0, 116.0)
	var center: Vector2 = square.position + square.size * 0.5
	draw_rect(square, COLOR_SECONDARY, false, 1.2)
	draw_line(Vector2(center.x, square.position.y + 5.0), Vector2(center.x, square.end.y - 5.0), COLOR_DIM, 1.0)
	draw_line(Vector2(square.position.x + 5.0, center.y), Vector2(square.end.x - 5.0, center.y), COLOR_DIM, 1.0)
	draw_line(Vector2(square.position.x + 10.0, center.y), Vector2(square.end.x - 10.0, center.y), COLOR_SECONDARY, 1.6)
	draw_line(Vector2(center.x, square.position.y + 10.0), Vector2(center.x, square.end.y - 10.0), COLOR_SECONDARY, 1.6)
	var stick_position := Vector2(
		center.x + clampf(roll_input, -1.0, 1.0) * 48.0,
		center.y + clampf(pitch_input, -1.0, 1.0) * 48.0
	)
	draw_circle(stick_position, 7.0, COLOR_PRIMARY)
	draw_circle(stick_position, 11.0, COLOR_SECONDARY, false, 1.0)
	_draw_text(font, Vector2(516.0, 684.0), "PITCH / ROLL", 10, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 136.0)

	# Rudder command is a laterally moving, thick vertical marker.
	var rudder_axis_center_x: float = 730.0
	draw_line(Vector2(rudder_axis_center_x - 42.0, 608.0), Vector2(rudder_axis_center_x + 42.0, 608.0), COLOR_DIM, 1.0)
	var rudder_x: float = rudder_axis_center_x + clampf(yaw_input, -1.0, 1.0) * 36.0
	draw_line(Vector2(rudder_x, 558.0), Vector2(rudder_x, 660.0), COLOR_PRIMARY, 4.0)
	_draw_text(font, Vector2(680.0, 684.0), "RUDDER", 10, COLOR_SECONDARY, HORIZONTAL_ALIGNMENT_CENTER, 100.0)


func _draw_bottom_guidance(font: Font) -> void:
	_draw_text(
		font,
		Vector2(350.0, 711.0),
		"F FIELD   W/S POWER   Q/E VECTOR   MOUSE P/R   A/D RUDDER   V FCC   C VIEW   RMB LOOK   F3 DEBUG   F10 DISPLAY",
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
