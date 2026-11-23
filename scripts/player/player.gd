extends CharacterBody3D
## Player — Elias "Eli" Vane. Third-person controller: weighted but responsive
## movement, combat disciplines, firearms, interactions, vehicles, save hooks.

const GRAVITY := 19.0
const WALK := 2.3
const RUN := 4.4
const SPRINT := 6.4
const CROUCH_SPD := 1.4
const ACCEL := 26.0
const FRICTION := 20.0

var anim: AnimDriver
var combat: CombatController
var weapons: WeaponsController
var cam_rig: Node = null
var skeleton: Skeleton3D
var mesh_inst: MeshInstance3D

var crouch_held := false
var sprint_held := false
var lock_target: Node3D = null
var in_vehicle: Node = null
var interact_target: Node = null
var _look_delta := Vector2.ZERO
var touch_move := Vector2.ZERO      # virtual stick (HUD touch controls)
var _story_started := false
var dead := false
var height_scale := 1.0

signal entered_vehicle(v)
signal exited_vehicle()


func _ready() -> void:
	add_to_group("player")
	add_to_group("humanoid")
	# body
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	# humanoid
	var ch := Db.character("eli")
	var app: Dictionary = ch.get("appearance", {})
	var outfit: Dictionary = Db.outfits.get(WorldState.equipped_outfit, {}).get("colors", {})
	var params := {
		"height": app.get("height", 1.83), "build": app.get("build", 0.55),
		"skin": app.get("skin", 2), "hair": app.get("hair", "crop"),
		"hair_color": app.get("hair_color", 0), "face": app.get("face", 4),
		"outfit_colors": outfit,
	}
	var hum := Humanoid.build(params)
	add_child(hum)
	skeleton = hum.get_node("Skeleton3D") as Skeleton3D
	mesh_inst = skeleton.get_child(0) as MeshInstance3D
	height_scale = app.get("height", 1.83) / 1.8
	set_meta("height_scale", height_scale)
	set_meta("fem", false)
	anim = AnimDriver.new()
	anim.attach(skeleton)
	combat = CombatController.new()
	combat.setup(self, anim, skeleton, true)
	combat.hostile_to = func(t: Node3D): return t.is_in_group("enemy") or (t.is_in_group("humanoid") and t.get_meta("hostile", false))
	set("combat", combat)
	weapons = WeaponsController.new()
	weapons.setup(self, anim)
	# camera
	var cr: Node3D = load("res://scripts/player/camera_rig.gd").new()
	cam_rig = cr
	get_parent().add_child(cr)
	cr.target = self
	# restore weapons from worldstate
	for wid in WorldState.owned_weapons:
		weapons.give(wid, false)
		weapons.reserves[wid] = WorldState.inventory.get("ammo_" + wid.replace("gun_", ""), 0)
	if WorldState.equipped_weapon != "":
		weapons.equip(WorldState.equipped_weapon)
	combat.set_style(WorldState.current_style)
	combat.armor_prot = Db.armor.get(WorldState.equipped_armor, {}).get("protection", 0.0)
	combat.speed_mod = Db.armor.get(WorldState.equipped_armor, {}).get("speed_mod", 1.0)
	combat.died.connect(_on_died)
	Bus.combat_style_changed.emit(WorldState.current_style)


func _exit_tree() -> void:
	if cam_rig and is_instance_valid(cam_rig):
		cam_rig.queue_free()


# ------------------------------------------------------------------ input --
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and Game.state == Game.State.PLAYING:
		_look_delta += Vector2(ev.relative.x, ev.relative.y) * 0.05
	if ev is InputEventJoypadMotion and (ev.axis == 2 or ev.axis == 3):
		if ev.axis == 2:
			_look_delta.x += ev.axis_value * 0.9
		elif ev.axis == 3:
			_look_delta.y += ev.axis_value * 0.9
	# touch look is injected by TouchControls via look_input()


func look_input(d: Vector2) -> void:
	_look_delta += d


func current_speed() -> float:
	return velocity.length()


func get_velocity_look() -> Vector3:
	var v := velocity * 0.12
	v.y = 0
	return v


func melee_weapon_id() -> String:
	if weapons.weapon_id != "" and Db.weapon(weapons.weapon_id).get("kind", "") == "melee":
		return weapons.weapon_id
	return ""


