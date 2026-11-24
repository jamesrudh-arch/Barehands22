extends CanvasLayer
## Cutscene — directed in-engine cinematics: letterbox bars, camera moves,
## actor staging, subtitle lines, fades, and title cards. Data-driven via a
## small script format (arrays of steps) stored per cutscene id.

var playing := false
var _steps: Array = []
var _step_i := 0
var _t := 0.0
var _bars: Array = [ColorRect.new(), ColorRect.new()]
var _card: Label
var _sub: Label
var _fade: ColorRect
var _cam: Camera3D
var _finished_cb := Callable()
var _skip_lbl: Label


func _ready() -> void:
	layer = 60
	for b in _bars:
		b.color = Color(0, 0, 0, 1)
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.visible = false
		add_child(b)
	_bars[0].offset_bottom = -1.0  # top bar sized on play
	_skip_lbl = Label.new()
	_skip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_lbl.anchor_left = 1.0
	_skip_lbl.anchor_right = 1.0
	_skip_lbl.anchor_top = 1.0
	_skip_lbl.anchor_bottom = 1.0
	_skip_lbl.offset_left = -260
	_skip_lbl.offset_right = -22
	_skip_lbl.offset_top = -104
	_skip_lbl.offset_bottom = -84
	_skip_lbl.add_theme_font_size_override("font_size", 13)
	_skip_lbl.add_theme_color_override("font_color", Color(0.78, 0.76, 0.72, 0.85))
	_skip_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_skip_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_skip_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_skip_lbl.text = "ESC \u2014 skip"
	_skip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_lbl.visible = false
	add_child(_skip_lbl)
	_card = Label.new()
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_theme_font_size_override("font_size", 40)
	_card.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	_card.visible = false
	add_child(_card)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.anchor_left = 0.5
	_sub.anchor_right = 0.5
	_sub.anchor_top = 1.0
	_sub.anchor_bottom = 1.0
	_sub.set_meta("fit_half", float(360))
	_sub.offset_top = -140
	_sub.offset_bottom = -80
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_font_size_override("font_size", 19)
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_sub.add_theme_constant_override("shadow_offset_x", 2)
	_sub.add_theme_constant_override("shadow_offset_y", 2)
	_sub.visible = false
	add_child(_sub)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


# step verbs:
# {"v":"fade","to":0.0/1.0,"dur":1.0}
# {"v":"bars","on":true}
# {"v":"card","text":"...","dur":3.0}
# {"v":"cam","pos":[x,y,z],"look":[x,y,z],"dur":2.0}
# {"v":"line","spk":"eli","text":"...","dur":3.0}
# {"v":"spawn","char":"marcus","at":[x,y,z]}
# {"v":"teleport","who":"player","at":[x,y,z],"rot":0.0}
# {"v":"sfx","name":"..."}  {"v":"music","track":"..."}
# {"v":"wait","dur":1.5}
# {"v":"weather","kind":"rain"}  {"v":"hour","h":22.0}
# {"v":"dialogue","tree":"dlg_..."}   (waits for dialogue end)
# {"v":"flag","name":"...","value":true}
# {"v":"notify","text":"..."}

	_refit()
	UiFit.watch(self, _refit)

func play(id: String, finished: Callable = Callable()) -> void:
	if playing:
		return
	var steps: Array = _script(id)
	if steps.is_empty():
		if finished.is_valid():
			finished.call()
		return
	playing = true
	Game.cutscene_active = true
	_finished_cb = finished
	_steps = steps
	_step_i = -1
	_t = 0.0
	Bus.cutscene_started.emit(id)
	_setup_camera()
	_next_step()


func _setup_camera() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 55.0
	_cam.current = false
	var root := _scene()
	if root and not _cam.is_inside_tree():
		root.add_child(_cam)
	_cam.current = true
	_fade.visible = true


