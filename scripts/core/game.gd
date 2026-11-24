extends Node
## Game — application state machine, scene flow, settings, pause, new/continue.

enum State { BOOT, MENU, LOADING, PLAYING, CINEMATIC, PAUSED, GAMEOVER }

var state: State = State.BOOT
var settings: Dictionary = {
	"master": 0.9, "music": 0.7, "sfx": 0.9, "vox": 0.9,
	"sensitivity": 1.0, "subtitles": true, "quality": 1,  # 0 low 1 med 2 high
	"touch_scale": 1.0, "invert_y": false, "shake": true,
}
const SETTINGS_PATH := "user://settings.json"

var current_district: String = "kiln_row"
var player: Node = null            # set by city scene on spawn
var mission_manager: Node = null   # set by city scene
var cutscene_active := false

var _scene_root: Node = null
var _fade: CanvasLayer = null


func _ready() -> void:
	_load_settings()
	AudioDirector.settings = {
		"master": settings["master"], "music": settings["music"],
		"sfx": settings["sfx"], "vox": settings["vox"]}
	AudioDirector.apply_settings()
	Bus.crime_committed.connect(_on_crime)


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if d is Dictionary:
			for k in d:
				settings[k] = d[k]


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(settings))
	f.close()
	AudioDirector.settings = {
		"master": settings["master"], "music": settings["music"],
		"sfx": settings["sfx"], "vox": settings["vox"]}
	AudioDirector.apply_settings()
	Bus.settings_changed.emit()


func set_state(s: State) -> void:
	if state == s:
		return
	state = s
	get_tree().paused = (s == State.PAUSED)
	Bus.game_state_changed.emit(State.keys()[s].to_lower())


# ------------------------------------------------------------- scene flow --
func goto_scene(path: String, on_ready: Callable = Callable()) -> void:
	set_state(State.LOADING)
	# free previous gameplay scene
	if _scene_root != null:
		_scene_root.queue_free()
		_scene_root = null
	await get_tree().process_frame
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Game: cannot load scene " + path)
		return
	_scene_root = packed.instantiate()
	get_tree().root.add_child(_scene_root)
	get_tree().current_scene = _scene_root
	await get_tree().process_frame
	set_state(State.PLAYING)
	Bus.scene_changed.emit(path)
	if on_ready.is_valid():
		on_ready.call()


func new_game() -> void:
	WorldState.reset_all()
	goto_scene("res://scenes/world/city.tscn", _after_city_boot_new)


func continue_game(slot: int) -> void:
	var d := SaveSystem.load_game(slot)
	if d.is_empty():
		Bus.notification.emit("No save found.", "error")
		return
	goto_scene("res://scenes/world/city.tscn", func():
		_after_city_boot_load(d))


func _after_city_boot_new() -> void:
	Progression.reset()
	Difficulty.reset()
	player = _find_player()
	if player:
		player.start_story_intro()


func _after_city_boot_load(d: Dictionary) -> void:
	player = _find_player()
	if player and d.has("player"):
		player.apply_save(d["player"])
	if d.has("missions") and mission_manager:
		mission_manager.apply_save(d["missions"])
	if d.has("progression"):
		Progression.apply_save(d["progression"])
		Progression.refresh()


func _find_player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


func request_autosave() -> void:
	if player == null:
		return
	SaveSystem.save_game(0, _save_extra())  # slot 0 doubles as autosave


func save_to_slot(slot: int) -> void:
	if player == null:
		return
	SaveSystem.save_game(slot, _save_extra())


func _save_extra() -> Dictionary:
	var extra := {
		"player": player.save_state() if player else {},
		"missions": mission_manager.save_state() if mission_manager else {},
		"district": current_district,
	}
	return extra


func _unhandled_input(ev: InputEvent) -> void:
	## BUG FIXED: the "pause" action existed in project.godot but nothing ever
	## read it, and its key was bound to KEY_SPECIAL (4194304) rather than
	## KEY_ESCAPE (4194305) — so on a keyboard there was no way to pause at
	## all. The pad's START worked only because the touch button shared the
	## same call. Cutscenes get Escape first, and they mark the event handled.
	if ev.is_action_pressed("pause"):
		if cutscene_active or state == State.CINEMATIC:
			return
		pause_toggle()
		get_viewport().set_input_as_handled()


func pause_toggle() -> void:
	if state == State.PLAYING:
		set_state(State.PAUSED)
	elif state == State.PAUSED:
		set_state(State.PLAYING)


func game_over(kind: String) -> void:
	set_state(State.GAMEOVER)
	AudioDirector.sting("sting_wasted" if kind != "busted" else "sting_busted")
	Bus.notification.emit(kind.to_upper(), "gameover")


# ------------------------------------------------------------------ crime --
func _on_crime(crime: String, severity: int, _pos: Vector3) -> void:
	# witnesses escalate this via police system; base bump here
	var lvl := WorldState.wanted
	var target := clampi(maxi(lvl, severity), 0, 5)
	if target > lvl:
		WorldState.set_wanted(target)
