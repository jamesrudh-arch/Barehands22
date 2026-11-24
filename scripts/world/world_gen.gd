extends Node
## WorldGen — builds Cinder City from data/city.json: road grid, merged block
## geometry (buildings/facades/furniture), landmarks, POI doors, water,
## lane graph for traffic, lamp registry for pooled night lights.
## Static geometry is merged per district into a few ArrayMeshes (draw-call
## budget); simulation (peds/traffic/events) is gated per active district.

var root: Node3D = null
var district_nodes: Dictionary = {}      # id -> Node3D
var district_bounds: Dictionary = {}     # id -> Rect2 (x,z)
var lanes: Array = []                    # Array of PackedVector3Array loops
var lane_district: Array = []
var lamp_posts: Array = []               # {pos, district, color}
var traffic_lights: Array = []           # nodes
var pois: Dictionary = {}                # id -> data + node
var climb_points: Array = []             # {bottom: Vector3, top: Vector3} fire escapes
var interiors: Dictionary = {}
var built := false

# material cache
var _mats: Dictionary = {}
const TEX := "res://assets/textures/world/"

# surface slots for merged district mesh
const S_ASPHALT := 0
const S_SIDEWALK := 1
const S_MARK := 2
const S_FACADE := 3        # per-variant facades appended after
var facade_slots: Dictionary = {}        # facade name -> slot index
var slot_mats: Array = []


func mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"asphalt":
			m.albedo_texture = load(TEX + "asphalt.png")
			m.normal_texture = load(TEX + "asphalt_n.png")
			m.roughness_texture = load(TEX + "asphalt_r.png")
		"asphalt_wet":
			m.albedo_texture = load(TEX + "asphalt_wet.png")
			m.roughness = 0.15
		"sidewalk":
			m.albedo_texture = load(TEX + "sidewalk.png")
			m.normal_texture = load(TEX + "sidewalk_n.png")
		"mark":
			m.albedo_texture = load(TEX + "road_marks.png")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"grass":
			m.albedo_texture = load(TEX + "grass.png")
			m.normal_texture = load(TEX + "grass_n.png")
		"water":
			m.albedo_texture = load(TEX + "water.png")
			m.normal_texture = load(TEX + "water_n.png")
			m.roughness = 0.08
			m.metallic = 0.4
		"concrete":
			m.albedo_texture = load(TEX + "concrete.png")
			m.normal_texture = load(TEX + "concrete_n.png")
		"metal":
			m.albedo_texture = load(TEX + "metal_panel.png")
			m.normal_texture = load(TEX + "metal_panel_n.png")
			m.metallic = 0.6
			m.roughness = 0.4
		"rust":
			m.albedo_texture = load(TEX + "metal_rusted.png")
			m.normal_texture = load(TEX + "metal_rusted_n.png")
			m.roughness = 0.9
		"wood":
			m.albedo_texture = load(TEX + "wood_planks.png")
			m.normal_texture = load(TEX + "wood_planks_n.png")
		"signs":
			m.albedo_texture = load(TEX + "signs_atlas.png")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.emission_enabled = true
			m.emission_texture = load(TEX + "signs_atlas.png")
			m.emission_energy_multiplier = 1.4
		"posters":
			m.albedo_texture = load(TEX + "posters_atlas.png")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"glass":
			m.albedo_texture = load(TEX + "glass_dark.png")
			m.metallic = 0.7
			m.roughness = 0.1
		"foliage":
			m.albedo_color = Color(0.16, 0.24, 0.12)
			m.roughness = 0.95
		"trunk":
			m.albedo_color = Color(0.20, 0.15, 0.11)
		"neon_white":
			m.albedo_color = Color(1, 1, 1)
			m.emission_enabled = true
			m.emission = Color(1, 0.9, 0.8)
			m.emission_energy_multiplier = 3.0
		_:
			if key.begins_with("facade_"):
				m.albedo_texture = load(TEX + key + ".png")
				m.emission_enabled = true
				m.emission_texture = load(TEX + key + "_e.png")
				m.emission_energy_multiplier = 0.0   # raised at night
				m.emission = Color(1, 1, 1)
				if key == "facade_glass":
					m.metallic = 0.6
					m.roughness = 0.12
				else:
					m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mats[key] = m
	return m


# ------------------------------------------------------------- accumulator --
class Acc:
	var slots: Dictionary = {}    # slot -> arrays

	func _s(i: int) -> Dictionary:
		if not slots.has(i):
			slots[i] = {"v": PackedVector3Array(), "n": PackedVector3Array(),
				"uv": PackedVector2Array(), "c": PackedColorArray(), "idx": PackedInt32Array()}
		return slots[i]

	func quad(i: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
			uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2, tint := Color(1, 1, 1)) -> void:
		var s := _s(i)
		var base: int = s["v"].size()
		s["v"].append_array([a, b, c, d])
		s["n"].append_array([n, n, n, n])
		s["uv"].append_array([uv_a, uv_b, uv_c, uv_d])
		s["c"].append_array([tint, tint, tint, tint])
		s["idx"].append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func box(i: int, center: Vector3, size: Vector3, uvs := Vector3(0.15, 0.15, 0.15), tint := Color(1, 1, 1)) -> void:
		var h := size * 0.5
		var c := center
		quad(i, c + Vector3(-h.x, 0, h.z), c + Vector3(h.x, 0, h.z), c + Vector3(h.x, size.y, h.z), c + Vector3(-h.x, size.y, h.z), Vector3(0, 0, 1),
			Vector2(0, 0), Vector2(size.x * uvs.x, 0), Vector2(size.x * uvs.x, size.y * uvs.z), Vector2(0, size.y * uvs.z), tint)
		quad(i, c + Vector3(h.x, 0, -h.z), c + Vector3(-h.x, 0, -h.z), c + Vector3(-h.x, size.y, -h.z), c + Vector3(h.x, size.y, -h.z), Vector3(0, 0, -1),
			Vector2(0, 0), Vector2(size.x * uvs.x, 0), Vector2(size.x * uvs.x, size.y * uvs.z), Vector2(0, size.y * uvs.z), tint)
		quad(i, c + Vector3(h.x, 0, h.z), c + Vector3(h.x, 0, -h.z), c + Vector3(h.x, size.y, -h.z), c + Vector3(h.x, size.y, h.z), Vector3(1, 0, 0),
			Vector2(0, 0), Vector2(size.z * uvs.y, 0), Vector2(size.z * uvs.y, size.y * uvs.z), Vector2(0, size.y * uvs.z), tint)
		quad(i, c + Vector3(-h.x, 0, -h.z), c + Vector3(-h.x, 0, h.z), c + Vector3(-h.x, size.y, h.z), c + Vector3(-h.x, size.y, -h.z), Vector3(-1, 0, 0),
			Vector2(0, 0), Vector2(size.z * uvs.y, 0), Vector2(size.z * uvs.y, size.y * uvs.z), Vector2(0, size.y * uvs.z), tint)
		quad(i, c + Vector3(-h.x, size.y, -h.z), c + Vector3(h.x, size.y, -h.z), c + Vector3(h.x, size.y, h.z), c + Vector3(-h.x, size.y, h.z), Vector3(0, 1, 0),
			Vector2(0, 0), Vector2(size.x * uvs.x, 0), Vector2(size.x * uvs.x, size.z * uvs.y), Vector2(0, size.z * uvs.y), tint)

	func cyl(i: int, from: Vector3, to: Vector3, r1: float, r2: float, seg := 8, tint := Color(1, 1, 1)) -> void:
		var dir := to - from
		var L := dir.length()
		if L < 0.001:
			return
		dir /= L
		var up := Vector3(0, 0, 1) if absf(dir.y) < 0.9 else Vector3(1, 0, 0)
		var x := dir.cross(up).normalized()
		var y := dir.cross(x).normalized()
		var s := _s(i)
		var r1i := []
		var r2i := []
		for k in seg:
			var a := TAU * k / seg
			var off := x * cos(a) + y * sin(a)
			r1i.append(s["v"].size())
			s["v"].append(from + off * r1)
			s["n"].append(off)
			s["uv"].append(Vector2(float(k) / seg, 0))
			s["c"].append(tint)
			r2i.append(s["v"].size())
			s["v"].append(to + off * r2)
			s["n"].append(off)
			s["uv"].append(Vector2(float(k) / seg, L))
			s["c"].append(tint)
		for k in seg:
			var j := (k + 1) % seg
			s["idx"].append_array([r1i[k], r2i[k], r2i[j], r1i[k], r2i[j], r1i[j]])


