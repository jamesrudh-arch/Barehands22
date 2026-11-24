extends Node3D
## Wildlife — the living layer of Cinder City.
##
## Before this the city had 234 sound effects, six districts, traffic and
## crowds, and not one creature in it: no birds off the rooftops, no gulls
## over the harbour, no rats in the alleys, no moths at the neon, no fish
## breaking the water. data/events.json even promised "a dock cat leads
## someone somewhere it wants to be fed" — with no cat in the game.
##
## Design rules:
##   - Procedural geometry only, like everything else here. No external art,
##     no canned clips: a bird is a body plus two wings whose flap phase is
##     driven by what the bird is DOING (perched = still, climbing = fast).
##   - Budgeted for mobile. Creatures exist only inside LIVE_RADIUS of the
##     player and are pooled; despawn uses a wider radius than spawn so
##     nothing pops at the boundary. Counts are hard caps, not per-frame
##     allocations.
##   - Reactive through Bus, so the city reads as one system rather than a
##     decoration layer: gunfire empties a rooftop, a player walking an alley
##     scatters rats, neon draws moths after dark, the harbour feeds gulls.
##   - Every sound is positional (AudioDirector.sfx_at) and throttled, so a
##     flock is heard as individuals, never as a wall of noise.

## ---------------------------------------------------------------- budget --
const LIVE_RADIUS := 58.0        # creatures only exist this close
const DESPAWN_RADIUS := 78.0     # hysteresis: never pop at the spawn edge
const MAX_BIRDS := 14
const MAX_RATS := 8
const MAX_STRAYS := 5
const MAX_FISH := 6
const MAX_MOTH_SITES := 6

const BIRD_SFX_CD := 2.6         # min seconds between bird calls (global)
const STARTLE_RADIUS := 34.0     # a crime this close empties the rooftops

var _birds: Array = []
var _rats: Array = []
var _strays: Array = []
var _fish: Array = []
var _moth_sites: Array = []      # {node: GPUParticles3D, lamp: Vector3}

var _player: Node3D = null
var _t := 0.0
var _spawn_cd := 0.0
var _moth_cd := 0.0
var _bird_sfx_cd := 0.0
var _rat_sfx_cd := 0.0
var _stray_sfx_cd := 0.0
var _night := false

# harbour water surface (matches world_gen _build_water)
var _water_y := -0.6
var _water_z := -380.0        # city.json world.water_z = the SHOREWARD edge
var _water_cx := 100.0
var _water_cz := -510.0       # world_gen centres the sheet 130 m seaward
var _water_half_x := 700.0
var _water_half_z := 130.0

# shared meshes + materials, built once and reused by every instance
var _mbird: ArrayMesh
var _mwing: ArrayMesh
var _mrat: ArrayMesh
var _mtail: ArrayMesh
var _mcat: ArrayMesh
var _mdog: ArrayMesh
var _mfish: ArrayMesh
var _mat_feather: StandardMaterial3D
var _mat_gull: StandardMaterial3D
var _mat_fur_dark: StandardMaterial3D
var _mat_fur_tabby: StandardMaterial3D
var _mat_fur_dog: StandardMaterial3D
var _mat_scale: StandardMaterial3D


func _ready() -> void:
	_build_meshes()
	_build_materials()
	var w: Dictionary = Db.districts.get("world", {})
	if w.has("water_z"):
		_water_z = float(w["water_z"])
		# _build_water puts the sheet centre 130 m seaward of water_z and
		# spans 260 m, so the shoreward edge IS water_z. Getting this wrong
		# spawns fish on the docks.
		_water_cz = _water_z - 130.0
	Bus.crime_committed.connect(_on_crime)


func _exit_tree() -> void:
	if Bus.crime_committed.is_connected(_on_crime):
		Bus.crime_committed.disconnect(_on_crime)


# ================================================================ GEOMETRY ==
## SurfaceTool discipline learned the hard way (wave 47): EVERY vertex gets a
## UV. SurfaceTool latches ARRAY_FORMAT_TEX_UV on the first vertex and rejects
## set_uv afterwards, which silently leaves surfaces sampling UV (0,0).

func _suv(st: SurfaceTool, uv: Vector2, v: Vector3) -> void:
	st.set_uv(uv)
	st.add_vertex(v)


func _sbox(st: SurfaceTool, c: Vector3, sz: Vector3) -> void:
	## Axis-aligned box, outward winding, one UV tile per face.
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
	## Tapered cylinder a->b, side quads + caps. Used for legs, tails, beaks.
	var axis := (b - a).normalized()
	if axis.length_squared() < 0.0001:
		return
	var ref := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u := axis.cross(ref).normalized()
	var v := axis.cross(u).normalized()
	var ring_a: Array = []
	var ring_b: Array = []
	for i in seg:
		var ang := TAU * float(i) / float(seg)
		var d := u * cos(ang) + v * sin(ang)
		ring_a.append(a + d * ra)
		ring_b.append(b + d * rb)
	for i in seg:
		var j := (i + 1) % seg
		var u0 := float(i) / float(seg)
		var u1 := float(j) / float(seg)
		_suv(st, Vector2(u0, 0), ring_a[i]); _suv(st, Vector2(u1, 0), ring_a[j])
		_suv(st, Vector2(u1, 1), ring_b[j]); _suv(st, Vector2(u0, 0), ring_a[i])
		_suv(st, Vector2(u1, 1), ring_b[j]); _suv(st, Vector2(u0, 1), ring_b[i])
	# caps (fans)
	_scap(st, ring_a, a, false)
	_scap(st, ring_b, b, true)


