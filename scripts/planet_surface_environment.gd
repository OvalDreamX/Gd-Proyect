extends Node3D
class_name PlanetSurfaceEnvironment

## Phase 3J / 4A spherical planetary surface environment ("Tatooine / Simple Planet", R = 600,000 m).
## Patch 0.4.1a hotfix:
## - Keeps CockpitCamera.near at base 0.05 m across all altitudes so the cockpit
##   mesh never clips out at high altitude while ExternalCamera clamps near/far.
## - Runs floating-origin checks in _physics_process (priority -20) at a 4,000 m
##   threshold and recursively resets subtree physics interpolation so the ship
##   hull & external rig never jump or flash for 0.5s during high-speed climbs.

const SOLAR_SYSTEM_LOADER = preload("res://scripts/solar_system_loader.gd")
const ATMOSPHERE_MODEL = preload("res://scripts/atmosphere_model.gd")

const PLANET_CENTER: Vector3 = Vector3(0.0, -600000.0, 0.0)
const PLANET_RADIUS_M: float = 600000.0
const ATMOSPHERE_HALO_RADIUS_M: float = 613500.0

const TERRAIN_EXTENT_M: float = 12800.0
const VISUAL_GRID_SEGMENTS: int = 64
const COLLISION_GRID_SEGMENTS: int = 32

const SPHERE_FACE_VISUAL_SEGMENTS: int = 56
const SPHERE_FACE_COLLISION_SEGMENTS: int = 24
const BASIN_SEAM_INNER_ARC_M: float = 2800.0
const BASIN_SEAM_OUTER_ARC_M: float = 4600.0
const BASIN_SKIRT_OUTER_ARC_M: float = 5800.0
const BASIN_SEAM_TUCK_M: float = 45.0

const STARPORT_FLAT_RADIUS_M: float = 115.0
const FOOTHILL_START_RADIUS_M: float = 160.0
const RIDGE_START_RADIUS_M: float = 650.0

const OUTPOST_DIRECTION: Vector3 = Vector3(0.05475, 0.99779, -0.03764)
const OUTPOST_BASE_HEIGHT_M: float = 80.0
const OUTPOST_FLAT_ARC_M: float = 280.0
const OUTPOST_BLEND_ARC_M: float = 1200.0

const FLOATING_ORIGIN_THRESHOLD_M: float = 4000.0
const ORIGIN_SHIFT_GRACE_SECONDS: float = 0.35
const ORIGIN_SHIFT_DWELL_FRAMES: int = 3
const STAR_DISC_VISUAL_DISTANCE_M: float = 72000.0
const MAX_DEPTH_CLIP_RATIO: float = 220000.0

const HALO_SHADER_CODE: String = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front;

uniform vec3 atmo_color = vec3(0.16, 0.52, 1.0);
uniform vec3 sun_dir_world = vec3(0.4, 0.6, -0.6);
uniform float halo_alpha = 0.0;

