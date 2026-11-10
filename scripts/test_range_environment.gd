extends Node3D
class_name TestRangeEnvironment

## Builds a readable flight-test landscape from lightweight procedural and
## primitive geometry. The central test area remains level; distant ridges,
## range markings and beacons provide visual references without changing the
## ship's flight model.

const GROUND_SIZE_M: float = 1000.0
const GROUND_HALF_SIZE_M: float = GROUND_SIZE_M * 0.5
const GRID_SPACING_M: float = 20.0
const RUNWAY_CENTER_Z: float = -62.0
const RUNWAY_LENGTH_M: float = 100.0
const RUNWAY_WIDTH_M: float = 18.0

var _ground_material: StandardMaterial3D
var _marking_white: StandardMaterial3D
var _marking_yellow: StandardMaterial3D
var _marking_dark: StandardMaterial3D
var _grid_material: StandardMaterial3D
var _beacon_material: StandardMaterial3D
var _beacon_lamp_material: StandardMaterial3D


func _ready() -> void:
	_create_materials()
	_configure_ground()
	_build_survey_grid()
	_build_landing_pad_markings()
	_build_approach_lane()
	_build_range_beacons()
	_build_distant_ridges()
	_build_wind_reference()


func _create_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 31847
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.48

	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.18, 0.19, 0.16, 1.0))
	color_ramp.add_point(0.38, Color(0.29, 0.28, 0.22, 1.0))
	color_ramp.add_point(0.68, Color(0.39, 0.36, 0.27, 1.0))
	color_ramp.set_color(color_ramp.get_point_count() - 1, Color(0.48, 0.43, 0.32, 1.0))

	var noise_texture := NoiseTexture2D.new()
	noise_texture.width = 512
	noise_texture.height = 512
	noise_texture.seamless = true
	noise_texture.noise = noise
	noise_texture.color_ramp = color_ramp

	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_texture = noise_texture
	_ground_material.roughness = 1.0
	_ground_material.uv1_scale = Vector3(10.0, 10.0, 1.0)

	_marking_white = _make_unshaded_material(Color(0.78, 0.79, 0.70, 0.92))
	_marking_yellow = _make_unshaded_material(Color(0.89, 0.62, 0.24, 0.96))
	_marking_dark = _make_unshaded_material(Color(0.10, 0.12, 0.12, 0.92))
	_grid_material = _make_unshaded_material(Color(0.08, 0.10, 0.09, 0.26), true)
	_beacon_material = _make_standard_material(Color(0.28, 0.31, 0.31, 1.0))
	_beacon_lamp_material = _make_standard_material(Color(1.0, 0.32, 0.16, 1.0))
	_beacon_lamp_material.emission_enabled = true
	_beacon_lamp_material.emission = Color(1.0, 0.12, 0.035, 1.0)
	_beacon_lamp_material.emission_energy_multiplier = 1.4


func _make_unshaded_material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _make_standard_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.96
	return material


func _configure_ground() -> void:
	var ground_mesh_instance := get_node_or_null("Ground/GroundMesh") as MeshInstance3D
	if ground_mesh_instance != null:
		var plane := PlaneMesh.new()
		plane.size = Vector2(GROUND_SIZE_M, GROUND_SIZE_M)
		ground_mesh_instance.mesh = plane
		ground_mesh_instance.material_override = _ground_material

	var ground_body := get_node_or_null("Ground") as StaticBody3D
	if ground_body == null:
		push_error("TestRangeEnvironment requires a StaticBody3D named Ground.")
		return

	# The scene defines four collision strips around the 14 m landing-pad opening.
	# Preserve that opening so the pad remains the only contact surface at its center.
	var collision_count: int = 0
	for child in ground_body.get_children():
		if child is CollisionShape3D:
			collision_count += 1
	if collision_count != 4:
		push_error("TestRange Ground must retain four collision strips around the landing pad.")


func _build_survey_grid() -> void:
	var grid_mesh := ImmediateMesh.new()
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _grid_material)
	var half_extent: float = GROUND_HALF_SIZE_M
	for coordinate in range(-int(half_extent), int(half_extent) + 1, int(GRID_SPACING_M)):
		# Leave the two center axes clean so the survey grid does not paint
		# over the physical landing pad and its H marking.
		if coordinate == 0:
			continue
		var value: float = float(coordinate)
		grid_mesh.surface_add_vertex(Vector3(value, 0.018, -half_extent))
		grid_mesh.surface_add_vertex(Vector3(value, 0.018, half_extent))
		grid_mesh.surface_add_vertex(Vector3(-half_extent, 0.018, value))
		grid_mesh.surface_add_vertex(Vector3(half_extent, 0.018, value))
	grid_mesh.surface_end()

	var grid_instance := MeshInstance3D.new()
	grid_instance.name = "SurveyGrid20m"
	grid_instance.mesh = grid_mesh
	grid_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid_instance)


