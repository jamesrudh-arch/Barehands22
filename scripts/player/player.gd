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
var _seat_offset := Vector3(0, 0.78, -0.1)
var interact_target: Node = null
var _look_delta := Vector2.ZERO
var touch_move := Vector2.ZERO      # virtual stick (HUD touch controls)
var _story_started := false
var dead := false
var height_scale := 1.0
# gunplay: focus (bullet-time) meter + soft cover
var focus := 0.0                    # 0..100 bullet-time meter
var focus_active := false
var in_cover := false               # soft cover: crouched behind geometry
var _cover_prop: Node3D = null

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
	if climbing:
		_climb_tick(delta)
		if _look_delta.length_squared() > 0.0001:
			cam_rig.look(_look_delta.x, _look_delta.y)
		_look_delta = Vector2.ZERO
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
			if _try_climb():
				pass
			elif _try_vault(forward, wish):
				pass
			else:
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
	if vault_t > 0.0:
		_vault_tick(delta)
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


func _env_takedown() -> bool:
	## Environmental takedown: shove a reeling enemy into the wall/prop
	## behind them. Requires stagger + solid geometry within 1.2 m of them.
	var fwd := -global_transform.basis.z
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or n.combat == null or n.combat.dead or n.combat.knocked:
			continue
		if n.combat.stagger < 18.0:
			continue
		var to: Vector3 = n.global_position - global_position
		to.y = 0
		if to.length() > 1.8 or to.normalized().dot(fwd) < 0.35:
			continue
		var q := PhysicsRayQueryParameters3D.new()
		q.from = n.global_position + Vector3(0, 1.0, 0)
		q.to = q.from + to.normalized() * 1.3
		q.exclude = [get_rid(), n.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		# slam!
		var cc: CombatController = n.combat
		cc.take_hit(cc.max_hp * 0.55, to.normalized(), "env_slam", self)
		cc.apply_stagger(60.0, to.normalized())
		AudioDirector.sfx_at("slam", n.global_position + Vector3(0, 1.1, 0))
		AudioDirector.sfx_at("block_hit", n.global_position + Vector3(0, 1.1, 0), 0.7)
		Effects.burst(n.global_position + Vector3(0, 1.2, 0) + to.normalized() * 0.4, "blood", to.normalized())
		Effects.add_shake(0.45)
		Bus.notification.emit("ENVIRONMENTAL TAKEDOWN!", "warn")
		combat.stamina = maxf(0.0, combat.stamina - 10.0)
		Progression.add_style_xp(combat.style_id, 2.0)
		if cc.dead:
			Progression.add_xp(25, "takedown")
		return true
	return false


func _heavy_move() -> String:
	# best heavy the current style has earned; downed enemies invite finishers
	var sid: String = combat.style_id
	var downed := _downed_target_in_reach()
	if downed and Progression.has_move(sid, "ground_pound"):
		return "ground_pound"
	if downed and Progression.has_move(sid, "axe_kick"):
		return "axe_kick"
	if downed:
		return "executioner" if Progression.has_move(sid, "executioner") else "heavy"
	match sid:
		"brawler":
			return "haymaker" if Progression.has_move(sid, "haymaker") else ("swing_v" if melee_weapon_id() != "" else "heavy")
		"grappling":
			return "suplex" if Progression.has_move(sid, "suplex") else "heavy"
		"drunken":
			return "sway_strike" if Progression.has_move(sid, "sway_strike") else "heavy"
		"weapon":
			return "swing_v" if melee_weapon_id() != "" else ("executioner" if Progression.has_move(sid, "executioner") else "heavy")
		_:
			return "swing_v" if melee_weapon_id() != "" else "heavy"


func _kick_move() -> String:
	var sid: String = combat.style_id
	if sid == "kickboxing":
		if Progression.has_move(sid, "axe_kick"):
			return ["kick_r", "kick_high", "axe_kick"][combat.combo_idx % 3]
		if Progression.has_move(sid, "kick_high"):
			return ["kick_r", "kick_high"][combat.combo_idx % 2]
	if sid == "drunken" and Progression.has_move(sid, "flurry"):
		return "flurry"
	return "kick_r" if combat.combo_idx % 2 == 0 else "teep"


func _downed_target_in_reach() -> bool:
	var fwd := -global_transform.basis.z
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or n.combat == null:
			continue
		if n.combat.knocked and not n.combat.dead:
			var to: Vector3 = n.global_position - global_position
			to.y = 0
			if to.length() < 2.0 and to.normalized().dot(fwd) > 0.2:
				return true
	return false


var vault_t: float = 0.0            # >0 while vaulting
var vault_dir := Vector3.ZERO
var vault_height: float = 0.0
# fire-escape climbing
var climb_point: Dictionary = {}
var climbing := false
var climb_t := 0.0
var climb_from := Vector3.ZERO
var climb_to := Vector3.ZERO


func _find_climb_point() -> Dictionary:
	## Nearest fire-escape entry within 2.2 m (bottom or rooftop top).
	var best: Dictionary = {}
	var best_d := 2.2
	for cp in WorldGen.climb_points:
		var db: float = (global_position - cp["bottom"]).length()
		if db < best_d and global_position.y < cp["top"].y - 2.0:
			best_d = db
			best = {"cp": cp, "dir": "up"}
		var dt2: float = (global_position - cp["top"]).length()
		if dt2 < best_d and global_position.y > cp["bottom"].y + 2.0:
			best_d = dt2
			best = {"cp": cp, "dir": "down"}
	return best


func _try_climb() -> bool:
	if dead or in_vehicle or combat.knocked or combat.attacking:
		return false
	var found := _find_climb_point()
	if found.is_empty():
		return false
	if combat.stamina < 15.0:
		Bus.notification.emit("Too winded to climb.", "warn")
		return false
	climb_point = found["cp"]
	climbing = true
	climb_t = 0.0
	climb_from = global_position
	climb_to = climb_point["top"] if found["dir"] == "up" else climb_point["bottom"]
	combat.stamina -= 12.0
	AudioDirector.sfx("cloth_rustle", 0.1)
	return true


func _climb_tick(delta: float) -> void:
	if not climbing:
		return
	var dist := climb_from.distance_to(climb_to)
	var dur := clampf(dist / 3.4, 0.6, 4.0)   # ~3.4 m/s hand-over-hand
	climb_t += delta / dur
	var k := clampf(climb_t, 0.0, 1.0)
	var eased := k * k * (3.0 - 2.0 * k)       # smoothstep
	global_position = climb_from.lerp(climb_to, eased)
	velocity = Vector3.ZERO
	# face the ladder
	var face := (climb_to - climb_from)
	face.y = 0
	if face.length_squared() > 0.01:
		rotation.y = atan2(face.x, face.z)
	anim.mode = "locomote"
	anim.speed = 2.2
	anim.speed01 = 0.5
	anim.air_t = 0.0
	if climb_t >= 1.0:
		climbing = false
		AudioDirector.sfx("land_thud", 0.1)
		if climb_to.y > 4.0:
			Bus.notification.emit("ROOFTOP — the city sprawls below.", "info")
		Bus.tutorial_hint.emit("climb")


func _try_vault(forward: Vector3, wish: Vector3) -> bool:
	## Parkour-lite vault: knee-to-chest-high ledges in front of you while
	## moving get flowed over instead of stopping you. Probes a waist ray
	## (must hit) and a head ray (must be clear).
	if dead or in_vehicle or combat.knocked or not is_on_floor():
		return false
	var dir := wish if wish.length_squared() > 0.01 else forward
	dir = dir.normalized()
	dir.y = 0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.from = global_position + Vector3(0, 0.95, 0)
	q.to = q.from + dir * 1.35
	q.exclude = [get_rid()]
	var low := space.intersect_ray(q)
	if low.is_empty():
		return false                      # nothing to vault
	var q2 := PhysicsRayQueryParameters3D.new()
	q2.from = global_position + Vector3(0, 1.75, 0)
	q2.to = q2.from + dir * 1.35
	q2.exclude = [get_rid()]
	var high := space.intersect_ray(q2)
	if not high.is_empty():
		return false                      # too tall — wall, not a ledge
	# ground check beyond the ledge
	var q3 := PhysicsRayQueryParameters3D.new()
	q3.from = global_position + Vector3(0, 1.6, 0) + dir * 1.5
	q3.to = q3.from + Vector3(0, -2.6, 0)
	q3.exclude = [get_rid()]
	var ground := space.intersect_ray(q3)
	if ground.is_empty():
		return false
	vault_t = 0.42
	vault_dir = dir
	vault_height = clampf(global_position.y - float(ground["position"].y) - 0.9, 0.0, 1.2)
	anim.mode = "locomote"
	AudioDirector.sfx("cloth_rustle", 0.1)
	combat.stamina = maxf(0.0, combat.stamina - 6.0)
	return true


func _vault_tick(delta: float) -> void:
	if vault_t <= 0.0:
		return
	vault_t -= delta
	velocity = vault_dir * 7.2
	velocity.y = 2.2 if vault_t > 0.2 else -3.0
	anim.air_t = 0.12
	if vault_t <= 0.0:
		AudioDirector.sfx("land_thud", 0.08)


func _tick_focus(delta: float) -> void:
	## Max Payne-style focus: while aiming, hold FOCUS to slow the world.
	var want := Input.is_action_pressed("focus") and weapons.aim and focus > 2.0 and not dead
	if want != focus_active:
		focus_active = want
		AudioDirector.sfx("focus_on" if want else "focus_off", 0.1)
		if want:
			Bus.tutorial_hint.emit("focus")
	if focus_active:
		focus = maxf(0.0, focus - delta * 22.0)
		Engine.time_scale = 0.35
		if not _focus_ducked:
			_focus_ducked = true
			var mi: int = AudioServer.get_bus_index("Master")
			_focus_prev_db = AudioServer.get_bus_volume_db(mi)
			AudioServer.set_bus_volume_db(mi, _focus_prev_db - 7.0)
		if focus <= 0.0:
			focus_active = false
			Engine.time_scale = 1.0
			_restore_audio()
	else:
		focus = minf(100.0, focus + delta * (7.0 if weapons.aim else 4.5))
		if Engine.time_scale != 1.0:
			Engine.time_scale = 1.0
			_restore_audio()


var _focus_ducked := false
var _focus_prev_db := 0.0


func _restore_audio() -> void:
	if _focus_ducked:
		_focus_ducked = false
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), _focus_prev_db)


