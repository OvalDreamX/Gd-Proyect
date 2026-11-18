extends RefCounted
class_name SolarSystemLoader

## Moddable JSON loader, validator, and analytical orbital/rotational propagator
## for Phase 3I simple solar system foundations (interplanetary travel deferred).

const DEFAULT_SYSTEM_PATH: String = "res://data/systems/test_system.json"


static func load_system_from_file(path: String = DEFAULT_SYSTEM_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"valid": false,
			"errors": ["Solar system JSON file not found: %s" % path],
			"system": {},
		}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"valid": false,
			"errors": ["Unable to open solar system JSON file: %s" % path],
			"system": {},
		}
	var text: String = file.get_as_text()
	return parse_and_validate_json(text)


static func parse_and_validate_json(json_text: String) -> Dictionary:
	var json := JSON.new()
	var err: Error = json.parse(json_text)
	if err != OK:
		return {
			"valid": false,
			"errors": ["JSON parse error line %d: %s" % [json.get_error_line(), json.get_error_message()]],
			"system": {},
		}
	if not (json.data is Dictionary):
		return {
			"valid": false,
			"errors": ["Top-level solar system JSON must be an object."],
			"system": {},
		}
	var raw: Dictionary = json.data
	return validate_system_dict(raw)


static func validate_system_dict(raw: Dictionary) -> Dictionary:
	var errors: Array[String] = []

	var system_id: String = str(raw.get("system_id", "")).strip_edges()
	if system_id.is_empty():
		errors.append("Missing non-empty 'system_id'.")

	var time_scale: float = float(raw.get("time_scale", 1.0))
	if time_scale < 0.0:
		errors.append("'time_scale' must be >= 0.0.")

	var stars_raw = raw.get("stars", [])
	if not (stars_raw is Array) or (stars_raw as Array).is_empty():
		errors.append("'stars' must be a non-empty array.")

	var planets_raw = raw.get("planets", [])
	if not (planets_raw is Array) or (planets_raw as Array).is_empty():
		errors.append("'planets' must be a non-empty array.")

	var stations_raw = raw.get("stations", [])
	if not (stations_raw is Array):
		errors.append("'stations' must be an array.")

	var star_ids: Dictionary = {}
	if stars_raw is Array:
		for i in range((stars_raw as Array).size()):
			var s = stars_raw[i]
			if not (s is Dictionary):
				errors.append("stars[%d] must be an object." % i)
				continue
			var s_dict: Dictionary = s
			var sid: String = str(s_dict.get("star_id", "")).strip_edges()
			if sid.is_empty():
				errors.append("stars[%d] missing 'star_id'." % i)
			else:
				star_ids[sid] = true
			if float(s_dict.get("light_intensity", -1.0)) < 0.0:
				errors.append("stars[%d] 'light_intensity' must be >= 0.0." % i)
			if not _is_valid_rgb_array(s_dict.get("light_color", null)):
				errors.append("stars[%d] 'light_color' must be a 3-element RGB array in [0..1]." % i)

	var planet_ids: Dictionary = {}
	if planets_raw is Array:
		for i in range((planets_raw as Array).size()):
			var p = planets_raw[i]
			if not (p is Dictionary):
				errors.append("planets[%d] must be an object." % i)
				continue
			var p_dict: Dictionary = p
			var pid: String = str(p_dict.get("planet_id", "")).strip_edges()
			if pid.is_empty():
				errors.append("planets[%d] missing 'planet_id'." % i)
			else:
				planet_ids[pid] = true
			var parent_star: String = str(p_dict.get("parent_star_id", "")).strip_edges()
			if not star_ids.has(parent_star):
				errors.append("planets[%d] references unknown parent_star_id '%s'." % [i, parent_star])
			if float(p_dict.get("radius_m", 0.0)) <= 0.0:
				errors.append("planets[%d] 'radius_m' must be > 0." % i)
			if float(p_dict.get("orbital_radius_m", 0.0)) <= 0.0:
				errors.append("planets[%d] 'orbital_radius_m' must be > 0." % i)
			if float(p_dict.get("orbital_period_seconds", 0.0)) <= 0.0:
				errors.append("planets[%d] 'orbital_period_seconds' must be > 0." % i)
			if is_zero_approx(float(p_dict.get("rotation_period_seconds", 0.0))):
				errors.append("planets[%d] 'rotation_period_seconds' must be non-zero." % i)
			var ptype: String = str(p_dict.get("planet_type", "")).strip_edges()
			if ptype.is_empty():
				errors.append("planets[%d] missing 'planet_type'." % i)

	if stations_raw is Array:
		for i in range((stations_raw as Array).size()):
			var st = stations_raw[i]
			if not (st is Dictionary):
				errors.append("stations[%d] must be an object." % i)
				continue
			var st_dict: Dictionary = st
			var st_id: String = str(st_dict.get("station_id", "")).strip_edges()
			if st_id.is_empty():
				errors.append("stations[%d] missing 'station_id'." % i)
			var parent_planet: String = str(st_dict.get("orbit_parent_id", "")).strip_edges()
			if not planet_ids.has(parent_planet):
				errors.append("stations[%d] references unknown orbit_parent_id '%s'." % [i, parent_planet])
			if float(st_dict.get("orbital_radius_m", 0.0)) <= 0.0:
				errors.append("stations[%d] 'orbital_radius_m' must be > 0." % i)
			if float(st_dict.get("orbital_period_seconds", 0.0)) <= 0.0:
				errors.append("stations[%d] 'orbital_period_seconds' must be > 0." % i)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"system": raw if errors.is_empty() else {},
	}


