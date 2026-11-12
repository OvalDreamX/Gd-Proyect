extends Node

## Persistent display preferences shared by the HUD and the main Window.
## Fullscreen modes use the current desktop mode; custom sizes apply to windowed mode.

const CONFIG_PATH := "user://display_settings.cfg"
const MODE_WINDOWED := "windowed"
const MODE_BORDERLESS := "borderless_fullscreen"
const MODE_EXCLUSIVE := "exclusive_fullscreen"
const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)
const MIN_WINDOW_SIZE := Vector2i(800, 450)
const DEFAULT_HUD_SCALE := 1.0
const MIN_HUD_SCALE := 0.8
const MAX_HUD_SCALE := 1.0

const WINDOWED_PRESETS: Array[Vector2i] = [
	Vector2i(800, 450),
	Vector2i(960, 540),
	Vector2i(1024, 576),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(1920, 1200),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
]

var _display_mode: String = MODE_WINDOWED
var _windowed_resolution: Vector2i = DEFAULT_WINDOW_SIZE
var _hud_scale: float = DEFAULT_HUD_SCALE


func _ready() -> void:
	_load_settings()
	call_deferred("_apply_current_settings")


func get_display_mode() -> String:
	return _display_mode


func get_windowed_resolution() -> Vector2i:
	return _windowed_resolution


func get_hud_scale() -> float:
	return _hud_scale


func get_desktop_resolution() -> Vector2i:
	var screen_index: int = DisplayServer.window_get_current_screen()
	var size: Vector2i = DisplayServer.screen_get_size(screen_index)
	if size.x <= 0 or size.y <= 0:
		return DEFAULT_WINDOW_SIZE
	return size


func get_windowed_resolution_options() -> Array[Vector2i]:
	var screen_index: int = DisplayServer.window_get_current_screen()
	var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_index)
	var available_size: Vector2i = usable_rect.size
	if available_size.x <= 0 or available_size.y <= 0:
		available_size = get_desktop_resolution()

	var options: Array[Vector2i] = []
	for preset: Vector2i in WINDOWED_PRESETS:
		if preset.x <= available_size.x and preset.y <= available_size.y:
			options.append(preset)

	if options.is_empty():
		# The project enforces MIN_WINDOW_SIZE. If the monitor is smaller than
		# that minimum, retain the minimum rather than offering an impossible size.
		options.append(MIN_WINDOW_SIZE)

	if not options.has(_windowed_resolution):
		var current_window_size: Vector2i = DisplayServer.window_get_size()
		if (
			current_window_size.x >= MIN_WINDOW_SIZE.x
			and current_window_size.y >= MIN_WINDOW_SIZE.y
			and current_window_size.x <= available_size.x
			and current_window_size.y <= available_size.y
		):
			options.append(current_window_size)
			options.sort_custom(_resolution_comes_first)
	return options


func apply_display_settings(mode: String, resolution: Vector2i, hud_scale: float) -> void:
	_display_mode = normalize_mode(mode)
	_hud_scale = normalize_hud_scale(hud_scale)
	_windowed_resolution = _sanitize_windowed_resolution(resolution)
	_apply_current_settings()
	_save_settings()


func _apply_current_settings() -> void:
	# Exit fullscreen first so that the borderless flag and window geometry
	# can be set predictably before selecting the requested mode.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_min_size(MIN_WINDOW_SIZE)

	match _display_mode:
		MODE_WINDOWED:
			DisplayServer.window_set_size(_windowed_resolution)
			var screen_index: int = DisplayServer.window_get_current_screen()
			var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_index)
			if usable_rect.size.x > 0 and usable_rect.size.y > 0:
				var centered_position: Vector2i = usable_rect.position + (usable_rect.size - _windowed_resolution) / 2
				DisplayServer.window_set_position(centered_position)
		MODE_BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		MODE_EXCLUSIVE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return

	_display_mode = normalize_mode(str(config.get_value("display", "mode", MODE_WINDOWED)))
	var saved_resolution: Variant = config.get_value("display", "windowed_resolution", DEFAULT_WINDOW_SIZE)
	if typeof(saved_resolution) == TYPE_VECTOR2I:
		_windowed_resolution = saved_resolution
	elif typeof(saved_resolution) == TYPE_VECTOR2:
		_windowed_resolution = Vector2i(roundi(saved_resolution.x), roundi(saved_resolution.y))
	else:
		_windowed_resolution = DEFAULT_WINDOW_SIZE
	_hud_scale = normalize_hud_scale(float(config.get_value("display", "hud_scale", DEFAULT_HUD_SCALE)))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "mode", _display_mode)
	config.set_value("display", "windowed_resolution", _windowed_resolution)
	config.set_value("display", "hud_scale", _hud_scale)
	var error: Error = config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Could not save display settings: %s" % error_string(error))


func _sanitize_windowed_resolution(requested: Vector2i) -> Vector2i:
	var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var available_size: Vector2i = usable_rect.size
	if available_size.x <= 0 or available_size.y <= 0:
		available_size = get_desktop_resolution()

	if (
		requested.x < MIN_WINDOW_SIZE.x or requested.y < MIN_WINDOW_SIZE.y
		or requested.x > available_size.x or requested.y > available_size.y
	):
		return best_fitting_windowed_resolution(available_size)
	return requested


func _resolution_comes_first(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


static func best_fitting_windowed_resolution(available_size: Vector2i) -> Vector2i:
	var best_fit: Vector2i = Vector2i.ZERO
	var best_area: int = -1
	for preset: Vector2i in WINDOWED_PRESETS:
		if preset.x <= available_size.x and preset.y <= available_size.y:
			var preset_area: int = preset.x * preset.y
			if preset_area > best_area:
				best_fit = preset
				best_area = preset_area
	# If no preset fits, preserve the explicit 800×450 minimum-window contract.
	return MIN_WINDOW_SIZE if best_fit == Vector2i.ZERO else best_fit


static func normalize_mode(value: String) -> String:
	if value == MODE_BORDERLESS or value == MODE_EXCLUSIVE:
		return value
	return MODE_WINDOWED


static func normalize_hud_scale(value: float) -> float:
	var snapped_scale: float = clampf(value, MIN_HUD_SCALE, MAX_HUD_SCALE)
	return snapped_scale


static func mode_label(value: String) -> String:
	match normalize_mode(value):
		MODE_BORDERLESS:
			return "Borderless Fullscreen"
		MODE_EXCLUSIVE:
			return "Exclusive Fullscreen"
	return "Windowed"


static func format_resolution(size: Vector2i) -> String:
	return "%d × %d" % [size.x, size.y]
