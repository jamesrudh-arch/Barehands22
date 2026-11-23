extends CharacterBody3D
## NPC — pedestrian / named character / enemy. Data-driven appearance and
## routine; reactive states (flee, gawk, call police, fight); distance-based
## simulation LOD; memory of the player's deeds via WorldState.

enum State { ROUTINE, IDLE_ACT, TALK, FLEE, GAWK, COMBAT, DOWN, DEAD, GUARD, VENDOR, BUSK }

var char_id: String = ""          # named character id or "" for ped
var ped_id: String = ""
var display_name: String = "Citizen"
var voice: String = "ped_m"
var anim: AnimDriver
var combat: CombatController
var skeleton: Skeleton3D
var state: int = State.ROUTINE
var hostile: bool = false
# --- combat tactics (wave 4) ---
var _tactics_t := 0.0
var _flank_side := 0.0
var _stagger_t := 0.0
var _retreat_t := 0.0
var _call_cd := 8.0
var _backoff_t := 0.0
var faction_tag: String = ""

var _target: Vector3 = Vector3.ZERO
var _wait_t := 0.0
var _routine_i := 0
var _sim_t := 0.0
var _sim_rate := 60.0
var _flee_from: Vector3 = Vector3.ZERO
var _gawk_t := 0.0
var _bark_cd := 0.0
var _talk_partner: Node = null
var _dialogue_id: String = ""
var _weapon_id: String = ""
var _style_id: String = "brawler"
var _attack_cd := 0.0
var _home: Vector3 = Vector3.ZERO
var _district: String = ""
var _dead_t := 0.0

const GRAVITY := 19.0


func setup_ped(pid: String, district: String, pos: Vector3) -> void:
	ped_id = pid
	var d: Dictionary = Db.peds.get(pid, {})
	display_name = d.get("label", "Citizen")
	voice = "ped_m" if randf() < 0.5 else "ped_f"
	_district = district
	_home = pos
	global_position = pos
	var app: Dictionary = d.get("app", {})
	_build_body({
		"height": randf_range(1.62, 1.92), "build": randf_range(0.3, 0.8),
		"skin": app.get("skin", randi() % 8), "hair": app.get("hair", "crop"),
		"hair_color": randi() % 8, "face": randi() % 24,
		"outfit_colors": Db.outfits.get(app.get("outfit", "outfit_default"), {}).get("colors", {}),
		"fem": voice == "ped_f",
	})
	if d.get("routine", "") == "guard":
		state = State.GUARD
	if d.get("routine", "") == "vendor":
		state = State.VENDOR
	if d.get("routine", "") == "busker":
		state = State.BUSK


func setup_named(cid: String) -> void:
	char_id = cid
	var c := Db.character(cid)
	display_name = c.get("short", c.get("name", cid))
	voice = c.get("voice", "ped_m")
	faction_tag = c.get("faction", "")
	var app: Dictionary = c.get("appearance", {})
	var outfit: Dictionary = Db.outfits.get(app.get("outfit", "outfit_default"), {}).get("colors", {})
	_build_body({
		"height": app.get("height", 1.78), "build": app.get("build", 0.5),
		"skin": app.get("skin", 2), "hair": app.get("hair", "crop"),
		"hair_color": app.get("hair_color", 0), "face": app.get("face", 0),
		"outfit_colors": outfit,
		"fem": app.get("height", 1.8) < 1.72 and cid in ["roz", "tess", "vivian", "nia", "ruth"],
	})
	add_to_group("named")
	set_meta("interact_label", "Talk to %s" % display_name)
	add_to_group("interact")


