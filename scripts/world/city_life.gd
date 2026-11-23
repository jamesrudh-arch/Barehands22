extends Node
## CityLife — the simulation layer that makes Cinder City exist without the
## player watching: pedestrian crowds with routines, traffic on lane loops,
## police response & pursuits, scheduled world events, pooled night lighting,
## traffic-light cycles and district ambience/music.

var peds: Array = []
var traffic: Array = []
var parked: Array = []
var police_units: Array = []
var named_nodes: Dictionary = {}
var event_actors: Array = []

var _ped_target := 26
var _traffic_target := 12
var _spawn_cd := 0.0
var _event_cd := 40.0
var _light_pool: Array = []
var _light_cd := 0.0
var _last_crime_pos := Vector3.ZERO
var _last_crime_t := 0.0
var _roadblock_nodes: Array = []
var _arrest_t := 0.0
var _amb_district := ""

const PED_SCENE := "res://scripts/npc/npc.gd"
const VEH_SCENE := "res://scripts/vehicle/vehicle.gd"


func _ready() -> void:
	for i in 28:
		var l := OmniLight3D.new()
		l.omni_range = 16.0
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_light_pool.append(l)
	Bus.crime_committed.connect(_on_crime)
	Bus.district_changed.connect(_on_district)
	Bus.mission_completed.connect(_on_mission_done)
	Bus.wanted_changed.connect(_on_wanted)


func _process(delta: float) -> void:
	var player := _player()
	if player == null:
		return
	var pp: Vector3 = player.global_position
	# crowds
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 0.6
		_manage_crowds(pp)
		_manage_traffic(pp)
	# traffic AI
	for v in traffic:
		if is_instance_valid(v):
			v.traffic_tick(delta)
	# police
	_police_tick(delta, player)
	# radio
	_radio_tick(player)
	# events
	_event_cd -= delta
	if _event_cd <= 0.0:
		_event_cd = randf_range(35.0, 80.0)
		_spawn_event(pp)
	# lights
	_light_cd -= delta
	if _light_cd <= 0.0:
		_light_cd = 1.0
		_assign_lights(pp)
		_traffic_light_cycle()
	# event actors cleanup
	for a in event_actors.duplicate():
		if not is_instance_valid(a):
			event_actors.erase(a)


func _player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


# ------------------------------------------------------------------ crowds --
func _manage_crowds(pp: Vector3) -> void:
	# cull far
	for p in peds.duplicate():
		if not is_instance_valid(p):
			peds.erase(p)
			continue
		if (p.global_position - pp).length() > 150.0 and p.char_id == "":
			p.queue_free()
			peds.erase(p)
	# spawn to density
	var did := WorldGen.district_at(pp)
	var dens: float = Db.district(did).get("ped_density", 0.7)
	var want := int(_ped_target * dens)
	var active := 0
	for p in peds:
		if (p.global_position - pp).length() < 90.0:
			active += 1
	if peds.size() < want:
		_spawn_ped(pp, did)


func _spawn_ped(pp: Vector3, did: String) -> void:
	var candidates := []
	for pid in Db.peds:
		if did in Db.peds[pid].get("districts", [did]):
			candidates.append(pid)
	if candidates.is_empty():
		candidates = Db.peds.keys()
	var pid: String = candidates[randi() % candidates.size()]
	# spawn on a sidewalk near player but out of sight-ish
	for attempt in 6:
		var ang := randf() * TAU
		var r := randf_range(28.0, 55.0)
		var pos := pp + Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not WorldGen.district_bounds.has(WorldGen.district_at(pos)):
			continue
		var n := CharacterBody3D.new()
		n.set_script(load(PED_SCENE))
		get_parent().add_child(n)
		n.setup_ped(pid, did, pos + Vector3(0, 0.02, 0))
		peds.append(n)
		return


func place_named(cid: String, pos: Vector3) -> void:
	var n := CharacterBody3D.new()
	n.set_script(load(PED_SCENE))
	get_parent().add_child(n)
	n.setup_named(cid)
	n.global_position = pos
	named_nodes[cid] = n
	peds.append(n)


