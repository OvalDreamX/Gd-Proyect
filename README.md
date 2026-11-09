# Space Trucker — Phase 2A Prototype

**Target engine:** Godot 4.7.2 Stable (GDScript, standard edition; no .NET required)

Phase 2A adds ship-owned repulsorlift activation-state handling, initial ship command collection, and a telemetry HUD. It builds on the original first-person walk-up/cockpit-entry slice.

## Implemented

- Existing first-person walking and cockpit-entry transition are preserved.
- A `ShipFlightController` node is attached to the ship's existing `RigidBody3D` root.
- Pressing F in the cockpit changes the field state through `OFF -> STARTING -> ONLINE`; pressing F again aborts startup or switches the field OFF.
- W/S changes the field-power command while ONLINE.
- Q/E continuously changes the vector-distribution command between 0 and 110 degrees.
- A/D produces a normalized yaw command for telemetry.
- A neutral-input interlock prevents keys held during field startup from becoming unintended commands when the field comes ONLINE.
- A separate `FlightHUD` displays the command values and clearly reports that force output is not connected.
- The HUD is visible only after the cockpit-entry transition is complete.

## Controls

| Input | Action |
|---|---|
| W / A / S / D | Walk outside the ship; field power / yaw telemetry while seated and ONLINE |
| Mouse | Look around outside the ship |
| Space | Jump |
| F near the ship | Enter cockpit |
| F while seated | Start/abort/stop the repulsorlift field |
| W / S while field ONLINE | Increase/decrease field-power command |
| Q / E while field ONLINE | Move vector distribution continuously from 0 to 110 degrees |
| A / D while field ONLINE | Yaw command telemetry (-1 to +1) |
| Escape | Release mouse capture while walking |

## Explicit scope boundary

**The ship does not fly in Phase 2A.** The rigid body remains frozen, and the new controller does not call force, impulse or torque APIs or modify the ship's transform/velocity. Field power starts at zero. W/S, Q/E and A/D currently produce command values only.

Mouse pitch/roll input, external camera, RMB camera-look mode and F3 debug overview are reserved for Phase 2B. Vane definitions, force/torque calculations, FCC and actual rigid-body integration remain later milestones. The GDD's Step 1 rigid-body validation must be completed before collective lift is connected to physics.

## Run

Open the project in Godot 4.7.2 Stable and press F5 to run the configured main scene. Walk to the freighter, enter the cockpit using the existing prompt, and test the seated controls above.

## Project structure

```text
res://
  project.godot
  scenes/
    test_range.tscn
    player.tscn
    ship.tscn
  scripts/
    player_controller.gd
    ship_interactable.gd
    ship_flight_controller.gd
    flight_hud.gd
```

## Next validation

Follow `INSTALL_PHASE_2A.md` for the acceptance-test sequence. The immediate next implementation should be chosen after Phase 2A has been run on the target Godot 4.7.2 installation and its results have been reviewed.
