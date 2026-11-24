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
var _chat_idle := false             # nightlife: stand and chat
var suspicion: float = 0.0          # 0..100 stealth awareness meter
var _last_known := Vector3.ZERO     # where the player was last spotted
var _search_t := 0.0
var hostile: bool = false
# --- combat tactics (wave 4) ---
var _tactics_t := 0.0
var _flank_side := 0.0
var _stagger_t := 0.0
var _retreat_t := 0.0
var _call_cd := 8.0
var _backoff_t := 0.0
var _mag := 12
var _reload_t := 0.0
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
	bark_ctx = str(d.get("barks", ""))
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
			combat.armor_prot = 0.30
		"cop":
			_weapon_id = "gun_pistol"
			_style_id = "weapon"
			combat.armor_prot = 0.20
		_:
			_style_id = ["brawler", "kickboxing", "drunken"][randi() % 3]
	# late-game thugs arrive armed/armoured as the city gets meaner
	if kind.begins_with("thug") and _weapon_id == "":
		var roll: float = Difficulty.loadout_roll()
		if roll > 0.55 and randf() < roll * 0.5:
			_weapon_id = "gun_pistol"
			_style_id = "weapon"
		elif roll > 0.3 and randf() < roll * 0.6:
			_weapon_id = "melee_bat"
			combat.armor_prot = 0.10
	if _weapon_id != "":
		var wd: Dictionary = Db.weapon(_weapon_id)
		_mag = int(wd.get("mag", 12))
	# escalating difficulty: enemy vitals scale with story threat
	combat.max_hp *= Difficulty.enemy_hp_mult()
	combat.hp = combat.max_hp
	combat.set_style(_style_id)
	state = State.COMBAT
	add_to_group("enemy")


func _armor_visual() -> void:
	# plate vest over the torso: readable armour silhouette
	var sk := get_node_or_null("Humanoid/Skeleton3D")
	if sk == null:
		return
	var chest: int = sk.find_bone("chest")
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
			_try_hop_in_car()
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


var _body_t := 0.0


func _body_scan(dt: float) -> void:
	## Hitman-style consequence: leave a body where a patroller can see it
	## and the district learns about it. Discovery = alarm + crime report
	## at the body's position (witnesses point the police at YOUR trail).
	if hostile or state in [State.COMBAT, State.DEAD, State.FLEE]:
		return
	_body_t -= dt
	if _body_t > 0.0:
		return
	_body_t = 0.8
	for c in get_tree().get_nodes_in_group("corpse"):
		if c == self or not is_instance_valid(c):
			continue
		var to: Vector3 = c.global_position - global_position
		to.y = 0
		if to.length() > 16.0:
			continue
		var fwd := -global_transform.basis.z
		if fwd.normalized().dot(to.normalized()) < 0.3:
			continue
		if not _los_clear(c):
			continue
		# discovered!
		_bark("body")
		Bus.notification.emit("A body has been found!", "error")
		Bus.crime_committed.emit("body_found", 3, c.global_position)
		WorldState.stats["bodies_found"] = WorldState.stats.get("bodies_found", 0) + 1
		state = State.FLEE
		_flee_from = c.global_position
		anim.sprint = true
		return


func _routine(dt: float, player: Node, dist: float) -> void:
	_body_scan(dt)
	# react to nearby crime/violence
	if player and dist < 18.0:
		if WorldState.wanted > 0 and randf() < 0.01:
			_react_crime(player)
		elif combat.in_combat or (player.combat and player.combat.in_combat):
			if randf() < 0.05:
				_react_crime(player)
	# A DRAWN GUN clears the street: civilians don't wait to find out what
	# it's for. Screams, scatter, and a decent chance someone calls it in.
	if player and not player.dead and hostile == false and dist < 22.0 \
			and player.in_vehicle == null and player.weapons != null \
			and player.weapons.weapon_id != "" and player.weapons.is_gun() \
			and not player.get("crouch_held") and _los_clear(player):
		if randf() < 2.2 * dt:
			_bark("gunshots")
			_react_crime(player)
	_greet_respect_cd = maxf(0.0, _greet_respect_cd - dt)
	if _wait_t > 0.0:
		_wait_t -= dt
		velocity = Vector3.ZERO
		if _chat_idle and _day_part() == "nightlife":
			if bark_ctx == "drunk" and randf() < 0.02:
				_bark("drunk")
			anim.mode = "talk" if randf() < 0.6 else "listen"
			anim.talk_t = maxf(anim.talk_t, 0.0) + dt
		elif WorldState.weather == WorldState.Weather.RAIN:
			anim.mode = "listen"       # huddled, arms in, waiting out the rain
		else:
			anim.mode = "listen" if randf() < 0.5 else "locomote"
		anim.tick(dt, {})
		if _wait_t <= 0.0:
			_chat_idle = false
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