func _scap(st: SurfaceTool, ring: Array, centre: Vector3, front: bool) -> void:
	var rad := 0.001
	for p in ring:
		rad = maxf(rad, (p - centre).length())
	var uvs: Array = []
	for p in ring:
		var d: Vector3 = (p - centre) / rad
		uvs.append(Vector2(0.5 + d.x * 0.5, 0.5 + d.z * 0.5))
	for i in ring.size():
		var j := (i + 1) % ring.size()
		if front:
			_suv(st, Vector2(0.5, 0.5), centre); _suv(st, uvs[j], ring[j]); _suv(st, uvs[i], ring[i])
		else:
			_suv(st, Vector2(0.5, 0.5), centre); _suv(st, uvs[i], ring[i]); _suv(st, uvs[j], ring[j])


func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


func _build_meshes() -> void:
	# ---- bird body: torso + head + beak + tail fan ------------------------
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(st, Vector3(0, 0, 0), Vector3(0.085, 0.095, 0.19))            # torso
	_scyl(st, Vector3(0, 0.05, 0.09), Vector3(0, 0.075, 0.155), 0.042, 0.038, 7)   # neck/head
	_scyl(st, Vector3(0, 0.075, 0.155), Vector3(0, 0.070, 0.205), 0.020, 0.004, 5) # beak
	_scyl(st, Vector3(0, 0.01, -0.09), Vector3(0, 0.03, -0.20), 0.030, 0.006, 5)   # tail
	_mbird = _commit(st)

	# ---- wing: a flat tapered plate, root at origin so it can pivot -------
	var sw := SurfaceTool.new()
	sw.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(sw, Vector3(0.10, 0, 0), Vector3(0.20, 0.012, 0.13))
	_sbox(sw, Vector3(0.235, 0, -0.005), Vector3(0.09, 0.008, 0.085))
	_mwing = _commit(sw)

	# ---- rat: low body, pointed snout, big ears ---------------------------
	var sr := SurfaceTool.new()
	sr.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(sr, Vector3(0, 0.045, 0), Vector3(0.075, 0.075, 0.20))        # body
	_scyl(sr, Vector3(0, 0.05, 0.10), Vector3(0, 0.045, 0.175), 0.032, 0.010, 6)  # snout
	_sbox(sr, Vector3(-0.032, 0.095, 0.085), Vector3(0.030, 0.030, 0.012))        # ear l
	_sbox(sr, Vector3(0.032, 0.095, 0.085), Vector3(0.030, 0.030, 0.012))         # ear r
	for sx in [-1.0, 1.0]:
		for sz in [-0.06, 0.06]:
			_scyl(sr, Vector3(sx * 0.03, 0.03, sz), Vector3(sx * 0.035, 0.0, sz), 0.009, 0.007, 4)
	_mrat = _commit(sr)

	# ---- shared tail: tapered, root at origin -----------------------------
	var stl := SurfaceTool.new()
	stl.begin(Mesh.PRIMITIVE_TRIANGLES)
	_scyl(stl, Vector3(0, 0, 0), Vector3(0, 0.02, -0.26), 0.014, 0.003, 5)
	_mtail = _commit(stl)

	# ---- cat: compact body, head, ears, legs ------------------------------
	var sc := SurfaceTool.new()
	sc.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(sc, Vector3(0, 0.16, 0), Vector3(0.115, 0.135, 0.34))         # body
	_sbox(sc, Vector3(0, 0.245, 0.20), Vector3(0.115, 0.115, 0.115))    # head
	_sbox(sc, Vector3(-0.038, 0.325, 0.20), Vector3(0.030, 0.045, 0.020))  # ear l
	_sbox(sc, Vector3(0.038, 0.325, 0.20), Vector3(0.030, 0.045, 0.020))   # ear r
	for sx in [-1.0, 1.0]:
		for sz in [-0.11, 0.11]:
			_scyl(sc, Vector3(sx * 0.042, 0.13, sz), Vector3(sx * 0.042, 0.0, sz), 0.021, 0.017, 5)
	_mcat = _commit(sc)

	# ---- dog: longer body, muzzle, legs -----------------------------------
	var sd := SurfaceTool.new()
	sd.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sbox(sd, Vector3(0, 0.32, 0), Vector3(0.19, 0.21, 0.56))           # body
	_sbox(sd, Vector3(0, 0.42, 0.32), Vector3(0.155, 0.155, 0.15))      # head
	_scyl(sd, Vector3(0, 0.40, 0.40), Vector3(0, 0.375, 0.50), 0.045, 0.030, 6)  # muzzle
	for sx in [-1.0, 1.0]:
		for sz in [-0.19, 0.19]:
			_scyl(sd, Vector3(sx * 0.065, 0.26, sz), Vector3(sx * 0.065, 0.0, sz), 0.030, 0.024, 5)
	_mdog = _commit(sd)

	# ---- fish: body + tail fin + dorsal -----------------------------------
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	_scyl(sf, Vector3(0, 0, -0.17), Vector3(0, 0, 0.13), 0.012, 0.052, 7)   # nose -> body
	_scyl(sf, Vector3(0, 0, 0.13), Vector3(0, 0, 0.24), 0.052, 0.014, 7)    # body -> tail base
	_sbox(sf, Vector3(0, 0, 0.30), Vector3(0.012, 0.13, 0.11))              # tail fin
	_sbox(sf, Vector3(0, 0.055, 0.05), Vector3(0.010, 0.055, 0.10))         # dorsal
	_mfish = _commit(sf)


