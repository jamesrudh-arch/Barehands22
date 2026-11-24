extends Node
## Game — application state machine, scene flow, settings, pause, new/continue.

enum State { BOOT, MENU, LOADING, PLAYING, CINEMATIC, PAUSED, GAMEOVER }

var state: State = State.BOOT
var settings: Dictionary = {
	"master": 0.9, "music": 0.7, "sfx": 0.9, "vox": 0.9,
	"sensitivity": 1.0, "subtitles": true, "quality": 1,  # 0 low 1 med 2 high
	"touch_scale": 1.0, "invert_y": false, "shake": true,
	"difficulty": 1,   # index into Difficulty.PRESETS: 0 street 1 ledger 2 crowe
}
const SETTINGS_PATH := "user://settings.json"

var current_district: String = "kiln_row"
var player: Node = null            # set by city scene on spawn
var mission_manager: Node = null   # set by city scene
var cutscene_active := false

var _scene_root: Node = null
var _fade: CanvasLayer = null


func _notification(what: int) -> void:
	## Mobile app lifecycle. On iOS/iPadOS -- the XOGOT target -- the OS driver
	## sends this when the app goes to background:
	## `OS_AppleEmbedded::on_enter_background()` notifies the MainLoop with
	## NOTIFICATION_APPLICATION_PAUSED and only then calls `on_focus_out()`,
	## which stops the audio driver and invalidates the CADisplayLink that drives
	## the frame loop. `SceneTree::_notification` propagates PAUSED to every node,
	## so this autoload sees it.
	##
	## The engine already handles the parts that are the engine's job, and this
	## deliberately does not duplicate them: rendering halts (display link
	## invalidated, so _process/_physics_process stop and no mission timer runs
	## blind), audio stops (audio_driver.stop()), held inputs are released
	## (Input::release_pressed_events() also clears sticky action_press state,
	## which is what the touch buttons use), and touches are cleared
	## (clearTouches). What nothing in the engine does is protect the SAVE.
	##
	## iOS terminates backgrounded apps routinely under memory pressure, and
	## every existing autosave trigger is a discrete achievement -- mission
	## complete, safehouse rest, hidden stash, property purchase, manual save.
	## So a player forty minutes into a mission who takes a phone call can have
	## XOGOT killed with nothing written since the last mission they finished.
	## PAUSED is the "we may be terminated" moment and it arrives before
	## rendering and audio are torn down, so the write can still complete.
	##
	## Not FOCUS_OUT: that also fires for a transient interruption such as a
	## notification banner or Control Center, where the app is not at risk, and
	## saving on every banner is write churn for no benefit.
	##
	## request_autosave() already no-ops when player == null, so this is safe
	## from the menu, the boot scene or a game-over screen.
	if what == MainLoop.NOTIFICATION_APPLICATION_PAUSED:
		request_autosave()


func _ready() -> void:
	_load_settings()
	AudioDirector.settings = {
		"master": settings["master"], "music": settings["music"],
		"sfx": settings["sfx"], "vox": settings["vox"]}
	AudioDirector.apply_settings()
	_apply_difficulty()
	Bus.crime_committed.connect(_on_crime)


func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		if d is Dictionary:
			for k in d:
				settings[k] = d[k]


func _apply_difficulty() -> void:
	## settings.json is the persisted home of the preset; Difficulty owns the
	## live value. Pushed at boot and on every change so a save file never has
	## to carry a preference that belongs to the player, not the playthrough.
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return
	diff.set_preset(int(settings.get("difficulty", 1)), false)


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(settings))
	f.close()
	AudioDirector.settings = {
		"master": settings["master"], "music": settings["music"],
		"sfx": settings["sfx"], "vox": settings["vox"]}
	AudioDirector.apply_settings()
	_apply_difficulty()
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