func _tick_cover() -> void:
	## Soft cover: crouching with something solid in front = damage break +
	## blindfire lane. No sticky cover states — the city is the cover.
	var was := in_cover
	in_cover = false
	_cover_prop = null
	if crouch_held and not dead and not in_vehicle:
		var fwd := -global_transform.basis.z
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.new()
		q.from = global_position + Vector3(0, 0.55, 0)
		q.to = q.from + fwd * 1.15
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.has("collider"):
			in_cover = true
			var c = hit["collider"]
			if c is Node3D:
				_cover_prop = c
	if in_cover and not was:
		Bus.tutorial_hint.emit("cover")
		Bus.notification.emit("IN COVER — fire blind or slip away", "info")


func _try_stealth_takedown() -> bool:
	var fwd := -global_transform.basis.z
	var best: Node = null
	var best_dot := 0.62
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or n.combat == null or n.combat.dead:
			continue
		if not (n.state in [n.State.ROUTINE, n.State.IDLE_ACT, n.State.TALK, n.State.GAWK, n.State.GUARD]):
			continue  # already alerted — no free kills
		var to: Vector3 = n.global_position - global_position
		to.y = 0
		if to.length() > 1.9:
			continue
		# behind them: our approach opposite to their facing
		var nfwd: Vector3 = -n.global_transform.basis.z
		if nfwd.normalized().dot(to.normalized()) < best_dot:
			continue
		best = n
		best_dot = nfwd.normalized().dot(to.normalized())
	if best == null:
		return false
	var cc: CombatController = best.combat
	cc.take_hit(cc.max_hp * 1.6, fwd * 0.5, "stealth_kill", self)
	AudioDirector.sfx_at("takedown", best.global_position + Vector3(0, 1.3, 0))
	Effects.burst(best.global_position + Vector3(0, 1.2, 0), "blood", fwd)
	Effects.add_shake(0.3)
	focus = minf(100.0, focus + 14.0)
	Bus.notification.emit("SILENT TAKEDOWN", "info")
	Bus.tutorial_hint.emit("stealth")
	Progression.add_style_xp(combat.style_id, 2.5)
	if cc.dead:
		Progression.add_xp(20, "takedown")
	return true


