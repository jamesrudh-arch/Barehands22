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
var _gear := 1
var _rpm := 0.2
var _shift_dip := 0.0
var _skid_t := 0.0
var _reversing := false
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


var _length := 4.4


func _build_mesh(d: Dictionary) -> void:
	_length = 4.4 if int(d.get("seats", 4)) >= 4 else 3.9
	_body_mi = MeshInstance3D.new()
	if vehicle_type == "bike":
		set_meta("seat_offset", Vector3(0, 0.95, -0.35))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sb(st, Vector3(0, 0.55, 0), Vector3(0.16, 0.35, 1.5))          # frame/tank
		_sb(st, Vector3(0, 0.85, -0.35), Vector3(0.3, 0.12, 0.7))      # seat
		_sb(st, Vector3(0, 0.95, 0.6), Vector3(0.4, 0.25, 0.15))       # bars
		_sb(st, Vector3(0, 0.5, 0.95), Vector3(0.2, 0.2, 0.1))         # headlight box
		_sb(st, Vector3(0, 0.62, 0.15), Vector3(0.24, 0.22, 0.55))     # tank shape
		_sb(st, Vector3(0, 0.42, -0.55), Vector3(0.14, 0.16, 0.6))     # swingarm
		st.generate_normals()
		_body_mi.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = 0.55
		m.roughness = 0.35
		_body_mi.material_override = m
		add_child(_body_mi)
		return
	# ---- v2 car: lofted body sections, greenhouse glass, trim, interior ----
	var L := _length
	var hw := 0.925
	# [z, halfwidth, y_bottom, y_top, cabin]
	var stations: Array = [
		[0.50 * L, hw * 0.93, 0.40, 0.76, false],
		[0.46 * L, hw * 0.99, 0.36, 0.90, false],
		[0.24 * L, hw * 1.00, 0.34, 1.00, false],
		[0.11 * L, hw * 0.97, 0.34, 1.38, true],
		[-0.17 * L, hw * 0.97, 0.34, 1.36, true],
		[-0.33 * L, hw * 1.00, 0.34, 1.02, false],
		[-0.46 * L, hw * 0.98, 0.36, 0.88, false],
		[-0.50 * L, hw * 0.92, 0.40, 0.80, false]]
	var st_b := SurfaceTool.new()
	st_b.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for stn in stations:
		rings.append(_sec(stn[0], stn[1], stn[2], stn[3], stn[4]))
	for r in rings.size() - 1:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		for i in a.size():
			var j := (i + 1) % a.size()
			_quad(st_b, a[i], a[j], b[j], b[i])
	# end caps
	_cap(st_b, rings[0], true)
	_cap(st_b, rings[rings.size() - 1], false)
	# mirrors + chrome side trim + bumpers
	for sgn in [1.0, -1.0]:
		_sb(st_b, Vector3(sgn * (hw + 0.06), 1.06, 0.20 * L), Vector3(0.03, 0.03, 0.16))
		_sb(st_b, Vector3(sgn * (hw + 0.10), 1.10, 0.21 * L), Vector3(0.16, 0.10, 0.03))
		_sb(st_b, Vector3(sgn * hw * 0.99, 0.52, 0.0), Vector3(0.02, 0.05, L * 0.62))
	_sb(st_b, Vector3(0, 0.42, 0.50 * L - 0.04), Vector3(hw * 1.86, 0.22, 0.16))
	_sb(st_b, Vector3(0, 0.42, -0.50 * L + 0.04), Vector3(hw * 1.86, 0.22, 0.16))
	st_b.generate_normals()
	var mesh: ArrayMesh = st_b.commit()
	# greenhouse glass
	var st_g := SurfaceTool.new()
	st_g.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gz: Array = [0.22 * L, 0.10 * L, -0.16 * L, -0.30 * L]
	var grings: Array = []
	for k in gz.size():
		var t: float = float(k) / (gz.size() - 1)
		var y_top: float = lerpf(1.02, 1.36, minf(1.0, t * 3.0)) if k == 0 else (1.36 if k < 3 else 1.04)
		var w: float = hw * 0.90
		grings.append(PackedVector3Array([
			Vector3(-w, 0.92, gz[k]), Vector3(-w * 0.86, y_top, gz[k]),
			Vector3(w * 0.86, y_top, gz[k]), Vector3(w, 0.92, gz[k])]))
	for r in grings.size() - 1:
		var a: PackedVector3Array = grings[r]
		var b: PackedVector3Array = grings[r + 1]
		for i in a.size() - 1:
			_quad(st_g, a[i], a[i + 1], b[i + 1], b[i])
	_cap4(st_g, grings[0], true)
	_cap4(st_g, grings[grings.size() - 1], false)
	st_g.generate_normals()
	st_g.commit(mesh)
	# interior: dash, seats, wheel
	var st_i := SurfaceTool.new()
	st_i.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sb(st_i, Vector3(0, 1.00, 0.20 * L), Vector3(hw * 1.6, 0.22, 0.28))
	for sx in [-0.38, 0.38]:
		_sb(st_i, Vector3(sx, 0.62, -0.02 * L), Vector3(0.46, 0.14, 0.50))
		_sb(st_i, Vector3(sx, 0.98, -0.14 * L), Vector3(0.46, 0.62, 0.14))
		_sb(st_i, Vector3(-0.38, 1.10, 0.14 * L), Vector3(0.30, 0.05, 0.30))
	st_i.generate_normals()
	st_i.commit(mesh)
	_body_mi.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.metallic = 0.62
	paint.roughness = 0.30
	mesh.surface_set_material(0, paint)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.08, 0.10, 0.12, 0.45)
	glass.roughness = 0.08
	glass.metallic = 0.1
	mesh.surface_set_material(1, glass)
	var interior := StandardMaterial3D.new()
	interior.albedo_color = Color(0.05, 0.05, 0.06)
	interior.roughness = 0.85
	mesh.surface_set_material(2, interior)
	add_child(_body_mi)
	# headlights / taillights
	var hl := MeshInstance3D.new()
	var hq := QuadMesh.new()
	hq.size = Vector2(0.5, 0.16)
	hl.mesh = hq
	hl.position = Vector3(0, 0.70, _length * 0.5 - 0.06 if vehicle_type == "car" else 1.0)
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
	_tail_mi.position = Vector3(0, 0.74, -_length * 0.5 + 0.06 if vehicle_type == "car" else -1.0)
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


