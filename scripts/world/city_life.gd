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
var _last_seen := Vector3.ZERO
var _seen_t := 999.0
var _search_center := Vector3.ZERO
var _search_i := 0
var _amb_district := ""

const PED_SCENE := "res://scripts/npc/npc.gd"
const VEH_SCENE := "res://scripts/vehicle/vehicle.gd"


var _checkin_t := 0.0


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
	_checkin_t += delta
	if _checkin_t > 300.0:
		_checkin_t = 0.0
		if Game.state == Game.State.PLAYING and WorldState.wanted == 0 and randf() < 0.35:
			var who: Array = ["marcus", "ruth", "padre", "sol"]
			var kind := "warning" if WorldState.day >= 2 and randf() < 0.4 else "checkin"
			CallManager.schedule_call(who[randi() % who.size()], kind)
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
	_spike_check(player)
	# faction grudges
	_grudge_tick(delta, player)
	# fame: the papers notice careers, not just neighborhoods
	_fame_tick(delta)
	# fires: lifetime + the crackle you hear walking past
	_fire_tick(delta, player)
	# radio
	_radio_tick(delta, player)
	_gossip_tick(delta, player)
	_intervene_tick(delta, player)
	# adaptive music (explore -> tension -> combat -> chase)
	_music_tick(delta, player)
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
	if _event_kind != "" and event_actors.is_empty():
		_event_kind = ""
		_event_helped = false


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
	var want: int = int(Difficulty.ped_target(_ped_target) * dens * _hour_crowd_mult(did))
	var active := 0
	for p in peds:
		if (p.global_position - pp).length() < 90.0:
			active += 1
	if peds.size() < want:
		_spawn_ped(pp, did)


## Living-city rhythm: crowds breathe with the clock and the district.
## Rush hours pack the avenues; deep night thins most streets while the
## neon district and docks stay loud. Weather pushes everyone indoors.
func _hour_crowd_mult(did: String) -> float:
	var h: float = WorldState.game_hour
	var m := 1.0
	if h >= 7.5 and h < 9.5:
		m = 1.45                      # morning rush
	elif h >= 17.0 and h < 19.5:
		m = 1.55                      # evening rush
	elif h >= 21.0 or h < 1.0:
		m = 1.3 if did in ["neon_mile", "ashfall_docks"] else 0.75   # nightlife vs quiet
	elif h < 5.5:
		m = 0.3                       # dead of night
	elif h < 7.5:
		m = 0.6                       # early risers
	if WorldState.weather == WorldState.Weather.RAIN:
		m *= 0.6
	return m


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
	if traffic.size() < Difficulty.traffic_target(_traffic_target):
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
	# district-flavored traffic: the docks get work trucks, the Heights get
	# limousines... er, sports cars; the Mile gets taxis and bikes.
	var defs: Array
	match did:
		"ashfall_docks":
			defs = ["truck", "truck", "van", "pickup", "sedan", "bus"]
		"crown_heights":
			defs = ["sports", "sedan", "sedan", "taxi", "ambulance"]
		"neon_mile":
			defs = ["taxi", "taxi", "sedan", "bike", "muscle", "sports"]
		"slagworks":
			defs = ["truck", "van", "pickup", "sedan", "bus"]
		"the_furnace":
			defs = ["van", "sedan", "sedan", "muscle", "ambulance", "pickup"]
		_:
			defs = ["sedan", "sedan", "van", "taxi", "muscle", "bike", "truck", "pickup", "bus"]
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
		# most civilian cars are locked; bikes less so
		v.locked = randf() < (0.35 if v.vehicle_type == "bike" else 0.6)
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
	v.is_player_owned = true
	return v


