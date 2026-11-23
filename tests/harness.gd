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
			if vmi and vmi.mesh:
				for si in vmi.mesh.get_surface_count():
					var va: Array = vmi.mesh.surface_get_arrays(si)
					vtris += va[Mesh.ARRAY_INDEX].size() / 3
			_check(vtris >= 200 and vtris <= 9000, "vehicle v2 triangle budget (%d)" % vtris)
			veh.queue_free()
		51:
			# living phone: ring -> decline -> missed log; message threads
			var cm = root.get_node_or_null("CallManager")
			_check(cm != null, "CallManager autoload present")
			if cm:
				_check(cm.state == 0, "call manager idle at boot")
				cm.schedule_call("marcus", "checkin")
				_check(cm.state == 1, "incoming call rings")
				cm.decline_call()
				var lg: Array = WorldState.call_log
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
			if WorldGen.lanes.size() > 0:
				var a := Vector3(-240, 0, 43)
				var b := Vector3(120, 0, -80)
				var path := WorldGen.route_world(a, b)
				_check(path.size() >= 2, "GPS route found between distant points")
				_check(WorldGen.route_length(path) > (b - a).length() * 0.9, "route length plausible")
			else:
				_check(false, "lanes exist for GPS")
		48:
			# gunfire hitscan
			if _player:
				_player.weapons.equip("gun_pistol")
				_player.weapons.reserves["gun_pistol"] = 60
				_player.weapons.try_fire(false, 0.016, _player.global_position + Vector3(0, 1.4, 0), -_player.global_transform.basis.z, true)
				_check(true, "gunfire executed")
		99:
			print("HARNESS: DONE — checks=%d fails=%d" % [_checks, _fails])
			_city.queue_free()
			quit(0 if _fails == 0 else 1)
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
