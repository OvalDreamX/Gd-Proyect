# Space Trucker 0.2.5F.7 — Rated Main-Thrust Wear Fixture Correction

## Installation

Extract this ZIP into the Godot project root and overwrite the listed files.
This is a test-only correction for the 0.2.5F.5 geometry-based maneuver
integration and the F5.6 rated-thrust fixture update. Do not delete `.godot`,
`.gd.uid`, `.import`, project settings, or files not included in this archive.

## Included files

- `tests/flight_force_control_test.gd` — resets the main-rear actuator's
  integrity and temperature immediately before the nominal rated-force test.
- `0.2.5.X.gd` — adds the F5.7 changelog entry.
- `OVERWRITE_README.md` — this installation note.

## Root cause

F5.6 restored `main_rear` to 60 C, but did not restore its integrity, despite
claiming to do so in its README. Earlier calls to `apply_flight_control_forces()`
advance the thermal/wear simulation using one default physics step when no
explicit delta is supplied. The controller applies baseline operating wear
while the field is online even if the vane has little or no active load.

The configured baseline wear rate is `0.000002` integrity per second. About
seven 60 Hz steps yield an integrity loss of approximately `2.33e-7`. Applied
to the nominal `809325 N` main-thrust rating, this predicts a reduction of about
`0.189 N`, consistent with the reported `0.1875 N` shortfall after float
rounding. The `1.50000` TWR fixture assertion used five decimal places in its
reporting, so it did not reveal the tiny integrity loss.

F5.7 now explicitly restores both:

1. `main_rear` integrity to `1.0` (100%).
2. `main_rear` temperature to `60.0 C`.

The existing authority and rated-force assertions are retained. This fixes the
fixture rather than loosening its tolerance or changing production behavior.

## Local verification

Run from the project root in PowerShell:

```powershell
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
```

The packaging environment does not have Godot 4.7.2, so runtime execution must
be confirmed locally. The script patch is limited to fixture setup and one
additional assertion; no production GDScript is modified.