# ------------------------------------------------------------------ police --
func _on_crime(crime: String, severity: int, pos: Vector3) -> void:
	_last_crime_pos = pos
	_last_crime_t = 0.0
	# the neighborhood remembers: crimes leave lingering district heat
	var did := WorldGen.district_at(pos)
	var heat := float(severity) * 4.0
	if crime == "body_found":
		heat = 22.0
	var before: float = WorldState.district_heat01(did)
	WorldState.add_district_heat(did, heat)
	# FACTION CONSEQUENCES: every district belongs to someone. Bleed on
	# crew turf and the Syndicate sour on you; torch cars in the Furnace
	# and Halcyon marks your file. Heat at home is rep abroad — rival
	# factions quietly respect chaos aimed at their enemies.
	if crime in ["gunfire", "explosion", "homicide", "body_found"] and severity >= 2:
		match did:
			"ashfall_docks", "slagworks":
				WorldState.add_faction_rep("crew", -1.5)
				WorldState.add_faction_rep("corp", -0.5)
			"the_furnace", "crown_heights":
				WorldState.add_faction_rep("corp", -1.5)
				WorldState.add_faction_rep("crew", 0.5)
			"neon_mile":
				WorldState.add_faction_rep("crew", -0.5)
				WorldState.add_faction_rep("corp", -0.5)
		WorldState.add_faction_rep("family", -0.5 if crime == "homicide" else 0.0)
	var after: float = WorldState.district_heat01(did)
	# heat milestones make the papers — consequences you can read about
	var dname: String = Db.district(did).get("name", "the district")
	if before < 0.35 and after >= 0.35:
		PhoneUI.push_news("Crime wave rattles %s; CCDP promises 'visible presence.'" % dname)
	elif before < 0.7 and after >= 0.7:
		PhoneUI.push_news("%s on edge: shops close early as violence climbs." % dname)
	if crime == "body_found" and after > 0.5:
		PhoneUI.push_news("Body discovered in %s. Police tight-lipped; residents aren't." % dname)
	# SOUND PROPAGATION: loud crimes ripple outward — peds within earshot
	# panic even if they never saw a thing. Rain muffles the city; a
	# suppressor keeps the ripple from starting at all (no gunfire crime).
	# a carjacking in the street: whoever SEES it reacts (smashed glass
	# is loud, hot-wiring is not — severity tells them apart)
	if crime == "theft" and severity >= 3:
		for n in get_tree().get_nodes_in_group("humanoid"):
			if not is_instance_valid(n) or not n.has_method("react"):
				continue
			if (n.global_position - pos).length() < 20.0:
				n.react("crime", pos)
	var loud := crime in ["gunfire", "explosion", "homicide"]
	if loud:
		var radius := 45.0 if crime == "explosion" else 34.0
		if WorldState.weather == WorldState.Weather.RAIN:
			radius *= 0.7
		elif WorldState.weather == WorldState.Weather.FOG:
			radius *= 0.85
		var event := "gunshots" if crime != "homicide" else "fight"
		for n in get_tree().get_nodes_in_group("humanoid"):
			if not is_instance_valid(n) or (n.global_position - pos).length() > radius:
				continue
			if not n.has_method("react") or n.state == n.State.DEAD:
				continue
			# combatants don't spook at their own war
			if n.get("hostile") == true or n.state == n.State.COMBAT:
				continue
			n.react(event, pos)
	if severity >= 2:
		_dispatch(pos, severity)


