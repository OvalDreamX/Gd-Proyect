extends CanvasLayer
class_name GroundEffectDiagnosticsOverlay

## Compact readout for the prototype's F3 diagnostics. It follows the existing
## ForceVectorDebug visibility flag and reads telemetry only; it never changes
## simulation state.

@export var repulsorlift_system_path: NodePath = NodePath("../RepulsorliftSystem")
@export var force_vector_debug_path: NodePath = NodePath("../ForceVectorDebug")
@export_range(0.05, 1.0, 0.05) var refresh_interval_seconds: float = 0.10

@onready var _repulsorlift_system: RepulsorliftSystem = get_node_or_null(repulsorlift_system_path) as RepulsorliftSystem
@onready var _force_vector_debug: ForceVectorDebug = get_node_or_null(force_vector_debug_path) as ForceVectorDebug

var _panel: PanelContainer
var _label: Label
var _refresh_elapsed: float = 0.0


func _ready() -> void:
	layer = 25
	_build_overlay()
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_panel):
		return
	var debug_visible: bool = is_instance_valid(_force_vector_debug) and _force_vector_debug.visible
	_panel.visible = debug_visible
	if not debug_visible or not is_instance_valid(_repulsorlift_system):
		return

	_refresh_elapsed += maxf(delta, 0.0)
	if _refresh_elapsed < maxf(refresh_interval_seconds, 0.05):
		return
	_refresh_elapsed = 0.0
	_label.text = _format_telemetry(_repulsorlift_system.get_telemetry())


func _build_overlay() -> void:
	_panel = PanelContainer.new()
	_panel.name = "GroundEffectReadout"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -418.0
	_panel.offset_top = 22.0
	_panel.offset_right = -22.0
	_panel.offset_bottom = 164.0
	_panel.custom_minimum_size = Vector2(396.0, 142.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.027, 0.038, 0.94)
	style.border_color = Color(1.0, 0.42, 0.12, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)

	_label = Label.new()
	_label.name = "GroundEffectTelemetry"
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.90, 1.0))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	add_child(_panel)


func _format_telemetry(telemetry: Dictionary) -> String:
	var configured: bool = bool(telemetry.get("ground_effect_enabled", false))
	var field_online: bool = bool(telemetry.get("lift_field_online", false))
	var valid_probes: int = int(telemetry.get("ground_effect_valid_probe_count", 0))
	var minimum_probes: int = int(telemetry.get("ground_effect_minimum_valid_probes", 3))
	var probe_names: Variant = telemetry.get("ground_effect_probe_anchor_names", [])
	var total_probes: int = probe_names.size() if probe_names is Array or probe_names is PackedStringArray else 0
	var clearance: float = float(telemetry.get("ground_effect_average_clearance_m", -1.0))
	var footprint: float = float(telemetry.get("ground_effect_footprint_width_m", 0.0))
	var proximity: float = float(telemetry.get("ground_effect_proximity", 0.0))
	var maximum_gain: float = float(telemetry.get("ground_effect_max_gain", 0.0))
	var multiplier: float = float(telemetry.get("ground_effect_multiplier", 1.0))
	var extra_force_n: float = float(telemetry.get("ground_effect_force_n", 0.0))
	var main_force: Vector3 = telemetry.get("lift_main_force_vector", Vector3.ZERO)
	var up_world: Vector3 = telemetry.get("ground_effect_up_world", Vector3.UP)
	if up_world.length_squared() > 0.000001:
		up_world = up_world.normalized()
	var main_upward_force_n: float = maxf(main_force.dot(up_world), 0.0)

	var status: String = "ACTIVE"
	if not configured:
		status = "DISABLED — JSON configuration not loaded"
	elif not field_online:
		status = "STANDBY — repulsorlift field offline"
	elif valid_probes < minimum_probes:
		status = "NO SURFACE — insufficient valid probe hits"
	elif clearance < 0.0:
		status = "NO SURFACE — no usable clearance sample"
	elif proximity <= 0.0:
		status = "OUT OF RANGE — above configured footprint"
	elif main_upward_force_n <= 0.001:
		status = "NO UPWARD MAIN FORCE — vector/power setting"
	elif extra_force_n <= 0.001:
		status = "NO ADDITIONAL FORCE — inspect configuration"

	var clearance_text: String = "NO HIT" if clearance < 0.0 else "%.3f m" % clearance
	var errors_text: String = str(telemetry.get("ground_effect_definition_errors", PackedStringArray()))
	var lines := PackedStringArray()
	lines.append("REPULSORLIFT GROUND EFFECT — %s" % status)
	lines.append("Probes: %d / %d valid (minimum %d) | Clearance: %s / %.2f m" % [valid_probes, total_probes, minimum_probes, clearance_text, footprint])
	lines.append("Proximity: %.3f | Max gain: %.1f%% | Current multiplier: %.3fx" % [proximity, maximum_gain * 100.0, multiplier])
	lines.append("Upward main force: %.1f kN | Additional force: %.1f kN" % [main_upward_force_n / 1000.0, extra_force_n / 1000.0])	
	if not errors_text.is_empty() and errors_text != "[]":
		lines.append("Definition errors: " + errors_text)
	return "\n".join(lines)