func _build_materials() -> void:
	_mat_feather = StandardMaterial3D.new()
	_mat_feather.albedo_color = Color(0.30, 0.30, 0.34)     # city pigeon slate
	_mat_feather.roughness = 0.88
	_mat_gull = StandardMaterial3D.new()
	_mat_gull.albedo_color = Color(0.86, 0.87, 0.88)        # harbour gull
	_mat_gull.roughness = 0.80
	_mat_fur_dark = StandardMaterial3D.new()
	_mat_fur_dark.albedo_color = Color(0.17, 0.155, 0.145)  # alley rat
	_mat_fur_dark.roughness = 0.95
	_mat_fur_tabby = StandardMaterial3D.new()
	_mat_fur_tabby.albedo_color = Color(0.40, 0.33, 0.24)   # dock cat
	_mat_fur_tabby.roughness = 0.92
	_mat_fur_dog = StandardMaterial3D.new()
	_mat_fur_dog.albedo_color = Color(0.33, 0.27, 0.22)
	_mat_fur_dog.roughness = 0.93
	_mat_scale = StandardMaterial3D.new()
	_mat_scale.albedo_color = Color(0.42, 0.50, 0.52)
	_mat_scale.roughness = 0.35
	_mat_scale.metallic = 0.25


# ================================================================= SPAWNING ==
func _process(delta: float) -> void:
	_t += delta
	_night = WorldState.game_hour >= 19.0 or WorldState.game_hour < 6.0
	var ps := _tree_players()
	_player = ps[0] if ps.size() > 0 else null
	_bird_sfx_cd = maxf(0.0, _bird_sfx_cd - delta)
	_rat_sfx_cd = maxf(0.0, _rat_sfx_cd - delta)
	_stray_sfx_cd = maxf(0.0, _stray_sfx_cd - delta)

	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 1.1
		_despawn_far()
		if _player != null:
			_top_up_birds()
			_top_up_rats()
			_top_up_strays()
			_top_up_fish()
	_moth_cd -= delta
	if _moth_cd <= 0.0:
		_moth_cd = 4.0
		_update_moths()

	_tick_birds(delta)
	_tick_rats(delta)
	_tick_strays(delta)
	_tick_fish(delta)
	_tick_moths(delta)


func _tree_players() -> Array:
	return get_tree().get_nodes_in_group("player")


## Rooftop perches near a point, from the fire-escape records worldgen keeps.
func _near_rooftops(centre: Vector3, radius: float, want: int) -> Array:
	var out: Array = []
	var cp: Array = WorldGen.climb_points
	var cand: Array = []
	for c in cp:
		var top: Vector3 = c["top"]
		if top.distance_to(centre) < radius:
			cand.append(top)
	cand.shuffle()
	for i in mini(want, cand.size()):
		out.append(cand[i] + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2)))
	return out


func _ground_at(p: Vector3) -> Vector3:
	## Ray down for the real surface height (sidewalk, roof, crate).
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3(p.x, 0.0, p.z)
	var q := PhysicsRayQueryParameters3D.new()
	q.from = Vector3(p.x, p.y + 40.0, p.z)
	q.to = Vector3(p.x, p.y - 6.0, p.z)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3(p.x, 0.0, p.z)
	return hit["position"]


func _despawn_far() -> void:
	if _player == null:
		return
	var p := _player.global_position
	for list in [_birds, _rats, _strays, _fish]:
		for i in range(list.size() - 1, -1, -1):
			var c: Dictionary = list[i]
			var n: Node = c["node"]
			if not is_instance_valid(n) or n.global_position.distance_to(p) > DESPAWN_RADIUS:
				if is_instance_valid(n):
					n.queue_free()
				list.remove_at(i)


