extends Node

## Deterministic simulation clock autoload for Phase 3F/3I travel and celestial propagation.
## Preserves discrete jump time in get_time_seconds() for fixed-route tests while accumulating
## continuous real-time elapsed seconds for live solar-system rotation and orbital motion.

signal time_advanced(new_time_seconds: float, delta_seconds: float, jump_count: int)

var _current_time_seconds: float = 0.0
var _realtime_elapsed_seconds: float = 0.0
var _realtime_enabled: bool = true
var _time_scale: float = 1.0
var _jump_count: int = 0


func _process(delta: float) -> void:
	if _realtime_enabled and _time_scale > 0.0 and delta > 0.0:
		_realtime_elapsed_seconds += delta * _time_scale


func get_time_seconds() -> float:
	return _current_time_seconds


func get_realtime_elapsed_seconds() -> float:
	return _realtime_elapsed_seconds


func get_total_celestial_time_seconds() -> float:
	return _current_time_seconds + _realtime_elapsed_seconds


func set_realtime_enabled(enabled: bool) -> void:
	_realtime_enabled = enabled


func is_realtime_enabled() -> bool:
	return _realtime_enabled


func set_time_scale(scale: float) -> void:
	_time_scale = maxf(scale, 0.0)


func get_time_scale() -> float:
	return _time_scale


func advance_realtime(delta_seconds: float) -> float:
	if delta_seconds > 0.0:
		_realtime_elapsed_seconds += delta_seconds * maxf(_time_scale, 0.0)
	return get_total_celestial_time_seconds()


func get_jump_count() -> int:
	return _jump_count


func advance_time(duration_seconds: float) -> float:
	if duration_seconds <= 0.0:
		return _current_time_seconds
	_current_time_seconds += duration_seconds
	_jump_count += 1
	time_advanced.emit(_current_time_seconds, duration_seconds, _jump_count)
	return _current_time_seconds


func reset_clock(initial_time_seconds: float = 0.0) -> void:
	_current_time_seconds = maxf(initial_time_seconds, 0.0)
	_realtime_elapsed_seconds = 0.0
	_jump_count = 0


func get_formatted_clock() -> String:
	return _format_seconds(_current_time_seconds)


func get_formatted_celestial_clock() -> String:
	return _format_seconds(get_total_celestial_time_seconds())


func get_body_orbital_angle_radians(angular_speed_rad_s: float, epoch_angle_rad: float = 0.0) -> float:
	return fposmod(epoch_angle_rad + angular_speed_rad_s * _current_time_seconds, TAU)


static func _format_seconds(raw_seconds: float) -> String:
	var total_sec: int = int(floor(maxf(raw_seconds, 0.0)))
	var hours: int = total_sec / 3600
	var minutes: int = (total_sec % 3600) / 60
	var seconds: int = total_sec % 60
	return "T+%02d:%02d:%02d" % [hours, minutes, seconds]