# ------------------------------------------------------------------- tick --
func _physics_process(delta: float) -> void:
	if Game.state == Game.State.PAUSED or Game.cutscene_active:
		return
	if in_vehicle:
		_in_vehicle_tick(delta)
		return
	if dead:
		return
	# camera look
	if _look_delta.length_squared() > 0.0001:
		cam_rig.look(_look_delta.x, _look_delta.y)
		_look_delta = Vector2.ZERO
	# movement input (touch stick overrides when active)
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length_squared() > 0.001:
		mv = touch_move
	sprint_held = Input.is_action_pressed("sprint") and mv.y > 0.1
	crouch_held = Input.is_action_pressed("crouch")
	var cam_yaw: float = cam_rig.yaw
	var forward := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var right := Vector3(sin(cam_yaw + PI / 2.0), 0, cos(cam_yaw + PI / 2.0))
	var wish := (forward * -mv.y + right * mv.x)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var spd: float = RUN if mv.length() > 0.6 else WALK
	if sprint_held and combat.stamina > 5.0:
		spd = SPRINT
		combat.stamina = maxf(0.0, combat.stamina - delta * 12.0)
	if crouch_held:
		spd = CROUCH_SPD
	spd *= combat.speed_mod
	if combat.knocked:
		spd = 0.0
	if combat.attacking:
		spd *= 0.25
	# dodge impulse
	var dodge_imp := combat.tick(delta, wish)
	# accel / friction
	var target_v := wish * spd + dodge_imp
	velocity.x = move_toward(velocity.x, target_v.x, ACCEL * delta * (1.0 if wish.length() > 0.1 else FRICTION / ACCEL))
	velocity.z = move_toward(velocity.z, target_v.z, ACCEL * delta * (1.0 if wish.length() > 0.1 else FRICTION / ACCEL))
	# gravity / jump
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		anim.air_t += delta
	else:
		if anim.air_t > 0.25:
			anim.land_t = 1.0
			AudioDirector.sfx("land_thud", 0.1)
		anim.air_t = 0.0
		if Input.is_action_just_pressed("jump") and not combat.knocked:
			velocity.y = 5.6
			AudioDirector.sfx("jump_effort", 0.08)
	if anim.land_t > 0.0:
		anim.land_t -= delta * 4.0
	# facing: toward move dir, or lock target, or aim dir
	var face_dir := Vector3.ZERO
	if lock_target and is_instance_valid(lock_target):
		face_dir = (lock_target.global_position - global_position)
	elif weapons.aim or weapons.weapon_id != "" and Input.is_action_pressed("aim"):
		face_dir = forward * -1.0
	elif wish.length_squared() > 0.01:
		face_dir = wish
	if face_dir.length_squared() > 0.01:
		face_dir.y = 0
		var target_angle := atan2(face_dir.x, face_dir.z)
		var cur_angle := rotation.y
		var diff := wrapf(target_angle - cur_angle, -PI, PI)
		rotation.y = cur_angle + diff * minf(1.0, delta * 14.0)
	move_and_slide()
	# footstep audio by surface + distance
	_step_tick(delta)
	# combat inputs
	_handle_combat_input(delta)
	# interaction
	_handle_interact(delta)
	# animation state push
	_push_anim(delta, mv, spd)
	# district tracking + stats
	_track_district()
	if velocity.length() > 0.5:
		WorldState.stats["on_foot_km"] += velocity.length() * delta / 1000.0


var _step_dist := 0.0


func _step_tick(delta: float) -> void:
	var sp := Vector2(velocity.x, velocity.z).length()
	_step_dist += sp * delta
	var stride := lerpf(0.78, 1.35, clampf(sp / 6.0, 0, 1))
	if _step_dist >= stride and is_on_floor() and sp > 0.6:
		_step_dist = 0.0
		var surf := "asphalt"
		if WorldState.wetness > 0.5 and randf() < 0.3:
			surf = "water"
		AudioDirector.sfx("foot_%s_%s_%d" % [surf, "run" if sp > RUN else "walk", randi() % 3], 0.06, 0.5)


func _handle_combat_input(delta: float) -> void:
	weapons.tick(delta)
	# lock-on toggle
	if Input.is_action_just_pressed("lock_on"):
		_cycle_lock()
	# style switch
	if Input.is_action_just_pressed("style_next"):
		_cycle_style(1)
	# weapon cycle
	if Input.is_action_just_pressed("weapon_next"):
		weapons.cycle(1)
	if Input.is_action_just_pressed("weapon_prev"):
		weapons.cycle(-1)
	# attacks (X punch, Y heavy, A kick, B dodge) — context: combat
	var want_attack := combat.in_combat or lock_target != null or _near_hostile()
	if want_attack:
		if Input.is_action_just_pressed("punch"):
			var kind: String = ["jab", "cross", "hook"][combat.combo_idx % 3]
			if melee_weapon_id() != "":
				kind = ["swing_h", "stab", "swing_h"][combat.combo_idx % 3]
			combat.request_attack(kind)
		if Input.is_action_just_pressed("heavy_attack"):
			combat.request_attack("heavy" if melee_weapon_id() == "" else "swing_v")
		if Input.is_action_just_pressed("kick"):
			combat.request_attack("kick_r" if combat.combo_idx % 2 == 0 else "teep")
	if Input.is_action_just_pressed("dodge"):
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var fwd := -global_transform.basis.z
		var rgt := global_transform.basis.x
		var d := (fwd * -mv.y + rgt * mv.x)
		if d.length_squared() < 0.01:
			d = -fwd
		combat.start_dodge(d)
	combat.set_block(Input.is_action_pressed("block") and weapons.weapon_id == "")
	# firearms
	weapons.aim = Input.is_action_pressed("aim") and weapons.is_gun()
	anim.aiming = weapons.aim or (weapons.weapon_id != "" and Input.is_action_pressed("aim"))
	if weapons.is_gun():
		if Input.is_action_pressed("fire"):
			_try_shoot(delta)
		if Input.is_action_just_pressed("reload"):
			weapons.start_reload()
	elif Input.is_action_just_pressed("reload"):
		pass