# ----------------------------------------------------------------- traffic --
func _manage_traffic(pp: Vector3) -> void:
	for v in traffic.duplicate():
		if not is_instance_valid(v):
			traffic.erase(v)
			continue
		if (v.global_position - pp).length() > 170.0:
			v.queue_free()
			traffic.erase(v)
	if traffic.size() < _traffic_target:
		_spawn_traffic(pp)
	# parked cars once per district visit
	if parked.size() < 18:
		_spawn_parked(pp)


func _spawn_traffic(pp: Vector3) -> void:
	var did := WorldGen.district_at(pp)
	var loops := []
	for i in WorldGen.lanes.size():
		if WorldGen.lane_district[i] == did:
			loops.append(WorldGen.lanes[i])
	if loops.is_empty():
		return
	var loop: PackedVector3Array = loops[randi() % loops.size()]
	var start: Vector3 = loop[0]
	if (start - pp).length() < 20.0 or (start - pp).length() > 120.0:
		return
	var defs := ["sedan", "sedan", "van", "taxi", "muscle", "bike", "truck"]
	var vid: String = defs[randi() % defs.size()]
	var v := VehicleBody3D.new()
	v.set_script(load(VEH_SCENE))
	get_parent().add_child(v)
	var col: Color = Color.from_hsv(randf(), randf_range(0.2, 0.7), randf_range(0.3, 0.8))
	v.setup(vid, col)
	v.global_position = start + Vector3(0, 0.5, 0)
	v.set_lane(loop, randf_range(6.5, 10.5))
	traffic.append(v)


func _spawn_parked(pp: Vector3) -> void:
	for attempt in 4:
		var ang := randf() * TAU
		var r := randf_range(15.0, 45.0)
		var pos := pp + Vector3(cos(ang) * r, 0, sin(ang) * r)
		var did := WorldGen.district_at(pos)
		if not WorldGen.district_bounds.has(did):
			continue
		var v := VehicleBody3D.new()
		v.set_script(load(VEH_SCENE))
		get_parent().add_child(v)
		var defs := ["sedan", "sedan", "van", "muscle", "bike"]
		v.setup(defs[randi() % defs.size()], Color.from_hsv(randf(), 0.4, 0.45))
		v.global_position = pos + Vector3(0, 0.45, 0)
		v.rotation.y = randf() * TAU
		v.parked = true
		parked.append(v)
		return


func give_player_vehicle(def_id: String, pos: Vector3) -> Node:
	var v := VehicleBody3D.new()
	v.set_script(load(VEH_SCENE))
	get_parent().add_child(v)
	var cols: Array = Db.vehicle(def_id).get("colors", [])
	var col := Color(0.4, 0.4, 0.45)
	if cols.size():
		var c0 = cols[0]
		col = Color(c0[0] / 255.0, c0[1] / 255.0, c0[2] / 255.0) if c0 is Array else Color(c0)
	v.setup(def_id, col)
	v.global_position = pos
	v.parked = true
	return v


# ------------------------------------------------------------------ police --
func _on_crime(crime: String, severity: int, pos: Vector3) -> void:
	_last_crime_pos = pos
	_last_crime_t = 0.0
	if severity >= 2:
		_dispatch(pos, severity)


func _dispatch(pos: Vector3, severity: int) -> void:
	var count := clampi(WorldState.wanted, 1, 4)
	for i in count:
		if police_units.size() >= 8:
			return
		_spawn_police(pos, i == 0)


func _spawn_police(near: Vector3, with_car: bool) -> void:
	var ang := randf() * TAU
	var r := randf_range(45.0, 70.0)
	var pos := near + Vector3(cos(ang) * r, 0, sin(ang) * r)
	if with_car:
		var v := VehicleBody3D.new()
		v.set_script(load(VEH_SCENE))
		get_parent().add_child(v)
		v.setup("police", Color(0.09, 0.1, 0.13), true)
		v.global_position = pos
		v.is_police = true
		v.set_siren(true)
		police_units.append({"node": v, "kind": "car", "t": 0.0})
	else:
		var n := CharacterBody3D.new()
		n.set_script(load(PED_SCENE))
		get_parent().add_child(n)
		n.setup_enemy("cop", pos, "law")
		n.display_name = "CCPD Officer"
		n.combat.max_hp = 120
		n.combat.hp = 120
		police_units.append({"node": n, "kind": "foot", "t": 0.0})