# ------------------------------------------------------------------ build --
func build_city(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "CinderCity"
	parent.add_child(root)
	slot_mats = [mat("asphalt"), mat("sidewalk"), mat("mark"), null]
	var city: Dictionary = Db.districts
	for did in city:
		if did == "world":
			continue
		_build_district(did, city[did])
	_build_arterials(city.get("world", {}))
	_build_water(city.get("world", {}))
	_build_river(city.get("world", {}))
	_build_river_crossings(city.get("world", {}))
	_build_rail(city.get("world", {}))
	_build_stations(city.get("world", {}))
	built = true


func _slot_for_facade(name: String) -> int:
	if facade_slots.has(name):
		return facade_slots[name]
	var idx := S_FACADE + facade_slots.size()
	facade_slots[name] = idx
	slot_mats.resize(idx + 1)
	slot_mats[idx] = mat(name)
	return idx


func _build_district(id: String, d: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "district_" + id
	root.add_child(node)
	district_nodes[id] = node
	var c := Vector2(d["center"][0], d["center"][1])
	var sz := Vector2(d["size"][0], d["size"][1])
	district_bounds[id] = Rect2(c - sz * 0.5, sz)
	var acc := Acc.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) & 0x7FFFFFFF
	var block: float = d.get("block", 48)
	var road_w: float = d.get("road_w", 10)
	var hmin: float = d["heights"][0]
	var hmax: float = d["heights"][1]
	var palette: Dictionary = d.get("palette", {"concrete": 1.0})
	var facades: Array = _palette_facades(palette)
	# ground plate (sidewalk level)
	acc.box(S_SIDEWALK, Vector3(c.x, -0.35, c.y), Vector3(sz.x, 0.35, sz.y), Vector3(0.05, 0.05, 0.05))
	# roads: horizontal & vertical strips at y=0 (on plate top)
	var nx := int(sz.x / block)
	var nz := int(sz.y / block)
	var x0 := c.x - sz.x * 0.5
	var z0 := c.y - sz.y * 0.5
	for i in range(nx + 1):
		var x := x0 + i * block
		acc.box(S_ASPHALT, Vector3(x, -0.02, c.y), Vector3(road_w, 0.06, sz.y), Vector3(0.08, 0.08, 0.08))
		# center dashes
		for k in range(int(sz.y / 8)):
			var z := z0 + k * 8 + 2
			acc.quad(S_MARK, Vector3(x - 0.15, 0.05, z), Vector3(x + 0.15, 0.05, z),
				Vector3(x + 0.15, 0.05, z + 3), Vector3(x - 0.15, 0.05, z + 3), Vector3.UP,
				Vector2(0.46, 0), Vector2(0.54, 0), Vector2(0.54, 1), Vector2(0.46, 1))
	for j in range(nz + 1):
		var z := z0 + j * block
		acc.box(S_ASPHALT, Vector3(c.x, -0.02, z), Vector3(sz.x, 0.06, road_w), Vector3(0.08, 0.08, 0.08))
		for k in range(int(sz.x / 8)):
			var x := x0 + k * 8 + 2
			acc.quad(S_MARK, Vector3(x, 0.05, z - 0.15), Vector3(x + 3, 0.05, z - 0.15),
				Vector3(x + 3, 0.05, z + 0.15), Vector3(x, 0.05, z + 0.15), Vector3.UP,
				Vector2(0.46, 0), Vector2(0.54, 0), Vector2(0.54, 1), Vector2(0.46, 1))
	# crosswalks at intersections
	for i in range(nx + 1):
		for j in range(nz + 1):
			var x := x0 + i * block
			var z := z0 + j * block
			for k in range(5):
				var off := -road_w * 0.5 + k * (road_w / 5.0) + 0.4
				acc.quad(S_MARK, Vector3(x + off, 0.06, z - road_w * 0.9), Vector3(x + off + road_w / 7.0, 0.06, z - road_w * 0.9),
					Vector3(x + off + road_w / 7.0, 0.06, z - road_w * 0.55), Vector3(x + off, 0.06, z - road_w * 0.55), Vector3.UP,
					Vector2(0.5, 0.1), Vector2(0.6, 0.1), Vector2(0.6, 0.9), Vector2(0.5, 0.9))
			# traffic light at NE corner
			if i < nx and j < nz:
				_add_traffic_light(node, Vector3(x + road_w * 0.7, 0, z + road_w * 0.7), id)
	# blocks -> buildings / landmarks / parks
	var reserved := _reserved_cells(d, x0, z0, block, nx, nz)
	for i in range(nx):
		for j in range(nz):
			var key := "%d_%d" % [i, j]
			var bx := x0 + i * block + block * 0.5
			var bz := z0 + j * block + block * 0.5
			if reserved.has(key):
				_build_reserved(reserved[key], acc, node, Vector2(bx, bz), block, id, rng)
				continue
			_build_block(acc, Vector2(bx, bz), block - road_w - 3.0, hmin, hmax, facades, rng, d)
	# street furniture along roads
	for i in range(nx + 1):
		var x := x0 + i * block
		for k in range(int(sz.y / 14)):
			var z := z0 + k * 14 + 5
			_add_lamp(acc, Vector3(x + road_w * 0.62, 0, z), id, d.get("lamp", [255, 179, 71]))
			if rng.randf() < d.get("trees", 0.4):
				_add_tree(acc, Vector3(x - road_w * 0.62, 0, z + 4), rng)
			if rng.randf() < 0.25:
				_add_prop(acc, "bin", Vector3(x + road_w * 0.6, 0, z + 7), rng)
	for j in range(nz + 1):
		var z := z0 + j * block
		for k in range(int(sz.x / 16)):
			var x := x0 + k * 16 + 6
			if rng.randf() < 0.3:
				_add_prop(acc, "bench", Vector3(x, 0, z + road_w * 0.62), rng)
			if rng.randf() < 0.12:
				_add_prop(acc, "hydrant", Vector3(x + 3, 0, z - road_w * 0.62), rng)
	# signs (atlas quads) on some buildings handled in _build_block
	# lane loops for traffic: ring per block
	for i in range(nx):
		for j in range(nz):
			var bx := x0 + i * block + block * 0.5
			var bz := z0 + j * block + block * 0.5
			var r := (block - road_w) * 0.5 + road_w * 0.3
			var loop := PackedVector3Array([
				Vector3(bx - r, 0, bz - r), Vector3(bx + r, 0, bz - r),
				Vector3(bx + r, 0, bz + r), Vector3(bx - r, 0, bz + r)])
			lanes.append(loop)
			lane_district.append(id)
	# commit mesh
	_commit(acc, node, id)
	# POI doors + interiors registry
	for p in d.get("pois", []):
		_make_poi(node, p, id)


func _palette_facades(p: Dictionary) -> Array:
	var out := []
	for k in p:
		var mapped: String = {
			"brick_red": "facade_brick_red", "brick_dark": "facade_brick_dark",
			"brick_grey": "facade_brick_grey", "concrete": "facade_concrete",
			"stucco": "facade_stucco", "glass": "facade_glass",
			"metal_panel": "facade_metal", "metal_corrugated": "facade_corrugated",
			"metal_rusted": "facade_corrugated",
		}.get(k, "facade_concrete")
		out.append([mapped, p[k]])
	return out


func _reserved_cells(d: Dictionary, x0: float, z0: float, block: float, nx: int, nz: int) -> Dictionary:
	var out := {}
	var add := func(wx: float, wz: float, kind: String, data):
		var i := clampi(int((wx - x0) / block), 0, nx - 1)
		var j := clampi(int((wz - z0) / block), 0, nz - 1)
		out["%d_%d" % [i, j]] = [kind, data]
	for lm in d.get("landmarks", []):
		add.call(lm["at"][0], lm["at"][1], "landmark", lm)
	for p in d.get("pois", []):
		if p.get("kind", "") in ["home", "shop", "faction", "place", "activity", "law", "safehouse"]:
			add.call(p["at"][0], p["at"][1], "poi_block", p)
	return out


func _build_reserved(entry: Array, acc: Acc, node: Node3D, center: Vector2, block: float, id: String, rng: RandomNumberGenerator) -> void:
	var kind: String = entry[0]
	var data: Dictionary = entry[1]
	if kind == "landmark":
		_build_landmark(data, acc, node, center, id, rng)
	else:
		# building that hosts the POI: solid mid-rise with sign
		var slot := _slot_for_facade("facade_brick_red" if id == "kiln_row" else "facade_concrete")
		var h := rng.randf_range(9, 15)
		var w := block * 0.55
		acc.box(slot, Vector3(center.x, 0, center.y), Vector3(w, h, w * 0.8), Vector3(0.22, 0.22, 0.22))
		acc.box(S_SIDEWALK, Vector3(center.x, 0, center.y + w * 0.4 + 1.2), Vector3(w * 0.9, 0.3, 2.2), Vector3(0.3, 0.3, 0.3))


func _build_landmark(lm: Dictionary, acc: Acc, node: Node3D, c: Vector2, id: String, rng: RandomNumberGenerator) -> void:
	var p := Vector3(c.x, 0, c.y)
	match lm.get("type", ""):
		"church":
			acc.box(_slot_for_facade("facade_brick_dark"), p, Vector3(16, 14, 24), Vector3(0.2, 0.2, 0.2))
			acc.box(_slot_for_facade("facade_brick_dark"), p + Vector3(0, 0, -14), Vector3(7, 34, 7), Vector3(0.3, 0.3, 0.3))
			acc.cyl(_slot_for_facade("facade_brick_dark"), p + Vector3(0, 34, -14), p + Vector3(0, 46, -14), 3.4, 0.2, 4)
		"park":
			acc.box(_grass_slot(), p + Vector3(0, -0.3, 0), Vector3(38, 0.32, 30), Vector3(0.2, 0.2, 0.2))
			for k in 9:
				_add_tree(acc, p + Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-12, 12)), rng)
			_add_prop(acc, "bench", p + Vector3(0, 0, 6), rng)
		"crane":
			acc.box(S_SIDEWALK, p, Vector3(3, 26, 3), Vector3(0.4, 0.4, 0.4))
			acc.box(mat_slot("rust"), p + Vector3(0, 26, 12), Vector3(2.4, 2.4, 34), Vector3(0.4, 0.4, 0.4))
			acc.box(mat_slot("rust"), p + Vector3(0, 20, 20), Vector3(0.6, 8, 0.6), Vector3(0.4, 0.4, 0.4))
		"containers":
			for k in 10:
				var cc := p + Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-10, 10))
				var col := Color.from_hsv(rng.randf(), 0.55, 0.5)
				acc.box(mat_slot("rust"), cc + Vector3(0, 1.3 if k % 3 == 2 else 0, 0),
					Vector3(6, 2.6, 2.4), Vector3(0.5, 0.5, 0.5), col)
		"lighthouse":
			acc.cyl(S_SIDEWALK, p, p + Vector3(0, 18, 0), 3.0, 2.2, 10)
			acc.box(_slot_for_facade("facade_glass"), p + Vector3(0, 18, 0), Vector3(3.4, 3, 3.4), Vector3(0.5, 0.5, 0.5))
		"tower":
			var h: float = lm.get("h", 90)
			var slot := _slot_for_facade("facade_glass")
			acc.box(slot, p, Vector3(26, h, 26), Vector3(0.35, 0.35, 0.35))
			acc.box(mat_slot("metal"), p + Vector3(0, h, 0), Vector3(10, 8, 10), Vector3(0.4, 0.4, 0.4))
			acc.cyl(mat_slot("metal"), p + Vector3(0, h + 8, 0), p + Vector3(0, h + 26, 0), 0.6, 0.15, 6)
		"plaza":
			acc.box(S_SIDEWALK, p + Vector3(0, -0.2, 0), Vector3(40, 0.3, 30), Vector3(0.1, 0.1, 0.1))
			acc.cyl(S_SIDEWALK, p + Vector3(0, 0.3, 0), p + Vector3(0, 2.2, 0), 4.0, 3.4, 12)
			for k in 6:
				_add_tree(acc, p + Vector3(cos(k) * 16, 0, sin(k) * 10), rng)
		"arch":
			acc.box(mat_slot("metal"), p + Vector3(-11, 0, 0), Vector3(2.5, 16, 2.5), Vector3(0.4, 0.4, 0.4))
			acc.box(mat_slot("metal"), p + Vector3(11, 0, 0), Vector3(2.5, 16, 2.5), Vector3(0.4, 0.4, 0.4))
			acc.box(_neon_slot(), p + Vector3(0, 16, 0), Vector3(25, 3.5, 1.6), Vector3(0.5, 0.5, 0.5))
		"refinery":
			for k in 4:
				var off := Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-10, 10))
				acc.cyl(mat_slot("rust"), p + off, p + off + Vector3(0, rng.randf_range(18, 34), 0), rng.randf_range(2.5, 4.5), rng.randf_range(2.2, 4.0), 10)
			acc.cyl(mat_slot("metal"), p + Vector3(8, 30, 0), p + Vector3(20, 12, 6), 1.2, 1.2, 8)
			acc.cyl(mat_slot("metal"), p + Vector3(-6, 26, -4), p + Vector3(-18, 10, -8), 1.0, 1.0, 8)
		"slagheap":
			acc.cyl(mat_slot("rust"), p, p + Vector3(0, 12, 0), 16, 2, 8)
		"dome":
			acc.cyl(S_SIDEWALK, p, p + Vector3(0, 8, 0), 9, 9, 14)
			acc.cyl(mat_slot("metal"), p + Vector3(0, 8, 0), p + Vector3(0, 14, 0), 9, 0.5, 14)
		"manor":
			acc.box(_slot_for_facade("facade_stucco"), p, Vector3(30, 12, 18), Vector3(0.2, 0.2, 0.2))
			acc.box(_slot_for_facade("facade_stucco"), p + Vector3(0, 12, 0), Vector3(32, 1.6, 20), Vector3(0.3, 0.3, 0.3))
			for k in 5:
				acc.cyl(S_SIDEWALK, p + Vector3(-12 + k * 6, 0, 10), p + Vector3(-12 + k * 6, 7, 10), 0.5, 0.5, 8)


func _grass_slot() -> int:
	if not slot_mats.has(90):
		pass
	return _extra_slot("grass", 90)


func _neon_slot() -> int:
	return _extra_slot("neon_white", 91)


func mat_slot(key: String) -> int:
	return _extra_slot(key, 80 + absi(hash(key)) % 8)


var _extra: Dictionary = {}


func _extra_slot(key: String, base: int) -> int:
	if _extra.has(key):
		return _extra[key]
	var idx := base + _extra.size()
	_extra[key] = idx
	if slot_mats.size() <= idx:
		slot_mats.resize(idx + 1)
	slot_mats[idx] = mat(key)
	return idx


func _build_block(acc: Acc, c: Vector2, span: float, hmin: float, hmax: float, facades: Array, rng: RandomNumberGenerator, d: Dictionary) -> void:
	# 1-3 buildings per block
	var n := 1 + rng.randi() % 3
	for b in n:
		var off := Vector2(rng.randf_range(-span * 0.2, span * 0.2), rng.randf_range(-span * 0.2, span * 0.2)) if n > 1 else Vector2.ZERO
		var w := rng.randf_range(span * 0.35, span * 0.55)
		var dp := rng.randf_range(span * 0.35, span * 0.55)
		var h := rng.randf_range(hmin, hmax)
		var pick: Array = facades[rng.randi() % facades.size()]
		var slot := _slot_for_facade(pick[0])
		var p := Vector3(c.x + off.x, 0, c.y + off.y)
		acc.box(slot, p, Vector3(w, h, dp), Vector3(0.22, 0.22, 0.22))
		# parapet lip + cornice band (architectural silhouette)
		acc.box(mat_slot("concrete"), p + Vector3(0, h, 0), Vector3(w + 0.35, 0.35, dp + 0.35), Vector3(0.3, 0.3, 0.3))
		if h > 9.0:
			acc.box(mat_slot("concrete"), p + Vector3(0, h * 0.55, 0), Vector3(w + 0.18, 0.22, dp + 0.18), Vector3(0.3, 0.3, 0.3))
		# entrance: recessed door + step + awning on the street face
		if rng.randf() < 0.75:
			acc.box(mat_slot("metal"), p + Vector3(rng.randf_range(-w * 0.3, w * 0.3), 1.15, dp / 2 + 0.06),
				Vector3(1.5, 2.3, 0.12), Vector3(0.4, 0.4, 0.4), Color(0.12, 0.13, 0.15))
			acc.box(mat_slot("concrete"), p + Vector3(0, 0.08, dp / 2 + 0.5), Vector3(2.4, 0.16, 1.0), Vector3(0.4, 0.4, 0.4))
			acc.box(_extra_slot("wood", 96), p + Vector3(0, 2.6, dp / 2 + 0.55), Vector3(2.8, 0.09, 1.2), Vector3(0.4, 0.4, 0.4))
		# fire escape on the street face of some taller buildings:
		# zig-zag ladders + landings, and a registered climb point so the
		# player can scale it to the roof (rooftops = escape routes + views)
		if h > 11.0 and rng.randf() < 0.4:
			var fx := p.x + rng.randf_range(-w * 0.3, w * 0.3)
			var fz := p.z + dp / 2 + 0.45
			var land_y := 3.2
			var side := 1.0
			while land_y < h - 1.0:
				# landing platform + railing
				acc.box(mat_slot("metal"), Vector3(fx + side * 0.9, land_y, fz), Vector3(1.9, 0.1, 1.0), Vector3(0.4, 0.4, 0.4), Color(0.24, 0.22, 0.2))
				acc.box(mat_slot("metal"), Vector3(fx + side * 0.9, land_y + 0.5, fz + 0.47), Vector3(1.9, 0.9, 0.05), Vector3(0.4, 0.4, 0.4), Color(0.2, 0.19, 0.18))
				# ladder down to the next landing below (alternating sides)
				var next_y := maxf(0.0, land_y - 3.2)
				for rung in 5:
					var ry := next_y + (land_y - next_y) * (float(rung) + 0.5) / 5.0
					acc.box(mat_slot("metal"), Vector3(fx - side * 0.9, ry, fz), Vector3(0.5, 0.04, 0.04), Vector3(0.4, 0.4, 0.4), Color(0.26, 0.24, 0.22))
				acc.box(mat_slot("metal"), Vector3(fx - side * 0.9, (land_y + next_y) * 0.5, fz), Vector3(0.05, land_y - next_y, 0.05), Vector3(0.4, 0.4, 0.4), Color(0.22, 0.21, 0.2))
				side = -side
				land_y += 3.2
			climb_points.append({
				"bottom": Vector3(fx, 0.05, fz + 0.9),
				"top": Vector3(fx, h + 0.15, fz - 0.4),
				"height": h})
		# balconies on some mid floors
		if h > 12.0 and rng.randf() < 0.5:
			var by := 4.0
			while by < h - 2.0:
				acc.box(mat_slot("concrete"), p + Vector3(w * 0.25, by, dp / 2 + 0.55), Vector3(2.2, 0.14, 1.1), Vector3(0.3, 0.3, 0.3))
				acc.box(mat_slot("metal"), p + Vector3(w * 0.25, by + 0.5, dp / 2 + 1.05), Vector3(2.2, 0.9, 0.06), Vector3(0.3, 0.3, 0.3), Color(0.2, 0.2, 0.22))
				by += rng.randf_range(3.2, 4.2)
		# roof clutter
		if rng.randf() < 0.6:
			acc.box(mat_slot("rust"), p + Vector3(rng.randf_range(-w * 0.2, w * 0.2), h, rng.randf_range(-dp * 0.2, dp * 0.2)),
				Vector3(rng.randf_range(1.5, 3), rng.randf_range(1, 2.2), rng.randf_range(1.5, 3)), Vector3(0.4, 0.4, 0.4))
		if rng.randf() < 0.35:
			acc.box(mat_slot("metal"), p + Vector3(0, h, 0), Vector3(2, 3, 2), Vector3(0.4, 0.4, 0.4))
		# shopfront sign at street level
		if rng.randf() < d.get("signs", 0.4):
			var sz := rng.randf_range(3.5, 6.0)
			var cell := rng.randi() % 16
			var u0 := (cell % 4) * 0.25
			var v0 := (cell / 4) * 0.25
			var face := rng.randi() % 4
			var y := rng.randf_range(3.0, 4.5)
			var sn := _extra_slot("signs", 92)
			match face:
				0: acc.quad(sn, p + Vector3(-sz / 2, y, dp / 2 + 0.1), p + Vector3(sz / 2, y, dp / 2 + 0.1), p + Vector3(sz / 2, y + sz * 0.45, dp / 2 + 0.1), p + Vector3(-sz / 2, y + sz * 0.45, dp / 2 + 0.1), Vector3(0, 0, 1), Vector2(u0, v0), Vector2(u0 + 0.25, v0), Vector2(u0 + 0.25, v0 + 0.25), Vector2(u0, v0 + 0.25))
				1: acc.quad(sn, p + Vector3(sz / 2 + 0.1, y, -sz / 2), p + Vector3(sz / 2 + 0.1, y, sz / 2), p + Vector3(sz / 2 + 0.1, y + sz * 0.45, sz / 2), p + Vector3(sz / 2 + 0.1, y + sz * 0.45, -sz / 2), Vector3(1, 0, 0), Vector2(u0, v0), Vector2(u0 + 0.25, v0), Vector2(u0 + 0.25, v0 + 0.25), Vector2(u0, v0 + 0.25))
				2: acc.quad(sn, p + Vector3(sz / 2, y, -dp / 2 - 0.1), p + Vector3(-sz / 2, y, -dp / 2 - 0.1), p + Vector3(-sz / 2, y + sz * 0.45, -dp / 2 - 0.1), p + Vector3(sz / 2, y + sz * 0.45, -dp / 2 - 0.1), Vector3(0, 0, -1), Vector2(u0, v0), Vector2(u0 + 0.25, v0), Vector2(u0 + 0.25, v0 + 0.25), Vector2(u0, v0 + 0.25))
				3: acc.quad(sn, p + Vector3(-sz / 2 - 0.1, y, sz / 2), p + Vector3(-sz / 2 - 0.1, y, -sz / 2), p + Vector3(-sz / 2 - 0.1, y + sz * 0.45, -sz / 2), p + Vector3(-sz / 2 - 0.1, y + sz * 0.45, sz / 2), Vector3(-1, 0, 0), Vector2(u0, v0), Vector2(u0 + 0.25, v0), Vector2(u0 + 0.25, v0 + 0.25), Vector2(u0, v0 + 0.25))
		# posters on some walls
		if rng.randf() < 0.3:
			var pn := _extra_slot("posters", 93)
			var cell2 := rng.randi() % 16
			var u1 := (cell2 % 4) * 0.25
			var v1 := (cell2 / 4) * 0.25
			acc.quad(pn, p + Vector3(-1.1, 1.6, dp / 2 + 0.12), p + Vector3(1.1, 1.6, dp / 2 + 0.12),
				p + Vector3(1.1, 3.4, dp / 2 + 0.12), p + Vector3(-1.1, 3.4, dp / 2 + 0.12), Vector3(0, 0, 1),
				Vector2(u1, v1), Vector2(u1 + 0.25, v1), Vector2(u1 + 0.25, v1 + 0.25), Vector2(u1, v1 + 0.25))


