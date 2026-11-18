extends Node3D
class_name StationLocalSpaceEnvironment

## Phase 3J / 4A local-space orbital cube station scene controller.
## Keeps OrbitalStationBody at local (0,0,0), drives KeyLight 1:1 from JSON
## star lighting, and renders a 64x64 cube-sphere Tatooine globe with analytical
## fragment normals + sharp desert bands + tight 1.020 cobalt Fresnel limb halo
## sweeping cleanly across the upper-left sky like Star Wars low orbit.

signal docking_zone_entered(visit_count: int)
signal docking_zone_exited(visit_count: int)

const DEFAULT_STATION_DEF_PATH: String = "res://data/stations/orbital_cube_station.tres"
const SOLAR_SYSTEM_LOADER = preload("res://scripts/solar_system_loader.gd")

const PLANET_BACKDROP_DISTANCE_M: float = 28000.0
const STAR_DISC_DISTANCE_M: float = 48000.0

const PLANET_GLOBE_SHADER_CODE: String = """shader_type spatial;
render_mode unshaded;

uniform vec3 sun_dir_world = vec3(0.5, 0.3, -0.8);
uniform vec3 atmo_color = vec3(0.16, 0.52, 1.0);
uniform vec3 surface_tint = vec3(0.85, 0.68, 0.44);

varying vec3 v_local_dir;
varying vec3 v_world_pos;
varying vec3 v_center_world;

void vertex() {
	v_local_dir = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 d = normalize(v_local_dir);
	vec3 n = normalize(v_world_pos - v_center_world);
	vec3 l = normalize(sun_dir_world);
	vec3 v_world = normalize(CAMERA_POSITION_WORLD - v_world_pos);

	float n_dot_l = dot(n, l);
	float diffuse = smoothstep(-0.06, 0.30, n_dot_l) * (0.24 + 0.76 * max(n_dot_l, 0.0));

	float band_warp = sin(d.x * 6.4 + d.z * 5.2) * 0.14 + cos(d.z * 14.0 - d.y * 9.5) * 0.06;
	float lat = d.y + band_warp;
	float bands = sin(lat * 32.0) * 0.5 + 0.5;
	float dunes = sin(d.x * 26.0 + d.z * 21.0 + lat * 15.0) * 0.5 + 0.5;

	vec3 desert_light = surface_tint * vec3(1.10, 1.03, 0.92);
	vec3 desert_mid = surface_tint * vec3(0.90, 0.79, 0.68);
	vec3 desert_deep = surface_tint * vec3(0.62, 0.49, 0.42);
	vec3 ground = mix(desert_mid, desert_light, smoothstep(0.22, 0.80, bands));
	ground = mix(ground, desert_deep, smoothstep(0.52, 0.90, dunes) * 0.62);

	float mu = clamp(dot(n, v_world), 0.0, 1.0);
	float horizon_haze = pow(1.0 - mu, 5.5);
	float sun_limb = smoothstep(-0.18, 0.28, n_dot_l);
	vec3 terminator_tint = vec3(0.86, 0.46, 0.24) * smoothstep(-0.14, 0.08, n_dot_l) * (1.0 - smoothstep(0.08, 0.26, n_dot_l)) * 0.24;

	vec3 lit_surface = ground * diffuse + terminator_tint;
	vec3 color = mix(lit_surface, atmo_color * 0.92, horizon_haze * sun_limb * 0.28);
	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
}
"""

const PLANET_RIM_SHADER_CODE: String = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front;

uniform vec3 sun_dir_world = vec3(0.5, 0.3, -0.8);
uniform vec3 atmo_color = vec3(0.16, 0.52, 1.0);

