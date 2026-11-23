extends Node
## InteriorManager — generates enterable interiors on demand (one at a time),
## moves the player inside, and returns them to the street on exit.
## Interiors are procedural rooms with furniture sets per type; lighting is
## baked-feel (emissive strips + a couple of omnis) for mobile.

var current: Node3D = null
var current_id: String = ""
var return_pos: Vector3 = Vector3.ZERO
var return_rot: float = 0.0
var active := false

const ROOM_DEFS := {
	"int_apartment": {"w": 8, "d": 7, "h": 2.8, "floor": "wood_planks", "wall": "stucco", "furn": ["sofa", "table", "bed", "shelf", "kitchen"]},
	"int_ruths": {"w": 10, "d": 8, "h": 3.0, "floor": "tile_floor", "wall": "brick_red", "furn": ["counter", "tables4", "stove", "shelf", "jukebox"]},
	"int_church": {"w": 12, "d": 16, "h": 6.0, "floor": "wood_planks", "wall": "brick_dark", "furn": ["pews", "altar", "candles"]},
	"int_clinic": {"w": 8, "d": 7, "h": 2.8, "floor": "tile_floor", "wall": "stucco", "furn": ["counter", "bed", "shelf", "desk"]},
	"int_market": {"w": 10, "d": 8, "h": 3.2, "floor": "concrete", "wall": "stucco", "furn": ["shelves3", "counter", "crates"]},
	"int_berth7": {"w": 9, "d": 8, "h": 3.0, "floor": "concrete", "wall": "metal_panel", "furn": ["desk", "shelf", "crates", "sofa"]},
	"int_haulage": {"w": 14, "d": 12, "h": 5.0, "floor": "concrete", "wall": "metal_corrugated", "furn": ["crates", "shelf", "desk"]},
	"int_warehouse": {"w": 18, "d": 16, "h": 7.0, "floor": "concrete", "wall": "metal_corrugated", "furn": ["crates_many", "containers2"]},
	"int_lobby": {"w": 16, "d": 14, "h": 6.0, "floor": "tile_floor", "wall": "glass_dark", "furn": ["desk", "sofa", "plants"]},
	"int_precinct": {"w": 12, "d": 10, "h": 3.2, "floor": "tile_floor", "wall": "concrete", "furn": ["desks3", "counter", "cells"]},
	"int_crowe": {"w": 9, "d": 8, "h": 3.0, "floor": "carpet", "wall": "wood_planks", "furn": ["desk", "shelf", "sofa", "chair"]},
	"int_pawn": {"w": 8, "d": 7, "h": 2.9, "floor": "tile_floor", "wall": "brick_grey", "furn": ["counter", "shelves3", "shelf"]},
	"int_lounge": {"w": 12, "d": 10, "h": 3.2, "floor": "carpet", "wall": "brick_dark", "furn": ["bar", "tables4", "sofa", "stage"]},
	"int_club": {"w": 14, "d": 12, "h": 4.0, "floor": "tile_floor", "wall": "metal_panel", "furn": ["bar", "stage", "tables4"]},
	"int_casino": {"w": 16, "d": 12, "h": 3.6, "floor": "carpet", "wall": "stucco", "furn": ["bar", "tables6", "counter"]},
	"int_shelter": {"w": 12, "d": 10, "h": 3.4, "floor": "concrete", "wall": "brick_grey", "furn": ["beds4", "tables2", "stove"]},
	"int_gunsmith": {"w": 8, "d": 7, "h": 2.9, "floor": "wood_planks", "wall": "brick_grey", "furn": ["counter", "shelves3", "workbench"]},
	"int_garage": {"w": 14, "d": 12, "h": 4.5, "floor": "concrete", "wall": "metal_corrugated", "furn": ["workbench", "crates", "carlift"]},
	"int_fightclub": {"w": 14, "d": 12, "h": 5.0, "floor": "concrete", "wall": "metal_corrugated", "furn": ["ring", "crates", "barrels"]},
}


func enter(interior_id: String, poi_id: String) -> void:
	if active:
		return
	var def: Dictionary = ROOM_DEFS.get(interior_id, ROOM_DEFS["int_apartment"])
	var player := _player()
	if player == null:
		return
	return_pos = player.global_position
	return_rot = player.rotation.y
	current_id = interior_id
	current = _build_room(def)
	_scene().add_child(current)
	# place player just inside the door (door at +Z wall)
	player.global_position = current.global_position + Vector3(0, 0, def["d"] * 0.5 - 1.5)
	player.rotation.y = PI
	active = true
	Bus.district_changed.emit("interior")
	AudioDirector.ambient("interior", "res://assets/audio/sfx/crowd_loop.wav", 0.08)


func exit() -> void:
	if not active:
		return
	var player := _player()
	if player and current:
		player.global_position = return_pos
		player.rotation.y = return_rot
	if current:
		current.queue_free()
	current = null
	active = false
	AudioDirector.ambient_off("interior")
	Bus.district_changed.emit(WorldGen.district_at(return_pos))


func _player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