func _dispatch(pos: Vector3, severity: int) -> void:
	var count: int = Difficulty.dispatch_count(WorldState.wanted)
	for i in count:
		if police_units.size() >= Difficulty.police_cap():
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
		# setup_enemy already applied Difficulty.enemy_hp_mult to the 120 base
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
		for sp in _spikes.duplicate():
			if is_instance_valid(sp["node"]):
				sp["node"].queue_free()
			_spikes.erase(sp)
		return
	var pp: Vector3 = player.global_position
	# --- perception: units only know where they last SAW you ---
	_seen_t += delta
	var can_see := _police_see_player(player)
	if can_see:
		_last_seen = pp
		_seen_t = 0.0
	var target_pos := pp
	if _seen_t > 3.5:
		# lost sight: converge on last known position, then search around it
		if _search_center == Vector3.ZERO or (_last_seen - _search_center).length() > 30.0:
			_search_center = _last_seen
			_search_i = 0
		var ring := 6.0 + float(_search_i % 5) * 5.0
		var ang := float(_search_i) * 2.399   # golden-angle sweep
		target_pos = _search_center + Vector3(cos(ang) * ring, 0, sin(ang) * ring)
	for u in police_units.duplicate():
		if not is_instance_valid(u["node"]):
			police_units.erase(u)
			continue
		var n: Node3D = u["node"]
		if _seen_t > 3.5 and fmod(_seen_t, 2.0) < delta:
			_search_i += 1
		var to: Vector3 = target_pos - n.global_position
		var dist: float = to.length()
		if u["kind"] == "car":
			# drive toward player
			var fwd := -n.global_transform.basis.z
			var angle := atan2(to.normalized().cross(fwd).y, to.normalized().dot(fwd))
			n.steering = move_toward(n.steering, clampf(angle * 2.0, -0.55, 0.55), delta * 2.0)
			n.engine_force = 60.0 * 22.0 if dist > 8.0 else 0.0
			if n.has_method("_set_brake"):
				n._set_brake(6.0 if dist < 8.0 else 1.0)
			if dist < 4.5 and player.in_vehicle == null and (pp - n.global_position).length() < 6.0:
				_try_arrest(delta, player, dist)
			# drive-by: at 2+ stars cruisers open fire through the glass —
			# hits the player's vehicle when driving, the player on foot
			u["shoot_t"] = float(u.get("shoot_t", randf_range(0.5, 2.0))) - delta
			if wanted >= 2 and dist < 34.0 and dist > 6.0 and u["shoot_t"] <= 0.0:
				u["shoot_t"] = randf_range(1.6, 3.2) * (1.35 - Difficulty.aggression() * 0.35)
				_cruiser_shot(n, player, dist)
		else:
			if _is_investigator(n):
				pass   # crime-scene officers work the wreck, not the chase
			else:
				if n.state != n.State.COMBAT and n.state != n.State.DEAD:
					n.state = n.State.COMBAT
				if dist < 2.0 and player.in_vehicle == null and (pp - n.global_position).length() < 2.6:
					_try_arrest(delta, player, dist)
	# RUBBERNECKING: sirens are theater — the block watches the show
	_siren_gawk_t -= delta
	if _siren_gawk_t <= 0.0:
		_siren_gawk_t = 1.1
		for u in police_units:
			if not is_instance_valid(u["node"]) or u["kind"] != "car":
				continue
			for n in get_tree().get_nodes_in_group("humanoid"):
				if not is_instance_valid(n) or not n.has_method("react"):
					continue
				if n.state in [n.State.COMBAT, n.State.DEAD, n.State.FLEE]:
					continue
				if (n.global_position - u["node"].global_position).length() < 16.0:
					n.react("siren", u["node"].global_position)
	# roadblocks at 3+
	if wanted >= 3 and _roadblock_nodes.is_empty():
		_make_roadblock(pp)
	# --- pursuit escalation: the deeper the heat, the nastier the tactics ---
	# pursuit chatter: a police radio cutting through the cabin
	_radio_chatter_t -= delta
	if wanted >= 2 and _radio_chatter_t <= 0.0:
		_radio_chatter_t = randf_range(9.0, 18.0)
		AudioDirector.sfx("police_radio", 0.18, 0.3)
	_spike_t -= delta
	if wanted >= 4 and player.in_vehicle != null and _spike_t <= 0.0:
		_spike_t = 18.0
		_drop_spike_strips(pp)
	if wanted >= 3 and player.in_vehicle != null:
		_pit_tick(delta, player)


var _spike_t := 0.0
var _spikes: Array = []
var _pit_cd := 0.0
var _radio_chatter_t := 6.0
var _siren_gawk_t := 1.0


func _drop_spike_strips(pp: Vector3) -> void:
	## 4-star answer to a fast car: belts of spikes across the lanes ahead.
	## Driving one shreds tyres — the vehicle limps and takes damage.
	Bus.notification.emit("SPIKE STRIPS AHEAD!", "warn")
	AudioDirector.sfx("ui_notify", 0.3)
	for i in 3:
		var ang := randf() * TAU
		var pos := pp + Vector3(cos(ang), 0, sin(ang)) * randf_range(30.0, 55.0)
		pos.y = 0.06
		var m := MeshInstance3D.new()
		var am := ArrayMesh.new()
		var verts := PackedVector3Array()
		for sx in range(-3, 4):
			for sz in [-1, 1]:
				var x := float(sx) * 0.6
				verts.append(Vector3(x - 0.25, 0.0, float(sz) * 0.25))
				verts.append(Vector3(x + 0.25, 0.0, float(sz) * 0.25))
				verts.append(Vector3(x, 0.16, 0.0))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.mesh = am
		var mi := StandardMaterial3D.new()
		mi.albedo_color = Color(0.15, 0.15, 0.18)
		mi.metallic = 0.7
		mi.metallic_specular = 0.4
		am.surface_set_material(0, mi)
		get_parent().add_child(m)
		m.global_position = pos
		_spikes.append({"node": m, "pos": pos, "used": false})


func _spike_check(player: Node) -> void:
	if player.in_vehicle == null:
		return
	for sp in _spikes.duplicate():
		if sp["used"] or not is_instance_valid(sp["node"]):
			continue
		if (player.global_position - sp["pos"]).length() < 2.4:
			sp["used"] = true
			var v: Node = player.in_vehicle
			if v.has_method("damage"):
				v.damage(28.0)
			v.puncture_tires()
			AudioDirector.sfx_at("tire_burst", player.global_position)
			Bus.notification.emit("TYRES SHREDDED!", "error")
			Effects.burst(player.global_position + Vector3(0, 0.4, 0), "spark")
			sp["node"].queue_free()
			_spikes.erase(sp)


