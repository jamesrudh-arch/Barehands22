class_name Humanoid
extends RefCounted
## Humanoid — builds a fully rigged, skinned, proportioned human mesh in code.
## One MeshInstance (6 material surfaces) + Skeleton3D (22 bones).
## Characters differ by height, build, skin, hair, face texture and outfit
## colors, so nobody is a recoloured clone: silhouette, hair shape and
## proportions all vary. Original procedural geometry.

const BONES := [
	"root", "hips", "spine", "chest", "neck", "head",
	"shoulder_l", "upper_arm_l", "forearm_l", "hand_l",
	"shoulder_r", "upper_arm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "toe_l",
	"thigh_r", "shin_r", "foot_r", "toe_r",
]
const BI := {  # bone index lookup
	"root": 0, "hips": 1, "spine": 2, "chest": 3, "neck": 4, "head": 5,
	"shoulder_l": 6, "upper_arm_l": 7, "forearm_l": 8, "hand_l": 9,
	"shoulder_r": 10, "upper_arm_r": 11, "forearm_r": 12, "hand_r": 13,
	"thigh_l": 14, "shin_l": 15, "foot_l": 16, "toe_l": 17,
	"thigh_r": 18, "shin_r": 19, "foot_r": 20, "toe_r": 21,
}

const SKINS := [
	Color(0.91, 0.75, 0.60), Color(0.81, 0.63, 0.46), Color(0.67, 0.48, 0.33),
	Color(0.47, 0.32, 0.22), Color(0.35, 0.24, 0.16), Color(0.94, 0.82, 0.71),
	Color(0.59, 0.41, 0.27), Color(0.24, 0.16, 0.12),
]
const HAIRS := [
	Color(0.09, 0.07, 0.06), Color(0.16, 0.10, 0.06), Color(0.30, 0.18, 0.08),
	Color(0.55, 0.35, 0.12), Color(0.75, 0.65, 0.45), Color(0.85, 0.85, 0.85),
	Color(0.45, 0.10, 0.10), Color(0.10, 0.12, 0.20),
]

# rest-pose skeleton (meters), scaled by height later
const REST := {
	"hips": Vector3(0, 1.00, 0),
	"spine": Vector3(0, 0.13, 0),
	"chest": Vector3(0, 0.17, 0),
	"neck": Vector3(0, 0.21, 0),
	"head": Vector3(0, 0.10, 0),
	"shoulder_l": Vector3(0.06, 0.16, 0),
	"upper_arm_l": Vector3(0.13, -0.06, 0),
	"forearm_l": Vector3(0.0, -0.27, 0.01),
	"hand_l": Vector3(0, -0.25, 0.01),
	"shoulder_r": Vector3(-0.06, 0.16, 0),
	"upper_arm_r": Vector3(-0.13, -0.06, 0),
	"forearm_r": Vector3(0.0, -0.27, 0.01),
	"hand_r": Vector3(0, -0.25, 0.01),
	"thigh_l": Vector3(0.10, -0.05, 0),
	"shin_l": Vector3(0, -0.44, 0),
	"foot_l": Vector3(0, -0.43, 0),
	"toe_l": Vector3(0, -0.045, 0.05),
	"thigh_r": Vector3(-0.10, -0.05, 0),
	"shin_r": Vector3(0, -0.44, 0),
	"foot_r": Vector3(0, -0.43, 0),
	"toe_r": Vector3(0, -0.045, 0.05),
}
const PARENT := {
	"root": -1, "hips": 0, "spine": 1, "chest": 2, "neck": 3, "head": 4,
	"shoulder_l": 3, "upper_arm_l": 6, "forearm_l": 7, "hand_l": 8,
	"shoulder_r": 3, "upper_arm_r": 10, "forearm_r": 11, "hand_r": 12,
	"thigh_l": 1, "shin_l": 14, "foot_l": 15, "toe_l": 16,
	"thigh_r": 1, "shin_r": 18, "foot_r": 19, "toe_r": 20,
}

# material slot ids
const M_SKIN := 0
const M_FACE := 1
const M_HAIR := 2
const M_TOP := 3
const M_LEGS := 4
const M_SHOE := 5


