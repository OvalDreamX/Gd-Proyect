# Space Trucker — Stability Preparation Overwrite

Extract this ZIP into the existing Godot project root and allow the included paths to overwrite the matching files. This is a small overwrite package, not a full project archive.

## Changes

- F3 diagnostic scrolling is preserved after the Phase 2U HUD finishes applying its trim-status wording and appended trim diagnostics. The base HUD's scroll restoration was previously undone by the subclass's later TextEdit assignments.
- The ship flight controller no longer marks an unhandled mouse-wheel event as handled while debug UI interaction is active. The GUI gets its normal opportunity to consume the event first. External-camera zoom remains unchanged when debug interaction is off.
- A regression check now exercises the Phase 2U scroll-retention path.

## Test

Run from the project root:

```text
godot --headless --path . --script res://tests/flight_hud_phase2u_test.gd
```

The test script has been updated but was not executed during package preparation.

## Scope limits

This package is intentionally based only on files from the current Phase 2U overwrite snapshot that were confirmed byte-for-byte identical to the current GitHub main branch. It does not change the base HUD, display settings, cargo mass/inertia, ship seat lifecycle, environment model, scenes, project settings, or resource files. Those changes need a current full project snapshot and engine validation rather than being inferred from an older project archive.