func _pit_tick(delta: float, player: Node) -> void:
	## PIT maneuver: at 3+ stars a cruiser alongside your rear quarter will
	## shove the back end out. Real consequence for hot-car escapes.
	_pit_cd -= delta
	if _pit_cd > 0.0 or player.in_vehicle == null:
		return
	var pv: Node = player.in_vehicle
	# VehicleBody3D carries linear_velocity; CharacterBody3D carries velocity
	var pvel: Vector3 = Vector3.ZERO
	if "linear_velocity" in pv:
		pvel = pv.linear_velocity
	elif "velocity" in pv:
		pvel = pv.velocity
	if pvel.length() < 9.0:
		return                          # PIT needs speed to matter
	for u in police_units:
		if not is_instance_valid(u["node"]) or u["kind"] != "car":
			continue
		var n: Node3D = u["node"]
		var off: Vector3 = n.global_position - player.global_position
		off.y = 0
		var d := off.length()
		if d > 5.5 or d < 2.0:
			continue
		var side := off.normalized().dot(-pv.global_transform.basis.x)
		if absf(side) < 0.35:
			continue                    # not alongside
		_pit_cd = 9.0
		# the shove: spin impulse + damage
		pv.apply_central_impulse(off.normalized() * pv.mass * 3.2)
		pv.apply_torque_impulse(Vector3.UP * (2600.0 if side > 0 else -2600.0))
		if pv.has_method("damage"):
			pv.damage(12.0)
		if n.has_method("damage"):
			n.damage(8.0)
		AudioDirector.sfx_at("crash_metal", player.global_position)
		Effects.add_shake(0.55)
		Bus.notification.emit("PIT MANEUVER — they're spinning you out!", "error")
		return


func _police_see_player(player: Node) -> bool:
	# any unit within 55 m with unobstructed LOS keeps the chase honest
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for u in police_units:
		if not is_instance_valid(u["node"]):
			continue
		var n: Node3D = u["node"]
		var d: float = (player.global_position - n.global_position).length()
		# weather caps how far units can actually see you
		var see_range := 55.0
		if WorldState.weather == WorldState.Weather.FOG:
			see_range = 32.0
		elif WorldState.weather == WorldState.Weather.RAIN:
			see_range = 44.0
		if d > see_range:
			continue
		var from: Vector3 = n.global_position + Vector3(0, 1.4, 0)
		var to: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [n.get_rid(), player.get_rid()]
		q.collision_mask = 1   # static world only — units never block each other
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			return true
	return false