func _build_room(def: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "interior"
	var w: float = def["w"]
	var d: float = def["d"]
	var h: float = def["h"]
	# shell (inverted box via 6 quads facing inward)
	var shell := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w * 0.5
	var hd := d * 0.5
	# floor
	_quad(st, Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd), Vector3.UP, def["floor"])
	# ceiling
	_quad(st, Vector3(-hw, h, hd), Vector3(hw, h, hd), Vector3(hw, h, -hd), Vector3(-hw, h, -hd), Vector3.DOWN, def["wall"])
	# walls
	_quad(st, Vector3(-hw, 0, hd), Vector3(hw, 0, hd), Vector3(hw, h, hd), Vector3(-hw, h, hd), Vector3(0, 0, -1), def["wall"])
	_quad(st, Vector3(hw, 0, -hd), Vector3(-hw, 0, -hd), Vector3(-hw, h, -hd), Vector3(hw, h, -hd), Vector3(0, 0, 1), def["wall"])
	_quad(st, Vector3(hw, 0, hd), Vector3(hw, 0, -hd), Vector3(hw, h, -hd), Vector3(hw, h, hd), Vector3(-1, 0, 0), def["wall"])
	_quad(st, Vector3(-hw, 0, -hd), Vector3(-hw, 0, hd), Vector3(-hw, h, hd), Vector3(-hw, h, -hd), Vector3(1, 0, 0), def["wall"])
	st.generate_normals()
	shell.mesh = st.commit()
	var mm := StandardMaterial3D.new()
	mm.albedo_texture = load("res://assets/textures/world/%s.png" % def["wall"])
	mm.cull_mode = BaseMaterial3D.CULL_FRONT
	shell.material_override = mm
	node.add_child(shell)
	# collision shell
	var sb := StaticBody3D.new()
	for face in [Vector3(0, 1, 0), Vector3(0, -1, 0)]:
		pass
	var box := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 0.2, d)
	cs.shape = bs
	cs.position = Vector3(0, -0.1, 0)
	box.add_child(cs)
	node.add_child(box)
	for wv in [Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var wb := StaticBody3D.new()
		var wc := CollisionShape3D.new()
		var wbs := BoxShape3D.new()
		wbs.size = Vector3(0.2, h, d)
		wc.shape = wbs
		wc.position = Vector3(wv.x * hw, h * 0.5, 0)
		wb.add_child(wc)
		node.add_child(wb)
	for wv in [Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var wb := StaticBody3D.new()
		var wc := CollisionShape3D.new()
		var wbs := BoxShape3D.new()
		wbs.size = Vector3(w, h, 0.2)
		wc.shape = wbs
		wc.position = Vector3(0, h * 0.5, wv.z * hd)
		wb.add_child(wc)
		node.add_child(wb)
	# lights
	var l1 := OmniLight3D.new()
	l1.light_energy = 1.4
	l1.light_color = Color(1.0, 0.85, 0.65)
	l1.omni_range = maxf(w, d) * 0.7
	l1.position = Vector3(0, h - 0.4, 0)
	node.add_child(l1)
	# furniture
	for f in def["furn"]:
		_furniture(node, f, w, d, h)
	# exit door marker
	var door := Area3D.new()
	door.position = Vector3(0, 1.1, hd - 0.3)
	door.add_to_group("interact")
	door.set("interact_label", "Leave")
	door.set_script(load("res://scripts/world/exit_door.gd"))
	node.add_child(door)
	return node


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, dd: Vector3, n: Vector3, _mat: String) -> void:
	st.set_normal(n)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_uv(Vector2(2, 0))
	st.add_vertex(b)
	st.set_uv(Vector2(2, 2))
	st.add_vertex(c)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_uv(Vector2(2, 2))
	st.add_vertex(c)
	st.set_uv(Vector2(0, 2))
	st.add_vertex(dd)


func _box_at(node: Node3D, pos: Vector3, size: Vector3, mat_key: String) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	var m := StandardMaterial3D.new()
	var t := load("res://assets/textures/world/%s.png" % mat_key) if ResourceLoader.exists("res://assets/textures/world/%s.png" % mat_key) else null
	if t:
		m.albedo_texture = t
	else:
		m.albedo_color = Color(mat_key) if mat_key.begins_with("#") else Color(0.4, 0.35, 0.3)
	mi.material_override = m
	node.add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.position = mi.position
	sb.add_child(cs)
	node.add_child(sb)


func _furniture(node: Node3D, kind: String, w: float, d: float, h: float) -> void:
	var hw := w * 0.5
	var hd := d * 0.5
	match kind:
		"counter":
			_box_at(node, Vector3(0, 0, -hd + 1.2), Vector3(w * 0.6, 1.05, 0.7), "wood_planks")
		"bar":
			_box_at(node, Vector3(-hw + 1.5, 0, 0), Vector3(0.8, 1.1, d * 0.6), "wood_planks")
		"desk":
			_box_at(node, Vector3(0, 0, -hd + 1.5), Vector3(1.8, 0.75, 0.9), "wood_planks")
		"desks3":
			for i in 3:
				_box_at(node, Vector3(-3 + i * 3, 0, -hd + 2 + (i % 2)), Vector3(1.8, 0.75, 0.9), "wood_planks")
		"table":
			_box_at(node, Vector3(0, 0, 0), Vector3(1.4, 0.72, 0.9), "wood_planks")
		"tables2":
			for i in 2:
				_box_at(node, Vector3(-2 + i * 4, 0, 0), Vector3(1.4, 0.72, 0.9), "wood_planks")
		"tables4":
			for i in 4:
				_box_at(node, Vector3(-3 + (i % 2) * 6, 0, -2 + (i / 2) * 4), Vector3(1.2, 0.72, 1.2), "wood_planks")
		"tables6":
			for i in 6:
				_box_at(node, Vector3(-4 + (i % 3) * 4, 0, -3 + (i / 3) * 5), Vector3(1.2, 0.72, 1.2), "wood_planks")
		"sofa":
			_box_at(node, Vector3(-hw + 1.2, 0, 1), Vector3(0.9, 0.8, 2.2), "carpet")
		"bed":
			_box_at(node, Vector3(hw - 1.2, 0, -hd + 1.4), Vector3(2.0, 0.5, 1.4), "carpet")
		"beds4":
			for i in 4:
				_box_at(node, Vector3(-hw + 1.4, 0, -hd + 2 + i * 2.4), Vector3(1.9, 0.45, 0.9), "carpet")
		"shelf", "shelves3":
			var n := 1 if kind == "shelf" else 3
			for i in n:
				_box_at(node, Vector3(hw - 0.5, 0, -hd + 1.5 + i * 2.4), Vector3(0.5, 2.0, 1.8), "wood_planks")
		"kitchen":
			_box_at(node, Vector3(hw - 1.0, 0, hd - 1.0), Vector3(1.6, 0.9, 0.7), "metal_panel")
		"stove":
			_box_at(node, Vector3(hw - 1.0, 0, -hd + 1.0), Vector3(1.2, 1.0, 0.8), "metal_panel")
		"workbench":
			_box_at(node, Vector3(-hw + 1.2, 0, 0), Vector3(0.8, 0.95, 3.0), "wood_planks")
		"crates":
			for i in 4:
				_box_at(node, Vector3(randf_range(-hw + 1, hw - 1), 0, randf_range(-hd + 1, hd - 1)), Vector3(1.0, 1.0, 1.0), "wood_planks")
		"crates_many":
			for i in 10:
				_box_at(node, Vector3(randf_range(-hw + 1, hw - 1), 0, randf_range(-hd + 1, hd - 1)), Vector3(1.1, 1.1, 1.1), "wood_planks")
		"containers2":
			for i in 2:
				_box_at(node, Vector3(randf_range(-hw + 3, hw - 3), 0, randf_range(-hd + 2, hd - 2)), Vector3(6.0, 2.6, 2.4), "metal_rusted")
		"barrels":
			for i in 6:
				_box_at(node, Vector3(randf_range(-hw + 1, hw - 1), 0, randf_range(-hd + 1, hd - 1)), Vector3(0.7, 1.0, 0.7), "metal_rusted")
		"pews":
			for i in 5:
				_box_at(node, Vector3(0, 0, -hd + 4 + i * 2.0), Vector3(6.0, 0.9, 0.6), "wood_planks")
		"altar":
			_box_at(node, Vector3(0, 0, -hd + 1.6), Vector3(2.4, 1.1, 1.0), "wood_planks")
		"candles":
			for i in 4:
				_box_at(node, Vector3(-1.5 + i, 0, -hd + 1.2), Vector3(0.1, 0.4, 0.1), "stucco")
		"jukebox":
			_box_at(node, Vector3(hw - 0.8, 0, hd - 1.2), Vector3(0.8, 1.4, 0.7), "metal_rusted")
		"stage":
			_box_at(node, Vector3(0, 0, -hd + 2), Vector3(5.0, 0.6, 3.0), "wood_planks")
		"plants":
			for i in 3:
				_box_at(node, Vector3(-4 + i * 4, 0, hd - 1.0), Vector3(0.6, 1.2, 0.6), "grass")
		"cells":
			_box_at(node, Vector3(hw - 1.5, 0, 0), Vector3(2.0, 2.2, d * 0.5), "metal_panel")
		"chair":
			_box_at(node, Vector3(0, 0, -hd + 2.4), Vector3(0.6, 0.9, 0.6), "wood_planks")
		"ring":
			_box_at(node, Vector3(0, 0, 0), Vector3(6.0, 0.4, 6.0), "carpet")
			for i in 4:
				_box_at(node, Vector3(-3 + (i % 2) * 6, 0, -3 + (i / 2) * 6), Vector3(0.2, 1.2, 0.2), "metal_panel")
		"carlift":
			_box_at(node, Vector3(0, 0, 0), Vector3(4.0, 0.3, 2.2), "metal_panel")


func _scene() -> Node:
	var t := get_tree()
	if t == null:
		t = Engine.get_main_loop() as SceneTree
	return t.current_scene if t != null else null
