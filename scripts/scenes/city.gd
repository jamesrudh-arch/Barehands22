extends Node3D
## City scene — assembles Cinder City at runtime: environment, day/night sun,
## weather (rain/fog/thunder), WorldGen geometry, player spawn, CityLife
## simulation, HUD, and world-event routing (POI doors, interiors, shops,
## talks, game-complete ending).

var env: Environment
var sun: DirectionalLight3D
var rain: GPUParticles3D
var player: Node = null
var city_life: Node = null
var hud: CanvasLayer = null
var _thunder_cd := 0.0
var _news_cd := 120.0
var _built := false


func _ready() -> void:
	Game.set_state(Game.State.PLAYING)
	_setup_environment()
	_setup_sun()
	_setup_rain()
	# world geometry
	WorldGen.build_city(self)
	# simulation layer
	city_life = preload("res://scripts/world/city_life.gd").new()
	city_life.name = "CityLife"
	add_child(city_life)
	# player
	var spawn: Array = WorldGen.pois.get("poi_home", {}).get("data", {}).get("at", [-240, 46])
	player = CharacterBody3D.new()
	player.set_script(load("res://scripts/player/player.gd"))
	add_child(player)
	player.global_position = Vector3(float(spawn[0]), 0.05, float(spawn[1]) + 3.0)
	Game.player = player
	Game.mission_manager = MissionManager
	# tutorial coach
	var tut := preload("res://scripts/ui/tutorial.gd").new()
	tut.name = "Tutorial"
	add_child(tut)
	# HUD
	hud = CanvasLayer.new()
	hud.set_script(load("res://scripts/ui/hud.gd"))
	add_child(hud)
	# event routing
	Bus.world_event.connect(_on_world_event)
	Bus.weather_changed.connect(_on_weather)
	Bus.game_state_changed.connect(_on_state)
	_apply_weather(WorldState.weather_name())
	_built = true
	# welcome news
	Bus.radio_news.emit("Cinder City harbour authority delays Berth 7 repairs again. Dockworkers not surprised.")


func _spawn_check(p: Vector3) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if player == null:
		return
	if player.global_position.y < -2.0 or not _ground_below(player.global_position):
		player.global_position = _find_ground(p)


func _ground_below(pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.from = pos + Vector3(0, 2, 0)
	q.to = pos + Vector3(0, -2, 0)
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


func _find_ground(p: Vector3) -> Vector3:
	# spawn on the street in front of the door; verify support with a raycast
	var space := get_world_3d().direct_space_state
	var offsets := [Vector3(0, 0, 10), Vector3(0, 0, 14), Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, -14), Vector3.ZERO]
	for off in offsets:
		var q := PhysicsRayQueryParameters3D.new()
		q.from = p + off + Vector3(0, 3, 0)
		q.to = p + off + Vector3(0, -3, 0)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return p + off + Vector3(0, 0.1, 0)
	return p + Vector3(0, 0.1, 10)


func _setup_environment() -> void:
	env = load("res://assets/env/default_env.tres").duplicate()
	# cinematic grade: filmic response, grounded contrast, controlled neon glow
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 0.93
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_strength = 0.9
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)


func _setup_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 1400
	rain.lifetime = 1.4
	rain.local_coords = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.25, -1, 0.1)
	mat.spread = 4.0
	mat.gravity = Vector3(0, -22, 0)
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 13.0
	rain.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.02, 0.4)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.6, 0.68, 0.8, 0.35)
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = rm
	rain.draw_pass_1 = qm
	rain.emitting = false
	add_child(rain)


func _process(delta: float) -> void:
	if not _built:
		return
	_day_night()
	# rain follows camera
	var cam := get_viewport().get_camera_3d()
	if cam:
		rain.global_position = cam.global_position + Vector3(0, 12, 0)
	# thunder
	if WorldState.weather == WorldState.Weather.RAIN:
		_thunder_cd -= delta
		if _thunder_cd <= 0.0:
			_thunder_cd = randf_range(14.0, 40.0)
			AudioDirector.sfx("thunder_%d" % (1 + randi() % 3), 0.2, 0.7)
	# periodic radio news
	_news_cd -= delta
	if _news_cd <= 0.0:
		_news_cd = randf_range(150.0, 260.0)
		_push_news()