func _cruiser_shot(n: Node3D, player: Node, dist: float) -> void:
	## Patrol-car drive-by: tracer, report, and a hit roll that damages
	## whatever the player is riding (or the player). Accuracy scales with
	## Difficulty; moving targets are genuinely hard to hit.
	var muz: Vector3 = n.global_position + Vector3(0.55, 1.1, 0)
	var tgt: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	if player.in_vehicle != null:
		tgt = player.in_vehicle.global_position + Vector3(0, 0.7, 0)
	var dir: Vector3 = (tgt - muz).normalized()
	dir += Vector3(randf_range(-0.05, 0.05), randf_range(-0.02, 0.04), randf_range(-0.05, 0.05))
	AudioDirector.sfx_at("shot_pistol", muz, 0.8)
	Effects.burst(muz, "muzzle", dir)
	Effects.tracer(muz, muz + dir * 45.0)
	var speed_penalty: float = 0.0
	if player.in_vehicle != null and player.in_vehicle.has_method("speed_kmh"):
		speed_penalty = clampf(player.in_vehicle.speed_kmh() / 160.0, 0.0, 0.35)
	var chance := clampf(0.42 - dist * 0.006 + Difficulty.accuracy_bonus() - speed_penalty, 0.05, 0.6)
	if randf() < chance:
		if player.in_vehicle != null and player.in_vehicle.has_method("damage"):
			player.in_vehicle.damage(float(randf_range(4.0, 9.0)))
			Effects.burst(tgt, "spark", dir)
		elif player.combat:
			player.combat.take_hit(float(randf_range(7.0, 13.0)) * Difficulty.enemy_dmg_mult(), dir, "bullet", n)


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
	if eid == "mugging":
		_event_kind = "mugging"
		_event_kind_district = did
		_intervene_pos = pos
		_intervene_cd = 0.0
	elif eid in ["citizen_dispute", "street_fight"]:
		_event_kind = "brawl"
		_event_kind_district = did
		_intervene_pos = pos
		_intervene_cd = 0.0
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
		"turf_war":
			# rival factions tear into each other; the player is a spectator
			# (or an opportunist) until someone spots them
			for side in [["thug_light", "thug_grappler", "crew"], ["halcyon_guard", "crowe_gunman", "corp"]]:
				for i in 2:
					var n := CharacterBody3D.new()
					n.set_script(load(PED_SCENE))
					get_parent().add_child(n)
					n.setup_enemy(side[i % 2], pos + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)) + (Vector3(6, 0, 0) if side[2] == "corp" else Vector3(-6, 0, 0)), side[2])
					event_actors.append(n)
			Bus.notification.emit("Turf war brewing — Syndicate and Halcyon are squaring up.", "warn")
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
			t.set_meta("event_role", "mugger")
			event_actors.append(t)
			var vic := CharacterBody3D.new()
			vic.set_script(load(PED_SCENE))
			get_parent().add_child(vic)
			vic.setup_ped(rand_pick(Db.peds.keys()), did, pos + Vector3(1.2, 0, 0))
			vic.state = vic.State.GAWK
			vic._flee_from = pos
			vic.set_meta("event_role", "victim")
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
			# a barrel fire that actually burns: flickering light, crackle
			# ambience for passersby, gone in 2 minutes (via _fire_tick)
			var fb := Node3D.new()
			fb.global_position = pos
			var fl := OmniLight3D.new()
			fl.light_color = Color(1.0, 0.5, 0.18)
			fl.light_energy = 1.8
			fl.omni_range = 6.0
			fl.position = Vector3(0, 0.7, 0)
			fb.add_child(fl)
			get_parent().add_child(fb)
			fb.add_to_group("burning")
			_fires.append({"node": fb, "t": 120.0})
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
var _chatter_t := 45.0


func _radio_tick(delta: float, player: Node) -> void:
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
	# DJ chatter between songs — the city has a voice even at 3 a.m.
	var ch: Array = st.get("chatter", [])
	if not ch.is_empty():
		_chatter_t -= delta
		if _chatter_t <= 0.0:
			_chatter_t = randf_range(75.0, 150.0)
			AudioDirector.sfx("radio_static", 0.12)
			if WorldState.owns_property("radio_slot") and randf() < 0.3:
				Bus.notification.emit("[RADIO] ...brought to you by YOUR 3 a.m. ad slot. Billboards pay.", "info")
			else:
				Bus.notification.emit("[RADIO] %s" % ch[randi() % ch.size()], "info")


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


var _music_state := "explore"
var _music_hold := 0.0


func _music_tick(delta: float, player: Node) -> void:
	if Game.state != Game.State.PLAYING:
		return
	# player-chosen radio wins while riding
	if player.in_vehicle != null and WorldState.phone_station != "":
		_music_hold = 3.0
		return
	_music_hold = maxf(0.0, _music_hold - delta)
	var combat_now: bool = player.combat != null and player.combat.in_combat
	var police_near := false
	for u in police_units:
		if is_instance_valid(u["node"]) and (u["node"].global_position - player.global_position).length() < 60.0:
			police_near = true
			break
	var target := "explore"
	if WorldState.wanted >= 3 or (WorldState.wanted > 0 and police_near):
		target = "chase"
	elif combat_now:
		target = "combat"
	elif WorldState.wanted > 0:
		target = "tension"
	elif player.combat != null and player.combat.combat_timer > 0.0:
		target = "combat"          # just finished a fight: hold the sting
	# cinematic left a non-explore track playing while we're calm: restore
	if target == "explore" and _music_state == "explore":
		var cm: String = AudioDirector.current_music
		if not cm.begins_with("music_explore") and player.in_vehicle == null and WorldState.phone_station == "" and _music_hold <= 0.0:
			var dd := Db.district(Game.current_district)
			AudioDirector.play_music(dd.get("music", "music_explore_kiln"), 2.0)
	if target != _music_state:
		if target == "explore" and _music_hold > 0.0:
			return
		_music_state = target
		match target:
			"chase":
				AudioDirector.play_music("music_chase", 0.8)
			"combat":
				AudioDirector.play_music("music_combat", 0.7)
			"tension":
				AudioDirector.play_music("music_tension", 1.2)
			"explore":
				var d := Db.district(Game.current_district)
				AudioDirector.play_music(d.get("music", "music_explore_kiln"), 2.5)


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