func _police_tick(delta: float, player: Node) -> void:
	_last_crime_t += delta
	var wanted := WorldState.wanted
	if wanted == 0:
		# units lose interest and leave
		for u in police_units.duplicate():
			if is_instance_valid(u["node"]):
				u["t"] += delta
				if u["t"] > 20.0:
					u["node"].queue_free()
					police_units.erase(u)
		if _roadblock_nodes.size():
			_clear_roadblocks()
		return
	var pp: Vector3 = player.global_position
	for u in police_units.duplicate():
		if not is_instance_valid(u["node"]):
			police_units.erase(u)
			continue
		var n: Node3D = u["node"]
		var to: Vector3 = pp - n.global_position
		var dist: float = to.length()
		if u["kind"] == "car":
			# drive toward player
			var fwd := -n.global_transform.basis.z
			var angle := atan2(to.normalized().cross(fwd).y, to.normalized().dot(fwd))
			n.steering = move_toward(n.steering, clampf(angle * 2.0, -0.55, 0.55), delta * 2.0)
			n.engine_force = 60.0 * 22.0 if dist > 8.0 else 0.0
			if n.has_method("_set_brake"):
				n._set_brake(6.0 if dist < 8.0 else 1.0)
			if dist < 4.5 and player.in_vehicle == null:
				_try_arrest(delta, player, dist)
		else:
			if n.state != n.State.COMBAT and n.state != n.State.DEAD:
				n.state = n.State.COMBAT
			if dist < 2.0 and player.in_vehicle == null:
				_try_arrest(delta, player, dist)
	# roadblocks at 3+
	if wanted >= 3 and _roadblock_nodes.is_empty():
		_make_roadblock(pp)


func _try_arrest(delta: float, player: Node, dist: float) -> void:
	if player.in_vehicle != null:
		return
	_arrest_t += delta
	if _arrest_t > 1.6:
		_arrest_t = 0.0
		Bus.player_busted.emit()


func _make_roadblock(pp: Vector3) -> void:
	for i in 2:
		var ang := randf() * TAU
		var pos := pp + Vector3(cos(ang) * 40.0, 0, sin(ang) * 40.0)
		var v := VehicleBody3D.new()
		v.set_script(load(VEH_SCENE))
		get_parent().add_child(v)
		v.setup("police", Color(0.09, 0.1, 0.13), true)
		v.global_position = pos
		v.rotation.y = ang + PI / 2
		v.is_police = true
		v.set_siren(true)
		_roadblock_nodes.append(v)


func _clear_roadblocks() -> void:
	for v in _roadblock_nodes:
		if is_instance_valid(v):
			v.queue_free()
	_roadblock_nodes.clear()


