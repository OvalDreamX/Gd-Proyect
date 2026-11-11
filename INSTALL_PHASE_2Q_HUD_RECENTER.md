# Phase 2Q — Stable HUD and cockpit recentering

Extract this ZIP into the project root and overwrite files. This restores the proven screen-space CanvasLayer HUD from Phase 2N; it does not use the experimental 3D SubViewport windshield projection.

## Behavior
- Side field-power/vector gauges and pitch/roll/rudder control viewer remain visible in cockpit and external camera views.
- Central heading tape, flight data, attitude ladder and flight-path marker are shown only in cockpit view while the cockpit camera is within 0.5 degrees of its default boresight.
- RMB toggles camera-look mode. RMB again returns to flight control and starts a 3-second delay. If the pilot does not re-enter look mode, the cockpit camera smoothly recenters. Central symbology returns once the camera is centered.
- The heading tape wraps correctly through 000 and uses cardinal labels. Heading is calculated from the forward vector projected onto the local horizontal plane.
- Pitch ladder marks use tangent-based perspective projection, not a constant pixels-per-degree approximation.

## Preserved propulsion configuration
- Dry mass: 30,000 kg.
- Rated payload capacity: 25,000 kg.
- Vane force ratings remain based on 55,000 kg gross design mass.

## Tests
Run from the project root with Godot 4.7.2:

```powershell
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/flight_path_marker_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
```

Godot runtime tests were not run during package generation.