var _grudge_cd := 0.0
const TURF := {
	"ashfall_docks": "crew", "slagworks": "crew",
	"the_furnace": "corp", "crown_heights": "corp",
	"neon_mile": "crew",
}
## enemy faction_tag per turf faction (setup_enemy tags: mission/corp/crew)
const TURF_TAG := {"crew": "crew", "corp": "corp"}


## Faction grudges: walk onto the turf of a faction you've burned (rep deep
## negative) and they send collectors. Scales with Difficulty — late game
## the collections arrive heavier.
var _fires: Array = []
var _invest_cd := 0.0
var _investigators: Array = []   # {node, t} — cops working a fire scene


func _is_investigator(n: Node) -> bool:
	for inv in _investigators:
		if inv["node"] == n:
			return true
	return false


func _investigate_fires(delta: float) -> void:
	## A burning hulk in the street is a crime scene with a countdown.
	## CCPD rolls up to work it: two officers loiter by the wreck for a
	## while, then get bored and wander off (despawn). Witnesses to your
	## arson will find badges standing in the ashes.
	_invest_cd -= delta
	# retire finished investigators
	for inv in _investigators.duplicate():
		inv["t"] -= delta
		if inv["t"] <= 0.0 or not is_instance_valid(inv["node"]):
			if is_instance_valid(inv["node"]):
				inv["node"].queue_free()
			_investigators.erase(inv)
	if _invest_cd > 0.0:
		return
	for n in get_tree().get_nodes_in_group("burning"):
		if not is_instance_valid(n) or not n.is_in_group("vehicle"):
			continue
		_invest_cd = 25.0
		for i in 2:
			var cop := CharacterBody3D.new()
			cop.set_script(load(PED_SCENE))
			get_parent().add_child(cop)
			cop.setup_enemy("cop", n.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), "law")
			cop.hostile = false
			cop.display_name = "CCPD Investigator"
			cop.state = cop.State.GAWK
			cop._flee_from = n.global_position
			cop._gawk_t = 30.0
			_investigators.append({"node": cop, "t": randf_range(40.0, 70.0)})
			police_units.append({"node": cop, "kind": "foot", "t": 0.0})
		Bus.notification.emit("CCPD are working the burning wreck.", "info")
		break


func _fire_tick(delta: float, player: Node) -> void:
	_investigate_fires(delta)
	for f in _fires.duplicate():
		f["t"] -= delta
		if f["t"] <= 0.0 or not is_instance_valid(f["node"]):
			if is_instance_valid(f["node"]):
				f["node"].queue_free()
			_fires.erase(f)
	# nearest burning thing drives the ambient crackle channel
	var best := 1e9
	if player != null:
		for n in get_tree().get_nodes_in_group("burning"):
			if is_instance_valid(n):
				var d: float = (n.global_position - player.global_position).length()
				if d < best:
					best = d
	if best < 22.0:
		AudioDirector.ambient("fire", "res://assets/audio/sfx/fire_crackle.wav", clampf(0.5 * (1.0 - best / 22.0), 0.0, 0.5))
	else:
		AudioDirector.ambient_off("fire")


const FAME_MILESTONES := [
	["fame_thefts5", "thefts", 5, "Grand theft wave: five cars gone in %s nights. Owners 'left them running,' police say."],
	["fame_kos25", "kos", 25, "Twenty-five bodies this season. The city stops naming them; the numbers keep counting."],
	["fame_jobs8", "jobs_done", 8, "Eight jobs pulled off clean. Whoever's running this crew doesn't leave witnesses OR paperwork."],
	["fame_rich10k", "money", 10000, "New money in Cinder: someone's spending five figures in a city that runs on ones."],
	["fame_ghost3", "ghost_runs", 3, "Three jobs, zero sightings. Security firms are calling it 'the ghost problem.'"],
	["fame_races3", "races_won", 3, "Street racing's new name keeps winning. Bookies at the Quay are 'adjusting odds.'"],
]


var _fame_t := 5.0


func _fame_tick(delta: float) -> void:
	## Career milestones make the papers — one shot each, persisted as flags.
	_fame_t -= delta
	if _fame_t > 0.0:
		return
	_fame_t = 6.0
	for m in FAME_MILESTONES:
		if WorldState.get_flag(m[0], false):
			continue
		var v := 0.0
		if m[1] == "money":
			v = float(WorldState.money)
		else:
			v = float(WorldState.stats.get(m[1], 0))
		if v >= float(m[2]):
			WorldState.set_flag(m[0], true)
			var line := str(m[3])
			if line.contains("%"):
				line = line % WorldState.day
			PhoneUI.push_news(line)


