# Space Trucker — Phase 2K: Test Wind, FCC Input Response and F3 Diagnostics

## Install

1. Back up the current Phase 2J project folder.
2. Extract this ZIP directly into the existing Godot project root.
3. Allow the included files to overwrite the existing files.
4. Open the project in **Godot 4.7.2 Stable** and run the main scene with F5.

This is an incremental overwrite package. It expects the Phase 2J project and its existing Phase 2E–2I dependencies to remain in place. It does not replace `project.godot` or remove any project files.

## Changes

### 1. Front-left test wind and mild turbulence

The atmospheric model now starts with a steady **8 m/s mean wind**. With the test ship's initial forward direction (-Z), the wind originates from the front-left and flows toward the rear-right (+X, +Z in world space).

A seeded `FastNoiseLite` sample adds smooth, time-correlated turbulence with a configured amplitude of 1.1 m/s. Three separated noise samples vary the wind's X, Y and Z components. This is deterministic coherent noise, not independent random impulses every physics frame.

The wind is world-space and remains fixed when the ship turns. The wind and turbulence only generate drag while the local atmosphere is enabled. The model remains independent of the repulsorlift field and FCC.

The initial wind is intentionally strong enough to be measurable on the current 12,000 kg prototype, without behaving like a storm. At sea-level density, expect a few hundred newtons of drag on a stationary ship; the resulting drift is gradual, so observe it while hovering rather than while resting on the landing pad.

### 2. F3 diagnostics display fix

The F3 page now uses a read-only `TextEdit` with its own vertical scrollbar instead of a `Label` nested inside a `ScrollContainer`. This gives the diagnostics text a concrete viewport size and avoids the nested layout sizing issue that could leave the panel visible but its contents absent.

The F3 page also reports:

- Mean wind velocity.
- Current wind velocity after turbulence.
- Turbulence velocity and configured amplitude.
- Air-relative velocity and airspeed.
- Drag force and magnitude.
- FCC input deadzone, curvature and conditioned pitch/roll/yaw values.

To scroll with the mouse captured, use the existing procedure: hold RMB to enter camera-look mode, then hold Shift to release the cursor while interacting with the diagnostics page.

### 3. FCC response curve and deadzone

The FCC now applies a fixed **1% deadzone** and **18% response curvature** to pitch, roll and yaw pilot inputs before rate requests or direct-mode vane commands are calculated.

The curve is a symmetric blend from linear response toward a cubic response:

`shaped = lerp(x, x * x * x, 0.18)`

The input is first clamped and remapped outside the 1% deadzone. Both signs and full-scale endpoints are preserved. This lowers center sensitivity by approximately 15–20% through the useful mid-stick range without reducing maximum command.

The persistent mouse-stick position remains raw, so the cockpit stick indicator continues to show where the player has moved the virtual stick. The FCC shapes that input internally. The settings are constants for now; later they can become controls on the in-game FCC display, without introducing a separate options menu.

Pitch remains inverted in the conventional flight-sim sense established in the previous update: mouse up commands nose down, and mouse down commands nose up.

## Suggested manual test

1. Enter the cockpit and bring the repulsorlift field online.
2. Use the 90-degree vector setting and enough field power to hover a few metres above the pad.
3. Keep the pitch/roll stick centered and avoid commanding lateral movement.
4. Open F3. Confirm the mean wind is approximately `(5, 0, 6.25) m/s`, while the current wind varies smoothly around it.
5. Watch the drag vector and the ship's slow drift. At the initial heading, the wind should push it generally toward world +X and +Z.
6. Turn the ship. The wind remains fixed in world space, so its ship-relative direction changes.
7. Move the mouse stick through small and medium deflections. The conditioned input shown in F3 should grow more slowly around center, remain symmetrical, and still reach ±1 at full deflection.
8. Check that FCC assistance OFF still uses the same input curve; only the rate-control assistance is removed.

A ship resting on the pad may not move because ground friction can resist this light wind. Use a hover test to observe the effect more clearly.

## Automated tests

Run these separately from PowerShell in the project root:

```powershell
$godot = "C:\Path\To\Godot_v4.7.2-stable_win64.exe"

& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/display_settings_test.gd
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
```

The package updates the FCC, atmospheric model, F3 HUD and the corresponding FCC/atmosphere/HUD tests. Keep the existing display settings and force-control tests from prior phases.

## Validation status

The code and scene wiring have been statically reviewed, and the ZIP archive is checked for integrity. Godot 4.7.2 is not installed in this build environment, so I have not run the Godot parser, automated tests or an in-engine visual check. Run the tests above before treating this update as runtime-validated.