static func evaluate_system_state(system_data: Dictionary, elapsed_sim_seconds: float, station_id_filter: String = "") -> Dictionary:
	var stars: Array = system_data.get("stars", [])
	var planets: Array = system_data.get("planets", [])
	var stations: Array = system_data.get("stations", [])
	if stars.is_empty() or planets.is_empty():
		return {"valid": false}

	var time_scale: float = maxf(float(system_data.get("time_scale", 1.0)), 0.0)
	var epoch_s: float = float(system_data.get("initial_epoch_seconds", 0.0))
	var t_s: float = epoch_s + elapsed_sim_seconds * time_scale

	var star: Dictionary = stars[0]
	var star_pos: Vector3 = _vec3_from_array(star.get("position_m", [0.0, 0.0, 0.0]), Vector3.ZERO)
	var light_color: Color = _color_from_array(star.get("light_color", [1.0, 0.96, 0.90]), Color(1.0, 0.96, 0.90, 1.0))
	var light_intensity: float = maxf(float(star.get("light_intensity", 1.0)), 0.0)
	var disc_color: Color = _color_from_array(star.get("disc_color", [1.0, 0.97, 0.89]), Color(1.0, 0.97, 0.89, 1.0))
	var disc_ang_deg: float = clampf(float(star.get("disc_angular_radius_deg", 0.95)), 0.15, 8.0)

	var planet: Dictionary = planets[0]
	var planet_radius_m: float = maxf(float(planet.get("radius_m", 100000.0)), 1.0)
	var planet_orb_r: float = maxf(float(planet.get("orbital_radius_m", 150000000.0)), 1.0)
	var planet_orb_period: float = maxf(float(planet.get("orbital_period_seconds", 7200.0)), 0.1)
	var planet_orb_inc_rad: float = deg_to_rad(float(planet.get("orbital_inclination_deg", 0.0)))
	var planet_orb_init_rad: float = deg_to_rad(float(planet.get("initial_orbital_angle_deg", 205.0)))
	var planet_orb_angle_rad: float = fposmod(planet_orb_init_rad + (TAU / planet_orb_period) * t_s, TAU)

	var planet_inc_basis := Basis(Vector3.RIGHT, planet_orb_inc_rad)
	var planet_rel_star: Vector3 = planet_inc_basis * Vector3(cos(planet_orb_angle_rad) * planet_orb_r, 0.0, sin(planet_orb_angle_rad) * planet_orb_r)
	var planet_pos: Vector3 = star_pos + planet_rel_star
	var planet_to_star_dir: Vector3 = (star_pos - planet_pos).normalized()

	var rot_period: float = float(planet.get("rotation_period_seconds", 1800.0))
	var rot_rate: float = TAU / rot_period if not is_zero_approx(rot_period) else 0.0
	var planet_spin_init_rad: float = deg_to_rad(float(planet.get("initial_rotation_deg", 32.5)))
	var planet_spin_angle_rad: float = fposmod(planet_spin_init_rad + rot_rate * t_s, TAU)
	var axial_tilt_rad: float = deg_to_rad(float(planet.get("axial_tilt_deg", 12.0)))
	var spin_axis_tilt_basis := Basis(Vector3.BACK, axial_tilt_rad)
	var planet_spin_basis: Basis = (spin_axis_tilt_basis * Basis(Vector3.UP, planet_spin_angle_rad)).orthonormalized()

	# Construct Starport Alpha local tangent frame on the spinning planet at configured latitude.
	# Body columns: East = X, Up = Y, South = Z (right-handed, so North = -Z).
	var lat_rad: float = deg_to_rad(clampf(float(planet.get("starport_latitude_deg", 35.0)), -85.0, 85.0))
	var cos_lat: float = cos(lat_rad)
	var sin_lat: float = sin(lat_rad)
	var port_east_body := Vector3(0.0, 0.0, -1.0)
	var port_up_body := Vector3(cos_lat, sin_lat, 0.0)
	var port_south_body := Vector3(sin_lat, -cos_lat, 0.0)
	var port_in_planet_basis := Basis(port_east_body, port_up_body, port_south_body).orthonormalized()
	var port_world_basis: Basis = (planet_spin_basis * port_in_planet_basis).orthonormalized()

	# Transform heliocentric planet->star vector into Starport Alpha surface scene coordinates.
	var sun_dir_surface: Vector3 = (port_world_basis.inverse() * planet_to_star_dir).normalized()
	var sun_elev_deg: float = rad_to_deg(asin(clampf(sun_dir_surface.y, -1.0, 1.0)))
	# North = -Z, East = +X => clockwise azimuth from North: atan2(east, north) = atan2(x, -z).
	var sun_azimuth_deg: float = fposmod(rad_to_deg(atan2(sun_dir_surface.x, -sun_dir_surface.z)), 360.0)

	# Station orbital state around parent planet.
	var station: Dictionary = stations[0] if not stations.is_empty() else {}
	if not station_id_filter.is_empty():
		for cand in stations:
			if cand is Dictionary and str((cand as Dictionary).get("station_id", "")) == station_id_filter:
				station = cand
				break

	var station_id: String = str(station.get("station_id", "station_orbital_cube_01"))
	var station_name: String = str(station.get("display_name", "Orbital Relay Cube 01"))
	var st_orb_r: float = maxf(float(station.get("orbital_radius_m", 180000.0)), planet_radius_m + 1000.0)
	var st_orb_period: float = maxf(float(station.get("orbital_period_seconds", 900.0)), 0.1)
	var st_orb_inc_rad: float = deg_to_rad(float(station.get("orbital_inclination_deg", 12.0)))
	var st_orb_init_rad: float = deg_to_rad(float(station.get("initial_orbital_angle_deg", 145.0)))
	var st_orb_angle_rad: float = fposmod(st_orb_init_rad + (TAU / st_orb_period) * t_s, TAU)

	var st_inc_basis := Basis(Vector3.RIGHT, st_orb_inc_rad)
	var station_rel_planet: Vector3 = st_inc_basis * Vector3(cos(st_orb_angle_rad) * st_orb_r, 0.0, sin(st_orb_angle_rad) * st_orb_r)
	var station_pos: Vector3 = planet_pos + station_rel_planet
	var station_to_star_dir: Vector3 = (star_pos - station_pos).normalized()
	var station_to_planet_dir: Vector3 = (planet_pos - station_pos).normalized()

	var atmo_color: Color = _color_from_array(planet.get("atmosphere_color", [0.36, 0.64, 0.98]), Color(0.36, 0.64, 0.98, 1.0))

	return {
		"valid": true,
		"system_id": str(system_data.get("system_id", "test_system")),
		"system_name": str(system_data.get("display_name", "Solara Test System")),
		"celestial_time_seconds": t_s,
		"star_id": str(star.get("star_id", "sol_prime")),
		"star_name": str(star.get("display_name", "Sol Prime")),
		"star_light_color": light_color,
		"star_light_intensity": light_intensity,
		"star_disc_color": disc_color,
		"star_disc_angular_radius_deg": disc_ang_deg,
		"planet_id": str(planet.get("planet_id", "test_planet")),
		"planet_name": str(planet.get("display_name", "Veridia")),
		"planet_type": str(planet.get("planet_type", "TERRESTRIAL")),
		"planet_radius_m": planet_radius_m,
		"planet_orbital_radius_m": planet_orb_r,
		"planet_orbital_angle_deg": rad_to_deg(planet_orb_angle_rad),
		"planet_rotation_angle_deg": rad_to_deg(planet_spin_angle_rad),
		"planet_position_heliocentric_m": planet_pos,
		"planet_spin_basis": planet_spin_basis,
		"planet_atmosphere_color": atmo_color,
		"planet_to_star_dir": planet_to_star_dir,
		"surface_sun_dir_to_star": sun_dir_surface,
		"surface_sun_light_dir": -sun_dir_surface,
		"surface_solar_elevation_deg": sun_elev_deg,
		"surface_solar_azimuth_deg": sun_azimuth_deg,
		"station_id": station_id,
		"station_name": station_name,
		"station_orbital_radius_m": st_orb_r,
		"station_orbital_angle_deg": rad_to_deg(st_orb_angle_rad),
		"station_position_heliocentric_m": station_pos,
		"station_rel_planet_m": station_rel_planet,
		"station_to_star_dir": station_to_star_dir,
		"station_to_planet_dir": station_to_planet_dir,
	}


static func orient_directional_light(light: DirectionalLight3D, dir_to_star: Vector3) -> void:
	if not is_instance_valid(light):
		return
	var star_dir: Vector3 = dir_to_star.normalized() if dir_to_star.length_squared() > 0.000001 else Vector3.UP
	var light_travel_dir: Vector3 = -star_dir
	var up_hint: Vector3 = Vector3.FORWARD if absf(light_travel_dir.dot(Vector3.UP)) > 0.98 else Vector3.UP
	# DirectionalLight3D shines along local -Z.
	light.global_basis = Basis.looking_at(light_travel_dir, up_hint)


static func _is_valid_rgb_array(value) -> bool:
	if not (value is Array):
		return false
	var arr: Array = value
	if arr.size() < 3:
		return false
	for i in range(3):
		var c: float = float(arr[i])
		if c < 0.0 or c > 1.0:
			return false
	return true


static func _color_from_array(value, fallback: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var arr: Array = value
		return Color(clampf(float(arr[0]), 0.0, 1.0), clampf(float(arr[1]), 0.0, 1.0), clampf(float(arr[2]), 0.0, 1.0), 1.0)
	return fallback


static func _vec3_from_array(value, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var arr: Array = value
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback
