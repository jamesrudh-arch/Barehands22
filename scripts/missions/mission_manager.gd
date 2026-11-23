extends Node
## MissionManager — runs story + side missions as ordered stage machines over
## the live city. Spawns actors/vehicles/pickups per stage, tracks objectives,
## applies choice effects & rewards, chains the 3-act story, handles fail /
## bust / death recovery. Autoload; operates on the current city scene.

signal mission_failed(mission_id: String)

var active_id: String = ""
var active_stage_i: int = -1
var stage: Dictionary = {}
var rt: Dictionary = {}              # per-stage runtime state
var completed: Dictionary = {}       # mid -> true
var failed: Dictionary = {}          # mid -> true (retry allowed)
var story_offer: String = ""         # next story mission awaiting accept
var side_offer: Array = []

var actors: Array = []               # mission-spawned nodes (freed on end)
var _pickup_root: Node3D = null
var _race_laps := 0
var _stealth_alarm := false
var _last_objective := ""

const RACE_TRACKS := {
	"race_quay": {"district": "ashfall_docks", "laps": 2},
	"race_neon": {"district": "neon_mile", "laps": 2},
}


func _ready() -> void:
	Bus.dialogue_ended.connect(_on_dialogue_ended)
	Bus.world_event.connect(_on_world_event)
	Bus.crime_committed.connect(_on_crime)
	Bus.player_busted.connect(_on_busted)
	Bus.player_died.connect(_on_died)


func _process(delta: float) -> void:
	if active_id == "":
		return
	var player := _player()
	if player == null:
		return
	_tick_stage(delta, player)


# ------------------------------------------------------------------ offers --
func begin_prologue() -> void:
	if completed.has("m01_last_call"):
		_refresh_offers()
		return
	start_mission("m01_last_call")


func _refresh_offers() -> void:
	story_offer = ""
	side_offer = []
	var order := ["m02_the_book", "m03_berth7", "m04_crowe_credit", "m05_static",
		"m06_the_shelter", "m07_yard4", "m08_halcyon_tower", "m09_the_exchange",
		"m10_smoke_line", "m11_the_leverage", "m12_everyone"]
	for mid in order:
		if completed.has(mid):
			continue
		var m := Db.mission(mid)
		var req: String = m.get("requires_flag", "")
		if req != "" and not WorldState.get_flag(req, false):
			continue
		# act gating: only offer act N+1 missions once an act N mission is done
		var act: int = m.get("act", 1)
		if act >= 1 and not completed.has("m01_last_call"):
			continue
		if act >= 2 and not (completed.has("m03_berth7") or completed.has("m04_crowe_credit")):
			continue
		if act >= 3 and not completed.has("m08_halcyon_tower"):
			continue
		story_offer = mid
		var giver: String = Db.mission(mid).get("giver", Db.mission(mid).get("contact", "marcus"))
		CallManager.schedule_call(giver, "offer", mid, 6.0)
		break
	for sid in ["side_courier", "side_race1", "side_race2", "side_nightshift", "side_dockwork", "side_fightclub", "side_ledger", "side_favors", "side_ghost", "side_rooftops", "side_bait", "side_repo", "side_partner", "side_heatmagnet", "side_torch", "side_clean_wheels"]:
		var m := Db.mission(sid)
		if not m.get("repeatable", false) and completed.has(sid):
			continue
		side_offer.append(sid)


func available_missions() -> Array:
	var out: Array = []
	if story_offer != "":
		out.append(story_offer)
	out.append_array(side_offer)
	return out


# ------------------------------------------------------------------- start --
func start_mission(mid: String) -> bool:
	if active_id != "":
		Bus.notification.emit("Already on a job.", "warn")
		return false
	var m := Db.mission(mid)
	if m.is_empty():
		return false
	var req: String = m.get("requires_flag", "")
	if req != "" and not WorldState.get_flag(req, false):
		return false
	active_id = mid
	active_stage_i = -1
	rt = {}
	_stealth_alarm = false
	Bus.mission_started.emit(mid)
	AudioDirector.sfx("ui_confirm", 0.2)
	Bus.notification.emit("JOB: %s" % m.get("title", mid), "mission")
	_advance_stage()
	return true


