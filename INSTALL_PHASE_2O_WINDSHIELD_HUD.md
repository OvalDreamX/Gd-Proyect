# Phase 2O — Fixed Windshield HUD and Flight Sensor Bus

## Install

Extract the Phase 2O overwrite ZIP into the project root (the directory containing `project.godot`) and overwrite the listed files.

## What changed

- The central flight symbology is rendered by a transparent `SubViewport` and mapped to a non-billboarded 3D quad attached to the ship at the forward windshield. It is fixed to the ship/cockpit, not the camera. Turning the camera therefore makes the symbology move out of view naturally.
- The 2D side gauges and the pitch/roll stick plus rudder viewer remain in the original screen-fixed CanvasLayer.
- The central attitude ladder uses a tangent/perspective angular projection calibrated from the eye-to-windshield distance and windshield dimensions. Positive pitch marks are solid, negative pitch marks are broken; bank is shown by the moving index on a fixed scale.
- Compass heading is calculated from the ship's forward vector projected onto the local horizontal plane. It is clockwise from north (N=000, E=090, S=180, W=270), so pitch no longer contaminates heading.
- The new `FlightSensorSuite` on the ship is the instrument-data boundary. It converts ship and atmosphere state into AHRS, compass, velocity, and altitude readings, each with an independent validity flag. The HUD renderer consumes this packet rather than reading rigid-body or atmosphere-model state directly.
- `FlightSensorSuite.set_channel_available()` can invalidate an individual sensor channel. Future gyro bias/drift, compass error, latency, and sensor failures should be implemented in this layer, not in the HUD drawing code.
- The atmospheric drag, wind, and glide-lift equations are not changed.

## Tests

Run these from PowerShell in the project root with the Godot 4.7.2 executable:

```powershell
& .\godot.exe --headless --path . --script res://tests/flight_sensor_suite_test.gd
& .\godot.exe --headless --path . --script res://tests/flight_path_marker_test.gd
& .\godot.exe --headless --path . --script res://tests/flight_hud_layout_test.gd
& .\godot.exe --headless --path . --script res://tests/flight_force_control_test.gd
& .\godot.exe --headless --path . --script res://tests/flight_control_computer_test.gd
& .\godot.exe --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& .\godot.exe --headless --path . --script res://tests/display_settings_test.gd
& .\godot.exe --headless --path . --script res://tests/test_range_environment_test.gd
```

## Manual flight checks

1. Enter the cockpit and look straight ahead. Confirm the central symbology appears on the forward window while the two side gauges and controls viewer remain screen-fixed.
2. Hold RMB and look left/right/up/down. The central HUD must remain on the windshield and slide out of the camera view; it must not follow the camera.
3. Return the camera to neutral and rotate the ship through north/east/south/west. The heading tape must read 000/090/180/270 respectively, including while pitching up or down.
4. Compare the pitch ladder against known attitudes (0°, +10°, -10°, +20°). The matching degree line should pass through the fixed aircraft reference.
5. In F3 diagnostics, check the FLIGHT SENSOR BUS section. Mark the heading channel unavailable through `FlightSensorSuite.set_channel_available(&"heading", false)` in a temporary debug call and confirm heading becomes invalid without invalidating the attitude channel.
6. Check external view and F3: the windshield mesh should be hidden in both states.

## Calibration note

The prototype ship has only placeholder cockpit geometry. The windshield quad is placed at local position `(0, 0.12, -2.36)` with size `2.78 × 1.56375 m`; its focal calibration assumes an eye-to-glass distance of `0.91 m`. These values are centralized in `FlightHUD`/`FlightHUDOverlay` and should be tuned against the actual cockpit/window model before visual polish.