# ================================================================== BIRDS ===
func _top_up_birds() -> void:
	if _birds.size() >= MAX_BIRDS:
		return
	var p := _player.global_position
	var roofs := _near_rooftops(p, LIVE_RADIUS, MAX_BIRDS - _birds.size())
	for r in roofs:
		if _birds.size() >= MAX_BIRDS:
			break
		_spawn_bird(r, "perch")
	# Not every street has a fire escape within reach, and a city with no
	# birds in it reads as abandoned. Pigeons work the pavement anyway, so
	# when the rooftops come up short they forage on the ground nearby.
	var short := MAX_BIRDS - _birds.size()
	if short > 0:
		for i in mini(short, 4):
			var ang := randf() * TAU
			var dist := randf_range(7.0, 26.0)
			var g := _ground_at(p + Vector3(cos(ang) * dist, 0, sin(ang) * dist))
			_spawn_bird(g + Vector3(0, 0.05, 0), "perch")
	# gulls work the harbour: circle low over the water when it is near
	if _water_near(p) and _birds.size() < MAX_BIRDS:
		var gp := Vector3(clampf(p.x, _water_cx - _water_half_x, _water_cx + _water_half_x),
			_water_y + randf_range(4.0, 9.0),
			clampf(_water_cz + 40.0, _water_cz - _water_half_z, _water_cz + _water_half_z))
		_spawn_bird(gp, "circle", true)


func _water_near(p: Vector3) -> bool:
	return absf(p.z - _water_cz) < _water_half_z + 70.0 and absf(p.x - _water_cx) < _water_half_x


func _spawn_bird(at: Vector3, state: String, gull: bool = false) -> void:
	var n := Node3D.new()
	n.name = "Bird"
	var body := MeshInstance3D.new()
	body.mesh = _mbird
	body.material_override = _mat_gull if gull else _mat_feather
	n.add_child(body)
	var wl := MeshInstance3D.new()
	wl.mesh = _mwing
	wl.material_override = body.material_override
	wl.position = Vector3(-0.04, 0.03, 0.0)
	n.add_child(wl)
	var wr := MeshInstance3D.new()
	wr.mesh = _mwing
	wr.material_override = body.material_override
	wr.scale = Vector3(-1, 1, 1)          # mirror the wing
	wr.position = Vector3(0.04, 0.03, 0.0)
	n.add_child(wr)
	add_child(n)
	n.global_position = at
	if not gull:
		var g := _ground_at(at)
		n.global_position = g + Vector3(0, 0.05, 0)
	_birds.append({
		"node": n, "wing_l": wl, "wing_r": wr, "body": body,
		"state": state, "t": randf() * 10.0, "phase": randf() * TAU,
		"gull": gull, "flee_t": 0.0, "vel": Vector3.ZERO,
		"centre": n.global_position, "radius": randf_range(5.0, 13.0),
		"alt": n.global_position.y, "hop_t": randf_range(1.5, 6.0),
		"yaw": randf() * TAU, "idle": randf_range(1.0, 5.0),
	})


func _tick_birds(delta: float) -> void:
	for c in _birds:
		var n: Node3D = c["node"]
		if not is_instance_valid(n):
			continue
		c["t"] += delta
		var st: String = c["state"]
		var wl: MeshInstance3D = c["wing_l"]
		var wr: MeshInstance3D = c["wing_r"]

		if st == "flee":
			c["flee_t"] -= delta
			# hard flapping, climbing, straight out of here
			var rate := 26.0
			var flap: float = sin(c["t"] * rate)
			wl.rotation.z = deg_to_rad(18.0 + 62.0 * flap)
			wr.rotation.z = deg_to_rad(-18.0 - 62.0 * flap)
			var v: Vector3 = c["vel"]
			v.y += 5.2 * delta
			v = v.limit_length(16.0)
			c["vel"] = v
			n.global_position += v * delta
			n.rotation.y = atan2(v.x, v.z)
			n.rotation.x = clampf(-v.y * 0.035, -0.45, 0.35)
			if c["flee_t"] <= 0.0:
				c["state"] = "circle" if c["gull"] else "perch"
				c["centre"] = n.global_position
				c["alt"] = n.global_position.y
			continue

		if st == "circle":
			# lazy thermal circle; gulls hold low over the water
			var a: float = c["t"] * 0.42 + c["phase"]
			var r: float = c["radius"]
			var target := Vector3(c["centre"].x + cos(a) * r,
				c["alt"] + sin(c["t"] * 0.7 + c["phase"]) * 1.4,
				c["centre"].z + sin(a) * r)
			var prev: Vector3 = n.global_position
			n.global_position = prev.lerp(target, clampf(delta * 2.2, 0.0, 1.0))
			var d := n.global_position - prev
			if d.length_squared() > 0.000001:
				n.rotation.y = atan2(d.x, d.z)
			n.rotation.z = sin(a) * 0.30          # bank into the turn
			var slow: float = 6.5 + 2.0 * sin(c["t"] * 0.9)
			var f2: float = sin(c["t"] * slow + c["phase"])
			wl.rotation.z = deg_to_rad(8.0 + 20.0 * f2)
			wr.rotation.z = deg_to_rad(-8.0 - 20.0 * f2)
			# occasional call, positional and throttled
			if _bird_sfx_cd <= 0.0 and _near_player(n, 40.0):
				_bird_sfx_cd = BIRD_SFX_CD + randf() * 2.0
				if c["gull"]:
					AudioDirector.sfx_at("gull_cry", n.global_position, 0.5, 0.10)
				else:
					AudioDirector.sfx_at("crow_caw", n.global_position, 0.34, 0.12)
			continue

		# --- perched / ground ---
		c["idle"] -= delta
		var flap3: float = sin(c["t"] * 3.1 + c["phase"]) * 0.06
		wl.rotation.z = deg_to_rad(4.0) + flap3
		wr.rotation.z = deg_to_rad(-4.0) - flap3
		# head bob + occasional hop
		c["body"].rotation.x = sin(c["t"] * 2.2 + c["phase"]) * 0.10
		if c["idle"] <= 0.0:
			c["idle"] = randf_range(2.0, 7.0)
			if randf() < 0.35:
				c["state"] = "hop"
				c["hop_t"] = randf_range(0.8, 2.0)
				c["yaw"] = randf() * TAU
			elif _bird_sfx_cd <= 0.0 and _near_player(n, 34.0):
				_bird_sfx_cd = BIRD_SFX_CD + randf() * 2.4
				AudioDirector.sfx_at("bird_chirp_%d" % (randi() % 3), n.global_position, 0.30, 0.14)
		if c["state"] == "hop":
			c["hop_t"] -= delta
			var dir := Vector3(sin(c["yaw"]), 0, cos(c["yaw"]))
			var bounce: float = absf(sin(c["t"] * 9.0))
			n.global_position += dir * 1.15 * delta
			n.global_position.y = c["centre"].y + 0.05 + bounce * 0.07
			n.rotation.y = c["yaw"]
			var f4: float = sin(c["t"] * 18.0)
			wl.rotation.z = deg_to_rad(10.0 + 30.0 * maxf(0.0, f4))
			wr.rotation.z = deg_to_rad(-10.0 - 30.0 * maxf(0.0, f4))
			if c["hop_t"] <= 0.0:
				c["state"] = "perch"
				c["centre"] = n.global_position


