# Testing and Validation — Space Trucker v0.4.0

**Target:** Godot 4.7.2 Stable, standard GDScript build, GL Compatibility renderer.

## 1. Phase 2 GLB, Pipeline, Ground Effect & 6-DOF Allocator Suite
Run from the project root in PowerShell with `$godot` set to the Godot 4.7.2 console binary:

```powershell
& $godot --headless --path . --script res://tests/flight_force_control_test.gd
& $godot --headless --path . --script res://tests/main_vector_allocator_test.gd
& $godot --headless --path . --script res://tests/vane_yaw_geometry_test.gd
& $godot --headless --path . --script res://tests/unified_actuator_wrench_test.gd
& $godot --headless --path . --script res://tests/unified_actuator_channel_priority_test.gd
& $godot --headless --path . --script res://tests/vane_actuator_allocator_test.gd
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
& $godot --headless --path . --script res://tests/ship_definition_loader_test.gd
& $godot --headless --path . --script res://tests/ship_model_mount_test.gd
& $godot --headless --path . --script res://tests/ship_model_pipeline_test.gd
& $godot --headless --path . --script res://tests/ship_anchor_integration_test.gd
& $godot --headless --path . --script res://tests/ship_animation_controller_test.gd
& $godot --headless --path . --script res://tests/ship_interaction_controller_test.gd
& $godot --headless --path . --script res://tests/ship_cockpit_control_bridge_test.gd
& $godot --headless --path . --script res://tests/ship_pilot_cleanup_test.gd
& $godot --headless --path . --script res://tests/repulsorlift_ground_effect_test.gd
& $godot --headless --path . --script res://tests/planetary_reference_frame_test.gd
```

## 2. Phase 3 Environment, Solar System, Jump & Space Allocator Suite
```powershell
& $godot --headless --path . --script res://tests/fcc_space_mode_test.gd
& $godot --headless --path . --script res://tests/simple_planet_loop_test.gd
& $godot --headless --path . --script res://tests/solar_system_test.gd
& $godot --headless --path . --script res://tests/ship_systems_tuning_test.gd
& $godot --headless --path . --script res://tests/planet_surface_environment_test.gd
& $godot --headless --path . --script res://tests/station_local_space_test.gd
& $godot --headless --path . --script res://tests/hyperspace_jump_test.gd
& $godot --headless --path . --script res://tests/jump_envelope_evaluator_test.gd
& $godot --headless --path . --script res://tests/environment_manager_test.gd
& $godot --headless --path . --script res://tests/environment_profile_test.gd
```