# ------------------------------------------------------- part accumulator --
class Parts:
	var data := {}   # slot -> dict of arrays

	func _init() -> void:
		for i in 6:
			data[i] = {"v": PackedVector3Array(), "n": PackedVector3Array(),
				"uv": PackedVector2Array(), "idx": PackedInt32Array(),
				"bones": PackedInt32Array(), "w": PackedFloat32Array()}

	func _push(d: Dictionary, p: Vector3, n: Vector3, uv: Vector2, b: int, b2: int, w2: float) -> void:
		d["v"].append(p)
		d["n"].append(n)
		d["uv"].append(uv)
		d["bones"].append(b)
		d["bones"].append(b2 if b2 >= 0 else b)
		d["bones"].append(0)
		d["bones"].append(0)
		d["w"].append(1.0 - w2)
		d["w"].append(w2 if b2 >= 0 else 0.0)
		d["w"].append(0.0)
		d["w"].append(0.0)

	func quad(slot: int, a: Vector3, b: Vector3, c: Vector3, d2: Vector3,
			na: Vector3, bone: int, bone2 := -1, w2 := 0.0,
			uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]) -> void:
		var dd: Dictionary = data[slot]
		var base: int = dd["v"].size()
		_push(dd, a, na, uvs[0], bone, bone2, w2)
		_push(dd, b, na, uvs[1], bone, bone2, w2)
		_push(dd, c, na, uvs[2], bone, bone2, w2)
		_push(dd, d2, na, uvs[3], bone, bone2, w2)
		dd["idx"].append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func box(slot: int, center: Vector3, size: Vector3, bone: int, bone2 := -1, w2 := 0.0, uvscale := 2.0) -> void:
		var h := size * 0.5
		var c := center
		# +Z front (face dir), -Z back, +X left, -X right, +Y top, -Y bottom
		quad(slot, c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z), Vector3(0, 0, 1), bone, bone2, w2,
			[Vector2(0, 1), Vector2(size.x * uvscale, 1), Vector2(size.x * uvscale, 1 - size.y * uvscale), Vector2(0, 1 - size.y * uvscale)])
		quad(slot, c + Vector3(h.x, -h.y, -h.z), c + Vector3(-h.x, -h.y, -h.z), c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z), Vector3(0, 0, -1), bone, bone2, w2)
		quad(slot, c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(h.x, h.y, h.z), Vector3(1, 0, 0), bone, bone2, w2)
		quad(slot, c + Vector3(-h.x, -h.y, -h.z), c + Vector3(-h.x, -h.y, h.z), c + Vector3(-h.x, h.y, h.z), c + Vector3(-h.x, h.y, -h.z), Vector3(-1, 0, 0), bone, bone2, w2)
		quad(slot, c + Vector3(-h.x, h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z), Vector3(0, 1, 0), bone, bone2, w2)
		quad(slot, c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z), Vector3(0, -1, 0), bone, bone2, w2)

	func cyl(slot: int, from: Vector3, to: Vector3, r1: float, r2: float, bone: int, bone2 := -1, w2 := 0.0, seg := 8) -> void:
		var dir := (to - from)
		var length := dir.length()
		if length < 0.001:
			return
		dir = dir / length
		var up := Vector3(0, 0, 1) if abs(dir.y) < 0.9 else Vector3(1, 0, 0)
		var x := dir.cross(up).normalized()
		var y := dir.cross(x).normalized()
		var dd: Dictionary = data[slot]
		var ring1 := []
		var ring2 := []
		for i in seg:
			var a := TAU * i / seg
			var off := Vector3(cos(a), sin(a), 0)
			ring1.append(dd["v"].size())
			_push(dd, from + (x * off.x + y * off.y) * r1, (x * off.x + y * off.y).normalized(), Vector2(float(i) / seg, 0), bone, bone2, w2)
			ring2.append(dd["v"].size())
			_push(dd, to + (x * off.x + y * off.y) * r2, (x * off.x + y * off.y).normalized(), Vector2(float(i) / seg, length), bone, bone2, w2)
		for i in seg:
			var j := (i + 1) % seg
			dd["idx"].append_array([ring1[i], ring2[i], ring2[j], ring1[i], ring2[j], ring1[j]])
		# caps
		var c1: int = dd["v"].size()
		_push(dd, from, -dir, Vector2(0.5, 0.5), bone, bone2, w2)
		for i in seg:
			var j := (i + 1) % seg
			dd["idx"].append_array([c1, ring1[j], ring1[i]])
		var c2: int = dd["v"].size()
		_push(dd, to, dir, Vector2(0.5, 0.5), bone, bone2, w2)
		for i in seg:
			var j := (i + 1) % seg
			dd["idx"].append_array([c2, ring2[i], ring2[j]])

	func sphere(slot: int, center: Vector3, r: Vector3, bone: int, bone2 := -1, w2 := 0.0, seg := 10, rings := 6) -> void:
		var dd: Dictionary = data[slot]
		var grid := []
		for ri in rings + 1:
			var phi := PI * ri / rings
			var row := []
			for si in seg:
				var th := TAU * si / seg
				var nrm := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
				row.append(dd["v"].size())
				_push(dd, center + Vector3(nrm.x * r.x, nrm.y * r.y, nrm.z * r.z), nrm, Vector2(float(si) / seg, float(ri) / rings), bone, bone2, w2)
			grid.append(row)
		for ri in rings:
			for si in seg:
				var sj := (si + 1) % seg
				dd["idx"].append_array([grid[ri][si], grid[ri + 1][si], grid[ri + 1][sj], grid[ri][si], grid[ri + 1][sj], grid[ri][sj]])