## Sims-like day part: the same citizen does different things at 8am and 2am.
func _day_part() -> String:
	var h: float = WorldState.game_hour
	if h < 6.0:
		return "night"
	if h < 9.5:
		return "commute_am"
	if h < 17.0:
		return "work"
	if h < 20.0:
		return "commute_pm"
	return "nightlife"


func _pick_next_routine() -> void:
	var d: Dictionary = Db.peds.get(ped_id, {})
	var routine: String = d.get("routine", "wander")
	var part := _day_part()
	# --- schedule layer: overrides base routine by time of day ---
	match part:
		"commute_am", "commute_pm":
			if routine in ["commute", "work", "courier"]:
				# purposeful long walk: commuters cross the district
				_target = _home + Vector3(randf_range(-70, 70), 0, randf_range(-70, 70))
				return
		"work":
			if routine in ["work", "courier", "commute"]:
				_target = _home + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
				_wait_t = randf_range(3.0, 8.0)
				return
		"nightlife":
			if randf() < 0.45:
				# cluster near neon: bars, stalls, corners — stand and talk
				_target = _home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
				_wait_t = randf_range(4.0, 10.0)
				_chat_idle = randf() < 0.4
				return
		"night":
			if routine in ["commute", "work", "jog", "courier"] and randf() < 0.7:
				# sensible citizens are home: short shuffle, mostly still
				_target = _home + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
				_wait_t = randf_range(6.0, 14.0)
				return
	# --- base routine ---
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
			if part == "night":
				_target = _home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
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
	## Stealth-aware guard: vision cone feeds a suspicion meter
	## (0 calm -> 45 suspicious -> 100 alert). Broken line of sight sends
	## them to search the last known position, then cool off.
	if player == null or player.dead:
		suspicion = maxf(0.0, suspicion - dt * 12.0)
		velocity = Vector3.ZERO
		anim.tick(dt, {})
		return
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0
	var facing := -global_transform.basis.z
	var sees := false
	# weather shortens sightlines: fog swallows the street, rain blurs it
	var sight: float = 26.0
	if WorldState.weather == WorldState.Weather.FOG:
		sight = 15.0
	elif WorldState.weather == WorldState.Weather.RAIN:
		sight = 21.0
	if dist < sight:
		var in_cone: bool = facing.normalized().dot(to_p.normalized()) > (0.25 if dist > 6.0 else -0.2)
		if in_cone and _los_clear(player):
			sees = true
	if sees:
		# crouch + distance + weather slow detection; sprinting right at them is suicide
		var rate: float = 34.0 * (1.6 - dist / 26.0)
		# DISGUISE: matching outfit halves suspicion — unless you're blatant
		# (gun out or sprinting). Hitman-lite: clothes are a tool, not magic.
		# district heat: a neighborhood on edge spots trouble faster
		rate *= 1.0 + WorldState.district_heat01(WorldGen.district_at(global_position)) * 0.6
		var dis: String = Db.outfits.get(WorldState.equipped_outfit, {}).get("disguise", "")
		if dis != "" and dis == faction_tag:
			var blatant: bool = (player.weapons != null and player.weapons.weapon_id != "" and player.weapons.is_gun()) or player.sprint_held
			rate *= 1.0 if blatant else 0.45
		if player.crouch_held:
			rate *= 0.4
		if player.sprint_held:
			rate *= 1.7
		if WorldState.weather == WorldState.Weather.RAIN and dist > 10.0:
			rate *= 0.7
		if WorldState.weather == WorldState.Weather.FOG and dist > 8.0:
			rate *= 0.55
		var before: float = suspicion
		suspicion = minf(100.0, suspicion + rate * dt)
		_last_known = player.global_position
		_face(to_p.normalized(), dt * 2.0)
		if before < 45.0 and suspicion >= 45.0:
			_bark("suspicious")
			Bus.prompt_hint.emit("A guard is getting suspicious...")
		if suspicion >= 100.0:
			_bark("alert")
			hostile = true
			set_meta("hostile", true)
			state = State.COMBAT
			_alert_nearby()
			return
		velocity = Vector3.ZERO
		anim.mode = "listen"
		anim.look_dir = to_p.normalized()
	else:
		suspicion = maxf(0.0, suspicion - dt * (14.0 if suspicion < 100.0 else 8.0))
		if suspicion > 45.0 and _last_known != Vector3.ZERO:
			# SEARCH: walk to where they last saw you, look around
			_search_t -= dt
			var to_lk := _last_known - global_position
			to_lk.y = 0
			if to_lk.length() > 1.4:
				velocity = to_lk.normalized() * 2.4
				_face(to_lk.normalized(), dt)
				anim.mode = "locomote"
			else:
				velocity = Vector3.ZERO
				anim.mode = "listen"
				var sweep := Vector3(sin(Time.get_ticks_msec() * 0.002), 0, cos(Time.get_ticks_msec() * 0.002))
				_face(sweep, dt)
				anim.look_dir = sweep
			if suspicion <= 45.0:
				_search_t = 0.0
				Bus.prompt_hint.emit("")
		else:
			velocity = Vector3.ZERO
			anim.mode = "listen"
			anim.look_dir = Vector3.ZERO
	anim.tick(dt, {})


