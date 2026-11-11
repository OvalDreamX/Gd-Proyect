# Phase 2Q — Windshield HUD render-path correction

## Install

Extract this overwrite ZIP into the project root (the directory containing `project.godot`) and overwrite the listed files.

## What changed

- The windshield `SubViewport` is now a direct child of the ship, independent of the `FlightHUD` `CanvasLayer`. Hiding the screen-space layer before pilot entry or during UI state changes can no longer affect the windshield render target's ownership/visibility chain.
- The viewport is explicitly 1280×720, transparent, 2D-only, and `UPDATE_ALWAYS`.
- The 3D receiving material uses premultiplied-alpha blending, disables depth testing and depth writes, disables face culling, and uses render priority 127. The projected combiner symbology is therefore not hidden by the placeholder cockpit dashboard or frame meshes.
- The viewport continues to render the central symbology from the ship sensor packet. The physical projection remains fixed to the ship's forward window; head-look still moves the camera relative to the glass.
- The side HUD remains screen-space and visible in third-person view. F3 still suppresses normal HUD elements while diagnostics are active.
- Added tests that inspect the receiving material configuration and the actual SubViewport image alpha, rather than only checking that the viewport/mesh nodes exist.
- Added compass wrap tests around north.

## Tests

Run from PowerShell in the project root with Godot 4.7.2:

```powershell
# Run this one with the desktop renderer, not --headless: it samples actual viewport pixels.
& .\godot.exe --path . --script res://tests/flight_hud_layout_test.gd
& .\godot.exe --headless --path . --script res://tests/flight_path_marker_test.gd
& .\godot.exe --headless --path . --script res://tests/flight_sensor_suite_test.gd
```

Then run the full existing suite:

```powershell
& .\godot.exe --headless --path . --script res://tests/flight_force_control_test.gd
& .\godot.exe --headless --path . --script res://tests/flight_control_computer_test.gd
& .\godot.exe --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& .\godot.exe --headless --path . --script res://tests/display_settings_test.gd
& .\godot.exe --headless --path . --script res://tests/test_range_environment_test.gd
& .\godot.exe --headless --path . --script res://tests/vane_force_model_test.gd
```

## Manual checks

1. Enter the cockpit and look straight ahead. The central ladder, boresight, flight-path marker, heading tape and data blocks should appear on the glass.
2. Move the mouse-look camera while holding RMB. Central symbology must remain on the windshield and leave view as the camera turns; it must not follow the camera.
3. Check that the symbology is still visible over the placeholder dashboard/frame geometry.
4. Switch to external view. The central windshield projection should disappear, while the side gauges and control viewer stay visible on screen.
5. Check headings around north, especially 359.6° → 000°.

## Validation status

The source-level changes and package structure were checked in the build environment. Godot 4.7.2 runtime rendering tests could not be executed in this environment; the new pixel-output regression test is included specifically to verify that the 2D SubViewport actually renders non-transparent HUD pixels on the user's machine.
