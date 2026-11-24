extends Node
## Effects — pooled VFX: muzzle flashes, tracers, impact sparks, blood,
## decals (scorch/blood/glass), dust, camera shake bus. Mobile-friendly:
## small particle counts, GPUParticles3D with one-shot emission.

var _tex_cache: Dictionary = {}
var shake_amount: float = 0.0
var shake_decay: float = 3.0
var _shake_cam: Camera3D = null

const POOL := 24


func _ready() -> void:
	for i in POOL:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 14
		p.lifetime = 0.5
		p.visible = false
		add_child(p)


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


func add_shake(amount: float) -> void:
	# honor the SETTINGS > camera shake toggle (motion-sickness friendly)
	if not Game.settings.get("shake", true):
		return
	shake_amount = minf(shake_amount + amount, 1.2)


func register_camera(cam: Camera3D) -> void:
	_shake_cam = cam


func _process(delta: float) -> void:
	if shake_amount > 0.001 and _shake_cam:
		shake_amount = maxf(0.0, shake_amount - delta * shake_decay)
		var a := shake_amount * shake_amount * 0.09
		_shake_cam.h_offset = randf_range(-a, a)
		_shake_cam.v_offset = randf_range(-a, a)
	elif _shake_cam:
		_shake_cam.h_offset = 0.0
		_shake_cam.v_offset = 0.0


func _free_particles() -> GPUParticles3D:
	for c in get_children():
		var p := c as GPUParticles3D
		if p and not p.emitting:
			return p
	return null


func burst(at: Vector3, kind: String, dir: Vector3 = Vector3.UP, scale: float = 1.0) -> void:
	# scale = juice budget multiplier: >1 for heavies/kills (more particles,
	# faster, bigger quads), <1 for trivial pings — proportionality ladder
	var p := _free_particles()
	if p == null:
		return
	var mat := ParticleProcessMaterial.new()
	var ptx: Texture2D = null
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = dir.normalized()
	mat.spread = 35.0
	mat.initial_velocity_min = 1.5 * scale
	mat.initial_velocity_max = 4.5 * scale
	mat.gravity = Vector3(0, -9.8, 0)
	mat.lifetime_randomness = 0.4
	p.global_position = at
	p.visible = true
	match kind:
		"spark":
			ptx = _tex("res://assets/textures/world/particle_spark.png")
			mat.initial_velocity_min = 3.0
			mat.initial_velocity_max = 8.0
			mat.spread = 55.0
			p.amount = 10
			p.lifetime = 0.3
		"blood":
			ptx = _tex("res://assets/textures/world/particle_blood.png")
			mat.initial_velocity_min = 1.0
			mat.initial_velocity_max = 3.0
			p.amount = 8
			p.lifetime = 0.45
		"dust":
			ptx = _tex("res://assets/textures/world/particle_smoke.png")
			mat.initial_velocity_min = 0.4
			mat.initial_velocity_max = 1.4
			mat.spread = 70.0
			p.amount = 8
			p.lifetime = 0.7
		"debris":
			ptx = _tex("res://assets/textures/world/particle_debris.png")
			p.amount = 8
			p.lifetime = 0.6
		"muzzle":
			ptx = _tex("res://assets/textures/world/particle_muzzle.png")
			mat.direction = dir.normalized()
			mat.spread = 12.0
			mat.initial_velocity_min = 0.2
			mat.initial_velocity_max = 0.6
			mat.gravity = Vector3.ZERO
			p.amount = 4
			p.lifetime = 0.09
		"smoke":
			ptx = _tex("res://assets/textures/world/particle_smoke.png")
			mat.initial_velocity_min = 0.6
			mat.initial_velocity_max = 1.6
			mat.gravity = Vector3(0, 1.5, 0)
			p.amount = 10
			p.lifetime = 1.2
	p.amount = int(clampf(p.amount * scale, 4.0, 40.0))
	p.process_material = mat
	# textured billboard quad (ParticleProcessMaterial has no emission_texture)
	var qm := QuadMesh.new()
	var qs := 0.16 * sqrt(scale)
	qm.size = Vector2(qs, qs)
	var qmat := StandardMaterial3D.new()
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.vertex_color_use_as_albedo = true
	if ptx != null:
		qmat.albedo_texture = ptx
	qmat.emission_enabled = true
	qmat.emission = Color(1, 0.85, 0.6)
	qmat.emission_energy_multiplier = 1.6
	qm.material = qmat
	p.draw_pass_1 = qm
	p.emitting = true
	p.restart()
	# auto-hide
	get_tree().create_timer(p.lifetime + 0.1).timeout.connect(func(): p.visible = false)


func tracer(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(to - from)
	im.surface_end()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5, 0.9)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	_scene().add_child(mi)
	mi.global_position = from
	if (to - from).length_squared() > 0.01:
		mi.look_at(from + (to - from).normalized(), Vector3.UP)
	get_tree().create_timer(0.06).timeout.connect(func(): mi.queue_free())


func decal(at: Vector3, normal: Vector3, kind: String, scale: float = 0.6) -> void:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(scale, scale)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("res://assets/textures/world/decal_%s.png" % kind)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if kind == "scorch" else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	get_tree().current_scene.add_child(mi)
	# Orient AFTER entering the tree: look_at() refuses to run on a node
	# outside it, so every decal used to silently keep its default pose.
	# PlaneMesh faces +Y, so we build a basis whose Y axis IS the surface
	# normal (the old code aligned +Z — a 90-degree error on walls).
	var off := at + normal * 0.02
	if normal.length_squared() > 0.01:
		var n := normal.normalized()
		if absf(n.dot(Vector3.UP)) < 0.98:
			var tan := n.cross(Vector3.UP).normalized()
			var bitan := n.cross(tan).normalized()
			mi.global_transform = Transform3D(Basis(tan, n, bitan), off)
		elif n.y < -0.5:
			# ceiling: flip the default floor pose
			mi.global_transform = Transform3D(
				Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), off)
		else:
			mi.global_position = off
	else:
		mi.global_position = off
	# decals fade out after a while to save overdraw
	get_tree().create_timer(25.0).timeout.connect(func(): mi.queue_free())


func _scene() -> Node:
	var t := get_tree()
	if t == null:
		t = Engine.get_main_loop() as SceneTree
	return t.current_scene if t else null


func muzzle_flash_light(at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 6.0
	l.omni_range = 7.0
	_scene().add_child(l)
	l.global_position = at
	get_tree().create_timer(0.07).timeout.connect(func(): l.queue_free())