func _build_landing_pad_markings() -> void:
	var markings := Node3D.new()
	markings.name = "LandingPadMarkings"
	add_child(markings)

	# Outer perimeter around the existing 14 m physical pad.
	_add_box(markings, "PadBorderNorth", Vector3(0.0, 0.035, -7.25), Vector3(15.0, 0.025, 0.18), _marking_yellow)
	_add_box(markings, "PadBorderSouth", Vector3(0.0, 0.035, 7.25), Vector3(15.0, 0.025, 0.18), _marking_yellow)
	_add_box(markings, "PadBorderWest", Vector3(-7.25, 0.035, 0.0), Vector3(0.18, 0.025, 14.5), _marking_yellow)
	_add_box(markings, "PadBorderEast", Vector3(7.25, 0.035, 0.0), Vector3(0.18, 0.025, 14.5), _marking_yellow)

	# High-contrast H, aiming point and centerline.
	_add_box(markings, "HLeft", Vector3(-2.25, 0.042, 0.0), Vector3(0.38, 0.028, 4.7), _marking_white)
	_add_box(markings, "HRight", Vector3(2.25, 0.042, 0.0), Vector3(0.38, 0.028, 4.7), _marking_white)
	_add_box(markings, "HCrossbar", Vector3(0.0, 0.042, 0.0), Vector3(4.9, 0.028, 0.38), _marking_white)
	_add_box(markings, "PadCenterline", Vector3(0.0, 0.042, -5.3), Vector3(0.16, 0.028, 2.0), _marking_yellow)
	_add_world_label(markings, "PadID", "PAD 01", Vector3(0.0, 0.05, 5.2), 44, 0.012, Vector3(90.0, 0.0, 0.0))


func _build_approach_lane() -> void:
	var lane := Node3D.new()
	lane.name = "ApproachLane"
	add_child(lane)
	_add_box(lane, "DarkApproachSurface", Vector3(0.0, 0.014, RUNWAY_CENTER_Z), Vector3(RUNWAY_WIDTH_M, 0.018, RUNWAY_LENGTH_M), _marking_dark)

	var edge_x: float = RUNWAY_WIDTH_M * 0.5 - 0.5
	_add_box(lane, "LeftEdgeLine", Vector3(-edge_x, 0.030, RUNWAY_CENTER_Z), Vector3(0.16, 0.02, RUNWAY_LENGTH_M), _marking_yellow)
	_add_box(lane, "RightEdgeLine", Vector3(edge_x, 0.030, RUNWAY_CENTER_Z), Vector3(0.16, 0.02, RUNWAY_LENGTH_M), _marking_yellow)

	for z_position in range(-22, -116, -9):
		_add_box(lane, "Centerline_%d" % abs(z_position), Vector3(0.0, 0.032, float(z_position)), Vector3(0.22, 0.022, 3.4), _marking_white)

	# Threshold and fixed-distance reference bars.
	_add_box(lane, "ThresholdBar", Vector3(0.0, 0.032, -18.0), Vector3(15.0, 0.022, 0.28), _marking_white)
	for distance in [25, 50, 75]:
		var z_position: float = -float(distance)
		for stripe_index in range(3):
			var x_position: float = -4.5 + float(stripe_index) * 4.5
			_add_box(lane, "Range_%dm_%d" % [distance, stripe_index], Vector3(x_position, 0.034, z_position), Vector3(2.0, 0.024, 0.16), _marking_yellow)
		_add_world_label(lane, "RangeLabel_%dm" % distance, "%d m" % distance, Vector3(-11.0, 2.2, z_position), 56, 0.012, Vector3.ZERO)


func _add_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _add_world_label(
		parent: Node3D,
		node_name: String,
		label_text: String,
		position: Vector3,
		font_size: int,
		pixel_size: float,
		rotation_degrees: Vector3
) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = label_text
	label.position = position
	label.rotation_degrees = rotation_degrees
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = Color(0.90, 0.87, 0.73, 0.96)
	label.outline_size = 5
	label.no_depth_test = false
	parent.add_child(label)


func _build_range_beacons() -> void:
	var positions: Array[Vector3] = [
		Vector3(-34.0, 0.0, -108.0),
		Vector3(34.0, 0.0, -108.0),
		Vector3(-34.0, 0.0, 18.0),
		Vector3(34.0, 0.0, 18.0),
	]
	for index in range(positions.size()):
		_add_beacon("RangeBeacon_%d" % index, positions[index], 16.0)


func _add_beacon(node_name: String, base_position: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = base_position + Vector3.UP * (height * 0.5)
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)

	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.32
	mast_mesh.bottom_radius = 0.72
	mast_mesh.height = height
	mast_mesh.radial_segments = 8
	var mast := MeshInstance3D.new()
	mast.name = "Mast"
	mast.mesh = mast_mesh
	mast.material_override = _beacon_material
	mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mast)

	var collision := CollisionShape3D.new()
	var collision_shape := CylinderShape3D.new()
	collision_shape.radius = 0.8
	collision_shape.height = height
	collision.shape = collision_shape
	body.add_child(collision)

	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.7
	lamp_mesh.height = 1.4
	lamp_mesh.radial_segments = 8
	lamp_mesh.rings = 4
	var lamp := MeshInstance3D.new()
	lamp.name = "BeaconLamp"
	lamp.mesh = lamp_mesh
	lamp.position = Vector3(0.0, height * 0.5 + 0.3, 0.0)
	lamp.material_override = _beacon_lamp_material
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(lamp)


