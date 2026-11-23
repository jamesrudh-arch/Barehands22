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

	func loft(slot: int, rings: Array, bone: int, bone2 := -1, w2 := 0.0, seg := 12, caps := true) -> void:
		# rings: Array of [center:Vector3, rx:float, rz:float] — elliptical cross-sections,
		# bottom-to-top. Smooth tapered anatomy / clothing shells.
		var dd: Dictionary = data[slot]
		var rows: int = rings.size()
		if rows < 2:
			return
		var base: int = dd["v"].size()
		for r in rows:
			var c: Vector3 = rings[r][0]
			var rx: float = rings[r][1]
			var rz: float = rings[r][2]
			for i in seg:
				var a := TAU * i / seg
				var nrm := Vector3(cos(a) * rz, 0.0, sin(a) * rx).normalized()
				_push(dd, c + Vector3(cos(a) * rx, 0.0, sin(a) * rz), nrm,
					Vector2(float(i) / seg, float(r) / max(1, rows - 1)), bone, bone2, w2)
		for r in rows - 1:
			for i in seg:
				var j := (i + 1) % seg
				var i0 := base + r * seg + i
				var i1 := base + r * seg + j
				var i2 := base + (r + 1) * seg + j
				var i3 := base + (r + 1) * seg + i
				dd["idx"].append_array([i0, i1, i2, i0, i2, i3])
		if caps:
			var c0: Vector3 = rings[0][0]
			var b0: int = dd["v"].size()
			_push(dd, c0, Vector3(0, -1, 0), Vector2(0.5, 0.0), bone, bone2, w2)
			for i in seg:
				var j := (i + 1) % seg
				dd["idx"].append_array([b0, base + j, base + i])
			var cn: Vector3 = rings[rows - 1][0]
			var b1: int = dd["v"].size()
			_push(dd, cn, Vector3(0, 1, 0), Vector2(0.5, 1.0), bone, bone2, w2)
			var top := base + (rows - 1) * seg
			for i in seg:
				var j := (i + 1) % seg
				dd["idx"].append_array([b1, top + i, top + j])

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
	# ---- v2 anatomy: lofted torso/limbs, layered clothing, sculpted head ----
	var build: float = params.get("build", 0.5)      # 0 thin .. 1 heavy
	var bw := 0.88 + build * 0.36                    # girth multiplier (subtler)
	var fem: bool = params.get("fem", false)
	var hipw := (1.06 if fem else 0.96) * bw
	var shw := (0.92 if fem else 1.08) * bw
	var hips := rest_global("hips")
	var spine := rest_global("spine")
	var chest := rest_global("chest")
	var neck := rest_global("neck")
	# torso: pelvis loft + chest loft (overlapping at waist)
	parts.loft(M_TOP, [
		[hips + Vector3(0, -0.06, 0), 0.150 * hipw, 0.100 * bw],
		[hips + Vector3(0, 0.02, 0), 0.156 * hipw, 0.104 * bw],
		[spine + Vector3(0, -0.02, 0), 0.138 * bw, 0.096 * bw],
		[spine + Vector3(0, 0.06, 0), 0.148 * bw, 0.100 * bw]],
		BI["hips"], BI["spine"], 0.35)
	parts.loft(M_TOP, [
		[spine + Vector3(0, 0.04, 0), 0.146 * bw, 0.099 * bw],
		[chest + Vector3(0, 0.00, 0), 0.168 * shw, 0.106 * bw],
		[chest + Vector3(0, 0.08, 0), 0.176 * shw, 0.102 * bw],
		[chest + Vector3(0, 0.14, 0), 0.128 * shw, 0.088 * bw]],
		BI["spine"], BI["chest"], 0.3)
	# jacket shell: offset loft waist->shoulders + collar + hem (real cloth layer)
	parts.loft(M_TOP, [
		[hips + Vector3(0, 0.00, 0), 0.170 * hipw, 0.115 * bw],
		[spine + Vector3(0, 0.00, 0), 0.156 * bw, 0.108 * bw],
		[chest + Vector3(0, 0.02, 0), 0.180 * shw, 0.116 * bw],
		[chest + Vector3(0, 0.10, 0), 0.186 * shw, 0.112 * bw],
		[chest + Vector3(0, 0.15, 0), 0.140 * shw, 0.096 * bw]],
		BI["spine"], BI["chest"], 0.25)
	parts.loft(M_TOP, [
		[neck + Vector3(0, -0.02, -0.01), 0.085, 0.075],
		[neck + Vector3(0, 0.045, -0.012), 0.078, 0.070]], BI["chest"], -1, 0.0, 10)
	# glutes + shoulder caps
	for sgn in [1.0, -1.0]:
		parts.sphere(M_LEGS, hips + Vector3(sgn * 0.075 * hipw, -0.04, -0.055),
			Vector3(0.085, 0.085, 0.075), BI["hips"])
	# neck + head
	parts.cyl(M_SKIN, neck + Vector3(0, -0.02, 0), neck + Vector3(0, 0.10, 0.012), 0.058, 0.050, BI["neck"], -1, 0.0, 10)
	var hg := rest_global("head")
	parts.sphere(M_SKIN, hg + Vector3(0, 0.105, -0.012), Vector3(0.096, 0.112, 0.104), BI["head"], -1, 0.0, 14, 10)
	# jaw + chin + cheeks + brow + nose + lips + ears
	parts.loft(M_SKIN, [
		[hg + Vector3(0, 0.045, 0.010), 0.078, 0.088],
		[hg + Vector3(0, 0.010, 0.022), 0.062, 0.072],
		[hg + Vector3(0, -0.015, 0.030), 0.040, 0.050]], BI["head"], -1, 0.0, 10)
	parts.sphere(M_SKIN, hg + Vector3(0, 0.005, 0.070), Vector3(0.026, 0.022, 0.024), BI["head"])
	for sgn in [1.0, -1.0]:
		parts.sphere(M_SKIN, hg + Vector3(sgn * 0.052, 0.075, 0.045), Vector3(0.022, 0.024, 0.022), BI["head"])
		parts.sphere(M_SKIN, hg + Vector3(sgn * 0.096, 0.095, -0.005), Vector3(0.012, 0.034, 0.024), BI["head"])
	parts.box(M_SKIN, hg + Vector3(0, 0.128, 0.078), Vector3(0.052, 0.016, 0.018), BI["head"])
	parts.loft(M_SKIN, [
		[hg + Vector3(0, 0.105, 0.088), 0.014, 0.014],
		[hg + Vector3(0, 0.070, 0.100), 0.017, 0.020]], BI["head"], -1, 0.0, 8)
	parts.box(M_SKIN, hg + Vector3(0, 0.052, 0.086), Vector3(0.026, 0.010, 0.012), BI["head"])
	# face texture plate, just proud of the skull front
	parts.quad(M_FACE, hg + Vector3(-0.070, 0.045, 0.0965), hg + Vector3(0.070, 0.045, 0.0965),
		hg + Vector3(0.070, 0.170, 0.090), hg + Vector3(-0.070, 0.170, 0.090), Vector3(0, 0, 1), BI["head"])
	_hair(parts, params, hg)
	# arms: deltoid, tapered upper/sleeve, elbow, forearm, cuff, hand w/ thumb+fingers
	for side in ["l", "r"]:
		var sgn := 1.0 if side == "l" else -1.0
		var ua := rest_global("upper_arm_" + side) + Vector3(sgn * 0.015, 0, 0)
		parts.sphere(M_TOP, ua + Vector3(0, 0.01, 0), Vector3(0.070 * shw, 0.070, 0.070), BI["upper_arm_" + side])
		var elbow := ua + Vector3(0, -0.275, 0.012)
		parts.loft(M_SKIN, [
			[ua + Vector3(0, -0.01, 0), 0.052 * bw, 0.052 * bw],
			[ua + Vector3(0, -0.14, 0.006), 0.048 * bw, 0.048 * bw],
			[elbow, 0.041, 0.041]], BI["upper_arm_" + side])
		parts.loft(M_TOP, [
			[ua + Vector3(0, 0.005, 0), 0.064 * shw, 0.064 * shw],
			[ua + Vector3(0, -0.16, 0.007), 0.058 * bw, 0.058 * bw],
			[elbow + Vector3(0, 0.02, 0), 0.052, 0.052]], BI["upper_arm_" + side])
		parts.sphere(M_SKIN, elbow, Vector3(0.040, 0.042, 0.040), BI["forearm_" + side])
		var wrist := elbow + Vector3(0, -0.255, 0.010)
		parts.loft(M_SKIN, [
			[elbow + Vector3(0, -0.02, 0), 0.043, 0.043],
			[elbow + Vector3(0, -0.10, 0.004), 0.045, 0.043],
			[wrist, 0.029, 0.026]], BI["forearm_" + side])
		parts.loft(M_TOP, [
			[elbow + Vector3(0, -0.01, 0), 0.054, 0.054],
			[wrist + Vector3(0, 0.035, 0), 0.044, 0.042],
			[wrist + Vector3(0, 0.005, 0), 0.040, 0.038]], BI["forearm_" + side])
		# hand: palm + fingers + thumb
		var hd := wrist + Vector3(0, -0.045, 0.004)
		parts.loft(M_SKIN, [
			[wrist + Vector3(0, -0.005, 0), 0.030, 0.042],
			[hd, 0.032, 0.046],
			[hd + Vector3(0, -0.055, 0.004), 0.026, 0.040]], BI["hand_" + side], -1, 0.0, 8)
		parts.box(M_SKIN, hd + Vector3(sgn * 0.030, -0.020, 0.012), Vector3(0.016, 0.045, 0.020), BI["hand_" + side])
	# legs: tapered thigh + pants shell, knee, calf w/ bulge, ankle, shoe w/ sole+toe
	for side in ["l", "r"]:
		var th := rest_global("thigh_" + side)
		var knee := th + Vector3(0, -0.44, 0.01)
		parts.loft(M_LEGS, [
			[th + Vector3(0, 0.02, 0), 0.092 * bw * hipw, 0.096 * bw * hipw],
			[th + Vector3(0, -0.20, 0.005), 0.080 * bw, 0.084 * bw],
			[knee, 0.060, 0.062]], BI["thigh_" + side])
		parts.loft(M_LEGS, [
			[th + Vector3(0, 0.03, 0), 0.100 * bw * hipw, 0.104 * bw * hipw],
			[th + Vector3(0, -0.24, 0.006), 0.088 * bw, 0.092 * bw],
			[knee + Vector3(0, 0.03, 0), 0.070, 0.072]], BI["thigh_" + side])
		parts.sphere(M_LEGS, knee, Vector3(0.058, 0.060, 0.058), BI["shin_" + side])
		var ankle := knee + Vector3(0, -0.435, -0.01)
		parts.loft(M_LEGS, [
			[knee + Vector3(0, -0.03, 0), 0.058, 0.060],
			[knee + Vector3(0, -0.13, 0.006), 0.060, 0.062],
			[knee + Vector3(0, -0.28, 0.0), 0.042, 0.044],
			[ankle, 0.032, 0.034]], BI["shin_" + side])
		var ft := ankle + Vector3(0, -0.03, 0.01)
		parts.box(M_SHOE, ft + Vector3(0, -0.028, 0.045), Vector3(0.088, 0.036, 0.255), BI["foot_" + side])
		parts.loft(M_SHOE, [
			[ft + Vector3(0, 0.01, 0.02), 0.052, 0.090],
			[ft + Vector3(0, 0.055, 0.01), 0.056, 0.100],
			[ft + Vector3(0, 0.085, -0.02), 0.048, 0.078]], BI["foot_" + side], -1, 0.0, 10)
		parts.sphere(M_SHOE, ft + Vector3(0, -0.015, 0.155), Vector3(0.046, 0.030, 0.052), BI["toe_" + side])


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