func _advance_stage() -> void:
	_cleanup_stage()
	active_stage_i += 1
	var m := Db.mission(active_id)
	var stages: Array = m.get("stages", [])
	if active_stage_i >= stages.size():
		_complete(true)
		return
	stage = stages[active_stage_i]
	rt = {}
	_setup_stage()
	var text: String = stage.get("text", "...")
	_last_objective = text
	Bus.objective_updated.emit(active_id, text)


func _cleanup_stage() -> void:
	for a in actors:
		if is_instance_valid(a) and a.get("keep_after_stage") != true:
			a.queue_free()
	actors.clear()
	# scripted pursuit heat is borrowed, not earned: give it back
	if rt.has("prev_wanted"):
		WorldState.set_wanted(mini(WorldState.wanted, int(rt["prev_wanted"])))


func _apply_pursuit() -> void:
	## Chase restaging: a stage can script wanted stars ("pursuit": 2-4) so
	## the full pursuit stack — cruisers, drive-bys, roadblocks, PIT, spikes
	## — is part of the JOB, not just of open-world crime.
	var lvl := int(stage.get("pursuit", 0))
	if lvl <= 0:
		return
	rt["prev_wanted"] = WorldState.wanted
	if WorldState.wanted < lvl:
		WorldState.set_wanted(lvl)
		WorldState.heat_decay = 0.0
		Bus.notification.emit("Heat's on the job — %d stars. Drive." % lvl, "warn")
		AudioDirector.sfx("ui_notify", 0.4)


# ------------------------------------------------------------------ stages --
func _setup_stage() -> void:
	var t: String = stage.get("type", "")
	var player := _player()
	match t:
		"goto":
			rt["pos"] = _poi_pos(stage.get("poi", ""))
		"talk":
			var cid: String = stage.get("char", "")
			var at := _poi_pos(stage.get("poi", "")) if stage.has("poi") else Vector3.ZERO
			if at == Vector3.ZERO and player:
				at = player.global_position + Vector3(2.0, 0, 2.0)
			var n := _spawn_char(cid, at)
			rt["npc"] = n
			rt["done"] = false
			n.set_meta("mission_dialogue", stage.get("dialogue", ""))
		"choice":
			# open immediately if no dialogue gating
			if player and not DialogueUI.is_open():
				var opts: Array = stage.get("options", [])
				var tree_id: String = stage.get("dialogue", "")
				var tree := Db.dialogue_tree(tree_id)
				if not tree.is_empty() and tree.has("opts"):
					DialogueUI.start_tree(tree_id)
					rt["via_tree"] = true
				elif not tree.is_empty():
					# linear intro then choices
					DialogueUI.start_tree(tree_id)
					rt["pending_opts"] = opts
				else:
					DialogueUI.start_choices(stage.get("text", "Choose:"), opts, _on_choice_picked)
		"objective":
			pass
		"cutscene":
			Cutscene.play(stage.get("cutscene", ""), _advance_stage)
			rt["started"] = true
		"event":
			rt["ev"] = ""
			# stage triggers its own event near the player after a beat
			rt["spawn_t"] = 8.0
		"combat":
			_spawn_enemies()
		"collect":
			pass  # world pickups; progress via inventory count
		"carry":
			_spawn_pickups("crate_token", int(stage.get("count", 8)), "docks_pickup")
			rt["to"] = _poi_pos("poi_berth7")
		"drive", "drive_timed":
			_spawn_mission_vehicle()
			rt["from"] = _poi_pos(stage.get("from", ""))
			rt["to"] = _poi_pos(stage.get("to", ""))
			rt["in_veh"] = false
			if t == "drive_timed":
				rt["time"] = float(stage.get("time", 90))
			_apply_pursuit()
		"race":
			_setup_race()
			_apply_pursuit()
		"escort":
			_setup_escort()
		"search":
			var at := _poi_pos(stage.get("poi", ""))
			_spawn_pickups("mission_clue", 1, "search", at)
			rt["found"] = false
		"stealth":
			rt["pos"] = _poi_pos(stage.get("poi", ""))
			_spawn_guards(rt["pos"])
			_stealth_alarm = false
		"phone":
			rt["call_t"] = 2.0


