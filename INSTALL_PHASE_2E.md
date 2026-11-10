# Space Trucker — Phase 2E

## Install

1. Extract this ZIP into the existing Godot project root.
2. Preserve the folder structure.
3. Overwrite the three existing files when prompted:
   - `scripts/repulsorlift_system.gd`
   - `scripts/flight_hud.gd`
   - `scenes/ship.tscn`
4. Keep the new files and folders:
   - `scripts/vane_definition.gd`
   - `scripts/vane_controller.gd`
   - `data/vanes/*.tres`
   - `tests/vane_force_model_test.gd`
5. Open the project in Godot 4.7.2 Stable and allow the new Resources/scripts to be scanned.

No other existing files need to be changed. The current camera, zoom, input modes, field startup, throttle response and collective-lift controls are preserved.

## What this increment does

- Adds five typed `VaneDefinition` Resources: four bottom vanes and the main rear vane.
- Creates separate per-ship runtime state for integrity, failure and alignment offset. Runtime state is not stored in shared Resources.
- Splits the bottom vanes into front and rear groups.
- Calculates every bottom vane's force and moment about the ship's current center of mass.
- Aggregates front/rear net force and torque.
- Continues applying only the net central lift force. Predicted torque is displayed in the HUD/debug overview but is deliberately **not applied** in this increment, so existing hover behavior cannot acquire unvalidated rotation.

## Configuration values and scope

- Four bottom vanes: `0.275 TWR` each, `1.10 TWR` collectively. This retains the GDD Section 9.6 placeholder.
- Main rear vane: `1.5 TWR` placeholder, registered but not yet used to produce propulsion.
- The initial vane coordinates are provisional positions inside the current placeholder hull. They are configuration data, not final ship-design dimensions.
- Side vanes are not fabricated here. Their count and exact layout remain TBD in the GDD.
- Temperature, degradation, FCC compensation, vector-distribution mapping and torque integration are not implemented in this increment.

## Deterministic force-model test

After opening the project once in the editor so Godot can scan the new scripts and Resources, run this from a terminal in the project root:

```bash
godot --headless --path . --script res://tests/vane_force_model_test.gd
```

The test checks:

1. Five vane definitions register and the four bottom vanes total 1.10 TWR.
2. Healthy symmetric vanes produce the expected net lift and approximately zero torque.
3. A 50%-effective front-right vane reduces available lift and creates a roll moment.
4. A failed vane contributes zero force.
5. Reset restores the healthy force/torque baseline.
6. Equal opposing front/rear group forces cancel translation and produce pitch torque.

A successful run exits with code `0` and reports zero failures. If your Godot executable is not on PATH, run the same arguments with the full path to your Godot 4.7.2 executable.

## In-project checks

1. Run the main scene and enter the cockpit.
2. Confirm the HUD reports `5 REGISTERED / 5 HEALTHY`.
3. Activate the field and repeat the previously working takeoff/hover/descent test.
4. Confirm the maximum lift TWR and hover threshold remain approximately `1.10` and `90.9%`.
5. Press F3. The debug panel should list all five vane states and show force/moment contributions for the four bottom vanes.
6. With all vanes healthy and symmetrically placed, predicted lift torque should be approximately zero.
7. Confirm the predicted torque is labelled `NOT APPLIED`; there should be no new rotation behavior from this increment.
8. Confirm C, RMB, Shift, F3 and external-camera scroll zoom still work as before.

## Files changed

Overwritten:
- `scripts/repulsorlift_system.gd`
- `scripts/flight_hud.gd`
- `scenes/ship.tscn`

Added:
- `scripts/vane_definition.gd`
- `scripts/vane_controller.gd`
- `data/vanes/bottom_front_left.tres`
- `data/vanes/bottom_front_right.tres`
- `data/vanes/bottom_rear_left.tres`
- `data/vanes/bottom_rear_right.tres`
- `data/vanes/main_rear.tres`
- `tests/vane_force_model_test.gd`
- `INSTALL_PHASE_2E.md`