# ---------------------------------------------------------------- build ----
static func rest_global(bone: String) -> Vector3:
	var p: Vector3 = REST.get(bone, Vector3.ZERO)
	var par: int = PARENT[bone]
	while par > 0:
		var name: String = BONES[par]
		p += REST.get(name, Vector3.ZERO)
		par = PARENT[name]
	return p


static func build_skeleton(height: float) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	var scale := height / 1.8
	for i in BONES.size():
		sk.add_bone(BONES[i])
	for i in BONES.size():
		sk.set_bone_parent(i, PARENT[BONES[i]])
	for i in BONES.size():
		var name: String = BONES[i]
		var local: Vector3 = REST[name] if REST.has(name) else Vector3.ZERO
		sk.set_bone_rest(i, Transform3D(Basis(), local * scale))
	return sk


static func build_mesh(parts: Parts, height: float) -> ArrayMesh:
	var m := ArrayMesh.new()
	var scale := height / 1.8
	for slot in parts.data:
		var d: Dictionary = parts.data[slot]
		if d["v"].size() == 0:
			continue
		var verts := PackedVector3Array()
		verts.resize(d["v"].size())
		for i in d["v"].size():
			verts[i] = d["v"][i] * scale
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = d["n"]
		arr[Mesh.ARRAY_TEX_UV] = d["uv"]
		arr[Mesh.ARRAY_BONES] = d["bones"]
		arr[Mesh.ARRAY_WEIGHTS] = d["w"]
		arr[Mesh.ARRAY_INDEX] = d["idx"]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func make_materials(params: Dictionary) -> Array:
	var outfit: Dictionary = params.get("outfit_colors", {})
	var skin_i: int = params.get("skin", 0)
	var hair_i: int = params.get("hair_color", 0)
	var face_i: int = params.get("face", 0)
	var mats := []
	var skin_m := StandardMaterial3D.new()
	skin_m.albedo_color = SKINS[skin_i % SKINS.size()]
	skin_m.roughness = 0.65
	mats.append(skin_m)
	var face_m := StandardMaterial3D.new()
	var ftex := load("res://assets/textures/faces/face_%02d.png" % (face_i % 24))
	face_m.albedo_texture = ftex
	face_m.roughness = 0.6
	mats.append(face_m)
	var hair_m := StandardMaterial3D.new()
	hair_m.albedo_color = HAIRS[hair_i % HAIRS.size()]
	hair_m.roughness = 0.8
	mats.append(hair_m)
	var top := StandardMaterial3D.new()
	top.albedo_color = _col(outfit.get("jacket", [70, 64, 58]))
	top.roughness = 0.85
	top.normal_texture = load("res://assets/textures/world/fabric_wool_n.png")
	mats.append(top)
	var legs := StandardMaterial3D.new()
	legs.albedo_color = _col(outfit.get("pants", [46, 44, 48]))
	legs.roughness = 0.9
	legs.normal_texture = load("res://assets/textures/world/fabric_denim_n.png")
	mats.append(legs)
	var shoe := StandardMaterial3D.new()
	shoe.albedo_color = _col(outfit.get("shoes", [30, 28, 26]))
	shoe.roughness = 0.5
	mats.append(shoe)
	return mats


static func _col(a) -> Color:
	if a is Color:
		return a
	return Color(a[0] / 255.0, a[1] / 255.0, a[2] / 255.0)


