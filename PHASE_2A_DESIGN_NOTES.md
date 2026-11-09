# Phase 2A implementation notes

## Architecture

`ShipInteractable` remains the owner of the pilot-seat claim. `ShipFlightController` is a separate child of the ship's single `RigidBody3D`; it accepts ship-only inputs and owns the repulsorlift activation state and command setpoints. `FlightHUD` is a separate `CanvasLayer` that receives telemetry snapshots and only displays them.

The `is_pilot_ready()` gate checks the seat claim and the player controller’s explicit piloting state. The player exposes a read-only `is_piloting()` query that becomes true only after the cockpit-entry transition fully completes. This avoids interpreting the F key used for boarding as a second F press for field activation, and it ensures a future external-camera switch does not look like the pilot has left the seat.

## JSBSim-inspired design choice

This borrows an architectural principle, not JSBSim's aircraft equations or code: keep pilot commands, system/control state, the physical model, and output/telemetry as separable stages. JSBSim's manual describes distinct input, flight-control, propulsion, mass-balance, aerodynamic and other model components executed in a defined cycle. Space Trucker's future force model can use the same separation at a much smaller scale, while keeping Godot's `RigidBody3D` as the sole owner of physical integration.

Reference: https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/flight-control-and-systems-modeling/

## Why there is no separate FlightTelemetry script yet

At this stage the data contract is a small `Dictionary` snapshot passed from the controller to the HUD. Creating a separate telemetry Resource before there are multiple producers or consumers would add indirection without providing a current benefit. The boundary is already explicit: only the controller writes the snapshot; the HUD reads it. It can be formalized into a typed Resource when the vane, FCC and physics systems need to publish a larger shared state.
