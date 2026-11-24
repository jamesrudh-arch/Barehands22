extends Node3D
## Smoke Line — the freight train that works the viaduct above the z=-30
## arterial. Built by WorldGen._build_rail(); this script owns the moving
## consist, its audio and its headlight.
##
## A train is the single loudest statement a city can make about being a
## city: you hear it from four districts away, you feel the rumble in the
## deck before you see it, and the horn cuts through rain. Godot's 3D audio
## gives the Doppler for free on a moving emitter, so the sounds are written
## flat and the engine does the pass-by.
##
## It is also not decoration: stand on the viaduct and it will hit you.

const SPEED := 17.5             # m/s — about 63 km/h, a working freight pace
const CAR_GAP := 1.15
const HORN_NEAR := 170.0        # you can hear a diesel horn this far off
const RUMBLE_FULL := 40.0       # inside this the bed is at full level
const RUMBLE_CUT := 230.0       # outside this it is gone
const HIT_RADIUS := 2.6

var _loco: Node3D = null
var _cars: Array = []           # {node, offset}
var _x := -700.0
var _head: SpotLight3D = null
var _tail: OmniLight3D = null
var _rumble: AudioStreamPlayer3D = null
var _horn_cd := 6.0
var _clack_cd := 0.0
var _hit_cd := 0.0
var _y := 8.25
var _z := -30.0
var _x0 := -560.0
var _x1 := 360.0


func _ready() -> void:
	## Missions reach the consist through this group (rail_cross), because the
	## harness boots city.tscn without going through city.gd's named member.
	add_to_group("smoke_line")
	if WorldGen.has_method("rail_height"):
		_y = WorldGen.rail_height()
	# the deck runs the width of the city; keep a margin so the train enters
	# and leaves the horizon rather than popping into existence
	_x0 = WorldGen.RAIL_X0 - 220.0
	_x1 = WorldGen.RAIL_X1 + 220.0
	_z = WorldGen.RAIL_Z
	_build_loco()
	_build_cars()
	_build_audio()
	_x = _x0
	_apply_positions()


# ================================================================ GEOMETRY ==
## SurfaceTool discipline (wave 47): every vertex carries a UV, because the
## format latches on the first vertex and rejects set_uv afterwards.

func _suv(st: SurfaceTool, uv: Vector2, v: Vector3) -> void:
	st.set_uv(uv)
	st.add_vertex(v)


func _sbox(st: SurfaceTool, c: Vector3, sz: Vector3) -> void:
	var h := sz * 0.5
	var faces := [
		[c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)],
		[c + Vector3(h.x, -h.y, -h.z), c + Vector3(-h.x, -h.y, -h.z), c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z)],
		[c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z)],
		[c + Vector3(-h.x, -h.y, -h.z), c + Vector3(-h.x, -h.y, h.z), c + Vector3(-h.x, h.y, h.z), c + Vector3(-h.x, h.y, -h.z)],
		[c + Vector3(-h.x, h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z)],
		[c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z)],
	]
	for q in faces:
		_suv(st, Vector2(0, 0), q[0]); _suv(st, Vector2(1, 0), q[1]); _suv(st, Vector2(1, 1), q[2])
		_suv(st, Vector2(0, 0), q[0]); _suv(st, Vector2(1, 1), q[2]); _suv(st, Vector2(0, 1), q[3])


func _scyl(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, seg: int) -> void:
	var axis := (b - a).normalized()
	if axis.length_squared() < 0.0001:
		return
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	var ra_arr: Array = []
	var rb_arr: Array = []
	for i in seg:
		var ang := TAU * float(i) / float(seg)
		var d := u * cos(ang) + v * sin(ang)
		ra_arr.append(a + d * ra)
		rb_arr.append(b + d * rb)
	for i in seg:
		var j := (i + 1) % seg
		var u0 := float(i) / float(seg)
		var u1 := float(j) / float(seg)
		_suv(st, Vector2(u0, 0), ra_arr[i]); _suv(st, Vector2(u1, 0), ra_arr[j])
		_suv(st, Vector2(u1, 1), rb_arr[j]); _suv(st, Vector2(u0, 0), ra_arr[i])
		_suv(st, Vector2(u1, 1), rb_arr[j]); _suv(st, Vector2(u0, 1), rb_arr[i])


func _bogies(st: SurfaceTool, length: float, y: float) -> void:
	## Two bogies with wheels — the detail that sells "heavy rolling stock".
	for bx in [-length * 0.30, length * 0.30]:
		_sbox(st, Vector3(bx, y + 0.30, 0), Vector3(2.6, 0.42, 1.55))
		for wx in [-0.95, 0.95]:
			for wz in [-0.72, 0.72]:
				_scyl(st, Vector3(bx + wx, y + 0.34, wz - 0.10), Vector3(bx + wx, y + 0.34, wz + 0.10), 0.34, 0.34, 9)