func _add_lamp(acc: Acc, p: Vector3, id: String, col: Array) -> void:
	acc.cyl(mat_slot("metal"), p, p + Vector3(0, 5.4, 0), 0.09, 0.07, 6)
	acc.box(mat_slot("metal"), p + Vector3(0, 5.4, 0.5), Vector3(0.25, 0.2, 1.2), Vector3(0.5, 0.5, 0.5))
	lamp_posts.append({"pos": p + Vector3(0, 5.3, 0.8), "district": id,
		"color": Color(col[0] / 255.0, col[1] / 255.0, col[2] / 255.0)})


func _add_tree(acc: Acc, p: Vector3, rng: RandomNumberGenerator) -> void:
	# v2: tapered trunk, real branches, layered crown blobs, per-tree variation
	var h := rng.randf_range(3.6, 6.2)
	var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
	var trunk_top := p + Vector3(lean.x * h, h * 0.62, lean.z * h)
	acc.cyl(_extra_slot("trunk", 94), p, trunk_top, 0.17, 0.10, 7)
	var fol := _extra_slot("foliage", 95)
	var nb := 2 + rng.randi() % 3
	for i in nb:
		var t := rng.randf_range(0.45, 0.8)
		var base := p + Vector3(lean.x * h * t, h * t, lean.z * h * t)
		var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 1.0), rng.randf_range(-1, 1)).normalized()
		var bl := rng.randf_range(0.7, 1.4)
		acc.cyl(_extra_slot("trunk", 94), base, base + dirv * bl, 0.06, 0.03, 5)
		var cr := rng.randf_range(0.9, 1.5)
		acc.cyl(fol, base + dirv * bl * 0.6, base + dirv * bl + Vector3(0, cr * 0.8, 0), cr, cr * 0.55, 7)
	# crown: three overlapping squashed blobs
	var c0 := trunk_top + Vector3(0, 0.5, 0)
	acc.cyl(fol, c0 + Vector3(-0.5, -0.2, 0.2), c0 + Vector3(-0.7, 0.9, 0.3), 1.05, 0.62, 8)
	acc.cyl(fol, c0 + Vector3(0.5, -0.1, -0.2), c0 + Vector3(0.75, 1.0, -0.3), 1.0, 0.58, 8)
	acc.cyl(fol, c0 + Vector3(0, 0.3, 0), c0 + Vector3(lean.x * 3, 1.7, lean.z * 3), rng.randf_range(1.15, 1.6), 0.7, 9)


func _add_prop(acc: Acc, kind: String, p: Vector3, rng: RandomNumberGenerator) -> void:
	match kind:
		"bin":
			acc.cyl(mat_slot("rust"), p, p + Vector3(0, 0.9, 0), 0.32, 0.3, 8)
		"bench":
			acc.box(_extra_slot("wood", 96), p + Vector3(0, 0.42, 0), Vector3(1.8, 0.09, 0.55), Vector3(0.5, 0.5, 0.5))
			acc.box(_extra_slot("wood", 96), p + Vector3(0, 0.75, -0.25), Vector3(1.8, 0.5, 0.08), Vector3(0.5, 0.5, 0.5))
		"hydrant":
			acc.cyl(_neon_slot(), p, p + Vector3(0, 0.7, 0), 0.14, 0.1, 8, Color(0.7, 0.1, 0.1))
			acc.box(_neon_slot(), p + Vector3(0, 0.72, 0), Vector3(0.3, 0.12, 0.16), Vector3(0.3, 0.3, 0.3), Color(0.7, 0.1, 0.1))
		"bus_stop":
			for sx in [-1.1, 1.1]:
				acc.cyl(mat_slot("metal"), p + Vector3(sx, 0, 0), p + Vector3(sx, 2.3, 0), 0.05, 0.05, 6)
			acc.box(mat_slot("metal"), p + Vector3(0, 2.35, 0), Vector3(2.6, 0.1, 1.0), Vector3(0.4, 0.4, 0.4))
			acc.box(_extra_slot("wood", 96), p + Vector3(0, 0.45, -0.3), Vector3(2.2, 0.08, 0.5), Vector3(0.4, 0.4, 0.4))
			acc.quad(_extra_slot("posters", 93), p + Vector3(-1.0, 0.4, -0.45), p + Vector3(1.0, 0.4, -0.45),
				p + Vector3(1.0, 2.1, -0.45), p + Vector3(-1.0, 2.1, -0.45), Vector3(0, 0, -1),
				Vector2(0, 0), Vector2(0.25, 0), Vector2(0.25, 0.25), Vector2(0, 0.25))
		"dumpster":
			acc.box(mat_slot("rust"), p + Vector3(0, 0.65, 0), Vector3(1.9, 1.2, 1.1), Vector3(0.5, 0.5, 0.5), Color(0.25, 0.32, 0.26))
			acc.box(mat_slot("rust"), p + Vector3(0, 1.28, 0), Vector3(1.94, 0.1, 1.14), Vector3(0.5, 0.5, 0.5), Color(0.2, 0.26, 0.21))
		"sign_pole":
			acc.cyl(mat_slot("metal"), p, p + Vector3(0, 2.6, 0), 0.06, 0.06, 6)
			acc.box(_extra_slot("signs", 92), p + Vector3(0, 2.9, 0), Vector3(0.9, 0.7, 0.06), Vector3(0.3, 0.3, 0.3))
		"planter":
			acc.box(mat_slot("concrete"), p + Vector3(0, 0.35, 0), Vector3(1.4, 0.7, 1.4), Vector3(0.4, 0.4, 0.4))
			acc.cyl(_extra_slot("foliage", 95), p + Vector3(0, 0.6, 0), p + Vector3(0, 1.15, 0), 0.55, 0.35, 7)


func _add_traffic_light(node: Node3D, p: Vector3, id: String) -> void:
	var n := Node3D.new()
	node.add_child(n)
	n.global_position = p
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 3.4, 0.16)
	mi.mesh = box
	mi.position = Vector3(0, 1.7, 0)
	mi.material_override = mat("metal")
	n.add_child(mi)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.35, 0.9, 0.3)
	head.mesh = hb
	head.position = Vector3(0, 3.2, 0.2)
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.08, 0.08, 0.08)
	head.material_override = hm
	n.add_child(head)
	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 0.9, 0.3)
	light.light_energy = 1.2
	light.omni_range = 6.0
	light.position = Vector3(0, 3.0, 0.45)
	light.visible = false   # enabled at night/near player by light manager
	n.add_child(light)
	n.set_meta("tlight", true)
	traffic_lights.append({"node": n, "light": light, "district": id, "phase": randf() * 20.0})


func _commit(acc: Acc, node: Node3D, id: String) -> void:
	var mesh := ArrayMesh.new()
	var slot_ids := acc.slots.keys()
	slot_ids.sort()
	for s in slot_ids:
		var d2: Dictionary = acc.slots[s]
		if d2["v"].size() == 0:
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = d2["v"]
		arr[Mesh.ARRAY_NORMAL] = d2["n"]
		arr[Mesh.ARRAY_TEX_UV] = d2["uv"]
		arr[Mesh.ARRAY_COLOR] = d2["c"]
		arr[Mesh.ARRAY_INDEX] = d2["idx"]
		var mi := MeshInstance3D.new()
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mi.mesh = mesh
		if s < slot_mats.size() and slot_mats[s] != null:
			mi.material_override = slot_mats[s]
		else:
			mi.material_override = mat("concrete")
		mi.name = "chunk_%s_%d" % [id, s]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s != S_MARK else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		if s == S_MARK:
			continue   # markings are visual only
		# static body collision for world chunk
		var sb := StaticBody3D.new()
		sb.name = "col_%s_%d" % [id, s]
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		sb.add_child(cs)
		node.add_child(sb)


func _make_poi(node: Node3D, p: Dictionary, district_id: String) -> void:
	var door := Area3D.new()
	door.add_to_group("interact")
	door.set("interact_label", "Enter %s" % p.get("name", "building"))
	node.add_child(door)
	door.global_position = Vector3(p["at"][0], 1.1, p["at"][1])
	# marker light
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.8)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.4, 0.3)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.9, 0.6)
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.position = Vector3(0, 0.6, 0)
	door.add_child(mi)
	pois[p["id"]] = {"data": p, "node": door, "district": district_id}
	door.set_meta("poi_id", p["id"])
	if not door.has_method("interact"):
		door.set_script(load("res://scripts/world/poi_door.gd"))


func _build_arterials(w: Dictionary) -> void:
	var acc := Acc.new()
	for a in w.get("arterials", []):
		if a["axis"] == "x":
			acc.box(S_ASPHALT, Vector3(a["at"], -0.03, -100), Vector3(a["width"], 0.06, 700), Vector3(0.08, 0.08, 0.08))
		else:
			acc.box(S_ASPHALT, Vector3(-100, -0.03, a["at"]), Vector3(900, 0.06, a["width"]), Vector3(0.08, 0.08, 0.08))
	var node := Node3D.new()
	node.name = "arterials"
	root.add_child(node)
	_commit_simple(acc, node)


