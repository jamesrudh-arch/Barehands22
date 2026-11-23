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


func _build_water(w: Dictionary) -> void:
	var z: float = w.get("water_z", -380)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1400, 260)
	mi.mesh = q
	mi.material_override = mat("water")
	mi.rotation_degrees.x = -90
	mi.position = Vector3(100, -0.6, z - 130)
	root.add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1400, 2, 260)
	cs.shape = box
	sb.position = Vector3(100, -1.5, z - 130)
	root.add_child(sb)


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
			if b[1] >= 0 and b[0] < 70.0 * 70.0:
				var c: float = sqrt(b[0])
				var dup := false
				for e in _rg_adj[i]:
					if e[0] == b[1]:
						dup = true
						break
				if not dup:
					_rg_adj[i].append([b[1], c])
					_rg_adj[b[1]].append([i, c])
	_rg_built = true


func _rg_nearest(p: Vector3) -> int:
	var best := 0
	var bd := 1e18
	for i in _rg_nodes.size():
		var d := (_rg_nodes[i] - p).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


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

