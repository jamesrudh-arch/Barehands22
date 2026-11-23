extends VehicleBody3D
## Vehicle — drivable cars/bikes (VehicleBody3D) with procedural bodies,
## engine audio, damage, horns, lights; doubles as traffic AI vehicle and
## police cruiser. Player enters/exits; traffic mode follows lane loops.

var vehicle_def_id: String = "sedan"
var vehicle_type: String = "car"
var hp: float = 100.0
var driver: Node = null          # player node when occupied
var is_traffic: bool = false
var is_police: bool = false
var parked: bool = true
var color: Color = Color(0.3, 0.32, 0.36)

var _body_mi: MeshInstance3D
var _wheel_mis: Array = []
var _engine_pitch := 1.0
var _engine_player: AudioStreamPlayer
var _horn_t := 0.0
var _speed := 0.0
var _lane: PackedVector3Array = PackedVector3Array()
var _lane_i := 0
var _traffic_speed := 8.0
var _stop_t := 0.0
var _light_bar: MeshInstance3D
var _siren_on := false
var _head_l: OmniLight3D
var _tail_mi: MeshInstance3D

const WHEEL_R := 0.34


func setup(def_id: String, col: Color = Color(0.3, 0.32, 0.36), police: bool = false) -> void:
	vehicle_def_id = def_id
	var d := Db.vehicle(def_id)
	vehicle_type = d.get("type", "car")
	color = col
	is_police = police
	mass = d.get("mass", 1400)
	_build_mesh(d)
	_build_wheels(d)
	_engine_player = AudioStreamPlayer.new()
	_engine_player.bus = "SFX"
	var s: AudioStream = load("res://assets/audio/sfx/%s.wav" % d.get("engine", "veh_engine_sedan"))
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_begin = 0
		(s as AudioStreamWAV).loop_end = (s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate
	_engine_player.stream = s
	add_child(_engine_player)
	add_to_group("vehicle")
	set_meta("interact_label", "Drive %s" % d.get("name", "vehicle"))


func _build_mesh(d: Dictionary) -> void:
	_body_mi = MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if vehicle_type == "bike":
		_sb(st, Vector3(0, 0.55, 0), Vector3(0.16, 0.35, 1.5))          # frame/tank
		_sb(st, Vector3(0, 0.85, -0.35), Vector3(0.3, 0.12, 0.7))      # seat
		_sb(st, Vector3(0, 0.95, 0.6), Vector3(0.4, 0.25, 0.15))       # bars
		_sb(st, Vector3(0, 0.5, 0.95), Vector3(0.2, 0.2, 0.1))         # headlight box
	else:
		var L: float = 4.4 if int(d.get("seats", 4)) >= 4 else 3.9
		var W := 1.85
		_sb(st, Vector3(0, 0.55, 0), Vector3(W, 0.6, L))               # body
		_sb(st, Vector3(0, 1.05, -0.25), Vector3(W * 0.82, 0.55, L * 0.5))  # cabin
		_sb(st, Vector3(0, 0.35, L * 0.5 - 0.1), Vector3(W * 0.9, 0.35, 0.3)) # bumper f
		_sb(st, Vector3(0, 0.35, -L * 0.5 + 0.1), Vector3(W * 0.9, 0.35, 0.3)) # bumper r
	st.generate_normals()
	st.deindex()
	st.generate_normals()
	_body_mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.55
	m.roughness = 0.35
	_body_mi.material_override = m
	add_child(_body_mi)
	# headlights / taillights
	var hl := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(0.5, 0.16)
	hl.mesh = hq
	hl.position = Vector3(0, 0.62, 2.25 if vehicle_type == "car" else 1.0)
	var hm := StandardMaterial3D.new()
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.95, 0.8)
	hm.emission_energy_multiplier = 0.0
	hm.albedo_color = Color(0.9, 0.9, 0.85)
	hl.material_override = hm
	add_child(hl)
	_tail_mi = MeshInstance3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(0.5, 0.12)
	_tail_mi.mesh = tq
	_tail_mi.position = Vector3(0, 0.62, -2.25 if vehicle_type == "car" else -1.0)
	_tail_mi.rotation.y = PI
	var tm := StandardMaterial3D.new()
	tm.emission_enabled = true
	tm.emission = Color(1.0, 0.1, 0.08)
	tm.emission_energy_multiplier = 1.2
	tm.albedo_color = Color(0.4, 0.05, 0.05)
	_tail_mi.material_override = tm
	add_child(_tail_mi)
	_head_l = OmniLight3D.new()
	_head_l.light_color = Color(1.0, 0.95, 0.8)
	_head_l.light_energy = 0.0
	_head_l.omni_range = 14.0
	_head_l.position = Vector3(0, 0.7, 2.4)
	add_child(_head_l)
	if is_police:
		_light_bar = MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1.2, 0.14, 0.35)
		_light_bar.mesh = lb
		_light_bar.position = Vector3(0, 1.4, -0.25)
		var lm := StandardMaterial3D.new()
		lm.emission_enabled = true
		lm.emission = Color(1, 0.1, 0.1)
		lm.emission_energy_multiplier = 3.0
		_light_bar.material_override = lm
		add_child(_light_bar)


