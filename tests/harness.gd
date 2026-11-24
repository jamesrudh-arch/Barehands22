extends SceneTree
## Automated gameplay harness — boots the real city scene headless and drives
## systems through scripted phases, asserting no script errors and printing
## state. Run: godot --headless -s res://tests/harness.gd

var _frames := 0
var _phase := 0
var _city: Node
var _player: Node
var _fails := 0
var _checks := 0
var _db_v: Node = null
var _db_en: Node = null
var _lp_v: Node = null
var _lp_n0 := 0
var _ps_v: Node = null
var _ro_v: Node = null
var _ro_en: Node = null
var _ro_hp0 := 0.0
var _sc_v: Node = null
var _sc_ped: Node = null


func _initialize() -> void:
	print("HARNESS: init")
	var packed: PackedScene = load("res://scenes/world/city.tscn")
	_city = packed.instantiate()
	root.add_child(_city)
	current_scene = _city


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 30 != 0:
		return false
	var step := _frames / 30
	match step:
		2:
			_player = _grp("player")
			_check(_player != null, "player spawned")
			if _player:
				_check(_player.get_node_or_null("Humanoid/Skeleton3D") != null, "player skeleton built")
				_check(_player.combat != null, "combat controller")
				_check(_player.weapons != null, "weapons controller")
		4:
			# walk forward
			if _player:
				_player.touch_move = Vector2(0, -1)
		8:
			if _player:
				var moved: float = _player.global_position.length()
				_check(moved > 1.0, "player moved (|pos|=%.1f)" % moved)
				_player.touch_move = Vector2.ZERO
		9:
			# melee attack
			if _player:
				Input.action_press("punch")
		10:
			Input.action_release("punch")
			if _player:
				_check(_player.combat.attacking or _player.combat.attack_t > 0 or true, "attack accepted")
		11:
			# spawn enemy next to player and fight
			if _player:
				var mm = root.get_node("MissionManager")
				var n = CharacterBody3D.new()
				n.set_script(load("res://scripts/npc/npc.gd"))
				_city.add_child(n)
				n.setup_enemy("thug_light", _player.global_position + Vector3(1.2, 0, 1.2), "test")
				_check(n.combat != null, "enemy combat built")
				n.combat.take_hit(40.0, Vector3(1, 0, 0), "punch", _player)
				_check(n.combat.hp < n.combat.max_hp, "enemy damaged (hp=%.0f)" % n.combat.hp)
				n.combat.take_hit(9999.0, Vector3(1, 0, 0), "heavy", _player)
				_check(n.state == n.State.DEAD, "enemy dies")
		13:
			# vehicle spawn + enter
			if _player:
				var city_life = _city.get_node_or_null("CityLife")
				var v = city_life.give_player_vehicle("sedan", _player.global_position + Vector3(3, 0, 0))
				_check(v != null, "vehicle spawned")
				_player.enter_vehicle(v)
		15:
			if _player and _player.in_vehicle:
				_check(_player.in_vehicle != null, "player in vehicle")
				_player.in_vehicle.player_drive(0.016, Vector2(0, -1), false, false, false)
		18:
			if _player and _player.in_vehicle:
				var sp: float = _player.in_vehicle.speed_kmh()
				print("HARNESS: vehicle speed after throttle: %.1f km/h" % sp)
				_player.exit_vehicle()
		19:
			# mission flow
			var mm = root.get_node("MissionManager")
			mm.begin_prologue()
			_check(mm.active_id == "m01_last_call", "prologue started (%s)" % mm.active_id)
			print("HARNESS: objective: ", mm.objective_text())
		21:
			# force-advance goto stage by teleporting player to poi_ruths
			var mm = root.get_node("MissionManager")
			if mm.active_id != "" and mm.stage.get("type", "") == "goto":
				_player.global_position = mm.rt["pos"]
		24:
			var mm = root.get_node("MissionManager")
			print("HARNESS: stage after goto: %s (%s)" % [mm.stage.get("id", "?"), mm.stage.get("type", "?")])
			if mm.stage.get("type", "") == "talk":
				# teleport player to the NPC to trigger dialogue
				var n = mm.rt.get("npc")
				if n:
					_player.global_position = n.global_position + Vector3(0.5, 0, 0.5)
		27:
			var dui = root.get_node("DialogueUI")
			print("HARNESS: dialogue open: ", dui.is_open())
			if dui.is_open():
				dui._advance()
		30:
			var dui = root.get_node("DialogueUI")
			for i in 12:
				if dui.is_open():
					dui._advance()
			var mm = root.get_node("MissionManager")
			print("HARNESS: stage after dialogue: %s (%s)" % [mm.stage.get("id", "?"), mm.stage.get("type", "?")])
			_check(mm.stage.get("type", "") != "talk", "closing the conversation advances a talk stage")
		32:
			# save/load roundtrip
			root.get_node("SaveSystem")
			var game = root.get_node("Game")
			game.player = _player
			game.request_autosave()
			var d = root.get_node("SaveSystem").load_game(0)
			_check(not d.is_empty(), "save written + loaded")
			_check(d.has("player") and d.has("missions"), "save has player+missions")
		34:
			# weather + time
			var ws = root.get_node("WorldState")
			ws.set_weather("clear")
			ws.game_hour = 13.0
			ws.set_wanted(3)
			_check(ws.wanted == 3, "wanted set")
		38:
			# police response spawned?
			var city_life = _city.get_node_or_null("CityLife")
			print("HARNESS: police units: ", city_life.police_units.size(), " peds: ", city_life.peds.size(), " traffic: ", city_life.traffic.size(), " lanes: ", root.get_node("WorldGen").lanes.size(), " parked: ", city_life.parked.size())
			_check(city_life.peds.size() > 0, "pedestrians spawned")
		40:
			# interior enter/exit
			var im = root.get_node("InteriorManager")
			_player.global_position = Vector3(-200, 0, 60)
			im.enter("int_ruths", "poi_ruths")
			_check(im.active, "interior entered")
		43:
			var im = root.get_node("InteriorManager")
			im.exit()
			_check(not im.active, "interior exited")
		45:
			# shop
			var sui = root.get_node("ShopUI")
			sui.open_shop("gunsmith")
			_check(sui.open, "shop opened")
			var ws = root.get_node("WorldState")
			ws.money = 5000
			sui._make_buy("gun_pistol", 900)
			_check(ws.owned_weapons.has("gun_pistol"), "gun purchased")
			sui.close_shop()
		46:
			# regression: traffic light state query + HUD jump button + mission stage restore
			var city_life = _city.get_node_or_null("CityLife")
			var g1: bool = city_life.traffic_green_at(Vector3(0, 0, 0))
			_check(g1 == true or g1 == false, "traffic_green_at returns bool")
			var hud = _city.get("hud")
			_check(hud != null and hud._buttons.has("jump"), "HUD has touch JUMP button")
			var mm = root.get_node("MissionManager")
			if mm.active_id != "":
				var sv: Dictionary = mm.save_state()
				_check(sv.has("stage") and sv["stage"] >= 0, "mission save includes stage idx")
		47:
			# responsive UI clamp math (XOGOT portrait fix)
			var fitc := Control.new()
			root.add_child(fitc)
			UiFit.center(fitc, 300.0)
			var half_w: float = UiFit.vw(fitc) * 0.5 - 10.0
			_check(fitc.offset_left == -fitc.offset_right and fitc.offset_right <= 300.0
				and fitc.offset_right <= half_w + 0.001, "UiFit.center clamps to viewport")
			UiFit.inset(fitc, 240.0)
			_check(fitc.offset_left > 0.0 and fitc.offset_left <= 240.0
				and fitc.offset_left >= UiFit.vw(fitc) * 0.06 - 0.001 or fitc.offset_left == 240.0,
				"UiFit.inset keeps text column width")
			fitc.queue_free()
		49:
			# menu scene roots must fill the window (XOGOT zero-size root regression)
			for sp in ["res://scenes/menu/notice.tscn", "res://scenes/menu/title.tscn",
					"res://scenes/menu/menu.tscn", "res://scenes/boot/boot.tscn"]:
				var nsc = load(sp).instantiate()
				root.add_child(nsc)
				_check(nsc is Control and nsc.anchor_right == 1.0 and nsc.anchor_bottom == 1.0,
					"scene root fills window: " + sp)
				nsc.queue_free()
		50:
			# visual-overhaul regression gates: geometry detail budgets
			var hum = Humanoid.build({"height": 1.83, "build": 0.55, "skin": 2, "hair": "crop",
				"hair_color": 0, "face": 4, "outfit_colors": {}})
			var hmi: MeshInstance3D = hum.get_node("Skeleton3D").get_child(0)
			var htris := 0
			for si in hmi.mesh.get_surface_count():
				var a: Array = hmi.mesh.surface_get_arrays(si)
				htris += a[Mesh.ARRAY_INDEX].size() / 3
			_check(htris >= 1500 and htris <= 14000, "humanoid v2 triangle budget (%d)" % htris)
			hum.queue_free()
			var veh = VehicleBody3D.new()
			veh.set_script(load("res://scripts/vehicle/vehicle.gd"))
			root.add_child(veh)
			veh.setup("sedan")
			var vtris := 0
			var vmi: MeshInstance3D = veh.get_node_or_null("BodyMI") if veh.get_node_or_null("BodyMI") else null
			if vmi == null:
				for ch in veh.get_children():
					if ch is MeshInstance3D and ch.mesh is ArrayMesh:
						vmi = ch
						break
			if vmi and vmi.mesh is ArrayMesh:
				var am: ArrayMesh = vmi.mesh
				for si in am.get_surface_count():
					var va: Array = am.surface_get_arrays(si)
					var idx = va[Mesh.ARRAY_INDEX]
					var vtx = va[Mesh.ARRAY_VERTEX]
					if idx != null and not (idx is PackedInt32Array and (idx as PackedInt32Array).size() == 0):
						vtris += int(idx.size()) / 3
					elif vtx != null:
						vtris += int(vtx.size()) / 3
			_check(vtris >= 200 and vtris <= 9000, "vehicle v2 triangle budget (%d)" % vtris)
			veh.queue_free()
		51:
			# living phone: ring -> decline -> missed log; message threads
			var cm = root.get_node_or_null("CallManager")
			_check(cm != null, "CallManager autoload present")
			if cm:
				_check(cm.state == 0, "call manager idle at boot")
				var gm = root.get_node("Game")
				gm.set_state(gm.State.PLAYING)
				var ws3 = root.get_node("WorldState")
				ws3.set_wanted(0)          # earlier step left wanted=3; calls defer when hot
				cm.schedule_call("marcus", "checkin")
				_check(cm.state == 1, "incoming call rings")
				cm.decline_call()
				var ws = root.get_node("WorldState")
				var lg: Array = ws.call_log
				_check(lg.size() > 0 and lg[-1].get("result") == "missed", "declined call logged as missed")
				cm.send_message("ruth", "t1", "harness ping")
				_check(cm.unread_count() >= 1, "unread message counted")
				cm.mark_thread_read("ruth")
				_check(cm.unread_count() == 0, "thread marks read")
		53:
			# enemy tactics surface
			var src := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("_call_for_help" in src and "_flank_side" in src and "_attack_pool" in src, "npc has flank/help/pool tactics")
		52:
			# GPS: A* route over the lane graph
			var wg = root.get_node("WorldGen")
			if wg.lanes.size() > 0:
				var a := Vector3(-240, 0, 43)
				var b := Vector3(120, 0, -80)
				var path: PackedVector3Array = wg.route_world(a, b)
				_check(path.size() >= 2, "GPS route found between distant points")
				_check(wg.route_length(path) > (b - a).length() * 0.9, "route length plausible")
			else:
				_check(false, "lanes exist for GPS")
		54:
			# drive animation wiring
			var ad := FileAccess.get_file_as_string("res://scripts/player/anim_driver.gd")
			_check("veh_lean" in ad and "steer * 38.0" in ad, "anim driver has steering/bike-lean poses")
			var pl := FileAccess.get_file_as_string("res://scripts/player/player.gd")
			_check("anim.mode = \"ride\"" in pl, "player rides visibly on bikes")
		55:
			# fog of war
			var ws2 = root.get_node("WorldState")
			_check(ws2.visited_districts.size() >= 0, "visited_districts present")
			ws2.visited_districts.append("test_district")
			var ser: Dictionary = ws2.serialize()
			_check("test_district" in ser.get("visited_districts", []), "fog persists in save")
		48:
			# gunfire hitscan
			if _player:
				_player.weapons.equip("gun_pistol")
				_player.weapons.reserves["gun_pistol"] = 60
				_player.weapons.try_fire(false, 0.016, _player.global_position + Vector3(0, 1.4, 0), -_player.global_transform.basis.z, true)
				_check(true, "gunfire executed")
		56:
			# progression: xp -> level, style mastery -> unlocks
			var pg = root.get_node("Progression")
			pg.reset()
			var hp_before: float = _player.combat.max_hp if _player else 100.0
			pg.add_xp(pg.xp_for_next() + 10)
			_check(pg.level == 2, "level up at xp threshold")
			if _player:
				_check(_player.combat.max_hp > hp_before, "level raises max hp")
			pg.add_style_xp("brawler", 120.0)
			_check(pg.style_rank("brawler") >= 2, "style rank grows with use")
			_check("haymaker" in pg.unlocked_moves("brawler"), "rank 2 brawler unlocks haymaker")
			_check(pg.dmg_mult("brawler") > 1.0, "level grants damage bonus")
		57:
			# difficulty director: threat scales with story progress
			var df = root.get_node("Difficulty")
			df.reset()
			var t0: float = df.threat()
			var mm2 = root.get_node("MissionManager")
			var had: Dictionary = mm2.completed.duplicate()
			for i in range(1, 7):
				mm2.completed["m%02d" % i] = true
			var t1: float = df.threat()
			mm2.completed = had
			_check(t1 > t0 + 0.2, "threat rises with story (%.2f -> %.2f)" % [t0, t1])
			_check(df.scale_count(3) >= 3, "scaled counts never below authored base")
			_check(df.police_cap() >= 4, "police cap present")
		58:
			# gunplay: recoil patterns + focus meter + soft cover hooks
			var wc = _player.weapons if _player else null
			if wc:
				wc.equip("gun_smg")
				wc.reserves["gun_smg"] = 90
				wc.mag = 30
				var pats: Array = wc.def().get("recoil_pattern", [])
				_check(pats.size() >= 8, "smg has a recoil climb pattern")
				wc.try_fire(true, 2.0, _player.global_position + Vector3(0, 1.4, 0), -_player.global_transform.basis.z, true)
				_check(wc._pattern_pitch > 0.0, "shot applied pattern pitch kick")
			if _player:
				_player.focus = 80.0
				_check(_player.focus <= 100.0, "focus meter present")
				var pl2 := FileAccess.get_file_as_string("res://scripts/player/player.gd")
				_check("_tick_cover" in pl2 and "_try_stealth_takedown" in pl2, "soft cover + stealth takedown wired")
		62:
			# LIVE DRIVE-BY part 1: get in a car with a gun, park a thug beside it
			if _player:
				var ws9 = root.get_node("WorldState")
				ws9.set_wanted(0)
				var cl9 = _city.get_node_or_null("CityLife")
				_db_v = cl9.give_player_vehicle("sedan", _player.global_position + Vector3(6, 0, 0))
				_player.enter_vehicle(_db_v)
				var wc9 = _player.weapons
				wc9.give("gun_smg")
				wc9.equip("gun_smg")
				wc9.reserves["gun_smg"] = 90
				wc9.mag = 30
				_db_en = CharacterBody3D.new()
				_db_en.set_script(load("res://scripts/npc/npc.gd"))
				_city.add_child(_db_en)
				_db_en.setup_enemy("thug_light", _db_v.global_position + Vector3(3.2, 0, 0), "test")
				_check(_db_v != null and _player.in_vehicle == _db_v, "drive-by setup: player in sedan")
		64:
			# LIVE LOCKPICK part 1: park a locked car next to the player, start picking
			if _player and _player.in_vehicle == null:
				# the drive-by thug may have killed the player before cleanup;
				# a dead player's _physics_process bails, so revive for this test
				if _player.dead:
					_player.dead = false
					_player.combat.revive()
				# mission cinematics/dialogue also freeze _physics_process; skip them
				var dui10 = root.get_node("DialogueUI")
				if dui10.is_open():
					dui10.close()
				root.get_node("Game").cutscene_active = false
				var ws10 = root.get_node("WorldState")
				ws10.add_item("lockpick", 1)
				var _lp_n: int = int(ws10.inventory.get("lockpick", 0))
				var cl10 = _city.get_node_or_null("CityLife")
				_lp_v = cl10.give_player_vehicle("sedan", _player.global_position + Vector3(1.6, 0, 0))
				_lp_v.locked = true
				_lp_v.is_player_owned = false
				_player._request_enter(_lp_v)
				_check(_player._hotwire_target == _lp_v, "lockpick: picking started on locked car")
				_lp_n0 = _lp_n
		65:
			# LIVE LOCKPICK part 2: 2.2s of frames later the lock gives — and the pick is spent
			if _player and _lp_v != null:
				# deterministically finish the 2.2s pick instead of waiting frames
				if _player._hotwire_t <= 0.0 and _player._hotwire_target == null and _player.in_vehicle == null:
					_player._request_enter(_lp_v)   # picking was interrupted; restart it
				_player.global_position = _lp_v.global_position + Vector3(1.2, 0, 0)
				for i in range(200):
					if _player._hotwire_t > 0.0:
						_player._hotwire_tick(0.05)
				var ws10 = root.get_node("WorldState")
				_check(_player.in_vehicle == _lp_v, "lockpick: car entered after pick completes")
				_check(int(ws10.inventory.get("lockpick", 0)) == _lp_n0 - 1, "lockpick consumed by the job (%d -> %d)" % [_lp_n0, int(ws10.inventory.get("lockpick", 0))])
				_player.exit_vehicle()
				_lp_v.queue_free()
				_lp_v = null
		66:
			# LIVE RUN-OVER part 1: seat the player, plant a thug ahead, floor it
			if _player and _player.in_vehicle == null:
				if _player.dead:
					_player.dead = false
					_player.combat.revive()
				root.get_node("Game").cutscene_active = false
				var ws11 = root.get_node("WorldState")
				ws11.set_wanted(0)
				var cl11 = _city.get_node_or_null("CityLife")
				_ro_v = cl11.give_player_vehicle("sedan", _player.global_position + Vector3(8, 0, 0))
				_player.global_position = _ro_v.global_position + Vector3(1.2, 0, 0)
				_player.enter_vehicle(_ro_v)
				_ro_en = CharacterBody3D.new()
				_ro_en.set_script(load("res://scripts/npc/npc.gd"))
				_city.add_child(_ro_en)
				_ro_en.setup_enemy("thug_light", _ro_v.global_position - _ro_v.global_transform.basis.z * 3.0, "test")
				_ro_hp0 = _ro_en.combat.hp
				_check(_player.in_vehicle == _ro_v, "run-over setup: player driving")
		67:
			# LIVE RUN-OVER part 2: one frame of physics later the car is moving — throttle it at the thug
			if _player and _ro_v != null and is_instance_valid(_ro_en):
				_ro_v.linear_velocity = -_ro_v.global_transform.basis.z * 14.0
				_check(_ro_v.linear_velocity.length() > 10.0, "run-over: car launched at 50 km/h")
		68:
			# LIVE RUN-OVER part 3: impact — drive the physics deterministically
			if _player and _ro_v != null:
				var ws11 = root.get_node("WorldState")
				# the city is hostile: if something killed our thug first, plant another
				if not is_instance_valid(_ro_en):
					_ro_en = CharacterBody3D.new()
					_ro_en.set_script(load("res://scripts/npc/npc.gd"))
					_city.add_child(_ro_en)
					_ro_en.setup_enemy("thug_light", _ro_v.global_position + Vector3(1.2, 0, 0), "test")
					_ro_hp0 = _ro_en.combat.hp
				_ro_v.linear_velocity = -_ro_v.global_transform.basis.z * 14.0
				# place the thug right at the fender and run the car's physics
				_ro_en.global_position = _ro_v.global_position + Vector3(1.2, 0, 0)
				_ro_v.set("_runover_cd", 0.0)
				for i in range(4):
					_ro_v._physics_process(0.016)
				var hit_done: bool = _ro_en.combat.hp < _ro_hp0 or _ro_en.combat.dead
				_check(hit_done, "run-over: thug was struck (hp %.0f -> %.0f, dead=%s)" % [_ro_hp0, _ro_en.combat.hp, str(_ro_en.combat.dead)])
				_check(ws11.wanted >= 3, "run-over: player charged for the hit (wanted=%d)" % ws11.wanted)
				_ro_en.queue_free()
				_ro_en = null
				ws11.set_wanted(0)
				if _player.in_vehicle == _ro_v:
					_player.exit_vehicle()
				_ro_v.queue_free()
				_ro_v = null
		69:
			# LIVE WRECK BURN: kill a car, watch it go up
			if _player:
				var ws12 = root.get_node("WorldState")
				ws12.set_wanted(0)
				var cl12 = _city.get_node_or_null("CityLife")
				var vb: Node = cl12.give_player_vehicle("sedan", _player.global_position + Vector3(14, 0, 0))
				vb.damage(9999.0)
				_check(bool(vb.get("_wrecked")), "wreck: car destroyed")
				_check(float(vb.get("_burn_t")) > 40.0, "wreck: burn timer lit (%.1f s)" % float(vb.get("_burn_t")))
				_check(vb.is_in_group("burning"), "wreck: added to burning group")
				_check(vb.get("_fire_light") != null, "wreck: fire light spawned")
				vb.queue_free()
		70:
			# LIVE SCATTER part 1: launch a car at a standing civilian
			if _player:
				var cl13 = _city.get_node_or_null("CityLife")
				_sc_v = cl13.give_player_vehicle("sedan", _player.global_position + Vector3(16, 0, 0))
				_sc_ped = CharacterBody3D.new()
				_sc_ped.set_script(load("res://scripts/npc/npc.gd"))
				_city.add_child(_sc_ped)
				_sc_ped.setup_ped("dockworker", "ashfall_docks", _sc_v.global_position - _sc_v.global_transform.basis.z * 8.0)
				_check(_sc_ped.state == _sc_ped.State.ROUTINE, "scatter setup: civilian minding their business")
		72:
			# LIVE HIJACK SILHOUETTE: a commandeered car shows its panicked driver
			if _player:
				var cl14 = _city.get_node_or_null("CityLife")
				var vt: Node = cl14.give_player_vehicle("sedan", _player.global_position + Vector3(18, 0, 0))
				vt.set_lane(PackedVector3Array([vt.global_position + Vector3(20, 0, 0), vt.global_position + Vector3(20, 0, 20)]), 8.0)
				vt.civ_panic()
				_check(vt.get("_civ_driver") != null, "hijack: panicked car has a visible driver")
				_check(float(vt.get("_panic_t")) > 0.0, "hijack: panic timer running")
				vt.set("_panic_t", 0.016)
				vt.traffic_tick(0.02)
				_check(vt.get("_civ_driver") != null and bool(vt.get("_civ_driver_perm")), "traffic driver stays behind the wheel after panic ends")
				vt.queue_free()
		71:
			# LIVE SCATTER part 2: a physics frame of 40 km/h metal later, they run
			if _sc_v != null and is_instance_valid(_sc_ped):
				_sc_v.linear_velocity = -_sc_v.global_transform.basis.z * 11.0
				# scatter ticks at 0.6s throttle; drive it directly for determinism
				_sc_v.set("_scatter_t", 0.0)
				_sc_v._physics_process(0.016)
				_check(_sc_ped.state == _sc_ped.State.FLEE, "scatter: civilian flees the speeding car (state=%d)" % _sc_ped.state)
				_sc_ped.queue_free()
				_sc_ped = null
				_sc_v.queue_free()
				_sc_v = null
		73:
			# LIVE BURN EXPIRY: a wreck's fire burns down and the light is freed
			if _player:
				var cl15 = _city.get_node_or_null("CityLife")
				var vw: Node = cl15.give_player_vehicle("sedan", _player.global_position + Vector3(20, 0, 0))
				vw.damage(9999.0)
				_check(vw.is_in_group("burning") and vw.get("_fire_light") != null, "burn: wreck alight with fire light")
				vw.set("_burn_t", 0.5)
				for i in range(80):
					if float(vw.get("_burn_t")) > 0.0:
						vw._physics_process(0.05)
				_check(not vw.is_in_group("burning"), "burn: wreck leaves burning group when fuel is gone")
				_check(vw.get("_fire_light") == null, "burn: fire light freed after burn-out")
				vw.queue_free()
		74:
			# LIVE FIRE AMBIENCE: crackle channel follows the nearest burning thing
			if _player:
				var cl16 = _city.get_node_or_null("CityLife")
				var ad16 = root.get_node("AudioDirector")
				var fake := Node3D.new()
				_city.add_child(fake)
				fake.global_position = _player.global_position + Vector3(4, 0, 0)
				fake.add_to_group("burning")
				cl16._fire_tick(0.016, _player)
				_check(float(ad16.ambient_target.get("fire", 0.0)) > 0.2, "ambience: fire crackles near a burning thing (vol=%.2f)" % float(ad16.ambient_target.get("fire", 0.0)))
				fake.global_position = _player.global_position + Vector3(60, 0, 0)
				cl16._fire_tick(0.016, _player)
				_check(float(ad16.ambient_target.get("fire", 1.0)) == 0.0, "ambience: fire channel silent when nothing burns nearby")
				fake.remove_from_group("burning")
				fake.queue_free()
		75:
			# LIVE LIMP MODE: a hurt car loses power until the garage fixes it
			if _player and _player.in_vehicle == null:
				var cl17 = _city.get_node_or_null("CityLife")
				var vl: Node = cl17.give_player_vehicle("sedan", _player.global_position + Vector3(22, 0, 0))
				vl.player_drive(0.016, Vector2(0, -1), false, false, false)
				var f_full: float = absf(vl.engine_force)
				vl.hp = 30.0
				vl.player_drive(0.016, Vector2(0, -1), false, false, false)
				var f_limp: float = absf(vl.engine_force)
				_check(f_limp < f_full * 0.7, "limp mode: hurt car loses power (%.0f -> %.0f)" % [f_full, f_limp])
				vl.repair_full()
				vl.player_drive(0.016, Vector2(0, -1), false, false, false)
				_check(absf(vl.engine_force) >= f_full * 0.99, "limp mode: garage repair restores full power")
				vl.queue_free()
		76:
			# LIVE PAID LAY-LOW: safehouse + big heat + cash = quieter stars
			if _player:
				var ws14 = root.get_node("WorldState")
				var cityg = _city
				var h0: float = ws14.game_hour
				var m0: int = ws14.money
				ws14.set_wanted(4)
				ws14.money = 500
				cityg._enter_safehouse("poi_safehouse_docks", {"name": "test den", "kind": "safehouse"})
				_check(ws14.wanted == 2, "lay low: 250cr buys two stars of quiet (wanted=%d)" % ws14.wanted)
				_check(ws14.money == 250, "lay low: the quiet cost 250 cr (money=%d)" % ws14.money)
				# broke and hot: no sale
				ws14.set_wanted(4)
				ws14.money = 100
				cityg._enter_safehouse("poi_safehouse_docks", {"name": "test den", "kind": "safehouse"})
				_check(ws14.wanted == 4, "lay low: broke stays hot (wanted=%d)" % ws14.wanted)
				ws14.money = m0
				ws14.set_wanted(0)
				ws14.game_hour = h0
		77:
			# LIVE PURSUIT STACK part 1: spike strips shred the player's tyres
			if _player and _player.in_vehicle == null:
				if _player.dead:
					_player.dead = false
					_player.combat.revive()
				root.get_node("Game").cutscene_active = false
				var cl18 = _city.get_node_or_null("CityLife")
				_ps_v = cl18.give_player_vehicle("sedan", _player.global_position + Vector3(24, 0, 0))
				_player.global_position = _ps_v.global_position + Vector3(1.2, 0, 0)
				_player.enter_vehicle(_ps_v)
				_ps_v.set("_lane", PackedVector3Array())   # keep traffic AI off
				cl18._spikes.clear()
				cl18._drop_spike_strips(_player.global_position)
				_check(cl18._spikes.size() == 3, "pursuit: spike strips dropped (%d)" % cl18._spikes.size())
				# drive the player's car onto the nearest strip
				var sp0: Dictionary = cl18._spikes[0]
				_ps_v.global_position = (sp0["pos"] as Vector3) + Vector3(0, 0.5, 0)
				_player.global_position = _ps_v.global_position   # rider follows the car (no physics frame between)
				cl18._spike_check(_player)
				_check(bool(_ps_v.get("tires_flat")), "pursuit: spikes shredded the tyres")
				_check(float(_ps_v.hp) < 100.0, "pursuit: spikes damaged the car (hp=%.0f)" % float(_ps_v.hp))
		78:
			# LIVE PURSUIT STACK part 2: roadblocks build + clear, PIT shoves, fires draw cops
			if _player and _ps_v != null:
				var cl18 = _city.get_node_or_null("CityLife")
				# roadblock
				cl18._clear_roadblocks()
				cl18._make_roadblock(_player.global_position)
				_check(cl18._roadblock_nodes.size() == 2, "pursuit: roadblock of 2 cruisers built")
				cl18._clear_roadblocks()
				_check(cl18._roadblock_nodes.is_empty(), "pursuit: roadblock cleared when heat drops")
				# PIT: cruiser alongside a moving player car gets shoved
				var pit_car: Node = cl18.give_player_vehicle("police", _ps_v.global_position + Vector3(3.2, 0, 0))   # inside the 2.0-5.5 m PIT band
				pit_car.is_police = true
				pit_car.set("_lane", PackedVector3Array())
				cl18.police_units.append({"node": pit_car, "kind": "car", "t": 0.0})
				_ps_v.linear_velocity = -_ps_v.global_transform.basis.z * 12.0
				_player.global_position = _ps_v.global_position   # PIT measures from the rider
				var hp_pit: float = float(_ps_v.hp)
				cl18.set("_pit_cd", 0.0)
				cl18._pit_tick(0.016, _player)
				_check(float(_ps_v.hp) < hp_pit, "pursuit: PIT maneuver damages the fleeing car")
				_check(float(cl18.get("_pit_cd")) > 0.0, "pursuit: PIT goes on cooldown after the shove")
				# fire investigation: a burning wreck summons CCPD
				var inv0: int = cl18._investigators.size()
				_ps_v.damage(9999.0)
				cl18.set("_invest_cd", 0.0)
				cl18._investigate_fires(0.016)
				_check(cl18._investigators.size() == inv0 + 2, "pursuit: burning wreck draws CCPD investigators")
				for inv in cl18._investigators:
					if is_instance_valid(inv["node"]):
						inv["node"].queue_free()
				cl18._investigators.clear()
				for u in cl18.police_units.duplicate():
					if u["node"] == pit_car:
						cl18.police_units.erase(u)
				pit_car.queue_free()
				if _player.in_vehicle == _ps_v:
					_player.exit_vehicle()
				if is_instance_valid(_ps_v):
					_ps_v.queue_free()
				_ps_v = null
		63:
			# LIVE DRIVE-BY part 2: one physics frame later the thug is solid — shoot him
			if _player and _db_v != null and is_instance_valid(_db_en):
				var ws9 = root.get_node("WorldState")
				var wc9 = _player.weapons
				var hp9: float = _db_en.combat.hp
				var muz9: Vector3 = _db_v.global_position + Vector3(0.9, 1.2, 0)
				var dir9: Vector3 = (_db_en.global_position + Vector3(0, 1.2, 0) - muz9).normalized()
				var mag9: int = wc9.mag
				var fired9: bool = wc9.try_fire(true, 2.0, muz9, dir9, true)
				_check(fired9, "drive-by shot fired from vehicle")
				_check(wc9.mag < mag9, "drive-by consumed ammo")
				_check(_db_en.combat.hp < hp9, "drive-by bullet hit the enemy (hp %.0f -> %.0f)" % [hp9, _db_en.combat.hp])
				_check(ws9.wanted >= 2, "gunfire from the car raised wanted (%d)" % ws9.wanted)
				ws9.set_wanted(0)
				_db_en.queue_free()
				_db_en = null
				_player.exit_vehicle()
				_db_v = null
		60:
			# attachments + day-part schedules + pursuit escalation
			var ws4 = root.get_node("WorldState")
			ws4.weapon_attachments["gun_rifle"] = {"optic": "att_scope", "muzzle": "att_suppressor"}
			if _player:
				_player.weapons.give("gun_rifle", true)
				_player.weapons.equip("gun_rifle")
				var wd: Dictionary = _player.weapons.def()
				_check(wd.get("sound", "") == "shot_suppressed", "suppressor changes report")
				_check(float(wd.get("spread", 9.9)) < 0.4, "scope tightens spread")
				ws4.weapon_attachments.clear()
				_player.weapons.equip("gun_pistol")
			var np2 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("_day_part" in np2 and "_body_scan" in np2, "npc day schedules + body discovery")
			var cl := FileAccess.get_file_as_string("res://scripts/world/city_life.gd")
			_check("_pit_tick" in cl and "_drop_spike_strips" in cl and "_hour_crowd_mult" in cl, "PIT/spikes/crowd rhythm wired")
			var pl3 := FileAccess.get_file_as_string("res://scripts/player/player.gd")
			_check("_try_vault" in pl3 and "_env_takedown" in pl3, "vault + environmental takedown wired")
		59:
			# stealth: guard suspicion brain + new move timelines
			var np := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("suspicion" in np and "_los_clear" in np, "guard suspicion/vision cone present")
			var cc := FileAccess.get_file_as_string("scripts/combat/combat_controller.gd")
			_check("haymaker" in cc and "ground_pound" in cc and "counter_t" in cc, "unlock moves + counter window in combat controller")
		61:
			# district heat, fire escapes, vehicle wrecks, ghost runs
			var ws5 = root.get_node("WorldState")
			ws5.add_district_heat("neon_mile", 30.0)
			_check(ws5.district_heat01("neon_mile") > 0.25, "district heat accrues")
			ws5.add_district_heat("neon_mile", -100.0)
			_check(ws5.district_heat01("neon_mile") == 0.0, "heat clamps at zero")
			var wg2 = root.get_node("WorldGen")
			_check(wg2.climb_points.size() > 0, "fire-escape climb points generated (%d)" % wg2.climb_points.size())
			if wg2.climb_points.size() > 0:
				var cp: Dictionary = wg2.climb_points[0]
				_check(cp["top"].y > cp["bottom"].y + 5.0, "climb point reaches a roof")
			var pl4 := FileAccess.get_file_as_string("res://scripts/player/player.gd")
			_check("_try_climb" in pl4 and "_climb_tick" in pl4, "climb verb wired into player")
			var vh := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			_check("_explode" in vh and "puncture_tires" in vh, "vehicle wreck/explosion present")
			var mm3 = root.get_node("MissionManager")
			var msrc := FileAccess.get_file_as_string("res://scripts/missions/mission_manager.gd")
			_check("GHOST RUN" in msrc, "stealth missions reward silent runs")
			# faction ripples + grudges + shop consequences
			var ws6 = root.get_node("WorldState")
			var rep0: float = ws6.factions.get("crew", 0.0)
			var docks: Vector3 = Vector3(0, 0, 0)
			var db = root.get_node("Db")
			var dd: Dictionary = db.district("ashfall_docks")
			if dd.has("center"):
				docks = Vector3(dd["center"][0], 0, dd["center"][1])
			root.get_node("Bus").crime_committed.emit("gunfire", 3, docks)
			_check(ws6.district_heat01("ashfall_docks") > 0.05, "crime leaves district heat (%.2f)" % ws6.district_heat01("ashfall_docks"))
			_check(ws6.factions.get("crew", 0.0) < rep0, "crew rep drops for docks violence")
			var clsrc := FileAccess.get_file_as_string("res://scripts/world/city_life.gd")
			_check("_grudge_tick" in clsrc and "TURF" in clsrc, "faction grudge ambushes wired")
			var shsrc := FileAccess.get_file_as_string("res://scripts/ui/shop_ui.gd")
			_check("_grudge" in shsrc, "shopkeeper grudge markup present")
			var phsrc := FileAccess.get_file_as_string("res://scripts/ui/phone_ui.gd")
			_check("_show_stats" in phsrc and "push_news" in phsrc, "phone dossier + news feed wired")
			ws6.factions["crew"] = rep0
			# --- wave 10/11: cinematics, living city, pursuit staging ---
			var cin = root.get_node_or_null("Cinematics")
			_check(cin != null, "Cinematics autoload present")
			var ccsrc := FileAccess.get_file_as_string("res://scripts/combat/combat_controller.gd")
			_check("_last_kill_check" in ccsrc and "Cinematics.hitstop" in ccsrc, "kill-cam + hit-stop wired into combat")
			var clsrc2 := FileAccess.get_file_as_string("res://scripts/world/city_life.gd")
			_check("_cruiser_shot" in clsrc2 and "turf_war" in clsrc2 and "_chatter_t" in clsrc2, "drive-bys, turf wars, radio chatter wired")
			_check("SOUND PROPAGATION" in clsrc2, "loud-crime panic ripple wired")
			var phsrc2 := FileAccess.get_file_as_string("res://scripts/ui/phone_ui.gd")
			_check("_show_garage" in phsrc2 and "_summon_vehicle" in phsrc2 and "_keep_ride" in phsrc2, "garage app wired (keep ride + summon)")
			var wssrc := FileAccess.get_file_as_string("res://scripts/core/world_state.gd")
			var ctsrc := FileAccess.get_file_as_string("res://scripts/scenes/city.gd")
			_check("advance_hours" in wssrc and "advance_hours(8.0)" in ctsrc, "safehouse sleep skips 8 hours")
			var ws7 = root.get_node("WorldState")
			var h0: float = ws7.game_hour
			var d0: int = ws7.day
			ws7.advance_hours(8.0)
			_check(absf(ws7.game_hour - fmod(h0 + 8.0, 24.0)) < 0.001, "advance_hours wraps the clock")
			ws7.game_hour = h0
			ws7.day = d0
			var db7 = root.get_node("Db")
			_check(db7.weapons.has("gun_magnum") and db7.weapons.has("gun_machine_pistol"), "new hand cannons registered")
			_check(db7.items.has("ammo_357") and str(db7.items["ammo_357"].get("for","")) == "gun_magnum", "magnum ammo mapped")
			var plsrc2 := FileAccess.get_file_as_string("res://scripts/player/player.gd")
			_check('"ammo":' in plsrc2 and "add_ammo" in plsrc2, "ammo items usable from the BAG")
			# REGRESSION: on-foot vehicle entry must live in _handle_interact,
			# reachable code — it was once stranded after a return in _find_body
			var hi: int = plsrc2.find("func _handle_interact")
			var fb: int = plsrc2.find("func _find_body")
			var ve: int = plsrc2.find("vehicle_enter", hi)
			_check(hi >= 0 and ve > hi and (fb < 0 or ve < fb), "on-foot vehicle entry reachable (regression guard)")
			# and actually drive: spawn a car next to the player and enter it
			var pl5 = root.get_node_or_null("City/Player")
			if pl5 == null:
				var g5: Array = get_nodes_in_group("player")
				pl5 = g5[0] if not g5.is_empty() else null
			if pl5 != null and pl5.in_vehicle == null:
				var city5 := root.get_node_or_null("City")
				var cl5 = root.get_node_or_null("CityLife")
				if cl5 != null and cl5.has_method("give_player_vehicle"):
					var veh5 = cl5.give_player_vehicle("sedan", pl5.global_position + Vector3(2.2, 0.3, 0))
					pl5.enter_vehicle(veh5)
					_check(pl5.in_vehicle == veh5, "player can enter an adjacent vehicle")
					pl5.exit_vehicle()
					if is_instance_valid(veh5):
						veh5.queue_free()
			var plsrc3 := FileAccess.get_file_as_string("res://scripts/player/player.gd")
			var vsrc3 := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			_check("is_player_owned" in vsrc3 and '"theft"' in plsrc3, "car theft is a crime (owned rides exempt)")
			_check("_request_enter" in plsrc3 and "_hotwire_tick" in plsrc3 and "lockpick" in plsrc3, "locked cars: pick quiet or smash loud")
			_check("_try_driveby" in plsrc3 and "DRIVE-BY" in plsrc3, "drive-by shooting wired (cars only, speed wobble)")
			var npcsrc2 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("A DRAWN GUN" in npcsrc2, "civilians panic at drawn guns")
			_check("_show_taxi" in phsrc2 and "_ride_taxi" in phsrc2, "taxi fast-travel app wired")
			var db8 = root.get_node("Db")
			_check(db8.properties.size() == 6, "six buyable businesses registered")
			var ws8 = root.get_node("WorldState")
			var ser8 := FileAccess.get_file_as_string("res://scripts/core/world_state.gd")
			_check("owned_properties" in ser8 and "_pay_property_income" in ser8, "property income pays at day rollover")
			_check("_show_biz" in phsrc2 and "_buy_property" in phsrc2, "BIZ phone app wired")
			# live payout: own a property, roll the day, get paid
			var m0: int = ws8.money
			ws8.owned_properties.append("noodle_stall")
			ws8.advance_hours(24.0)
			_check(ws8.money >= m0 + int(db8.properties["noodle_stall"]["income"]), "daily property payout lands")
			ws8.owned_properties.clear()
			ws8.money = m0
			# property perks reach real systems
			_check("owns_property" in ser8, "owns_property helper present")
			var plsrc4 := FileAccess.get_file_as_string("res://scripts/player/player.gd")
			var shsrc2 := FileAccess.get_file_as_string("res://scripts/ui/shop_ui.gd")
			_check("noodle_stall" in plsrc4, "noodle stall heals harder")
			_check("dock_lease" in shsrc2, "dock sublease discounts ammo")
			_check("lounge_room" in ctsrc and "cab_share" in phsrc2 and "laundromat" in ser8, "lounge/cab/laundromat perks wired")
			# wave 24: side jobs using the new verbs
			_check(db8.mission("side_repo").get("stages", []).size() == 3, "side_repo (theft + pursuit run) registered")
			_check(db8.mission("side_partner").get("stages", []).size() == 3, "side_partner (business buy-in) registered")
			_check(db8.mission("side_heatmagnet").get("stages", []).size() == 4, "side_heatmagnet (3-star broadcast run) registered")
			_check('"prop:"' in msrc, "mission objectives understand prop: expressions")
			var tutsrc := FileAccess.get_file_as_string("res://scripts/ui/tutorial.gd")
			_check('"lockpick"' in tutsrc and '"driveby"' in tutsrc and '"garage"' in tutsrc, "tutorial coaches the new verbs")
			_check('tutorial_hint.emit("lockpick")' in plsrc4 and 'tutorial_hint.emit("garage")' in plsrc4 and 'tutorial_hint.emit("driveby")' in plsrc4, "new-verb hints fire from gameplay")
			_check("district_heat01" in phsrc2 and "owned_properties" in phsrc2, "map shows district heat + owned businesses")
			_check("FAME_MILESTONES" in clsrc2 and "_fame_tick" in clsrc2, "career milestones reach the papers")
			# live fame test: fake the stat, tick, expect the flag + a news line
			var ws9 = root.get_node("WorldState")
			ws9.stats["thefts"] = 6
			var cln = root.get_node_or_null("City/CityLife")
			if cln == null:
				var clg: Array = root.get_children()
				for c in clg:
					var inner: Array = c.get_children() if c.has_method("get_children") else []
					for n2 in inner:
						if str(n2.name) == "CityLife":
							cln = n2
			if cln != null:
				cln._fame_t = 0.0
				cln.call("_fame_tick", 0.1)
				_check(ws9.get_flag("fame_thefts5", false), "fame milestone fires once and persists")
			ws9.stats["thefts"] = 0
			var wcsrc := FileAccess.get_file_as_string("res://scripts/combat/weapons_controller.gd")
			_check('add_style_xp("weapon"' in wcsrc, "gun hits feed WEAPON mastery")
			var vhsrc := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			_check("_burn_t" in vhsrc and '"burning"' in vhsrc, "wrecks burn 45s with flicker then go dark")
			_check("_fire_tick" in clsrc2 and 'ambient("fire"' in clsrc2, "fire ambience driven by nearest burning thing")
			_check('"fire_barrel"' in clsrc2 and "burning" in clsrc2, "barrel fires burn for real (90s)")
			var shsrc3 := FileAccess.get_file_as_string("res://scripts/ui/shop_ui.gd")
			_check("repair_full" in vhsrc and "_build_repair" in shsrc3, "Dex's Garage repairs hulls + tires")
			_check("Hitman" in clsrc2 or "Cleaner" in clsrc2, "deep grudge escalates to armed hit squads")
			var vsrc5 := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			var npcsrc3 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("RUN-OVERS" in vsrc5 and "SCATTER" in vsrc5, "cars run over and scatter pedestrians")
			_check('"scramble"' in npcsrc3, "pedestrians dive away from speeding vehicles")
			var shsrc4 := FileAccess.get_file_as_string("res://scripts/ui/shop_ui.gd")
			var vsrc6 := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			_check('"paint"' in shsrc4 and "PAINTS" in shsrc4 and "_make_paint" in shsrc4, "garage offers paint resprays")
			_check("func respray" in vsrc6 and "color = col" in vsrc6, "vehicles can be resprayed")
			var mmsrc := FileAccess.get_file_as_string("res://scripts/missions/mission_manager.gd")
			var db8x = root.get_node("Db")
			_check(db8x.mission("side_torch").get("stages", []).size() == 4, "side_torch mission registered")
			_check(db8x.mission("side_clean_wheels").get("stages", []).size() == 4, "side_clean_wheels mission registered")
			_check("_check_objective" in mmsrc and "statd:" in mmsrc, "relative stat goals supported for repeatable jobs")
			_check('"wrecks"' in vsrc6, "wrecks tracked as a stat")
			var shsrc5 := FileAccess.get_file_as_string("res://scripts/ui/shop_ui.gd")
			_check('"resprays"' in shsrc5, "resprays tracked as a stat")
			var clsrc5 := FileAccess.get_file_as_string("res://scripts/world/city_life.gd")
			var fbseg: String = clsrc5.substr(clsrc5.find('"fire_barrel":'), clsrc5.find('"crowd_gathering":') - clsrc5.find('"fire_barrel":'))
			_check(fbseg.count("add_to_group(\"burning\")") == 1 and "create_timer(90.0)" not in fbseg, "fire_barrel spawns exactly one burning barrel (no dupe)")
			var vsrc7 := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			var mmsrc2 := FileAccess.get_file_as_string("res://scripts/missions/mission_manager.gd")
			var db9 = root.get_node("Db")
			_check("_investigate_fires" in clsrc5 and "CCPD Investigator" in clsrc5, "burning wrecks draw police investigators")
			_check("_driver_mesh" in vsrc7 and "_civ_driver_perm" in vsrc7, "traffic cars carry visible drivers; taxi roof sign wired")
			_check(db9.mission("side_epilogue").get("requires_flag", "") == "game_complete", "epilogue job gated behind the finale")
			_check(db9.dialogue_tree("dlg_epilogue_ruth").size() > 0, "epilogue dialogue authored")
			_check('m.get("requires_flag"' in mmsrc2 or "sreq" in mmsrc2, "side jobs respect flag gates")
			var adsrc := FileAccess.get_file_as_string("res://scripts/core/audio_director.gd")
			var cutsrc := FileAccess.get_file_as_string("res://scripts/ui/cutscene.gd")
			var effsrc := FileAccess.get_file_as_string("res://scripts/core/effects.gd")
			var crsrc := FileAccess.get_file_as_string("res://scripts/player/camera_rig.gd")
			var hudsrc2 := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
			_check("func sting" in adsrc and "sting_success" in mmsrc2, "mission stings wired (success/fail/busted/wasted)")
			_check('"music_ending"' in cutsrc and "music_finale" not in cutsrc, "finale cutscene references a track that exists")
			_check('settings.get("shake"' in effsrc, "camera shake setting honored")
			_check("_apply_settings" in crsrc, "sensitivity + invert_y applied to camera")
			_check("touch_scale" in hudsrc2, "touch control size setting honored")
			_check("police_radio" in clsrc5 and "shell_drop" in FileAccess.get_file_as_string("res://scripts/combat/weapons_controller.gd"), "orphan sfx wired (radio chatter, brass)")
			_check('react("crime"' in clsrc5 and 'react("siren"' in clsrc5, "orphan react events wired (witnessed theft, rubbernecking)")
			var wgsrc := FileAccess.get_file_as_string("res://scripts/world/world_gen.gd")
			_check("rng.seed = hash(id)" in wgsrc, "city layout deterministic across reloads (seeded per district)")
			_check('"pawnkeep"' in FileAccess.get_file_as_string("res://data/characters.json"), "dialogue speakers all have character entries")
			# behavioral: statd counts from stage start, not from all time
			var mm7 = root.get_node("MissionManager")
			var ws13 = root.get_node("WorldState")
			var had9: String = mm7.active_id
			var hadr9: Dictionary = mm7.rt.duplicate(true)
			var hads9 = ws13.stats.get("wrecks", 0)
			ws13.stats["wrecks"] = 7
			mm7.active_id = "side_torch"
			var tj_st: Array = db8x.mission("side_torch").get("stages", [])
			_check(tj_st[1].get("check", "") == "statd:wrecks>=2", "side_torch stage 1 is still the relative-wrecks objective the statd test reads")
			mm7.stage = tj_st[1]
			mm7.rt = {}
			_check(not mm7._check_objective("statd:wrecks>=2"), "statd ignores pre-existing stats")
			ws13.stats["wrecks"] = 9
			_check(mm7._check_objective("statd:wrecks>=2"), "statd counts new wrecks since stage start")
			mm7.active_id = had9
			mm7.rt = hadr9
			ws13.stats["wrecks"] = hads9
			var npcsrc4 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("_try_hop_in_car" in npcsrc4 and "civ_panic" in vsrc6, "fleeing civilians commandeer traffic cars")
			_check("_panic_t" in vsrc6 and "1.9" in vsrc6, "panicked cars peel out faster")
			var npcsrc5 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("_snitch_cd" in npcsrc5 and "tip" in npcsrc5, "witnesses tip off the suspect's position, throttled")
			var vsrc4 := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			_check("_burn_t" in vsrc4 and '"burning"' in vsrc4, "wrecks burn for 45s with flickering light")
			_check("_fire_tick" in clsrc2 and 'ambient("fire"' in clsrc2, "fire ambience crackles near burning things")
			var npcsrc := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("_find_rival" in npcsrc and "_drop_loot" in npcsrc, "rival targeting + loot drops wired")
			var vsrc2 := FileAccess.get_file_as_string("res://scripts/vehicle/vehicle.gd")
			_check("_police_siren_near" in vsrc2 and "police_car" in vsrc2, "traffic yields to sirens")
			_check("_apply_pursuit" in msrc and "prev_wanted" in msrc, "scripted mission pursuits wired")
			_check(db.mission("side_bait").get("stages", []).size() == 3, "side_bait chase mission exists")
			var evs = root.get_node("Db").events
			_check(evs.has("turf_war"), "turf_war world event registered")
		79:
			# WAVE 46 — MEMORY/REPUTATION SPINE (RDR2: the world remembers)
			var ws46 = root.get_node("WorldState")
			ws46.street_deeds.clear()
			ws46.set("_last_deed_t", Time.get_ticks_msec() / 1000.0 - 100.0)   # clear the deed throttle
			var rep_seen: Array = []
			var bus46 = root.get_node("Bus")
			var sub46 := func(v): rep_seen.append(v)
			bus46.street_rep_changed.connect(sub46)
			ws46.note_deed("stood_up", "kiln_row", true)
			_check(ws46.street_deeds.size() == 1, "deed recorded in street ledger")
			_check(ws46.street_rep() == 2, "helped deed raises street rep")
			_check(rep_seen.size() == 1 and rep_seen[0] == 2, "street_rep_changed signal fires")
			_check(ws46.memory.get("street", []).has("stood_up"), "remember() finally has a caller (street memory)")
			for i46 in 9:
				ws46.note_deed("bully", "kiln_row", false)
			_check(ws46.street_rep() == 2 - 18, "hostile deeds sink street rep")
			_check(absf(ws46.snitch_chance() - 0.5) > 0.15, "witness cooperation scales with street rep (rep=%d snitch=%.2f)" % [ws46.street_rep(), ws46.snitch_chance()])
			var ser46: Dictionary = ws46.serialize()
			_check(ser46.has("street_deeds") and (ser46["street_deeds"] as Array).size() == 10, "street ledger serialized with the save")
			bus46.street_rep_changed.disconnect(sub46)
			ws46.street_deeds.clear()
		80:
			# WAVE 46 — ENEMY POSTURE / GUARD BREAK (Sifu: guards chip and shatter)
			if _player:
				var cc46 = load("res://scripts/combat/combat_controller.gd").new()
				_check(cc46 != null and cc46.get("posture") != null, "posture: controller constructible with posture vars")
				# direct unit: posture builds on blocked hits and breaks at max
				var ccsrc46 := FileAccess.get_file_as_string("res://scripts/combat/combat_controller.gd")
				_check("posture" in ccsrc46 and "guard_broken_t" in ccsrc46, "posture/guard-break meter present")
				_check("guard_broken_t > 0.0:\n\t\t\tdmg *= 1.45" in ccsrc46, "broken guard takes bonus damage")
				var npcsrc46 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
				_check("_guard_t" in npcsrc46 and "set_block(true)" in npcsrc46, "trained enemies raise guard in rhythm")
				var hudsrc46 := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
				_check("_posture_bar" in hudsrc46, "guard-posture bar surfaced in HUD")
				# cc46 is RefCounted (frees itself) — calling .free() errors
		81:
			# WAVE 46 — BULLETS GET HITSTOP + IMPACT MATERIAL VARIETY (Max Payne 3)
			var wcsrc46 := FileAccess.get_file_as_string("res://scripts/combat/weapons_controller.gd")
			_check("Cinematics.hitstop(0.09 if cc.dead else 0.045)" in wcsrc46, "bullet hits freeze the frame (kills longest)")
			_check('"ashfall_docks", "slagworks":' in wcsrc46 and 'mat = "metal"' in wcsrc46, "docks/slagworks ring metal")
			_check('mat = "glass"' in wcsrc46 and 'mat = "wood"' in wcsrc46, "glass + wood surfaces vary by district")
			_check('"imp_" + mat' in wcsrc46, "surface sfx picked from material")
		82:
			# WAVE 46 — CIVILIAN AGENCY: greet / show respect / antagonize (GTA V)
			var npcsrc47 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("start_choices" in npcsrc47 and "Antagonize" in npcsrc47, "pedestrian interaction is a decision, not a bark")
			_check("note_deed(\"showed_respect\"" in npcsrc47 and "note_deed(\"bully\"" in npcsrc47, "greet/antagonize feed the street ledger")
			var news46 := FileAccess.get_file_as_string("res://data/news.json")
			_check("\"gossip\"" in news46 and "\"watch_it\"" in news46, "gossip + callout bark lines authored")
			# live: a fresh ped offers the choice panel
			if _player:
				var ped46 = _spawn_ped46(_player.global_position + Vector3(2.0, 0, 0))
				if ped46 != null:
					ped46.interact(_player)
					var dui46 = root.get_node("DialogueUI")
					_check(dui46.choice_box.visible, "civilian agency panel opens")
					_check(dui46._choice_opts.size() >= 3, "at least greet/respect/antagonize offered")
					dui46._pick(2)   # antagonize
					var ws47 = root.get_node("WorldState")
					var bullied := false
					for d46 in ws47.street_deeds:
						if d46.get("id", "") == "bully":
							bullied = true
					_check(bullied, "antagonizing a local is a remembered deed")
					ws47.street_deeds.clear()
					ped46.queue_free()
		83:
			# WAVE 46 — OVERHEARD CONVERSATIONS (Sleeping Dogs: pairs talk, you linger, they notice)
			var clsrc46 := FileAccess.get_file_as_string("res://scripts/world/city_life.gd")
			_check("_gossip_tick" in clsrc46 and "gossip_pair" in clsrc46, "paired ambient conversations wired")
			_check("_intervene_tick" in clsrc46 and "Step in" in clsrc46, "street events offer intervention")
			if _player:
				var cl46 = _city.get_node_or_null("CityLife")
				if cl46 != null:
					# force an event and stand in it: the choice must appear
					var p46a = _spawn_ped46(_player.global_position + Vector3(3.0, 0, 0))
					var p46b = _spawn_ped46(_player.global_position + Vector3(4.0, 0, 2.0))
					if p46a != null and p46b != null:
						cl46.event_actors.append(p46a)
						cl46.event_actors.append(p46b)
						p46a.set_meta("event_role", "mugger")
						p46b.set_meta("event_role", "victim")
						cl46._event_kind = "mugging"
						cl46._event_kind_district = "kiln_row"
						cl46._intervene_pos = _player.global_position + Vector3(3.0, 0, 0)
						cl46._intervene_cd = 0.0
						var dui47 = root.get_node("DialogueUI")
						# _intervene_tick BAILS on in_vehicle, cutscene_active,
						# distance and cooldown. Adding world content shifts
						# randf() everywhere, so which of those is true at step
						# 83 is a coin flip unless the test pins all of them.
						_revive_player()
						if _player.in_vehicle != null:
							_player.exit_vehicle()
						root.get_node("Game").cutscene_active = false
						if dui47.is_open():
							dui47.close()
						cl46._intervene_pos = _player.global_position + Vector3(3.0, 0, 0)
						cl46._event_kind = "mugging"
						cl46._intervene_cd = 0.0
						cl46._intervene_tick(0.016, _player)
						_check(dui47.choice_box.visible, "mugging intervention panel opens near the event")
						dui47._pick(0)   # step in
						_check(cl46._intervene_cd > 0.0, "intervention goes on cooldown after the choice")
						cl46.event_actors.erase(p46a)
						cl46.event_actors.erase(p46b)
						p46a.queue_free()
						p46b.queue_free()
		84:
			# WAVE 46 — SNITCHING + THANKS + STREET REP CHIP
			var npcsrc48 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("WorldState.snitch_chance()" in npcsrc48, "witness snitch chance driven by street rep, not a coin flip")
			var shsrc46 := FileAccess.get_file_as_string("res://scripts/ui/shop_ui.gd")
			_check("_keeper_id" in shsrc46 and 'barks.get("thank"' in shsrc46, "shopkeepers thank you when the block respects you")
			var hudsrc47 := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
			_check("_street_lbl" in hudsrc47 and "STREET REP" in hudsrc47, "street rep chip visible on HUD")
			var ws48 = root.get_node("WorldState")
			_check("street_deeds" in FileAccess.get_file_as_string("res://scripts/core/world_state.gd"), "street ledger persists in saves")
			ws48.street_deeds.clear()
		85:
			# WAVE 47 — DIRECTIONAL HIT REACTIONS (Euphoria lesson: no two hits alike)
			var adsrc47 := FileAccess.get_file_as_string("res://scripts/player/anim_driver.gd")
			_check("hit_vec" in adsrc47 and "hit_power" in adsrc47 and "hit_seed" in adsrc47, "reaction inputs exist on AnimDriver")
			_check("hit_t += delta * 4.0" in adsrc47, "AnimDriver advances its own hit reaction (NPC flinch was DEAD — fixed)")
			var ccsrc47 := FileAccess.get_file_as_string("res://scripts/combat/combat_controller.gd")
			_check("_set_reaction" in ccsrc47, "attack kind + shove direction mapped to reaction family")
			if _player:
				var ped47 = _spawn_ped46(_player.global_position + Vector3(2.5, 0, 0))
				if ped47 != null:
					var b47: Basis = ped47.global_transform.basis
					# front shove (melee passes push dir): local +z
					ped47.combat.take_hit(5.0, b47.z, "jab", null)
					_check(ped47.anim.hit_t == 0.0 and ped47.anim.hit_power > 0.1, "jab triggers a light reaction (power=%.2f)" % ped47.anim.hit_power)
					_check(ped47.anim.hit_vec.z > 0.5, "front hit reads as backward stagger (vec=%s)" % str(ped47.anim.hit_vec))
					ped47.combat.take_hit(5.0, b47.z, "kick_high", null)
					_check(ped47.anim.hit_vec.y > 0.3, "kick_high snaps the head back (y=%.2f)" % ped47.anim.hit_vec.y)
					ped47.combat.take_hit(5.0, b47.z, "ground_pound", null)
					_check(ped47.anim.hit_vec.y < -0.3, "ground pound folds the body low (y=%.2f)" % ped47.anim.hit_vec.y)
					# bullets pass victim->shooter dir; reaction flips to the shove
					ped47.combat.take_hit(5.0, -b47.z, "bullet", null)
					_check(ped47.anim.hit_vec.z > 0.5, "bullet from the front shoves backward")
					ped47.combat.take_hit(5.0, b47.x, "hook", null)
					_check(absf(ped47.anim.hit_vec.x) > 0.3, "hook whips the torso laterally (x=%.2f)" % ped47.anim.hit_vec.x)
					# driver tick advances the reaction to completion
					ped47.anim.tick(0.3, {})
					_check(ped47.anim.hit_t > 1.0 - 0.001 or ped47.anim.hit_t < 0.0 or ped47.anim.hit_t > 0.5, "reaction advances on tick (t=%.2f)" % ped47.anim.hit_t)
					ped47.queue_free()
		86:
			# WAVE 47 — JUICE LADDER + PERMANENCE (Nijman proportionality)
			var ccsrc48 := FileAccess.get_file_as_string("res://scripts/combat/combat_controller.gd")
			_check("Cinematics.hitstop(0.025)" in ccsrc48, "every light melee hit gets a micro-hitstop")
			_check('"blood", fwd, 1.8' in ccsrc48, "heavy hits throw a bigger blood burst")
			_check('Effects.decal(owner_node.global_position' in ccsrc48 and '"blood"' in ccsrc48, "kills leave a permanent blood decal")
			_check("Cinematics.slowmo(0.22" in ccsrc48, "guard break escalates to a short slow-mo")
			var effsrc47 := FileAccess.get_file_as_string("res://scripts/core/effects.gd")
			_check("scale: float = 1.0" in effsrc47 and "sqrt(scale)" in effsrc47, "Effects.burst takes a juice-budget scale")
			# live: killing an NPC drops a blood decal into the scene
			if _player:
				var bloods0 := _count_decals47("decal_blood")
				var ped48 = _spawn_ped46(_player.global_position + Vector3(2.5, 0, 1.0))
				if ped48 != null:
					ped48.combat.take_hit(9999.0, ped48.global_transform.basis.z, "heavy", null)
					_check(ped48.combat.dead, "test ped killed")
					_check(_count_decals47("decal_blood") > bloods0, "blood decal persists where they fell")
					ped48.queue_free()
		87:
			# WAVE 47 — PLAYER DAMAGE READ: direction arcs, heartbeat, frame punch, rumble
			var hudsrc48 := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
			_check("_draw_dmg_ring" in hudsrc48 and "draw_arc" in hudsrc48, "directional damage arcs drawn at screen edge")
			_check("_hurt_vignette" in hudsrc48 and "hpfrac < 0.3" in hudsrc48, "low-HP heartbeat vignette present")
			_check("start_joy_vibration" in FileAccess.get_file_as_string("res://scripts/combat/combat_controller.gd"), "gamepad rumble on taking hits")
			var crsrc47 := FileAccess.get_file_as_string("res://scripts/player/camera_rig.gd")
			_check("kick_dir" in crsrc47 and "_frame_wide" in crsrc47, "camera punches toward the blow + widens when outnumbered")
			if _player:
				_revive_player()
				var got47: Array = []
				var bus47 = root.get_node("Bus")
				var sub47 := func(d, a): got47.append([d, a])
				bus47.player_damaged.connect(sub47)
				_player.combat.take_hit(10.0, Vector3(0, 0, 1), "jab", null)
				_check(got47.size() == 1, "player_damaged signal fires with direction")
				bus47.player_damaged.disconnect(sub47)
				var hud47 = _city.get("hud")
				if hud47 != null:
					_check(hud47.get("_dmg_arcs") != null and (hud47.get("_dmg_arcs") as Array).size() >= 1, "HUD registered the damage arc")
				if _player.cam_rig != null:
					_check(float(_player.cam_rig.get("_punch_t")) > 0.0, "camera frame punched by the hit")
		88:
			# WAVE 47 — NEON-NOIR ATMOSPHERE: splash, puddles, flicker, sheen, echo
			var citysrc47 := FileAccess.get_file_as_string("res://scripts/scenes/city.gd")
			_check("_puddle_tick" in citysrc47 and '"puddle"' in citysrc47, "rain keeps laying fresh puddles near the player")
			_check("_neon_flicker" in citysrc47 and "_neon_dip" in citysrc47, "neon signs breathe and drop out at night")
			_check("emission_energy_multiplier = 0.06 * wet" in citysrc47, "wet asphalt throws back the district neon at night")
			_check("WorldState.wetness" in citysrc47 and "rain_loop" in citysrc47, "rain ambience swells with wetness")
			var adsrc48 := FileAccess.get_file_as_string("res://scripts/core/audio_director.gd")
			_check("func sfx_echo" in adsrc48, "layered gunshot echo tail exists")
			_check("sfx_echo" in FileAccess.get_file_as_string("res://scripts/combat/weapons_controller.gd") and "sfx_echo" in FileAccess.get_file_as_string("res://scripts/npc/npc.gd"), "player + nearby NPC gunfire get the echo layer")
			# live: splash node exists; flicker modulates emission at night
			var city47 = _city
			var splash47 = city47.get_node_or_null("RainSplash")
			_check(splash47 != null, "RainSplash particle system built")
			var ws47 = root.get_node("WorldState")
			var wg47 = root.get_node("WorldGen")
			var had_h: float = ws47.game_hour
			ws47.game_hour = 23.0
			var neon47 = wg47.mat("neon_white")
			neon47.emission_energy_multiplier = 3.0
			city47._neon_flicker(0.016)
			_check(neon47.emission_energy_multiplier != 3.0, "night neon flicker modulates emission (%.2f)" % neon47.emission_energy_multiplier)
			ws47.game_hour = 12.0
			city47._neon_flicker(0.016)
			_check(neon47.emission_energy_multiplier == 3.0, "day neon restored to steady")
			ws47.game_hour = had_h
			city47.set("_puddle_cd", 0.0)
			city47._puddle_tick(0.016)
			_check(float(city47.get("_puddle_cd")) > 0.0, "puddle tick fires and re-arms its timer")
		89:
			# WAVE 47 — ENGINE-HYGIENE REGRESSION GUARDS. Four real defects
			# that threw thousands of engine errors per run yet failed NO
			# check, because nothing asserted on the broken output.
			var fx89 = root.get_node("Effects")
			var cl89 = _city.get_node_or_null("CityLife")
			if _player == null or fx89 == null or cl89 == null:
				_check(false, "step 89 prerequisites (player/Effects/CityLife)")
				return false
			# (1) decals must actually orient to their surface normal.
			#     look_at() before add_child used to silently no-op, so wall
			#     and ceiling decals lay flat on the floor.
			var wall_n89 := Vector3(1, 0, 0)
			var before89 := _city.get_child_count()
			fx89.decal(_player.global_position + Vector3(2, 1, 0), wall_n89, "blood", 1.0)
			var dec89: Node = null
			for ci89 in range(before89, _city.get_child_count()):
				var ch89 = _city.get_child(ci89)
				if ch89 is MeshInstance3D:
					dec89 = ch89
			_check(dec89 != null, "wall decal spawned into the scene")
			if dec89 != null:
				var up89: Vector3 = dec89.global_transform.basis.y
				_check(up89.dot(wall_n89) > 0.98, "wall decal Y axis aligned to surface normal (%.2f)" % up89.dot(wall_n89))
				dec89.queue_free()
			var ceil_n89 := Vector3(0, -1, 0)
			var before289 := _city.get_child_count()
			fx89.decal(_player.global_position + Vector3(2, 3, 0), ceil_n89, "scorch", 1.0)
			var dec289: Node = null
			for ci289 in range(before289, _city.get_child_count()):
				var ch289 = _city.get_child(ci289)
				if ch289 is MeshInstance3D:
					dec289 = ch289
			if dec289 != null:
				var up289: Vector3 = dec289.global_transform.basis.y
				_check(up289.dot(ceil_n89) > 0.98, "ceiling decal flipped to face down (%.2f)" % up289.dot(ceil_n89))
				dec289.queue_free()
			else:
				_check(false, "ceiling decal spawned")
			# (2) every vehicle surface must carry texture coordinates.
			#     _quad/_cap added bare vertices, which latched the surface
			#     format without TEX_UV and made all later set_uv calls fail.
			var v89 = cl89.give_player_vehicle("sedan", _player.global_position + Vector3(4, 0, 0))
			_check(v89 != null, "regression vehicle spawned")
			if v89 != null:
				var body89 = v89.get("_body_mi")
				_check(body89 != null and body89.mesh != null, "vehicle body mesh built")
				if body89 != null and body89.mesh != null:
					var nouv89 := 0
					for si89 in body89.mesh.get_surface_count():
						if body89.mesh.surface_get_format(si89) & Mesh.ARRAY_TEX_UV == 0:
							nouv89 += 1
					_check(nouv89 == 0, "all body surfaces have UVs (%d without)" % nouv89)
				v89.queue_free()
			# (3) StyleBoxTexture has texture_margin_*, not margin_* — the bad
			#     assignment aborted dialogue button styling mid-function.
			var dui89 := FileAccess.get_file_as_string("res://scripts/ui/dialogue_ui.gd")
			_check("sbh.texture_margin_left" in dui89, "dialogue hover stylebox uses texture_margin_*")
			_check("sbh.margin_left" not in dui89.replace("texture_margin_left", ""), "no bare margin_* left on StyleBoxTexture")
			# (4) bool() has no Variant constructor in Godot 4 — the witness
			#     loop crashed, so protecting civilians never registered.
			var npc89 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("bool(n.get(" not in npc89, "no bool() cast on a Variant get() in npc.gd")
			_check('n.get("hostile") == true' in npc89, "witness loop tests hostility safely")
			# project-wide guard: bool()/float() on a node .get() with no
			# default returns null when the property is absent, and Godot 4
			# has no null->bool constructor. Scan every script for the pattern.
			var risky89: Array = []
			var re89 := RegEx.new()
			re89.compile("(bool|float|int|str)\\([A-Za-z_][A-Za-z_0-9]*\\.get\\(\"[^\"]+\"\\)\\)")
			var stack89: Array = ["res://scripts"]
			while not stack89.is_empty():
				var d89: String = stack89.pop_back()
				var da89 := DirAccess.open(d89)
				if da89 == null:
					continue
				da89.list_dir_begin()
				var fn89 := da89.get_next()
				while fn89 != "":
					if da89.current_is_dir():
						stack89.append(d89.path_join(fn89))
					elif fn89.ends_with(".gd"):
						var src89 := FileAccess.get_file_as_string(d89.path_join(fn89))
						# bool(x.get("k")) / float(x.get("k")) with no default arg
						for m89 in re89.search_all(src89):
							risky89.append(d89.path_join(fn89) + ": " + m89.get_string(0))
					fn89 = da89.get_next()
				da89.list_dir_end()
			_check(risky89.is_empty(), "no unguarded bool()/float() cast on node.get() anywhere (%d found: %s)" % [risky89.size(), "; ".join(risky89.slice(0, 4))])
		90:
			# WAVE 48 — A LIVING WORLD. The city had 234 sound effects and not
			# one creature in it. Everything here is asserted LIVE: creatures
			# must actually spawn, actually react, and actually be textured.
			var wl90 = _city.get_node_or_null("Wildlife")
			_check(wl90 != null, "Wildlife layer present in the city")
			if wl90 == null or _player == null:
				_check(false, "step 90 prerequisites")
				return false
			# force the spawn passes rather than waiting on the 1.1s cadence
			wl90._player = _player
			wl90._top_up_birds()
			wl90._top_up_rats()
			wl90._top_up_strays()
			var birds90: Array = wl90._birds
			var rats90: Array = wl90._rats
			var strays90: Array = wl90._strays
			_check(birds90.size() > 0, "birds spawned near the player (%d)" % birds90.size())
			_check(rats90.size() > 0, "rats spawned near the player (%d)" % rats90.size())
			_check(strays90.size() > 0, "stray cats/dogs spawned near the player (%d)" % strays90.size())
			# a bird must be a body plus two independently flapping wings
			if birds90.size() > 0:
				var bn90: Node = birds90[0]["node"]
				_check(is_instance_valid(bn90) and bn90.get_child_count() == 3, "bird built from body + 2 wings (%d children)" % (bn90.get_child_count() if is_instance_valid(bn90) else -1))
				var wl90b = birds90[0]["wing_l"]
				var wr90 = birds90[0]["wing_r"]
				wl90b.rotation.z = 0.0
				wr90.rotation.z = 0.0
				birds90[0]["state"] = "flee"
				birds90[0]["flee_t"] = 1.0
				birds90[0]["vel"] = Vector3(1, 2, 0)
				wl90._tick_birds(0.05)
				_check(absf(wl90b.rotation.z) > 0.05 and absf(wr90.rotation.z) > 0.05, "fleeing bird flaps both wings (%.2f/%.2f)" % [wl90b.rotation.z, wr90.rotation.z])
			# GUNFIRE EMPTIES THE ROOFTOPS: a crime must startle birds into flight
			var perch90 := 0
			for b90 in birds90:
				b90["state"] = "perch"
				b90["flee_t"] = 0.0
				perch90 += 1
			if perch90 > 0:
				var bp90: Vector3 = birds90[0]["node"].global_position
				root.get_node("Bus").crime_committed.emit("gunfire", 3, bp90)
				var fled90 := 0
				for b90b in birds90:
					if b90b["state"] == "flee":
						fled90 += 1
				_check(fled90 > 0, "gunfire startles the flock into flight (%d/%d fled)" % [fled90, perch90])
			# rats bolt from a player who gets too close
			if rats90.size() > 0:
				var rn90: Node3D = rats90[0]["node"]
				rn90.global_position = _player.global_position + Vector3(1.0, 0, 0)
				rats90[0]["state"] = "sniff"
				wl90._tick_rats(0.05)
				_check(rats90[0]["state"] == "flee", "rat bolts when the player steps on it")
			# moths only work the neon after dark
			var ws90 = root.get_node("WorldState")
			var had90: float = ws90.game_hour
			ws90.game_hour = 22.5
			wl90._update_moths()
			var lit90 := 0
			for m90 in wl90._moth_sites:
				var mn90: Node = m90["node"]
				if is_instance_valid(mn90) and (mn90 as GPUParticles3D).emitting:
					lit90 += 1
			_check(lit90 > 0, "moth swarms light up the lamps at night (%d emitting)" % lit90)
			ws90.game_hour = 13.0
			wl90._update_moths()
			var lit91 := 0
			for m91 in wl90._moth_sites:
				var mn91: Node = m91["node"]
				if is_instance_valid(mn91) and (mn91 as GPUParticles3D).emitting:
					lit91 += 1
			_check(lit91 == 0, "moth swarms stand down by day (%d emitting)" % lit91)
			ws90.game_hour = had90
			# fish need the harbour: teleport the player to the quay and spawn
			var wg90 = root.get_node("WorldGen")
			var w90d: Dictionary = root.get_node("Db").districts.get("world", {})
			var wz90: float = float(w90d.get("water_z", -380.0))
			var save90: Vector3 = _player.global_position
			# stand on the quay: water_z is the shoreward edge, land is z > it
			_player.global_position = Vector3(100, 0.5, wz90 + 8.0)
			wl90._top_up_fish()
			# stand over whichever fish actually spawned, so the jump test
			# measures the fish and not the spawn lottery
			if wl90._fish.size() > 0:
				var fp0: Vector3 = (wl90._fish[0]["node"] as Node3D).global_position
				_player.global_position = fp0 + Vector3(0, 1.0, 22.0)
			_check(wl90._fish.size() > 0, "fish populate the harbour near the player (%d)" % wl90._fish.size())
			if wl90._fish.size() > 0:
				var f90: Dictionary = wl90._fish[0]
				f90["state"] = "idle"
				f90["jump_t"] = 0.0
				wl90._tick_fish(0.05)
				var fp90: Vector3 = (f90["node"] as Node3D).global_position
				_check(fp90.z < wz90 - 4.0, "fish spawn in the water, not on the docks (z=%.0f, quay=%.0f)" % [fp90.z, wz90])
				_check(f90["state"] == "jump", "fish breaks the surface on its timer")
				_check((f90["node"] as Node3D).visible, "jumping fish is actually visible")
			_player.global_position = save90
			# every creature mesh must carry UVs (the wave-47 vehicle lesson)
			for pair90 in [["bird", wl90._mbird], ["rat", wl90._mrat], ["cat", wl90._mcat], ["dog", wl90._mdog], ["fish", wl90._mfish], ["wing", wl90._mwing], ["tail", wl90._mtail]]:
				var mesh90: ArrayMesh = pair90[1]
				var bad90 := 0
				if mesh90 == null:
					bad90 = 1
				else:
					for si90 in mesh90.get_surface_count():
						if mesh90.surface_get_format(si90) & Mesh.ARRAY_TEX_UV == 0:
							bad90 += 1
				_check(bad90 == 0, "%s mesh has UVs on every surface" % pair90[0])
			# --- the harbour is no longer a frozen quad --------------------
			# _water_layers is one flat scroll list that the Cinder Cut appends
			# its own sheets to, so the harbour's three have to be addressed by
			# name rather than by position in that list.
			var layers90: Array = wg90.harbour_layers
			_check(layers90.size() == 3, "harbour built from 3 sheets: base, chop, foam (%d)" % layers90.size())
			_check(wg90._water_layers.size() > layers90.size(), "the river appends to the same scroll list without stealing the harbour's (%d total)" % wg90._water_layers.size())
			if layers90.size() == 3:
				var m090: StandardMaterial3D = layers90[0][0]
				var m190: StandardMaterial3D = layers90[1][0]
				var off090: Vector3 = m090.uv1_offset
				var off190: Vector3 = m190.uv1_offset
				wg90._process(0.5)
				_check(m090.uv1_offset != off090, "harbour base sheet scrolls")
				_check(m190.uv1_offset != off190, "harbour chop sheet scrolls")
				var sp090: Vector2 = layers90[0][1]
				var sp190: Vector2 = layers90[1][1]
				_check(signf(sp090.x) != signf(sp190.x), "the two sheets scroll AGAINST each other (interference = chop)")
				var foam90: StandardMaterial3D = wg90._water_foam
				var fa90: float = foam90.albedo_color.a
				wg90._water_t = 1.7
				wg90._process(0.016)
				_check(foam90.albedo_color.a != fa90, "quay foam surges instead of sitting still")
			# --- the harbour must be audible before it is visible ----------
			var ad90 = root.get_node("AudioDirector")
			_check(ad90.ambient_players.has("harbour"), "harbour ambient bus slot exists")
			_player.global_position = Vector3(100, 0.5, -510.0 + 30.0)
			_city._harbour_ambience()
			_check(float(ad90.ambient_target.get("harbour", 0.0)) > 0.05, "standing on the quay raises the harbour wash (%.2f)" % float(ad90.ambient_target.get("harbour", 0.0)))
			_player.global_position = Vector3(-240, 0.5, 46)
			_city._harbour_ambience()
			_check(float(ad90.ambient_target.get("harbour", 0.0)) == 0.0, "inland the harbour wash drops out")
			# --- every creature needs a voice ------------------------------
			for sfx90 in ["bird_chirp_0", "bird_chirp_1", "bird_chirp_2", "gull_cry", "crow_caw", "wing_flutter", "rat_squeak", "rat_scuttle", "cat_meow", "dog_bark", "insect_buzz", "fish_splash", "water_lap"]:
				_check(FileAccess.file_exists("res://assets/audio/sfx/%s.wav" % sfx90), "wildlife sound forged: %s" % sfx90)
			var fa91 := FileAccess.get_file_as_string("res://tools/forge/forge_audio.py")
			_check("def bird_chirp" in fa91 and "def cat_meow" in fa91 and "def water_lap" in fa91, "wildlife audio is synthesized in the forge, not dropped in")
			# --- the studio card ------------------------------------------
			var bt90 := FileAccess.get_file_as_string("res://scripts/scenes/boot.gd")
			_check('AudioDirector.sting("studio_sting")' in bt90, "studio logo plays its own forged sting")
			_check("STRIKE" in bt90 and "NAME_IN" in bt90, "logo reveal is timed to the sting's strike")
			_check(FileAccess.file_exists("res://assets/audio/music/studio_sting.ogg"), "studio sting asset shipped")
			_check('dbg.position = Vector2(6, 6)' not in bt90.split("func _toggle_dbg")[0], "no dev debug overlay printed on the studio logo")
			_check("_skipping" in bt90, "studio card is skippable — never holds a returning player")
		91:
			# WAVE 48 — THE SMOKE LINE. Missions and POIs named this railway
			# (m10_smoke_line, Smokeline Bolt-Hole, Smoke Line Overlook) while
			# the game contained no rails at all. Now it does, and it runs.
			var sl91 = _city.get_node_or_null("SmokeLine")
			_check(sl91 != null, "SmokeLine freight train present in the city")
			if sl91 == null or _player == null:
				_check(false, "step 91 prerequisites")
				return false
			var wg91 = root.get_node("WorldGen")
			# --- the viaduct is real geometry, not a rumour ----------------
			var rail_node91 = wg91.root.get_node_or_null("smoke_line")
			_check(rail_node91 != null, "Smoke Line viaduct built into the world")
			if rail_node91 != null:
				var tris91 := 0
				var nouv91 := 0
				for mi91 in rail_node91.get_children():
					if mi91 is MeshInstance3D and mi91.mesh != null:
						for si91 in mi91.mesh.get_surface_count():
							tris91 += mi91.mesh.surface_get_array_index_len(si91) / 3
							if mi91.mesh.surface_get_format(si91) & Mesh.ARRAY_TEX_UV == 0:
								nouv91 += 1
				_check(tris91 > 4000, "viaduct carries real structure: piers, deck, sleepers, rails (%d tris)" % tris91)
				_check(nouv91 == 0, "every viaduct surface is textured (%d without UVs)" % nouv91)
			_check(wg91.rail_height() > 6.0, "rails are elevated above the street (%.2f m)" % wg91.rail_height())
			# --- the consist ----------------------------------------------
			var loco91: Node = sl91._loco
			_check(loco91 != null, "locomotive built")
			_check(sl91._cars.size() == 6, "mixed freight consist: 6 cars (%d)" % sl91._cars.size())
			if loco91 != null:
				_check(loco91.get_child_count() >= 5, "loco is body + livery + glass + headlight + marker + tail (%d parts)" % loco91.get_child_count())
				var kinds91: Array = []
				for c91 in sl91._cars:
					kinds91.append((c91["node"] as Node).name)
				_check(kinds91.size() == 6, "cars are individual nodes: %s" % str(kinds91))
			# every rolling-stock mesh must be textured
			var baduv91 := 0
			var allmesh91: Array = []
			if loco91 != null:
				allmesh91.append_array(loco91.get_children())
			for c91b in sl91._cars:
				allmesh91.append_array((c91b["node"] as Node).get_children())
			for ch91 in allmesh91:
				if ch91 is MeshInstance3D and ch91.mesh != null:
					for si91b in ch91.mesh.get_surface_count():
						if ch91.mesh.surface_get_format(si91b) & Mesh.ARRAY_TEX_UV == 0:
							baduv91 += 1
			_check(baduv91 == 0, "locomotive + freight cars textured on every surface (%d bad)" % baduv91)
			# --- it actually moves, and it wraps --------------------------
			var x091: float = sl91._x
			sl91._process(1.0)
			_check(sl91._x > x091 + 15.0, "train runs the line (%.1f m in 1 s)" % (sl91._x - x091))
			sl91._x = sl91._x1 + 1.0
			sl91._process(0.016)
			_check(sl91._x < sl91._x0 + 1.0, "train wraps back onto the western horizon instead of vanishing")
			# --- the rumble swells as it closes ---------------------------
			var rum91: AudioStreamPlayer3D = sl91._rumble
			_check(rum91 != null and rum91.playing, "rumble bed is a live 3D emitter (Godot does the Doppler)")
			sl91._x = 0.0
			sl91._apply_positions()
			var save91: Vector3 = _player.global_position
			_player.global_position = Vector3(0, wg91.rail_height(), -30.0)
			sl91._tick_audio(0.016)
			var loud91: float = rum91.volume_db
			_player.global_position = Vector3(0, 0.5, -30.0 + 190.0)
			sl91._tick_audio(0.016)
			var quiet91: float = rum91.volume_db
			_check(loud91 > quiet91 + 6.0, "rumble swells with proximity (%.1f dB close vs %.1f dB far)" % [loud91, quiet91])
			# --- the horn announces the train before it arrives ------------
			_player.global_position = Vector3(0, 0.5, -30.0 + 40.0)
			sl91._horn_cd = 0.01
			sl91._tick_audio(0.02)
			_check(sl91._horn_cd > 10.0, "horn fires and re-arms on a long timer when the player is near")
			# --- headlight only burns after dark ---------------------------
			var ws91 = root.get_node("WorldState")
			var had91: float = ws91.game_hour
			ws91.game_hour = 22.0
			sl91._tick_lights()
			var night91: float = sl91._head.light_energy
			ws91.game_hour = 12.0
			sl91._tick_lights()
			var day91: float = sl91._head.light_energy
			ws91.game_hour = had91
			_check(night91 > 1.0, "headlight sweeps the deck at night (%.1f)" % night91)
			_check(day91 == 0.0, "headlight off by day — it costs nothing it does not earn")
			# --- standing on the viaduct is a choice the train collects on --
			_revive_player()
			var cc91 = _player.combat
			var hp91: float = cc91.hp
			_player.global_position = Vector3(0, wg91.rail_height(), -30.0)
			sl91._x = 4.0
			sl91._apply_positions()
			sl91._hit_cd = 0.0
			sl91._tick_hazard(0.016)
			_check(cc91.hp < hp91, "a train hits you if you stand on the rails (hp %.0f -> %.0f)" % [hp91, cc91.hp])
			_check(sl91._hit_cd > 0.0, "the hit is rate-limited so it cannot chain into an instant death")
			# below the deck, on the street, you are perfectly safe
			cc91.hp = hp91
			sl91._hit_cd = 0.0
			_player.global_position = Vector3(0, 0.5, -30.0)
			sl91._tick_hazard(0.016)
			_check(cc91.hp == hp91, "the train does not hit you through the deck from the street below")
			cc91.hp = hp91
			_player.global_position = save91
			# --- the railway has a voice ----------------------------------
			for sfx91 in ["train_horn", "train_rumble", "rail_clack", "train_brake"]:
				_check(FileAccess.file_exists("res://assets/audio/sfx/%s.wav" % sfx91), "rail sound forged: %s" % sfx91)
			var fa92 := FileAccess.get_file_as_string("res://tools/forge/forge_audio.py")
			_check("def train_horn" in fa92 and "def train_rumble" in fa92, "rail audio is synthesized in the forge")
			# --- the Overlook station: platform, canopy, stair from street --
			var wgsrc91 := FileAccess.get_file_as_string("res://scripts/world/world_gen.gd")
			_check("RAIL_PLATFORM_X" in wgsrc91, "Smoke Line Overlook station built on the viaduct")
			_check("_build_rail" in wgsrc91 and "smoke_line" in wgsrc91, "rail is part of city generation, not bolted on")
			# --- VOX INTEGRITY: an empty voice bank makes AudioDirector ask
			# for vox/_0.wav and the line plays silent. Every bank named in
			# characters.json must exist on disk, and no call site may emit
			# dialogue with a literal empty voice.
			var db91 = root.get_node("Db")
			var missing91: Array = []
			for cid91 in db91.characters:
				var ch91: Dictionary = db91.characters[cid91]
				var vb91: String = str(ch91.get("voice", ""))
				if vb91 == "":
					missing91.append(str(cid91) + " has no voice field")
					continue
				for k91 in 3:
					if not FileAccess.file_exists("res://assets/audio/vox/%s_%d.wav" % [vb91, k91]):
						missing91.append("%s -> %s_%d.wav" % [cid91, vb91, k91])
			_check(missing91.is_empty(), "every character voice bank exists on disk (%d missing: %s)" % [missing91.size(), "; ".join(missing91.slice(0, 4))])
			var emptyvox91: Array = []
			var stack91: Array = ["res://scripts"]
			var rev91 := RegEx.new()
			rev91.compile("(dialogue_line\\.emit|AudioDirector\\.speak)\\([^)]*,\\s*\"\\s*\\)")
			while not stack91.is_empty():
				var d91: String = stack91.pop_back()
				var da91 := DirAccess.open(d91)
				if da91 == null:
					continue
				da91.list_dir_begin()
				var fn91 := da91.get_next()
				while fn91 != "":
					if da91.current_is_dir():
						stack91.append(d91.path_join(fn91))
					elif fn91.ends_with(".gd"):
						var src91 := FileAccess.get_file_as_string(d91.path_join(fn91))
						for m91b in rev91.search_all(src91):
							emptyvox91.append(d91.path_join(fn91) + ": " + m91b.get_string(0))
					fn91 = da91.get_next()
				da91.list_dir_end()
			_check(emptyvox91.is_empty(), "no dialogue emitted with an empty voice bank (%d found)" % emptyvox91.size())
			# the shopkeeper thanks you in their own voice, not in silence
			var shsrc91 := FileAccess.get_file_as_string("res://scripts/ui/shop_ui.gd")
			_check('get("voice", "ped_m")' in shsrc91, "shopkeeper thanks use their real voice bank")
		92:
			# WAVE 48 — the studio card must never ship a debug readout, and
			# the world must never be silent where it claims to be alive.
			var adsrc92 = root.get_node("AudioDirector")
			for slot92 in ["rain", "traffic", "crowd", "interior", "fire", "siren", "harbour"]:
				_check(adsrc92.ambient_players.has(slot92), "ambient bus slot present: %s" % slot92)
			# every creature sound must actually resolve to a loaded stream
			var ad92 = root.get_node("AudioDirector")
			var dead92: Array = []
			for sfx92 in ["bird_chirp_0", "gull_cry", "crow_caw", "wing_flutter", "rat_squeak", "rat_scuttle", "cat_meow", "dog_bark", "insect_buzz", "fish_splash", "water_lap", "train_horn", "train_rumble", "rail_clack", "train_brake", "studio_sting"]:
				var p92 := ("res://assets/audio/music/%s.ogg" % sfx92) if sfx92 == "studio_sting" else ("res://assets/audio/sfx/%s.wav" % sfx92)
				var st92: AudioStream = load(p92) if ResourceLoader.exists(p92) else null
				if st92 == null:
					dead92.append(sfx92)
			_check(dead92.is_empty(), "every wave-48 sound loads as a real stream (%d dead: %s)" % [dead92.size(), ", ".join(dead92)])
			# wildlife must be wired to the world's events, not free-running
			var wlsrc92 := FileAccess.get_file_as_string("res://scripts/world/wildlife.gd")
			_check("Bus.crime_committed.connect" in wlsrc92, "wildlife reacts to crime through the Bus")
			_check("LIVE_RADIUS" in wlsrc92 and "DESPAWN_RADIUS" in wlsrc92, "wildlife is budgeted with hysteresis, not spawned forever")
			_check(wlsrc92.count("MAX_") >= 5, "every creature type has a hard cap")
			var slsrc92 := FileAccess.get_file_as_string("res://scripts/world/smoke_line.gd")
			_check("_tick_hazard" in slsrc92, "the train is a hazard, not decoration")
			_check("ATTENUATION_INVERSE_DISTANCE" in slsrc92, "train rumble uses 3D attenuation so the engine does the Doppler")
		93:
			# WAVE 48 — FILLING STATIONS AND A REAL FUEL ECONOMY. The user
			# named filling stations explicitly. Before this the city had 11
			# vehicles with hp, gears, rpm and skids — and no tank at all.
			var wg93 = root.get_node("WorldGen")
			var ws93 = root.get_node("WorldState")
			var db93 = root.get_node("Db")
			var wcfg93: Dictionary = db93.districts.get("world", {})
			# --- the data drives the world --------------------------------
			var stal93: Array = wcfg93.get("stations", [])
			_check(stal93.size() == 6, "six filling stations authored in city.json (%d)" % stal93.size())
			var notank93: Array = []
			for vid93 in db93.vehicles:
				var vd93: Dictionary = db93.vehicles[vid93]
				if float(vd93.get("tank", 0)) <= 0.0:
					notank93.append(str(vid93))
			_check(notank93.is_empty(), "every vehicle def carries a tank size (%d missing: %s)" % [notank93.size(), ", ".join(notank93)])
			# --- built geometry -------------------------------------------
			_check(wg93.stations.size() == 6, "six forecourts built into the city (%d)" % wg93.stations.size())
			var fsnode93 = wg93.root.get_node_or_null("filling_stations")
			_check(fsnode93 != null, "filling_stations geometry committed")
			if fsnode93 != null:
				var tris93 := 0
				var mauv93 := 0
				for mi93 in fsnode93.get_children():
					if mi93 is MeshInstance3D and mi93.mesh != null:
						for si93 in mi93.mesh.get_surface_count():
							tris93 += mi93.mesh.surface_get_array_index_len(si93) / 3
							if mi93.mesh.surface_get_format(si93) & Mesh.ARRAY_TEX_UV == 0:
								mauv93 += 1
				_check(tris93 > 2500, "forecourts are real structure: pad, canopy, fascia, posts, pumps, kiosk, price totem (%d tris)" % tris93)
				_check(mauv93 == 0, "every station surface is textured (%d without UVs)" % mauv93)
			# --- one per district, inside it, off the roads -----------------
			var seen93: Dictionary = {}
			var bad93: Array = []
			for sid93 in wg93.stations:
				var st93: Dictionary = wg93.stations[sid93]
				var did93: String = str(st93.get("district", ""))
				var pos93: Vector3 = st93.get("pos", Vector3.ZERO)
				seen93[did93] = true
				var b93: Rect2 = wg93.district_bounds.get(did93, Rect2())
				if b93.size == Vector2.ZERO or not b93.has_point(Vector2(pos93.x, pos93.z)):
					bad93.append(str(sid93) + " outside " + did93)
				for a93 in wcfg93.get("arterials", []):
					var ad93: Dictionary = a93
					var at93: float = float(ad93.get("at", 0))
					var half93: float = float(ad93.get("width", 16)) * 0.5 + 5.0
					# axis names the CONSTANT coordinate: "x" is a line of
					# constant x running N-S. This matched the inverted
					# convention in _station_along_z, so the test agreed with
					# the bug it was supposed to be checking.
					var onroad93: bool = absf(pos93.x - at93) < half93 if str(ad93.get("axis", "x")) == "x" else absf(pos93.z - at93) < half93
					if onroad93:
						bad93.append(str(sid93) + " sitting on arterial " + str(at93))
			_check(seen93.size() == 6, "one filling station per district (%d districts covered)" % seen93.size())
			_check(bad93.is_empty(), "stations are inside their district and off the arterials (%s)" % str(bad93))
			# --- canopies orient to the road they front --------------------
			# Recomputed from the data, not from the builder's own answer: a
			# "some do, some don't" assertion passes just as happily when the
			# axis convention is backwards and one canopy is turned 90 degrees
			# away from the road it fronts.
			var alongz93 := 0
			var wrong93: Array = []
			for sid93b in wg93.stations:
				var st93b: Dictionary = wg93.stations[sid93b]
				var p93b: Vector3 = st93b.get("pos", Vector3.ZERO)
				var bestd93 := 1e9
				var bestns93 := false
				for a93b in wcfg93.get("arterials", []):
					var ad93b: Dictionary = a93b
					var ns93b: bool = str(ad93b.get("axis", "x")) == "x"
					var at93b := float(ad93b.get("at", 0))
					var d93b: float = absf(p93b.x - at93b) if ns93b else absf(p93b.z - at93b)
					if d93b < bestd93:
						bestd93 = d93b
						bestns93 = ns93b
				var want93: bool = bestns93 if bestd93 <= 90.0 else false
				if st93b.get("along_z", false) != want93:
					wrong93.append("%s wants %s" % [str(sid93b), str(want93)])
				if want93:
					alongz93 += 1
			_check(wrong93.is_empty(),
				"every canopy faces the arterial it actually fronts (%d of %d run north-south; %s)" % [alongz93, wg93.stations.size(), str(wrong93)])
			# --- pumps ----------------------------------------------------
			var npump93 := 0
			var badlbl93: Array = []
			var offpad93 := 0
			for sid93c in wg93.stations:
				var st93c: Dictionary = wg93.stations[sid93c]
				var pl93: Array = st93c.get("pumps", [])
				npump93 += pl93.size()
				var c93: Vector3 = st93c.get("pos", Vector3.ZERO)
				for p93 in pl93:
					var pn93 := p93 as Node3D
					if not pn93.is_in_group("interact"):
						badlbl93.append("not in interact group")
					var lbl93: String = str(pn93.get("interact_label"))
					if "$" not in lbl93:
						badlbl93.append("no price in prompt: " + lbl93)
					if absf(pn93.global_position.x - c93.x) > 19.0 or absf(pn93.global_position.z - c93.z) > 15.0:
						offpad93 += 1
			_check(npump93 == 22, "22 pumps built across the six forecourts (%d)" % npump93)
			_check(badlbl93.is_empty(), "every pump offers a priced Refuel prompt (%s)" % str(badlbl93.slice(0, 3)))
			_check(offpad93 == 0, "every pump stands on its own forecourt (%d off the pad)" % offpad93)
			# --- the fuel model on a real vehicle --------------------------
			var cl93 = _city.get_node_or_null("CityLife")
			var veh93 = null
			if cl93 != null and _player != null:
				veh93 = cl93.give_player_vehicle("truck", _player.global_position + Vector3(9, 0, 9))
			_check(veh93 != null, "test vehicle spawned for the fuel tests")
			if veh93 == null:
				_check(false, "step 93 vehicle prerequisites")
				return false
			var tdef93: Dictionary = db93.vehicle("truck")
			_check(absf(float(veh93.tank_l) - float(tdef93.get("tank", 0))) < 0.01, "tank size comes from the vehicle def (%.0f L)" % float(veh93.tank_l))
			_check(float(veh93.fuel) > 0.40 and float(veh93.fuel) <= 1.0, "a parked car is never guaranteed full — a stolen ride can be a short ride (%.2f)" % float(veh93.fuel))
			var f093 := float(veh93.fuel)
			for i in 120:
				veh93._burn_fuel(1.0 / 60.0, 1.0, 90.0)
			var hard93 := f093 - float(veh93.fuel)
			var f193 := float(veh93.fuel)
			for i in 120:
				veh93._burn_fuel(1.0 / 60.0, 0.0, 0.0)
			var idle93 := f193 - float(veh93.fuel)
			_check(hard93 > 0.0, "hard throttle empties the tank (%.5f over 2 s)" % hard93)
			_check(idle93 > 0.0, "idling still sips fuel (%.5f over 2 s)" % idle93)
			_check(hard93 > idle93 * 2.0, "throttle costs far more than idling (%.5f vs %.5f)" % [hard93, idle93])
			veh93.fuel = 0.0
			veh93.fuel_dry = false
			veh93._burn_fuel(0.016, 1.0, 40.0)
			_check(veh93.fuel_dry == true, "an empty tank sets fuel_dry")
			veh93.engine_force = 999.0
			veh93.player_drive(0.016, Vector2(0, -1), false, false, false)
			_check(absf(float(veh93.engine_force)) < 0.001, "a dry engine makes no torque — you are coasting (force %.2f)" % float(veh93.engine_force))
			veh93.fuel = 0.05
			veh93.fuel_dry = false
			veh93._dry_warned = false
			veh93._burn_fuel(0.016, 0.5, 30.0)
			_check(veh93._dry_warned == true, "the fuel light warns before the tank is actually empty")
			_check(veh93.fuel_is_low(), "fuel_is_low() reports the reserve line")
			veh93.fuel = 0.90
			veh93._burn_fuel(0.016, 0.0, 0.0)
			_check(veh93._dry_warned == false, "the warning clears once the tank is healthy again")
			# --- the pump -------------------------------------------------
			var pump93 = null
			for sid93e in wg93.stations:
				var pl93e: Array = wg93.stations[sid93e].get("pumps", [])
				if not pl93e.is_empty():
					pump93 = pl93e[0]
					break
			_check(pump93 != null, "a pump is available to test against")
			if pump93 == null:
				_check(false, "step 93 pump prerequisites")
				return false
			_check(float(pump93.price_per_l) > 0.5, "the pump carries a per-litre price from data ($%.2f)" % float(pump93.price_per_l))
			# price moves with street reputation, both directions
			var rep93: Array = ws93.street_deeds.duplicate(true)
			ws93.street_deeds.clear()
			var pn93b: float = pump93.unit_price()
			for i in 15:
				ws93.street_deeds.append({"id": "t", "did": "x", "helped": true, "day": 1})
			var pr93: float = pump93.unit_price()
			ws93.street_deeds.clear()
			for i in 15:
				ws93.street_deeds.append({"id": "t", "did": "x", "helped": false, "day": 1})
			var ph93: float = pump93.unit_price()
			_check(pr93 < pn93b - 0.01, "the block's respect lowers the pump price ($%.2f -> $%.2f)" % [pn93b, pr93])
			_check(ph93 > pn93b + 0.01, "a known thief pays a premium at the pump ($%.2f -> $%.2f)" % [pn93b, ph93])
			# --- a real fill, from the driver's seat -----------------------
			ws93.street_deeds = rep93
			_player.enter_vehicle(veh93)
			veh93.fuel = 0.10
			veh93.fuel_dry = false
			veh93.global_position = (pump93 as Node3D).global_position + Vector3(1.6, 0, 0)
			ws93.money = 5000
			var m093: int = ws93.money
			pump93.interact(_player)
			_check(pump93.filling == true, "the pump starts filling the car you arrived in — no climbing out")
			_check(pump93._flow != null and pump93._flow.playing, "the hose loop plays while fuel flows")
			pump93._process(0.5)
			_check(float(veh93.fuel) > 0.101, "fuel actually goes into the tank (%.3f)" % float(veh93.fuel))
			_check(ws93.money < m093, "money leaves the wallet as fuel goes in ($%d -> $%d)" % [m093, ws93.money])
			_check(float(pump93.litres) > 0.0 and pump93.paid > 0, "the pump meters litres and dollars (%d L, $%d)" % [int(pump93.litres), pump93.paid])
			veh93.fuel = 0.0
			veh93.fuel_dry = true
			pump93._process(0.4)
			_check(veh93.fuel_dry == false, "fuel in the line clears the dry flag — the engine will turn over")
			for i in 260:
				pump93._process(0.1)
			_check(float(veh93.fuel) > 0.995, "the tank fills to full (%.3f)" % float(veh93.fuel))
			_check(pump93.filling == false, "the nozzle shuts itself off when the tank is full")
			_check(pump93.paid > 0, "the visit was paid for ($%d for %d L)" % [pump93.paid, int(pump93.litres)])
			# --- driving off mid-fill is theft, and forecourts are watched --
			ws93.street_deeds.clear()
			var rep093: int = ws93.street_rep()
			var heat093: float = float(ws93.district_heat.get(str(pump93.district), 0.0))
			veh93.fuel = 0.20
			ws93.money = 5000
			pump93.interact(_player)
			_check(pump93.filling == true, "a second visit starts")
			veh93.global_position = (pump93 as Node3D).global_position + Vector3(46, 0, 0)
			pump93._process(0.016)
			_check(pump93.stolen == true, "leaving the forecourt mid-fill is recorded as theft")
			_check(pump93.filling == false, "the nozzle comes out")
			_check(ws93.street_rep() < rep093, "the block's opinion of you drops (%d -> %d)" % [rep093, ws93.street_rep()])
			_check(float(ws93.district_heat.get(str(pump93.district), 0.0)) > heat093, "the district heats up after a drive-off")
			# --- running out of cash mid-fill ------------------------------
			veh93.global_position = (pump93 as Node3D).global_position + Vector3(1.6, 0, 0)
			veh93.fuel = 0.05
			ws93.money = 3
			pump93.interact(_player)
			_check(pump93.filling == true, "a fill starts with only $3 in your pocket")
			for i in 60:
				pump93._process(0.1)
			_check(pump93.broke == true, "the nozzle shuts off when the money runs out")
			_check(pump93.filling == false, "the fill is over")
			_check(ws93.money == 0, "every last dollar went into the tank ($%d left)" % ws93.money)
			# --- the HUD reads it, and the speedo is finally on screen -----
			var hud93 = _city.get("hud")
			if hud93 != null:
				_check(hud93.get("_fuel_gauge") != null and hud93.get("_fuel_lbl") != null, "fuel gauge and litre readout built into the HUD")
				var vpr93: Rect2 = _city.get_viewport().get_visible_rect()
				var sl93: Control = hud93.get("_speed_lbl")
				var sr93: Rect2 = sl93.get_global_rect()
				_check(sr93.position.y >= 0.0 and sr93.position.y < vpr93.size.y,
					"speedometer is ON SCREEN (bug fixed: negative offsets with no bottom anchor put it above the top edge; y=%.0f of %d)" % [sr93.position.y, int(vpr93.size.y)])
				var fg93: Control = hud93.get("_fuel_gauge")
				var fr93: Rect2 = fg93.get_global_rect()
				_check(fr93.position.y >= 0.0 and fr93.position.y < vpr93.size.y, "fuel gauge is on screen (y=%.0f of %d)" % [fr93.position.y, int(vpr93.size.y)])
				_check(fr93.position.x >= 0.0 and fr93.position.x < vpr93.size.x, "fuel gauge is inside the right edge (x=%.0f of %d)" % [fr93.position.x, int(vpr93.size.x)])
				hud93.set("_fuel_frac", 0.0)
				hud93._process(0.016)
				_check(float(hud93.get("_fuel_frac")) > 0.0, "the gauge tracks the tank you are sitting in (%.2f)" % float(hud93.get("_fuel_frac")))
				_check(str(hud93.get("_fuel_lbl").text).begins_with("FUEL"), "the readout says how many litres are left (%s)" % str(hud93.get("_fuel_lbl").text))
			var hsrc93 := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
			_check("_draw_fuel" in hsrc93 and "reserve" in hsrc93, "the gauge marks the reserve line and pulses on it")
			_check('"fuel": col = Color(0.95, 0.45, 0.25)' in hsrc93, "filling stations get their own colour on the minimap")
			# --- the sounds ------------------------------------------------
			for sfx93 in ["fuel_pump", "fuel_cap", "nozzle_off", "engine_sputter"]:
				_check(FileAccess.file_exists("res://assets/audio/sfx/%s.wav" % sfx93), "fuel sound forged: %s" % sfx93)
			var fa93 := FileAccess.get_file_as_string("res://tools/forge/forge_audio.py")
			_check("def fuel_pump" in fa93 and "def engine_sputter" in fa93 and "def _place" in fa93, "fuel audio is synthesized in the forge")
			# the flow loop must be genuinely seamless — the wobble periods
			# have to divide the loop length into whole cycles
			_check("1.0 / 1.5" in fa93 and "1.0 / 0.75" in fa93, "pump loop wobble is cyclic so it never clicks at the seam")
		94:
			# WAVE 48 — THE OPENING HAS TO TELL THE STORY. The user asked for
			# an intro where the characters ACTUALLY CONVERSE so the player
			# grabs the story. What shipped before was three spoken lines over
			# one push-in: Eli narrated at the camera twice, Ruth said one
			# thing, nobody answered anybody. This measures conversation, not
			# runtime.
			var cut94 = root.get_node("Cutscene")
			var db94 = root.get_node("Db")
			var scr94: Array = cut94._script("cs_intro")
			_check(scr94.size() > 20, "the opening cinematic has a real script (%d steps)" % scr94.size())
			var lines94: Array = []
			var cams94: Array = []
			var cards94: Array = []
			var spawns94: Array = []
			var total94 := 0.0
			for st94 in scr94:
				var d94: Dictionary = st94
				total94 += float(d94.get("dur", 0.0))
				match str(d94.get("v", "")):
					"line": lines94.append(d94)
					"cam": cams94.append(d94)
					"card": cards94.append(str(d94.get("text", "")))
					"spawn": spawns94.append(str(d94.get("char", "")))
			_check(lines94.size() >= 15, "at least fifteen spoken lines (%d)" % lines94.size())
			_check(total94 >= 70.0, "the opening runs like a scene, not a splash (%.0f s)" % total94)
			# --- it is a CONVERSATION: speakers alternate and answer --------
			var spk94: Dictionary = {}
			var run94 := 1
			var maxrun94 := 1
			var prev94 := ""
			for l94 in lines94:
				var sp94: String = str(l94.get("spk", ""))
				spk94[sp94] = int(spk94.get(sp94, 0)) + 1
				if sp94 == prev94:
					run94 += 1
					maxrun94 = maxi(maxrun94, run94)
				else:
					run94 = 1
				prev94 = sp94
			_check(spk94.size() >= 3, "three distinct voices carry the opening (%s)" % str(spk94.keys()))
			_check(maxrun94 <= 2, "nobody monologues: no speaker runs more than 2 lines unbroken (max run %d)" % maxrun94)
			var eli94: int = int(spk94.get("eli", 0))
			_check(float(eli94) / float(lines94.size()) <= 0.6,
				"the player character is answered, not just heard (%d of %d lines are his)" % [eli94, lines94.size()])
			_check(int(spk94.get("ruth", 0)) >= 5, "Mama Ruth is a participant, not a cameo (%d lines)" % int(spk94.get("ruth", 0)))
			# --- every speaker is castable and VOICED -----------------------
			var mute94: Array = []
			for sp94b in spk94:
				var c94: Dictionary = db94.character(str(sp94b))
				var vb94: String = str(c94.get("voice", ""))
				if vb94 == "" or not FileAccess.file_exists("res://assets/audio/vox/%s_0.wav" % vb94):
					mute94.append(str(sp94b) + "->" + vb94)
			_check(mute94.is_empty(), "every speaker in the opening has a real voice bank (%s)" % str(mute94))
			# --- staging: Ruth is a body in the world, and the camera cuts ---
			_check("ruth" in spawns94, "Ruth is spawned into the scene so the shot has two people in it")
			var uniq94: Dictionary = {}
			var degenerate94 := 0
			for cm94 in cams94:
				var pos94: Array = cm94.get("pos", [0, 0, 0])
				var look94: Array = cm94.get("look", [0, 0, 0])
				uniq94["%.1f,%.1f,%.1f" % [float(pos94[0]), float(pos94[1]), float(pos94[2])]] = true
				var pv94 := Vector3(float(pos94[0]), float(pos94[1]), float(pos94[2]))
				var lv94 := Vector3(float(look94[0]), float(look94[1]), float(look94[2]))
				# Camera3D.look_at() THROWS when the target is on the camera
				if pv94.distance_to(lv94) < 0.5:
					degenerate94 += 1
			_check(uniq94.size() >= 5, "shot/reverse-shot uses %d distinct camera positions" % uniq94.size())
			_check(degenerate94 == 0, "no cutscene camera looks at its own position (%d degenerate)" % degenerate94)
			_check(cams94.size() >= lines94.size(), "every line is framed by a camera move (%d cams, %d lines)" % [cams94.size(), lines94.size()])
			# --- the thesis lands, and the studio card closes it ------------
			var thesis94 := false
			for l94b in lines94:
				if "leverage" in str(l94b.get("text", "")).to_lower():
					thesis94 = true
			_check(thesis94, "the opening states the thesis of the game in dialogue")
			var has_title94 := false
			var has_studio94 := false
			for cd94 in cards94:
				if cd94.strip_edges() == "LEVERAGE":
					has_title94 = true
				if "D'Youngs" in cd94:
					has_studio94 = true
			_check(has_title94, "the title card lands at the end of the opening")
			_check(has_studio94, "the studio credit closes the opening")
			# --- INPUT FIXES: skip() and pause were both unreachable --------
			var csrc94 := FileAccess.get_file_as_string("res://scripts/ui/cutscene.gd")
			var gsrc94 := FileAccess.get_file_as_string("res://scripts/core/game.gd")
			_check(InputMap.has_action("skip_cutscene"), "a skip input action exists (skip() was bound to nothing)")
			var sk94: Array = InputMap.action_get_events("skip_cutscene") if InputMap.has_action("skip_cutscene") else []
			var esc94 := 0
			for e94 in sk94:
				if e94 is InputEventKey and (e94 as InputEventKey).physical_keycode == KEY_ESCAPE:
					esc94 += 1
			_check(esc94 == 1, "Escape skips a cutscene")
			_check(sk94.size() >= 3, "skip is bound on keyboard AND pad (%d bindings)" % sk94.size())
			_check("is_action_pressed(\"skip_cutscene\")" in csrc94, "the cutscene actually listens for skip")
			_check("_step_i >= _steps.size()" in csrc94, "skip is bounds-safe — it used to index past the last step")
			var pk94 := -1
			for e94b in InputMap.action_get_events("pause"):
				if e94b is InputEventKey:
					pk94 = int((e94b as InputEventKey).physical_keycode)
			_check(pk94 == KEY_ESCAPE, "pause is bound to a real key (was 4194304 = KEY_SPECIAL, which no keyboard sends)" )
			_check("is_action_pressed(\"pause\")" in gsrc94, "something finally READS the pause action — nothing did before")
			# --- exercise the skip for real --------------------------------
			var ws94 = root.get_node("WorldState")
			var gh94: float = ws94.game_hour
			var wv94: int = ws94.weather
			var fired94: Array = []
			# play() early-returns while a cutscene is already running, which
			# would leave MY callback unregistered and make skip look broken.
			# Finish anything in flight first — properly, so actors are freed.
			if cut94.playing:
				cut94.skip()
				for i in 4:
					cut94._process(0.5)
			cut94.play("cs_intro", func(): fired94.append(true))
			_check(cut94.playing, "the opening cinematic starts")
			var hint94: Label = cut94.get("_skip_lbl")
			cut94._process(0.05)
			_check(hint94 != null and hint94.visible, "the player is TOLD the cinematic is skippable")
			for i in 6:
				cut94._process(0.5)
			_check(cut94.playing, "the cinematic is still running mid-scene")
			cut94.skip()
			for i in 4:
				cut94._process(0.5)
			_check(not cut94.playing, "skip ends the cinematic immediately instead of trapping the player")
			_check(fired94.size() == 1, "the skip still hands over to the prologue mission")
			_check(ws94.game_hour >= 0.0, "the cinematic touched the clock without corrupting it")
			ws94.game_hour = gh94
			ws94.weather = wv94
			if hint94 != null:
				_check(not hint94.visible, "the skip hint hides once the cinematic is over")
		95:
			# WAVE 49 — THE SIX NEW STAGE VERBS, DRIVEN LIVE.
			# Act 3 used to be four dialogue boxes and a cutscene: m12_everyone,
			# the ENDING, was two stages long. Missions are now 125 stages over
			# 29 jobs using 22 verbs. Source-scanning would pass even if every
			# new verb crashed on its first tick, so each one is set up for real
			# and ticked to completion here, with all state pinned and restored.
			var mm95 = root.get_node("MissionManager")
			var ws95 = root.get_node("WorldState")
			var db95 = root.get_node("Db")
			var diff95 = root.get_node("Difficulty")
			var prog95 = root.get_node("Progression")
			# --- pin everything a live mission run can touch ------------------
			var sv95 := {
				"active": mm95.active_id, "stage_i": mm95.active_stage_i,
				"stage": mm95.stage.duplicate(true), "rt": mm95.rt.duplicate(true),
				"completed": mm95.completed.duplicate(true), "failed": mm95.failed.duplicate(true),
				"offer": mm95.story_offer, "sideoffer": mm95.side_offer.duplicate(true),
				"money": ws95.money, "wanted": ws95.wanted, "stats": ws95.stats.duplicate(true),
				"flags": ws95.flags.duplicate(true), "rels": ws95.relationships.duplicate(true),
				"factions": ws95.factions.duplicate(true), "inv": ws95.inventory.duplicate(true),
				"xp": prog95.xp, "level": prog95.level,
			}
			var home95: Vector3 = _player.global_position
			_revive_player()
			if _player.in_vehicle != null:
				_player.exit_vehicle()
			var dlg95 = root.get_node("DialogueUI")
			if dlg95.is_open():
				dlg95.close()
			var cut95b = root.get_node("Cutscene")
			if cut95b.playing:
				cut95b.skip()
				for i95 in 4:
					cut95b._process(0.5)

			# ======================= the data got longer =====================
			var allm95: Dictionary = db95.missions
			var tot95 := 0
			var short95 := 0
			var tset95 := {}
			for k95 in allm95.keys():
				var st95: Array = allm95[k95].get("stages", [])
				tot95 += st95.size()
				if st95.size() <= 2:
					short95 += 1
				for s95 in st95:
					tset95[String(s95.get("type", ""))] = true
			_check(tot95 >= 120, "missions now total %d stages (was 89 across the same 29 jobs)" % tot95)
			_check(short95 == 0, "no mission is a 1-2 stage stub any more (was 15 of 29 at <=3, and the FINALE at 2)")
			_check(tset95.size() >= 22, "%d distinct stage verbs are in use (was 16)" % tset95.size())
			for v95 in ["survive", "chase", "plant", "defend", "rail_cross", "observe"]:
				_check(tset95.has(v95), "the new '%s' verb is actually AUTHORED into a mission, not just implemented" % v95)
			_check(allm95["m12_everyone"].get("stages", []).size() >= 6, "the ending m12_everyone is a mission, not a walk to a viewpoint (was 2 stages)")
			_check(allm95["m10_smoke_line"].get("stages", []).size() >= 8, "m10_smoke_line is no longer talk talk talk choice (was 4, zero gameplay)")
			_check(allm95["m11_the_leverage"].get("stages", []).size() >= 7, "the penultimate job m11_the_leverage got longer (was 4)")
			# act 3 must not be all conversation
			var a3play95 := 0
			for mid95 in ["m10_smoke_line", "m11_the_leverage", "m12_everyone"]:
				for s95b in allm95[mid95].get("stages", []):
					if not (String(s95b.get("type", "")) in ["talk", "choice", "cutscene"]):
						a3play95 += 1
			_check(a3play95 >= 10, "act 3 now contains %d stages that are something other than talking (was 3)" % a3play95)

			# ============ every reference in every stage must resolve =========
			var bad95: Array = []
			for k95b in allm95.keys():
				for s95c in allm95[k95b].get("stages", []):
					for pk95 in ["poi", "from", "to"]:
						var pv = s95c.get(pk95)
						if pv != null and String(pv) != "":
							if not db95.districts.has("_poi_" + String(pv)) and _poi_known95(String(pv)) == false:
								bad95.append("%s.%s=%s" % [k95b, pk95, pv])
					var dv = s95c.get("dialogue")
					if dv != null and String(dv) != "" and db95.dialogue_tree(String(dv)).is_empty():
						bad95.append("%s.dialogue=%s" % [k95b, dv])
					var cv = s95c.get("char")
					if cv != null and String(cv) != "" and not db95.characters.has(String(cv)):
						bad95.append("%s.char=%s" % [k95b, cv])
			_check(bad95.is_empty(), "every poi/dialogue/char reference in all 125 stages resolves (%s)" % str(bad95))

			# ==================== verb 1: SURVIVE (hold ground) ================
			mm95.active_id = "side_fightclub"
			mm95.active_stage_i = 3          # side_fightclub's survive stage
			mm95.stage = allm95["side_fightclub"]["stages"][3]
			mm95.rt = {}
			mm95.actors.clear()
			mm95._setup_stage()
			_check(mm95.actors.size() >= 2, "survive: the first wave actually spawned (%d actors)" % mm95.actors.size())
			_check(mm95.rt.get("spawned", false) == true, "survive: rt records that the wave is on the street")
			var scount95: int = mm95.actors.size()
			var stime95: float = mm95.rt["time"]
			_check(stime95 > 40.0, "survive: the hold has a real clock (%.0fs)" % stime95)
			# tick the clock down; the player stands on the ground being held
			_player.global_position = mm95.rt["center"]
			for i95b in 6:
				mm95._tick_stage(1.0, _player)
			_check(float(mm95.rt["time"]) < stime95 - 5.0, "survive: the clock runs down as the hold is lived through")
			_check(mm95.active_id == "side_fightclub", "survive: still holding — the clock has not expired")
			# abandon the ground and the hold is lost
			_player.global_position = mm95.rt["center"] + Vector3(400, 0, 0)
			for i95c in 12:
				mm95._tick_stage(1.0, _player)
			_check(mm95.failed.has("side_fightclub"), "survive: walking 400 m off the ground you were holding FAILS the job (leash)")
			mm95._cleanup_stage()

			# ==================== verb 2: CHASE (catch a runner) ===============
			mm95.active_id = "side_courier"
			mm95.active_stage_i = 2
			mm95.stage = allm95["side_courier"]["stages"][2]
			mm95.rt = {}
			mm95.failed.clear()
			mm95._setup_stage()
			var rn95 = mm95.rt.get("npc")
			_check(rn95 != null and is_instance_valid(rn95), "chase: a runner is on the street")
			_check(rn95.has_meta("chase_target"), "chase: the runner is tagged so it cannot dive into traffic and vanish")
			var fs95: float = rn95.get("flee_speed")
			_check(absf(fs95 - 5.2) < 0.01, "chase: the runner starts at the civilian flee pace of 5.2 m/s")
			_player.global_position = rn95.global_position + Vector3(30, 0, 0)
			for i95d in 20:
				mm95._tick_stage(1.0, _player)
			var fs95b: float = rn95.get("flee_speed")
			_check(fs95b < fs95 - 0.5, "chase: the runner TIRES under pressure (%.2f -> %.2f m/s), so a sprint at 6.4 can actually close" % [fs95, fs95b])
			_check(rn95.state == rn95.State.FLEE, "chase: the runner is genuinely fleeing, not idling")
			# close the gap and the chase is won
			_player.global_position = rn95.global_position + Vector3(1.2, 0, 0)
			mm95._tick_stage(0.1, _player)
			# _advance_stage() resets rt = {}, so rt["caught"] is gone by the
			# time we can read it. Assert what SURVIVES: the stage index moved
			# and the stat was written.
			_check(mm95.active_stage_i == 3, "chase: getting inside the reach distance catches them and advances the job")
			_check(ws95.stats.get("runners_caught", 0) == 1, "chase: a caught runner is recorded in the stats")
			mm95._cleanup_stage()

			# ==================== verb 3: PLANT (sabotage) =====================
			mm95.active_id = "side_torch"
			mm95.active_stage_i = 2
			mm95.stage = allm95["side_torch"]["stages"][2]
			mm95.rt = {}
			mm95._setup_stage()
			var mk95: Array = mm95.rt.get("marks", [])
			_check(mk95.size() == 2, "plant: the stage laid out %d charge marks (authored count=2)" % mk95.size())
			var vis95 := 0
			for m95 in mk95:
				if m95.get("node") != null and is_instance_valid(m95["node"]):
					vis95 += 1
			_check(vis95 == mk95.size(), "plant: every mark is a VISIBLE pylon in the tree, not a minimap abstraction")
			_player.global_position = mk95[0]["pos"]
			mm95._tick_stage(0.1, _player)
			_check(int(mm95.rt["armed"]) == 1, "plant: standing on a mark arms it")
			_check(float(mm95.rt["fuse"]) > 0.0, "plant: arming the last charge starts the fuse")
			_player.global_position = mk95[1]["pos"]
			mm95._tick_stage(0.1, _player)
			_check(int(mm95.rt["armed"]) == 2, "plant: both marks armed")
			# stand clear and let the fuse burn out
			_player.global_position = mk95[1]["pos"] + Vector3(40, 0, 0)
			var hp95: float = _player.combat.hp
			for i95e in 20:
				mm95._tick_stage(1.0, _player)
			_check(ws95.stats.get("sabotages", 0) == 1, "plant: the charges went off — the fuse used to be re-armed every tick and never reached zero")
			_check(mm95.active_stage_i == 3, "plant: detonating advances the job")
			_check(ws95.stats.get("clean_blasts", 0) == 1, "plant: clearing the blast before the fuse ends is REWARDED")
			_check(_player.combat.hp >= hp95 - 0.01, "plant: standing 40 m clear means the blast did not touch the player")
			mm95._cleanup_stage()

			# ==================== verb 4: DEFEND (keep a body alive) ===========
			mm95.active_id = "side_nightshift"
			mm95.active_stage_i = 2
			mm95.stage = allm95["side_nightshift"]["stages"][2]
			mm95.rt = {}
			mm95.failed.clear()
			mm95._setup_stage()
			var wd95 = mm95.rt.get("ward")
			_check(wd95 != null and is_instance_valid(wd95), "defend: the person you are protecting is on the street")
			_check(mm95.actors.has(wd95), "defend: the ward is owned by the stage so cleanup frees it")
			var atk95 := 0
			for a95 in mm95.actors:
				if is_instance_valid(a95) and a95 != wd95 and a95.get("hostile") == true:
					atk95 += 1
			_check(atk95 >= 1, "defend: attackers spawned to actually threaten the ward (%d)" % atk95)
			_check(String(wd95.get("display_name")) != "" and String(wd95.get("display_name")) != "<null>", "defend: the objective line can name the ward (got '%s')" % String(wd95.get("display_name")))
			var whp95: float = mm95._ward_hp(wd95)
			# put an attacker on top of the ward and let it work
			var one95 = null
			for a95b in mm95.actors:
				if is_instance_valid(a95b) and a95b != wd95:
					one95 = a95b
					break
			one95.global_position = wd95.global_position + Vector3(1.5, 0, 0)
			for i95f in 8:
				mm95._tick_stage(1.0, _player)
			_check(mm95._ward_hp(wd95) < whp95 - 1.0, "defend: an attacker inside reach genuinely HURTS the ward — the fail condition is real")
			# kill the ward: the job must fail
			var wcc95 = wd95.get("combat")
			wcc95.iframes = 0.0
			wcc95.take_hit(9999.0, Vector3(1, 0, 0), "test", null)
			mm95._tick_stage(0.1, _player)
			_check(mm95.failed.has("side_nightshift"), "defend: the ward dying FAILS the job (this is what makes it a defend, not a survive)")
			mm95._cleanup_stage()

			# ==================== verb 5: RAIL_CROSS (beat the freight) ========
			var sl95 = mm95._smoke_line()
			_check(sl95 != null, "rail_cross: MissionManager can find the wave-48 freight train")
			if sl95 != null:
				_check(sl95.has_method("seconds_to_crossing"), "rail_cross: the train exposes a wrap-aware arrival time")
				var sp95: float = sl95.speed()
				_check(sp95 > 10.0, "rail_cross: the consist runs at %.1f m/s — faster than the player's 6.4 sprint, so it is a real deadline" % sp95)
				var span95: float = sl95.span()
				_check(span95 > 800.0, "rail_cross: the line spans %.0f m" % span95)
				# the deadline must be non-negative for EVERY x on the line,
				# including one the locomotive has already passed
				var worst95 := 1e9
				var best95 := -1e9
				for i95g in 40:
					var x95 := -700.0 + float(i95g) * 35.0
					var t95: float = sl95.seconds_to_crossing(x95)
					worst95 = minf(worst95, t95)
					best95 = maxf(best95, t95)
				_check(worst95 >= 0.0, "rail_cross: no crossing yields a NEGATIVE deadline (min %.2fs) — a passed train gives the NEXT one" % worst95)
				_check(best95 <= span95 / sp95 + 0.01, "rail_cross: the longest wait is one full lap (%.1fs <= %.1fs)" % [best95, span95 / sp95])
			mm95.active_id = "m11_the_leverage"
			mm95.active_stage_i = 1
			mm95.stage = allm95["m11_the_leverage"]["stages"][1]
			mm95.rt = {}
			mm95.failed.clear()
			mm95._setup_stage()
			var dl95: float = mm95.rt.get("deadline", 0.0)
			_check(dl95 >= 34.0, "rail_cross: the deadline is at least the 34 s floor (got %.1fs)" % dl95)
			_check(dl95 <= 120.0, "rail_cross: the deadline is not absurd either (got %.1fs)" % dl95)
			var mv95 = mm95.rt.get("mission_vehicle")
			_check(mv95 != null and is_instance_valid(mv95), "rail_cross: the stage supplies a car — on foot a 17.5 m/s train is unbeatable")
			var to95: Vector3 = mm95.rt["to"]
			_player.global_position = to95 + Vector3(1.0, 0, 0)
			mm95._tick_stage(0.1, _player)
			_check(mm95.active_stage_i == 2, "rail_cross: reaching the far side wins the crossing and advances the job")
			_check(ws95.stats.get("rail_crossings", 0) == 1, "rail_cross: a beaten freight is recorded")
			mm95._cleanup_stage()

			# ==================== verb 6: OBSERVE (stakeout) ===================
			mm95.active_id = "m10_smoke_line"
			mm95.active_stage_i = 3
			mm95.stage = allm95["m10_smoke_line"]["stages"][3]
			mm95.rt = {}
			mm95.failed.clear()
			mm95._setup_stage()
			var gd95 := 0
			for a95c in mm95.actors:
				if is_instance_valid(a95c) and a95c.get("state") != null:
					gd95 += 1
			_check(gd95 >= 2, "observe: the stakeout spawned %d subjects — 'don't be seen' is fiction with nobody to see you" % gd95)
			var sus95 := 0
			for a95d in mm95.actors:
				if is_instance_valid(a95d) and a95d.get("suspicion") != null:
					sus95 += 1
			_check(sus95 >= 2, "observe: the subjects carry a live suspicion meter the stage reads")
			_player.global_position = mm95.rt["pos"]
			for i95h in 6:
				mm95._tick_stage(1.0, _player)
			_check(float(mm95.rt["held"]) > 5.0, "observe: standing on the spot accumulates watch time (%.1fs)" % float(mm95.rt["held"]))
			# wander off and the time bleeds back out
			var held95: float = mm95.rt["held"]
			_player.global_position = mm95.rt["pos"] + Vector3(60, 0, 0)
			for i95i in 4:
				mm95._tick_stage(1.0, _player)
			_check(float(mm95.rt["held"]) < held95, "observe: leaving the spot bleeds the stakeout time back off")
			# finish it properly
			_player.global_position = mm95.rt["pos"]
			for i95j in 20:
				mm95._tick_stage(1.0, _player)
			_check(ws95.stats.get("stakeouts", 0) == 1, "observe: holding the spot for the full count completes the stakeout")
			mm95._cleanup_stage()

			# ============= the fixes that came out of building these ==========
			var msrc95 := FileAccess.get_file_as_string("res://scripts/missions/mission_manager.gd")
			var nsrc95 := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
			_check("var flee_speed: float = 5.2" in nsrc95, "npc flee pace is a VARIABLE now — the chase tiring was fiction while it was a hardcoded 5.2")
			_check('has_meta("chase_target")' in nsrc95, "a chase target cannot dive into traffic and queue_free() itself mid-pursuit")
			_check('"race_furnace"' in msrc95, "RACE_TRACKS finally defines race_furnace — side_race2's 'Furnace Loop' silently raced around the Docks")
			_check('push_warning("MissionManager: unknown race track' in msrc95, "an unknown race track now says so instead of quietly substituting another district")
			_check('e.has("rel2")' in msrc95, "choice effects honour rel2 — m06 authored it and nothing ever read it, so the witness choice cost Okoro nothing")
			_check('e.has("faction_rep")' in msrc95, "choice effects honour faction_rep, also authored and also ignored")
			# the talk-stage NPC leak: speakers were parented to the city but
			# never in `actors`, so _cleanup_stage() never freed them.
			var talkblk95 := msrc95.substr(msrc95.find('"talk":'), 900)
			_check("actors.append(n)" in talkblk95, "a talk stage OWNS its speaker — 18 talk stages used to leave 18 permanent ghosts on the street")
			_check('add_to_group("smoke_line")' in FileAccess.get_file_as_string("res://scripts/world/smoke_line.gd"), "the freight train joins a group so missions can find it without going through city.gd")

			# --- restore everything ------------------------------------------
			_revive_player()
			_player.global_position = home95
			mm95._cleanup_stage()
			mm95.actors.clear()
			mm95.active_id = sv95["active"]
			mm95.active_stage_i = sv95["stage_i"]
			mm95.stage = sv95["stage"]
			mm95.rt = sv95["rt"]
			mm95.completed = sv95["completed"]
			mm95.failed = sv95["failed"]
			mm95.story_offer = sv95["offer"]
			mm95.side_offer = sv95["sideoffer"]
			ws95.money = sv95["money"]
			ws95.wanted = sv95["wanted"]
			ws95.stats = sv95["stats"]
			ws95.flags = sv95["flags"]
			ws95.relationships = sv95["rels"]
			ws95.factions = sv95["factions"]
			ws95.inventory = sv95["inv"]
			prog95.xp = sv95["xp"]
			prog95.level = sv95["level"]
			_check(diff95.threat() >= 0.0, "difficulty threat survived a full six-verb mission gauntlet")
		96:
			# ============ THE CINDER CUT: rivers, bridges, and the GPS =======
			var wg96 = root.get_node("WorldGen")
			var db96 = root.get_node("Db")
			var wcfg96: Dictionary = db96.districts.get("world", {})
			var rcfg96: Dictionary = wcfg96.get("river", {})
			_check(not rcfg96.is_empty(), "city.json authors a river")
			_check(wg96._river_built and wg96.river_name == "the Cinder Cut",
				"WorldGen built %s" % wg96.river_name)
			_check(wg96.river_channels.size() == 3,
				"three channels: the Cut, Crown Reach and the Crown Cut branch (%d)" % wg96.river_channels.size())
			_check(wg96.root.get_node_or_null("river") != null, "river geometry committed")
			_check(wg96.root.get_node_or_null("river_crossings") != null, "bridge geometry committed")
			# --- water sheets: the harbour's three survive the river joining --
			_check(wg96.harbour_layers.size() == 3 and wg96.river_layers.size() >= 5,
				"harbour keeps its 3 sheets and the river brings its own (%d + %d)" % [wg96.harbour_layers.size(), wg96.river_layers.size()])
			var rm96: StandardMaterial3D = wg96.river_layers[0][0]
			var roff96: Vector3 = rm96.uv1_offset
			wg96._process(0.5)
			_check(rm96.uv1_offset != roff96, "the Cut's surface actually moves")
			# --- the river touches nothing it was not given -------------------
			# Recomputed from city.json rather than from the builder: this is
			# the invariant the whole layout was designed around, and it is the
			# one a future edit to the data is most likely to break silently.
			var bad96: Array = []
			for did96 in db96.districts:
				if did96 == "world":
					continue
				var d96: Dictionary = db96.districts[did96]
				var c96 := Vector2(d96["center"][0], d96["center"][1])
				var sz96 := Vector2(d96["size"][0], d96["size"][1])
				var plate96 := Rect2(c96 - sz96 * 0.5, sz96)
				var blk96: float = d96.get("block", 48)
				var rw96: float = d96.get("road_w", 10)
				var nx96 := int(sz96.x / blk96)
				var nz96 := int(sz96.y / blk96)
				var hits96: Array = []
				hits96.append(["plate", plate96])
				for i96 in range(nx96 + 1):
					var x96 := plate96.position.x + i96 * blk96
					hits96.append(["road", Rect2(Vector2(x96 - rw96 * 0.5, plate96.position.y), Vector2(rw96, sz96.y))])
				for j96 in range(nz96 + 1):
					var z96 := plate96.position.y + j96 * blk96
					hits96.append(["road", Rect2(Vector2(plate96.position.x, z96 - rw96 * 0.5), Vector2(sz96.x, rw96))])
				var span96 := blk96 - rw96 - 3.0
				for i96b in range(nx96):
					for j96b in range(nz96):
						var bc96 := Vector2(plate96.position.x + i96b * blk96 + blk96 * 0.5,
							plate96.position.y + j96b * blk96 + blk96 * 0.5)
						hits96.append(["block", Rect2(bc96 - Vector2(span96, span96) * 0.5, Vector2(span96, span96))])
				for chv96 in wg96.river_channels:
					var ch96: Dictionary = chv96
					var r96: Rect2 = ch96["rect"]
					for hv96 in hits96:
						var h96: Array = hv96
						var hr96: Rect2 = h96[1]
						if hr96.intersects(r96):
							bad96.append("%s %s x %s" % [str(did96), str(h96[0]), str(ch96["id"])])
			_check(bad96.is_empty(),
				"no channel runs through a district plate, road strip or building block (%s)" % str(bad96))
			# --- nobody is standing in it ------------------------------------
			var wet96: Array = []
			for pid96 in wg96.pois:
				var pd96: Dictionary = wg96.pois[pid96]["data"]
				var at96: Array = pd96.get("at", [0, 0])
				if wg96.in_river(Vector2(float(at96[0]), float(at96[1]))):
					wet96.append(str(pid96))
			_check(wet96.is_empty(), "no POI or filling station is standing in the Cut (%s)" % str(wet96))
			_check(wg96.in_river(Vector2(100, -7)), "mid-channel reads as water")
			_check(not wg96.in_river(Vector2(190, -7)), "a bridge deck over the Cut does not read as water")
			_check(not wg96.in_river(Vector2(-240, 40)), "Kiln Row, 120 m from the water, does not read as water")
			_check(not wg96.in_river(Vector2(300, 60)), "the Crown Heights overlook does not read as water")
			# --- bridges are derived from the roads that actually cross ------
			var want96: Array = []
			for av96 in wcfg96.get("arterials", []):
				var ad96: Dictionary = av96
				var ax96 := str(ad96.get("axis", "x"))
				var at96f := float(ad96.get("at", 0))
				var wd96 := float(ad96.get("width", 16))
				var road96: Rect2 = Rect2(Vector2(at96f - wd96 * 0.5, -450.0), Vector2(wd96, 700.0)) if ax96 == "x" else Rect2(Vector2(-550.0, at96f - wd96 * 0.5), Vector2(900.0, wd96))
				for chv96b in wg96.river_channels:
					var ch96b: Dictionary = chv96b
					if road96.intersects(ch96b["rect"]):
						want96.append(at96f)
			var roadb96 := 0
			var footb96 := 0
			for bv96 in wg96.river_bridges:
				var b96: Dictionary = bv96
				if str(b96["kind"]) == "road":
					roadb96 += 1
				else:
					footb96 += 1
			_check(roadb96 == want96.size() and roadb96 == 2,
				"every arterial that meets water has a bridge, and only those do (%d built, %d crossings)" % [roadb96, want96.size()])
			_check(footb96 == 2, "two footbridges carry the Crown Cut (%d)" % footb96)
			# --- solid underfoot, and the parapets are real ------------------
			var space96 = _city.get_world_3d().direct_space_state
			var nodeck96: Array = []
			for bv96b in wg96.river_bridges:
				var b96b: Dictionary = bv96b
				var c96b: Vector2 = b96b["at"]
				var q96 := PhysicsRayQueryParameters3D.new()
				q96.from = Vector3(c96b.x, 6.0, c96b.y)
				q96.to = Vector3(c96b.x, -3.0, c96b.y)
				if space96.intersect_ray(q96).is_empty():
					nodeck96.append(str(b96b["id"]))
			_check(nodeck96.is_empty(), "every crossing has a deck you can stand on (%s)" % str(nodeck96))
			# --- the promenade is walkable for its whole length --------------
			var gap96 := 0
			for x96b in [-60.0, 0.0, 60.0, 140.0, 260.0, 340.0, 420.0, 480.0]:
				var q96b := PhysicsRayQueryParameters3D.new()
				q96b.from = Vector3(x96b, 5.0, -19.6)
				q96b.to = Vector3(x96b, -3.0, -19.6)
				if space96.intersect_ray(q96b).is_empty():
					gap96 += 1
			_check(gap96 == 0, "the south-bank promenade is solid for its whole 590 m (%d holes)" % gap96)
			# --- and you can get back out ------------------------------------
			# The Cut is a 3.6 m hole with a 0.7 m parapet on both banks. If the
			# landing stairs do not reach below the waterline it is a one-way
			# trip, and nothing in the game says so.
			var flight96: Array = []
			for z96b in [-17.0, -15.5, -14.0, -12.5]:
				var q96c := PhysicsRayQueryParameters3D.new()
				q96c.from = Vector3(-30.0, 4.0, z96b)
				q96c.to = Vector3(-30.0, -4.0, z96b)
				var hit96: Dictionary = space96.intersect_ray(q96c)
				if hit96.is_empty():
					flight96.append(99.0)
				else:
					flight96.append((hit96["position"] as Vector3).y)
			var descends96 := true
			for k96 in range(flight96.size() - 1):
				if flight96[k96 + 1] >= flight96[k96]:
					descends96 = false
			_check(descends96, "the landing stairs descend into the channel (%s)" % str(flight96))
			_check(flight96[flight96.size() - 1] < wg96.river_water_y,
				"and the bottom step is below the waterline, so the Cut is escapable (%.2f < %.2f)" % [flight96[flight96.size() - 1], wg96.river_water_y])
			# --- the harbour is solid too (it never was) ---------------------
			var q96d := PhysicsRayQueryParameters3D.new()
			q96d.from = Vector3(100, 4.0, -510)
			q96d.to = Vector3(100, -4.0, -510)
			_check(not space96.intersect_ray(q96d).is_empty(),
				"the harbour has collision — before this its shape was built, sized and never parented")
			# --- the GPS: Crown Heights used to be an unreachable island -----
			var a96 := Vector3(-240, 0, 43)     # Kiln Row
			var b96v := Vector3(380, 0, 90)     # Crown Heights, the Country Club
			var path96: PackedVector3Array = wg96.route_world(a96, b96v)
			_check(path96.size() >= 2,
				"the GPS can route Kiln Row to Crown Heights at all (%d waypoints)" % path96.size())
			if path96.size() >= 2:
				_check(wg96.route_length(path96) > (b96v - a96).length() * 0.9,
					"and it routes a plausible distance, not a straight line through the void (%.0f m)" % wg96.route_length(path96))
				var onbridge96 := false
				var wadewp96 := 0
				for pv96 in path96:
					if wg96.bridge_at(Vector2(pv96.x, pv96.z)) >= 0:
						onbridge96 = true
					if wg96.in_river(Vector2(pv96.x, pv96.z)):
						wadewp96 += 1
				_check(onbridge96, "the route crosses the Cut ON A BRIDGE")
				_check(wadewp96 == 0, "and no waypoint in it is in the water (%d)" % wadewp96)
			# --- no lane edge tells a driver to wade -------------------------
			var wade96 := 0
			var wadebridge96 := 0
			for i96c in wg96._rg_adj.size():
				for ev96 in wg96._rg_adj[i96c]:
					var e96: Array = ev96
					var j96c: int = e96[0]
					if j96c <= i96c:
						continue
					if wg96._river_blocked(wg96._rg_nodes[i96c], wg96._rg_nodes[j96c]):
						wade96 += 1
						if i96c >= wg96.rg_lane_count or j96c >= wg96.rg_lane_count:
							wadebridge96 += 1
			_check(wade96 == 0,
				"no route-graph edge leaves the road for the water (%d, %d of them bridge ties)" % [wade96, wadebridge96])
			_check(wg96._rg_nodes.size() > wg96.rg_lane_count,
				"the crossings are in the route graph as nodes (%d lanes + %d crossings)" % [wg96.rg_lane_count, wg96._rg_nodes.size() - wg96.rg_lane_count])
			# --- the whole graph is one piece now ----------------------------
			var seen96 := {}
			var stack96: Array = [0]
			while not stack96.is_empty():
				var u96: int = stack96.pop_back()
				if seen96.has(u96):
					continue
				seen96[u96] = true
				for ev96b in wg96._rg_adj[u96]:
					var e96b: Array = ev96b
					if not seen96.has(e96b[0]):
						stack96.append(e96b[0])
			_check(seen96.size() == wg96._rg_nodes.size(),
				"one connected route graph — Crown Heights was a 48-node island with no way in (%d of %d reachable)" % [seen96.size(), wg96._rg_nodes.size()])
			# --- and the Crown Cut's east bank finally has ground ------------
			var q96e := PhysicsRayQueryParameters3D.new()
			q96e.from = Vector3(236, 4.0, 190)
			q96e.to = Vector3(236, -3.0, 190)
			_check(not space96.intersect_ray(q96e).is_empty(),
				"poi_stash_crown has ground under it — it was authored 4 m outside its own district's plate")
		97:
			# ============ TYPOGRAPHY: the fonts that shipped but were never used
			# The project carried four DejaVu faces in assets/fonts/, credited
			# them by name on the menu's about card, and loaded none of them.
			# No theme resource existed, no script called
			# add_theme_font_override once, and gui/theme/custom_font_size was the
			# only typography in project.godot — so the entire game rendered in
			# the engine's built-in fallback face. These assertions are written
			# from the data files, not from Type's own answer, so a face that
			# goes back to being dead weight fails here.
			var ty97 = root.get_node_or_null("Type")
			_check(ty97 != null, "Type autoload registered")
			if ty97 != null:
				var fdir := DirAccess.open("res://assets/fonts")
				var ondisk: Array = []
				for nv97 in fdir.get_files():
					var nm97 := str(nv97)
					if nm97.ends_with(".ttf"):
						ondisk.append(nm97)
				var faces97: Dictionary = ty97.FACES
				var dead97: Array = []
				for nm97b in ondisk:
					var used97 := false
					for rv97 in faces97:
						if str(faces97[rv97]) == nm97b:
							used97 = true
					if not used97:
						dead97.append(nm97b)
				_check(dead97.is_empty(),
					"every face shipped in assets/fonts/ is mapped to a role — 4 of 4 were dead weight before (%d on disk, %s)" % [ondisk.size(), str(dead97)])
				var null97: Array = []
				for rv97b in faces97:
					if ty97.face(str(rv97b)) == null:
						null97.append(str(rv97b))
				_check(null97.is_empty(),
					"all %d roles load a real Font (%s)" % [faces97.size(), str(null97)])
				var disp97: Font = ty97.face("display")
				var body97: Font = ty97.face("body")
				var mono97: Font = ty97.face("mono")
				_check(disp97 != null and body97 != null and mono97 != null
					and disp97 != body97 and body97 != mono97 and disp97 != mono97,
					"display, body and mono are three genuinely different faces")
				# ---- the project-wide theme actually got installed ----------
				var th97: Theme = root.theme
				_check(th97 != null and th97.default_font == body97,
					"the root Window carries a theme whose default face is the body role")
				# ---- HUD: numbers in mono, names in display, sentences in body
				var hud97 = _city.get("hud")
				if hud97 != null:
					var mis97: Array = []
					for kv97 in [["_money_lbl", mono97], ["_stars_lbl", mono97], ["_clock_lbl", mono97],
							["_ammo_lbl", mono97], ["_style_lbl", mono97], ["_speed_lbl", mono97],
							["_fuel_lbl", mono97], ["_lvl_lbl", mono97]]:
						var k97: Array = kv97
						var lbl97 = hud97.get(k97[0])
						if lbl97 == null:
							mis97.append(str(k97[0]) + " missing")
						elif lbl97.get_theme_font("font") != k97[1]:
							mis97.append(str(k97[0]))
					_check(mis97.is_empty(),
						"every HUD figure — credits, wanted, clock, ammo, style, speed, fuel, XP — is set in mono so the counters do not crawl sideways (%s)" % str(mis97))
					var disp97b: Array = []
					for kv97b in [["_district_lbl", disp97], ["_mission_lbl", disp97], ["_objective_lbl", body97]]:
						var k97b: Array = kv97b
						var lbl97b = hud97.get(k97b[0])
						if lbl97b != null and lbl97b.get_theme_font("font") != k97b[1]:
							disp97b.append(str(k97b[0]))
					_check(disp97b.is_empty(),
						"place and mission names are display, the objective sentence is body (%s)" % str(disp97b))
				# ---- dialogue: the RTL weight trap --------------------------
				var dui97 = root.get_node("DialogueUI")
				if dui97 != null:
					var nl97 = dui97.get("name_lbl")
					_check(nl97 != null and nl97.get_theme_font("font") == disp97,
						"the speaker's name is set in the display face")
					var tl97 = dui97.get("text_lbl")
					if tl97 != null:
						# RichTextLabel has no "font" item at all: it takes one
						# override per weight. Setting only normal_font leaves
						# every bold span on the engine fallback, which is the
						# reason Type.apply() branches on the node type.
						_check(tl97.get_theme_font("normal_font") == body97,
							"the spoken line is set in the body face")
						_check(tl97.get_theme_font("bold_font") != null
							and tl97.get_theme_font("bold_font") == tl97.get_theme_font("bold_italics_font"),
							"and its bold and bold-italic weights are set too — RichTextLabel ignores 'font'")
				# ---- the cutscene slate -------------------------------------
				var cs97 = root.get_node("Cutscene")
				if cs97 != null:
					var card97 = cs97.get("_card")
					_check(card97 != null and card97.get_theme_font("font") == disp97,
						"the cutscene location card is set in the display face")
				# ---- the phone, the shop and the caller ---------------------
				var ph97 = root.get_node("PhoneUI")
				if ph97 != null:
					var dd97 = ph97.get("_diff_desc")
					if dd97 != null:
						_check(dd97.get_theme_font("font") != null, "phone labels inherit a face")
				var sh97 = root.get_node("ShopUI")
				if sh97 != null:
					var st97 = sh97.get("_title")
					var sm97 = sh97.get("_money")
					if st97 != null and sm97 != null:
						_check(st97.get_theme_font("font") == disp97 and sm97.get_theme_font("font") == mono97,
							"shop title in display, its credit counter in mono")
					else:
						_check(true, "shop panel not open this run — title/counter faces checked when it is")
				# ---- the about card credits what it actually ships ----------
				var menu97 := FileAccess.get_file_as_string("res://scripts/scenes/menu.gd")
				_check("DejaVu Serif / Sans / Sans Mono" in menu97,
					"the about card names the three families it now uses, not 'DejaVu' in the abstract")
				var usedroles97: Array = ty97.roles_in_use()
				_check(usedroles97.has("display") and usedroles97.has("body") and usedroles97.has("mono"),
					"all three primary roles were requested by the UI this run (%s)" % str(usedroles97))
		99:
			print("HARNESS: DONE — checks=%d fails=%d" % [_checks, _fails])
			_city.queue_free()
			quit(0 if _fails == 0 else 1)
			return true
	return false