func _sec(z: float, hw: float, y0: float, y1: float, cabin: bool) -> PackedVector3Array:
	# 8-point cross-section; cabin stations pull the top in to a roof
	var ys: float = y1 - 0.34 if cabin else y1 - 0.10
	var rw: float = hw * 0.80 if cabin else hw * 0.90
	return PackedVector3Array([
		Vector3(-hw * 0.86, y0, z), Vector3(-hw, y0 + 0.16, z), Vector3(-hw, ys, z), Vector3(-rw, y1, z),
		Vector3(rw, y1, z), Vector3(hw, ys, z), Vector3(hw, y0 + 0.16, z), Vector3(hw * 0.86, y0, z)])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d2: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d2)


func _cap(st: SurfaceTool, ring: PackedVector3Array, front: bool) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	if front:
		for i in ring.size():
			var j := (i + 1) % ring.size()
			st.add_vertex(c); st.add_vertex(ring[j]); st.add_vertex(ring[i])
	else:
		for i in ring.size():
			var j := (i + 1) % ring.size()
			st.add_vertex(c); st.add_vertex(ring[i]); st.add_vertex(ring[j])


func _cap4(st: SurfaceTool, ring: PackedVector3Array, front: bool) -> void:
	if front:
		st.add_vertex(ring[0]); st.add_vertex(ring[2]); st.add_vertex(ring[1])
		st.add_vertex(ring[0]); st.add_vertex(ring[3]); st.add_vertex(ring[2])
	else:
		st.add_vertex(ring[0]); st.add_vertex(ring[1]); st.add_vertex(ring[2])
		st.add_vertex(ring[0]); st.add_vertex(ring[2]); st.add_vertex(ring[3])


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