func _sb(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var c := center
	var pts := [
		[c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z), Vector3(0, 0, 1)],
		[c + Vector3(h.x, -h.y, -h.z), c + Vector3(-h.x, -h.y, -h.z), c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), Vector3(0, 0, -1)],
		[c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), Vector3(1, 0, 0)],
		[c + Vector3(-h.x, -h.y, -h.z), c + Vector3(-h.x, -h.y, h.z), c + Vector3(-h.x, h.y, h.z), c + Vector3(-h.x, h.y, -h.z), Vector3(-1, 0, 0)],
		[c + Vector3(-h.x, h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z), Vector3(0, 1, 0)],
		[c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z), Vector3(0, -1, 0)],
	]
	for q in pts:
		st.set_normal(q[4])
		st.set_uv(Vector2(0, 0))
		st.add_vertex(q[0])
		st.set_uv(Vector2(1, 0))
		st.add_vertex(q[1])
		st.set_uv(Vector2(1, 1))
		st.add_vertex(q[2])
		st.set_uv(Vector2(0, 0))
		st.add_vertex(q[0])
		st.set_uv(Vector2(1, 1))
		st.add_vertex(q[2])
		st.set_uv(Vector2(0, 1))
		st.add_vertex(q[3])


func _build_wheels(d: Dictionary) -> void:
	var positions: Array
	if vehicle_type == "bike":
		positions = [Vector3(0, WHEEL_R, 0.85), Vector3(0, WHEEL_R, -0.85)]
	else:
		positions = [Vector3(0.85, WHEEL_R, 1.45), Vector3(-0.85, WHEEL_R, 1.45),
			Vector3(0.85, WHEEL_R, -1.45), Vector3(-0.85, WHEEL_R, -1.45)]
	for i in positions.size():
		var w := VehicleWheel3D.new()
		w.wheel_radius = WHEEL_R
		w.wheel_rest_length = 0.25
		w.wheel_friction_slip = d.get("grip", 1.0) * 1.6
		w.suspension_travel = 0.16
		w.suspension_stiffness = 5.2 if vehicle_type == "car" else 6.5
		w.suspension_max_force = 9000.0 if vehicle_type == "car" else 2500.0
		w.position = positions[i]
		add_child(w)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = WHEEL_R
		cyl.bottom_radius = WHEEL_R
		cyl.height = 0.26
		mi.mesh = cyl
		mi.rotation.z = PI / 2
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.08, 0.08, 0.08)
		wm.roughness = 0.9
		mi.material_override = wm
		w.add_child(mi)
		_wheel_mis.append(mi)
		if vehicle_type == "car":
			if i < 2:
				w.use_as_steering = true
			else:
				w.use_as_traction = true
		else:
			if i == 1:
				w.use_as_traction = true
			else:
				w.use_as_steering = true


# ---------------------------------------------------------------- driving --
func player_enter(p: Node) -> void:
	driver = p
	parked = false
	is_traffic = false
	_engine_player.play()
	AudioDirector.sfx("veh_start", 0.05)


func player_exit() -> void:
	driver = null
	parked = true
	_engine_player.stop()
	linear_velocity = Vector3.ZERO


func player_drive(delta: float, mv: Vector2, brake: bool, handbrake: bool, horn: bool) -> void:
	var d := Db.vehicle(vehicle_def_id)
	var throttle := -mv.y
	engine_force = throttle * float(d.get("power", 100)) * 22.0
	_set_brake(8.0 if brake else 1.0)
	if handbrake:
		_set_brake(22.0)
		for w in get_children():
			if w is VehicleWheel3D and not w.use_as_steering:
				w.wheel_friction_slip = 0.7
	else:
		for w in get_children():
			if w is VehicleWheel3D and not w.use_as_steering:
				w.wheel_friction_slip = d.get("grip", 1.0) * 1.6
	steering = move_toward(steering, mv.x * 0.55, delta * 2.4)
	if horn and _horn_t <= 0.0:
		AudioDirector.sfx_at("veh_horn", global_position)
		_horn_t = 0.7
	_horn_t -= delta
	_update_audio_and_lights(delta, true)