func _commit_simple(acc: Acc, node: Node3D) -> void:
	for s in acc.slots.keys():
		var d2: Dictionary = acc.slots[s]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = d2["v"]
		arr[Mesh.ARRAY_NORMAL] = d2["n"]
		arr[Mesh.ARRAY_TEX_UV] = d2["uv"]
		arr[Mesh.ARRAY_COLOR] = d2["c"]
		arr[Mesh.ARRAY_INDEX] = d2["idx"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = slot_mats[s] if s < slot_mats.size() and slot_mats[s] else mat("asphalt")
		node.add_child(mi)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		sb.add_child(cs)
		node.add_child(sb)


# ============================================================ SMOKE LINE ====
## The Smoke Line: a freight viaduct carried above the east-west arterial at
## z = -30. Missions m10_smoke_line, the Smokeline Bolt-Hole safehouse and the
## Smoke Line Overlook all name this railway; until now there were no rails in
## the game, only the word. It runs the full width of the city so a train is
## something you hear before you see, from four districts away.
const RAIL_Z := -30.0
const RAIL_X0 := -560.0
const RAIL_X1 := 360.0
const RAIL_DECK_Y := 7.2
const RAIL_PIERS := 24.0        # pier spacing
const RAIL_SLEEPERS := 2.0      # sleeper spacing
const RAIL_GAUGE := 0.72        # half-gauge: rails at +/- this
const RAIL_PLATFORM_X := 300.0  # the Overlook station, 90 m from the POI

## Where the rails are, so the running train and the audio can find them.
# ---------------------------------------------------------------- stations --
# Filling stations. Six forecourts, one per district, priced so that the cheap
# fuel is in the rough districts and the premium is in Crown Heights — where
# you fill up is a small economic decision the city already understands.
const STA_PAD_X := 30.0
const STA_PAD_Z := 20.0
const STA_CANOPY_Y := 4.30
const STA_PUMP_Y := 1.05

var stations: Dictionary = {}          # id -> {data, node, pumps, district, pos}

# per-station local frame: stations are authored long-axis-X and rotated to
# face whichever arterial they front
var _sta_cx := 0.0
var _sta_cz := 0.0
var _sta_swap := false


func rail_height() -> float:
	return RAIL_DECK_Y + 1.05


func _build_rail(_w: Dictionary) -> void:
	var acc := Acc.new()
	var con := mat_slot("concrete")
	var met := mat_slot("metal")
	var rust := mat_slot("rust")
	var neon := _neon_slot()
	var grey := Color(0.42, 0.41, 0.40)
	var dark := Color(0.24, 0.235, 0.23)
	var steel := Color(0.58, 0.58, 0.60)

	var x := RAIL_X0
	# ---- piers + capitals -------------------------------------------------
	while x <= RAIL_X1:
		# tapered pier: wide at the base, narrower at the deck
		acc.cyl(con, Vector3(x, 0.0, RAIL_Z - 2.3), Vector3(x, RAIL_DECK_Y - 0.5, RAIL_Z - 2.3), 0.85, 0.62, 8, grey)
		acc.cyl(con, Vector3(x, 0.0, RAIL_Z + 2.3), Vector3(x, RAIL_DECK_Y - 0.5, RAIL_Z + 2.3), 0.85, 0.62, 8, grey)
		# capital beam tying the two legs
		acc.box(con, Vector3(x - 0.55, RAIL_DECK_Y - 0.9, RAIL_Z - 3.1), Vector3(1.1, 0.5, 6.2), Vector3(0.3, 0.3, 0.3), grey)
		# base plinths so the legs meet the ground with weight
		acc.box(con, Vector3(x - 1.05, 0.0, RAIL_Z - 3.2), Vector3(2.1, 0.5, 1.8), Vector3(0.3, 0.3, 0.3), dark)
		acc.box(con, Vector3(x - 1.05, 0.0, RAIL_Z + 1.4), Vector3(2.1, 0.5, 1.8), Vector3(0.3, 0.3, 0.3), dark)
		x += RAIL_PIERS

	# ---- deck: ballast bed, two girders, parapets (segmented for UVs) -----
	var seg := 23.0
	x = RAIL_X0
	while x < RAIL_X1:
		var w := minf(seg, RAIL_X1 - x)
		var cx := x + w * 0.5
		# deck slab (Acc.box grows upward from its centre.y)
		acc.box(con, Vector3(cx - w * 0.5, RAIL_DECK_Y - 0.45, RAIL_Z - 3.4), Vector3(w, 0.45, 6.8), Vector3(0.25, 0.25, 0.25), grey)
		# ballast
		acc.box(rust, Vector3(cx - w * 0.5, RAIL_DECK_Y, RAIL_Z - 2.6), Vector3(w, 0.22, 5.2), Vector3(0.5, 0.5, 0.5), Color(0.30, 0.27, 0.25))
		# girders under the slab
		acc.box(met, Vector3(cx - w * 0.5, RAIL_DECK_Y - 1.55, RAIL_Z - 3.35), Vector3(w, 1.1, 0.22), Vector3(0.3, 0.3, 0.3), dark)
		acc.box(met, Vector3(cx - w * 0.5, RAIL_DECK_Y - 1.55, RAIL_Z + 3.13), Vector3(w, 1.1, 0.22), Vector3(0.3, 0.3, 0.3), dark)
		# cross-bracing in an X, the detail that makes a viaduct read as built
		acc.cyl(met, Vector3(x, RAIL_DECK_Y - 1.5, RAIL_Z - 3.2), Vector3(x + w, RAIL_DECK_Y - 0.5, RAIL_Z + 3.2), 0.07, 0.07, 5, dark)
		acc.cyl(met, Vector3(x, RAIL_DECK_Y - 0.5, RAIL_Z - 3.2), Vector3(x + w, RAIL_DECK_Y - 1.5, RAIL_Z + 3.2), 0.07, 0.07, 5, dark)
		# parapets
		acc.box(met, Vector3(cx - w * 0.5, RAIL_DECK_Y + 0.1, RAIL_Z - 3.55), Vector3(w, 0.95, 0.10), Vector3(0.35, 0.35, 0.35), dark)
		acc.box(met, Vector3(cx - w * 0.5, RAIL_DECK_Y + 0.1, RAIL_Z + 3.45), Vector3(w, 0.95, 0.10), Vector3(0.35, 0.35, 0.35), dark)
		x += seg

	# ---- sleepers + rails -------------------------------------------------
	var sleeper_n := int((RAIL_X1 - RAIL_X0) / RAIL_SLEEPERS)
	for i in sleeper_n:
		var sx := RAIL_X0 + float(i) * RAIL_SLEEPERS
		acc.box(rust, Vector3(sx - 1.25, RAIL_DECK_Y + 0.20, RAIL_Z - 1.25), Vector3(2.5, 0.14, 0.24), Vector3(0.6, 0.6, 0.6), Color(0.26, 0.22, 0.19))
		acc.box(rust, Vector3(sx - 1.25, RAIL_DECK_Y + 0.20, RAIL_Z + 1.01), Vector3(2.5, 0.14, 0.24), Vector3(0.6, 0.6, 0.6), Color(0.26, 0.22, 0.19))
	# rails run in 20 m lengths so the UV tiling stays sane over 920 m
	var rx := RAIL_X0
	while rx < RAIL_X1:
		var rw := minf(20.0, RAIL_X1 - rx)
		for side in [-1.0, 1.0]:
			acc.box(met, Vector3(rx, RAIL_DECK_Y + 0.33, RAIL_Z + side * RAIL_GAUGE - 0.05), Vector3(rw, 0.13, 0.10), Vector3(0.8, 0.8, 0.8), steel)
		rx += 20.0

	# ---- gantry lamps: they glow at night and mark the line from anywhere --
	var lx := RAIL_X0 + 30.0
	while lx < RAIL_X1:
		acc.cyl(met, Vector3(lx, RAIL_DECK_Y + 0.2, RAIL_Z + 3.4), Vector3(lx, RAIL_DECK_Y + 4.6, RAIL_Z + 3.4), 0.09, 0.07, 6, dark)
		acc.box(met, Vector3(lx - 0.9, RAIL_DECK_Y + 4.5, RAIL_Z + 2.4), Vector3(1.8, 0.10, 1.0), Vector3(0.4, 0.4, 0.4), dark)
		acc.box(neon, Vector3(lx - 0.8, RAIL_DECK_Y + 4.34, RAIL_Z + 2.5), Vector3(1.6, 0.10, 0.8), Vector3(0.4, 0.4, 0.4), Color(1.0, 0.92, 0.78))
		lx += 60.0

	# ---- the Overlook station: a platform, a canopy, and a stair down -----
	var px := RAIL_PLATFORM_X
	acc.box(con, Vector3(px - 26.0, RAIL_DECK_Y + 0.05, RAIL_Z - 7.6), Vector3(52.0, 0.30, 3.6), Vector3(0.3, 0.3, 0.3), grey)
	for cxo in [-24.0, -8.0, 8.0, 24.0]:
		acc.cyl(met, Vector3(px + cxo, RAIL_DECK_Y + 0.3, RAIL_Z - 7.2), Vector3(px + cxo, RAIL_DECK_Y + 3.5, RAIL_Z - 7.2), 0.11, 0.11, 6, dark)
	acc.box(met, Vector3(px - 26.0, RAIL_DECK_Y + 3.5, RAIL_Z - 8.4), Vector3(52.0, 0.16, 4.4), Vector3(0.3, 0.3, 0.3), Color(0.20, 0.20, 0.22))
	# stair from the street up to the platform
	var sy := 0.0
	var sz := RAIL_Z - 11.0
	var step_i := 0
	while sy < RAIL_DECK_Y:
		acc.box(con, Vector3(px - 30.0, sy, sz - 0.5), Vector3(3.0, 0.42, 1.0), Vector3(0.3, 0.3, 0.3), grey)
		sy += 0.42
		sz -= 0.34
		step_i += 1

	var node := Node3D.new()
	node.name = "smoke_line"
	root.add_child(node)
	_commit(acc, node, "smoke_line")

	# collision: the deck is solid, so a train cannot be walked through and
	# the player can be on top of it. Segmented to keep the shape count sane.
	var cx2 := RAIL_X0
	while cx2 < RAIL_X1:
		var cw := minf(46.0, RAIL_X1 - cx2)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(cw, 1.6, 7.0)
		cs.shape = box
		sb.position = Vector3(cx2 + cw * 0.5, RAIL_DECK_Y - 0.2, RAIL_Z)
		sb.collision_layer = 1
		root.add_child(sb)
		sb.add_child(cs)
		cx2 += 46.0


func _sta_p(lx: float, ly: float, lz: float) -> Vector3:
	## local station space -> world. ly is a BASE height (Acc.box grows up).
	if _sta_swap:
		return Vector3(_sta_cx + lz, ly, _sta_cz + lx)
	return Vector3(_sta_cx + lx, ly, _sta_cz + lz)


func _sta_s(lx: float, ly: float, lz: float) -> Vector3:
	## local SIZE -> world size (axes swap with the orientation)
	if _sta_swap:
		return Vector3(lz, ly, lx)
	return Vector3(lx, ly, lz)


func _sta_box(acc: Acc, i: int, lx: float, ly: float, lz: float,
		sx: float, sy: float, sz: float, uvs := Vector3(0.25, 0.25, 0.25),
		tint := Color(1, 1, 1)) -> void:
	acc.box(i, _sta_p(lx, ly, lz), _sta_s(sx, sy, sz), uvs, tint)


func _sta_cyl(acc: Acc, i: int, ax: float, ay: float, az: float,
		bx: float, by: float, bz: float, r1: float, r2: float,
		seg := 8, tint := Color(1, 1, 1)) -> void:
	acc.cyl(i, _sta_p(ax, ay, az), _sta_p(bx, by, bz), r1, r2, seg, tint)


func _sta_bar(acc: Acc, i: int, ax: float, az: float, bx: float, bz: float,
		width: float, y := 0.085) -> void:
	## a flat painted stripe on the forecourt. Winding matches Acc.box's top
	## face so it can never end up facing away from the sky.
	var a := _sta_p(ax, y, az)
	var b := _sta_p(bx, y, bz)
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return
	d /= L
	var perp := Vector3(-d.z, 0.0, d.x) * (width * 0.5)
	acc.quad(i, a - perp, b - perp, b + perp, a + perp, Vector3(0, 1, 0),
		Vector2(0, 0), Vector2(L, 0), Vector2(L, width), Vector2(0, width))


func _station_along_z(p: Vector2, w: Dictionary) -> bool:
	## true when the nearest arterial runs north-south, so the canopy's long
	## axis (and the bays) should run with it.
	##
	## city.json's axis label names the coordinate that is CONSTANT: axis "x"
	## is a line of constant x, i.e. a road running N-S at x = at. That is what
	## _build_arterials lays down and what the Smoke Line viaduct assumes when
	## it runs along the "z = -30" arterial in x. This function had the two
	## cases the other way round, so it measured every station against the wrong
	## family of roads — Slag Diesel Yard fronts the x = 190 arterial 60 m to
	## its west, but was told its nearest road was 280 m away, gave up, and
	## built its canopy turned 90 degrees away from the traffic it exists to
	## serve. The other five came out right by coincidence.
	var best_d := 1e9
	var best_ns := false
	for a in w.get("arterials", []):
		var ad: Dictionary = a
		var at := float(ad.get("at", 0))
		var ns: bool = str(ad.get("axis", "x")) == "x"
		var d: float = absf(p.x - at) if ns else absf(p.y - at)
		if d < best_d:
			best_d = d
			best_ns = ns
	if best_d > 90.0:
		return false                # no road worth orienting to
	return best_ns


func _station_brand(brand: String) -> Color:
	match brand:
		"Dockside":
			return Color(0.20, 0.47, 0.58)
		"Halcyon":
			return Color(0.72, 0.80, 0.90)
		"Neon Mile":
			return Color(0.90, 0.28, 0.60)
		"Slag Yard":
			return Color(0.70, 0.36, 0.16)
		"Crown":
			return Color(0.88, 0.74, 0.32)
		_:
			return Color(0.83, 0.53, 0.20)   # Ember & Ash


func _build_stations(w: Dictionary) -> void:
	var list: Array = w.get("stations", [])
	if list.is_empty():
		return
	var acc := Acc.new()
	var con := mat_slot("concrete")
	var met := mat_slot("metal")
	var rust := mat_slot("rust")
	var gls := mat_slot("glass")
	var neon := _neon_slot()
	var node := Node3D.new()
	node.name = "filling_stations"
	root.add_child(node)
	var pump_script: GDScript = load("res://scripts/world/fuel_pump.gd")
	var pale := Color(0.50, 0.49, 0.47)
	var dark := Color(0.24, 0.235, 0.23)

	for entry in list:
		var sd: Dictionary = entry
		var sid: String = str(sd.get("id", ""))
		if sid == "":
			continue
		var at: Array = sd.get("at", [0, 0])
		_sta_cx = float(at[0])
		_sta_cz = float(at[1])
		_sta_swap = _station_along_z(Vector2(_sta_cx, _sta_cz), w)
		var npumps := clampi(int(sd.get("pumps", 3)), 2, 6)
		var brand: Color = _station_brand(str(sd.get("brand", "")))
		var did: String = str(sd.get("district", district_at(_sta_p(0, 0, 0))))

		# ---- forecourt pad ----
		_sta_box(acc, con, 0.0, 0.0, 0.0, STA_PAD_X, 0.07, STA_PAD_Z,
			Vector3(0.11, 0.11, 0.11), pale)

		# ---- canopy: slab, fascia band, soffit light panels, four posts ----
		_sta_box(acc, met, 2.0, STA_CANOPY_Y, 0.0, 20.0, 0.42, 12.5,
			Vector3(0.3, 0.3, 0.3), Color(0.62, 0.62, 0.64))
		_sta_box(acc, met, 2.0, STA_CANOPY_Y, -6.36, 20.5, 0.64, 0.24, Vector3(0.4, 0.4, 0.4), brand)
		_sta_box(acc, met, 2.0, STA_CANOPY_Y, 6.36, 20.5, 0.64, 0.24, Vector3(0.4, 0.4, 0.4), brand)
		_sta_box(acc, met, -8.13, STA_CANOPY_Y, 0.0, 0.24, 0.64, 13.0, Vector3(0.4, 0.4, 0.4), brand)
		_sta_box(acc, met, 12.13, STA_CANOPY_Y, 0.0, 0.24, 0.64, 13.0, Vector3(0.4, 0.4, 0.4), brand)
		for k in 3:
			_sta_box(acc, neon, -4.4 + float(k) * 6.4, 4.20, 0.0, 5.4, 0.08, 1.4,
				Vector3(0.5, 0.5, 0.5))
		for sx in [-9.0, 9.0]:
			for sz in [-5.2, 5.2]:
				_sta_box(acc, con, 2.0 + sx, 0.0, sz, 0.46, STA_CANOPY_Y, 0.46,
					Vector3(0.4, 0.4, 0.4), pale)
				# a base plinth so the post meets the pad with weight
				_sta_box(acc, con, 2.0 + sx - 0.16, 0.07, sz - 0.16, 0.78, 0.20, 0.78,
					Vector3(0.4, 0.4, 0.4), dark)

		# ---- pumps: island, body, head, hose, nozzle, bollards ----
		var pumps: Array = []
		var span := 15.0 if npumps > 1 else 0.0
		for k in npumps:
			var lx := 2.0 + (float(k) - float(npumps - 1) * 0.5) * (span / maxf(1.0, float(npumps - 1)))
			_sta_box(acc, con, lx, 0.07, 0.0, 3.4, 0.18, 1.15, Vector3(0.4, 0.4, 0.4), pale)
			_sta_box(acc, met, lx, 0.25, 0.0, 0.68, 1.20, 0.46, Vector3(0.5, 0.5, 0.5), brand)
			_sta_box(acc, gls, lx, 1.32, 0.0, 0.54, 0.38, 0.48, Vector3(0.5, 0.5, 0.5))
			_sta_box(acc, met, lx, 1.70, 0.0, 0.74, 0.10, 0.54, Vector3(0.5, 0.5, 0.5), dark)
			_sta_cyl(acc, rust, lx + 0.34, 1.25, 0.0, lx + 0.62, 0.95, 0.20, 0.045, 0.045, 6)
			_sta_box(acc, rust, lx + 0.54, 0.86, 0.16, 0.16, 0.30, 0.14, Vector3(0.6, 0.6, 0.6))
			for bx in [-1.85, 1.85]:
				_sta_cyl(acc, met, lx + bx, 0.07, 0.0, lx + bx, 1.00, 0.0, 0.09, 0.09, 7,
					Color(0.85, 0.78, 0.20))
			# painted bay lines either side of the island
			_sta_bar(acc, S_MARK, lx - 1.95, -2.55, lx + 1.95, -2.55, 0.14)
			_sta_bar(acc, S_MARK, lx - 1.95, 2.55, lx + 1.95, 2.55, 0.14)
			# the interactable itself — a real Area3D the player can walk to
			var area := Area3D.new()
			area.name = "pump_%s_%d" % [sid, k]
			area.set_script(pump_script)
			area.add_to_group("interact")
			area.set("station_id", sid)
			area.set("station_name", str(sd.get("name", "Filling Station")))
			area.set("price_per_l", float(sd.get("price", 2.20)))
			area.set("diesel", bool(sd.get("diesel", false)))
			area.set("district", did)
			area.set("pump_index", k)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(3.2, 2.6, 3.6)
			cs.shape = bs
			area.add_child(cs)
			node.add_child(area)
			area.position = _sta_p(lx, STA_PUMP_Y, 0.0)
			pumps.append(area)

		# ---- kiosk: the shop beside the forecourt ----
		_sta_box(acc, con, -10.0, 0.0, 0.0, 6.0, 3.10, 4.6, Vector3(0.22, 0.22, 0.22), pale)
		_sta_box(acc, met, -10.0, 3.10, 0.0, 7.0, 0.24, 5.6, Vector3(0.3, 0.3, 0.3), dark)
		_sta_box(acc, gls, -6.95, 0.95, -0.9, 0.10, 1.55, 2.6, Vector3(0.5, 0.5, 0.5))
		_sta_box(acc, rust, -6.94, 0.07, 1.50, 0.12, 2.05, 1.05, Vector3(0.4, 0.4, 0.4))
		_sta_box(acc, met, -6.93, 2.60, 0.0, 0.14, 0.48, 4.4, Vector3(0.4, 0.4, 0.4), brand)

		# ---- price totem: the thing you actually spot from down the road ----
		_sta_cyl(acc, con, -10.0, 0.0, -7.6, -10.0, 5.60, -7.6, 0.26, 0.22, 8, pale)
		_sta_box(acc, met, -10.0, 4.20, -7.6, 3.2, 1.80, 0.26, Vector3(0.4, 0.4, 0.4), brand)
		_sta_box(acc, neon, -10.0, 4.36, -7.44, 2.8, 1.48, 0.06, Vector3(0.4, 0.4, 0.4))
		_sta_box(acc, neon, -10.0, 4.36, -7.76, 2.8, 1.48, 0.06, Vector3(0.4, 0.4, 0.4))

		# ---- painted entry / exit arrows on the pad ----
		_sta_bar(acc, S_MARK, 13.2, -6.0, 13.2, 6.0, 0.30)
		_sta_bar(acc, S_MARK, 11.6, 0.0, 13.2, 0.0, 0.30)
		_sta_bar(acc, S_MARK, -13.6, -6.0, -13.6, 6.0, 0.30)

		# the pooled street lights know about the canopy too, so a forecourt
		# is genuinely lit when you are standing in it (and moths find it)
		lamp_posts.append({"pos": _sta_p(-3.0, 4.20, 0.0), "district": did,
			"color": Color(1.0, 0.95, 0.86)})
		lamp_posts.append({"pos": _sta_p(7.0, 4.20, 0.0), "district": did,
			"color": Color(1.0, 0.95, 0.86)})

		stations[sid] = {
			"data": sd, "node": node, "pumps": pumps, "district": did,
			"pos": Vector3(_sta_cx, 0.0, _sta_cz),
			"along_z": _sta_swap,
		}
		# on the minimap, the big map and the phone's tap-to-route list
		pois[sid] = {"data": sd, "node": node, "district": did}

	_commit(acc, node, "stations")


func _build_water(w: Dictionary) -> void:
	## The harbour. It used to be one flat static quad — a blue floor with a
	## normal map frozen on it. Water that never moves reads as painted on,
	## so it is now three sheets:
	##   1. a base sheet scrolling slowly one way,
	##   2. a second sheet at a different scale scrolling the OTHER way —
	##      two overlapping normal maps interfere and read as real chop,
	##      which is far cheaper than a vertex-displaced mesh on mobile,
	##   3. a foam strip along the quay that surges in and out.
	## _process() drives the scroll; see _water_layers.
	var z: float = w.get("water_z", -380)
	var centre := Vector3(100, -0.6, z - 130)
	var sz := Vector2(1400, 260)

	var mi := MeshInstance3D.new()
	mi.name = "HarbourWater"
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	var base_m: StandardMaterial3D = mat("water").duplicate()
	mi.material_override = base_m
	mi.rotation_degrees.x = -90
	mi.position = centre
	root.add_child(mi)

	var mi2 := MeshInstance3D.new()
	mi2.name = "HarbourChop"
	var q2 := QuadMesh.new()
	q2.size = sz
	mi2.mesh = q2
	var chop_m: StandardMaterial3D = base_m.duplicate()
	chop_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chop_m.albedo_color = Color(0.72, 0.80, 0.84, 0.42)
	chop_m.uv1_scale = Vector3(1.9, 1.9, 1.0)
	chop_m.metallic = 0.15
	chop_m.roughness = 0.05
	mi2.material_override = chop_m
	mi2.rotation_degrees.x = -90
	mi2.position = centre + Vector3(0, 0.025, 0)
	root.add_child(mi2)

	# foam along the quay edge (the shoreward side of the sheet)
	var mi3 := MeshInstance3D.new()
	mi3.name = "HarbourFoam"
	var q3 := QuadMesh.new()
	q3.size = Vector2(1400, 9)
	mi3.mesh = q3
	var foam_m := StandardMaterial3D.new()
	foam_m.albedo_texture = load(TEX + "water.png")
	foam_m.normal_texture = load(TEX + "water_n.png")
	foam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam_m.albedo_color = Color(0.86, 0.90, 0.92, 0.34)
	foam_m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	foam_m.uv1_scale = Vector3(26.0, 1.0, 1.0)
	foam_m.metallic = 0.0
	foam_m.roughness = 0.22
	mi3.material_override = foam_m
	mi3.rotation_degrees.x = -90
	mi3.position = centre + Vector3(0, 0.05, sz.y * 0.5 - 3.0)
	root.add_child(mi3)

	# [material, scroll speed (uv/sec)]. Assigned here, appended to by
	# _build_river so the Cut's sheets join the same _process() scroll.
	_water_layers = [
		[base_m, Vector2(0.014, 0.009)],
		[chop_m, Vector2(-0.023, 0.017)],
		[foam_m, Vector2(-0.085, 0.0)],
	]
	harbour_layers = _water_layers.duplicate()
	_water_foam = foam_m

	# The sea is solid. This CollisionShape3D was created, sized, shaped — and
	# never parented to its body, so for the whole life of the project the
	# harbour has had exactly zero collision: walk off the Berth 7 quay and you
	# fall out of the world instead of into the water. One missing add_child.
	var sb := StaticBody3D.new()
	sb.name = "HarbourCollision"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1400, 2, 260)
	cs.shape = box
	sb.position = Vector3(100, -1.5, z - 130)
	sb.add_child(cs)
	root.add_child(sb)


