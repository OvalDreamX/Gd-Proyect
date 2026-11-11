# Phase 2S — Vane Thermal Simulation (current behavior after 2U)

This document describes the current thermal implementation, including the 2U runtime correction. The thermal model is game-tuned fiction, not a claim that real repulsorlift hardware follows these exact equations.

## Runtime model

Each vane owns independent temperature, load, integrity, wear, failure and sputter state.

For a vane's current load fraction:

- Lower green-zone bound: `60°C * load^0.7`.
- Upper green-zone bound: `180°C - 20°C * load`.
- Heat input while the field is online: `3°C/s + 22°C/s * load^2`.
- Cooling: `0.05/s * (vane temperature - ambient temperature)`.
- Green-zone wear: `0.000002 integrity/s`.
- Outside the green zone: baseline wear plus `0.000008 * temperature_delta^2 * load^2` per second.

The cold authority clamp is separate from the load-dependent green-zone threshold. Below 60°C a vane is limited between 70% and 100% of its integrity-adjusted authority. Above 180°C and up to 230°C, the vane has a temporary 5% output bonus. Above 230°C, or below 20% integrity, it can sputter. Integrity reaching zero permanently fails the vane until repaired/reset by a future maintenance system.

The lower green-zone boundary changes with load. At 35% load it is about 27°C, while the cold authority clamp still does not reach full authority until 60°C.

## 2U runtime correction

Thermal simulation now advances once per call to `RepulsorliftSystem.apply_flight_control_forces`, including when the field is offline or the body is frozen. Offline vanes have zero load, no base operating wear, and continue cooling toward ambient temperature.

The thermal load packet combines:
- Main-vector load allocated to the bottom or rear vane groups according to the current vector distribution.
- Per-vane force magnitudes from the current maneuver allocator contributions.

This is a first-pass actuator-load estimate. It is not yet a complete energy/temperature solution based on every physical subsystem or a detailed thermal network between vanes and radiators.

## Timing

With the current coefficients, the model heats aggressively. At full vane load, heat input is 25°C/s before cooling. Starting at -10°C, a continuously full-loaded vane enters overheat territory quickly (the load-dependent upper green bound is 160°C at full load), and reaches the critical region on the order of a dozen seconds. At 35% load, reaching 60°C from -10°C takes roughly 19 seconds under the current ambient and cooling settings.

These are model estimates; actual runtime behavior should be checked with the test and F3 diagnostics. Do not use the earlier 25–35 second full-power overheat claim.

## Diagnostics

F3 reports per-vane temperature, status, green-zone bounds, load fraction, wear rate and sputter state.

## Tests

From the Godot project root in PowerShell:

```powershell
& $godot --headless --path . --script res://tests/vane_thermal_model_test.gd
& $godot --headless --path . --script res://tests/cargo_system_test.gd
& $godot --headless --path . --script res://tests/flight_hud_phase2u_test.gd
```

The cargo integration test also verifies offline cooling through the actual ship's `RepulsorliftSystem`.