func _day_night() -> void:
	var h := WorldState.game_hour
	# sun angle: rises 6, sets 19
	var ang := (h - 6.0) / 13.0 * PI          # 0..PI across the day
	sun.rotation = Vector3(-sin(ang) * 1.1, PI * 0.25 + h * 0.05, 0)
	var dayness := clampf(sin(ang), 0.0, 1.0)
	if h < 6.0 or h > 19.5:
		dayness = 0.0
	var weather_dim := 1.0
	match WorldState.weather:
		WorldState.Weather.RAIN: weather_dim = 0.45
		WorldState.Weather.OVERCAST: weather_dim = 0.7
		WorldState.Weather.FOG: weather_dim = 0.8
	sun.light_energy = (0.12 + dayness * 0.95) * weather_dim
	sun.light_color = Color(1.0, 0.92, 0.8).lerp(Color(0.35, 0.45, 0.75), 1.0 - dayness)
	# sky tint by hour
	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
	var night_top := Color(0.045, 0.05, 0.085)
	var dusk_top := Color(0.16, 0.12, 0.2)
	var day_top := Color(0.32, 0.42, 0.58)
	var top: Color
	if dayness < 0.15:
		top = night_top
	elif dayness < 0.4:
		top = dusk_top.lerp(day_top, (dayness - 0.15) / 0.25)
	else:
		top = day_top
	if WorldState.weather == WorldState.Weather.RAIN:
		top = top.lerp(Color(0.1, 0.11, 0.13), 0.6)
	elif WorldState.weather == WorldState.Weather.OVERCAST:
		top = top.lerp(Color(0.16, 0.16, 0.18), 0.45)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = top.lerp(Color(0.45, 0.33, 0.26), 0.35)
	env.ambient_light_energy = 0.28 + dayness * 0.4
	env.fog_enabled = WorldState.weather == WorldState.Weather.FOG or WorldState.is_night()
	env.fog_density = 0.004 if WorldState.weather == WorldState.Weather.FOG else (0.0016 if WorldState.is_night() else 0.0008)
	env.fog_light_color = Color(0.28, 0.3, 0.36) if WorldState.is_night() else Color(0.55, 0.5, 0.45)


func _on_weather(kind: String, _wet: float) -> void:
	_apply_weather(kind)


func _apply_weather(kind: String) -> void:
	rain.emitting = kind == "rain"
	if rain.emitting:
		AudioDirector.ambient("rain", "res://assets/audio/sfx/rain_loop.wav", 0.35)
	else:
		AudioDirector.ambient_off("rain")


func _on_world_event(event_id: String, payload: Dictionary) -> void:
	match event_id:
		"poi_enter":
			var data: Dictionary = payload.get("data", {})
			var pid: String = payload.get("poi", "")
			if data.has("interior"):
				InteriorManager.enter(data["interior"], pid)
			else:
				Bus.notification.emit(data.get("name", "Here"), "info")
				Bus.poi_discovered.emit(pid)
		"talk_request":
			var n = payload.get("node")
			var cid: String = payload.get("char", "")
			if n == null:
				return
			# mission talk handled by mission stage; else ambient chat
			var mm := MissionManager
			if mm.active_id != "" and mm.stage.get("type", "") == "talk" and mm.stage.get("char", "") == cid:
				return  # mission manager drives this
			var tree: String = "chat_" + str({"padre_sol": "padre", "crowe_jr": "julian"}.get(cid, cid))
			if Db.dialogue.has(tree):
				n.begin_talk(player)
				DialogueUI.start_tree(tree)
				Bus.dialogue_ended.connect(func(): n.end_talk(), CONNECT_ONE_SHOT)
			else:
				Bus.dialogue_line.emit(cid, "Not now, kid.", "ped_m")
		"game_complete":
			Cutscene.play("cs_ending", func():
				Game.set_state(Game.State.MENU)
				Game.goto_scene("res://scenes/menu/menu.tscn"))
		"police_sweep", "citizen_dispute", "traffic_collision", "mugging", "gang_shakedown", "crowd_gathering":
			pass  # handled by CityLife spawning


func _on_state(s: StringName) -> void:
	if s == "gameover":
		await get_tree().create_timer(2.2).timeout
		Game.set_state(Game.State.MENU)
		Game.goto_scene("res://scenes/menu/menu.tscn")


func _push_news() -> void:
	var templates: Array = Db.news_templates
	if templates.is_empty():
		return
	var t = templates[randi() % templates.size()]
	var text: String = t.get("text", "") if t is Dictionary else str(t)
	var cl := get_node_or_null("CityLife")
	if cl and cl.has_method("format_news"):
		text = cl.format_news(text)
	if WorldState.wanted > 0:
		var did: String = str(WorldState.current_district) if str(WorldState.current_district) != "" else "kiln_row"
		text = "CCPD escalate search for suspect last seen in %s. Tips to Static-88." % Db.district(did).get("name", "the city")
	Bus.radio_news.emit(text)
	Bus.notification.emit("NEWS: " + text, "info")