## Gunfire, explosions and violence empty the rooftops.
func _on_crime(_crime: String, severity: int, pos: Vector3) -> void:
	if severity < 1:
		return
	for c in _birds:
		var n: Node3D = c["node"]
		if not is_instance_valid(n):
			continue
		var d := n.global_position.distance_to(pos)
		if d > STARTLE_RADIUS:
			continue
		if c["state"] == "flee":
			continue
		c["state"] = "flee"
		c["flee_t"] = randf_range(3.2, 5.6)
		var away := (n.global_position - pos)
		away.y = 0.0
		if away.length_squared() < 0.001:
			away = Vector3(randf() - 0.5, 0, randf() - 0.5)
		c["vel"] = away.normalized() * randf_range(7.0, 11.0) + Vector3(0, 3.0, 0)
	# the flock going up is itself a sound cue
	if _near_pos(pos, 46.0):
		AudioDirector.sfx_at("wing_flutter", pos + Vector3(0, 4, 0), 0.55, 0.10)
	# rats bolt from noise too
	for r in _rats:
		var rn: Node3D = r["node"]
		if is_instance_valid(rn) and rn.global_position.distance_to(pos) < STARTLE_RADIUS * 0.6:
			r["state"] = "flee"
			r["flee_t"] = randf_range(1.6, 3.0)
			var aw := (rn.global_position - pos)
			aw.y = 0.0
			if aw.length_squared() > 0.001:
				r["vel"] = aw.normalized() * 5.2
			else:
				r["vel"] = Vector3(randf() - 0.5, 0, randf() - 0.5).normalized() * 5.2


func _near_player(n: Node3D, radius: float) -> bool:
	return _player != null and is_instance_valid(n) and n.global_position.distance_to(_player.global_position) < radius


func _near_pos(p: Vector3, radius: float) -> bool:
	return _player != null and p.distance_to(_player.global_position) < radius


# =================================================================== RATS ===
func _top_up_rats() -> void:
	# rats are a night creature; a couple still work the alleys by day
	var cap := MAX_RATS if _night else 3
	if _rats.size() >= cap:
		return
	var p := _player.global_position
	for i in cap - _rats.size():
		var ang := randf() * TAU
		var dist := randf_range(14.0, LIVE_RADIUS * 0.8)
		var at := _ground_at(p + Vector3(cos(ang) * dist, 0, sin(ang) * dist))
		_spawn_rat(at + Vector3(0, 0.02, 0))