func _tick_stage(delta: float, player: Node) -> void:
	var t: String = stage.get("type", "")
	match t:
		"goto", "stealth":
			var pos: Vector3 = rt.get("pos", Vector3.ZERO)
			if (player.global_position - pos).length() < 4.0:
				if t == "stealth" and _stealth_alarm:
					# spotted: fight your way in — convert to combat
					stage["type"] = "combat"
					stage["enemy"] = "halcyon_guard"
					stage["count"] = 3
					_setup_stage()
					Bus.notification.emit("SPOTTED! Fight through.", "warn")
					return
				if t == "stealth" and not _stealth_alarm:
					# GHOST RUN: never seen, never sounded — earn it
					Progression.add_xp(int(stage.get("xp", 80)), "silent approach")
					Bus.notification.emit("GHOST RUN — +%d XP" % int(stage.get("xp", 80)), "mission")
					WorldState.stats["ghost_runs"] = WorldState.stats.get("ghost_runs", 0) + 1
				_advance_stage()
			elif t == "stealth":
				# alarm now reads the guards' real suspicion meters (vision
				# cones, disguises, crouching all apply) instead of a crude
				# proximity cone
				for g in actors:
					if not is_instance_valid(g):
						continue
					var susp: float = g.get("suspicion") if g.get("suspicion") != null else 0.0
					if susp >= 45.0 and not rt.get("warned", false):
						rt["warned"] = true
						Bus.notification.emit("A guard is getting suspicious...", "warn")
					elif susp < 30.0:
						rt["warned"] = false
					if susp >= 100.0 and not _stealth_alarm:
						_stealth_alarm = true
						Bus.notification.emit("A guard saw you!", "warn")
						AudioDirector.sfx("alarm_loop", 0.3)
		"talk":
			var n = rt.get("npc")
			if n != null and is_instance_valid(n) and not rt.get("done", false):
				if (player.global_position - n.global_position).length() < 2.4:
					n.begin_talk(player)
					var dlg: String = stage.get("dialogue", "")
					if dlg != "":
						DialogueUI.start_tree(dlg)
					rt["done"] = true
		"objective":
			if _check_objective(stage.get("check", "")):
				_advance_stage()
		"event":
			if rt.get("ev", "") != "":
				_advance_stage()
			else:
				rt["spawn_t"] = rt.get("spawn_t", 8.0) - delta
				if rt["spawn_t"] <= 0.0:
					rt["spawn_t"] = 999.0
					Bus.world_event.emit(stage.get("event", "police_sweep"), {"pos": player.global_position})
		"combat":
			var alive := 0
			for e in actors:
				if is_instance_valid(e) and e.state != e.State.DEAD:
					alive += 1
			if alive == 0 and rt.get("spawned", false):
				WorldState.stats["fights_won"] = WorldState.stats.get("fights_won", 0) + 1
				_advance_stage()
		"collect":
			var item: String = stage.get("item", "")
			var need := int(stage.get("count", 1))
			var have: int = WorldState.inventory.get(item, 0)
			if rt.get("shown", 0) != have:
				rt["shown"] = have
				Bus.objective_updated.emit(active_id, "%s (%d/%d)" % [stage.get("text", "Collect"), have, need])
			if have >= need:
				_advance_stage()
			elif not rt.has("spawned_world"):
				rt["spawned_world"] = true
				_spawn_world_collectibles(item, need)
		"carry":
			var have: int = WorldState.inventory.get("crate_token", 0)
			var need := int(stage.get("count", 8))
			var to: Vector3 = rt.get("to", Vector3.ZERO)
			if have > 0 and (player.global_position - to).length() < 5.0:
				WorldState.remove_item("crate_token", have)
				rt["delivered"] = rt.get("delivered", 0) + have
				AudioDirector.sfx("cash", 0.3)
				Bus.objective_updated.emit(active_id, "Crates delivered: %d/%d" % [rt["delivered"], need])
			if rt.get("delivered", 0) >= need:
				_advance_stage()
			elif not rt.has("respawn_t"):
				rt["respawn_t"] = 0.0
			else:
				rt["respawn_t"] -= delta
				if rt["respawn_t"] <= 0.0 and _live_pickups() == 0 and rt.get("delivered", 0) < need:
					rt["respawn_t"] = 2.0
					_spawn_pickups("crate_token", need - rt.get("delivered", 0), "docks_pickup")
		"drive", "drive_timed":
			if not rt.get("in_veh", false):
				if player.in_vehicle != null:
					rt["in_veh"] = true
					rt["veh"] = player.in_vehicle
					if t == "drive_timed":
						Bus.notification.emit("GO! %d seconds!" % int(rt["time"]), "warn")
						AudioDirector.sfx("ui_notify", 0.4)
			else:
				var to: Vector3 = rt.get("to", Vector3.ZERO)
				if t == "drive_timed":
					rt["time"] -= delta
					if int(rt["time"]) != int(rt.get("shown_t", -1)):
						rt["shown_t"] = rt["time"]
						Bus.objective_updated.emit(active_id, "%s — %ds" % [stage.get("text", "Drive"), int(rt["time"])])
					if rt["time"] <= 0.0:
						_complete(false)
						return
				if (player.global_position - to).length() < 6.0:
					_advance_stage()
		"race":
			_tick_race(delta, player)
		"escort":
			_tick_escort(delta, player)
		"search":
			if rt.get("found", false):
				_advance_stage()
		"phone":
			rt["call_t"] = rt.get("call_t", 2.0) - delta
			if rt["call_t"] <= 0.0 and not rt.get("rang", false):
				rt["rang"] = true
				rt["tree"] = stage.get("call", "call_tess_1")
				var cm := get_node_or_null("/root/CallManager")
				if cm and cm.has_method("schedule_call"):
					cm.schedule_call(stage.get("char", "tess"), "mission", rt["tree"], 0.0)
				else:
					AudioDirector.sfx("phone_ring", 0.5)
					Bus.notification.emit("INCOMING CALL — answer via Phone (touch: PHONE)", "info")
		"cutscene", "choice":
			pass
		_:
			_advance_stage()