func _build_distant_ridges() -> void:
	var ridge_materials: Array[StandardMaterial3D] = [
		_make_standard_material(Color(0.31, 0.31, 0.27, 1.0)),
		_make_standard_material(Color(0.37, 0.35, 0.29, 1.0)),
		_make_standard_material(Color(0.26, 0.29, 0.27, 1.0)),
	]
	var ridge_specs: Array[Dictionary] = [
		{"position": Vector3(-360.0, 0.0, -335.0), "radius": 62.0, "height": 68.0, "material": 0},
		{"position": Vector3(-250.0, 0.0, -370.0), "radius": 48.0, "height": 54.0, "material": 1},
		{"position": Vector3(-105.0, 0.0, -365.0), "radius": 58.0, "height": 75.0, "material": 2},
		{"position": Vector3(65.0, 0.0, -385.0), "radius": 70.0, "height": 82.0, "material": 0},
		{"position": Vector3(250.0, 0.0, -365.0), "radius": 55.0, "height": 62.0, "material": 1},
		{"position": Vector3(365.0, 0.0, -300.0), "radius": 62.0, "height": 73.0, "material": 2},
		{"position": Vector3(375.0, 0.0, -105.0), "radius": 58.0, "height": 50.0, "material": 0},
		{"position": Vector3(380.0, 0.0, 120.0), "radius": 75.0, "height": 84.0, "material": 1},
		{"position": Vector3(280.0, 0.0, 365.0), "radius": 62.0, "height": 60.0, "material": 2},
		{"position": Vector3(75.0, 0.0, 380.0), "radius": 70.0, "height": 74.0, "material": 0},
		{"position": Vector3(-135.0, 0.0, 375.0), "radius": 60.0, "height": 67.0, "material": 1},
		{"position": Vector3(-335.0, 0.0, 315.0), "radius": 72.0, "height": 78.0, "material": 2},
	]
	for index in range(ridge_specs.size()):
		var spec: Dictionary = ridge_specs[index]
		var base_position: Vector3 = spec["position"]
		var radius: float = float(spec["radius"])
		var height: float = float(spec["height"])
		var mountain_mesh := CylinderMesh.new()
		mountain_mesh.top_radius = radius * 0.05
		mountain_mesh.bottom_radius = radius
		mountain_mesh.height = height
		mountain_mesh.radial_segments = 6
		mountain_mesh.rings = 1
		var visual := MeshInstance3D.new()
		visual.name = "DistantRidge_%02d" % index
		visual.mesh = mountain_mesh
		visual.material_override = ridge_materials[int(spec["material"])]
		visual.position = base_position + Vector3.UP * (height * 0.5)
		visual.rotation.y = deg_to_rad(float(index * 29))
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)


func _build_wind_reference() -> void:
	var reference := Node3D.new()
	reference.name = "WindReference"
	reference.position = Vector3(18.0, 0.0, 10.0)
	add_child(reference)

	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.14
	pole_mesh.height = 6.0
	pole_mesh.radial_segments = 8
	var pole := MeshInstance3D.new()
	pole.name = "WindPole"
	pole.mesh = pole_mesh
	pole.position.y = 3.0
	pole.material_override = _beacon_material
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reference.add_child(pole)

	# The arrow points in the configured mean wind-flow direction (+X, +Z).
	var arrow_mesh := ImmediateMesh.new()
	var arrow_material := _make_unshaded_material(Color(0.88, 0.56, 0.24, 0.95))
	arrow_mesh.surface_begin(Mesh.PRIMITIVE_LINES, arrow_material)
	arrow_mesh.surface_add_vertex(Vector3(-4.0, 0.055, -4.0))
	arrow_mesh.surface_add_vertex(Vector3(4.0, 0.055, 4.0))
	arrow_mesh.surface_add_vertex(Vector3(4.0, 0.055, 4.0))
	arrow_mesh.surface_add_vertex(Vector3(1.4, 0.055, 3.5))
	arrow_mesh.surface_add_vertex(Vector3(4.0, 0.055, 4.0))
	arrow_mesh.surface_add_vertex(Vector3(3.5, 0.055, 1.4))
	arrow_mesh.surface_end()
	var arrow := MeshInstance3D.new()
	arrow.name = "MeanWindDirectionArrow"
	arrow.mesh = arrow_mesh
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reference.add_child(arrow)
	_add_world_label(reference, "WindLabel", "MEAN WIND  →", Vector3(0.0, 0.1, -5.0), 38, 0.014, Vector3(90.0, 0.0, 0.0))