func _handle_combat_input(delta: float) -> void:
	_tick_focus(delta)
	_tick_cover()
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
			if not _env_takedown():
				combat.request_attack(_heavy_move())
		if Input.is_action_just_pressed("kick"):
			combat.request_attack(_kick_move())
	if Input.is_action_just_pressed("dodge"):
		# stealth takedown first: crouched behind an unaware target
		if crouch_held and _try_stealth_takedown():
			return
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
	var before: int = weapons.mag
	weapons.try_fire(true, delta, muz, dir, true)
	if weapons.mag < before and cam_rig:
		# felt recoil: camera climbs along the weapon's pattern
		var scale_r: float = 0.55 if weapons.aim else 1.0
		cam_rig.pitch = clampf(cam_rig.pitch + weapons._pattern_pitch * scale_r * 0.35, cam_rig.PITCH_MIN, cam_rig.PITCH_MAX)
		cam_rig.yaw += weapons._pattern_yaw * scale_r * 0.3


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
	# body hiding takes priority — the clock is always ticking on a corpse
	var body := _find_body()
	if body != null:
		Bus.interaction_available.emit("Hide body")
		if Input.is_action_just_pressed("interact") and not combat.in_combat:
			body.hide_body()
		return
	interact_target = _find_interact()
	if interact_target:
		Bus.interaction_available.emit(str(interact_target.get("interact_label")) if interact_target.get("interact_label") != null else "Interact")
		if Input.is_action_just_pressed("interact") and not combat.in_combat:
			interact_target.interact(self)
	else:
		Bus.interaction_cleared.emit()