# ----------------------------------------------------------------- choices --
func _on_choice_picked(opt: Dictionary) -> void:
	if active_id == "" or stage.get("type", "") != "choice":
		return
	var e: Dictionary = opt.get("effects", {})
	if e.has("money"):
		WorldState.add_money(int(e["money"]))
	if e.has("faction"):
		WorldState.add_faction_rep(e["faction"][0], float(e["faction"][1]))
	if e.has("rel"):
		WorldState.add_relationship(e["rel"][0], float(e["rel"][1]))
	if e.has("flag"):
		WorldState.set_flag(e["flag"], true)
	if e.has("wanted"):
		WorldState.set_wanted(clampi(WorldState.wanted + int(e["wanted"]), 0, 5))
	if e.has("item"):
		WorldState.add_item(e["item"], 1)
	Bus.notification.emit(opt.get("label", "Chosen."), "choice")
	AudioDirector.sfx("ui_confirm", 0.25)
	_advance_stage()


func _on_dialogue_ended() -> void:
	if active_id == "":
		return
	var t: String = stage.get("type", "")
	if t == "choice":
		if rt.get("via_tree", false):
			_advance_stage()
		elif rt.has("pending_opts"):
			var opts: Array = rt["pending_opts"]
			rt.erase("pending_opts")
			DialogueUI.start_choices(stage.get("text", "Choose:"), opts, _on_choice_picked)
	elif t == "phone":
		if rt.get("tree", "") != "" and rt.get("answered", false):
			rt["answered"] = false
			_advance_stage()


func answer_phone_call() -> void:
	if active_id != "" and stage.get("type", "") == "phone" and rt.get("rang", false):
		rt["answered"] = true
		DialogueUI.start_tree(rt.get("tree", "call_tess_1"))


# ------------------------------------------------------------------ combat --
func _spawn_enemies() -> void:
	var player := _player()
	if player == null:
		return
	var kind: String = stage.get("enemy", "thug_light")
	if kind == "thug_random":
		kind = ["thug_light", "thug_grappler", "thug_heavy"][randi() % 3]
	var count: int = Difficulty.scale_count(int(stage.get("count", 1)))
	var base: Vector3 = player.global_position
	var ang := randf() * TAU
	for i in count:
		var a := ang + i * (TAU / maxf(count, 1))
		var pos: Vector3 = base + Vector3(cos(a) * 7.0, 0, sin(a) * 7.0)
		pos.y = 0.02
		var n := _spawn_npc()
		n.setup_enemy(kind, pos, "mission")
		actors.append(n)
	rt["spawned"] = true
	var hint: String = stage.get("style_hint", "")
	if hint != "" and hint != "any":
		Bus.notification.emit("They fight %s. Switch style (LB/Style button)." % hint, "info")