## Harbour scroll state, filled by _build_water.
var _water_layers: Array = []
var _water_foam: StandardMaterial3D = null
var _water_t := 0.0
## Which sheets belong to whom. _water_layers is one flat list that _process()
## scrolls, and the river appends to it — so a test that wants to assert
## something about the HARBOUR's three sheets cannot index the flat list
## without also depending on the river's build order.
var harbour_layers: Array = []
var river_layers: Array = []


func _process(delta: float) -> void:
	## Drives the harbour. Two sheets scrolling against each other is what
	## makes it read as water; the foam surges on a slower, longer cycle so
	## the quay breathes instead of ticking.
	if _water_layers.is_empty():
		return
	_water_t += delta
	for l in _water_layers:
		var m: StandardMaterial3D = l[0]
		var sp: Vector2 = l[1]
		var off: Vector3 = m.uv1_offset
		m.uv1_offset = Vector3(off.x + sp.x * delta, off.y + sp.y * delta, off.z)
	if _water_foam != null:
		# surge: alpha and UV stretch rise and fall together
		var surge := 0.5 + 0.5 * sin(_water_t * 0.55)
		_water_foam.albedo_color = Color(0.86, 0.90, 0.92, 0.20 + 0.26 * surge)




# =================================================================== RIVER ==
## The Cinder Cut.
##
## Cinder City had a harbour, four arterials, six districts and a freight
## viaduct — and not one metre of running water inside the city. The harbour
## sheet stops dead at z = -380, so every line about "the Cut", "the Reach" or
## "meet me down by the water" was a word with no geometry behind it, and the
## seams between districts were voids you could fall straight through.
##
## The Cut runs east from a sluice head behind Kiln Row, along the bare seam
## between the furnace districts and the neon ones, then turns south at Crown
## Reach, drops through the Reach weir and empties into the harbour. The Crown
## Cut branches north off it between Neon Mile and Crown Heights, with the
## x = 190 arterial as its quayside road and two footbridges over it — which
## also gives poi_stash_crown at [236, 190] ground to stand on for the first
## time: it was authored 4 m outside its own district's plate and floated.
##
## Road bridges are NOT authored. _build_river_crossings walks the arterials in
## city.json and raises a bridge wherever one actually meets water, so moving a
## road in the data moves its bridge with it. Footbridges ARE authored, because
## which two banks are worth joining is a decision, not a consequence.
##
## Every rectangle in here was checked against district plates, road strips,
## building blocks, POIs and filling stations before it was written: the whole
## system fits in the corridors and touches nothing. tests/harness.gd re-proves
## that at runtime from the data, so a future edit to city.json cannot quietly
## drop a quay wall through somebody's ground floor.
const RIVER_WALL := 1.2          # quay wall thickness
const RIVER_TOP := 0.70          # how far the quay stands proud of the street
const RIVER_RAIL := 1.05         # railing height on the open promenade edge
const RIVER_STEP_RISE := 0.275
const RIVER_STEP_RUN := 0.42
const RIVER_STEP_N := 12         # 12 risers walk you from street level to bed
const RIVER_BAY := 4.0           # landing-step bay width
const RIVER_LAMP_EVERY := 46.0
const RIVER_BOLLARD_EVERY := 26.0
const RIVER_TILE := 9.0          # metres of water per texture tile

var river_channels: Array = []   # {id, name, axis, rect: Rect2 in (x,z)}
var river_bridges: Array = []    # {id, kind, axis, at, half_span, half_w, deck_y}
var river_bounds: Rect2 = Rect2()
var river_name := ""
var river_water_y := -1.30       # water surface, for wading checks and effects
var _river_built := false
var _river_by := -3.60           # bed underside


func _riv_box(acc: Acc, slot: int, x0: float, x1: float, y0: float, h: float,
		z0: float, z1: float, tint := Color(1, 1, 1)) -> void:
	## Min-corner authoring. Acc.box wants an x/z CENTRE and a y BASE, and
	## getting that backwards builds the entire river in the wrong place while
	## still parsing cleanly, so every box in this section goes through here.
	if x1 <= x0 or z1 <= z0 or h <= 0.0:
		return
	acc.box(slot, Vector3((x0 + x1) * 0.5, y0, (z0 + z1) * 0.5),
		Vector3(x1 - x0, h, z1 - z0), Vector3(0.22, 0.22, 0.22), tint)


