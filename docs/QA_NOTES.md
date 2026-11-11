# QA Notes — Phase 1 Prototype

## Checks performed in the build environment

- Confirmed all `.tscn` external resource paths point to files included in the project.
- Confirmed each scene's `load_steps` count matches its external and subresource declarations.
- Manually reviewed the GDScript for node paths, signal signatures, and Godot 4 APIs used by this small prototype.
- Confirmed the project targets Godot 4.7 stable feature compatibility and uses the GL Compatibility renderer.

## Runtime test status

**Not runtime-tested in this build environment.** A Godot executable was not installed, and a standalone engine binary could not be fetched here. Therefore, do not treat the project as engine-validated yet. Open it in Godot 4.7.2 stable and run the main scene with F5. Fix any parser/import errors before adding features.

## First manual test checklist

1. Project imports without parse or resource errors.
2. Player spawns upright on the test range, with mouse captured.
3. WASD moves, mouse looks, Space jumps, Escape releases the mouse, and clicking recaptures it.
4. Approaching the freighter causes `PILOT SHIP [F]` to appear.
5. Walking away removes the prompt.
6. Pressing F starts the dimmed camera-dolly transition.
7. Transition ends in the cockpit view with the player body moved to the seat and walking disabled.
8. No error appears in the Debugger / Output panel.


# Phase 2Q — HUD projection verification

## Source-level checks

- Windshield SubViewport is a ship child, not a child of the hidden `FlightHUD` CanvasLayer.
- Viewport is 1280×720, transparent, 2D-only and `UPDATE_ALWAYS`.
- Receiving material uses premultiplied-alpha blending, no depth test, disabled depth writes/culling, and render priority 127.
- Regression test now samples the SubViewport image and checks for non-transparent HUD pixels; node existence/visibility alone is no longer treated as proof of rendering. Run this one with the desktop renderer, not `--headless`.
- Third-person side HUD behavior and compass wraparound are covered by tests.

## Runtime status

**Not runtime-validated in this build environment.** The Windows Godot executable is included in the project, but this Linux build environment cannot execute the Windows binary. The user must run the Phase 2Q tests and inspect the cockpit projection in Godot 4.7.2. Do not assume the central HUD is fixed until the pixel-output test passes.