func _spawn_rat(at: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Rat"
	var body := MeshInstance3D.new()
	body.mesh = _mrat
	body.material_override = _mat_fur_dark
	n.add_child(body)
	var tail := MeshInstance3D.new()
	tail.mesh = _mtail
	tail.material_override = _mat_fur_dark
	tail.scale = Vector3(0.7, 0.7, 0.75)
	tail.position = Vector3(0, 0.055, -0.10)
	n.add_child(tail)
	add_child(n)
	n.global_position = at
	_rats.append({
		"node": n, "body": body, "tail": tail, "state": "sniff",
		"t": randf() * 10.0, "flee_t": 0.0, "vel": Vector3.ZERO,
		"idle": randf_range(0.6, 3.0), "yaw": randf() * TAU, "home": at,
	})


func _tick_rats(delta: float) -> void:
	for c in _rats:
		var n: Node3D = c["node"]
		if not is_instance_valid(n):
			continue
		c["t"] += delta
		var tail: MeshInstance3D = c["tail"]
		tail.rotation.y = sin(c["t"] * 5.5) * 0.35

		if c["state"] == "flee":
			c["flee_t"] -= delta
			var v: Vector3 = c["vel"]
			n.global_position += v * delta
			n.global_position.y = _ground_at(n.global_position).y + 0.02
			if v.length_squared() > 0.001:
				n.rotation.y = atan2(v.x, v.z)
			# scuttle bob
			c["body"].position.y = absf(sin(c["t"] * 22.0)) * 0.008
			if _rat_sfx_cd <= 0.0 and _near_player(n, 16.0):
				_rat_sfx_cd = 1.4 + randf()
				AudioDirector.sfx_at("rat_scuttle", n.global_position, 0.30, 0.14)
			if c["flee_t"] <= 0.0:
				c["state"] = "sniff"
				c["idle"] = randf_range(0.8, 2.6)
				c["home"] = n.global_position
			continue

		# a player this close is always worth running from
		if _player != null and n.global_position.distance_to(_player.global_position) < 3.6:
			c["state"] = "flee"
			c["flee_t"] = randf_range(1.2, 2.4)
			var away := (n.global_position - _player.global_position)
			away.y = 0.0
			if away.length_squared() < 0.001:
				away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			c["vel"] = away.normalized() * randf_range(3.6, 5.4)
			if _rat_sfx_cd <= 0.0 and _near_player(n, 14.0):
				_rat_sfx_cd = 2.2
				AudioDirector.sfx_at("rat_squeak", n.global_position, 0.26, 0.18)
			continue

		c["idle"] -= delta
		c["body"].position.y = 0.0
		# sniffing: head darts side to side
		c["body"].rotation.y = sin(c["t"] * 7.0) * 0.22
		if c["idle"] <= 0.0:
			c["idle"] = randf_range(1.0, 3.4)
			if randf() < 0.55:
				c["state"] = "flee"          # "flee" doubles as a casual dart
				c["flee_t"] = randf_range(0.35, 0.9)
				c["yaw"] = randf() * TAU
				c["vel"] = Vector3(sin(c["yaw"]), 0, cos(c["yaw"])) * randf_range(1.4, 2.6)


# ================================================================== STRAYS ==
func _top_up_strays() -> void:
	if _strays.size() >= MAX_STRAYS:
		return
	var p := _player.global_position
	for i in MAX_STRAYS - _strays.size():
		var ang := randf() * TAU
		var dist := randf_range(16.0, LIVE_RADIUS * 0.75)
		var at := _ground_at(p + Vector3(cos(ang) * dist, 0, sin(ang) * dist))
		_spawn_stray(at + Vector3(0, 0.02, 0), "cat" if randf() < 0.5 else "dog")


func _spawn_stray(at: Vector3, kind: String) -> void:
	var n := Node3D.new()
	n.name = "Stray"
	var body := MeshInstance3D.new()
	var tail := MeshInstance3D.new()
	var head := MeshInstance3D.new()
	if kind == "cat":
		body.mesh = _mcat
		body.material_override = _mat_fur_tabby
		tail.mesh = _mtail
		tail.material_override = _mat_fur_tabby
		tail.scale = Vector3(1.1, 1.1, 1.3)
		tail.position = Vector3(0, 0.20, -0.17)
		tail.rotation.x = deg_to_rad(-55.0)
	else:
		body.mesh = _mdog
		body.material_override = _mat_fur_dog
		tail.mesh = _mtail
		tail.material_override = _mat_fur_dog
		tail.scale = Vector3(1.2, 1.2, 0.7)
		tail.position = Vector3(0, 0.40, -0.28)
		tail.rotation.x = deg_to_rad(-40.0)
	n.add_child(body)
	n.add_child(tail)
	add_child(n)
	n.global_position = at
	_strays.append({
		"node": n, "body": body, "tail": tail, "head": head, "kind": kind,
		"state": "sit" if kind == "cat" else "roam",
		"t": randf() * 10.0, "idle": randf_range(2.0, 8.0),
		"yaw": randf() * TAU, "vel": Vector3.ZERO, "watch": 0.0,
		"home": at, "bark_cd": randf_range(3.0, 12.0),
	})


func _tick_strays(delta: float) -> void:
	for c in _strays:
		var n: Node3D = c["node"]
		if not is_instance_valid(n):
			continue
		c["t"] += delta
		var tail: MeshInstance3D = c["tail"]
		var body: MeshInstance3D = c["body"]
		var kind: String = c["kind"]
		var st: String = c["state"]

		if st == "flee":
			c["idle"] -= delta
			var v: Vector3 = c["vel"]
			n.global_position += v * delta
			n.global_position.y = _ground_at(n.global_position).y + 0.02
			if v.length_squared() > 0.001:
				n.rotation.y = atan2(v.x, v.z)
			# gallop: body pitches and the tail streams
			body.rotation.x = sin(c["t"] * 13.0) * 0.11
			body.position.y = absf(sin(c["t"] * 13.0)) * (0.030 if kind == "cat" else 0.045)
			tail.rotation.y = sin(c["t"] * 9.0) * 0.20
			if c["idle"] <= 0.0:
				c["state"] = "sit" if kind == "cat" else "roam"
				c["idle"] = randf_range(3.0, 9.0)
			continue

		if kind == "cat":
			# a dock cat mostly sits, flicks its tail, and watches you
			tail.rotation.y = sin(c["t"] * 2.4) * 0.45
			tail.rotation.z = sin(c["t"] * 1.7) * 0.18
			body.rotation.x = sin(c["t"] * 1.1) * 0.025        # breathing
			if _player != null:
				var to_p := _player.global_position - n.global_position
				to_p.y = 0.0
				if to_p.length() < 18.0:
					var want := atan2(to_p.x, to_p.z)
					n.rotation.y = lerp_angle(n.rotation.y, want, clampf(delta * 2.0, 0.0, 1.0))
					c["watch"] = 1.0
				# bolt if you run at it
				if to_p.length() < 2.6:
					c["state"] = "flee"
					c["idle"] = randf_range(2.0, 4.0)
					var aw := -to_p
					if aw.length_squared() < 0.001:
						aw = Vector3(randf() - 0.5, 0, randf() - 0.5)
					c["vel"] = aw.normalized() * 5.6
					if _stray_sfx_cd <= 0.0 and _near_player(n, 20.0):
						_stray_sfx_cd = 5.0
						AudioDirector.sfx_at("cat_meow", n.global_position, 0.55, 0.10)
			c["idle"] -= delta
			if c["idle"] <= 0.0:
				c["idle"] = randf_range(6.0, 16.0)
				if randf() < 0.30 and _stray_sfx_cd <= 0.0 and _near_player(n, 26.0):
					_stray_sfx_cd = 7.0
					AudioDirector.sfx_at("cat_meow", n.global_position, 0.42, 0.12)
		else:
			# dogs roam, and they have opinions about you
			c["idle"] -= delta
			c["bark_cd"] -= delta
			tail.rotation.y = sin(c["t"] * (9.0 if c["watch"] > 0.0 else 3.0)) * 0.42
			if _player != null:
				var dp := _player.global_position - n.global_position
				dp.y = 0.0
				c["watch"] = 1.0 if dp.length() < 14.0 else 0.0
				if dp.length() < 14.0:
					var want2 := atan2(dp.x, dp.z)
					n.rotation.y = lerp_angle(n.rotation.y, want2, clampf(delta * 2.4, 0.0, 1.0))
				if c["bark_cd"] <= 0.0 and dp.length() < 11.0:
					c["bark_cd"] = randf_range(6.0, 18.0)
					if _stray_sfx_cd <= 0.0:
						_stray_sfx_cd = 2.0
						AudioDirector.sfx_at("dog_bark", n.global_position, 0.60, 0.10)
			if c["idle"] <= 0.0:
				c["idle"] = randf_range(3.0, 8.0)
				if randf() < 0.6:
					# trot off in a new direction
					c["yaw"] = randf() * TAU
					c["vel"] = Vector3(sin(c["yaw"]), 0, cos(c["yaw"])) * randf_range(1.2, 2.2)
					c["state"] = "walk"
					c["walk_t"] = randf_range(1.5, 4.0)
			if st == "walk":
				c["walk_t"] = float(c.get("walk_t", 0.0)) - delta
				n.global_position += c["vel"] * delta
				n.global_position.y = _ground_at(n.global_position).y + 0.02
				if c["vel"].length_squared() > 0.001:
					n.rotation.y = atan2(c["vel"].x, c["vel"].z)
				body.position.y = absf(sin(c["t"] * 8.0)) * 0.022
				body.rotation.x = sin(c["t"] * 8.0) * 0.05
				if c["walk_t"] <= 0.0:
					c["state"] = "roam"
					c["vel"] = Vector3.ZERO
					body.position.y = 0.0
					body.rotation.x = 0.0


# =================================================================== FISH ===
func _top_up_fish() -> void:
	var p := _player.global_position
	if not _water_near(p):
		return
	if _fish.size() >= MAX_FISH:
		return
	for i in MAX_FISH - _fish.size():
		var x := clampf(p.x + randf_range(-55.0, 55.0),
			_water_cx - _water_half_x + 25.0, _water_cx + _water_half_x - 25.0)
		# shoreward half of the sheet: between the centre and the quay edge,
		# which is where a player standing on the docks can actually see them
		var z := clampf(_water_cz + randf_range(12.0, _water_half_z - 12.0),
			_water_cz - _water_half_z + 12.0, _water_cz + _water_half_z - 12.0)
		_spawn_fish(Vector3(x, _water_y - 0.5, z))


func _spawn_fish(at: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Fish"
	var body := MeshInstance3D.new()
	body.mesh = _mfish
	body.material_override = _mat_scale
	n.add_child(body)
	add_child(n)
	n.global_position = at
	n.visible = false
	_fish.append({
		"node": n, "body": body, "state": "idle", "t": randf() * 20.0,
		"jump_t": randf_range(2.0, 14.0), "arc": 0.0, "start": at,
		"dir": Vector3(randf() - 0.5, 0, randf() - 0.5).normalized(),
		"power": randf_range(2.2, 4.0),
	})


func _tick_fish(delta: float) -> void:
	for c in _fish:
		var n: Node3D = c["node"]
		if not is_instance_valid(n):
			continue
		c["t"] += delta
		if c["state"] == "idle":
			c["jump_t"] -= delta
			n.visible = false
			if c["jump_t"] <= 0.0 and _near_player(n, 62.0):
				c["state"] = "jump"
				c["arc"] = 0.0
				c["start"] = n.global_position
				c["dir"] = Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
				c["power"] = randf_range(2.2, 4.0)
				n.visible = true
				# the break of the surface is the sound, then the re-entry
				AudioDirector.sfx_at("fish_splash", n.global_position + Vector3(0, 0.3, 0), 0.55, 0.12)
			continue
		# ballistic arc out of the water and back in
		c["arc"] += delta
		var tt: float = c["arc"]
		var total: float = 2.0 * c["power"] / 9.8
		var horiz: Vector3 = c["dir"] * (c["power"] * 0.55) * tt
		var vy: float = c["power"] - 9.8 * tt * 0.5
		n.global_position = Vector3(c["start"].x + horiz.x, _water_y + vy * tt * 0.5, c["start"].z + horiz.z)
		# nose up on the way out, nose down on the way in
		n.rotation.x = clampf(-vy * 0.22, -1.1, 1.1)
		n.rotation.y = atan2(c["dir"].x, c["dir"].z)
		c["body"].rotation.y = sin(tt * 22.0) * 0.35       # tail beat
		if tt >= total:
			c["state"] = "idle"
			c["jump_t"] = randf_range(4.0, 22.0)
			n.visible = false
			n.global_position = Vector3(n.global_position.x, _water_y - 0.5, n.global_position.z)
			if _near_player(n, 46.0):
				AudioDirector.sfx_at("fish_splash", n.global_position + Vector3(0, 0.4, 0), 0.42, 0.14)


# =================================================================== MOTHS ==
func _update_moths() -> void:
	# moths only work the neon after dark; by day the swarms are pulled.
	# Recomputed here rather than trusting _night, which only refreshes in
	# _process — a direct call must still get the right answer.
	var h: float = WorldState.game_hour
	_night = h >= 19.0 or h < 6.0
	if not _night:
		for m in _moth_sites:
			var mn: Node = m["node"]
			if is_instance_valid(mn):
				(mn as GPUParticles3D).emitting = false
		return
	if _player == null:
		return
	if _moth_sites.size() < MAX_MOTH_SITES:
		for i in MAX_MOTH_SITES - _moth_sites.size():
			_moth_sites.append({"node": _make_moth_swarm(), "lamp": Vector3.ZERO})
	# re-site the swarms onto the nearest lamps, skipping ones already taken
	var lamps: Array = WorldGen.nearest_lamp_positions(_player.global_position, MAX_MOTH_SITES * 3)
	var used: Array = []
	for m in _moth_sites:
		var mn: GPUParticles3D = m["node"]
		if not is_instance_valid(mn):
			continue
		var placed := false
		for l in lamps:
			var lp: Vector3 = l["pos"]
			var taken := false
			for u in used:
				if u.distance_to(lp) < 3.0:
					taken = true
					break
			if taken:
				continue
			mn.global_position = lp + Vector3(0, -0.35, 0)
			mn.emitting = true
			used.append(lp)
			m["lamp"] = lp
			placed = true
			break
		if not placed:
			mn.emitting = false


func _make_moth_swarm() -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.name = "MothSwarm"
	gp.amount = 22
	gp.lifetime = 2.6
	gp.local_coords = false
	gp.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.12
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 0.15, 0)
	mat.initial_velocity_min = 0.25
	mat.initial_velocity_max = 0.75
	# orbit rather than drift: a tangential acceleration reads as swarming
	mat.angular_velocity_min = 90.0
	mat.angular_velocity_max = 260.0
	mat.scale_min = 0.6
	mat.scale_max = 1.3
	gp.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.035, 0.028)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.85, 0.80, 0.62, 0.75)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = rm
	gp.draw_pass_1 = qm
	add_child(gp)
	return gp


func _tick_moths(delta: float) -> void:
	if not _night or _player == null:
		return
	# a close swarm should be heard as a thin buzz, not a swarm of speakers
	for m in _moth_sites:
		var mn: Node = m["node"]
		if not is_instance_valid(mn) or not (mn as GPUParticles3D).emitting:
			continue
		if mn.global_position.distance_to(_player.global_position) < 4.5:
			if _bird_sfx_cd <= 0.0:
				_bird_sfx_cd = 3.4
				AudioDirector.sfx_at("insect_buzz", mn.global_position, 0.16, 0.05)
			break