func _riv_span_gaps(a0: float, a1: float, gaps: Array) -> Array:
	## [a0, a1] minus every [g0, g1] in gaps, as the surviving spans in order.
	## Quay walls have to be interrupted by step bays, cut junctions and bridge
	## abutments, and doing that arithmetic inline four times is how a wall ends
	## up built straight through a staircase.
	var gs: Array = gaps.duplicate()
	gs.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var out: Array = []
	var cur := a0
	for gv in gs:
		var g: Array = gv
		var g0 := float(g[0])
		var g1 := float(g[1])
		if g1 <= cur or g0 >= a1:
			continue
		if g0 > cur:
			out.append([cur, g0])
		cur = maxf(cur, g1)
	if cur < a1:
		out.append([cur, a1])
	return out


func in_river(p: Vector2) -> bool:
	## True when p is over open water. Bridge decks answer false, so this is
	## safe both for "can I stand here" and for pruning GPS routes.
	if not _river_built or river_channels.is_empty():
		return false
	if not river_bounds.grow(0.25).has_point(p):
		return false
	if bridge_at(p) >= 0:
		return false
	for c in river_channels:
		var r: Rect2 = c["rect"]
		if r.has_point(p):
			return true
	return false


func bridge_at(p: Vector2) -> int:
	## Index of the bridge whose deck covers p, or -1. b["axis"] is the
	## direction TRAFFIC runs across the water, which is perpendicular to the
	## waterway's own axis — the opposite of how city.json labels arterials,
	## where axis "x" means a line of constant x. Both conventions live in this
	## file and this is the one place they meet, so it is spelled out.
	for i in river_bridges.size():
		var b: Dictionary = river_bridges[i]
		var at: Vector2 = b["at"]
		var hs: float = b["half_span"]
		var hw: float = b["half_w"]
		if str(b["axis"]) == "z":
			if absf(p.x - at.x) <= hw and absf(p.y - at.y) <= hs:
				return i
		else:
			if absf(p.x - at.x) <= hs and absf(p.y - at.y) <= hw:
				return i
	return -1


func _riv_wall(acc: Acc, con: int, rust: int, x0: float, x1: float, z0: float, z1: float,
		by: float, sy: float, stone: Color, grime: Color, dark: Color,
		top: float = RIVER_TOP) -> void:
	## A quay wall in two lifts. Everything below the waterline is stained dark,
	## everything above it is clean stone, with a metal coping on top. That one
	## colour break is what stops a quay reading as a garden wall dropped into a
	## hole, and it costs two boxes.
	if x1 <= x0 or z1 <= z0 or top <= by:
		return
	var wet_top := minf(sy + 0.30, top)
	_riv_box(acc, con, x0, x1, by, wet_top - by, z0, z1, grime)
	if top > wet_top:
		_riv_box(acc, con, x0, x1, wet_top, top - wet_top, z0, z1, stone)
	_riv_box(acc, rust, x0 - 0.06, x1 + 0.06, top, 0.10, z0 - 0.06, z1 + 0.06, dark)


func _riv_clear_of(x: float, excl: Array, margin: float) -> bool:
	for e in excl:
		if absf(x - float(e)) < margin:
			return false
	return true


func _riv_in_cut(x: float, margin: float) -> bool:
	for ch in river_channels:
		if not ch.has("cut"):
			continue
		var r: Rect2 = ch["rect"]
		if x > r.position.x - margin and x < r.end.x + margin:
			return true
	return false


func _build_river(w: Dictionary) -> void:
	var cfg: Dictionary = w.get("river", {})
	if cfg.is_empty():
		return
	var hw: float = float(cfg.get("half_width", 9.0))
	var zc: float = float(cfg.get("z", -7.0))
	var hx: float = float(cfg.get("head_x", -77.0))
	var mx: float = float(cfg.get("mouth_x", 531.0))
	var sy: float = float(cfg.get("surface_y", -1.30))
	var by: float = float(cfg.get("bed_y", -3.60))
	var pz: float = float(cfg.get("promenade_z", -22.0))
	var rz: float = float(cfg.get("reach_to_z", -384.0))
	var wz: float = float(cfg.get("weir_z", -330.0))
	var hwy: float = float(cfg.get("harbour_y", -0.62))
	var z0 := zc - hw
	var z1 := zc + hw
	var rx0 := mx - hw * 2.0       # the Reach: the last channel-width of the
	var rx1 := mx                  # Cut, turned south towards the harbour
	river_name = str(cfg.get("name", "the Cinder Cut"))
	river_water_y = sy
	_river_by = by

	# ---- the logical channels: what in_river() and the bridge derivation read
	river_channels = []
	river_channels.append({"id": "main", "name": river_name, "axis": "x",
		"rect": Rect2(Vector2(hx, z0), Vector2(mx - hx, hw * 2.0))})
	river_channels.append({"id": "reach", "name": str(cfg.get("reach_name", "Crown Reach")),
		"axis": "z", "rect": Rect2(Vector2(rx0, rz), Vector2(rx1 - rx0, z1 - rz))})
	for c in cfg.get("cuts", []):
		var cd: Dictionary = c
		var cx0 := float(cd.get("x0", 0.0))
		var cx1 := float(cd.get("x1", 0.0))
		var cz1 := float(cd.get("to_z", 0.0))
		if cx1 <= cx0 or cz1 <= z1:
			push_warning("WorldGen: river cut '%s' has an empty rect — skipped" % str(cd.get("id", "?")))
			continue
		river_channels.append({"id": str(cd.get("id", "cut")), "name": str(cd.get("name", "Cut")),
			"axis": "z", "cut": cd,
			"rect": Rect2(Vector2(cx0, z0), Vector2(cx1 - cx0, cz1 - z0))})
	river_bounds = river_channels[0]["rect"]
	for ch in river_channels:
		river_bounds = river_bounds.merge(ch["rect"])
	_river_built = true

	var acc := Acc.new()
	var con := mat_slot("concrete")
	var met := mat_slot("metal")
	var rust := mat_slot("rust")
	var walk := mat_slot("sidewalk")
	var neon := _neon_slot()
	var stone := Color(0.400, 0.395, 0.385)
	var dark := Color(0.235, 0.230, 0.225)
	var grime := Color(0.265, 0.262, 0.250)
	var silt := Color(0.205, 0.200, 0.185)
	var bedtop := by + 0.30
	# where the carriageways are, so quay furniture never ends up under a span
	var crossings: Array = []
	for a in w.get("arterials", []):
		var ad: Dictionary = a
		if str(ad.get("axis", "x")) == "x":
			crossings.append(float(ad.get("at", 0.0)))

	# ---- beds. Tiled so that no two channel beds overlap: coincident faces
	#      inside one merged trimesh are how you get a floor that buzzes.
	_riv_box(acc, con, hx, rx0, by, 0.30, z0, z1, silt)
	_riv_box(acc, con, rx0, rx1, by, 0.30, rz, z1, silt)
	for ch in river_channels:
		if str(ch["id"]) == "main" or str(ch["id"]) == "reach":
			continue
		var r: Rect2 = ch["rect"]
		_riv_box(acc, con, r.position.x, r.end.x, by, 0.30, z1, r.end.y, silt)

	# ---- quay walls. The north wall of the Cut is interrupted wherever a cut
	#      joins it, the south wall wherever a landing stair descends, and the
	#      south wall stops dead where the Reach turns south.
	var cut_gaps: Array = []
	for ch in river_channels:
		if not ch.has("cut"):
			continue
		var r2: Rect2 = ch["rect"]
		cut_gaps.append([r2.position.x - RIVER_WALL, r2.end.x + RIVER_WALL])
	var bay_gaps: Array = []
	for bxv in cfg.get("steps_at", []):
		bay_gaps.append([float(bxv) - RIVER_BAY * 0.5, float(bxv) + RIVER_BAY * 0.5])
	var swall_end := rx0 - RIVER_WALL
	for sv in _riv_span_gaps(hx, mx + RIVER_WALL, cut_gaps):
		var s: Array = sv
		_riv_wall(acc, con, rust, float(s[0]), float(s[1]), z1, z1 + RIVER_WALL, by, sy, stone, grime, dark)
	for sv in _riv_span_gaps(hx, swall_end, bay_gaps):
		var s: Array = sv
		_riv_wall(acc, con, rust, float(s[0]), float(s[1]), z0 - RIVER_WALL, z0, by, sy, stone, grime, dark)
	_riv_wall(acc, con, rust, rx0 - RIVER_WALL, rx0, rz, z0, by, sy, stone, grime, dark)
	_riv_wall(acc, con, rust, rx1, rx1 + RIVER_WALL, rz, z1 + RIVER_WALL, by, sy, stone, grime, dark)
	for ch in river_channels:
		if not ch.has("cut"):
			continue
		var cd2: Dictionary = ch["cut"]
		var kx0 := float(cd2["x0"])
		var kx1 := float(cd2["x1"])
		var kz1 := float(cd2["to_z"])
		_riv_wall(acc, con, rust, kx0 - RIVER_WALL, kx0, z1 + RIVER_WALL, kz1, by, sy, stone, grime, dark)
		_riv_wall(acc, con, rust, kx1, kx1 + RIVER_WALL, z1 + RIVER_WALL, kz1, by, sy, stone, grime, dark)
		# the head wall is taller: this is where the cut stops, and it should
		# read as a structure from the far bank rather than as a low kerb
		_riv_wall(acc, con, rust, kx0 - RIVER_WALL, kx1 + RIVER_WALL, kz1, kz1 + 1.5, by, sy, stone, grime, dark, 2.60)
		# ---- the east-bank walk. The far side of a cut is dead ground without
		#      it, and it is what the footbridges actually land on. It also runs
		#      under poi_stash_crown, which had nothing to stand on before.
		var ex1 := float(cd2.get("east_walk_to_x", kx1 + RIVER_WALL))
		if ex1 > kx1 + RIVER_WALL:
			_riv_box(acc, walk, kx1 + RIVER_WALL, ex1, -0.35, 0.35, z1 + RIVER_WALL, kz1, stone)
			var lzp := kz1 - 20.0
			while lzp > z1 + RIVER_WALL + 12.0:
				var lpp := Vector3(kx1 + RIVER_WALL + 3.4, 0.0, lzp)
				_add_lamp(acc, lpp, district_at(lpp), [255, 196, 120])
				lzp -= 58.0

	# ---- the sluice head: the Cut comes out of a gatehouse behind Kiln Row ---
	_riv_wall(acc, con, rust, hx - 2.0, hx, z0 - RIVER_WALL, z1 + RIVER_WALL, by, sy, stone, grime, dark, 3.40)
	var glen := (z1 + RIVER_WALL) - (z0 - RIVER_WALL)
	for k in 3:
		var gz0 := (z0 - RIVER_WALL) + 0.55 + float(k) * (glen - 1.1) / 3.0
		var gz1 := gz0 + (glen - 1.1) / 3.0 - 0.55
		_riv_box(acc, rust, hx - 2.14, hx - 1.96, by + 0.45, (sy + 0.95) - (by + 0.45), gz0, gz1, Color(0.40, 0.29, 0.21))
	_riv_box(acc, neon, hx - 1.50, hx - 0.50, 3.40, 0.34, zc - 0.45, zc + 0.45, Color(0.95, 0.34, 0.22))
	var slp := Vector3(hx - 1.0, 3.72, zc)
	lamp_posts.append({"pos": slp, "district": district_at(slp), "color": Color(0.95, 0.34, 0.22)})

	# ---- the south-bank promenade. This is why the Cut is a place and not a
	#      hazard: 590 m of walkable quayside linking Kiln Row, the Furnace,
	#      Neon Mile, the Slagworks and Crown Reach over ground that was
	#      previously a hole in the world.
	_riv_box(acc, walk, hx, swall_end, -0.35, 0.35, pz, z0 - RIVER_WALL, stone)
	_riv_box(acc, con, hx, swall_end, 0.0, 0.16, pz - 0.4, pz, dark)
	# The east-west arterial only reaches x = 350, so east of that the kerb is
	# the edge of the world and needs a railing rather than a road.
	var rail_from := 350.0
	if rail_from < swall_end:
		_riv_box(acc, met, rail_from, swall_end, RIVER_RAIL - 0.10, 0.10, pz - 0.36, pz - 0.24, dark)
		_riv_box(acc, met, rail_from, swall_end, 0.56, 0.08, pz - 0.34, pz - 0.26, dark)
		var qx := rail_from
		while qx < swall_end:
			_riv_box(acc, met, qx, qx + 0.14, 0.0, RIVER_RAIL, pz - 0.40, pz - 0.16, dark)
			qx += 6.5

	# ---- landing stairs. Without these the Cut is a 3.6 m hole with a 0.7 m
	#      parapet on both sides: go in and you are in it for the rest of the
	#      night. Bays are sited clear of both bridges and of the cut.
	for bxv in cfg.get("steps_at", []):
		var bxc := float(bxv)
		var bx0 := bxc - RIVER_BAY * 0.5
		var bx1 := bxc + RIVER_BAY * 0.5
		var nsteps := RIVER_STEP_N
		while nsteps > 1 and -float(nsteps - 1) * RIVER_STEP_RISE <= bedtop:
			nsteps -= 1
		var send := (z0 - RIVER_WALL) + float(nsteps) * RIVER_STEP_RUN
		for k in nsteps:
			var sz0 := (z0 - RIVER_WALL) + float(k) * RIVER_STEP_RUN
			var ty := -float(k) * RIVER_STEP_RISE
			_riv_box(acc, con, bx0, bx1, by, ty - by, sz0, sz0 + RIVER_STEP_RUN, stone)
		_riv_wall(acc, con, rust, bx0 - 0.30, bx0, z0 - RIVER_WALL, send, by, sy, stone, grime, dark)
		_riv_wall(acc, con, rust, bx1, bx1 + 0.30, z0 - RIVER_WALL, send, by, sy, stone, grime, dark)

	# ---- mooring bollards along the district-side quay ---------------------
	var bxp := hx + 14.0
	while bxp < mx - 8.0:
		if _riv_clear_of(bxp, crossings, 15.0) and not _riv_in_cut(bxp, RIVER_WALL + 2.5):
			var bz := z1 + RIVER_WALL * 0.5
			acc.cyl(rust, Vector3(bxp, RIVER_TOP + 0.10, bz), Vector3(bxp, RIVER_TOP + 0.60, bz),
				0.17, 0.14, 7, Color(0.34, 0.28, 0.22))
			_riv_box(acc, rust, bxp - 0.23, bxp + 0.23, RIVER_TOP + 0.54, 0.12, bz - 0.23, bz + 0.23, dark)
		bxp += RIVER_BOLLARD_EVERY

	# ---- promenade lamps. They join the same pooled registry the streets use,
	#      so the Cut is lit at night without adding a single light node.
	var lx := hx + 22.0
	while lx < swall_end - 10.0:
		if _riv_clear_of(lx, crossings, 13.0) and not _riv_in_cut(lx, RIVER_WALL + 4.0):
			var lpos := Vector3(lx, 0.0, pz + 2.2)
			_add_lamp(acc, lpos, district_at(lpos), [255, 196, 120])
		lx += RIVER_LAMP_EVERY

	# ---- the Reach weir. The harbour sits at y = -0.62 and the Cut at -1.30,
	#      so without a structure between them the two levels would meet in a
	#      0.68 m step in the middle of nowhere. The weir is why the Cut holds
	#      its level at all, and it is a landmark from the Crown Heights overlook.
	var crest := -0.95   # between the Cut at -1.30 and the harbour at -0.62
	_riv_box(acc, con, rx0 - RIVER_WALL, rx1 + RIVER_WALL, by, crest - by, wz - 4.0, wz, stone)
	var gw := (rx1 + RIVER_WALL - (rx0 - RIVER_WALL)) / 3.0
	for k in 3:
		var gx0 := (rx0 - RIVER_WALL) + float(k) * gw
		_riv_box(acc, met, gx0, gx0 + 0.26, crest, 2.60, wz - 3.80, wz - 0.20, dark)
		_riv_box(acc, rust, gx0 + 0.26, gx0 + gw - 0.26, crest, 2.35, wz - 3.60, wz - 0.40, Color(0.42, 0.30, 0.22))
	_riv_box(acc, met, rx0 - RIVER_WALL - 0.3, rx1 + RIVER_WALL + 0.3, 1.55, 0.30, wz - 3.90, wz - 0.10, dark)
	_riv_box(acc, neon, rx0 + 3.0, rx0 + 7.0, 1.85, 0.22, wz - 2.60, wz - 1.40, Color(0.95, 0.72, 0.30))
	var wlp := Vector3(rx0 + 5.0, 2.10, wz - 2.0)
	lamp_posts.append({"pos": wlp, "district": district_at(wlp), "color": Color(0.95, 0.72, 0.30)})

	var node := Node3D.new()
	node.name = "river"
	root.add_child(node)
	_commit(acc, node, "river")

	# ---- water. Two sheets per reach scrolling against each other, the same
	#      trick the harbour uses, because water that never moves reads as
	#      painted on. _build_water runs first and owns _water_layers, so this
	#      appends; assigning here would silently delete the harbour's animation.
	var _wl0 := _water_layers.size()
	var flow_e := Vector2(0.052, 0.006)      # the Cut runs east
	var flow_s := Vector2(0.006, -0.048)     # the Reach runs south
	_riv_water_sheet(Rect2(Vector2(hx, z0), Vector2(rx0 - hx, z1 - z0)), sy,
		"CutWater", flow_e, true)
	_riv_water_sheet(Rect2(Vector2(rx0, wz), Vector2(rx1 - rx0, z1 - wz)), sy,
		"ReachWaterUpper", flow_s, true)
	_riv_water_sheet(Rect2(Vector2(rx0, rz), Vector2(rx1 - rx0, (wz - 4.0) - rz)), hwy,
		"ReachWaterLower", flow_s * 0.6, false)
	for ch in river_channels:
		if not ch.has("cut"):
			continue
		var r3: Rect2 = ch["rect"]
		_riv_water_sheet(Rect2(Vector2(r3.position.x, z1), Vector2(r3.size.x, r3.end.y - z1)),
			sy + 0.012, "%sWater" % str(ch["id"]), Vector2(0.004, 0.036), true)
	# foam against the one quay the player actually walks along
	_riv_foam(Rect2(Vector2(hx, z0), Vector2(swall_end - hx, 3.0)), sy + 0.045, "CutFoam", true)
	river_layers = _water_layers.slice(_wl0)