func setup_enemy(kind: String, pos: Vector3, faction: String) -> void:
	hostile = true
	faction_tag = faction
	display_name = kind
	_district = WorldGen.district_at(pos)
	global_position = pos
	# per-archetype silhouette: height/build/wardrobe all differ so reads
	# at a glance tell you WHO you are fighting
	var look := {
		"height": randf_range(1.7, 1.85), "build": randf_range(0.45, 0.65),
		"skin": randi() % 8, "hair": "buzz", "hair_color": randi() % 8, "face": randi() % 24,
		"outfit_colors": {"jacket": [40, 20, 26], "shirt": [26, 24, 26], "pants": [30, 30, 34], "shoes": [20, 20, 22]},
	}
	match kind:
		"thug_light":
			look["outfit_colors"] = {"jacket": [58, 24, 30], "shirt": [70, 66, 60], "pants": [34, 34, 40], "shoes": [22, 22, 24]}
			look["hair"] = ["buzz", "fade", "slick"][randi() % 3]
		"thug_grappler":
			look["build"] = randf_range(0.75, 0.95)
			look["height"] = randf_range(1.78, 1.9)
			look["outfit_colors"] = {"jacket": [30, 34, 30], "shirt": [40, 30, 30], "pants": [26, 26, 30], "shoes": [18, 18, 20]}
			look["hair"] = "buzz"
		"thug_heavy":
			look["build"] = randf_range(0.85, 1.0)
			look["height"] = randf_range(1.85, 1.98)
			look["outfit_colors"] = {"jacket": [46, 38, 28], "shirt": [30, 26, 24], "pants": [32, 30, 28], "shoes": [20, 18, 16]}
			look["hair"] = "cap"
		"crowe_gunman":
			look["outfit_colors"] = {"jacket": [24, 26, 34], "shirt": [64, 62, 66], "pants": [22, 24, 30], "shoes": [16, 16, 18]}
			look["hair"] = "slick"
			look["build"] = randf_range(0.5, 0.7)
		"halcyon_guard":
			look["outfit_colors"] = {"jacket": [26, 30, 34], "shirt": [20, 22, 26], "pants": [24, 26, 30], "shoes": [14, 14, 16]}
			look["height"] = randf_range(1.8, 1.92)
			look["build"] = randf_range(0.6, 0.8)
			look["hair"] = "cap"
		"cop":
			look["outfit_colors"] = {"jacket": [22, 30, 52], "shirt": [70, 72, 80], "pants": [20, 26, 44], "shoes": [12, 12, 14]}
			look["hair"] = "cap"
	_build_body(look)
	set_meta("hostile", true)
	match kind:
		"thug_light":
			_style_id = "brawler"
		"thug_grappler":
			_style_id = "grappling"
		"thug_heavy":
			_style_id = "brawler"
			combat.max_hp = 150
			combat.hp = 150
		"crowe_gunman":
			_weapon_id = "gun_pistol"
			_style_id = "weapon"
		"halcyon_guard":
			_weapon_id = "gun_smg" if randf() < 0.4 else "melee_bat"
			_style_id = "weapon"
			_armor_visual()
			combat.armor_prot = 30.0
		"cop":
			_weapon_id = "gun_pistol"
			_style_id = "weapon"
			combat.armor_prot = 20.0
		_:
			_style_id = ["brawler", "kickboxing", "drunken"][randi() % 3]
	combat.set_style(_style_id)
	state = State.COMBAT
	add_to_group("enemy")


func _armor_visual() -> void:
	# plate vest over the torso: readable armour silhouette
	var sk := get_node_or_null("Humanoid/Skeleton3D")
	if sk == null:
		return
	var chest := sk.find_bone("chest")
	if chest < 0:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.44, 0.5, 0.26)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.15, 0.17)
	m.roughness = 0.6
	m.metallic = 0.15
	mi.material_override = m
	sk.add_child(mi)
	mi.owner = sk.owner
	sk.bind_child_node_to_bone(chest, mi)


func _build_body(params: Dictionary) -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = params.get("height", 1.8) * 0.96
	shape.shape = cap
	shape.position = Vector3(0, params.get("height", 1.8) * 0.48, 0)
	add_child(shape)
	var hum := Humanoid.build(params)
	add_child(hum)
	skeleton = hum.get_node("Skeleton3D") as Skeleton3D
	set_meta("height_scale", params.get("height", 1.8) / 1.8)
	set_meta("fem", params.get("fem", false))
	anim = AnimDriver.new()
	anim.attach(skeleton)
	combat = CombatController.new()
	combat.setup(self, anim, skeleton, false)
	combat.hostile_to = func(t: Node3D):
		if hostile:
			return t.is_in_group("player")
		return false
	set("combat", combat)
	combat.died.connect(_on_died)
	add_to_group("humanoid")