func _process(delta: float) -> void:
	if not playing:
		if _skip_lbl != null and _skip_lbl.visible:
			_skip_lbl.visible = false
		return
	if _skip_lbl != null and not _skip_lbl.visible:
		_skip_lbl.visible = true
	_t += delta
	# skip() parks _step_i at size(); indexing _steps there would throw. This
	# guard is what makes the skip binding safe rather than a crash on keypress.
	if _step_i < 0 or _step_i >= _steps.size():
		_finish()
		return
	var s: Dictionary = _steps[_step_i]
	match s.get("v", ""):
		"fade":
			var d: float = s.get("dur", 1.0)
			_fade.modulate.a = clampf(_t / d, 0.0, 1.0) if s.get("to", 0.0) == 1.0 else 1.0 - clampf(_t / d, 0.0, 1.0)
			_fade.color.a = 1.0
			if _t >= d:
				_next_step()
		"bars", "card", "line", "wait", "notify", "weather", "hour", "flag", "sfx", "music", "spawn", "teleport":
			var d: float = s.get("dur", 0.0)
			if _t >= d:
				_next_step()
		"cam":
			var d: float = s.get("dur", 2.0)
			var k := clampf(_t / maxf(d, 0.001), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			_cam.global_position = _from.lerp(_to_pos, k)
			_cam.look_at(_look_to, Vector3.UP)
			if _t >= d:
				_next_step()
		"dialogue":
			if not DialogueUI.is_open() and _t > 0.5:
				_next_step()
		_:
			_next_step()


var _from := Vector3.ZERO
var _to_pos := Vector3.ZERO
var _look_to := Vector3.ZERO


func _next_step() -> void:
	_step_i += 1
	_t = 0.0
	if _step_i >= _steps.size():
		_finish()
		return
	var s: Dictionary = _steps[_step_i]
	match s.get("v", ""):
		"bars":
			var on: bool = s.get("on", true)
			var h := 70.0
			for b in _bars:
				b.visible = on
			if on:
				_bars[0].offset_top = 0
				_bars[0].offset_bottom = h
				_bars[1].offset_top = -h
				_bars[1].offset_bottom = 0
				_bars[1].anchor_top = 1.0
				_bars[1].anchor_bottom = 1.0
				_bars[1].offset_top = -h
				_bars[1].offset_bottom = 0
		"card":
			_card.text = s.get("text", "")
			_card.visible = true
		"line":
			var c := Db.character(s.get("spk", ""))
			var who: String = c.get("name", s.get("spk", ""))
			_sub.text = ("%s: \"%s\"" % [who, s.get("text", "")]) if who != "" else s.get("text", "")
			_sub.visible = true
			AudioDirector.speak(c.get("voice", "ped_m"), s.get("text", ""))
		"cam":
			_from = _cam.global_position
			_to_pos = _v3(s.get("pos", [0, 5, 10]))
			_look_to = _v3(s.get("look", [0, 1, 0]))
		"spawn":
			_spawn_actor(s.get("char", ""), _v3(s.get("at", [0, 0, 0])))
		"teleport":
			var who: String = s.get("who", "player")
			var node: Node = null
			if who == "player":
				var g := get_tree().get_nodes_in_group("player")
				node = g[0] if g.size() else null
			elif _actors.has(who):
				node = _actors[who]
			if node:
				node.global_position = _v3(s.get("at", [0, 0, 0]))
				node.rotation.y = float(s.get("rot", 0.0))
		"sfx":
			AudioDirector.sfx(s.get("name", ""), 0.1)
		"music":
			AudioDirector.play_music(s.get("track", ""), 1.0)
		"weather":
			WorldState.set_weather(s.get("kind", "clear"))
		"hour":
			WorldState.game_hour = float(s.get("h", 21.0))
		"flag":
			WorldState.set_flag(s.get("name", ""), s.get("value", true))
		"notify":
			Bus.notification.emit(s.get("text", ""), "info")
		"dialogue":
			_card.visible = false
			_sub.visible = false
			DialogueUI.start_tree(s.get("tree", ""))
		"fade":
			pass
		"wait":
			pass
	# instant steps (no dur, not time-based) chain immediately
	if not s.has("dur") and not ["cam", "dialogue", "fade", "wait"].has(s.get("v", "")):
		_next_step()


func _finish() -> void:
	playing = false
	for b in _bars:
		b.visible = false
	_card.visible = false
	_sub.visible = false
	_fade.visible = false
	if _skip_lbl != null:
		_skip_lbl.visible = false
	Game.cutscene_active = false
	if _cam:
		_cam.current = false
		# restore gameplay camera
		var g := get_tree().get_nodes_in_group("cam_rig")
		if g.size():
			var rig: Node = g[0]
			for c in rig.get_children():
				if c is Camera3D:
					c.current = true
	for a in _actors.values():
		if is_instance_valid(a):
			a.queue_free()
	_actors.clear()
	Bus.cutscene_ended.emit("")
	var cb := _finished_cb
	_finished_cb = Callable()
	if cb.is_valid():
		cb.call()


var _actors: Dictionary = {}


func _spawn_actor(cid: String, pos: Vector3) -> void:
	var n := CharacterBody3D.new()
	n.set_script(load("res://scripts/npc/npc.gd"))
	_scene().add_child(n)
	n.setup_named(cid)
	n.global_position = pos
	n.state = n.State.IDLE_ACT
	_actors[cid] = n


func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _script(id: String) -> Array:
	match id:
		"cs_intro":
			var p := _player_pos()
			# THE OPENING IS A CONVERSATION, NOT A VOICEOVER.
			# Eli is the player and is never spawned as an actor; Ruth stands
			# three and a half metres off his right shoulder, under the awning,
			# in the rain. Every line is answered by the next one, and the camera
			# cuts between them on classic shot/reverse-shot grammar so the
			# player always knows who is being replied to.
			var rp := p + Vector3(3.0, 0.0, -2.0)
			# Cam A sits on Ruth's far side and looks past her at Eli.
			# Cam B sits on Eli's far side and looks past him at Ruth.
			# They are ~7 m apart, so each cut genuinely reverses the angle.
			var cam_eli := [p.x + 3.75, 1.75, p.z - 2.50]
			var look_eli := [p.x, 1.56, p.z]
			var cam_ruth := [p.x - 0.75, 1.75, p.z + 0.50]
			var look_ruth := [rp.x, 1.54, rp.z]
			return [
				{"v": "fade", "to": 0.0, "dur": 1.4},
				{"v": "bars", "on": true},
				{"v": "weather", "kind": "rain"},
				{"v": "hour", "h": 21.4},
				{"v": "music", "track": "music_tension"},
				{"v": "card", "text": "CINDER CITY", "dur": 2.6},
				{"v": "card", "text": "Six districts. One debt. Everybody keeps a ledger.", "dur": 3.4},
				{"v": "spawn", "char": "ruth", "at": [rp.x, rp.y, rp.z]},
				{"v": "teleport", "who": "ruth", "at": [rp.x, rp.y, rp.z], "rot": 2.15},
				# master shot: the street, the rain, the two of them
				{"v": "cam", "pos": [p.x + 9.5, 4.6, p.z + 11.0], "look": [p.x + 1.4, 1.3, p.z - 0.8], "dur": 0.05},
				{"v": "sfx", "name": "thunder_1"},
				{"v": "cam", "pos": [p.x + 5.4, 2.5, p.z + 6.2], "look": [p.x + 1.4, 1.35, p.z - 0.8], "dur": 4.2},
				# ---- BEAT 1: Ruth has come to find him ----------------------
				{"v": "cam", "pos": cam_ruth, "look": look_ruth, "dur": 0.05},
				{"v": "line", "spk": "ruth", "text": "Sit down, Elias. You have been standing in that doorway eleven minutes.", "dur": 4.2},
				{"v": "cam", "pos": cam_eli, "look": look_eli, "dur": 0.05},
				{"v": "line", "spk": "eli", "text": "I was counting the rain. It is a habit. Numbers do not move when you are not looking.", "dur": 4.6},
				{"v": "cam", "pos": cam_ruth, "look": look_ruth, "dur": 0.05},
				{"v": "line", "spk": "ruth", "text": "Your brother is not a number.", "dur": 2.6},
				{"v": "cam", "pos": cam_eli, "look": look_eli, "dur": 0.05},
				{"v": "line", "spk": "eli", "text": "Everything is a number, Mama. That is the job. Twelve years reading other people's ledgers.", "dur": 4.6},
				{"v": "cam", "pos": cam_ruth, "look": look_ruth, "dur": 0.05},
				{"v": "line", "spk": "ruth", "text": "Then read this one. Where is Marcus?", "dur": 3.0},
				{"v": "cam", "pos": cam_eli, "look": look_eli, "dur": 0.05},
				{"v": "line", "spk": "eli", "text": "Owed. That is all I have got. Owed, and three days gone.", "dur": 3.6},
				{"v": "cam", "pos": cam_ruth, "look": look_ruth, "dur": 0.05},
				{"v": "line", "spk": "ruth", "text": "Then we call the police.", "dur": 2.4},
				{"v": "cam", "pos": cam_eli, "look": look_eli, "dur": 0.05},
				{"v": "line", "spk": "eli", "text": "The police are on a ledger too, Mama. I have seen that ledger.", "dur": 3.8},
				# ---- BEAT 2: the phone. Crowe's man, and Eli answers back ---
				{"v": "sfx", "name": "phone_ring"},
				{"v": "card", "text": "UNKNOWN NUMBER", "dur": 1.6},
				{"v": "cam", "pos": [p.x + 2.4, 2.6, p.z + 3.4], "look": [p.x + 1.2, 1.45, p.z - 0.6], "dur": 1.2},
				{"v": "line", "spk": "gunnar", "text": "Mr Vane. Silas Crowe sends his regards, and a number. Five thousand. Friday.", "dur": 4.4},
				{"v": "cam", "pos": cam_eli, "look": look_eli, "dur": 0.05},
				{"v": "line", "spk": "eli", "text": "And if Friday comes without it?", "dur": 2.6},
				{"v": "cam", "pos": [p.x + 2.4, 2.6, p.z + 3.4], "look": [p.x + 1.2, 1.45, p.z - 0.6], "dur": 0.05},
				{"v": "line", "spk": "gunnar", "text": "Then the harbour gets a story it has already told twice.", "dur": 3.6},
				{"v": "cam", "pos": cam_eli, "look": look_eli, "dur": 0.05},
				{"v": "line", "spk": "eli", "text": "Marcus is nineteen years old.", "dur": 2.4},
				{"v": "cam", "pos": [p.x + 2.4, 2.6, p.z + 3.4], "look": [p.x + 1.2, 1.45, p.z - 0.6], "dur": 0.05},
				{"v": "line", "spk": "gunnar", "text": "Nineteen is old enough to sign. Friday, Mr Vane.", "dur": 3.2},
				{"v": "sfx", "name": "phone_msg"},
				# ---- BEAT 3: the decision, and the thesis of the game -------
				{"v": "cam", "pos": cam_ruth, "look": look_ruth, "dur": 0.9},
				{"v": "line", "spk": "ruth", "text": "Who was that.", "dur": 2.0},
				{"v": "cam", "pos": cam_eli, "look": look_eli, "dur": 0.05},
				{"v": "line", "spk": "eli", "text": "The man holding the pen.", "dur": 2.6},
				{"v": "cam", "pos": cam_ruth, "look": look_ruth, "dur": 0.05},
				{"v": "line", "spk": "ruth", "text": "So we pay it.", "dur": 2.0},
				{"v": "cam", "pos": [p.x + 1.5, 1.66, p.z + 1.9], "look": [p.x, 1.57, p.z], "dur": 1.1},
				{"v": "line", "spk": "eli", "text": "No. We find out whose hand the pen is in. Everyone in this city has leverage on somebody, Mama. That is the whole economy.", "dur": 6.4},
				{"v": "cam", "pos": cam_ruth, "look": look_ruth, "dur": 0.05},
				{"v": "line", "spk": "ruth", "text": "And when they find out you have been reading their books?", "dur": 3.4},
				# the last line is the closest the camera ever gets to him
				{"v": "cam", "pos": [p.x + 0.72, 1.60, p.z + 0.95], "look": [p.x, 1.58, p.z], "dur": 1.3},
				{"v": "line", "spk": "eli", "text": "Then I will have leverage too.", "dur": 3.2},
				# ---- BEAT 4: pull out to the city, and the title ------------
				{"v": "cam", "pos": [p.x + 8.5, 6.2, p.z + 12.5], "look": [p.x + 1.4, 1.2, p.z - 0.8], "dur": 3.8},
				{"v": "sfx", "name": "thunder_1"},
				{"v": "fade", "to": 1.0, "dur": 1.2},
				{"v": "card", "text": "LEVERAGE", "dur": 3.0},
				{"v": "card", "text": "A D'Youngs Games story", "dur": 2.6},
				{"v": "card", "text": "Friday is three days away.", "dur": 2.8},
				{"v": "bars", "on": false},
				{"v": "fade", "to": 0.0, "dur": 1.0},
			]
		"cs_kidnap":
			var p := _player_pos()
			return [
				{"v": "fade", "to": 0.0, "dur": 0.8},
				{"v": "bars", "on": true},
				{"v": "card", "text": "CINDER CITY — 9:40 PM", "dur": 2.6},
				{"v": "cam", "pos": [p.x + 6, 3.2, p.z + 8], "look": [p.x, 1.2, p.z], "dur": 0.01},
				{"v": "spawn", "char": "gunnar", "at": [p.x + 4, 0, p.z + 3]},
				{"v": "cam", "pos": [p.x + 3.4, 2.0, p.z + 4.6], "look": [p.x + 4, 1.4, p.z + 3], "dur": 2.5},
				{"v": "line", "spk": "gunnar", "text": "The kid's got a tab. Tabs get paid. That's the whole sermon.", "dur": 3.4},
				{"v": "line", "spk": "eli", "text": "Marcus! MARCUS!", "dur": 2.2},
				{"v": "cam", "pos": [p.x + 1.6, 1.7, p.z + 2.2], "look": [p.x, 1.5, p.z], "dur": 1.6},
				{"v": "sfx", "name": "door_slam"},
				{"v": "line", "spk": "gunnar", "text": "Friday. Five thousand. Or the harbor gets a new story.", "dur": 3.6},
				{"v": "fade", "to": 1.0, "dur": 1.2},
				{"v": "card", "text": "EVERYONE HAS LEVERAGE ON YOU.", "dur": 3.0},
				{"v": "bars", "on": false},
				{"v": "fade", "to": 0.0, "dur": 0.8},
			]
		"cs_exchange":
			var p := _player_pos()
			return [
				{"v": "fade", "to": 0.0, "dur": 0.6},
				{"v": "bars", "on": true},
				{"v": "cam", "pos": [p.x + 5, 2.6, p.z + 6], "look": [p.x, 1.3, p.z], "dur": 2.0},
				{"v": "line", "spk": "crane", "text": "The drive for the boy. No heroes, no ledgers, no Static-88. Just a trade.", "dur": 3.8},
				{"v": "line", "spk": "eli", "text": "And when the trade's done? Who holds the pen then?", "dur": 2.8},
				{"v": "sfx", "name": "thunder_1"},
				{"v": "fade", "to": 1.0, "dur": 1.0},
				{"v": "bars", "on": false},
				{"v": "fade", "to": 0.0, "dur": 0.6},
			]
		"cs_finale":
			var p := _player_pos()
			return [
				{"v": "fade", "to": 0.0, "dur": 0.6},
				{"v": "bars", "on": true},
				{"v": "music", "track": "music_ending"},
				{"v": "card", "text": "THE LEVERAGE", "dur": 2.4},
				{"v": "cam", "pos": [p.x + 8, 4.0, p.z + 10], "look": [p.x, 1.5, p.z], "dur": 3.0},
				{"v": "line", "spk": "crane", "text": "Everyone has leverage on you, Eli. Tonight we find out what yours is worth.", "dur": 4.0},
				{"v": "line", "spk": "eli", "text": "Mine's simple. I know where the bodies are buried. All of them. Yours too.", "dur": 3.8},
				{"v": "fade", "to": 1.0, "dur": 1.2},
				{"v": "bars", "on": false},
				{"v": "fade", "to": 0.0, "dur": 0.8},
			]
		"cs_ending":
			return [
				{"v": "fade", "to": 0.0, "dur": 0.5},
				{"v": "bars", "on": true},
				{"v": "card", "text": "Three debts. Three truths. One city that keeps score.", "dur": 4.0},
				{"v": "card", "text": "Marcus is home. The ledger is ash. The pen is yours now.", "dur": 4.0},
				{"v": "line", "spk": "ruth", "text": "You came back. That's the only leverage that ever mattered, baby.", "dur": 3.6},
				{"v": "card", "text": "LEVERAGE — a D'Youngs Games story", "dur": 4.0},
				{"v": "fade", "to": 1.0, "dur": 2.0},
				{"v": "bars", "on": false},
			]
	return []


func _player_pos() -> Vector3:
	var g := get_tree().get_nodes_in_group("player")
	if g.size():
		return g[0].global_position
	return Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	## A 90-second opening the player cannot leave is not a cinematic, it is a
	## hostage situation. skip() existed from day one and was bound to nothing.
	if not playing:
		return
	if event.is_action_pressed("skip_cutscene"):
		skip()
		get_viewport().set_input_as_handled()


func skip() -> void:
	if playing:
		_step_i = _steps.size()
		_t = 9999.0


func _scene() -> Node:
	var t := get_tree()
	if t == null:
		t = Engine.get_main_loop() as SceneTree
	return t.current_scene if t != null else null


func _refit() -> void:
	UiFit.refit_tree(self)