func _riv_water_sheet(rect: Rect2, y: float, nm: String, flow: Vector2, chop: bool) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var mi := MeshInstance3D.new()
	mi.name = nm
	var q := QuadMesh.new()
	q.size = rect.size
	mi.mesh = q
	var m: StandardMaterial3D = mat("water").duplicate()
	# QuadMesh UVs run 0..1 across the whole sheet, so the scale has to be
	# proportional to the sheet's own size — otherwise an 18 m canal and a
	# 1400 m harbour tile at completely different densities and one of them
	# looks like it has been printed on linoleum.
	m.uv1_scale = Vector3(rect.size.x / RIVER_TILE, rect.size.y / RIVER_TILE, 1.0)
	mi.material_override = m
	mi.rotation_degrees.x = -90
	var c := rect.get_center()
	mi.position = Vector3(c.x, y, c.y)
	root.add_child(mi)
	_water_layers.append([m, flow])
	if not chop:
		return
	var mi2 := MeshInstance3D.new()
	mi2.name = nm + "Chop"
	var q2 := QuadMesh.new()
	q2.size = rect.size
	mi2.mesh = q2
	var cm: StandardMaterial3D = m.duplicate()
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_color = Color(0.70, 0.78, 0.82, 0.36)
	cm.uv1_scale = m.uv1_scale * 2.1
	cm.metallic = 0.15
	cm.roughness = 0.05
	mi2.material_override = cm
	mi2.rotation_degrees.x = -90
	mi2.position = Vector3(c.x, y + 0.022, c.y)
	root.add_child(mi2)
	_water_layers.append([cm, -flow * 1.7])


func _riv_foam(rect: Rect2, y: float, nm: String, along_x: bool) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var mi := MeshInstance3D.new()
	mi.name = nm
	var q := QuadMesh.new()
	q.size = rect.size
	mi.mesh = q
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = load(TEX + "water.png")
	fm.normal_texture = load(TEX + "water_n.png")
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(0.84, 0.88, 0.90, 0.30)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	fm.uv1_scale = Vector3(rect.size.x / 6.0, rect.size.y / 6.0, 1.0)
	fm.metallic = 0.0
	fm.roughness = 0.24
	mi.material_override = fm
	mi.rotation_degrees.x = -90
	var c := rect.get_center()
	mi.position = Vector3(c.x, y, c.y)
	root.add_child(mi)
	_water_layers.append([fm, Vector2(-0.045, 0.012) if along_x else Vector2(0.012, -0.045)])


# ---- bridges ---------------------------------------------------------------
func _riv_bbox(acc: Acc, slot: int, b: Dictionary, du0: float, du1: float, y0: float,
		h: float, dv0: float, dv1: float, tint := Color(1, 1, 1)) -> void:
	## Bridge-local box. du runs WITH traffic along the crossing and dv runs
	## across it, both relative to the bridge centre, so every structure below
	## is written once and lands correctly on either axis.
	var at: Vector2 = b["at"]
	if str(b["axis"]) == "z":
		_riv_box(acc, slot, at.x + dv0, at.x + dv1, y0, h, at.y + du0, at.y + du1, tint)
	else:
		_riv_box(acc, slot, at.x + du0, at.x + du1, y0, h, at.y + dv0, at.y + dv1, tint)


func _riv_bp(b: Dictionary, du: float, y: float, dv: float) -> Vector3:
	var at: Vector2 = b["at"]
	if str(b["axis"]) == "z":
		return Vector3(at.x + dv, y, at.y + du)
	return Vector3(at.x + du, y, at.y + dv)


func _build_river_crossings(w: Dictionary) -> void:
	if not _river_built:
		return
	river_bridges = []
	var acc := Acc.new()
	var con := mat_slot("concrete")
	var met := mat_slot("metal")
	var rust := mat_slot("rust")
	var stone := Color(0.400, 0.395, 0.385)
	var dark := Color(0.235, 0.230, 0.225)
	var steel := Color(0.560, 0.560, 0.585)

	# ---- road bridges, derived from the arterials that actually meet water --
	for a in w.get("arterials", []):
		var ad: Dictionary = a
		var axis := str(ad.get("axis", "x"))
		var at := float(ad.get("at", 0.0))
		var wd := float(ad.get("width", 16.0))
		# exactly the rect _build_arterials lays down, so a bridge can never be
		# derived for a road that is not really there
		var road: Rect2
		if axis == "x":
			road = Rect2(Vector2(at - wd * 0.5, -450.0), Vector2(wd, 700.0))
		else:
			road = Rect2(Vector2(-550.0, at - wd * 0.5), Vector2(900.0, wd))
		for ch in river_channels:
			var r: Rect2 = ch["rect"]
			if not road.intersects(r):
				continue
			var inter := road.intersection(r)
			if inter.size.x < 1.0 or inter.size.y < 1.0:
				continue
			var span_axis: String = "z" if axis == "x" else "x"
			var across: float = inter.size.y if axis == "x" else inter.size.x
			river_bridges.append({
				"id": "bridge_%s_%d" % [str(ch["id"]), int(round(at))],
				"kind": "road", "axis": span_axis, "at": inter.get_center(),
				"half_span": across * 0.5 + 2.0, "half_w": wd * 0.5 + 0.9,
				"deck_y": 0.04, "channel": str(ch["id"]),
				"road_axis": axis, "road_at": at, "road_w": wd,
			})
	# ---- footbridges, authored per cut -------------------------------------
	for ch in river_channels:
		if not ch.has("cut"):
			continue
		var cd: Dictionary = ch["cut"]
		for fb in cd.get("footbridges", []):
			var fd: Dictionary = fb
			var fz := float(fd.get("at_z", 0.0))
			var fx0 := float(fd.get("x0", 0.0))
			var fx1 := float(fd.get("x1", 0.0))
			if fx1 - fx0 < 4.0:
				push_warning("WorldGen: footbridge '%s' is too short to build" % str(fd.get("name", "?")))
				continue
			river_bridges.append({
				"id": "foot_%s_%d" % [str(cd.get("id", "cut")), int(round(fz))],
				"kind": "foot", "name": str(fd.get("name", "Footbridge")), "axis": "x",
				"at": Vector2((fx0 + fx1) * 0.5, fz), "half_span": (fx1 - fx0) * 0.5,
				"half_w": 2.0, "deck_y": RIVER_TOP, "channel": str(ch["id"]),
				"deck_x0": fx0, "deck_x1": fx1,
			})
	if river_bridges.is_empty():
		return
	for bb in river_bridges:
		var b: Dictionary = bb
		if str(b["kind"]) == "road":
			_riv_road_bridge(acc, b, con, met, rust, stone, dark, steel)
		else:
			_riv_foot_bridge(acc, b, con, met, rust, stone, dark, steel)
	var node := Node3D.new()
	node.name = "river_crossings"
	root.add_child(node)
	_commit(acc, node, "crossings")


func _riv_road_bridge(acc: Acc, b: Dictionary, con: int, met: int, rust: int,
		stone: Color, dark: Color, steel: Color) -> void:
	var hs: float = b["half_span"]
	var hw: float = b["half_w"]
	var by := _river_by
	var neon := _neon_slot()
	# ---- deck soffit. The arterials are a 6 cm veneer, which is fine over
	#      ground and ridiculous over open water, so the crossing gets a real
	#      underside hanging a metre below the carriageway.
	_riv_bbox(acc, con, b, -hs, hs, -1.00, 0.98, -hw, hw, stone)
	# ---- girders, diaphragms and cross bracing: the detail that makes a
	#      crossing read as built rather than as a road that happens to float
	_riv_bbox(acc, met, b, -hs, hs, -2.15, 1.15, -hw + 0.50, -hw + 0.86, dark)
	_riv_bbox(acc, met, b, -hs, hs, -2.15, 1.15, hw - 0.86, hw - 0.50, dark)
	for buv in [-hs * 0.5, 0.0, hs * 0.5]:
		var bu: float = buv
		_riv_bbox(acc, met, b, bu - 0.14, bu + 0.14, -2.05, 0.95, -hw + 0.86, hw - 0.86, dark)
		acc.cyl(met, _riv_bp(b, bu - 3.0, -2.05, -hw + 0.68), _riv_bp(b, bu + 3.0, -1.15, hw - 0.68), 0.06, 0.06, 5, dark)
		acc.cyl(met, _riv_bp(b, bu - 3.0, -1.15, -hw + 0.68), _riv_bp(b, bu + 3.0, -2.05, hw - 0.68), 0.06, 0.06, 5, dark)
	# ---- abutments, sitting on the quay walls either bank
	_riv_bbox(acc, con, b, -hs, -hs + 2.0, by, 0.14 - by, -hw - 0.3, hw + 0.3, stone)
	_riv_bbox(acc, con, b, hs - 2.0, hs, by, 0.14 - by, -hw - 0.3, hw + 0.3, stone)
	# ---- piers: two rows, tapered, on plinths in the bed
	for puv in [-hs + 5.0, hs - 5.0]:
		var pu: float = puv
		for pvv in [-hw * 0.56, hw * 0.56]:
			var pv: float = pvv
			_riv_bbox(acc, con, b, pu - 1.15, pu + 1.15, by, 0.55, pv - 1.15, pv + 1.15, dark)
			acc.cyl(con, _riv_bp(b, pu, by + 0.50, pv), _riv_bp(b, pu, -2.05, pv), 0.92, 0.66, 8, stone)
	# ---- parapets and coping. These carry collision from the merged trimesh,
	#      which is the whole point: an arterial over water with no barrier is
	#      a 16 m wide ramp into the Cut, at 90 km/h, in the dark.
	_riv_bbox(acc, met, b, -hs, hs, 0.04, 1.06, -hw, -hw + 0.30, dark)
	_riv_bbox(acc, met, b, -hs, hs, 0.04, 1.06, hw - 0.30, hw, dark)
	_riv_bbox(acc, rust, b, -hs, hs, 1.10, 0.10, -hw - 0.08, -hw + 0.38, steel)
	_riv_bbox(acc, rust, b, -hs, hs, 1.10, 0.10, hw - 0.38, hw + 0.08, steel)
	# ---- bridge lamps, two a side, into the same pool as the street lights
	for puv in [-hs + 2.6, hs - 2.6]:
		var pu: float = puv
		for sidev in [-1.0, 1.0]:
			var side: float = sidev
			var pv: float = side * (hw - 0.15)
			acc.cyl(met, _riv_bp(b, pu, 1.10, pv), _riv_bp(b, pu, 4.10, pv), 0.09, 0.07, 6, dark)
			_riv_bbox(acc, neon, b, pu - 0.30, pu + 0.30, 4.02, 0.26, pv - 0.30, pv + 0.30, Color(1.0, 0.88, 0.62))
			var wp := _riv_bp(b, pu, 4.05, pv)
			lamp_posts.append({"pos": wp, "district": district_at(wp), "color": Color(1.0, 0.88, 0.62)})