func _find_body() -> Node:
	var best: Node = null
	var bd := 1.8
	for n in get_tree().get_nodes_in_group("corpse"):
		if not is_instance_valid(n) or not n.has_method("hide_body"):
			continue
		var d: float = (n.global_position - global_position).length()
		if d < bd:
			bd = d
			best = n
	return best
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
	# bikes: the rider stays visible in a riding posture; cars: hidden inside
	visible = v.vehicle_type == "bike"
	if visible:
		var seat: Vector3 = v.get_meta("seat_offset", Vector3(0, 0.78, -0.1))
		_seat_offset = seat
		anim.mode = "ride"
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
	top_level = false
	visible = true
	anim.mode = "locomote"
	anim.steer = 0.0
	anim.veh_speed01 = 0.0
	anim.veh_lean = 0.0
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
	# rider posture on bikes: sit on the seat, lean with the machine
	if visible:
		var vb: Basis = in_vehicle.global_transform.basis
		top_level = true
		global_transform = Transform3D(vb, in_vehicle.global_position + vb * _seat_offset)
		var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		anim.steer = mv.x
		anim.veh_speed01 = clampf(in_vehicle.speed_kmh() / 90.0, 0.0, 1.0)
		anim.veh_lean = clampf(-in_vehicle.steer_angle() if in_vehicle.has_method("steer_angle") else mv.x, -1.0, 1.0)
		anim.speed = 0.0
		anim.tick(delta, {})
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
	if d != "" and d != "interior" and not (d in WorldState.visited_districts):
		WorldState.visited_districts.append(d)
		Bus.notification.emit("Discovered: %s" % Db.district(d).get("name", d), "info")


# ------------------------------------------------------------------ story --
func start_story_intro() -> void:
	if _story_started:
		return
	_story_started = true
	# opening cinematic -> then hand over to the prologue mission
	Cutscene.play("cs_intro", func():
		if Game.mission_manager:
			Game.mission_manager.begin_prologue())


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