func _mat(col: Color, rough := 0.62, metal := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _finish(st: SurfaceTool, mat: StandardMaterial3D, parent: Node3D, name: String) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_loco() -> void:
	_loco = Node3D.new()
	_loco.name = "Locomotive"
	add_child(_loco)

	# diesel-electric body: long hood, cab set back, nose, roof walk
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(st, Vector3(0, 1.55, 0), Vector3(15.0, 2.55, 2.75))          # main body
	_sbox(st, Vector3(-5.4, 3.10, 0), Vector3(3.6, 1.35, 2.55))       # cab
	_sbox(st, Vector3(6.9, 1.15, 0), Vector3(1.9, 1.55, 2.35))        # nose
	_sbox(st, Vector3(0, 2.86, 0), Vector3(13.4, 0.10, 1.5))          # roof walk
	_sbox(st, Vector3(2.2, 3.30, 0), Vector3(4.6, 0.62, 2.0))         # radiator hatch
	_scyl(st, Vector3(-3.2, 2.85, 0.9), Vector3(-3.2, 3.75, 0.9), 0.16, 0.20, 8)   # horn stack L
	_scyl(st, Vector3(-3.2, 2.85, -0.9), Vector3(-3.2, 3.75, -0.9), 0.16, 0.20, 8)  # horn stack R
	_scyl(st, Vector3(4.6, 2.85, 0.0), Vector3(4.6, 3.95, 0.0), 0.22, 0.26, 8)      # exhaust
	_bogies(st, 15.0, 0.0)
	_sbox(st, Vector3(7.7, 0.85, 0), Vector3(0.5, 0.5, 1.1))          # coupler
	_finish(st, _mat(Color(0.16, 0.17, 0.20), 0.55, 0.45), _loco, "body")

	# the livery stripe: Cinder City freight in amber on near-black
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(st2, Vector3(0, 1.95, 1.385), Vector3(15.0, 0.34, 0.02))
	_sbox(st2, Vector3(0, 1.95, -1.385), Vector3(15.0, 0.34, 0.02))
	_sbox(st2, Vector3(-5.4, 3.45, 1.285), Vector3(3.6, 0.20, 0.02))
	_sbox(st2, Vector3(-5.4, 3.45, -1.285), Vector3(3.6, 0.20, 0.02))
	_finish(st2, _mat(Color(0.95, 0.72, 0.25), 0.5, 0.2), _loco, "stripe")

	# glass
	var st3 := SurfaceTool.new()
	st3.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(st3, Vector3(-5.4, 3.55, 1.29), Vector3(3.2, 0.72, 0.03))
	_sbox(st3, Vector3(-5.4, 3.55, -1.29), Vector3(3.2, 0.72, 0.03))
	_sbox(st3, Vector3(-7.15, 3.55, 0), Vector3(0.03, 0.72, 2.3))
	_finish(st3, _mat(Color(0.10, 0.13, 0.16), 0.10, 0.85), _loco, "glass")

	# headlight: a real SpotLight so it sweeps the deck and the rain at night
	_head = SpotLight3D.new()
	_head.position = Vector3(7.6, 1.9, 0)
	_head.rotation_degrees = Vector3(0, -90, 0)     # facing +x, the direction of travel
	_head.spot_range = 95.0
	_head.spot_angle = 15.0
	_head.light_color = Color(1.0, 0.94, 0.80)
	_head.light_energy = 0.0
	_head.shadow_enabled = false
	_loco.add_child(_head)
	# the marker lamp below it, always lit — you see the train before the beam
	var marker := OmniLight3D.new()
	marker.position = Vector3(7.7, 1.35, 0)
	marker.light_color = Color(1.0, 0.96, 0.86)
	marker.light_energy = 1.5
	marker.omni_range = 12.0
	marker.shadow_enabled = false
	_loco.add_child(marker)
	# tail light on the back of the loco
	_tail = OmniLight3D.new()
	_tail.position = Vector3(-7.6, 2.6, 0)
	_tail.light_color = Color(1.0, 0.16, 0.12)
	_tail.light_energy = 1.2
	_tail.omni_range = 9.0
	_tail.shadow_enabled = false
	_loco.add_child(_tail)


func _build_cars() -> void:
	## A mixed freight: boxcar, tank, flatcar with containers, gondola. Mixed
	## consists read as a working railway; eight identical boxcars do not.
	var kinds := ["boxcar", "tank", "flat", "gondola", "boxcar", "flat"]
	var off := 15.0 * 0.5 + CAR_GAP
	for i in kinds.size():
		var kind: String = kinds[i]
		var length := 13.5
		var n := Node3D.new()
		n.name = "Car%d" % i
		add_child(n)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var col := Color(0.34, 0.28, 0.24)
		match kind:
			"boxcar":
				col = [Color(0.42, 0.26, 0.20), Color(0.30, 0.33, 0.34), Color(0.38, 0.34, 0.26)][i % 3]
				_sbox(st, Vector3(0, 1.85, 0), Vector3(length, 3.05, 2.85))
				_sbox(st, Vector3(0, 3.45, 0), Vector3(length + 0.3, 0.14, 3.0))   # roof cap
				# sliding door + ribs
				_sbox(st, Vector3(0.4, 1.75, 1.44), Vector3(3.0, 2.55, 0.06))
				for rx in [-4.5, -2.0, 2.6, 5.1]:
					_sbox(st, Vector3(rx, 1.85, 1.435), Vector3(0.14, 3.0, 0.05))
					_sbox(st, Vector3(rx, 1.85, -1.435), Vector3(0.14, 3.0, 0.05))
			"tank":
				col = Color(0.52, 0.53, 0.54)
				_scyl(st, Vector3(-length * 0.46, 1.95, 0), Vector3(length * 0.46, 1.95, 0), 1.28, 1.28, 14)
				_sbox(st, Vector3(0, 0.85, 0), Vector3(length, 0.30, 1.9))          # frame
				_sbox(st, Vector3(-1.4, 3.30, 0), Vector3(1.1, 0.34, 1.1))          # dome
				_scyl(st, Vector3(3.0, 3.0, 0), Vector3(3.0, 3.5, 0), 0.10, 0.10, 6)
				for hx in [-3.6, 3.6]:
					_sbox(st, Vector3(hx, 1.95, 0), Vector3(0.12, 2.7, 2.7))        # tank bands
			"flat":
				col = Color(0.28, 0.29, 0.31)
				_sbox(st, Vector3(0, 0.95, 0), Vector3(length, 0.34, 2.6))          # deck
				for sx in [-1.0, 1.0]:
					_sbox(st, Vector3(0, 1.35, sx * 1.28), Vector3(length, 0.5, 0.10))  # sides
				# two containers stacked on the deck
				_sbox(st, Vector3(-3.2, 1.95, 0), Vector3(6.1, 2.45, 2.45))
				_sbox(st, Vector3(3.4, 1.95, 0), Vector3(6.1, 2.45, 2.45))
				_sbox(st, Vector3(-3.2, 4.55, 0), Vector3(6.1, 2.45, 2.45))
			"gondola":
				col = Color(0.36, 0.24, 0.20)
				_sbox(st, Vector3(0, 1.55, 0), Vector3(length, 1.9, 2.8))           # tub
				_sbox(st, Vector3(0, 2.62, 0), Vector3(length + 0.2, 0.14, 2.95))   # top chord
				# scrap load, heaped
				for hx in [-4.2, -1.4, 1.4, 4.2]:
					_sbox(st, Vector3(hx, 2.55, randf_range(-0.5, 0.5)), Vector3(2.4, randf_range(0.5, 1.1), 2.0))
		_bogies(st, length, 0.0)
		_sbox(st, Vector3(-length * 0.5 - 0.35, 0.85, 0), Vector3(0.5, 0.5, 1.1))   # coupler
		_finish(st, _mat(col, 0.72, 0.30), n, "body")
		_cars.append({"node": n, "offset": off + length * 0.5})
		off += length + CAR_GAP


func _build_audio() -> void:
	## The rumble is a persistent 3D emitter parented to the locomotive, so
	## Godot does distance attenuation AND the Doppler on the pass-by.
	_rumble = AudioStreamPlayer3D.new()
	_rumble.name = "Rumble"
	_rumble.bus = "SFX"
	_rumble.unit_size = 26.0
	_rumble.max_distance = RUMBLE_CUT
	_rumble.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_rumble.volume_db = -40.0
	var s: AudioStream = load("res://assets/audio/sfx/train_rumble.wav")
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_begin = 0
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
	_rumble.stream = s
	_loco.add_child(_rumble)
	_rumble.play()


# ==================================================================== RUN ===
func _process(delta: float) -> void:
	_x += SPEED * delta
	if _x > _x1:
		_x = _x0
	_apply_positions()
	_tick_audio(delta)
	_tick_lights()
	_tick_hazard(delta)


func _apply_positions() -> void:
	if _loco != null:
		_loco.global_position = Vector3(_x, _y, _z)
		_loco.rotation_degrees = Vector3(0, 90, 0)   # nose toward +x
	for c in _cars:
		var n: Node3D = c["node"]
		if is_instance_valid(n):
			n.global_position = Vector3(_x - float(c["offset"]), _y, _z)
			n.rotation_degrees = Vector3(0, 90, 0)


func _tick_audio(delta: float) -> void:
	var pl := _player()
	if pl == null or _loco == null:
		return
	var d: float = _loco.global_position.distance_to(pl.global_position)
	# rumble swells with proximity; a train you cannot see is still a train
	if _rumble != null:
		if d < RUMBLE_CUT:
			var near := 1.0 - clampf((d - RUMBLE_FULL) / (RUMBLE_CUT - RUMBLE_FULL), 0.0, 1.0)
			_rumble.volume_db = linear_to_db(clampf(0.06 + 0.85 * near, 0.0001, 1.0))
		else:
			_rumble.volume_db = -60.0
	# wheel clacks over the 20 m rail joints — the rhythm of a moving train
	_clack_cd -= delta
	if _clack_cd <= 0.0:
		_clack_cd = 20.0 / SPEED
		if d < 120.0:
			AudioDirector.sfx_at("rail_clack", _loco.global_position, clampf(0.5 - d / 300.0, 0.05, 0.45), 0.06)
	# the horn: announced before the train arrives, not after
	_horn_cd -= delta
	if _horn_cd <= 0.0:
		_horn_cd = randf_range(16.0, 34.0)
		if d < HORN_NEAR:
			AudioDirector.sfx_at("train_horn", _loco.global_position, clampf(1.15 - d / 240.0, 0.25, 1.0), 0.02)


func _tick_lights() -> void:
	# headlight only earns its cost after dark; the marker lamp always burns
	var night: bool = WorldState.game_hour >= 18.6 or WorldState.game_hour < 6.4
	if _head != null:
		_head.light_energy = 3.2 if night else 0.0
	if _tail != null:
		_tail.light_energy = 1.5 if night else 0.7


func _tick_hazard(delta: float) -> void:
	## Standing on the viaduct is a choice, and the train collects on it.
	_hit_cd = maxf(0.0, _hit_cd - delta)
	if _hit_cd > 0.0:
		return
	var pl := _player()
	if pl == null or _loco == null:
		return
	var pp: Vector3 = pl.global_position
	# only relevant on the deck itself, not on the street 8 m below
	if absf(pp.y - _y) > 2.2 or absf(pp.z - _z) > 3.4:
		return
	# is the player inside the length of the consist?
	var tail_x: float = _x
	if _cars.size() > 0:
		tail_x = _x - float(_cars[_cars.size() - 1]["offset"]) - 7.0
	if pp.x < tail_x - 2.0 or pp.x > _x + 9.0:
		return
	_hit_cd = 1.4
	AudioDirector.sfx_at("slam", pp, 0.9, 0.05)
	Effects.add_shake(0.55)
	var combat = pl.get("combat")
	if combat != null and combat.has_method("take_hit"):
		combat.take_hit(34.0, Vector3(SPEED, 0, 0).normalized() * -1.0, "train", null)
	# and throw them clear of the rails rather than letting them ride
	if pl is CharacterBody3D:
		(pl as CharacterBody3D).velocity = Vector3(SPEED * 0.35, 4.0, 6.5 * (1.0 if pp.z > _z else -1.0))


func _player() -> Node3D:
	var ps := get_tree().get_nodes_in_group("player")
	return ps[0] if ps.size() > 0 else null


## Where the locomotive is right now — the HUD, missions and the harness can
## all ask without walking the tree.
func speed() -> float:
	## Consist speed in m/s. Exposed because `SPEED` is a const, and constants
	## are not properties — Object.get("SPEED") silently returns null.
	return SPEED


func span() -> float:
	## Full west-to-east traverse in metres, including the horizon margins the
	## consist wraps through. One lap of the line takes span()/SPEED seconds.
	return _x1 - _x0


func seconds_to_crossing(x: float) -> float:
	## How long until the locomotive reaches world x — counting the wrap, so a
	## consist that has already passed gives you the NEXT one rather than a
	## negative number. Missions use this as a deadline that is always fair.
	return fposmod(x - _x, _x1 - _x0) / SPEED


func train_position() -> Vector3:
	return _loco.global_position if _loco != null else Vector3.ZERO


func train_distance_to(p: Vector3) -> float:
	return _loco.global_position.distance_to(p) if _loco != null else 9999.0