# ------------------------------------------------------------------ tick ---
func _physics_process(delta: float) -> void:
	# distance LOD
	var player := _player()
	var dist := 999.0
	if player:
		dist = (player.global_position - global_position).length()
	_sim_rate = 60.0 if dist < 25.0 else (20.0 if dist < 60.0 else 5.0)
	_sim_t += delta
	if _sim_t < 1.0 / _sim_rate:
		return
	var dt := _sim_t
	_sim_t = 0.0
	if dist > 140.0 and char_id == "":
		# far away: freeze (position simulated by crowd manager on demand)
		return
	_bark_cd -= dt
	match state:
		State.ROUTINE:
			_routine(dt, player, dist)
		State.GUARD:
			_guard(dt, player, dist)
		State.VENDOR:
			anim.mode = "listen"
			anim.tick(dt, {})
			velocity = Vector3.ZERO
		State.BUSK:
			anim.mode = "talk"
			anim.talk_t = maxf(anim.talk_t, 0.0) + dt
			anim.tick(dt, {})
			velocity = Vector3.ZERO
		State.TALK:
			_talk_state(dt)
		State.FLEE:
			_flee(dt, dt)
		State.GAWK:
			_gawk(dt)
		State.COMBAT:
			_combat_state(dt, player)
		State.DOWN:
			pass
		State.DEAD:
			_dead_t += dt
			anim.tick(dt, {})
			velocity = Vector3.ZERO
			return
	# gravity + move
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	else:
		velocity.y = maxf(velocity.y, 0.0)
	move_and_slide()
	combat.tick(dt, Vector3(velocity.x, 0, velocity.z).normalized())
	anim.speed = Vector2(velocity.x, velocity.z).length()
	anim.speed01 = clampf((anim.speed - 1.6) / 3.0, 0.0, 1.0)


func _player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


func _routine(dt: float, player: Node, dist: float) -> void:
	# react to nearby crime/violence
	if player and dist < 18.0:
		if WorldState.wanted > 0 and randf() < 0.01:
			_react_crime(player)
		elif combat.in_combat or (player.combat and player.combat.in_combat):
			if randf() < 0.05:
				_react_crime(player)
	if _wait_t > 0.0:
		_wait_t -= dt
		velocity = Vector3.ZERO
		anim.mode = "listen" if randf() < 0.5 else "locomote"
		anim.tick(dt, {})
		return
	var to := _target - global_position
	to.y = 0
	if to.length() < 1.5:
		_pick_next_routine()
		return
	var dir := to.normalized()
	velocity = Vector3(dir.x * _walk_speed(), 0, dir.z * _walk_speed())
	_face(dir, dt)
	anim.mode = "locomote"
	anim.tick(dt, {})


func _walk_speed() -> float:
	var d: Dictionary = Db.peds.get(ped_id, {})
	return d.get("speed", 1.2)


func _pick_next_routine() -> void:
	var d: Dictionary = Db.peds.get(ped_id, {})
	var routine: String = d.get("routine", "wander")
	match routine:
		"work":
			_target = _home + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
			_wait_t = randf_range(2.0, 6.0)
		"commute":
			_target = _home + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))
		"wander", "tourist":
			_target = _home + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
			_wait_t = randf_range(1.0, 4.0)
		"jog":
			_target = _home + Vector3(randf_range(-50, 50), 0, randf_range(-50, 50))
		"courier":
			_target = _home + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
		"stumble":
			_target = _home + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			_wait_t = randf_range(1.0, 5.0)
		_:
			_target = _home + Vector3(randf_range(-16, 16), 0, randf_range(-16, 16))
			_wait_t = randf_range(1.0, 5.0)


func _face(dir: Vector3, dt: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, minf(1.0, dt * 8.0))


func _guard(dt: float, player: Node, dist: float) -> void:
	velocity = Vector3.ZERO
	if player and dist < 8.0:
		anim.mode = "listen"
		var to: Vector3 = (player.global_position - global_position).normalized()
		anim.look_dir = to
		_face(to, dt)
	else:
		anim.mode = "listen"
		anim.look_dir = Vector3.ZERO
	anim.tick(dt, {})


func _talk_state(dt: float) -> void:
	velocity = Vector3.ZERO
	if _talk_partner and is_instance_valid(_talk_partner):
		_face((_talk_partner.global_position - global_position).normalized(), dt)
	anim.mode = "talk"
	if anim.talk_t < 0:
		anim.talk_t = 0.0
	anim.tick(dt, {})


func _flee(dt: float, _d: float) -> void:
	var away := (global_position - _flee_from)
	away.y = 0
	if away.length() < 0.5:
		away = Vector3(1, 0, 0)
	velocity = away.normalized() * 5.2
	_face(away.normalized(), dt)
	anim.mode = "locomote"
	anim.sprint = true
	anim.tick(dt, {})
	if away.length() > 40.0:
		state = State.ROUTINE
		anim.sprint = false