varying vec3 v_world_pos;
varying vec3 v_center_world;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(v_world_pos - v_center_world);
	vec3 l = normalize(sun_dir_world);
	vec3 v_world = normalize(CAMERA_POSITION_WORLD - v_world_pos);

	float mu = clamp(-dot(n, v_world), 0.0, 1.0);
	float outer_fade = smoothstep(0.015, 0.14, mu);
	float inner_cut = 1.0 - smoothstep(0.15, 0.30, mu);
	float limb_glow = outer_fade * inner_cut;
	float sun_lit = smoothstep(-0.20, 0.28, dot(n, l));

	ALBEDO = atmo_color * (0.48 + 0.92 * sun_lit);
	ALPHA = clamp(limb_glow * (0.14 + 0.86 * sun_lit) * 0.88, 0.0, 1.0);
}
"""

@export var station_definition: Resource

var _hull_material: StandardMaterial3D
var _frame_material: StandardMaterial3D
var _bay_material: StandardMaterial3D
var _beacon_amber_material: StandardMaterial3D
var _beacon_cyan_material: StandardMaterial3D
var _planet_globe_material: ShaderMaterial
var _planet_rim_material: ShaderMaterial
var _star_material: StandardMaterial3D
var _star_disc_material: StandardMaterial3D

var _station_body: StaticBody3D
var _docking_trigger: Area3D
var _backdrop_rig: Node3D
var _planet_visual: Node3D
var _planet_globe_mesh: MeshInstance3D
var _planet_rim_mesh: MeshInstance3D
var _star_disc: MeshInstance3D
var _ship_cameras: Array[Camera3D] = []

var _system_data: Dictionary = {}
var _celestial_state: Dictionary = {}
var _celestial_time_override_seconds: float = -1.0

var _ship_in_docking_zone: bool = false
var _docking_visit_count: int = 0

@onready var _environment_manager: Node = get_node_or_null("EnvironmentManager")
@onready var _key_light: DirectionalLight3D = get_node_or_null("KeyLight") as DirectionalLight3D
@onready var _rim_fill_light: DirectionalLight3D = get_node_or_null("RimFillLight") as DirectionalLight3D
@onready var _ship: RigidBody3D = get_node_or_null("Ship") as RigidBody3D
@onready var _player: CharacterBody3D = get_node_or_null("Player") as CharacterBody3D
@onready var _arrival_marker: Marker3D = get_node_or_null("ShipArrivalPoint") as Marker3D
@onready var _player_spawn: Marker3D = get_node_or_null("PlayerSpawnPoint") as Marker3D


func _enter_tree() -> void:
	add_to_group("station_environment")


func _ready() -> void:
	process_priority = 20
	if station_definition == null and ResourceLoader.exists(DEFAULT_STATION_DEF_PATH):
		station_definition = ResourceLoader.load(DEFAULT_STATION_DEF_PATH)
	_load_solar_system()
	_create_materials()
	_build_orbital_station()
	_build_space_backdrop()
	_cache_ship_cameras()
	_update_celestial_lighting()
	call_deferred("seat_pilot_immediately")


func _process(_delta: float) -> void:
	_update_celestial_lighting()


func _load_solar_system() -> void:
	var loaded: Dictionary = SOLAR_SYSTEM_LOADER.load_system_from_file()
	if bool(loaded.get("valid", false)):
		_system_data = loaded.get("system", {}) as Dictionary
	else:
		push_warning("StationLocalSpaceEnvironment: using fallback solar system data: %s" % str(loaded.get("errors", [])))
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


func clear_celestial_time_override() -> void:
	_celestial_time_override_seconds = -1.0
	_update_celestial_lighting()


func get_celestial_telemetry() -> Dictionary:
	if _celestial_state.is_empty():
		_celestial_state = SOLAR_SYSTEM_LOADER.evaluate_system_state(_system_data, _get_active_celestial_elapsed_seconds(), get_station_id())
	var state_copy: Dictionary = _celestial_state.duplicate(true)
	state_copy["sun_light_energy"] = _key_light.light_energy if is_instance_valid(_key_light) else 1.0
	state_copy["sun_light_color"] = _key_light.light_color if is_instance_valid(_key_light) else Color.WHITE
	return state_copy


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_ev: InputEventKey = event as InputEventKey
		if key_ev.keycode == KEY_BACKSPACE or key_ev.physical_keycode == KEY_BACKSPACE:
			reset_to_arrival_point()
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


func reset_to_arrival_point() -> void:
	var arrival_xform: Transform3D = _get_arrival_transform()
	_ship_in_docking_zone = false
	if is_instance_valid(_ship):
		_ship.linear_velocity = Vector3.ZERO
		_ship.angular_velocity = Vector3.ZERO
		_ship.global_transform = arrival_xform
		_ship.sleeping = false
	if is_instance_valid(_player) and is_instance_valid(_ship):
		var seat_anchor: Node3D = _ship.get("seat_anchor") as Node3D
		if is_instance_valid(seat_anchor) and _ship.has_method("is_pilot_ready") and bool(_ship.call("is_pilot_ready")):
			_player.global_transform = seat_anchor.global_transform
		elif is_instance_valid(_player_spawn):
			_player.global_transform = _player_spawn.global_transform
	var cam_ctrl: Node = _ship.get_node_or_null("CameraController") if is_instance_valid(_ship) else null
	if is_instance_valid(cam_ctrl) and cam_ctrl.has_method("notify_origin_shifted"):
		cam_ctrl.call("notify_origin_shifted", Vector3.ZERO)
	_update_celestial_lighting()


func is_ship_in_docking_zone() -> bool:
	return _ship_in_docking_zone


func get_docking_visit_count() -> int:
	return _docking_visit_count


func get_station_size_m() -> Vector3:
	if station_definition != null and "station_size_m" in station_definition:
		return Vector3(station_definition.get("station_size_m"))
	return Vector3(120.0, 120.0, 120.0)


func get_station_display_name() -> String:
	if station_definition != null and "display_name" in station_definition:
		return str(station_definition.get("display_name"))
	return "Orbital Relay Cube 01"


func get_station_id() -> String:
	if station_definition != null and "station_id" in station_definition:
		return str(station_definition.get("station_id"))
	return "station_orbital_cube_01"


func get_station_telemetry() -> Dictionary:
	var origin_pos: Vector3 = _station_body.global_position if is_instance_valid(_station_body) else Vector3.ZERO
	var ship_pos: Vector3 = _ship.global_position if is_instance_valid(_ship) else Vector3.ZERO
	var center_dist: float = ship_pos.distance_to(origin_pos)
	var half_z: float = get_station_size_m().z * 0.5
	var face_dist: float = maxf(center_dist - half_z, 0.0)
	return {
		"station_id": get_station_id(),
		"station_name": get_station_display_name(),
		"station_distance_m": center_dist,
		"station_face_distance_m": face_dist,
		"station_in_docking_zone": _ship_in_docking_zone,
		"station_docking_visits": _docking_visit_count,
		"station_origin_world": origin_pos,
	}


func _get_arrival_transform() -> Transform3D:
	if is_instance_valid(_arrival_marker):
		return _arrival_marker.global_transform
	var offset: Vector3 = Vector3(0.0, 0.0, 450.0)
	if station_definition != null and "safe_arrival_offset_m" in station_definition:
		offset = Vector3(station_definition.get("safe_arrival_offset_m"))
	return Transform3D(Basis.IDENTITY, offset)


func _create_materials() -> void:
	_hull_material = StandardMaterial3D.new()
	_hull_material.albedo_color = Color(0.22, 0.25, 0.30, 1.0)
	_hull_material.roughness = 0.78
	_hull_material.metallic = 0.28

	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = Color(0.46, 0.51, 0.57, 1.0)
	_frame_material.roughness = 0.56
	_frame_material.metallic = 0.45

	_bay_material = StandardMaterial3D.new()
	_bay_material.albedo_color = Color(0.06, 0.08, 0.11, 1.0)
	_bay_material.roughness = 0.9

	_beacon_amber_material = StandardMaterial3D.new()
	_beacon_amber_material.albedo_color = Color(1.0, 0.68, 0.22, 1.0)
	_beacon_amber_material.emission_enabled = true
	_beacon_amber_material.emission = Color(1.0, 0.54, 0.12, 1.0)
	_beacon_amber_material.emission_energy_multiplier = 2.0

	_beacon_cyan_material = StandardMaterial3D.new()
	_beacon_cyan_material.albedo_color = Color(0.32, 0.88, 1.0, 1.0)
	_beacon_cyan_material.emission_enabled = true
	_beacon_cyan_material.emission = Color(0.24, 0.80, 0.96, 1.0)
	_beacon_cyan_material.emission_energy_multiplier = 2.2

	var globe_shader: Shader = Shader.new()
	globe_shader.code = PLANET_GLOBE_SHADER_CODE
	_planet_globe_material = ShaderMaterial.new()
	_planet_globe_material.shader = globe_shader
	_planet_globe_material.set_shader_parameter("sun_dir_world", Vector3(0.5, 0.3, -0.8))
	_planet_globe_material.set_shader_parameter("atmo_color", Vector3(0.16, 0.52, 1.0))
	_planet_globe_material.set_shader_parameter("surface_tint", Vector3(0.85, 0.68, 0.44))

	var rim_shader: Shader = Shader.new()
	rim_shader.code = PLANET_RIM_SHADER_CODE
	_planet_rim_material = ShaderMaterial.new()
	_planet_rim_material.shader = rim_shader
	_planet_rim_material.render_priority = 1
	_planet_rim_material.set_shader_parameter("sun_dir_world", Vector3(0.5, 0.3, -0.8))
	_planet_rim_material.set_shader_parameter("atmo_color", Vector3(0.16, 0.52, 1.0))

	_star_material = StandardMaterial3D.new()
	_star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_material.albedo_color = Color(0.88, 0.92, 1.0, 1.0)

	_star_disc_material = StandardMaterial3D.new()
	_star_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_disc_material.albedo_color = Color(1.0, 0.97, 0.89, 1.0)


func _build_orbital_station() -> void:
	var size: Vector3 = get_station_size_m()
	var half: Vector3 = size * 0.5

	_station_body = StaticBody3D.new()
	_station_body.name = "OrbitalStationBody"
	_station_body.collision_layer = 1
	_station_body.collision_mask = 1
	_station_body.add_to_group("jump_exclusion_origin")
	add_child(_station_body)

	var core_mesh: BoxMesh = BoxMesh.new()
	core_mesh.size = size
	var hull_instance: MeshInstance3D = MeshInstance3D.new()
	hull_instance.name = "StationCoreHull"
	hull_instance.mesh = core_mesh
	hull_instance.material_override = _hull_material
	_station_body.add_child(hull_instance)

	var hull_shape: BoxShape3D = BoxShape3D.new()
	hull_shape.size = size
	var hull_collision: CollisionShape3D = CollisionShape3D.new()
	hull_collision.name = "StationCollision"
	hull_collision.shape = hull_shape
	_station_body.add_child(hull_collision)

	var frame_root: Node3D = Node3D.new()
	frame_root.name = "StationFrameRibs"
	_station_body.add_child(frame_root)
	var rib_thick: float = 4.2
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_box_visual(frame_root, "RibX_%d_%d" % [int(sy), int(sz)], Vector3(0.0, sy * half.y, sz * half.z), Vector3(size.x + rib_thick, rib_thick, rib_thick), _frame_material)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_box_visual(frame_root, "RibY_%d_%d" % [int(sx), int(sz)], Vector3(sx * half.x, 0.0, sz * half.z), Vector3(rib_thick, size.y + rib_thick, rib_thick), _frame_material)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			_add_box_visual(frame_root, "RibZ_%d_%d" % [int(sx), int(sy)], Vector3(sx * half.x, sy * half.y, 0.0), Vector3(rib_thick, rib_thick, size.z + rib_thick), _frame_material)

	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_add_box_visual(frame_root, "CornerBeacon_%d_%d_%d" % [int(sx), int(sy), int(sz)], Vector3(sx * (half.x + 1.8), sy * (half.y + 1.8), sz * (half.z + 1.8)), Vector3(2.8, 2.8, 2.8), _beacon_amber_material)

	var dock_z: float = half.z + 0.4
	_add_box_visual(frame_root, "DockingBayPanel", Vector3(0.0, 0.0, dock_z), Vector3(36.0, 22.0, 0.6), _bay_material)
	_add_box_visual(frame_root, "DockingFrameTop", Vector3(0.0, 12.2, dock_z + 0.6), Vector3(40.0, 2.2, 1.8), _beacon_cyan_material)
	_add_box_visual(frame_root, "DockingFrameBottom", Vector3(0.0, -12.2, dock_z + 0.6), Vector3(40.0, 2.2, 1.8), _beacon_cyan_material)
	_add_box_visual(frame_root, "DockingFrameWest", Vector3(-19.0, 0.0, dock_z + 0.6), Vector3(2.2, 22.2, 1.8), _beacon_cyan_material)
	_add_box_visual(frame_root, "DockingFrameEast", Vector3(19.0, 0.0, dock_z + 0.6), Vector3(2.2, 22.2, 1.8), _beacon_cyan_material)

	for z_guide: float in [half.z + 45.0, half.z + 105.0]:
		for x_side: float in [-22.0, 22.0]:
			_add_box_visual(frame_root, "ApproachGuide_%d_%d" % [int(x_side), int(z_guide)], Vector3(x_side, 0.0, z_guide), Vector3(1.6, 1.6, 3.2), _beacon_cyan_material)

	var sign_label: Label3D = Label3D.new()
	sign_label.name = "StationSignLabel"
	sign_label.text = "%s\nDOCKING APPROACH (+Z)" % get_station_display_name().to_upper()
	sign_label.position = Vector3(0.0, 22.0, dock_z + 1.0)
	sign_label.font_size = 72
	sign_label.pixel_size = 0.08
	sign_label.modulate = Color(0.62, 0.92, 1.0, 0.95)
	sign_label.outline_size = 8
	_station_body.add_child(sign_label)

	var dock_offset: Vector3 = Vector3(0.0, 0.0, 78.0)
	var dock_size: Vector3 = Vector3(42.0, 28.0, 34.0)
	if station_definition != null:
		if "docking_zone_offset_m" in station_definition:
			dock_offset = Vector3(station_definition.get("docking_zone_offset_m"))
		if "docking_zone_size_m" in station_definition:
			dock_size = Vector3(station_definition.get("docking_zone_size_m"))

	_docking_trigger = Area3D.new()
	_docking_trigger.name = "DockingArrivalTrigger"
	_docking_trigger.position = dock_offset
	_docking_trigger.monitoring = true
	_docking_trigger.monitorable = false
	_docking_trigger.collision_layer = 0
	_docking_trigger.collision_mask = 1
	_station_body.add_child(_docking_trigger)

	var trigger_shape: BoxShape3D = BoxShape3D.new()
	trigger_shape.size = dock_size
	var trigger_col: CollisionShape3D = CollisionShape3D.new()
	trigger_col.name = "DockingZoneCollision"
	trigger_col.shape = trigger_shape
	_docking_trigger.add_child(trigger_col)

	_docking_trigger.body_entered.connect(_on_docking_trigger_body_entered)
	_docking_trigger.body_exited.connect(_on_docking_trigger_body_exited)


func _on_docking_trigger_body_entered(body: Node3D) -> void:
	if _is_ship_body(body):
		if not _ship_in_docking_zone:
			_ship_in_docking_zone = true
			_docking_visit_count += 1
			docking_zone_entered.emit(_docking_visit_count)


func _on_docking_trigger_body_exited(body: Node3D) -> void:
	if _is_ship_body(body):
		if _ship_in_docking_zone:
			_ship_in_docking_zone = false
			docking_zone_exited.emit(_docking_visit_count)


func _is_ship_body(body: Node3D) -> bool:
	if not is_instance_valid(body):
		return false
	if is_instance_valid(_ship) and body == _ship:
		return true
	return body is RigidBody3D and body.get_node_or_null("FlightController") != null


func _build_space_backdrop() -> void:
	_backdrop_rig = Node3D.new()
	_backdrop_rig.name = "SpaceBackdrop"
	add_child(_backdrop_rig)

	_planet_visual = Node3D.new()
	_planet_visual.name = "OrbitingPlanetVisual"
	_backdrop_rig.add_child(_planet_visual)

	_planet_globe_mesh = MeshInstance3D.new()
	_planet_globe_mesh.name = "PlanetGlobeMesh"
	_planet_globe_mesh.mesh = _generate_smooth_cube_sphere_mesh(1.0, 64)
	_planet_globe_mesh.material_override = _planet_globe_material
	_planet_globe_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_planet_visual.add_child(_planet_globe_mesh)

	_planet_rim_mesh = MeshInstance3D.new()
	_planet_rim_mesh.name = "PlanetAtmosphereRim"
	_planet_rim_mesh.mesh = _generate_smooth_cube_sphere_mesh(1.020, 64)
	_planet_rim_mesh.material_override = _planet_rim_material
	_planet_rim_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_planet_visual.add_child(_planet_rim_mesh)

	var disc_mesh: SphereMesh = SphereMesh.new()
	disc_mesh.radius = 520.0
	disc_mesh.height = 1040.0
	disc_mesh.radial_segments = 24
	disc_mesh.rings = 12
	_star_disc = MeshInstance3D.new()
	_star_disc.name = "StarDisc"
	_star_disc.mesh = disc_mesh
	_star_disc.material_override = _star_disc_material
	_star_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop_rig.add_child(_star_disc)

	var star_count: int = 420
	var star_box: BoxMesh = BoxMesh.new()
	star_box.size = Vector3(44.0, 44.0, 44.0)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_box
	mm.instance_count = star_count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 303501
	for idx: int in range(star_count):
		var theta: float = rng.randf_range(0.0, TAU)
		var z_dir: float = rng.randf_range(-1.0, 1.0)
		var r_xy: float = sqrt(maxf(1.0 - z_dir * z_dir, 0.0))
		var dir: Vector3 = Vector3(r_xy * cos(theta), z_dir, r_xy * sin(theta))
		var dist: float = rng.randf_range(38000.0, 56000.0)
		mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, dir * dist))
	var star_field: MultiMeshInstance3D = MultiMeshInstance3D.new()
	star_field.name = "StarfieldMultiMesh"
	star_field.multimesh = mm
	star_field.material_override = _star_material
	star_field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop_rig.add_child(star_field)


static func _generate_smooth_cube_sphere_mesh(radius_m: float, segments: int) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces_def: Array[Dictionary] = [
		{"normal": Vector3(0.0, 1.0, 0.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 0.0, 1.0)},
		{"normal": Vector3(0.0, -1.0, 0.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, 0.0, -1.0)},
		{"normal": Vector3(1.0, 0.0, 0.0), "u": Vector3(0.0, 0.0, -1.0), "v": Vector3(0.0, -1.0, 0.0)},
		{"normal": Vector3(-1.0, 0.0, 0.0), "u": Vector3(0.0, 0.0, 1.0), "v": Vector3(0.0, -1.0, 0.0)},
		{"normal": Vector3(0.0, 0.0, 1.0), "u": Vector3(1.0, 0.0, 0.0), "v": Vector3(0.0, -1.0, 0.0)},
		{"normal": Vector3(0.0, 0.0, -1.0), "u": Vector3(-1.0, 0.0, 0.0), "v": Vector3(0.0, -1.0, 0.0)},
	]
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
				st.set_normal(d00); st.add_vertex(d00 * radius_m)
				st.set_normal(d10); st.add_vertex(d10 * radius_m)
				st.set_normal(d11); st.add_vertex(d11 * radius_m)
				st.set_normal(d00); st.add_vertex(d00 * radius_m)
				st.set_normal(d11); st.add_vertex(d11 * radius_m)
				st.set_normal(d01); st.add_vertex(d01 * radius_m)
	return st.commit()


func _cache_ship_cameras() -> void:
	_ship_cameras.clear()
	if not is_instance_valid(_ship):
		return
	var stack: Array[Node] = [_ship]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Camera3D:
			var cam: Camera3D = node as Camera3D
			cam.far = maxf(cam.far, 140000.0)
			if cam.name == "ExternalCamera":
				cam.near = maxf(cam.near, 0.45)
			_ship_cameras.append(cam)
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
	_celestial_state = SOLAR_SYSTEM_LOADER.evaluate_system_state(_system_data, _get_active_celestial_elapsed_seconds(), get_station_id())
	if not bool(_celestial_state.get("valid", false)):
		return

	var star_dir: Vector3 = Vector3(_celestial_state.get("station_to_star_dir", Vector3.RIGHT)).normalized()
	var planet_dir: Vector3 = Vector3(_celestial_state.get("station_to_planet_dir", Vector3.FORWARD)).normalized()
	var planet_spin: Basis = _celestial_state.get("planet_spin_basis", Basis.IDENTITY) as Basis
	var light_color: Color = Color(_celestial_state.get("star_light_color", Color(1.0, 0.96, 0.90, 1.0)))
	var light_intensity: float = float(_celestial_state.get("star_light_intensity", 1.0))
	var disc_color: Color = Color(_celestial_state.get("star_disc_color", Color(1.0, 0.97, 0.89, 1.0)))
	var disc_ang_rad: float = deg_to_rad(float(_celestial_state.get("star_disc_angular_radius_deg", 0.95)))
	var atmo_color: Color = Color(_celestial_state.get("planet_atmosphere_color", Color(0.16, 0.52, 1.0, 1.0)))

	var p_radius: float = maxf(float(_celestial_state.get("planet_radius_m", 600000.0)), 1.0)
	var st_orbit_r: float = maxf(float(_celestial_state.get("station_orbital_radius_m", 654000.0)), p_radius + 1.0)
	var tint_arr: Array = [0.85, 0.68, 0.44]
	var planets_list: Array = _system_data.get("planets", []) as Array
	if not planets_list.is_empty() and planets_list[0] is Dictionary:
		var cand: Variant = (planets_list[0] as Dictionary).get("surface_tint", tint_arr)
		if cand is Array and (cand as Array).size() >= 3:
			tint_arr = cand as Array

	if is_instance_valid(_key_light):
		SOLAR_SYSTEM_LOADER.orient_directional_light(_key_light, star_dir)
		_key_light.light_color = light_color
		_key_light.light_energy = light_intensity
	if is_instance_valid(_rim_fill_light):
		_rim_fill_light.light_energy = 0.0
		_rim_fill_light.visible = false

	var viewer_pos: Vector3 = _get_active_viewer_position()
	if is_instance_valid(_backdrop_rig):
		_backdrop_rig.global_position = viewer_pos

	if is_instance_valid(_planet_visual):
		var visual_radius: float = clampf(PLANET_BACKDROP_DISTANCE_M * (p_radius / st_orbit_r), 200.0, PLANET_BACKDROP_DISTANCE_M * 0.96)
		var scaled_basis: Basis = planet_spin.orthonormalized().scaled_local(Vector3.ONE * visual_radius)
		_planet_visual.transform = Transform3D(scaled_basis, planet_dir * PLANET_BACKDROP_DISTANCE_M)

	var atmo_vec: Vector3 = Vector3(atmo_color.r, atmo_color.g, atmo_color.b)
	var sun_vec: Vector3 = Vector3(star_dir.x, star_dir.y, star_dir.z)
	if _planet_globe_material != null:
		_planet_globe_material.set_shader_parameter("sun_dir_world", sun_vec)
		_planet_globe_material.set_shader_parameter("atmo_color", atmo_vec)
		_planet_globe_material.set_shader_parameter("surface_tint", Vector3(float(tint_arr[0]), float(tint_arr[1]), float(tint_arr[2])))
	if _planet_rim_material != null:
		_planet_rim_material.set_shader_parameter("sun_dir_world", sun_vec)
		_planet_rim_material.set_shader_parameter("atmo_color", atmo_vec)

	if is_instance_valid(_star_disc):
		var disc_scale: float = (STAR_DISC_DISTANCE_M * tan(disc_ang_rad)) / 520.0
		_star_disc.position = star_dir * STAR_DISC_DISTANCE_M
		_star_disc.scale = Vector3.ONE * clampf(disc_scale, 0.2, 6.0)
		if _star_disc_material != null:
			_star_disc_material.albedo_color = disc_color


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