func _los_clear(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	var duck: float = 0.45 if target.get("crouch_held") else 0.0
	q.from = global_position + Vector3(0, 1.5, 0)
	q.to = target.global_position + Vector3(0, 1.1 - duck, 0)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == target


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


var _hop_t := 0.0


func _try_hop_in_car() -> void:
	## Fleeing civilians sometimes dive into a nearby traffic car and
	## peel away — the block scattering from wave 32, with wheels.
	if hostile:
		return
	_hop_t -= get_physics_process_delta_time()
	if _hop_t > 0.0:
		return
	_hop_t = 1.0
	for n in get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(n) or not bool(n.get("is_traffic")) or n.get("_wrecked"):
			continue
		if (n.global_position - global_position).length() > 9.0:
			continue
		if n.speed_kmh() > 25.0:
			continue
		if n.has_method("civ_panic"):
			n.civ_panic()
			_bark("alert")
			# they're gone: the car carries them off
			var t := create_tween()
			t.tween_property(self, "scale", Vector3(0.2, 0.2, 0.2), 0.25)
			t.tween_callback(queue_free)
			state = State.DEAD   # stop AI immediately (body never spawns)
			return


func _gawk(dt: float) -> void:
	_gawk_t -= dt
	velocity = Vector3.ZERO
	_face((_flee_from - global_position).normalized(), dt)
	anim.mode = "listen"
	anim.tick(dt, {})
	if _gawk_t <= 0.0:
		state = State.ROUTINE


func _combat_state(dt: float, player: Node) -> void:
	# TARGET SELECTION: nearest of player vs rival-faction NPC. Cinder City's
	# crews hate each other as much as they hate you — turf clashes erupt
	# and you can watch, join, or loot the aftermath.
	var target: Node3D = player
	if hostile and faction_tag != "":
		var rival := _find_rival(26.0)
		if rival != null:
			var dp := 1e9
			if player != null:
				dp = (player.global_position - global_position).length()
			var dr: float = (rival.global_position - global_position).length()
			if dr < dp * 0.85:
				target = rival
	if target == null:
		return
	var to_p: Vector3 = (target.global_position - global_position)
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
		var aggr: float = Difficulty.aggression()
		_tactics_t = randf_range(1.5, 2.2) - aggr * 0.9
		var allies := _nearby_allies(22.0)
		if allies.size() >= 2 and randf() < 0.3 + aggr * 0.45:
			_flank_side = 1.0 if randf() < 0.5 else -1.0   # pincer: opposite sides converge
		elif randf() < 0.25:
			_flank_side = 1.0 if randf() < 0.5 else -1.0
		else:
			_flank_side = 0.0
		if gun and frac < 0.3 and _retreat_t > 0.0:
			_flank_side = 0.0
	if gun:
		if _reload_t > 0.0:
			_reload_t -= dt
			anim.aiming = false
			if _reload_t <= 0.0:
				_mag = int(Db.weapon(_weapon_id).get("mag", 12))
				AudioDirector.sfx_at("reload_slide", global_position + Vector3(0, 1.2, 0), 0.5)
		if dist < 45.0 and _attack_cd <= 0.0 and _stagger_t <= 0.0 and _reload_t <= 0.0:
			# shoot with lead + spread
			var dir := to_p.normalized() + Vector3(0, 1.2 / dist, 0)
			dir += Vector3(randf_range(-0.03, 0.03), 0, randf_range(-0.03, 0.03))
			var muz := global_position + Vector3(0, 1.4, 0) + dir * 0.6
			var w := Db.weapon(_weapon_id)
			AudioDirector.sfx_at(w.get("sound", "shot_pistol"), muz)
			Effects.burst(muz, "muzzle", dir)
			Effects.tracer(muz, muz + dir * 40.0)
			# hit chance by distance
			var tc = target.get("combat")
			if randf() < clampf(0.55 - dist * 0.008 + Difficulty.accuracy_bonus(), 0.08, 0.72) and tc:
				var dmg_out: float = float(w.get("dmg", 18))
				if target == player:
					dmg_out *= Difficulty.enemy_dmg_mult()
				tc.take_hit(dmg_out, -dir, "bullet", self)
			_attack_cd = 60.0 / float(w.get("rpm", 300)) * randf_range(2.5, 4.5) * (1.35 - Difficulty.aggression() * 0.35)
			anim.aiming = true
			_mag -= 1
			if _mag <= 0:
				# dry: tactical reload under fire
				_reload_t = randf_range(1.8, 2.6)
				AudioDirector.sfx_at("reload_magout", global_position + Vector3(0, 1.2, 0), 0.5)
				_stagger_t = maxf(_stagger_t, 0.5)   # vulnerable window: fair to rush
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
		# GUARD AI (Sifu lesson): trained enemies raise hands in rhythm —
		# chip their posture with hits to break the guard, then punish.
		# A broken guard can't re-block until it recovers, so aggression
		# is rewarded, but turtling enemies are no longer punching bags.
		if _guard_t > 0.0:
			_guard_t -= dt
			if _guard_t <= 0.0:
				combat.set_block(false)
		elif not combat.attacking and combat.guard_broken_t <= 0.0 \
				and float(combat.style.get("guard_strength", 0.0)) >= 0.5 \
				and dist < 3.4 and randf() < (0.12 + Difficulty.aggression() * 0.2) * dt * 8.0:
			combat.set_block(true)
			_guard_t = randf_range(0.6, 1.2)
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


func _find_rival(radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for n in get_tree().get_nodes_in_group("enemy"):
		if n == self or not is_instance_valid(n):
			continue
		var nf: String = str(n.get("faction_tag"))
		if nf == "" or nf == faction_tag:
			continue
		var c = n.get("combat")
		if c == null or c.dead:
			continue
		var d: float = (n.global_position - global_position).length()
		if d < bd:
			bd = d
			best = n
	return best


func _nearby_allies(radius: float) -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n != self and is_instance_valid(n) and (n.global_position - global_position).length() < radius:
			out.append(n)
	return out


func _alert_nearby() -> void:
	## Shout the alarm: hostiles within 40 m converge on the fight.
	_call_for_help()


func _call_for_help() -> void:
	AudioDirector.sfx_at("shout_alert", global_position + Vector3(0, 1.5, 0))
	# wake hostiles in range toward the fight; alert neutral faction friends
	for n in get_tree().get_nodes_in_group("humanoid"):
		if n == self or not is_instance_valid(n):
			continue
		var d: float = (n.global_position - global_position).length()
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
		"respect_deed":
			# you just protected someone — the block says so out loud
			if WorldState.street_rep() >= 0:
				_bark("respect")
		"siren":
			if randf() < 0.4:
				state = State.GAWK
				_flee_from = from
				_gawk_t = 4.0
		"scramble":
			# a car is coming: not a show, a threat — get off the road
			if state in [State.ROUTINE, State.GAWK]:
				state = State.FLEE
				_flee_from = from
				if randf() < 0.25:
					_bark("fear")


var _snitch_cd := 0.0
var _guard_t := 0.0                 # trained-guard raise timer (posture system)
var bark_ctx := ""                  # per-ped bark override ("young", "drunk")
var _greeted_player := false          # already gave the player the time of day
var _greet_respect_cd := 0.0          # can't farm street rep off one local
var chatter_peer: Node = null         # mid-conversation partner (overheard)


func _react_crime(player: Node) -> void:
	_bark("fear")
	state = State.FLEE
	_flee_from = player.global_position if player else global_position
	# witnesses call it in — and a good witness describes WHERE the
	# suspect is, not where the screaming is. Throttled per-witness so
	# one crime doesn't become a dozen sirens.
	_snitch_cd -= get_physics_process_delta_time()
	# the block decides whether to talk to the CCPD: protect people and
	# they lie for you; prey on them and every witness sings
	if randf() < WorldState.snitch_chance() and _snitch_cd <= 0.0:
		_snitch_cd = 20.0
		var tip := _flee_from if player != null else global_position
		Bus.crime_committed.emit("witnessed", 1, tip)


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
	if state == State.DEAD or state == State.FLEE:
		return
	if hostile:
		return
	if char_id != "":
		Bus.world_event.emit("talk_request", {"char": char_id, "node": self})
		return
	# CIVILIAN AGENCY: talking to a local is a choice, not a coin-flip bark.
	# Greet them like a person, show the block respect, or rough them up
	# for nothing — each path feeds street rep the same way deeds do.
	if _greeted_player:
		_bark(bark_ctx if bark_ctx != "" and Db.barks.has(bark_ctx) else "greet")
		return
	var opts: Array = []
	var self_node := self
	var pl := player
	var casual := bark_ctx if bark_ctx != "" and Db.barks.has(bark_ctx) else "greet"
	opts.append({"label": "Ask what's going on in the block", "act": func():
		self_node._greeted_player = true
		self_node._bark(casual)})
	if _greet_respect_cd <= 0.0:
		opts.append({"label": "Show respect — how's the street doing?", "act": func():
			self_node._greet_respect_cd = 240.0
			self_node._bark("respect")
			WorldState.note_deed("showed_respect", WorldGen.district_at(self_node.global_position), true)})
	opts.append({"label": "Antagonize them", "act": func():
		self_node._bark("hostile")
		WorldState.note_deed("bully", WorldGen.district_at(self_node.global_position), false)
		if pl != null and randf() < 0.6:
			self_node._flee_from = pl.global_position
			self_node.state = State.FLEE})
	opts.append({"label": "Walk away", "act": func(): pass})
	DialogueUI.start_choices("The local eyes you.", opts, func(opt):
		var c: Callable = opt.get("act", Callable())
		if c.is_valid():
			c.call())


func begin_talk(partner: Node) -> void:
	state = State.TALK
	_talk_partner = partner
	anim.talk_t = 0.0


func end_talk() -> void:
	_talk_partner = null
	anim.talk_t = -1.0
	if state == State.TALK:
		state = State.ROUTINE


func hide_body() -> void:
	## Drag the body out of sight (dumpster, alcove, car trunk — the city
	## is full of them). Hidden bodies never get discovered, so heat and
	## faction heat never spike. Stashed kills are the professional's path.
	if state != State.DEAD:
		return
	remove_from_group("corpse")
	WorldState.stats["bodies_hidden"] = WorldState.stats.get("bodies_hidden", 0) + 1
	AudioDirector.sfx_at("cloth_rustle", global_position + Vector3(0, 0.6, 0))
	AudioDirector.sfx_at("body_fall", global_position, 0.5)
	Bus.notification.emit("Body hidden. Out of sight, out of the papers.", "info")
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector3(0.2, 0.2, 0.2), 0.5)
	t.tween_property(self, "global_position:y", global_position.y - 0.6, 0.5)
	t.chain().tween_callback(queue_free)


func _on_died(_cause: String) -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	set_meta("hostile", false)
	remove_from_group("enemy")
	add_to_group("corpse")
	if hostile:
		_drop_loot()
	var by_player: bool = combat != null and combat.last_attacker != null \
			and is_instance_valid(combat.last_attacker) and combat.last_attacker.is_in_group("player")
	var did_slain := WorldGen.district_at(global_position)
	if hostile:
		WorldState.stats["kos"] += 1
		if by_player and faction_tag != "law":
			# saved a mugging victim? they say thank you — and the deed
			# lands even with no other witnesses around
			if get_meta("event_role", "") == "mugger":
				for n in get_tree().get_nodes_in_group("humanoid"):
					if is_instance_valid(n) and String(n.get_meta("event_role", "")) == "victim" \
							and (n.global_position - global_position).length() < 25.0:
						WorldState.note_deed("stood_up", did_slain, true)
						n.react("respect_deed", global_position)
						n._bark("thank")
						break
			# THE BLOCK WATCHES: put down a predator while civilians see
			# it and the street remembers who protected it
			for n in get_tree().get_nodes_in_group("humanoid"):
				if n == self or not is_instance_valid(n) or bool(n.get("hostile")):
					continue
				if n.is_in_group("player") or not n.has_method("react"):
					continue
				if (n.global_position - global_position).length() < 14.0:
					WorldState.note_deed("stood_up", did_slain, true)
					n.react("respect_deed", global_position)
					break
		for n in get_tree().get_nodes_in_group("enemy"):
			if n != self and is_instance_valid(n) and n.has_method("react") and (n.global_position - global_position).length() < 30.0:
				n.react("ally_down", global_position)
	else:
		Bus.crime_committed.emit("homicide", 5, global_position)
		if by_player:
			WorldState.note_deed("preyed_on", did_slain, false)
		for n in get_tree().get_nodes_in_group("humanoid"):
			if n != self and is_instance_valid(n) and n.has_method("react") and (n.global_position - global_position).length() < 25.0:
				n.react("gunshots", global_position)


func _drop_loot() -> void:
	## Pockets pay: cash always, ammo for whatever they carried, sometimes
	## a bandage. Loot spawns as a pickup so looting is a deliberate beat —
	## and lingering over bodies is how you get caught with them.
	var cash := int(randf_range(8.0, 26.0) * (1.0 + Difficulty.threat()))
	WorldState.add_money(cash)
	AudioDirector.sfx_at("cash", global_position + Vector3(0, 0.4, 0), 0.5)
	var ammo_map := {"gun_pistol": "ammo_9mm", "gun_smg": "ammo_smg", "gun_shotgun": "ammo_12g", "gun_rifle": "ammo_308", "gun_magnum": "ammo_357", "gun_machine_pistol": "ammo_9mm"}
	if ammo_map.has(_weapon_id) and randf() < 0.65:
		_spawn_loot_pickup(ammo_map[_weapon_id])
	elif _weapon_id.begins_with("melee_") and randf() < 0.3:
		_spawn_loot_pickup(_weapon_id)
	if randf() < 0.22:
		_spawn_loot_pickup("bandage")


func _spawn_loot_pickup(item: String) -> void:
	var p := Area3D.new()
	p.set_script(load("res://scripts/missions/pickup.gd"))
	p.set_meta("item", item)
	p.set_meta("mode", "world")
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6))


func save_state() -> Dictionary:
	return {"id": char_id if char_id != "" else ped_id, "named": char_id != "",
		"pos": [global_position.x, global_position.y, global_position.z],
		"dead": state == State.DEAD, "hp": combat.hp}