varying vec3 v_world_pos;
varying vec3 v_center_world;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(v_world_pos - v_center_world);
	vec3 v_world = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float mu = clamp(-dot(n, v_world), 0.0, 1.0);
	float limb_band = smoothstep(0.02, 0.16, mu) * (1.0 - smoothstep(0.18, 0.40, mu));
	float sun_lit = smoothstep(-0.22, 0.30, dot(n, normalize(sun_dir_world)));
	ALBEDO = atmo_color * (0.35 + 1.05 * sun_lit);
	ALPHA = clamp(halo_alpha * limb_band * (0.14 + 0.86 * sun_lit), 0.0, 1.0);
}
"""

var _terrain_material: StandardMaterial3D
var _structure_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _glass_material: StandardMaterial3D
var _beacon_lamp_material: StandardMaterial3D
var _marking_yellow: StandardMaterial3D
var _marking_white: StandardMaterial3D
var _halo_material: ShaderMaterial
var _star_disc_material: StandardMaterial3D
var _night_star_material: StandardMaterial3D
var _atmosphere_halo: MeshInstance3D

var _celestial_sky_rig: Node3D
var _star_disc: MeshInstance3D
var _night_stars: MultiMeshInstance3D

var _system_data: Dictionary = {}
var _celestial_state: Dictionary = {}
var _celestial_time_override_seconds: float = -1.0

var _sky_transition_progress: float = 0.0
var _sky_material: ProceduralSkyMaterial
var _world_env_resource: Environment
var _base_fog_density: float = 0.00009
var _ship_cameras: Array[Camera3D] = []
var _camera_base_near_by_id: Dictionary = {}
var _active_waypoint_index: int = 1

var _world_origin_offset: Vector3 = Vector3.ZERO
var _origin_shift_grace_remaining: float = ORIGIN_SHIFT_GRACE_SECONDS
var _origin_dwell_frames: int = 0

@onready var _environment_manager: Node = get_node_or_null("EnvironmentManager")
@onready var _world_environment: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
@onready var _sun_light: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D

@onready var _ship: RigidBody3D = get_node_or_null("Ship") as RigidBody3D
@onready var _player: CharacterBody3D = get_node_or_null("Player") as CharacterBody3D
@onready var _ship_spawn: Marker3D = get_node_or_null("ShipSpawnPoint") as Marker3D
@onready var _player_spawn: Marker3D = get_node_or_null("PlayerSpawnPoint") as Marker3D


func _ready() -> void:
	process_physics_priority = -20
	process_priority = 20
	_origin_shift_grace_remaining = ORIGIN_SHIFT_GRACE_SECONDS
	_origin_dwell_frames = 0
	_load_solar_system()
	_create_materials()
	_build_terrain()
	_build_atmosphere_halo()
	_build_celestial_sky_rig()
	_build_starport_markings()
	_build_starport_structures()
	_build_approach_beacons()
	_build_near_outcrops()
	_build_horizon_outpost()
	_cache_sky_and_environment()
	_cache_ship_cameras()
	_update_celestial_lighting()
	_update_atmosphere_sky_and_fog()


func _physics_process(delta: float) -> void:
	_origin_shift_grace_remaining = maxf(_origin_shift_grace_remaining - maxf(delta, 0.0), 0.0)
	_maybe_shift_floating_origin()


func _process(_delta: float) -> void:
	_update_celestial_lighting()
	_update_atmosphere_sky_and_fog()


func _load_solar_system() -> void:
	var loaded: Dictionary = SOLAR_SYSTEM_LOADER.load_system_from_file()
	if bool(loaded.get("valid", false)):
		_system_data = loaded.get("system", {}) as Dictionary
	else:
		push_warning("PlanetSurfaceEnvironment: using fallback solar system data: %s" % str(loaded.get("errors", [])))
		_system_data = {
			"system_id": "test_system",
			"display_name": "Solara Test System",
			"time_scale": 1.0,
			"initial_epoch_seconds": 0.0,
			"stars": [{"star_id": "sol_prime", "display_name": "Sol Prime", "light_color": [1.0, 0.96, 0.90], "light_intensity": 1.0, "disc_color": [1.0, 0.97, 0.89], "disc_angular_radius_deg": 0.95}],
			"planets": [{"planet_id": "test_planet", "display_name": "Tatooine", "planet_type": "DESERT", "atmosphere_preset": "DESERT_TATOOINE", "parent_star_id": "sol_prime", "radius_m": 600000.0, "orbital_radius_m": 150000000.0, "orbital_period_seconds": 7200.0, "initial_orbital_angle_deg": 205.0, "rotation_period_seconds": 1800.0, "axial_tilt_deg": 12.0, "starport_latitude_deg": 35.0, "initial_rotation_deg": 32.5, "atmosphere_color": [0.16, 0.52, 1.0], "surface_tint": [0.85, 0.68, 0.44]}],
			"stations": [{"station_id": "station_orbital_cube_01", "display_name": "Orbital Relay Cube 01", "orbit_parent_id": "test_planet", "orbital_radius_m": 654000.0, "orbital_period_seconds": 1440.0, "orbital_inclination_deg": 72.4, "initial_orbital_angle_deg": 41.4}],
		}


func _get_active_celestial_elapsed_seconds() -> float:
	if _celestial_time_override_seconds >= 0.0:
		return _celestial_time_override_seconds
	var sim_clock: Node = get_node_or_null("/root/SimulationClock")
	if is_instance_valid(sim_clock):
		if sim_clock.has_method("get_total_celestial_time_seconds"):
			return float(sim_clock.call("get_total_celestial_time_seconds"))
		if sim_clock.has_method("get_time_seconds"):
			return float(sim_clock.call("get_time_seconds"))
	return 0.0


func set_celestial_time_override(seconds: float) -> void:
	_celestial_time_override_seconds = maxf(seconds, 0.0)
	_update_celestial_lighting()
	_update_atmosphere_sky_and_fog()


func clear_celestial_time_override() -> void:
	_celestial_time_override_seconds = -1.0
	_update_celestial_lighting()
	_update_atmosphere_sky_and_fog()


func get_celestial_telemetry() -> Dictionary:
	if _celestial_state.is_empty():
		_celestial_state = SOLAR_SYSTEM_LOADER.evaluate_system_state(_system_data, _get_active_celestial_elapsed_seconds())
	var state_copy: Dictionary = _celestial_state.duplicate(true)
	state_copy["sun_light_energy"] = _sun_light.light_energy if is_instance_valid(_sun_light) else 1.0
	state_copy["sun_light_color"] = _sun_light.light_color if is_instance_valid(_sun_light) else Color.WHITE
	return state_copy


func notify_arrival_grace(grace_seconds: float = ORIGIN_SHIFT_GRACE_SECONDS) -> void:
	_origin_shift_grace_remaining = maxf(grace_seconds, 0.0)
	_origin_dwell_frames = 0


func update_sky_and_atmosphere() -> void:
	_update_celestial_lighting()
	_update_atmosphere_sky_and_fog()


func get_sky_transition_progress() -> float:
	return _sky_transition_progress


static func get_planet_center() -> Vector3:
	return PLANET_CENTER


static func get_planet_radius_m() -> float:
	return PLANET_RADIUS_M


static func get_outpost_direction() -> Vector3:
	return OUTPOST_DIRECTION.normalized()


static func _spherical_point_relative(unit_dir: Vector3, height_m: float) -> Vector3:
	var lx: float = float(unit_dir.x)
	var ly: float = float(unit_dir.y)
	var lz: float = float(unit_dir.z)
	var len_sq: float = lx * lx + ly * ly + lz * lz
	if len_sq <= 0.000000001:
		return Vector3(0.0, height_m, 0.0)
	var inv_len: float = 1.0 / sqrt(len_sq)
	var dx: float = lx * inv_len
	var dy: float = ly * inv_len
	var dz: float = lz * inv_len
	var r_d: float = float(PLANET_RADIUS_M)
	var h_d: float = float(height_m)
	var vx: float = dx * (r_d + h_d)
	var vz: float = dz * (r_d + h_d)
	var vy: float = 0.0
	if dy >= 0.0:
		vy = -r_d * ((dx * dx + dz * dz) / (1.0 + dy)) + dy * h_d
	else:
		vy = (dy - 1.0) * r_d + dy * h_d
	return Vector3(vx, vy, vz)


static func get_spherical_surface_point(unit_dir: Vector3) -> Vector3:
	var dir: Vector3 = unit_dir.normalized() if unit_dir.length_squared() > 0.000001 else Vector3.UP
	var h: float = calculate_spherical_height_m(dir)
	return _spherical_point_relative(dir, h)


static func get_spherical_surface_point_xz(x_m: float, z_m: float) -> Vector3:
	var r_d: float = float(PLANET_RADIUS_M)
	var px: float = float(x_m)
	var pz: float = float(z_m)
	var inv_len: float = 1.0 / sqrt(px * px + r_d * r_d + pz * pz)
	var dir: Vector3 = Vector3(px * inv_len, r_d * inv_len, pz * inv_len)
	return get_spherical_surface_point(dir)


func get_world_origin_offset() -> Vector3:
	return _world_origin_offset


func get_scene_planet_center() -> Vector3:
	return PLANET_CENTER + _world_origin_offset


func get_logical_planet_position(scene_position: Vector3) -> Vector3:
	return scene_position - _world_origin_offset


func _maybe_shift_floating_origin() -> void:
	if not is_instance_valid(_ship) or _ship.freeze:
		_origin_dwell_frames = 0
		return
	if _ship.global_position.length() <= FLOATING_ORIGIN_THRESHOLD_M:
		_origin_dwell_frames = 0
		return
	_origin_dwell_frames += 1
	if _origin_shift_grace_remaining > 0.0:
		return
	if _origin_dwell_frames >= ORIGIN_SHIFT_DWELL_FRAMES:
		_origin_dwell_frames = 0
		_origin_shift_grace_remaining = ORIGIN_SHIFT_GRACE_SECONDS
		_rebase_world_origin(-_ship.global_position)
		_update_celestial_lighting()


func _reset_subtree_physics_interpolation(root_node: Node) -> void:
	if not is_instance_valid(root_node):
		return
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if is_instance_valid(current):
			if current.has_method("reset_physics_interpolation"):
				current.call("reset_physics_interpolation")
			for child: Node in current.get_children():
				stack.append(child)


func _rebase_world_origin(delta_shift: Vector3) -> void:
	if delta_shift.length_squared() <= 0.000001:
		return
	for child: Node in get_children():
		if child is Node3D:
			var node_3d: Node3D = child as Node3D
			node_3d.position += delta_shift
			node_3d.force_update_transform()
			_reset_subtree_physics_interpolation(node_3d)
	_world_origin_offset += delta_shift
	if is_instance_valid(_ship):
		var cam_ctrl: Node = _ship.get_node_or_null("CameraController")
		if is_instance_valid(cam_ctrl) and cam_ctrl.has_method("notify_origin_shifted"):
			cam_ctrl.call("notify_origin_shifted", delta_shift)


func cycle_surface_waypoint() -> int:
	_active_waypoint_index = (_active_waypoint_index + 1) % 2
	return _active_waypoint_index


func set_active_waypoint_index(index: int) -> void:
	_active_waypoint_index = posmod(index, 2)


func get_surface_navigation_telemetry(ship_world_pos: Vector3, ship_basis: Basis) -> Dictionary:
	var target_name: String = "HORIZON OUTPOST" if _active_waypoint_index == 1 else "STARPORT ALPHA"
	var target_dir: Vector3 = get_outpost_direction() if _active_waypoint_index == 1 else Vector3.UP
	var scene_planet_center: Vector3 = get_scene_planet_center()
	var target_pos: Vector3 = get_spherical_surface_point(target_dir) + _world_origin_offset

	var ship_radial: Vector3 = ship_world_pos - scene_planet_center
	var ship_dir: Vector3 = ship_radial.normalized() if ship_radial.length_squared() > 0.000001 else Vector3.UP
	var arc_angle: float = acos(clampf(ship_dir.dot(target_dir), -1.0, 1.0))
	var surface_distance_m: float = arc_angle * PLANET_RADIUS_M
	var direct_distance_m: float = ship_world_pos.distance_to(target_pos)

	var north_world: Vector3 = Vector3(0.0, 0.0, -1.0)
	var east_world: Vector3 = Vector3.RIGHT
	if is_instance_valid(_environment_manager) and _environment_manager.has_method("get_local_frame"):
		var frame: Dictionary = _environment_manager.call("get_local_frame", ship_world_pos) as Dictionary
		north_world = Vector3(frame.get("north_world", north_world))
		east_world = Vector3(frame.get("east_world", east_world))

	var to_target_tangent: Vector3 = (target_dir - ship_dir * ship_dir.dot(target_dir))
	var target_bearing_deg: float = 0.0
	if to_target_tangent.length_squared() > 0.000001:
		var tangent_dir: Vector3 = to_target_tangent.normalized()
		var n_comp: float = tangent_dir.dot(north_world)
		var e_comp: float = tangent_dir.dot(east_world)
		target_bearing_deg = fposmod(rad_to_deg(atan2(e_comp, n_comp)), 360.0)

	var ship_fwd: Vector3 = -ship_basis.orthonormalized().z
	var ship_fwd_tangent: Vector3 = ship_fwd - ship_dir * ship_dir.dot(ship_fwd)
	var ship_heading_deg: float = 0.0
	if ship_fwd_tangent.length_squared() > 0.000001:
		var hf: Vector3 = ship_fwd_tangent.normalized()
		ship_heading_deg = fposmod(rad_to_deg(atan2(hf.dot(east_world), hf.dot(north_world))), 360.0)

	var relative_bearing_deg: float = wrapf(target_bearing_deg - ship_heading_deg, -180.0, 180.0)

	return {
		"nav_waypoint_index": _active_waypoint_index,
		"nav_target_name": target_name,
		"nav_surface_distance_m": surface_distance_m,
		"nav_direct_distance_m": direct_distance_m,
		"nav_target_bearing_deg": target_bearing_deg,
		"nav_relative_bearing_deg": relative_bearing_deg,
		"nav_target_world_pos": target_pos,
	}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.keycode == KEY_BACKSPACE or key_ev.physical_keycode == KEY_BACKSPACE:
			reset_to_starport()
			get_viewport().set_input_as_handled()


func seat_pilot_immediately() -> void:
	if not is_instance_valid(_ship) or not is_instance_valid(_player):
		return
	if _ship.has_method("is_pilot_ready") and bool(_ship.call("is_pilot_ready")):
		return
	var seat_anchor: Node3D = _ship.get("seat_anchor") as Node3D
	var cockpit_camera: Camera3D = _ship.get("cockpit_camera") as Camera3D
	var hull_visual: Node3D = _ship.get("hull_visual") as Node3D
	var cockpit_interior: Node3D = _ship.get("cockpit_interior") as Node3D
	var body_collision: CollisionShape3D = _player.get("body_collision") as CollisionShape3D
	var player_camera: Camera3D = _player.get("player_camera") as Camera3D
	var controls_label: Control = _player.get("_controls_label") as Control
	var prompt_panel: Control = _player.get("_prompt_panel") as Control

	_player.set("_piloting", true)
	_player.set("_transitioning", false)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.velocity = Vector3.ZERO
	if is_instance_valid(seat_anchor):
		_player.global_transform = seat_anchor.global_transform
	if is_instance_valid(body_collision):
		body_collision.disabled = true
	if is_instance_valid(player_camera):
		player_camera.current = false
	if is_instance_valid(cockpit_camera):
		cockpit_camera.make_current()
	if is_instance_valid(controls_label):
		controls_label.visible = false
	if is_instance_valid(prompt_panel):
		prompt_panel.visible = false
	if is_instance_valid(hull_visual):
		hull_visual.visible = false
	if is_instance_valid(cockpit_interior):
		cockpit_interior.visible = true

	_ship.set("_pilot_claimed", true)
	_ship.set("_active_pilot", _player)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func reset_to_starport() -> void:
	if not _world_origin_offset.is_zero_approx():
		_rebase_world_origin(-_world_origin_offset)
		_world_origin_offset = Vector3.ZERO
	_origin_shift_grace_remaining = ORIGIN_SHIFT_GRACE_SECONDS
	_origin_dwell_frames = 0

	if is_instance_valid(_ship):
		var spawn_xform: Transform3D = _ship_spawn.global_transform if is_instance_valid(_ship_spawn) else Transform3D(Basis.IDENTITY, Vector3(0.0, 0.755, 0.0))
		_ship.linear_velocity = Vector3.ZERO
		_ship.angular_velocity = Vector3.ZERO
		_ship.global_transform = spawn_xform
		_ship.sleeping = false
		_ship.force_update_transform()
		_reset_subtree_physics_interpolation(_ship)
		var cam_ctrl: Node = _ship.get_node_or_null("CameraController")
		if is_instance_valid(cam_ctrl) and cam_ctrl.has_method("notify_origin_shifted"):
			cam_ctrl.call("notify_origin_shifted", Vector3.ZERO)
	if is_instance_valid(_player):
		var piloting: bool = _player.has_method("is_piloting") and bool(_player.call("is_piloting"))
		if not piloting:
			var player_xform: Transform3D = _player_spawn.global_transform if is_instance_valid(_player_spawn) else Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 7.0))
			_player.velocity = Vector3.ZERO
			_player.global_transform = player_xform
			_player.force_update_transform()
			_reset_subtree_physics_interpolation(_player)
	_update_celestial_lighting()
	_update_atmosphere_sky_and_fog()


static func calculate_terrain_height_m(x_m: float, z_m: float) -> float:
	var r: float = sqrt(x_m * x_m + z_m * z_m)
	if r <= STARPORT_FLAT_RADIUS_M:
		return -0.02
	var angle: float = atan2(z_m, x_m)
	var foothill_t: float = clampf((r - STARPORT_FLAT_RADIUS_M) / 220.0, 0.0, 1.0)
	var foothill_smooth: float = foothill_t * foothill_t * (3.0 - 2.0 * foothill_t)
	var rolling: float = (
		sin(x_m * 0.011 + 0.4) * cos(z_m * 0.010 - 0.3) * 14.0
		+ sin((x_m + z_m) * 0.017) * 7.5
		+ cos(x_m * 0.029 - z_m * 0.023) * 4.0
	)
	var ridge_t: float = clampf((r - RIDGE_START_RADIUS_M) / 480.0, 0.0, 1.0)
	var ridge_smooth: float = ridge_t * ridge_t * (3.0 - 2.0 * ridge_t)
	var ridge_ring: float = (
		88.0
		+ sin(angle * 5.0 + 0.8) * 34.0
		+ cos(angle * 9.0 - 0.5) * 22.0
		+ sin(x_m * 0.008) * cos(z_m * 0.009) * 26.0
	)
	var north_corridor_mask: float = 1.0
	if z_m < 0.0 and absf(x_m) < 160.0 and r > FOOTHILL_START_RADIUS_M:
		north_corridor_mask = clampf((absf(x_m) - 55.0) / 105.0, 0.2, 1.0)
	var outer_plateau_t: float = clampf((r - 2200.0) / 1400.0, 0.0, 1.0)
	var outer_plateau_smooth: float = outer_plateau_t * outer_plateau_t * (3.0 - 2.0 * outer_plateau_t)
	var base_height_m: float = (rolling * foothill_smooth + ridge_ring * ridge_smooth) * north_corridor_mask
	var horizon_shelf_m: float = 44.0 + sin(angle * 4.0 + 0.5) * 16.0 + cos(x_m * 0.002 + z_m * 0.002) * 10.0
	var height_m: float = lerpf(base_height_m, horizon_shelf_m, outer_plateau_smooth)
	return maxf(height_m, -1.5)


static func calculate_spherical_height_m(unit_dir: Vector3) -> float:
	var d: Vector3 = unit_dir.normalized() if unit_dir.length_squared() > 0.000001 else Vector3.UP

	var dune_sea: float = (
		sin(d.x * 16.0 + 0.6) * cos(d.z * 14.0 - 0.4) * 125.0
		+ sin((d.x + d.y) * 28.0 - 0.8) * cos(d.z * 24.0) * 75.0
	)
	var canyons: float = (
		absf(sin(d.x * 46.0 + d.z * 34.0 + cos(d.y * 38.0))) * 150.0
		+ cos(d.y * 62.0 - d.x * 52.0) * 48.0
	)
	var detail: float = sin(d.x * 120.0) * cos(d.z * 110.0 + d.y * 95.0) * 24.0
	var global_h: float = maxf(dune_sea + canyons + detail - 20.0, -14.0)

	var outpost_dir: Vector3 = OUTPOST_DIRECTION.normalized()
	var outpost_arc_m: float = acos(clampf(d.dot(outpost_dir), -1.0, 1.0)) * PLANET_RADIUS_M
	if outpost_arc_m < OUTPOST_BLEND_ARC_M:
		var out_t: float = clampf((outpost_arc_m - OUTPOST_FLAT_ARC_M) / maxf(OUTPOST_BLEND_ARC_M - OUTPOST_FLAT_ARC_M, 1.0), 0.0, 1.0)
		var out_smooth: float = out_t * out_t * (3.0 - 2.0 * out_t)
		global_h = lerpf(OUTPOST_BASE_HEIGHT_M, global_h, out_smooth)

	var polar_arc_m: float = acos(clampf(d.y, -1.0, 1.0)) * PLANET_RADIUS_M
	if polar_arc_m < 4800.0 and d.y > 0.90:
		var local_x: float = d.x * PLANET_RADIUS_M / maxf(d.y, 0.1)
		var local_z: float = d.z * PLANET_RADIUS_M / maxf(d.y, 0.1)
		var starport_h: float = calculate_terrain_height_m(local_x, local_z)
		var pole_t: float = clampf((polar_arc_m - 2600.0) / 2200.0, 0.0, 1.0)
		var pole_smooth: float = pole_t * pole_t * (3.0 - 2.0 * pole_t)
		return lerpf(starport_h, global_h, pole_smooth)

	return global_h


func _create_materials() -> void:
	_terrain_material = StandardMaterial3D.new()
	_terrain_material.vertex_color_use_as_albedo = true
	_terrain_material.roughness = 0.94
	_terrain_material.metallic = 0.01

	_structure_material = StandardMaterial3D.new()
	_structure_material.albedo_color = Color(0.56, 0.51, 0.43, 1.0)
	_structure_material.roughness = 0.86
	_structure_material.metallic = 0.08

	_trim_material = StandardMaterial3D.new()
	_trim_material.albedo_color = Color(0.74, 0.50, 0.22, 1.0)
	_trim_material.roughness = 0.72

	_glass_material = StandardMaterial3D.new()
	_glass_material.albedo_color = Color(0.14, 0.25, 0.32, 1.0)
	_glass_material.roughness = 0.22
	_glass_material.metallic = 0.35

	_beacon_lamp_material = StandardMaterial3D.new()
	_beacon_lamp_material.albedo_color = Color(1.0, 0.42, 0.16, 1.0)
	_beacon_lamp_material.emission_enabled = true
	_beacon_lamp_material.emission = Color(1.0, 0.28, 0.08, 1.0)
	_beacon_lamp_material.emission_energy_multiplier = 1.6

	_marking_yellow = StandardMaterial3D.new()
	_marking_yellow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marking_yellow.albedo_color = Color(0.91, 0.66, 0.22, 1.0)

	_marking_white = StandardMaterial3D.new()
	_marking_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marking_white.albedo_color = Color(0.84, 0.85, 0.80, 1.0)

	var halo_shader: Shader = Shader.new()
	halo_shader.code = HALO_SHADER_CODE
	_halo_material = ShaderMaterial.new()
	_halo_material.shader = halo_shader
	_halo_material.set_shader_parameter("atmo_color", Vector3(0.16, 0.52, 1.0))
	_halo_material.set_shader_parameter("sun_dir_world", Vector3(0.4, 0.6, -0.6))
	_halo_material.set_shader_parameter("halo_alpha", 0.0)

	_star_disc_material = StandardMaterial3D.new()
	_star_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_disc_material.albedo_color = Color(1.0, 0.97, 0.89, 1.0)
	_star_disc_material.disable_fog = true

	_night_star_material = StandardMaterial3D.new()
	_night_star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_night_star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_night_star_material.albedo_color = Color(0.88, 0.92, 1.0, 0.0)
	_night_star_material.disable_fog = true


func _build_terrain() -> void:
	var terrain_body: StaticBody3D = StaticBody3D.new()
	terrain_body.name = "PlanetaryTerrain"
	terrain_body.collision_layer = 1
	terrain_body.collision_mask = 1
	add_child(terrain_body)

	var basin_mesh: ArrayMesh = _generate_basin_array_mesh(TERRAIN_EXTENT_M, VISUAL_GRID_SEGMENTS)
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = basin_mesh
	mesh_instance.material_override = _terrain_material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_body.add_child(mesh_instance)

	var basin_faces: PackedVector3Array = _generate_basin_collision_faces(TERRAIN_EXTENT_M, COLLISION_GRID_SEGMENTS)
	var basin_concave: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	basin_concave.set_faces(basin_faces)
	var basin_collision: CollisionShape3D = CollisionShape3D.new()
	basin_collision.name = "TerrainCollision"
	basin_collision.shape = basin_concave
	terrain_body.add_child(basin_collision)

	var sphere_mesh: ArrayMesh = _generate_cube_sphere_array_mesh(SPHERE_FACE_VISUAL_SEGMENTS)
	var sphere_instance: MeshInstance3D = MeshInstance3D.new()
	sphere_instance.name = "SphereTerrainMesh"
	sphere_instance.mesh = sphere_mesh
	sphere_instance.material_override = _terrain_material
	sphere_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain_body.add_child(sphere_instance)

	var sphere_faces: PackedVector3Array = _generate_cube_sphere_collision_faces(SPHERE_FACE_COLLISION_SEGMENTS)
	var sphere_concave: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	sphere_concave.set_faces(sphere_faces)
	var sphere_collision: CollisionShape3D = CollisionShape3D.new()
	sphere_collision.name = "SphereTerrainCollision"
	sphere_collision.shape = sphere_concave
	terrain_body.add_child(sphere_collision)


static func _basin_vertex_world(x_m: float, z_m: float) -> Vector3:
	var r_d: float = float(PLANET_RADIUS_M)
	var px: float = float(x_m)
	var pz: float = float(z_m)
	var inv_len: float = 1.0 / sqrt(px * px + r_d * r_d + pz * pz)
	var dir: Vector3 = Vector3(px * inv_len, r_d * inv_len, pz * inv_len)
	var h: float = calculate_spherical_height_m(dir)
	var polar_arc_m: float = acos(clampf(dir.y, -1.0, 1.0)) * PLANET_RADIUS_M
	if polar_arc_m > BASIN_SEAM_OUTER_ARC_M:
		var skirt_t: float = clampf((polar_arc_m - BASIN_SEAM_OUTER_ARC_M) / maxf(BASIN_SKIRT_OUTER_ARC_M - BASIN_SEAM_OUTER_ARC_M, 1.0), 0.0, 1.0)
		h -= skirt_t * BASIN_SEAM_TUCK_M
	return _spherical_point_relative(dir, h)


static func _cube_sphere_vertex_world(unit_dir: Vector3) -> Vector3:
	var dir: Vector3 = unit_dir.normalized()
	var h: float = calculate_spherical_height_m(dir)
	var polar_arc_m: float = acos(clampf(dir.y, -1.0, 1.0)) * PLANET_RADIUS_M
	if polar_arc_m < BASIN_SEAM_OUTER_ARC_M:
		var tuck_t: float = clampf((BASIN_SEAM_OUTER_ARC_M - polar_arc_m) / maxf(BASIN_SEAM_OUTER_ARC_M - BASIN_SEAM_INNER_ARC_M, 1.0), 0.0, 1.0)
		h -= tuck_t * BASIN_SEAM_TUCK_M
	return _spherical_point_relative(dir, h)


static func _warp_pole_param(t: float) -> float:
	return t * (0.08 + 0.92 * t * t)


func _generate_basin_array_mesh(extent_m: float, segments: int) -> ArrayMesh:
	var half: float = extent_m * 0.5
	var step: float = extent_m / float(segments)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for gz: int in range(segments):
		for gx: int in range(segments):
			var x0: float = -half + float(gx) * step
			var x1: float = x0 + step
			var z0: float = -half + float(gz) * step
			var z1: float = z0 + step

			var p00: Vector3 = _basin_vertex_world(x0, z0)
			var p10: Vector3 = _basin_vertex_world(x1, z0)
			var p01: Vector3 = _basin_vertex_world(x0, z1)
			var p11: Vector3 = _basin_vertex_world(x1, z1)

			_emit_spherical_triangle(st, p00, p10, p11)
			_emit_spherical_triangle(st, p00, p11, p01)

	st.generate_normals()
	return st.commit()


func _generate_basin_collision_faces(extent_m: float, segments: int) -> PackedVector3Array:
	var faces: PackedVector3Array = PackedVector3Array()
	faces.resize(segments * segments * 6)
	var half: float = extent_m * 0.5
	var step: float = extent_m / float(segments)
	var idx: int = 0
	for gz: int in range(segments):
		for gx: int in range(segments):
			var x0: float = -half + float(gx) * step
			var x1: float = x0 + step
			var z0: float = -half + float(gz) * step
			var z1: float = z0 + step

			var p00: Vector3 = _basin_vertex_world(x0, z0)
			var p10: Vector3 = _basin_vertex_world(x1, z0)
			var p01: Vector3 = _basin_vertex_world(x0, z1)
			var p11: Vector3 = _basin_vertex_world(x1, z1)

			faces[idx] = p00
			faces[idx + 1] = p10
			faces[idx + 2] = p11
			faces[idx + 3] = p00
			faces[idx + 4] = p11
			faces[idx + 5] = p01
			idx += 6
	return faces


static func get_cube_face_definitions() -> Array[Dictionary]:
	return [
		{"name": "+Y", "normal": Vector3(0.0, 1.0, 0.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 0.0, 1.0)},
		{"name": "-Y", "normal": Vector3(0.0, -1.0, 0.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 0.0, -1.0)},
		{"name": "+X", "normal": Vector3(1.0, 0.0, 0.0), "u": Vector3(0.0, 0.0, -1.0), "v": Vector3(0.0, -1.0, 0.0)},
		{"name": "-X", "normal": Vector3(-1.0, 0.0, 0.0), "u": Vector3(0.0, 0.0, 1.0), "v": Vector3(0.0, -1.0, 0.0)},
		{"name": "+Z", "normal": Vector3(0.0, 0.0, 1.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, -1.0, 0.0)},
		{"name": "-Z", "normal": Vector3(0.0, 0.0, -1.0), "u": Vector3(-1.0, 0.0, 0.0), "v": Vector3(0.0, -1.0, 0.0)},
	]


func _generate_cube_sphere_array_mesh(segments: int) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces_def: Array[Dictionary] = get_cube_face_definitions()
	var step: float = 2.0 / float(segments)

	for face: Dictionary in faces_def:
		var n: Vector3 = face["normal"] as Vector3
		var u_ax: Vector3 = face["u"] as Vector3
		var v_ax: Vector3 = face["v"] as Vector3
		var is_top_face: bool = str(face["name"]) == "+Y"
		for gv: int in range(segments):
			var raw_v0: float = -1.0 + float(gv) * step
			var raw_v1: float = raw_v0 + step
			var v0: float = _warp_pole_param(raw_v0) if is_top_face else raw_v0
			var v1: float = _warp_pole_param(raw_v1) if is_top_face else raw_v1
			for gu: int in range(segments):
				var raw_u0: float = -1.0 + float(gu) * step
				var raw_u1: float = raw_u0 + step
				var u0: float = _warp_pole_param(raw_u0) if is_top_face else raw_u0
				var u1: float = _warp_pole_param(raw_u1) if is_top_face else raw_u1

				var p00: Vector3 = _cube_sphere_vertex_world(n + u_ax * u0 + v_ax * v0)
				var p10: Vector3 = _cube_sphere_vertex_world(n + u_ax * u1 + v_ax * v0)
				var p01: Vector3 = _cube_sphere_vertex_world(n + u_ax * u0 + v_ax * v1)
				var p11: Vector3 = _cube_sphere_vertex_world(n + u_ax * u1 + v_ax * v1)

				_emit_spherical_triangle(st, p00, p10, p11)
				_emit_spherical_triangle(st, p00, p11, p01)

	st.generate_normals()
	return st.commit()


func _generate_cube_sphere_collision_faces(segments: int) -> PackedVector3Array:
	var faces_def: Array[Dictionary] = get_cube_face_definitions()
	var faces: PackedVector3Array = PackedVector3Array()
	faces.resize(faces_def.size() * segments * segments * 6)
	var step: float = 2.0 / float(segments)
	var idx: int = 0

	for face: Dictionary in faces_def:
		var n: Vector3 = face["normal"] as Vector3
		var u_ax: Vector3 = face["u"] as Vector3
		var v_ax: Vector3 = face["v"] as Vector3
		var is_top_face: bool = str(face["name"]) == "+Y"
		for gv: int in range(segments):
			var raw_v0: float = -1.0 + float(gv) * step
			var raw_v1: float = raw_v0 + step
			var v0: float = _warp_pole_param(raw_v0) if is_top_face else raw_v0
			var v1: float = _warp_pole_param(raw_v1) if is_top_face else raw_v1
			for gu: int in range(segments):
				var raw_u0: float = -1.0 + float(gu) * step
				var raw_u1: float = raw_u0 + step
				var u0: float = _warp_pole_param(raw_u0) if is_top_face else raw_u0
				var u1: float = _warp_pole_param(raw_u1) if is_top_face else raw_u1

				var p00: Vector3 = _cube_sphere_vertex_world(n + u_ax * u0 + v_ax * v0)
				var p10: Vector3 = _cube_sphere_vertex_world(n + u_ax * u1 + v_ax * v0)
				var p01: Vector3 = _cube_sphere_vertex_world(n + u_ax * u0 + v_ax * v1)
				var p11: Vector3 = _cube_sphere_vertex_world(n + u_ax * u1 + v_ax * v1)

				faces[idx] = p00
				faces[idx + 1] = p10
				faces[idx + 2] = p11
				faces[idx + 3] = p00
				faces[idx + 4] = p11
				faces[idx + 5] = p01
				idx += 6
	return faces


static func _vertex_height_64(v: Vector3) -> float:
	var r_d: float = float(PLANET_RADIUS_M)
	var ax: float = float(v.x)
	var ay: float = float(v.y) + r_d
	var az: float = float(v.z)
	return sqrt(ax * ax + ay * ay + az * az) - r_d


func _emit_spherical_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var avg_h: float = (_vertex_height_64(a) + _vertex_height_64(b) + _vertex_height_64(c)) / 3.0
	var color: Color = _terrain_color_for_height(avg_h)
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)


static func _terrain_color_for_height(height_m: float) -> Color:
	if height_m < -4.0:
		return Color(0.68, 0.56, 0.38, 1.0)
	if height_m < 2.0:
		return Color(0.79, 0.67, 0.47, 1.0)
	if height_m < 45.0:
		return Color(0.84, 0.72, 0.50, 1.0)
	if height_m < 140.0:
		return Color(0.76, 0.61, 0.41, 1.0)
	return Color(0.71, 0.57, 0.42, 1.0)


func _build_atmosphere_halo() -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces_def: Array[Dictionary] = get_cube_face_definitions()
	var segments: int = 44
	var step: float = 2.0 / float(segments)
	for face: Dictionary in faces_def:
		var n: Vector3 = face["normal"] as Vector3
		var u_ax: Vector3 = face["u"] as Vector3
		var v_ax: Vector3 = face["v"] as Vector3
		for gv: int in range(segments):
			var v0: float = -1.0 + float(gv) * step
			var v1: float = v0 + step
			for gu: int in range(segments):
				var u0: float = -1.0 + float(gu) * step
				var u1: float = u0 + step
				var d00: Vector3 = (n + u_ax * u0 + v_ax * v0).normalized()
				var d10: Vector3 = (n + u_ax * u1 + v_ax * v0).normalized()
				var d01: Vector3 = (n + u_ax * u0 + v_ax * v1).normalized()
				var d11: Vector3 = (n + u_ax * u1 + v_ax * v1).normalized()
				st.set_normal(d00); st.add_vertex(d00)
				st.set_normal(d10); st.add_vertex(d10)
				st.set_normal(d11); st.add_vertex(d11)
				st.set_normal(d00); st.add_vertex(d00)
				st.set_normal(d11); st.add_vertex(d11)
				st.set_normal(d01); st.add_vertex(d01)

	_atmosphere_halo = MeshInstance3D.new()
	_atmosphere_halo.name = "AtmosphereHalo"
	_atmosphere_halo.position = PLANET_CENTER
	_atmosphere_halo.scale = Vector3.ONE * ATMOSPHERE_HALO_RADIUS_M
	_atmosphere_halo.mesh = st.commit()
	_atmosphere_halo.material_override = _halo_material
	_atmosphere_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_atmosphere_halo)


func _build_celestial_sky_rig() -> void:
	_celestial_sky_rig = Node3D.new()
	_celestial_sky_rig.name = "CelestialSkyRig"
	add_child(_celestial_sky_rig)

	var disc_sphere: SphereMesh = SphereMesh.new()
	disc_sphere.radius = 1200.0
	disc_sphere.height = 2400.0
	disc_sphere.radial_segments = 24
	disc_sphere.rings = 12
	_star_disc = MeshInstance3D.new()
	_star_disc.name = "StarDisc"
	_star_disc.mesh = disc_sphere
	_star_disc.material_override = _star_disc_material
	_star_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_celestial_sky_rig.add_child(_star_disc)

	var star_count: int = 260
	var star_box: BoxMesh = BoxMesh.new()
	star_box.size = Vector3(115.0, 115.0, 115.0)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_box
	mm.instance_count = star_count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 303101
	for idx: int in range(star_count):
		var theta: float = rng.randf_range(0.0, TAU)
		var z_dir: float = rng.randf_range(-1.0, 1.0)
		var r_xy: float = sqrt(maxf(1.0 - z_dir * z_dir, 0.0))
		var dir: Vector3 = Vector3(r_xy * cos(theta), z_dir, r_xy * sin(theta))
		var dist: float = rng.randf_range(64000.0, 78000.0)
		mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, dir * dist))
	_night_stars = MultiMeshInstance3D.new()
	_night_stars.name = "NightStarfieldMultiMesh"
	_night_stars.multimesh = mm
	_night_stars.material_override = _night_star_material
	_night_stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_celestial_sky_rig.add_child(_night_stars)


func _build_starport_markings() -> void:
	var markings: Node3D = Node3D.new()
	markings.name = "StarportMarkings"
	add_child(markings)

	_add_box_visual(markings, "PadEdgeNorth", Vector3(0.0, 0.015, -13.2), Vector3(26.4, 0.03, 0.45), _marking_yellow)
	_add_box_visual(markings, "PadEdgeSouth", Vector3(0.0, 0.015, 13.2), Vector3(26.4, 0.03, 0.45), _marking_yellow)
	_add_box_visual(markings, "PadEdgeWest", Vector3(-13.2, 0.015, 0.0), Vector3(0.45, 0.03, 26.4), _marking_yellow)
	_add_box_visual(markings, "PadEdgeEast", Vector3(13.2, 0.015, 0.0), Vector3(0.45, 0.03, 26.4), _marking_yellow)

	_add_box_visual(markings, "PadCenterline", Vector3(0.0, 0.018, -4.5), Vector3(0.35, 0.03, 14.0), _marking_white)
	_add_box_visual(markings, "PadCrossbar", Vector3(0.0, 0.018, 0.0), Vector3(8.5, 0.03, 0.45), _marking_white)

	for step_idx: int in range(6):
		var z_pos: float = -24.0 - float(step_idx) * 18.0
		_add_box_visual(markings, "ApproachStripe_%d" % step_idx, Vector3(0.0, 0.012, z_pos), Vector3(0.6, 0.025, 8.0), _marking_yellow)

	var pad_label: Label3D = Label3D.new()
	pad_label.name = "StarportLabel"
	pad_label.text = "MOS EISLEY ALPHA · PAD 01 · HDG 000 N"
	pad_label.position = Vector3(0.0, 0.06, 15.8)
	pad_label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	pad_label.font_size = 42
	pad_label.pixel_size = 0.022
	pad_label.modulate = Color(0.92, 0.88, 0.74, 0.96)
	pad_label.outline_size = 6
	markings.add_child(pad_label)


func _build_starport_structures() -> void:
	var structures: Node3D = Node3D.new()
	structures.name = "StarportStructures"
	add_child(structures)

	_add_static_box(structures, "ControlTowerBase", Vector3(-34.0, 6.0, -18.0), Vector3(9.0, 12.0, 9.0), _structure_material)
	_add_static_box(structures, "ControlTowerCab", Vector3(-34.0, 13.8, -18.0), Vector3(11.0, 3.6, 11.0), _glass_material)
	_add_static_box(structures, "ControlTowerRoof", Vector3(-34.0, 16.0, -18.0), Vector3(11.6, 0.8, 11.6), _trim_material)

	_add_static_box(structures, "CargoHangarBody", Vector3(38.0, 4.5, -24.0), Vector3(22.0, 9.0, 28.0), _structure_material)
	_add_box_visual(structures, "CargoHangarTrim", Vector3(38.0, 9.2, -24.0), Vector3(22.6, 0.6, 28.6), _trim_material)

	_add_static_box(structures, "ServiceBlock", Vector3(28.0, 2.2, 22.0), Vector3(12.0, 4.4, 8.0), _structure_material)
	_add_static_box(structures, "FuelTankA", Vector3(24.0, 2.5, 32.0), Vector3(3.6, 5.0, 3.6), _trim_material)
	_add_static_box(structures, "FuelTankB", Vector3(30.0, 2.5, 32.0), Vector3(3.6, 5.0, 3.6), _trim_material)


func _build_approach_beacons() -> void:
	var beacons: Node3D = Node3D.new()
	beacons.name = "ApproachBeacons"
	add_child(beacons)

	var beacon_positions: Array[Vector3] = [
		Vector3(-18.0, 0.0, -18.0),
		Vector3(18.0, 0.0, -18.0),
		Vector3(-18.0, 0.0, 18.0),
		Vector3(18.0, 0.0, 18.0),
		Vector3(-24.0, 0.0, -120.0),
		Vector3(24.0, 0.0, -120.0),
	]
	for idx: int in range(beacon_positions.size()):
		var pos: Vector3 = beacon_positions[idx]
		var ground_y: float = get_spherical_surface_point_xz(pos.x, pos.z).y
		var mast_height: float = 8.0 if idx < 4 else 16.0
		_add_static_box(beacons, "BeaconMast_%d" % idx, Vector3(pos.x, ground_y + mast_height * 0.5, pos.z), Vector3(0.65, mast_height, 0.65), _structure_material)
		_add_box_visual(beacons, "BeaconLamp_%d" % idx, Vector3(pos.x, ground_y + mast_height + 0.45, pos.z), Vector3(1.1, 0.9, 1.1), _beacon_lamp_material)


func _build_near_outcrops() -> void:
	var outcrops: Node3D = Node3D.new()
	outcrops.name = "ParallaxOutcrops"
	add_child(outcrops)

	var specs: Array[Dictionary] = [
		{"pos": Vector3(-165.0, 0.0, -90.0), "size": Vector3(18.0, 14.0, 22.0)},
		{"pos": Vector3(180.0, 0.0, -140.0), "size": Vector3(24.0, 18.0, 20.0)},
		{"pos": Vector3(-190.0, 0.0, 140.0), "size": Vector3(26.0, 16.0, 24.0)},
		{"pos": Vector3(175.0, 0.0, 165.0), "size": Vector3(20.0, 15.0, 22.0)},
	]
	for idx: int in range(specs.size()):
		var entry: Dictionary = specs[idx]
		var pos: Vector3 = entry["pos"] as Vector3
		var box_size: Vector3 = entry["size"] as Vector3
		var surf_pt: Vector3 = get_spherical_surface_point_xz(pos.x, pos.z)
		_add_static_box(outcrops, "Outcrop_%d" % idx, surf_pt + Vector3.UP * (box_size.y * 0.4), box_size, _structure_material)


func _build_horizon_outpost() -> void:
	var outpost_dir: Vector3 = get_outpost_direction()
	var outpost_pos: Vector3 = get_spherical_surface_point(outpost_dir)
	var up_world: Vector3 = outpost_dir
	var north_ref: Vector3 = Vector3(0.0, 0.0, -1.0)
	var north_world: Vector3 = (north_ref - up_world * north_ref.dot(up_world)).normalized()
	var east_world: Vector3 = north_world.cross(up_world).normalized()
	north_world = up_world.cross(east_world).normalized()

	var outpost: Node3D = Node3D.new()
	outpost.name = "HorizonOutpost"
	outpost.transform = Transform3D(Basis(east_world, up_world, -north_world), outpost_pos)
	add_child(outpost)

	_add_static_box(outpost, "OutpostPad", Vector3(0.0, 0.15, 0.0), Vector3(24.0, 0.4, 24.0), _structure_material)
	_add_box_visual(outpost, "OutpostPadTrimN", Vector3(0.0, 0.37, -11.4), Vector3(22.4, 0.04, 0.45), _marking_yellow)
	_add_box_visual(outpost, "OutpostPadTrimS", Vector3(0.0, 0.37, 11.4), Vector3(22.4, 0.04, 0.45), _marking_yellow)
	_add_static_box(outpost, "OutpostHabModule", Vector3(-26.0, 3.0, -10.0), Vector3(14.0, 6.0, 18.0), _structure_material)
	_add_box_visual(outpost, "OutpostHabTrim", Vector3(-26.0, 6.2, -10.0), Vector3(14.4, 0.5, 18.4), _trim_material)
	_add_static_box(outpost, "OutpostCommsMast", Vector3(22.0, 9.0, -14.0), Vector3(1.8, 18.0, 1.8), _structure_material)
	_add_box_visual(outpost, "OutpostBeaconLamp", Vector3(22.0, 18.8, -14.0), Vector3(2.4, 1.6, 2.4), _beacon_lamp_material)

	var label: Label3D = Label3D.new()
	label.name = "OutpostLabel"
	label.text = "HORIZON OUTPOST · SURVEY PAD 02"
	label.position = Vector3(0.0, 0.42, 13.5)
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.font_size = 38
	label.pixel_size = 0.022
	label.modulate = Color(0.92, 0.88, 0.74, 0.96)
	label.outline_size = 6
	outpost.add_child(label)


func _add_box_visual(parent: Node3D, node_name: String, pos: Vector3, box_size: Vector3, material: Material) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _add_static_box(parent: Node3D, node_name: String, pos: Vector3, box_size: Vector3, material: Material) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = box_size
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)


func _cache_sky_and_environment() -> void:
	if is_instance_valid(_world_environment) and _world_environment.environment != null:
		_world_env_resource = _world_environment.environment
		_base_fog_density = _world_env_resource.fog_density
		if _world_env_resource.sky != null and _world_env_resource.sky.sky_material is ProceduralSkyMaterial:
			_sky_material = _world_env_resource.sky.sky_material as ProceduralSkyMaterial


func _cache_ship_cameras() -> void:
	_ship_cameras.clear()
	_camera_base_near_by_id.clear()
	if not is_instance_valid(_ship):
		return
	var stack: Array[Node] = [_ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Camera3D:
			var cam: Camera3D = node as Camera3D
			_ship_cameras.append(cam)
			_camera_base_near_by_id[cam.get_instance_id()] = cam.near
		for child: Node in node.get_children():
			stack.append(child)


func _get_active_viewer_position() -> Vector3:
	for cam: Camera3D in _ship_cameras:
		if is_instance_valid(cam) and cam.current:
			return cam.global_position
	if is_instance_valid(_ship):
		return _ship.global_position
	return Vector3.ZERO


func _update_celestial_lighting() -> void:
	_celestial_state = SOLAR_SYSTEM_LOADER.evaluate_system_state(_system_data, _get_active_celestial_elapsed_seconds())
	if not bool(_celestial_state.get("valid", false)):
		return

	var sun_dir: Vector3 = Vector3(_celestial_state.get("surface_sun_dir_to_star", Vector3.UP)).normalized()
	var elev_deg: float = float(_celestial_state.get("surface_solar_elevation_deg", 18.0))
	var base_intensity: float = float(_celestial_state.get("star_light_intensity", 1.0))
	var base_color: Color = Color(_celestial_state.get("star_light_color", Color(1.0, 0.96, 0.90, 1.0)))
	var disc_color: Color = Color(_celestial_state.get("star_disc_color", Color(1.0, 0.97, 0.89, 1.0)))
	var disc_ang_rad: float = deg_to_rad(float(_celestial_state.get("star_disc_angular_radius_deg", 0.95)))

	var horizon_atten: float = 1.0 if elev_deg >= 2.0 else clampf((elev_deg + 3.0) / 5.0, 0.0, 1.0)
	if is_instance_valid(_sun_light):
		SOLAR_SYSTEM_LOADER.orient_directional_light(_sun_light, sun_dir)
		_sun_light.light_color = base_color
		_sun_light.light_energy = base_intensity * horizon_atten

	if is_instance_valid(_celestial_sky_rig):
		_celestial_sky_rig.global_position = _get_active_viewer_position()

	if is_instance_valid(_star_disc):
		var disc_radius_scale: float = (STAR_DISC_VISUAL_DISTANCE_M * tan(disc_ang_rad)) / 1200.0
		_star_disc.position = sun_dir * STAR_DISC_VISUAL_DISTANCE_M
		_star_disc.scale = Vector3.ONE * clampf(disc_radius_scale, 0.2, 5.0)
		_star_disc.visible = horizon_atten > 0.01 or _sky_transition_progress > 0.25
		if _star_disc_material != null:
			_star_disc_material.albedo_color = disc_color


func _update_atmosphere_sky_and_fog() -> void:
	if _world_env_resource == null:
		return
	var altitude_m: float = 0.0
	var atmo_cfg: Dictionary = ATMOSPHERE_MODEL.get_preset("DESERT_TATOOINE")
	var scene_planet_center: Vector3 = get_scene_planet_center()
	if is_instance_valid(_ship):
		var ship_rx: float = float(_ship.global_position.x) - float(scene_planet_center.x)
		var ship_ry: float = float(_ship.global_position.y) - float(scene_planet_center.y)
		var ship_rz: float = float(_ship.global_position.z) - float(scene_planet_center.z)
		altitude_m = sqrt(ship_rx * ship_rx + ship_ry * ship_ry + ship_rz * ship_rz) - float(PLANET_RADIUS_M)
	if is_instance_valid(_environment_manager):
		if is_instance_valid(_ship) and _environment_manager.has_method("get_local_frame"):
			var frame: Dictionary = _environment_manager.call("get_local_frame", _ship.global_position) as Dictionary
			altitude_m = float(frame.get("altitude_m", altitude_m))
		if _environment_manager.has_method("get_atmosphere_conditions"):
			var atmo: Dictionary = _environment_manager.call("get_atmosphere_conditions", altitude_m) as Dictionary
			if atmo.has("atmosphere_config") and atmo["atmosphere_config"] is Dictionary:
				atmo_cfg = atmo["atmosphere_config"] as Dictionary

	var elev_deg: float = float(_celestial_state.get("surface_solar_elevation_deg", 18.0))
	var sky_eval: Dictionary = ATMOSPHERE_MODEL.evaluate_sky_colors(atmo_cfg, altitude_m, elev_deg)
	var sky_t: float = float(sky_eval.get("sky_transition_progress", 0.0))
	_sky_transition_progress = sky_t

	if _sky_material != null:
		_sky_material.sky_top_color = sky_eval.get("sky_top_color", Color(0.20, 0.48, 0.80, 1.0)) as Color
		_sky_material.sky_horizon_color = sky_eval.get("sky_horizon_color", Color(0.87, 0.84, 0.74, 1.0)) as Color
		_sky_material.sky_curve = float(sky_eval.get("sky_curve", 0.085))
		_sky_material.ground_horizon_color = sky_eval.get("ground_horizon_color", Color(0.84, 0.77, 0.62, 1.0)) as Color
		_sky_material.ground_bottom_color = sky_eval.get("ground_bottom_color", Color(0.56, 0.44, 0.28, 1.0)) as Color

	_world_env_resource.fog_density = _base_fog_density * float(sky_eval.get("fog_density_factor", 1.0))
	_world_env_resource.fog_light_color = sky_eval.get("sky_horizon_color", Color(0.87, 0.84, 0.74, 1.0)) as Color
	_world_env_resource.ambient_light_energy = float(sky_eval.get("ambient_light_energy", 0.68))

	if _night_star_material != null and is_instance_valid(_night_stars):
		var star_vis: float = float(sky_eval.get("star_visibility", 0.0))
		_night_star_material.albedo_color = Color(0.88, 0.92, 1.0, star_vis * 0.92)
		_night_stars.visible = star_vis > 0.03

	if _halo_material != null:
		var halo_alpha: float = float(sky_eval.get("halo_alpha", 0.0))
		var sun_dir: Vector3 = Vector3(_celestial_state.get("surface_sun_dir_to_star", Vector3.UP)).normalized()
		var limb_col: Color = sky_eval.get("limb_rim_color", Color(0.16, 0.52, 1.0, 1.0)) as Color
		_halo_material.set_shader_parameter("halo_alpha", halo_alpha)
		_halo_material.set_shader_parameter("sun_dir_world", sun_dir)
		_halo_material.set_shader_parameter("atmo_color", Vector3(limb_col.r, limb_col.g, limb_col.b))
	if is_instance_valid(_atmosphere_halo):
		_atmosphere_halo.visible = altitude_m > 5500.0 and bool(atmo_cfg.get("has_atmosphere", true))

	if _ship_cameras.is_empty():
		_cache_ship_cameras()
	var alt_pos: float = maxf(altitude_m, 0.0)
	var horizon_m: float = sqrt(alt_pos * (2.0 * PLANET_RADIUS_M + alt_pos))
	var target_far: float = clampf(maxf(95000.0, horizon_m * 1.12 + 12000.0), 95000.0, 250000.0)
	var ext_near: float = clampf(target_far / MAX_DEPTH_CLIP_RATIO, 0.35, 1.15)
	for cam: Camera3D in _ship_cameras:
		if is_instance_valid(cam):
			cam.far = target_far
			var base_near: float = float(_camera_base_near_by_id.get(cam.get_instance_id(), 0.05))
			if cam.name == "ExternalCamera":
				cam.near = maxf(base_near, ext_near)
			else:
				cam.near = base_near
