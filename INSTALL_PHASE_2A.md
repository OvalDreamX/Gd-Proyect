# Space Trucker — Phase 2A patch

## Files in this patch

Copy the contents of this package into the root of your existing Godot project, preserving paths and allowing the listed files to be replaced:

- `project.godot` — adds ship-specific InputMap actions and updates the project label.
- `scenes/ship.tscn` — adds the ship-owned `FlightController` node.
- `scripts/ship_interactable.gd` — exposes a safe pilot-ready check after the cockpit-entry transition.
- `scripts/player_controller.gd` — hides the old walking-only hint once the independent ship HUD takes over; no flight logic is added to the player controller.
- `scripts/ship_flight_controller.gd` — manages field activation and command inputs.
- `scripts/flight_hud.gd` — presentation-only telemetry HUD.

No changes are required to `player_controller.gd`, `player.tscn`, or `test_range.tscn`.

## Controls while seated

- `F`: OFF -> STARTING -> ONLINE; pressing F again aborts startup or turns the field OFF.
- `W / S`: increase/decrease the field-power command while ONLINE.
- `Q / E`: move vector distribution continuously between 0 and 110 degrees while ONLINE.
- `A / D`: expose a -1 to +1 yaw command in telemetry while ONLINE.

The W/S, Q/E and A/D values are commands for the next milestones. They do not yet drive forces or torque.

## Important scope boundary

This is state/input/HUD infrastructure only. The ship remains frozen (`RigidBody3D.freeze = true`). The new controller does not call `apply_force`, `apply_central_force`, `apply_torque`, impulses, or modify the ship transform/velocity. Pressing F cannot launch the ship. Field power starts at zero.

Mouse pitch/roll input, external camera, RMB mode switching and debug UI interaction belong to Phase 2B. Rigid-body validation and actual force output must still be completed in the order established by GDD Section 19.

## Test procedure

1. Open the project in Godot 4.7.2 Stable and allow the editor to import/scan scripts.
2. Run the configured main scene (F5).
3. Walk to the freighter and enter using the existing F prompt.
4. Confirm the new HUD appears only after the cockpit-entry transition completes.
5. Confirm field state initially reads `OFF` and field power reads `0.0%`.
6. Press F. Confirm `STARTING` appears, then `ONLINE` after approximately 1.2 seconds.
7. Once ONLINE, release any W/S, Q/E or A/D keys held during startup; the command inputs arm only after they return to neutral.
8. While ONLINE, hold W and S separately. Confirm the power command moves smoothly between 0 and 100%, and never leaves that range.
9. Hold Q and E separately. Confirm the vector command moves smoothly between 0 and 110 degrees, and does not jump between three discrete modes.
10. Hold A and D separately. Confirm yaw telemetry reports -1 and +1 respectively, returning to zero when released.
11. Press F while STARTING to abort; press F while ONLINE to turn the field OFF. Confirm power resets to zero.
12. Verify the ship remains in exactly the same location and orientation throughout. It must not lift, drift or rotate.
13. Walk around after restarting the scene and confirm the HUD is not visible outside the cockpit.

## Known limitations

- The project was not run in the Godot editor as part of preparing this patch. Runtime validation is therefore pending on the project's pinned Godot 4.7.2 copy.
- The 1.2-second startup delay, 0.35/s power-command rate and 35-degree/s vector-command rate are prototype tuning values, not confirmed design values.
- The HUD is intentionally a temporary readable debug display, not the final cockpit interface.
- Phase 2A does not implement mouse pitch/roll, actual yaw torque, vane allocation, force output, FCC stabilization, disembarking or camera switching.