func _wheel_mesh() -> ArrayMesh:
	# tyre + rim + five spokes + hub, two material surfaces
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 16
	var w2 := 0.13
	var ring_f := PackedVector3Array()
	var ring_b := PackedVector3Array()
	for i in seg:
		var a := TAU * i / seg
		ring_f.append(Vector3(cos(a) * WHEEL_R, sin(a) * WHEEL_R, w2))
		ring_b.append(Vector3(cos(a) * WHEEL_R, sin(a) * WHEEL_R, -w2))
	for i in seg:
		var j := (i + 1) % seg
		_quad(st, ring_f[i], ring_f[j], ring_b[j], ring_b[i])
	# sidewalls to rim edge
	var rim_r := WHEEL_R * 0.60
	for i in seg:
		var j := (i + 1) % seg
		var a := TAU * i / seg
		var b := TAU * j / seg
		_quad(st, ring_f[j], ring_f[i],
			Vector3(cos(a) * rim_r, sin(a) * rim_r, w2), Vector3(cos(b) * rim_r, sin(b) * rim_r, w2))
		_quad(st, ring_b[i], ring_b[j],
			Vector3(cos(b) * rim_r, sin(b) * rim_r, -w2), Vector3(cos(a) * rim_r, sin(a) * rim_r, -w2))
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.045, 0.045, 0.048)
	rubber.roughness = 0.92
	mesh.surface_set_material(0, rubber)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	# rim barrel + face + spokes + hub
	var rf := PackedVector3Array()
	var rb := PackedVector3Array()
	for i in seg:
		var a := TAU * i / seg
		rf.append(Vector3(cos(a) * rim_r, sin(a) * rim_r, w2 * 0.85))
		rb.append(Vector3(cos(a) * rim_r, sin(a) * rim_r, -w2 * 0.85))
	for i in seg:
		var j := (i + 1) % seg
		_quad(st2, rb[i], rb[j], rf[j], rf[i])
	for k in 5:
		var ang := TAU * k / 5.0
		var dirv := Vector3(cos(ang), sin(ang), 0)
		var side := Vector3(-dirv.y, dirv.x, 0)
		var c0 := dirv * 0.06
		var c1 := dirv * (rim_r * 0.92)
		_quad(st2, c0 + side * 0.045 + Vector3(0, 0, w2 * 0.8), c1 + side * 0.035 + Vector3(0, 0, w2 * 0.8),
			c1 + side * 0.035 + Vector3(0, 0, w2 * 0.95), c0 + side * 0.045 + Vector3(0, 0, w2 * 0.95))
		_quad(st2, c0 - side * 0.045 + Vector3(0, 0, w2 * 0.8), c0 - side * 0.045 + Vector3(0, 0, w2 * 0.95),
			c1 - side * 0.035 + Vector3(0, 0, w2 * 0.95), c1 - side * 0.035 + Vector3(0, 0, w2 * 0.8))
	# hub cap
	var hr := 0.07
	for i in seg:
		var j := (i + 1) % seg
		var a := TAU * i / seg
		var b := TAU * j / seg
		_quad(st2, Vector3(cos(a) * hr, sin(a) * hr, w2 * 0.95), Vector3(cos(b) * hr, sin(b) * hr, w2 * 0.95),
			Vector3(0, 0, w2 * 1.02), Vector3(0, 0, w2 * 1.02))
	st2.generate_normals()
	st2.commit(mesh)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.63, 0.66)
	metal.metallic = 1.0
	metal.roughness = 0.22
	mesh.surface_set_material(1, metal)
	return mesh


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
		mi.mesh = _wheel_mesh()
		mi.rotation.z = PI / 2
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
	_reversing = throttle < -0.05 and sp_kmh_for_reverse() < 8.0
	if handbrake or (brake and speed_kmh() > 35.0):
		if _skid_t <= 0.0:
			AudioDirector.sfx_at("veh_skid", global_position, 0.5)
			_skid_t = 1.1
	_skid_t -= delta
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
	if not blocked:
		var cl := get_node_or_null("/root/City/CityLife")
		if cl == null:
			cl = get_node_or_null("/root/CityLife")
		if cl and cl.has_method("traffic_green_at"):
			var fwd2: Vector3 = -global_transform.basis.z
			if not cl.traffic_green_at(global_position + fwd2 * 10.0):
				blocked = true
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
	_brake_on = f > 4.0
	for w in get_children():
		if w is VehicleWheel3D:
			w.brake = f