func _gawk(dt: float) -> void:
	_gawk_t -= dt
	velocity = Vector3.ZERO
	_face((_flee_from - global_position).normalized(), dt)
	anim.mode = "listen"
	anim.tick(dt, {})
	if _gawk_t <= 0.0:
		state = State.ROUTINE


func _combat_state(dt: float, player: Node) -> void:
	if player == null:
		return
	var to_p: Vector3 = (player.global_position - global_position)
	var dist := to_p.length()
	combat.in_combat = true
	combat.combat_timer = 5.0
	_face(to_p.normalized(), dt)
	_attack_cd -= dt
	_call_cd -= dt
	_stagger_t -= dt
	_retreat_t -= dt
	_backoff_t -= dt
	# --- squad awareness: stagger, call for help, notify allies ---
	var frac: float = combat.hp / maxf(1.0, combat.max_hp)
	if frac < 0.35 and _stagger_t <= -1.0 and randf() < 0.6 * dt:
		_stagger_t = randf_range(0.6, 1.1)
		if _call_cd <= 0.0 and hostile:
			_call_for_help()
			_call_cd = randf_range(12.0, 20.0)
	if frac < 0.25 and _retreat_t <= 0.0 and randf() < 0.25 * dt:
		_retreat_t = randf_range(2.0, 3.5)
	var gun: bool = _weapon_id != "" and Db.weapon(_weapon_id).get("kind", "") == "gun"
	# --- re-evaluate tactics every ~1.2 s ---
	_tactics_t -= dt
	if _tactics_t <= 0.0:
		_tactics_t = randf_range(0.9, 1.5)
		var allies := _nearby_allies(22.0)
		if allies.size() >= 2 and randf() < 0.55:
			_flank_side = 1.0 if randf() < 0.5 else -1.0   # pincer: opposite sides converge
		elif randf() < 0.25:
			_flank_side = 1.0 if randf() < 0.5 else -1.0
		else:
			_flank_side = 0.0
		if gun and frac < 0.3 and _retreat_t > 0.0:
			_flank_side = 0.0
	if gun:
		if dist < 45.0 and _attack_cd <= 0.0 and _stagger_t <= 0.0:
			# shoot with lead + spread
			var dir := to_p.normalized() + Vector3(0, 1.2 / dist, 0)
			dir += Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
			var muz := global_position + Vector3(0, 1.4, 0) + dir * 0.6
			var w := Db.weapon(_weapon_id)
			AudioDirector.sfx_at(w.get("sound", "shot_pistol"), muz)
			Effects.burst(muz, "muzzle", dir)
			Effects.tracer(muz, muz + dir * 40.0)
			# hit chance by distance
			if randf() < clampf(0.55 - dist * 0.008, 0.08, 0.55) and player.combat:
				player.combat.take_hit(float(w.get("dmg", 18)), -dir, "bullet", self)
			_attack_cd = 60.0 / float(w.get("rpm", 300)) * randf_range(2.5, 4.5)
			anim.aiming = true
		else:
			anim.aiming = dist < 45.0
		# tactical movement: spacing + lateral flank + retreat when hurt
		var move := Vector3.ZERO
		if _retreat_t > 0.0 or dist < 9.0:
			move += -to_p.normalized() * 2.8
		elif dist > 32.0:
			move += to_p.normalized() * 3.2
		var lateral := to_p.normalized().cross(Vector3.UP)
		move += lateral * (_flank_side * 3.0)
		velocity = move
		anim.mode = "locomote"
		anim.tick(dt, combat.style.get("stance", {}))
	else:
		anim.aiming = false
		var ideal := 1.25
		if _stagger_t > 0.0 or _backoff_t > 0.0 or _retreat_t > 0.0:
			# hurt: give ground, circle
			var back := -to_p.normalized() * 2.2
			var side := to_p.normalized().cross(Vector3.UP) * (2.0 if _flank_side >= 0 else -2.0)
			velocity = back + side
			anim.mode = "locomote"
		elif dist > ideal:
			var move := to_p.normalized() * 3.4
			if absf(_flank_side) > 0.0 and dist > 3.0:
				move += to_p.normalized().cross(Vector3.UP) * (_flank_side * 2.6)
			velocity = move
			anim.mode = "locomote"
		else:
			velocity = Vector3.ZERO
			if _attack_cd <= 0.0 and not combat.attacking:
				var kinds := _attack_pool()
				combat.request_attack(kinds[randi() % kinds.size()])
				_attack_cd = randf_range(0.6, 1.5)
				if randf() < 0.25:
					_backoff_t = randf_range(0.5, 1.0)   # feint-and-reset, not a punching bag
			anim.mode = "locomote"
		anim.tick(dt, combat.style.get("stance", {}))


