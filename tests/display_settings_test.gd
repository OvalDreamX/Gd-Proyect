extends SceneTree

## Pure preference-validation checks; this test does not change the OS window.
## Run from the project root with Godot 4.7.2:
## godot --headless --path . --script res://tests/display_settings_test.gd

const DISPLAY_SETTINGS_SCRIPT = preload("res://scripts/display_settings.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run_tests()


func _run_tests() -> void:
	_expect(
		DISPLAY_SETTINGS_SCRIPT.normalize_mode("windowed") == "windowed",
		"Windowed mode is accepted"
	)
	_expect(
		DISPLAY_SETTINGS_SCRIPT.normalize_mode("borderless_fullscreen") == "borderless_fullscreen",
		"Borderless fullscreen mode is accepted"
	)
	_expect(
		DISPLAY_SETTINGS_SCRIPT.normalize_mode("exclusive_fullscreen") == "exclusive_fullscreen",
		"Exclusive fullscreen mode is accepted"
	)
	_expect(
		DISPLAY_SETTINGS_SCRIPT.normalize_mode("invalid") == "windowed",
		"Unknown display modes safely fall back to windowed"
	)
	_expect(
		is_equal_approx(DISPLAY_SETTINGS_SCRIPT.normalize_hud_scale(0.5), 0.8),
		"HUD scale is clamped to the minimum supported size"
	)
	_expect(
		is_equal_approx(DISPLAY_SETTINGS_SCRIPT.normalize_hud_scale(1.2), 1.0),
		"HUD scale is clamped to the maximum supported size"
	)
	_expect(
		DISPLAY_SETTINGS_SCRIPT.format_resolution(Vector2i(1920, 1080)) == "1920 × 1080",
		"Resolution labels are formatted consistently"
	)
	_expect(
		DISPLAY_SETTINGS_SCRIPT.best_fitting_windowed_resolution(Vector2i(1024, 768)) == Vector2i(1024, 576),
		"Invalid saved resolution falls back to the largest supported preset that fits"
	)
	_expect(
		DISPLAY_SETTINGS_SCRIPT.best_fitting_windowed_resolution(Vector2i(640, 480)) == Vector2i(800, 450),
		"Displays below the minimum retain the explicit minimum-window constraint"
	)

	print("Display settings tests: %d checks, %d failures." % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % description)
	else:
		_failures += 1
		push_error("FAIL: %s" % description)