static func build_body(parts: Parts, params: Dictionary) -> void:
	var build: float = params.get("build", 0.5)      # 0 thin .. 1 heavy
	var bw := 0.86 + build * 0.42                      # width multiplier
	var fem: bool = params.get("fem", false)
	var hipw := (1.02 if fem else 0.94) * bw
	var shw := (0.94 if fem else 1.06) * bw
	# torso
	parts.box(M_TOP, rest_global("hips") + Vector3(0, 0.04, 0), Vector3(0.30 * hipw, 0.20, 0.19 * bw), BI["hips"], BI["spine"], 0.35)
	parts.box(M_TOP, rest_global("spine") + Vector3(0, 0.06, 0), Vector3(0.28 * bw, 0.18, 0.18 * bw), BI["spine"], BI["chest"], 0.3)
	parts.box(M_TOP, rest_global("chest") + Vector3(0, 0.07, 0), Vector3(0.34 * shw, 0.22, 0.20 * bw), BI["chest"])
	parts.cyl(M_SKIN, rest_global("neck"), rest_global("neck") + Vector3(0, 0.10, 0.01), 0.055, 0.05, BI["neck"])
	# head: skull box + face plate + nose + ears
	var hg := rest_global("head")
	parts.box(M_SKIN, hg + Vector3(0, 0.09, -0.01), Vector3(0.155, 0.20, 0.185), BI["head"])
	parts.quad(M_FACE, hg + Vector3(-0.0775, 0.02, 0.083), hg + Vector3(0.0775, 0.02, 0.083),
		hg + Vector3(0.0775, 0.175, 0.083), hg + Vector3(-0.0775, 0.175, 0.083), Vector3(0, 0, 1), BI["head"])
	parts.box(M_SKIN, hg + Vector3(0, 0.085, 0.095), Vector3(0.03, 0.05, 0.03), BI["head"])
	parts.box(M_SKIN, hg + Vector3(0.082, 0.10, 0.0), Vector3(0.02, 0.05, 0.04), BI["head"])
	parts.box(M_SKIN, hg + Vector3(-0.082, 0.10, 0.0), Vector3(0.02, 0.05, 0.04), BI["head"])
	_hair(parts, params, hg)
	# arms
	for side in ["l", "r"]:
		var sgn := 1.0 if side == "l" else -1.0
		var sh := rest_global("shoulder_" + side) + Vector3(sgn * 0.10 * shw, 0, 0)
		parts.sphere(M_TOP, sh, Vector3(0.075, 0.075, 0.075), BI["upper_arm_" + side])
		var ua := rest_global("upper_arm_" + side)
		var fa := ua + rest_global("forearm_" + side).normalized() * 0.0
		parts.cyl(M_TOP, ua, ua + Vector3(0, -0.27, 0.01), 0.052 * bw, 0.044, BI["upper_arm_" + side])
		var fao := ua + Vector3(0, -0.27, 0.01)
		parts.cyl(M_SKIN, fao, fao + Vector3(0, -0.25, 0.01), 0.042, 0.033, BI["forearm_" + side])
		var ha := fao + Vector3(0, -0.25, 0.01)
		parts.box(M_SKIN, ha + Vector3(0, -0.05, 0.01), Vector3(0.045, 0.11, 0.09), BI["hand_" + side])
	# legs
	for side in ["l", "r"]:
		var th := rest_global("thigh_" + side)
		parts.cyl(M_LEGS, th, th + Vector3(0, -0.44, 0), 0.085 * bw * hipw, 0.062, BI["thigh_" + side])
		var sh2 := th + Vector3(0, -0.44, 0)
		parts.cyl(M_LEGS, sh2, sh2 + Vector3(0, -0.43, 0), 0.058, 0.040, BI["shin_" + side])
		var ft := sh2 + Vector3(0, -0.43, 0)
		parts.box(M_SHOE, ft + Vector3(0, -0.035, 0.05), Vector3(0.09, 0.08, 0.26), BI["foot_" + side])
		parts.box(M_SHOE, ft + Vector3(0, -0.055, 0.16), Vector3(0.085, 0.05, 0.10), BI["toe_" + side])