func _attack_pool() -> Array:
	match _style_id:
		"kickboxing":
			return ["kick_r", "kick_l", "kick_high", "jab", "cross", "heavy"]
		"grappling":
			return ["grab", "takedown", "jab", "hook", "heavy"]
		"drunken":
			return ["hook", "jab", "kick_r", "heavy", "kick_high", "cross"]
		_:
			return ["jab", "cross", "hook", "kick_r", "heavy"]


func _nearby_allies(radius: float) -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n != self and is_instance_valid(n) and (n.global_position - global_position).length() < radius:
			out.append(n)
	return out


func _call_for_help() -> void:
	AudioDirector.sfx_at("shout_alert", global_position + Vector3(0, 1.5, 0))
	# wake hostiles in range toward the fight; alert neutral faction friends
	for n in get_tree().get_nodes_in_group("humanoid"):
		if n == self or not is_instance_valid(n):
			continue
		var d := (n.global_position - global_position).length()
		if d < 45.0:
			if n.has_method("react"):
				n.react("combat_call", global_position)


func react(event: String, from: Vector3) -> void:
	match event:
		"combat_call", "ally_down":
			if state != State.DEAD:
				if event == "ally_down":
					_stagger_t = 0.4          # flinch: a friend just dropped
					combat.combat_timer = 6.0
					AudioDirector.sfx_at("shout_warn", global_position + Vector3(0, 1.5, 0), 0.4)
				if state != State.COMBAT and hostile:
					state = State.COMBAT
	match event:
		"gunshots":
			if state != State.DEAD:
				state = State.FLEE
				_flee_from = from
				_bark("gunshots")
		"fight":
			if randf() < 0.5:
				state = State.GAWK
				_flee_from = from
				_gawk_t = randf_range(4, 9)
				_bark("combat")
			else:
				state = State.FLEE
				_flee_from = from
		"crime":
			_react_crime(null)
		"siren":
			if randf() < 0.4:
				state = State.GAWK
				_flee_from = from
				_gawk_t = 4.0


func _react_crime(player: Node) -> void:
	_bark("fear")
	state = State.FLEE
	_flee_from = player.global_position if player else global_position
	# witnesses call it in
	if randf() < 0.5:
		Bus.crime_committed.emit("witnessed", 1, global_position)


func _bark(context: String) -> void:
	if _bark_cd > 0.0:
		return
	_bark_cd = randf_range(4.0, 9.0)
	var lines: Array = Db.barks.get(context, [])
	if lines.is_empty():
		return
	var line: String = lines[randi() % lines.size()]
	Bus.dialogue_line.emit(display_name, line, voice)


# ------------------------------------------------------------ conversation --
func interact(player: Node) -> void:
	if state == State.DEAD:
		return
	if hostile:
		return
	if char_id != "":
		Bus.world_event.emit("talk_request", {"char": char_id, "node": self})
	else:
		_bark(["greet", "city", "rain" if WorldState.weather == WorldState.Weather.RAIN else "night"][randi() % 3])


func begin_talk(partner: Node) -> void:
	state = State.TALK
	_talk_partner = partner
	anim.talk_t = 0.0


func end_talk() -> void:
	_talk_partner = null
	anim.talk_t = -1.0
	if state == State.TALK:
		state = State.ROUTINE


func _on_died(_cause: String) -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	set_meta("hostile", false)
	remove_from_group("enemy")
	if hostile:
		WorldState.stats["kos"] += 1
		for n in get_tree().get_nodes_in_group("enemy"):
			if n != self and is_instance_valid(n) and (n.global_position - global_position).length() < 30.0:
				n.react("ally_down", global_position)
	else:
		Bus.crime_committed.emit("homicide", 5, global_position)
		for n in get_tree().get_nodes_in_group("humanoid"):
			if n != self and (n.global_position - global_position).length() < 25.0:
				n.react("gunshots", global_position)


func save_state() -> Dictionary:
	return {"id": char_id if char_id != "" else ped_id, "named": char_id != "",
		"pos": [global_position.x, global_position.y, global_position.z],
		"dead": state == State.DEAD, "hp": combat.hp}