# ------------------------------------------------------------------ events --
func _spawn_event(pp: Vector3) -> void:
	var did := WorldGen.district_at(pp)
	var hour := WorldState.game_hour
	var candidates := []
	for eid in Db.events:
		var e: Dictionary = Db.events[eid]
		if did not in e.get("districts", [did]):
			continue
		var h0: float = e["hours"][0]
		var h1: float = e["hours"][1]
		var ok := (hour >= h0 and hour <= h1) if h0 <= h1 else (hour >= h0 or hour <= h1)
		if ok:
			candidates.append([e.get("weight", 5), eid])
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	var eid: String = candidates[randi() % mini(4, candidates.size())][1]
	var ang := randf() * TAU
	var r := randf_range(18.0, 40.0)
	var pos := pp + Vector3(cos(ang) * r, 0, sin(ang) * r)
	Bus.world_event.emit(eid, {"pos": pos, "district": did})
	match eid:
		"citizen_dispute", "street_fight":
			for i in 2:
				var n := CharacterBody3D.new()
				n.set_script(load(PED_SCENE))
				get_parent().add_child(n)
				n.setup_ped(rand_pick(Db.peds.keys()), did, pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
				n.state = n.State.GAWK
				n._flee_from = pos
				event_actors.append(n)
			if eid == "street_fight":
				var f := CharacterBody3D.new()
				f.set_script(load(PED_SCENE))
				get_parent().add_child(f)
				f.setup_enemy("thug_light", pos, "none")
				f.hostile = false
				event_actors.append(f)
		"traffic_collision":
			for i in 2:
				var v := VehicleBody3D.new()
				v.set_script(load(VEH_SCENE))
				get_parent().add_child(v)
				v.setup("sedan", Color.from_hsv(randf(), 0.5, 0.5))
				v.global_position = pos + Vector3(i * 2.4 - 1.2, 0.45, 0)
				v.rotation.y = randf() * 0.8
				v.parked = true
				event_actors.append(v)
			AudioDirector.sfx_at("veh_crash_light", pos)
		"mugging":
			var t := CharacterBody3D.new()
			t.set_script(load(PED_SCENE))
			get_parent().add_child(t)
			t.setup_enemy("thug_light", pos, "none")
			t.hostile = true
			event_actors.append(t)
			var vic := CharacterBody3D.new()
			vic.set_script(load(PED_SCENE))
			get_parent().add_child(vic)
			vic.setup_ped(rand_pick(Db.peds.keys()), did, pos + Vector3(1.2, 0, 0))
			vic.state = vic.State.GAWK
			vic._flee_from = pos
			event_actors.append(vic)
		"police_sweep":
			for i in 2:
				_spawn_police(pos, false)
		"steam_vent":
			Effects.burst(pos + Vector3(0, 0.3, 0), "smoke")
			AudioDirector.sfx_at("steam_hiss", pos)
		"fire_barrel":
			AudioDirector.sfx_at("fire_crackle", pos)
			Effects.burst(pos + Vector3(0, 0.6, 0), "smoke")
		"crowd_gathering":
			for i in 4:
				var n := CharacterBody3D.new()
				n.set_script(load(PED_SCENE))
				get_parent().add_child(n)
				n.setup_ped(rand_pick(Db.peds.keys()), did, pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
				n.state = n.State.GAWK
				n._flee_from = pos
				event_actors.append(n)
		"ambulance":
			AudioDirector.sfx_at("siren_loop", pos + Vector3(30, 0, 0), 0.5)
		"radio_car":
			AudioDirector.sfx_at("radio_static", pos, 0.4)
		"gang_shakedown":
			var g := CharacterBody3D.new()
			g.set_script(load(PED_SCENE))
			get_parent().add_child(g)
			g.setup_enemy("thug_light", pos, "none")
			g.hostile = false
			event_actors.append(g)
		"stray_cat":
			pass  # flavour only: bark
		_:
			pass


func _on_mission_done(mid: String, success: bool) -> void:
	var m := Db.mission(mid)
	var title: String = m.get("title", mid)
	if success:
		push_news("Underworld whispers: someone walked away clean from \"%s\". Names stay quiet." % title)
	else:
		push_news("Police confirm a botched incident in %s. Sources describe \"%s\" gone wrong." % [Db.district(Game.current_district).get("name", "the city"), title])


func _on_wanted(level: int) -> void:
	if level >= 3:
		push_news("CCPD raise the alert level. Eyewitnesses describe a suspect loose in %s." % Db.district(Game.current_district).get("name", "the city"))
	if level == 0:
		push_news("CCPD stand down citywide alert. \"Nothing to see,\" says a spokesperson.")


func rand_pick(arr: Array):
	return arr[randi() % arr.size()]


# ------------------------------------------------------------------ lights --
func _assign_lights(pp: Vector3) -> void:
	var night := WorldState.is_night()
	WorldGen.set_night_emission(night)
	if not night:
		for l in _light_pool:
			l.light_energy = 0.0
			l.visible = false
		return
	var nearest := WorldGen.nearest_lamp_positions(pp, _light_pool.size())
	for i in _light_pool.size():
		var l: OmniLight3D = _light_pool[i]
		if i < nearest.size():
			var info: Dictionary = nearest[i]
			l.global_position = info["pos"]
			l.light_color = info["color"]
			l.light_energy = 2.2
			l.visible = true
		else:
			l.light_energy = 0.0
			l.visible = false


func _traffic_light_cycle() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for tl in WorldGen.traffic_lights:
		if not is_instance_valid(tl["node"]):
			continue
		var ph: float = fmod(t + float(tl["phase"]), 24.0)
		var green := ph < 12.0
		var light: OmniLight3D = tl["light"]
		light.visible = WorldState.is_night()
		light.light_color = Color(0.2, 0.9, 0.3) if green else Color(0.95, 0.2, 0.15)
		tl["green"] = green


# --------------------------------------------------------------- ambience ---
var _radio_track_i := 0


func _radio_tick(player: Node) -> void:
	var st := _station()
	if st.is_empty():
		return
	if player.in_vehicle == null:
		return  # radio only audibly plays in-vehicle (see PhoneUI foot-note toast)
	var tracks: Array = st.get("tracks", [])
	if tracks.is_empty():
		return
	if AudioDirector.current_music != tracks[_radio_track_i % tracks.size()]:
		AudioDirector.play_music(tracks[_radio_track_i % tracks.size()], 1.2)


func _station() -> Dictionary:
	var sid: String = WorldState.phone_station
	for st in Db.radio.get("stations", []):
		if st.get("id", "") == sid:
			return st
	return {}


func radio_cycle() -> void:
	var ids: Array = ["off"]
	for st in Db.radio.get("stations", []):
		ids.append(st.get("id", ""))
	var cur := ids.find(WorldState.phone_station)
	var nxt: String = ids[(cur + 1) % ids.size()]
	WorldState.phone_station = nxt
	if nxt == "off":
		AudioDirector.stop_music(1.0)
		Bus.notification.emit("Radio off.", "info")
	else:
		_radio_track_i = randi() % 4
		var st := _station()
		Bus.notification.emit("Radio: %s" % st.get("name", nxt), "info")
		AudioDirector.sfx("radio_static", 0.2)
		var pl := _player()
		if pl and pl.in_vehicle == null:
			Bus.notification.emit("Signal's weak on foot — the radio plays while you drive.", "info")


func format_news(text: String) -> String:
	var t: String = text.replace("{district}", Db.district(Game.current_district).get("name", "Cinder City"))
	t = t.replace("{hour}", WorldState.hour_of_day_string())
	return t


func push_news(text: String) -> void:
	text = format_news(text)
	if not WorldState.news_queue.has(text):
		WorldState.news_queue.append(text)
		if WorldState.news_queue.size() > 24:
			WorldState.news_queue.pop_front()
	Bus.radio_news.emit(text)


func _on_district(did: String) -> void:
	if did == _amb_district:
		return
	_amb_district = did
	var d := Db.district(did)
	if d.is_empty():
		AudioDirector.stop_music(2.0)
		AudioDirector.ambient_off("traffic")
		AudioDirector.ambient_off("crowd")
		return
	if WorldState.wanted == 0 and WorldState.phone_station == "":
		AudioDirector.play_music(d.get("music", "music_explore_kiln"), 2.5)
	AudioDirector.ambient("traffic", "res://assets/audio/sfx/traffic_loop.wav", 0.25 * d.get("traffic_density", 0.6))
	AudioDirector.ambient("crowd", "res://assets/audio/sfx/crowd_loop.wav", 0.2 * d.get("ped_density", 0.6))


func traffic_green_at(pos: Vector3) -> bool:
	for tl in WorldGen.traffic_lights:
		if (tl["node"].global_position - pos).length() < 12.0:
			return tl.get("green", true)
	return true