func _grudge_tick(delta: float, player: Node) -> void:
	_grudge_cd -= delta
	if _grudge_cd > 0.0 or WorldState.wanted > 0 or Game.state != Game.State.PLAYING:
		return
	var did: String = Game.current_district
	var fac: String = TURF.get(did, "")
	if fac == "":
		return
	var rep: float = WorldState.factions.get(fac, 0.0)
	if rep > -35.0:
		return
	_grudge_cd = randf_range(100.0, 160.0)
	var count: int = Difficulty.scale_count(2)
	# ESCALATION: past -70 rep it stops being a collection and becomes a
	# hit — armed squads, one more body, a different kind of message
	var squad: bool = rep < -70.0
	if squad:
		count += 1
	var ppos: Vector3 = player.global_position
	if squad:
		Bus.notification.emit("%s isn't collecting anymore. They're finishing." % ("The Syndicate" if fac == "crew" else "Halcyon"), "error")
	else:
		Bus.notification.emit("%s collectors are here to talk. Bring bandages." % ("Syndicate" if fac == "crew" else "Halcyon"), "warn")
	AudioDirector.sfx("shout_alert", 0.2)
	for i in count:
		var a := randf() * TAU
		var pos := ppos + Vector3(cos(a), 0, sin(a)) * randf_range(14.0, 20.0)
		pos.y = 0.02
		var n := CharacterBody3D.new()
		n.set_script(load(PED_SCENE))
		get_parent().add_child(n)
		var kind: String
		if squad:
			kind = "crowe_gunman" if fac == "crew" else "halcyon_guard"
		else:
			kind = ["thug_light", "thug_grappler", "thug_heavy"][randi() % 3] if fac == "crew" else "halcyon_guard"
		n.setup_enemy(kind, pos, TURF_TAG.get(fac, fac))
		if squad:
			n.display_name = "Syndicate Hitman" if fac == "crew" else "Halcyon Cleaner"
		else:
			n.display_name = "Syndicate Collector" if fac == "crew" else "Halcyon Recovery"
	# rep floor: surviving a collection cools the grudge slightly
	WorldState.add_faction_rep(fac, 4.0)


func traffic_green_at(pos: Vector3) -> bool:
	for tl in WorldGen.traffic_lights:
		if (tl["node"].global_position - pos).length() < 12.0:
			return tl.get("green", true)
	return true


# --------------------------------------------- overheard conversations ---
# Sleeping Dogs / GTA V lesson: a city where nobody talks to each other is
# a ghost town. Pairs of locals hold short overheard conversations — and
# when you linger, they notice you and the block's opinion of you colors
# what they do next.
var _gossip_t := 12.0
var _gossip_until := 0.0
var gossip_pair: Array = []


func _gossip_tick(delta: float, player: Node) -> void:
	if player.in_vehicle != null or Game.get("cutscene_active") == true:
		return
	# 1) maintain a live pair
	if _gossip_until > 0.0:
		_gossip_until -= delta
		var pair := gossip_pair.duplicate()
		var alive: Array = []
		for n in pair:
			if is_instance_valid(n):
				alive.append(n)
		if alive.size() < 2:
			_end_gossip()
			return
		var a = alive[0]
		var b = alive[1]
		if a.state != a.State.ROUTINE or b.state != b.State.ROUTINE:
			_end_gossip()
			return
		if (a.global_position - player.global_position).length() < 3.5:
			# overheard up close — the conversation turns to YOU
			_end_gossip()
			if WorldState.street_rep() <= -8:
				a._bark("watch_it")
			elif randf() < 0.5:
				a._bark("interrupted")
			else:
				a._bark("greet")
			return
		var dir_b: Vector3 = (b.global_position - a.global_position)
		dir_b.y = 0.0
		if dir_b.length() > 0.1:
			a._face(dir_b.normalized(), delta * 6.0)
			b._face(-dir_b.normalized(), delta * 6.0)
		return
	# 2) start a new pair
	_gossip_t -= delta
	if _gossip_t > 0.0:
		return
	_gossip_t = randf_range(18.0, 34.0)
	var near: Array = []
	for n in get_tree().get_nodes_in_group("humanoid"):
		if not is_instance_valid(n) or n.get("hostile") == true or n.char_id != "":
			continue
		if n.state != n.State.ROUTINE or n.get("_chat_idle") == true:
			continue
		if (n.global_position - player.global_position).length() < 30.0:
			near.append(n)
	if near.size() < 2:
		return
	near.shuffle()
	var pa = near[0]
	var pb: Node = null
	for i in range(1, near.size()):
		if (near[i].global_position - pa.global_position).length() < 12.0:
			pb = near[i]
			break
	if pb == null:
		return
	pa._chat_idle = true
	pb._chat_idle = true
	pa.chatter_peer = pb
	pb.chatter_peer = pa
	gossip_pair = [pa, pb]
	_gossip_until = randf_range(12.0, 20.0)
	pa._bark("gossip")
	await get_tree().create_timer(1.1).timeout
	if is_instance_valid(pb) and gossip_pair.size() == 2:
		pb._bark("gossip")


