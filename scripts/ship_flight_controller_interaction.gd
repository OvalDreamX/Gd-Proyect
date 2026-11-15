extends "res://scripts/ship_flight_controller.gd"

## Narrow public bridge for data-authored cockpit controls. Flight physics and
## all normal keyboard/mouse input remain in ShipFlightController.

const INTERACTION_VECTOR_MIN_DEGREES: float = 0.0
const INTERACTION_VECTOR_MAX_DEGREES: float = 110.0


## Executes only the small, explicit control allowlist below. The model cannot
## request arbitrary methods or scripts; unknown IDs are rejected.
func request_cockpit_control(control_id: StringName, normalized_value: float = 1.0) -> bool:
	if not _cockpit_interaction_is_available() or not is_finite(normalized_value):
		return false

	match String(control_id):
		"switch_main_power":
			# In the current prototype, this maps to the existing repulsorlift
			# field on/off command. A separate ship electrical bus does not exist.
			_toggle_field_state()
			return true
		"switch_field_assist":
			if not is_instance_valid(_fcc):
				return false
			_fcc.set_assistance_enabled(not _fcc.assistance_enabled)
			_update_fcc_snapshot(_field_state == FieldState.ONLINE and not _ship.freeze)
			_publish_telemetry()
			return true
		"lever_throttle":
			if _field_state != FieldState.ONLINE:
				return false
			_field_power_command = clampf(normalized_value, 0.0, 1.0)
			_require_neutral_controls = false
			_publish_telemetry()
			return true
		"lever_vector_angle":
			if _field_state != FieldState.ONLINE:
				return false
			var value: float = clampf(normalized_value, 0.0, 1.0)
			_vector_distribution_degrees = lerpf(
				INTERACTION_VECTOR_MIN_DEGREES,
				INTERACTION_VECTOR_MAX_DEGREES,
				value
			)
			_require_neutral_controls = false
			_publish_telemetry()
			return true
		_:
			# E.g. button_landing_lights is structurally valid but remains
			# unbound until the project has a landing-light subsystem.
			return false


func _cockpit_interaction_is_available() -> bool:
	if not is_instance_valid(_ship) or not _ship.is_pilot_ready():
		return false
	if is_instance_valid(_hud):
		if _hud.is_cargo_manifest_open() or _hud.is_display_settings_open():
			return false
	return true