func _riv_foot_bridge(acc: Acc, b: Dictionary, con: int, met: int, rust: int,
		stone: Color, dark: Color, steel: Color) -> void:
	var hs: float = b["half_span"]
	var hw: float = b["half_w"]
	var by := _river_by
	var neon := _neon_slot()
	# The deck is flush with the quay parapet it springs from, so there is no
	# step up at one end and none down at the other.
	var dy: float = b["deck_y"]
	var seg := 2.6
	var u := -hs
	while u < hs - 0.01:
		var u1 := minf(u + seg, hs)
		_riv_bbox(acc, met, b, u, u1, dy - 0.28, 0.28, -hw, hw, steel)
		_riv_bbox(acc, met, b, u, u + 0.22, dy - 0.52, 0.24, -hw + 0.20, hw - 0.20, dark)
		u = u1
	_riv_bbox(acc, met, b, -hs, hs, dy, RIVER_RAIL, -hw, -hw + 0.10, dark)
	_riv_bbox(acc, met, b, -hs, hs, dy, RIVER_RAIL, hw - 0.10, hw, dark)
	_riv_bbox(acc, rust, b, -hs, hs, dy + RIVER_RAIL - 0.02, 0.09, -hw - 0.05, -hw + 0.15, steel)
	_riv_bbox(acc, rust, b, -hs, hs, dy + RIVER_RAIL - 0.02, 0.09, hw - 0.15, hw + 0.05, steel)
	for puv in [-hs * 0.45, hs * 0.45]:
		var pu: float = puv
		_riv_bbox(acc, con, b, pu - 0.85, pu + 0.85, by, 0.50, -hw - 0.15, hw + 0.15, dark)
		acc.cyl(con, _riv_bp(b, pu, by + 0.45, 0.0), _riv_bp(b, pu, dy - 0.30, 0.0), 0.50, 0.40, 8, stone)
	# ---- the two stairs that make it reachable. A deck flush with the parapet
	#      is still 0.66 m above the carriageway to the west and 0.70 m above
	#      the promenade to the east; without these it bridges nothing.
	for k in 4:
		var wu := -hs - 1.2 + float(k) * 0.30
		var wt := 0.04 + float(k + 1) * ((dy - 0.04) / 4.0)
		_riv_bbox(acc, con, b, wu, wu + 0.30, by, wt - by, -hw, hw, stone)
		var eu := hs + float(k) * 0.30
		var et := dy * float(3 - k) / 4.0
		_riv_bbox(acc, con, b, eu, eu + 0.30, by, et - by, -hw, hw, stone)
	acc.cyl(met, _riv_bp(b, 0.0, dy, -hw + 0.18), _riv_bp(b, 0.0, dy + 2.90, -hw + 0.18), 0.08, 0.06, 6, dark)
	_riv_bbox(acc, neon, b, -0.28, 0.28, dy + 2.82, 0.22, -hw - 0.06, -hw + 0.42, Color(0.86, 0.94, 1.0))
	var fp := _riv_bp(b, 0.0, dy + 2.85, -hw + 0.18)
	lamp_posts.append({"pos": fp, "district": district_at(fp), "color": Color(0.86, 0.94, 1.0)})


# ----------------------------------------------------------------- queries --
func _rect_dist(r: Rect2, p: Vector2) -> float:
	var c := p.clamp(r.position, r.end)
	return c.distance_to(p)


func district_at(pos: Vector3) -> String:
	var best := ""
	var bd := 1e9
	for id in district_bounds:
		var r: Rect2 = district_bounds[id]
		if r.has_point(Vector2(pos.x, pos.z)):
			return id
		var d: float = _rect_dist(r, Vector2(pos.x, pos.z))
		if d < bd:
			bd = d
			best = id
	return best


func nearest_lamp_positions(center: Vector3, count: int) -> Array:
	var out := []
	for l in lamp_posts:
		out.append([ (Vector3(l["pos"].x, 0, l["pos"].z) - Vector3(center.x, 0, center.z)).length_squared(), l ])
	out.sort_custom(func(a, b): return a[0] < b[0])
	var res := []
	for i in mini(count, out.size()):
		res.append(out[i][1])
	return res


func set_night_emission(on: bool) -> void:
	for k in _mats:
		if k.begins_with("facade_"):
			_mats[k].emission_energy_multiplier = 1.6 if on else 0.0

# ------------------------------------------------------------------ GPS ----
var _rg_nodes: PackedVector3Array = PackedVector3Array()
var _rg_adj: Array = []                     # per node: Array of [node_idx, cost]
var _rg_built := false


func _route_graph_build() -> void:
	_rg_nodes = PackedVector3Array()
	_rg_adj = []
	var index := {}
	for lane in lanes:
		var ids := []
		for p in lane:
			var key := Vector2(round(p.x * 2) / 2, round(p.z * 2) / 2)
			if not index.has(key):
				index[key] = _rg_nodes.size()
				_rg_nodes.append(p)
				_rg_adj.append([])
			ids.append(index[key])
		for i in ids.size():
			var a: int = ids[i]
			var b: int = ids[(i + 1) % ids.size()]
			var c: float = (_rg_nodes[a] - _rg_nodes[b]).length()
			_rg_adj[a].append([b, c])
			_rg_adj[b].append([a, c])
	# transfers: near-coincident nodes
	var n := _rg_nodes.size()
	for i in n:
		for j in range(i + 1, n):
			if (_rg_nodes[i] - _rg_nodes[j]).length() < 5.0:
				if _river_blocked(_rg_nodes[i], _rg_nodes[j]):
					continue
				_rg_adj[i].append([j, 2.0])
				_rg_adj[j].append([i, 2.0])
	# k-NN stitching: lane loops are per-block islands; connect every node to
	# its 2 nearest neighbours (cap 70 m) so the whole road network is one
	# navigable graph with cycles.
	for i in _rg_nodes.size():
		var best := [[1e18, -1], [1e18, -1]]
		for j in _rg_nodes.size():
			if i == j:
				continue
			var dd := (_rg_nodes[i] - _rg_nodes[j]).length_squared()
			if dd < best[0][0]:
				best[1] = best[0]
				best[0] = [dd, j]
			elif dd < best[1][0]:
				best[1] = [dd, j]
		for b in best:
			if b[1] >= 0 and b[0] < 70.0 * 70.0 and not _river_blocked(_rg_nodes[i], _rg_nodes[b[1]]):
				var c: float = sqrt(b[0])
				var dup := false
				for e in _rg_adj[i]:
					if e[0] == b[1]:
						dup = true
						break
				if not dup:
					_rg_adj[i].append([b[1], c])
					_rg_adj[b[1]].append([i, c])
	# ---- crossing nodes ----------------------------------------------------
	# Pruning the wading edges is only half the job; on its own it would leave
	# the graph exactly as disconnected as it found it, and it found it badly
	# disconnected. The lane rings are per-block islands stitched by a 70 m
	# k-NN, and the gap between Neon Mile's easternmost ring (x = 137.8) and
	# Crown Heights' westernmost (x = 242) is 104 m, so Crown Heights was a
	# 48-node island with no edge to the rest of the city. route_world()
	# returned an EMPTY path for any journey to or from it: the Overlook, the
	# Country Club, the Observatory, Crown Premium Fuels and the Crown Heights
	# stash all had a GPS that drew nothing at all — and m12_everyone opens with
	# goto(poi_overlook), so the finale sent the player to a waypoint the phone
	# could not route to. A crossing is a real edge in the real city, so it
	# becomes one here.
	rg_lane_count = _rg_nodes.size()
	for bb in river_bridges:
		var b: Dictionary = bb
		var at: Vector2 = b["at"]
		var hs: float = b["half_span"]
		var deck := Vector3(at.x, 0.0, at.y)
		var bi := _rg_add_node(deck)
		if str(b["kind"]) == "road":
			for sidev in [-1.0, 1.0]:
				var side: float = sidev
				var bank: Vector3
				if str(b["axis"]) == "z":
					bank = Vector3(at.x, 0.0, at.y + side * (hs + 6.0))
				else:
					bank = Vector3(at.x + side * (hs + 6.0), 0.0, at.y)
				_rg_link_clear(bi, bank, deck, rg_lane_count)
		else:
			# A footbridge gets a node on the deck AND a node on the bank it
			# lands on. One node is not enough: a straight tie from the middle
			# of a 20 m span to a lane node 24 m away on the far bank clips the
			# very water the span exists to avoid, which would put the crossing
			# back on the wading list it was added to get off.
			var landing := Vector3(float(b.get("deck_x1", at.x + hs)) + 6.0, 0.0, at.y)
			var li := _rg_add_node(landing)
			_rg_link(bi, li)
			_rg_link_clear(bi, Vector3(float(b.get("deck_x0", at.x - hs)) - 6.0, 0.0, at.y), deck, rg_lane_count)
			_rg_link_clear(li, landing, landing, rg_lane_count)
	_rg_built = true


func _rg_nearest(p: Vector3, limit: int = -1) -> int:
	## Nearest graph node to p, or -1 if the graph is empty. limit restricts the
	## search to indices below it, which is how the bridge insertion finds a
	## LANE node to tie into instead of finding itself.
	var best := -1
	var bd := 1e18
	var hi: int = _rg_nodes.size() if limit < 0 else mini(limit, _rg_nodes.size())
	for i in hi:
		var d := (_rg_nodes[i] - p).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


var rg_lane_count := 0           # nodes below this are lane nodes; the rest are
                                 # crossings inserted by _route_graph_build


func _rg_add_node(p: Vector3) -> int:
	_rg_nodes.append(p)
	_rg_adj.append([])
	return _rg_nodes.size() - 1


func _rg_link(i: int, j: int) -> void:
	if i < 0 or j < 0 or i == j:
		return
	var c: float = (_rg_nodes[i] - _rg_nodes[j]).length()
	_rg_adj[i].append([j, c])
	_rg_adj[j].append([i, c])


func _rg_link_clear(i: int, near: Vector3, from: Vector3, limit: int) -> void:
	## Tie node i to the lane node nearest `near` whose straight tie from
	## `from` does not wade. Falls back to the plain nearest, because a
	## crossing that ties to nothing is worse than one whose tie line clips a
	## corner of water it is already standing over.
	var best := -1
	var bd := 1e18
	var fb := -1
	var fbd := 1e18
	var hi: int = mini(limit, _rg_nodes.size())
	for k in hi:
		var d: float = (_rg_nodes[k] - near).length_squared()
		if d < fbd:
			fbd = d
			fb = k
		if d < bd and not _river_blocked(from, _rg_nodes[k]):
			bd = d
			best = k
	_rg_link(i, best if best >= 0 else fb)


func _river_blocked(a: Vector3, b: Vector3) -> bool:
	## True when the straight line a->b wades: some sample point is open water
	## and not on a bridge deck. A GPS that tells you to drive into the Cut is
	## worse than a GPS with no opinion, so the stitch loops above skip these.
	if not _river_built:
		return false
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	# Fast reject. Godot 3's Rect2.intersects_segment() is gone and Godot 4's
	# Geometry2D has no segment/rect test at all, so this compares the segment's
	# closest point to the bounds centre against the bounds' half-diagonal —
	# conservative, and cheap enough to run inside an O(n^2) stitch loop. The
	# per-sample in_river() walk below is what actually decides.
	var bc := river_bounds.get_center()
	var reach := river_bounds.size.length() * 0.5 + 1.0
	if Geometry2D.get_closest_point_to_segment(bc, pa, pb).distance_to(bc) > reach:
		return false
	var steps := int(ceil(pb.distance_to(pa) / 3.0)) + 1
	for k in range(steps + 1):
		if in_river(pa.lerp(pb, float(k) / float(steps))):
			return true
	return false


func route_world(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _rg_built:
		_route_graph_build()
	if _rg_nodes.size() == 0:
		return PackedVector3Array()
	var start := _rg_nearest(from)
	var goal := _rg_nearest(to)
	if start == goal:
		return PackedVector3Array([from, to])
	var g := {}
	var came := {}
	g[start] = 0.0
	var open := [[0.0, start]]
	var done := {}
	while open.size() > 0:
		open.sort()
		var cur: int = open[0][1]
		open.remove_at(0)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == goal:
			break
		for e in _rg_adj[cur]:
			var nx: int = e[0]
			var ng: float = g[cur] + e[1]
			if not g.has(nx) or ng < g[nx]:
				g[nx] = ng
				came[nx] = cur
				open.append([ng + (_rg_nodes[nx] - _rg_nodes[goal]).length(), nx])
	if not came.has(goal) and start != goal:
		return PackedVector3Array()
	var path := PackedVector3Array()
	var c: int = goal
	path.append(to)
	while c != start:
		path.append(_rg_nodes[c])
		if not came.has(c):
			break
		c = came[c]
	path.append(from)
	var rev := PackedVector3Array()
	for i in range(path.size() - 1, -1, -1):
		rev.append(path[i])
	return rev


func route_length(path: PackedVector3Array) -> float:
	var L := 0.0
	for i in path.size() - 1:
		L += (path[i + 1] - path[i]).length()
	return L