func _spawn_guards(pos: Vector3) -> void:
	for i in 3:
		var a := i * TAU / 3.0
		var n := _spawn_npc()
		n.setup_enemy("halcyon_guard", pos + Vector3(cos(a) * 8.0, 0.02, sin(a) * 8.0), "corp")
		n.hostile = false  # only hostile if alarmed
		n.state = n.State.GUARD
		n.set_meta("hostile", false)
		actors.append(n)


# --------------------------------------------------------------- pickups ---
func _spawn_pickups(item_id: String, count: int, mode: String, center: Vector3 = Vector3.ZERO) -> void:
	var player := _player()
	if center == Vector3.ZERO and player:
		center = player.global_position
	if _pickup_root == null:
		_pickup_root = Node3D.new()
		_pickup_root.name = "mission_pickups"
		_scene().add_child(_pickup_root)
	for i in count:
		var a := randf() * TAU
		var r := randf_range(4.0, 14.0)
		var pos := center + Vector3(cos(a) * r, 0.6, sin(a) * r)
		var pk := Area3D.new()
		pk.global_position = pos
		pk.set_script(load("res://scripts/missions/pickup.gd"))
		pk.set_meta("item", item_id)
		pk.set_meta("mode", mode)
		_pickup_root.add_child(pk)
		actors.append(pk)


func _spawn_world_collectibles(item_id: String, need: int) -> void:
	# scatter collectibles across the relevant district
	var m := Db.mission(active_id)
	var did: String = m.get("district", "kiln_row")
	var d := Db.district(did)
	var c: Array = d.get("center", [-220, 60])
	var s: Array = d.get("size", [280, 240])
	for i in need + 4:
		var pos := Vector3(c[0] + randf_range(-s[0] * 0.45, s[0] * 0.45), 0.6, c[1] + randf_range(-s[1] * 0.45, s[1] * 0.45))
		var pk := Area3D.new()
		pk.set_script(load("res://scripts/missions/pickup.gd"))
		pk.set_meta("item", item_id)
		pk.set_meta("mode", "world")
		if _pickup_root == null:
			_pickup_root = Node3D.new()
			_scene().add_child(_pickup_root)
		_pickup_root.add_child(pk)
		pk.global_position = pos


func _live_pickups() -> int:
	var n := 0
	for a in actors:
		if is_instance_valid(a) and a is Area3D:
			n += 1
	return n


# ------------------------------------------------------------------ race ----
func _setup_race() -> void:
	var player := _player()
	if player == null:
		return
	var track: Dictionary = RACE_TRACKS.get(stage.get("track", "race_quay"), RACE_TRACKS["race_quay"])
	var did: String = track["district"]
	var loops := []
	for i in WorldGen.lanes.size():
		if WorldGen.lane_district[i] == did:
			loops.append(WorldGen.lanes[i])
	if loops.is_empty():
		_complete(false)
		return
	var loop: PackedVector3Array = loops[randi() % loops.size()]
	rt["loop"] = loop
	rt["loop_i"] = 0
	rt["laps"] = 0
	rt["need_laps"] = int(track.get("laps", 2))
	rt["time"] = 150.0
	_race_laps = 0
	# start line marker
	var marker := Node3D.new()
	marker.global_position = loop[0]
	_scene().add_child(marker)
	actors.append(marker)
	# rival traffic
	for i in 2:
		var v := VehicleBody3D.new()
		v.set_script(load("res://scripts/vehicle/vehicle.gd"))
		_scene().add_child(v)
		v.setup("muscle", Color.from_hsv(randf(), 0.7, 0.6))
		v.global_position = loop[0] + Vector3(i * 3.0 - 1.5, 0.5, -4.0)
		v.set_lane(loop, 11.0 + i * 1.2)
		v.is_traffic = true
		var city := get_node_or_null("/root/CityLife")
		actors.append(v)
	# give player a ride if on foot
	if player.in_vehicle == null:
		var v := VehicleBody3D.new()
		v.set_script(load("res://scripts/vehicle/vehicle.gd"))
		_scene().add_child(v)
		v.setup("muscle", Color(0.75, 0.5, 0.15))
		v.global_position = loop[0] + Vector3(0, 0.5, -2.0)
		v.parked = true
		actors.append(v)
		# teleport player to start
		player.global_position = loop[0] + Vector3(0, 0.1, -6.0)
	Bus.notification.emit("RACE: %d laps. Get in the car." % rt["need_laps"], "mission")


