# Ground-effect diagnostics patch

This patch corrects visibility/diagnostics only. It does not change the force law, 15% maximum gain, 5 m fade distance, or the no-automatic-landing-assist policy.

## What changed

- F3 force visualization now draws the `ground_effect` resultant as a separate orange arrow.
- A compact readout appears in the upper-right while F3 is enabled.
- The readout reports configuration state, valid probe count, average clearance, proximity, maximum gain, current multiplier, upward main force, and additional force.
- When inactive, it reports the first detected reason: field offline, insufficient probe hits, out of range, no upward main force, or disabled/invalid configuration.
- The overlay samples telemetry at 10 Hz by default and never submits forces or changes ship state.

## Manual test

1. Run the test range and enter the ship.
2. Enable the field; use the 90-degree main-vector setting.
3. Press F3. The orange panel should show `ACTIVE`, four valid probes, and nonzero additional force when close to the ground.
4. Ascend slowly and watch the probe clearance and multiplier change.
5. Above 5 m clearance, proximity and additional force should reach zero.
6. If the panel reports `NO SURFACE`, check the probe count and collision layer/mask before tuning force values.

Clearance is measured from the bottom probe locations to the collision surface, not from the ship's origin or the HUD's planetary altitude.