func _try_shoot(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	if lock_target and is_instance_valid(lock_target):
		dir = (lock_target.global_position + Vector3(0, 1.2, 0) - from).normalized()
	# recoil pitch kick
	dir = dir.rotated(cam.global_transform.basis.x, deg_to_rad(weapons.recoil * 0.35))
	var muz: Vector3 = global_position + global_transform.basis * MUZZLE_POS
	weapons.try_fire(true, delta, muz, dir, true)


const MUZZLE_POS := Vector3(0.15, 1.42, 0.5)


func _cycle_lock() -> void:
	var candidates := []
	for n in get_tree().get_nodes_in_group("humanoid"):
		if n == self or not n.get_meta("hostile", false):
			continue
		var d: float = (n.global_position - global_position).length()
		if d < 25.0:
			candidates.append([d, n])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	if lock_target and candidates.size() > 1:
		var idx := -1
		for i in candidates.size():
			if candidates[i][1] == lock_target:
				idx = i
		lock_target = candidates[(idx + 1) % candidates.size()][1]
	elif candidates.size():
		lock_target = candidates[0][1]
	else:
		lock_target = null
	cam_rig.set_lock(lock_target)


func _cycle_style(d: int) -> void:
	var order := ["brawler", "kickboxing", "grappling", "drunken", "weapon"]
	var cur := order.find(WorldState.current_style)
	cur = (cur + d + order.size()) % order.size()
	WorldState.current_style = order[cur]
	combat.set_style(order[cur])
	Bus.combat_style_changed.emit(order[cur])
	Bus.notification.emit("Style: %s" % Db.style(order[cur]).get("label", order[cur]), "info")


func _near_hostile() -> bool:
	for n in get_tree().get_nodes_in_group("humanoid"):
		if n == self:
			continue
		if n.get_meta("hostile", false) and (n.global_position - global_position).length() < 4.0:
			return true
	return false


# ------------------------------------------------------------- interaction --
func _handle_interact(delta: float) -> void:
	interact_target = _find_interact()
	if interact_target:
		Bus.interaction_available.emit(str(interact_target.get("interact_label")) if interact_target.get("interact_label") != null else "Interact")
		if Input.is_action_just_pressed("interact") and not combat.in_combat:
			interact_target.interact(self)
	else:
		Bus.interaction_cleared.emit()
	# vehicle enter
	if Input.is_action_just_pressed("vehicle_enter"):
		var v := _find_vehicle()
		if v and not in_vehicle:
			enter_vehicle(v)


func _find_interact() -> Node:
	var best: Node = null
	var bd := 2.6
	for n in get_tree().get_nodes_in_group("interact"):
		var d: float = (n.global_position - global_position).length()
		if d < bd:
			bd = d
			best = n
	return best


func _find_vehicle() -> Node:
	var best: Node = null
	var bd := 3.2
	for n in get_tree().get_nodes_in_group("vehicle"):
		var d: float = (n.global_position - global_position).length()
		if d < bd:
			bd = d
			best = n
	return best


func enter_vehicle(v: Node) -> void:
	in_vehicle = v
	visible = false
	set_physics_process(true)
	v.player_enter(self)
	Bus.vehicle_entered.emit(v.vehicle_type)
	AudioDirector.sfx("veh_door_open")
	entered_vehicle.emit(v)


func exit_vehicle() -> void:
	if not in_vehicle:
		return
	var v := in_vehicle
	in_vehicle = null
	visible = true
	v.player_exit()
	# place beside
	global_position = v.global_position + v.global_transform.basis.x * 1.6 + Vector3(0, 0.2, 0)
	Bus.vehicle_exited.emit()
	AudioDirector.sfx("veh_door_close")
	exited_vehicle.emit()


func _in_vehicle_tick(delta: float) -> void:
	if _look_delta.length_squared() > 0.0001:
		cam_rig.look(_look_delta.x * 0.6, _look_delta.y * 0.6)
		_look_delta = Vector2.ZERO
	if Input.is_action_just_pressed("vehicle_enter"):
		exit_vehicle()
		return
	in_vehicle.player_drive(delta, Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
		Input.is_action_pressed("vehicle_brake"), Input.is_action_pressed("vehicle_handbrake"),
		Input.is_action_just_pressed("horn"))
	# camera follows vehicle
	cam_rig.target = in_vehicle
	WorldState.stats["driven_km"] += in_vehicle.speed_kmh() * delta / 3600.0


# ------------------------------------------------------------------- anim --
func _push_anim(delta: float, mv: Vector2, spd: float) -> void:
	anim.speed = Vector2(velocity.x, velocity.z).length()
	anim.speed01 = clampf((anim.speed - WALK) / (SPRINT - WALK), 0.0, 1.0) if anim.speed > WALK else 0.0
	anim.sprint = sprint_held and anim.speed > RUN
	anim.crouch = crouch_held
	anim.strafe = mv.x
	if not combat.attacking:
		anim.mode = "locomote"
	anim.block = combat.blocking
	if anim.hit_t >= 0:
		anim.hit_t += delta * 4.0
		if anim.hit_t > 1.0:
			anim.hit_t = -1.0
	anim.tick(delta, combat.style.get("stance", {}))


func _track_district() -> void:
	var d: String = WorldGen.district_at(global_position)
	if d != Game.current_district:
		Game.current_district = d
		Bus.district_changed.emit(d)


# ------------------------------------------------------------------ story --
func start_story_intro() -> void:
	if _story_started:
		return
	_story_started = true
	if Game.mission_manager:
		Game.mission_manager.begin_prologue()


func on_combat_end() -> void:
	lock_target = null
	cam_rig.set_lock(null)


func _on_died(_cause: String) -> void:
	dead = true
	Bus.player_died.emit(_cause)


func save_state() -> Dictionary:
	return {
		"pos": [global_position.x, global_position.y, global_position.z],
		"rot": rotation.y,
		"hp": combat.hp, "stamina": combat.stamina,
		"weapon": weapons.weapon_id,
		"owned": weapons.owned.duplicate(),
		"reserves": weapons.reserves.duplicate(),
	}


func apply_save(d: Dictionary) -> void:
	global_position = Vector3(d["pos"][0], d["pos"][1], d["pos"][2])
	rotation.y = d.get("rot", 0.0)
	combat.hp = d.get("hp", 100.0)
	combat.stamina = d.get("stamina", 100.0)
	weapons.owned = d.get("owned", [])
	weapons.reserves = d.get("reserves", {})
	if d.get("weapon", "") != "":
		weapons.equip(d["weapon"])


func rebuild_appearance() -> void:
	# rebuild the humanoid with the currently equipped outfit, preserving vitals
	var hp := combat.hp
	var stam := combat.stamina
	var style := combat.style_id
	var old := get_node_or_null("Humanoid")
	if old:
		old.queue_free()
	var ch := Db.character("eli")
	var app: Dictionary = ch.get("appearance", {})
	var outfit: Dictionary = Db.outfits.get(WorldState.equipped_outfit, {}).get("colors", {})
	var hum := Humanoid.build({
		"height": app.get("height", 1.83), "build": app.get("build", 0.55),
		"skin": app.get("skin", 2), "hair": app.get("hair", "crop"),
		"hair_color": app.get("hair_color", 0), "face": app.get("face", 4),
		"outfit_colors": outfit,
	})
	add_child(hum)
	skeleton = hum.get_node("Skeleton3D") as Skeleton3D
	mesh_inst = skeleton.get_child(0) as MeshInstance3D
	anim.attach(skeleton)
	combat.skeleton = skeleton
	combat.hp = hp
	combat.stamina = stam
	combat.set_style(style)


func give_weapon(wid: String) -> void:
	weapons.give(wid, true)
	weapons.equip(wid)
	WorldState.give_weapon(wid)


func use_item(iid: String) -> void:
	if WorldState.inventory.get(iid, 0) <= 0:
		return
	var it := Db.item(iid)
	match it.get("kind", ""):
		"consumable":
			WorldState.remove_item(iid, 1)
			if it.has("heal"):
				combat.heal(float(it["heal"]))
			if it.has("stamina"):
				combat.stamina = clampf(combat.stamina + float(it["stamina"]), 0.0, combat.max_stamina)
			AudioDirector.sfx("cloth_rustle", 0.2)
			Bus.notification.emit("Used %s." % it.get("name", iid), "info")
		_:
			Bus.notification.emit("Can't use that here.", "warn")
