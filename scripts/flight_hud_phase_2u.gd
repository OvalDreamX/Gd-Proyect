extends FlightHUD
class_name FlightHUDPhase2U

## Phase 2U presentation corrections for cargo-induced moments and bounded FCC trim.
## The base HUD still owns all layout, controls and rendering.

func set_cargo_system(system: Node) -> void:
	super.set_cargo_system(system)
	if is_instance_valid(system) and _cargo_mass_slider != null:
		var cargo_data: Dictionary = system.call("get_telemetry")
		_cargo_mass_slider.max_value = float(cargo_data.get("max_payload_kg", 25000.0))
		_cargo_mass_slider.value = minf(
			_cargo_mass_slider.value,
			_cargo_mass_slider.max_value
		)
		_update_cargo_labels()


func _update_cargo_labels() -> void:
	super._update_cargo_labels()
	if not is_instance_valid(_cargo_system) or _cargo_status_label == null:
		return

	var cargo_data: Dictionary = _cargo_system.call("get_telemetry")
	var total_kg: float = float(cargo_data.get("total_mass_kg", 30000.0))
	var max_gross_kg: float = float(cargo_data.get("max_gross_kg", 55000.0))
	var com: Vector3 = cargo_data.get("center_of_mass_m", Vector3.ZERO)
	var hover_percent: float = float(cargo_data.get("hover_throttle_estimate", 0.5)) * 100.0
	var preset: String = str(cargo_data.get("preset", "CUSTOM"))

	var load_note: String = "[ BALANCED LOAD ] Main-field resultant passes through the COM datum."
	if com.length_squared() > 0.0025:
		load_note = (
			"[ ASYMMETRIC LOAD ] The shifted COM changes the main-field force lever arm. "
			+ "FCC PI trim is bounded by available vane authority; residual rotation is possible."
		)

	var gross_fraction: float = total_kg / maxf(max_gross_kg, 1.0)
	_cargo_status_label.text = (
		"ACTIVE PRESET: %s\n"
		+ "TOTAL MASS: %.0f kg / %.0f kg (%.1f%% Gross Rating)\n"
		+ "COMBINED COM OFFSET: (X: %+.2f m, Y: %+.2f m, Z: %+.2f m)\n"
		+ "ESTIMATED 1g HOVER THROTTLE: %.1f%% (nominal rating only)\n\n%s"
	) % [
		preset, total_kg, max_gross_kg, gross_fraction * 100.0,
		com.x, com.y, com.z, hover_percent, load_note
	]


func _update_debug_text(telemetry: Dictionary) -> void:
	super._update_debug_text(telemetry)

	var integral_trim: Vector3 = telemetry.get("fcc_integral_trim_output_by_axis", Vector3.ZERO)
	var fcc_enabled: bool = bool(telemetry.get("fcc_assistance_enabled", true))
	var trim_active: bool = bool(telemetry.get("fcc_trim_active", false))
	var saturated: bool = bool(telemetry.get("fcc_any_axis_saturated", false))
	var com: Vector3 = telemetry.get("center_of_mass_m", Vector3.ZERO)

	var trim_status: String = "NO OFFSET / NO TRIM"
	if not fcc_enabled:
		trim_status = "DIRECT MODE — FCC TRIM DISABLED"
	elif saturated:
		trim_status = "OUTPUT SATURATED — RESIDUAL MOMENT POSSIBLE"
	elif trim_active:
		trim_status = "INTEGRAL TRIM COMMAND ACTIVE — BOUNDED"
	elif com.length_squared() > 0.0025:
		trim_status = "OFFSET COM — TRIM AVAILABLE, NOT CURRENTLY NEEDED"
	else:
		trim_status = "BALANCED — NO PERSISTENT TRIM REQUIRED"

	var corrected_text: String = _debug_text_label.text
	corrected_text = corrected_text.replace("FCC ACTIVE TRIM COMPENSATION", trim_status)
	corrected_text = corrected_text.replace("SYMMETRICAL / BALANCED", trim_status)
	_debug_text_label.text = corrected_text

	var trim_line: String = (
		"\n\n[ PHASE 2U FCC TRIM ]\n"
		+ "Trim status: %s\n"
		+ "Integral trim output P/R/Y: %+.3f / %+.3f / %+.3f\n"
		+ "Integral gain: %.3f | Per-axis trim limit: %.3f | Overall FCC output cap: %.3f\n"
		+ "Note: rate trim damps persistent moments; it does not command a return to level."
	) % [
		trim_status,
		integral_trim.x, integral_trim.z, integral_trim.y,
		float(telemetry.get("fcc_rate_integral_gain", 0.0)),
		float(telemetry.get("fcc_maximum_integral_trim_output", 0.0)),
		float(telemetry.get("fcc_maximum_control_output", 0.0))
	]
	_debug_text_label.text += trim_line
