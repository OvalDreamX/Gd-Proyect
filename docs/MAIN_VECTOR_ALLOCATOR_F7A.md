# Main-vector allocator — F7A implementation note

## Data contract

The main field vector now consumes these existing per-actuator channels:

- `lift`: bidirectional ship-local `Y` contribution.
- `main_thrust`: bidirectional ship-local `Z` contribution; positive demand is
  forward (`-Z`), negative demand is rearward (`+Z`).

A vane is eligible when its corresponding control weight is non-zero. Weights
remain allocator recruitment priorities, not percentages of the actuator's
rated force. `VaneController.get_vane_effective_authority_twr()` supplies the
current force limit after integrity, failure, sputter and temperature effects.
`get_vane_effective_thrust_axis_local()` supplies the actual axis after
alignment drift.

## Main-vector demand construction

Let `theta` be the existing requested vector angle, clamped to 0–110 degrees,
`P` the existing normalized power output and `R` the fixed gross-mass reference
force (`design_gross_mass * reference_gravity`). The allocator receives:

```text
lift        = P * sin(theta)
main_thrust = P * cos(theta)
```

The channel capacities are sums of each eligible actuator's effective TWR
multiplied by the absolute projection of its current thrust axis onto the
channel's reference axis. The selected force magnitude rating remains:

```text
available_twr = lerp(main_thrust_capacity, lift_capacity,
                     clamp(theta / 90 degrees, 0, 1))
allocator_reference_force = R * available_twr
```

This preserves the previous endpoint ratings and linear transition. At angles
greater than 90 degrees, the lift capacity remains selected and the signed
`main_thrust` component reverses to provide braking.

## Why the allocator is solved about the hull datum

The main field is still a ship-wide resultant in this prototype. It is not
supposed to create a new independent hull torque just because individual
actuator anchors are separated. F7A therefore gives the allocator a zero COM
reference (the hull datum), obtains its geometry-compatible net force and
submits that force once at the RigidBody3D origin.

The real rigid-body COM is used only when reporting the resultant's physical
moment, and Godot receives the force at offset zero. Thus an asymmetric cargo
COM still produces `(hull_origin - COM) x force`, matching the established
behavior. Maneuver actuators remain applied individually at their actual
anchor-derived offsets; F7B does not change that distinction.

## F7B dependency

The current main-vector and maneuver allocators are separate in F7A. They must
not be considered a final resource-sharing policy. F7B must combine `lift`,
`main_thrust`, `pitch`, `roll` and `yaw` into one request set before a single
bounded solve. It must then apply:

- the main-vector achieved resultant once at the hull datum;
- maneuver force components at their actuator application points, preserving
  the matching force moments without applying the main-vector contribution twice.

The unified result must also drive per-vane thermal loads and actuator telemetry.