func sp_kmh_for_reverse() -> float:
	return speed_kmh()


var _brake_on := false


func brake_active() -> bool:
	return _brake_on


func steer_angle() -> float:
	return steering / 0.55


func speed_kmh() -> float:
	_speed = linear_velocity.length() * 3.6
	return _speed


func _update_audio_and_lights(delta: float, night: bool) -> void:
	var sp := speed_kmh()
	var d := Db.vehicle(vehicle_def_id)
	var top: float = float(d.get("top_speed", 160))
	var bike: bool = vehicle_type == "bike"
	var gears: int = 5 if bike else int(d.get("gears", 6))
	# gearbox simulation: rpm climbs within a gear, then upshift drops it
	var gear_top := top / float(gears)
	if sp < 1.0:
		_gear = 1
	else:
		_gear = clampi(int(sp / gear_top) + 1, 1, gears)
	var in_gear: float = (sp - float(_gear - 1) * gear_top) / maxf(1.0, gear_top)
	var target_rpm := clampf(0.18 + in_gear * 0.82, 0.0, 1.0)
	if sp < 1.0:
		target_rpm = 0.15 + absf(engine_force) * 0.0004
	if target_rpm < _rpm - 0.3 and _shift_dip <= 0.0:
		_shift_dip = 0.16                              # just shifted: brief torque gap
		AudioDirector.sfx_at("gear_shift" if not bike else "gear_shift_bike", global_position, 0.25)
	_rpm = move_toward(_rpm, target_rpm, delta * (6.0 if target_rpm > _rpm else 9.0))
	_shift_dip = maxf(0.0, _shift_dip - delta)
	var base: float = 0.85 if bike else 0.62
	_engine_pitch = base + _rpm * (0.9 if bike else 0.75)
	if _shift_dip > 0.0:
		_engine_pitch *= 1.0 - _shift_dip * 1.2
	_engine_player.pitch_scale = _engine_pitch
	_engine_player.volume_db = linear_to_db((0.42 + _rpm * 0.22) if driver else 0.22)
	var lights_on := WorldState.is_night() or WorldState.weather == WorldState.Weather.RAIN
	if _tail_mi and _tail_mi.material_override:
		var tm: StandardMaterial3D = _tail_mi.material_override
		if _reversing:
			tm.emission = Color(0.95, 0.95, 0.9)
			tm.emission_energy_multiplier = 2.0
		else:
			tm.emission = Color(1.0, 0.1, 0.08)
			tm.emission_energy_multiplier = 1.6 if brake_active() else (1.2 if lights_on else 0.3)
	for c in get_children():
		if c is MeshInstance3D and c != _tail_mi and c != _light_bar and c.material_override and c.material_override.emission == Color(1.0, 0.95, 0.8):
			c.material_override.emission_energy_multiplier = 2.5 if lights_on else 0.0
	if _head_l:
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