func set_lane(loop: PackedVector3Array, speed: float) -> void:
	_lane = loop
	_lane_i = 0
	_traffic_speed = speed
	is_traffic = true
	parked = false


func traffic_tick(delta: float) -> void:
	if _lane.is_empty():
		return
	var d := Db.vehicle(vehicle_def_id)
	var target: Vector3 = _lane[_lane_i]
	var to: Vector3 = target - global_position
	to.y = 0
	if to.length() < 4.0:
		_lane_i = (_lane_i + 1) % _lane.size()
	var fwd := -global_transform.basis.z
	var angle := atan2(to.normalized().cross(fwd).y, to.normalized().dot(fwd))
	steering = move_toward(steering, clampf(angle * 2.2, -0.5, 0.5), delta * 1.6)
	# obstacle / light check ahead
	var blocked := _check_ahead()
	var desired := 0.0 if blocked else _traffic_speed
	var sp := speed_kmh() / 3.6
	if sp < desired:
		engine_force = float(d.get("power", 100)) * 14.0
	elif sp > desired + 1.5:
		engine_force = 0.0
		_set_brake(12.0)
	else:
		engine_force = float(d.get("power", 100)) * 6.0
		_set_brake(1.0)
	_update_audio_and_lights(delta, false)


func _check_ahead() -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.from = global_position + Vector3(0, 0.6, 0)
	q.to = global_position + (-global_transform.basis.z) * 9.0 + Vector3(0, 0.4, 0)
	q.collision_mask = 1 | 2 | 4
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var obj: Object = hit["collider"]
		if obj != driver and not (driver and obj == driver.get_parent()):
			return true
	return false


func _set_brake(f: float) -> void:
	for w in get_children():
		if w is VehicleWheel3D:
			w.brake = f


func speed_kmh() -> float:
	_speed = linear_velocity.length() * 3.6
	return _speed


func _update_audio_and_lights(delta: float, night: bool) -> void:
	var sp := speed_kmh()
	_engine_pitch = 0.7 + clampf(sp / 140.0, 0.0, 1.3) * 0.9
	_engine_player.pitch_scale = _engine_pitch
	_engine_player.volume_db = linear_to_db(0.5 if driver else 0.22)
	var lights_on := WorldState.is_night() or WorldState.weather == WorldState.Weather.RAIN
	for c in get_children():
		if c is MeshInstance3D and c != _tail_mi and c != _light_bar and c.material_override and c.material_override.emission == Color(1.0, 0.95, 0.8):
			c.material_override.emission_energy_multiplier = 2.5 if lights_on else 0.0
	_head_l.light_energy = 5.0 if lights_on else 0.0
	if is_police and _siren_on:
		var tmod := fmod(Time.get_ticks_msec() / 1000.0, 0.8)
		var lm: StandardMaterial3D = _light_bar.material_override
		lm.emission = Color(1, 0.1, 0.1) if tmod < 0.4 else Color(0.15, 0.3, 1.0)


func set_siren(on: bool) -> void:
	_siren_on = on
	if on and not _engine_player.playing:
		_engine_player.play()
	if on:
		AudioDirector.ambient("siren", "res://assets/audio/sfx/siren_loop.wav", 0.5)
	else:
		AudioDirector.ambient_off("siren")


func damage(amount: float) -> void:
	hp -= amount
	Bus.vehicle_health_changed.emit(hp)
	if hp < 40.0:
		Effects.burst(global_position + Vector3(0, 1.0, 0), "smoke")
	if hp <= 0.0:
		Effects.burst(global_position + Vector3(0, 1.1, 0), "smoke")
		AudioDirector.sfx_at("fire_crackle", global_position)


var _prev_vel := Vector3.ZERO
var _crash_cd := 0.0


func _physics_process(delta: float) -> void:
	_crash_cd -= delta
	if is_inside_tree():
		var impact := (_prev_vel - linear_velocity).length()
		_prev_vel = linear_velocity
		if impact > 9.0 and _crash_cd <= 0.0:
			_crash_cd = 1.2
			AudioDirector.sfx_at("veh_crash_light" if impact < 18.0 else "veh_crash_heavy", global_position)
			damage(impact * 0.8)
			Effects.add_shake(0.3)
			if is_traffic:
				_stop_t = 2.0
