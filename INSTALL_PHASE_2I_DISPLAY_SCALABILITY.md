# Space Trucker — Phase 2I: Display and UI Scalability

## Install

1. Make a backup of your current working project folder.
2. Extract this ZIP directly into the existing Godot project root — the folder containing `project.godot`.
3. Allow the included files to overwrite the existing files.
4. Open the project in **Godot 4.7.2 Stable** and run the main scene with F5.

This is an overwrite package based on the Phase 2H cockpit HUD package. It includes the Phase 2G/2H files needed for those phases, but still relies on the Phase 2F/2E project dependencies already present in your project, including:

- `scripts/repulsorlift_system.gd`
- `scripts/vane_controller.gd`
- `scripts/vane_definition.gd`
- `scripts/ship_camera_controller.gd`
- `scripts/force_vector_debug.gd`
- Existing vane Resources under `data/vanes/`
- `scenes/test_range.tscn` and `scenes/player.tscn`

Do not delete those files. No flight-force, FCC tuning, mass, inertia, or actuator response values are changed in this phase.

## What changes

### Window and display modes

Press **F10 while piloting** to open Display Settings.

- **Windowed:** choose a supported window size; the window remains resizable.
- **Borderless Fullscreen:** fills the current monitor at its existing desktop resolution.
- **Exclusive Fullscreen:** uses the current monitor's fullscreen mode.
- Fullscreen modes use the monitor's current desktop resolution. This menu does not change the monitor's video mode.
- Windowed resolution choices are filtered to sizes that fit the current monitor's usable work area.
- The minimum resizable window size is 800×450.

The selected mode, windowed resolution, and HUD scale are saved in `user://display_settings.cfg` and restored on the next launch. The settings file is stored in Godot's per-user application data location, not inside the project folder.

### HUD and aspect ratios

- The HUD remains based on a 1280×720 reference layout.
- The cockpit's central flight instruments remain centered.
- Side gauges move outward to use additional horizontal space on ultrawide windows.
- Additional vertical space is distributed around the HUD rather than stretching its proportions.
- The HUD scales uniformly to fit the available viewport; it does not distort text or symbology.
- HUD scale can be set to 80%, 90%, or 100% independently of the window size.
- F3 diagnostics and the F10 settings overlay use anchored Godot Controls and adapt to the available window area.

The project uses `canvas_items` stretch mode with `expand` aspect behavior. The 3D scene continues rendering at the active viewport/window size; this setting is not a forced 1280×720 render cap.

### Input while settings are open

While the display panel is open, flight-control input is blocked so the mouse and keyboard can operate the menu safely. The simulation and actuator spool continue; opening settings does not switch the field off or reset pilot setpoints. **F10** or **Escape** closes the panel and restores the previous mouse mode.

## Controls added

| Input | Action |
|---|---|
| F10 | Open / close display settings while piloting |
| Escape | Close display settings |

All existing flight and camera controls remain unchanged.

## Tests

Run these from the project root using your Godot 4.7.2 executable:

```powershell
& "C:\Path\To\Godot_v4.7.2-stable_win64.exe" --headless --path . --script res://tests/display_settings_test.gd
& "C:\Path\To\Godot_v4.7.2-stable_win64.exe" --headless --path . --script res://tests/flight_hud_layout_test.gd
& "C:\Path\To\Godot_v4.7.2-stable_win64.exe" --headless --path . --script res://tests/flight_control_computer_test.gd
& "C:\Path\To\Godot_v4.7.2-stable_win64.exe" --headless --path . --script res://tests/flight_force_control_test.gd
```

Replace the executable path with the actual path on your computer. Run each command separately. The final force-control test is the existing Phase 2F test and should already be in your project.

The new display test checks safe mode normalization, HUD scale bounds, and resolution formatting. The HUD test checks creation and visibility of the cockpit HUD, F3 diagnostics, and F10 settings panel. These tests do not replace manual window-mode and visual checks.

## Manual validation matrix

Check the following in the running game, using resolutions your monitor can actually display:

| Resolution / aspect | What to inspect |
|---|---|
| 1280×720 (16:9) | Reference layout; no clipped labels |
| 1600×900 (16:9) | Uniform scaling and readable instruments |
| 1920×1080 (16:9) | Fullscreen and windowed behavior |
| 1920×1200 (16:10) | Vertical spacing; no bottom clipping |
| 2560×1440 (16:9) | Large-resolution scaling |
| 3440×1440 (21:9) | Side gauges move outward; center remains centered |

Also test switching between all three window modes, resizing a window by dragging its edges, changing HUD scale, closing the game, and relaunching to confirm settings persist.

Do not try to force a resolution that your monitor does not support. For fullscreen, the game uses the monitor's current desktop mode.

## Validation status

The package has been statically inspected for expected file structure, project settings, scene/script wiring, and test presence. The build environment does not contain Godot 4.7.2, so GDScript parsing, automated runtime tests, and visual checks have **not** been executed here. Run the tests and manual matrix above on your machine before treating this phase as validated.