func _end_gossip() -> void:
	for n in gossip_pair:
		if is_instance_valid(n):
			n._chat_idle = false
			n.chatter_peer = null
	gossip_pair.clear()
	_gossip_until = 0.0


# ------------------------------------------------- street-event agency ---
# GTA V / Sleeping Dogs lesson: random street events are only alive if the
# player can INTERVENE and the world scores the choice. Step into a mugging
# or a street fight and decide whose side you're on — the block remembers.
var _intervene_cd := 0.0
var _intervene_pos := Vector3.ZERO
var _event_kind := ""
var _event_helped := false


func _intervene_tick(delta: float, player: Node) -> void:
	_intervene_cd -= delta
	if player.in_vehicle != null or Game.get("cutscene_active") == true:
		return
	if _event_kind == "" or player.global_position.distance_to(_intervene_pos) > 7.0:
		return
	if _intervene_cd > 0.0:
		return
	_intervene_cd = 45.0
	var kind := _event_kind
	var opts: Array = []
	var cl := self
	if kind == "mugging":
		opts.append({"label": "Step in — nobody gets robbed on this block", "act": func():
			cl._event_helped = true
			for a in cl.event_actors:
				if is_instance_valid(a) and String(a.get_meta("event_role", "")) == "mugger":
					a.hostile = true
					a.combat.combat_timer = 8.0
			Bus.notification.emit("You stepped in. The mugger turns on you.", "warn")})
		opts.append({"label": "Walk past — not your business", "act": func(): pass})
		opts.append({"label": "Back the mugger — hand over your cut", "act": func():
			cl._event_helped = false
			for a in cl.event_actors:
				if is_instance_valid(a) and String(a.get_meta("event_role", "")) == "mugger":
					a.hostile = false
					a.combat.combat_timer = 8.0
			var cut := int(clampi(WorldState.money / 40, 1, 25))
			WorldState.money = maxi(0, WorldState.money - cut)
			WorldState.note_deed("helped_mugger", String(cl._event_kind_district), false)
			Bus.notification.emit("You took the mugger's side. Word travels fast — the block won't forget. (-$%d)" % cut, "warn")})
	else:
		opts.append({"label": "Break it up", "act": func():
			cl._event_helped = true
			cl._calm_event_actors()
			Bus.notification.emit("You broke it up. Heads nod — the block noticed.", "info")})
		opts.append({"label": "Watch it play out", "act": func(): pass})
		opts.append({"label": "Jump in and swing", "act": func():
			cl._event_helped = false
			cl._provoke_event_actors()
			Bus.notification.emit("You swung first. Now everyone's swinging at you.", "warn")})
	DialogueUI.start_choices("The street is watching. What do you do?", opts, func(opt):
		var c: Callable = opt.get("act", Callable())
		if c.is_valid():
			c.call()
		if cl._event_kind == "mugging" and not opt.get("label", "").begins_with("Back"):
			if bool(opt.get("label", "").begins_with("Step")):
				pass  # deed lands when the mugger drops (npc._on_died)
			else:
				WorldState.note_deed("ignored_mugging", String(cl._event_kind_district), false)
		elif cl._event_kind != "mugging":
			WorldState.note_deed("brawl_" + ("helped" if cl._event_helped else "joined"), String(cl._event_kind_district), cl._event_helped)
		cl._event_kind = "")


var _event_kind_district := ""


func _calm_event_actors() -> void:
	for a in event_actors:
		if is_instance_valid(a) and a.has_method("end_talk"):
			a.state = a.State.ROUTINE
			a.hostile = false
			a._bark("respect")


func _provoke_event_actors() -> void:
	var pp: Vector3 = _intervene_pos
	for a in event_actors:
		if not is_instance_valid(a) or not a.has_method("end_talk"):
			continue
		if (a.global_position - pp).length() < 14.0:
			a.hostile = true
			if a.combat != null:
				a.combat.combat_timer = 8.0