static func _hair(parts: Parts, params: Dictionary, hg: Vector3) -> void:
	var style: String = params.get("hair", "crop")
	var top := hg + Vector3(0, 0.185, -0.01)
	match style:
		"bald", "none":
			return
		"buzz":
			parts.box(M_HAIR, top + Vector3(0, 0.005, -0.01), Vector3(0.16, 0.05, 0.19), BI["head"])
		"crop":
			parts.box(M_HAIR, top + Vector3(0, 0.012, -0.015), Vector3(0.165, 0.075, 0.20), BI["head"])
		"fade":
			parts.box(M_HAIR, top + Vector3(0, 0.02, -0.01), Vector3(0.163, 0.09, 0.195), BI["head"])
			parts.box(M_HAIR, top + Vector3(0, -0.02, -0.06), Vector3(0.166, 0.06, 0.10), BI["head"])
		"slick":
			parts.box(M_HAIR, top + Vector3(0, 0.01, -0.03), Vector3(0.16, 0.06, 0.23), BI["head"])
		"quiff":
			parts.box(M_HAIR, top + Vector3(0, 0.015, -0.01), Vector3(0.163, 0.08, 0.19), BI["head"])
			parts.box(M_HAIR, top + Vector3(0, 0.05, 0.07), Vector3(0.14, 0.07, 0.08), BI["head"])
		"bob":
			parts.box(M_HAIR, top + Vector3(0, 0.0, -0.01), Vector3(0.175, 0.10, 0.21), BI["head"])
			parts.box(M_HAIR, top + Vector3(0.085, -0.09, -0.01), Vector3(0.03, 0.16, 0.19), BI["head"])
			parts.box(M_HAIR, top + Vector3(-0.085, -0.09, -0.01), Vector3(0.03, 0.16, 0.19), BI["head"])
		"ponytail":
			parts.box(M_HAIR, top + Vector3(0, 0.012, -0.015), Vector3(0.165, 0.075, 0.20), BI["head"])
			parts.cyl(M_HAIR, top + Vector3(0, -0.02, -0.10), top + Vector3(0, -0.22, -0.14), 0.035, 0.02, BI["head"])
		"dreads":
			parts.box(M_HAIR, top + Vector3(0, 0.012, -0.015), Vector3(0.168, 0.075, 0.20), BI["head"])
			for i in 7:
				var a := TAU * i / 7.0
				var off := Vector3(cos(a) * 0.07, -0.05, sin(a) * 0.07 - 0.03)
				parts.cyl(M_HAIR, top + off, top + off + Vector3(off.x * 0.6, -0.20, off.z * 0.4), 0.016, 0.012, BI["head"])
		"locs":
			parts.box(M_HAIR, top + Vector3(0, 0.012, -0.015), Vector3(0.168, 0.075, 0.20), BI["head"])
			for i in 5:
				var off := Vector3(-0.06 + i * 0.03, -0.06, -0.09)
				parts.cyl(M_HAIR, top + off, top + off + Vector3(0, -0.16, -0.02), 0.018, 0.014, BI["head"])
		"bun":
			parts.box(M_HAIR, top + Vector3(0, 0.012, -0.015), Vector3(0.165, 0.075, 0.20), BI["head"])
			parts.sphere(M_HAIR, top + Vector3(0, 0.02, -0.12), Vector3(0.05, 0.05, 0.05), BI["head"])
		"chignon":
			parts.box(M_HAIR, top + Vector3(0, 0.008, -0.02), Vector3(0.162, 0.06, 0.20), BI["head"])
			parts.sphere(M_HAIR, top + Vector3(0, -0.06, -0.11), Vector3(0.045, 0.045, 0.045), BI["head"])
		"wrap":
			parts.box(M_HAIR, top + Vector3(0, 0.02, -0.01), Vector3(0.17, 0.10, 0.20), BI["head"])
		"afro":
			parts.sphere(M_HAIR, top + Vector3(0, 0.03, -0.01), Vector3(0.13, 0.12, 0.13), BI["head"])
		"tonsure":
			parts.box(M_HAIR, top + Vector3(0, -0.03, -0.02), Vector3(0.168, 0.05, 0.20), BI["head"])
		"cap":
			parts.box(M_HAIR, top + Vector3(0, 0.02, -0.01), Vector3(0.17, 0.08, 0.20), BI["head"])
			parts.box(M_HAIR, top + Vector3(0, 0.0, 0.12), Vector3(0.15, 0.02, 0.10), BI["head"])
		_:
			parts.box(M_HAIR, top + Vector3(0, 0.012, -0.015), Vector3(0.165, 0.075, 0.20), BI["head"])


## Builds the whole character node: Skeleton + MeshInstance (+ optional shadow tweaks)
static func build(params: Dictionary) -> Node3D:
	var height: float = params.get("height", 1.8)
	var root := Node3D.new()
	var sk := build_skeleton(height)
	root.add_child(sk)
	var parts := Parts.new()
	build_body(parts, params)
	var mesh := build_mesh(parts, height)
	var mi := MeshInstance3D.new()
	mi.skeleton = NodePath("..")
	mi.mesh = mesh
	var mats := make_materials(params)
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
		mi.material_override = null
	sk.add_child(mi)
	mi.set_owner(sk)
	root.name = "Humanoid"
	return root