func _tick_race(delta: float, player: Node) -> void:
	rt["time"] -= delta
	if int(rt["time"]) != int(rt.get("shown_t", -1)):
		rt["shown_t"] = rt["time"]
		Bus.objective_updated.emit(active_id, "Lap %d/%d — %ds" % [rt.get("laps", 0) + 1, rt["need_laps"], int(rt["time"])])
	if rt["time"] <= 0.0:
		_complete(false)
		return
	var loop: PackedVector3Array = rt["loop"]
	if loop.is_empty():
		return
	var nxt: Vector3 = loop[rt["loop_i"]]
	if (player.global_position - nxt).length() < 9.0:
		rt["loop_i"] = (rt["loop_i"] + 1) % loop.size()
		if rt["loop_i"] == 0:
			rt["laps"] += 1
			AudioDirector.sfx("ui_notify", 0.4)
			if rt["laps"] >= rt["need_laps"]:
				WorldState.stats["races_won"] = WorldState.stats.get("races_won", 0) + 1
				_advance_stage()


# ----------------------------------------------------------------- escort ---
func _setup_escort() -> void:
	var player := _player()
	if player == null:
		return
	var count := int(stage.get("count", 1))
	rt["vips"] = []
	for i in count:
		var n := _spawn_npc()
		n.setup_ped("nurse" if Db.peds.has("nurse") else Db.peds.keys()[0], "neon_mile",
			player.global_position + Vector3(randf_range(-2, 2), 0.02, randf_range(1, 3)))
		n.set_meta("escort", true)
		n._home = n.global_position
		actors.append(n)
		rt["vips"].append(n)
	var loops := []
	for i in WorldGen.lanes.size():
		if WorldGen.lane_district[i] == WorldGen.district_at(player.global_position):
			loops.append(WorldGen.lanes[i])
	var dest: Vector3 = player.global_position + Vector3(45, 0, 45)
	if not loops.is_empty():
		var loop: PackedVector3Array = loops[randi() % loops.size()]
		dest = loop[0]
	rt["dest"] = dest
	rt["home"] = player.global_position
	Bus.objective_updated.emit(active_id, "%s — keep them alive." % stage.get("text", "Escort"))


func _tick_escort(delta: float, player: Node) -> void:
	var dest: Vector3 = rt.get("dest", Vector3.ZERO)
	var alive := 0
	var arrived := 0
	for v in rt.get("vips", []):
		if not is_instance_valid(v):
			continue
		if v.state == v.State.DEAD:
			continue
		alive += 1
		# follow player
		var to: Vector3 = player.global_position - v.global_position
		to.y = 0
		var dlen: float = to.length()
		if dlen > 2.6:
			v.velocity = to.normalized() * minf(3.6, dlen)
			v._face(to.normalized(), delta)
			v.anim.mode = "locomote"
			if dlen > 9.0:
				v.anim.sprint = true
		else:
			v.velocity = Vector3.ZERO
			v.anim.mode = "listen"
		v.anim.tick(delta, {})
		if (v.global_position - dest).length() < 5.0:
			arrived += 1
	if alive == 0:
		_complete(false)
		return
	if arrived >= rt["vips"].size():
		_advance_stage()


# ------------------------------------------------------------------- drive --
func _spawn_mission_vehicle() -> void:
	var from := _poi_pos(stage.get("from", ""))
	var player := _player()
	if from == Vector3.ZERO and player:
		from = player.global_position + Vector3(4, 0, 0)
	var v := VehicleBody3D.new()
	v.set_script(load("res://scripts/vehicle/vehicle.gd"))
	_scene().add_child(v)
	v.setup("van", Color(0.25, 0.28, 0.24))
	v.global_position = from + Vector3(0, 0.5, 0)
	v.is_player_owned = true   # the job's car isn't a felony
	v.set_meta("keep_after_stage", true)  # player may still be driving at stage end
	actors.append(v)
	rt["mission_vehicle"] = v
	Bus.notification.emit("Mission vehicle marked nearby.", "info")