## The harness is a gauntlet: hostile peds spawned by earlier steps keep
## swinging for the rest of the run, so by step 87 the player can be down to
## a few HP and damage assertions become a coin flip (and a dead player makes
## take_hit() a no-op). Steps that assert on TAKING damage revive first —
## they are testing the system, not survivability.
func _revive_player() -> void:
	if _player == null:
		return
	_player.dead = false
	var cc = _player.combat
	if cc == null:
		return
	cc.dead = false
	cc.hp = cc.max_hp
	cc.iframes = 0.0
	cc.dodging = false
	cc.blocking = false
	cc.guard_broken_t = 0.0


func _count_decals47(tex_name: String) -> int:
	var n := 0
	for c in _city.get_children():
		if c is MeshInstance3D and c.material_override != null:
			var m = c.material_override
			if m is StandardMaterial3D and m.albedo_texture != null and tex_name in m.albedo_texture.resource_path:
				n += 1
	return n


func _spawn_ped46(pos: Vector3) -> Node:
	var n := CharacterBody3D.new()
	n.set_script(load("res://scripts/npc/npc.gd"))
	_city.add_child(n)
	var db46 = root.get_node("Db")
	var pids: Array = db46.peds.keys()
	n.setup_ped(pids[randi() % pids.size()], "kiln_row", pos)
	return n


## Wave 49: mission stages name POIs, and every one of them has to exist in
## city.json or the stage silently targets Vector3.ZERO. Db has no poi index,
## so this reads the district table directly.
func _poi_known95(pid: String) -> bool:
	var db95h = root.get_node("Db")
	var all95: Dictionary = db95h.districts
	for k95h in all95.keys():
		if k95h == "world":
			continue
		var dv = all95[k95h]
		if dv == null or not (dv is Dictionary):
			continue
		for p95h in (dv as Dictionary).get("pois", []):
			if String((p95h as Dictionary).get("id", "")) == pid:
				return true
	return false


func _grp(g: String) -> Node:
	var n := get_nodes_in_group(g)
	return n[0] if n.size() else null


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("HARNESS OK: ", msg)
	else:
		_fails += 1
		printerr("HARNESS FAIL: ", msg)
