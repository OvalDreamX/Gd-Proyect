# Testing and validation

**Target:** Godot 4.7.2 Stable, standard GDScript build, GL Compatibility renderer.  
**Regression scene:** `res://scenes/test_range.tscn`

This document consolidates the runnable test inventory and the minimum manual checks. A test file being present does not mean it has passed. Record the engine version, command, exit code and relevant output when validating a change.

## Running the headless regression suite

Open PowerShell in the project root (the directory containing `project.godot`). Set `$godot` to the path of the Godot 4.7.2 console executable, then run:

```powershell
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/vane_force_model_test.gd
& $godot --headless --path . --script res://tests/vane_physics_integration_test.gd
& $godot --headless --path . --script res://tests/flight_control_computer_test.gd
& $godot --headless --path . --script res://tests/flight_control_trim_test.gd
& $godot --headless --path . --script res://tests/phase_2j_flight_model_test.gd
& $godot --headless --path . --script res://tests/test_range_environment_test.gd
& $godot --headless --path . --script res://tests/display_settings_test.gd
& $godot --headless --path . --script res://tests/flight_path_marker_test.gd
& $godot --headless --path . --script res://tests/flight_sensor_suite_test.gd
& $godot --headless --path . --script res://tests/flight_hud_layout_test.gd
& $godot --headless --path . --script res://tests/flight_hud_phase2u_test.gd
& $godot --headless --path . --script res://tests/vane_thermal_model_test.gd
& $godot --headless --path . --script res://tests/cargo_system_test.gd
```

Run all relevant tests after a change, not only the test whose name matches the edited script. Physics, force allocation, thermal state and cargo COM are coupled.

## Manual regression checklist

### Import and startup

- Open the project in Godot 4.7.2 Stable and allow imports/script scanning to finish.
- Confirm there are no parser errors, missing resources, invalid node paths or autoload errors.
- Run the configured main scene. Confirm the player and ship spawn correctly and the ship settles on the landing pad without jitter or unwanted movement.

### Boarding, camera and HUD

- Approach the ship and use the interaction prompt to enter the cockpit.
- Confirm the HUD appears only after cockpit entry completes.
- Switch cockpit/external views with C. Confirm the camera switch does not change ship position, orientation, velocity or field state.
- In RMB camera-look mode, confirm camera movement does not move the ship or change the saved flight-stick position.
- Exit camera-look and verify the three-second cockpit recenter behavior.
- Confirm the central HUD is cockpit-only and disappears when the cockpit camera is off boresight; side gauges and control indicators remain visible in external view.
- Open/close F3 diagnostics, F4 cargo manifest and F10 display settings. Confirm each panel blocks flight input while interactive and restores the expected mouse mode on close.

### Flight and force model

- Start the field and wait for OFF → STARTING → ONLINE. Confirm held keys during startup do not unexpectedly arm commands.
- At the 90° vector setting, increase power and check takeoff, hover threshold and controllable descent.
- Test 0° forward propulsion and the 110° braking blend.
- Test mouse pitch/roll and A/D yaw in assisted and direct-vane modes.
- Turn the field off while rotating. Confirm no repulsorlift correction remains and the rigid body retains angular inertia.
- Confirm healthy symmetric vane groups do not introduce unintended torque. Test asymmetric vane condition and verify the predicted/applied moment has the expected direction.

### Atmosphere and glide

- Confirm drag opposes air-relative velocity and weakens as density falls with altitude.
- Confirm wind remains fixed in world space while ship heading changes.
- Compare airspeed with inertial speed in atmosphere and vacuum.
- At sufficient forward speed, test positive, neutral and negative angle of attack and the shield-generated glide-lift response.
- Disable shield glide lift and confirm drag remains while the added lift disappears.

### Sensors and FPM

- Confirm attitude, heading, velocity and altitude instruments follow the sensor packet.
- Invalidate one sensor channel and verify the other channels remain valid.
- Confirm FPM follows inertial velocity rather than nose direction; suppress it near zero speed.
- Drive the FPM outside the central HUD field and confirm the circle/X edge cue appears with the correct edge direction.
- Remember that the current compass north reference is world north and current altitude is not terrain/radar altitude.

### Thermal and cargo integration

- Start from cold vane temperatures and observe warmup, authority clamp and F3 thermal diagnostics.
- Run at high load and observe heating/overheat behavior. Use current coefficients; do not rely on the older 25–35 second overheat statement.
- Switch the field off and verify vanes continue cooling while offline without accruing operating wear.
- Use F4 to test empty, half, maximum, port-heavy, starboard-heavy, nose-heavy and aft-heavy manifests.
- Confirm payload clamps to the ship-authored capacity, total mass updates, custom COM moves as expected, and vane mount positions remain unchanged.
- For off-centre loads, inspect main-field torque and FCC PI trim/saturation in F3. The FCC is bounded rate trim, not guaranteed level-hover autopilot; residual rotation is expected if available authority is insufficient.

## Desktop-renderer checks

Use the normal desktop renderer for visual inspection of cockpit composition, HUD legibility, display scaling and any render-target/pixel-output check. A headless test can validate math and scene state but cannot substitute for checking actual in-game pixels and camera behavior.

Test at least the reference 1280×720 layout, a common 16:9 high-resolution mode, a 16:10 mode and an ultrawide mode. Confirm uniform HUD scaling, no clipped text and sensible placement of side instruments.

## Validation record template

For each validation pass, record:

- Commit SHA and project branch.
- Godot version/build and renderer.
- Exact test commands run.
- Pass/fail counts and exit codes.
- Manual tests performed and any observed deviations.
- Whether the normal desktop renderer was inspected.

Do not label a milestone runtime-validated on the basis of static code review, source parsing alone, ZIP integrity, or a test that only checks node existence.