# ------------------------------------------------------------------ events --
func _on_world_event(event_id: String, payload: Dictionary) -> void:
	if active_id == "":
		return
	var t: String = stage.get("type", "")
	if t == "event" and stage.get("event", "") == event_id:
		rt["ev"] = event_id
	if t == "search" and event_id == "pickup_found" and payload.get("item", "") == "mission_clue":
		rt["found"] = true
	if event_id == "poi_enter":
		# entering a POI can satisfy goto/stealth when interior counts
		var pid: String = payload.get("poi", "")
		if t in ["goto", "stealth"] and stage.get("poi", "") == pid:
			_advance_stage()
		if t == "talk" and stage.get("poi", "") == pid:
			var n = rt.get("npc")
			if n == null or not is_instance_valid(n):
				# spawn inside
				var player := _player()
				if player:
					n = _spawn_char(stage.get("char", ""), player.global_position + Vector3(1.5, 0, -1.5))
					rt["npc"] = n


func _on_crime(crime: String, severity: int, pos: Vector3) -> void:
	if active_id == "" or stage.get("type", "") != "stealth":
		return
	if severity >= 2 and pos.distance_to(_poi_pos(stage.get("poi", ""))) < 60.0:
		_stealth_alarm = true


# --------------------------------------------------------------- complete ---
func _complete(success: bool) -> void:
	var mid := active_id
	var m := Db.mission(mid)
	_cleanup_stage()
	active_id = ""
	stage = {}
	rt = {}
	Bus.mission_completed.emit(mid, success)
	if success:
		completed[mid] = true
		failed.erase(mid)
		Difficulty.note_mission_cleared()
		var rew: Dictionary = m.get("rewards", {})
		if int(rew.get("money", 0)) != 0:
			WorldState.add_money(int(rew["money"]))
		if rew.has("faction"):
			WorldState.add_faction_rep(rew["faction"][0], float(rew["faction"][1]))
		for f in rew.get("flags", []):
			WorldState.set_flag(f, true)
		for it in rew.get("items", []):
			WorldState.add_item(it, 1)
		if rew.has("stats"):
			WorldState.stats[rew["stats"][0]] = WorldState.stats.get(rew["stats"][0], 0) + int(rew["stats"][1])
		AudioDirector.sfx("ui_confirm", 0.4)
		Bus.notification.emit("JOB COMPLETE: %s (+%d cr)" % [m.get("title", mid), int(rew.get("money", 0))], "mission")
		Progression.add_xp(int(rew.get("xp", 150)) if rew.has("xp") else 150, m.get("title", mid))
		if WorldState.get_flag("game_complete", false):
			Bus.world_event.emit("game_complete", {})
		Game.request_autosave()
	else:
		failed[mid] = true
		mission_failed.emit(mid)
		AudioDirector.sfx("ui_error", 0.4)
		Bus.notification.emit("JOB FAILED: %s" % m.get("title", mid), "error")
	_refresh_offers()


func fail_active(reason: String) -> void:
	if active_id == "":
		return
	Bus.notification.emit(reason, "error")
	_complete(false)


func _on_busted() -> void:
	var fine := clampi(int(WorldState.money * 0.1), 0, 500)
	WorldState.add_money(-fine)
	WorldState.set_wanted(0)
	var player := _player()
	if player:
		player.global_position = _poi_pos("poi_precinct") + Vector3(0, 0.1, 6.0)
	if active_id != "" and stage.get("type", "") in ["stealth", "drive_timed", "race"]:
		_complete(false)
	Bus.notification.emit("BUSTED. Fine: %d cr." % fine, "error")


func _on_died(_cause: String) -> void:
	Difficulty.note_death()
	var player := _player()
	if player:
		player.global_position = _poi_pos("poi_clinic") + Vector3(0, 0.1, 3.0)
	var fee := clampi(int(WorldState.money * 0.1), 0, 300)
	WorldState.add_money(-fee)
	if active_id != "":
		_complete(false)
	Bus.notification.emit("PATCHED UP AT THE CLINIC. Fee: %d cr." % fee, "error")


# ----------------------------------------------------------------- helpers --
func _player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


func _poi_pos(pid: String) -> Vector3:
	var entry: Dictionary = WorldGen.pois.get(pid, {})
	var d: Dictionary = entry.get("data", {})
	if d.has("at"):
		return Vector3(d["at"][0], 0.0, d["at"][1])
	return Vector3.ZERO


func _spawn_npc() -> Node:
	var n := CharacterBody3D.new()
	n.set_script(load("res://scripts/npc/npc.gd"))
	_scene().add_child(n)
	return n


func _spawn_char(cid: String, at: Vector3) -> Node:
	var n := _spawn_npc()
	if Db.characters.has(cid):
		n.setup_named(cid)
	else:
		n.setup_ped(rand_pick_ped(), WorldGen.district_at(at), at)
		n.display_name = cid.capitalize()
	n.global_position = at + Vector3(0, 0.02, 0)
	n.state = n.State.IDLE_ACT
	return n


func rand_pick_ped() -> String:
	var keys := Db.peds.keys()
	return keys[randi() % keys.size()]


func _check_objective(expr: String) -> bool:
	## Like _check, but supports RELATIVE stat goals: "statd:wrecks>=2"
	## counts wrecks SINCE this stage started, so repeatable jobs can't
	## be pre-satisfied by last Tuesday's chaos.
	if expr.begins_with("statd:"):
		for op in [">=", ">", "=="]:
			if expr.contains(op):
				var parts := expr.split(op)
				var key := parts[0].trim_prefix("statd:").strip_edges()
				var need := float(parts[1].strip_edges())
				if not rt.has("base_" + key):
					rt["base_" + key] = WorldState.stats.get(key, 0)
				var v: float = float(WorldState.stats.get(key, 0)) - float(rt["base_" + key])
				match op:
					">=": return v >= need
					">": return v > need
					"==": return v == need
		return false
	return _check(expr)


func _check(expr: String) -> bool:
	# tiny evaluator: "money>=1500", "flag:route_crew", "item:x>=2", "wanted>=1", "hour>=22"
	if expr.begins_with("flag:"):
		return WorldState.get_flag(expr.trim_prefix("flag:"), false)
	if expr.begins_with("prop:"):
		return WorldState.owns_property(expr.trim_prefix("prop:"))
	for op in [">=", "<=", ">", "<", "=="]:
		if expr.contains(op):
			var parts := expr.split(op)
			var lhs := parts[0].strip_edges()
			var rhs := float(parts[1].strip_edges())
			var v := 0.0
			match lhs:
				"money": v = WorldState.money
				"wanted": v = WorldState.wanted
				"hour": v = WorldState.game_hour
				"hp": v = _player().combat.hp if _player() else 0.0
				"level": v = float(Progression.level)
				_:
					if lhs.begins_with("item:"):
						v = WorldState.inventory.get(lhs.trim_prefix("item:"), 0)
					elif lhs.begins_with("stat:"):
						v = WorldState.stats.get(lhs.trim_prefix("stat:"), 0)
			match op:
				">=": return v >= rhs
				"<=": return v <= rhs
				">": return v > rhs
				"<": return v < rhs
				"==": return v == rhs
	return false


func objective_text() -> String:
	if active_id == "":
		if story_offer != "":
			return "Next: %s" % Db.mission(story_offer).get("title", story_offer)
		return ""
	return _last_objective


func mission_title() -> String:
	if active_id == "":
		return ""
	return Db.mission(active_id).get("title", active_id)


# -------------------------------------------------------------------- save --
func save_state() -> Dictionary:
	return {"active": active_id, "stage": active_stage_i, "completed": completed.keys(),
		"failed": failed.keys(), "offer": story_offer,
		"rt_pos": [rt["pos"].x, rt["pos"].y, rt["pos"].z] if rt.get("pos") is Vector3 else [],
		"rt_time": rt.get("time", 0.0)}


func apply_save(d: Dictionary) -> void:
	completed.clear()
	failed.clear()
	for mid in d.get("completed", []):
		completed[mid] = true
	for mid in d.get("failed", []):
		failed[mid] = true
	active_id = ""
	stage = {}
	rt = {}
	_refresh_offers()
	var act: String = d.get("active", "")
	if act != "" and Db.missions.has(act):
		start_mission(act)
		var si: int = int(d.get("stage", -1))
		var stages: Array = Db.mission(act).get("stages", [])
		if si > 0 and si < stages.size():
			_cleanup_stage()
			active_stage_i = si - 1
			_advance_stage()
			if stage.get("type", "") == "cutscene":
				_advance_stage()  # don't replay a cinematic on load
			var rp: Array = d.get("rt_pos", [])
			if rp.size() == 3:
				rt["pos"] = Vector3(rp[0], rp[1], rp[2])
			if d.get("rt_time", 0.0) is float and float(d["rt_time"]) > 0.0:
				rt["time"] = float(d["rt_time"])


func _scene() -> Node:
	var t := get_tree()
	if t == null:
		t = Engine.get_main_loop() as SceneTree
	return t.current_scene if t != null else null
