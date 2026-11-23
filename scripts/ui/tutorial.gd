extends Node
## Tutorial — contextual coaching during the prologue (m01 flags
## tutorial: move/camera/interact) and first combat/vehicle moments.
## Hints surface through Bus.prompt_hint (HUD) and toasts; never blocks play.

var _step := 0
var _done: Dictionary = {}
var _hint_cd := 0.0
var _last_prompt := ""

const STEPS := [
	{"id": "camera", "hint": "Drag the right side of the screen to look around (mouse: hold + move)."},
	{"id": "move", "hint": "Left stick / WASD to move. Hold RUN to sprint — stamina burns."},
	{"id": "interact", "hint": "Glowing markers are doors. Walk up and press B (DODGE button doubles as INTERACT)."},
	{"id": "combat", "hint": "X = PUNCH, Y = HEAVY, A = KICK, B = DODGE. Hold BLK to guard — time it to parry."},
	{"id": "style", "hint": "STY cycles fighting styles: Brawler, Kickboxing, Grappling, Drunken, Weapon."},
	{"id": "vehicle", "hint": "Near a car: CAR button (or vehicle_enter) to drive. BRK brakes, HORN honks."},
	{"id": "phone", "hint": "PHONE opens your phone: map, jobs, radio, contacts, bag, saves."},
	{"id": "wanted", "hint": "Crime raises WANTED stars. Break line of sight and the heat cools — or get busted."},
]


func _ready() -> void:
	Bus.mission_started.connect(_on_mission)
	Bus.dialogue_ended.connect(func(): _try("interact"))
	Bus.combat_state_changed.connect(_on_combat)
	Bus.vehicle_entered.connect(_on_veh)
	Bus.phone_opened.connect(func(): _try("phone"))
	Bus.wanted_changed.connect(_on_wanted)
	Bus.objective_updated.connect(_on_obj)


func _on_combat(on: bool) -> void:
	if on:
		_try("combat")


func _on_veh(_t: String) -> void:
	_try("vehicle")


func _on_wanted(l: int) -> void:
	if l > 0:
		_try("wanted")


func _on_obj(_m: String, _t: String) -> void:
	_advance_prologue()


func _process(delta: float) -> void:
	_hint_cd -= delta
	if WorldState.get_flag("tutorial_done", false):
		return
	if _step < STEPS.size() and _hint_cd <= 0.0:
		_show(STEPS[_step])


func _show(s: Dictionary) -> void:
	if _done.has(s["id"]):
		_step += 1
		return
	_done[s["id"]] = true
	_step += 1
	_hint_cd = 12.0
	Bus.prompt_hint.emit(s["hint"])
	Bus.notification.emit(s["hint"], "info")
	AudioDirector.sfx("ui_notify", 0.15)
	if _step >= STEPS.size():
		WorldState.set_flag("tutorial_done", true)


func _try(id: String) -> void:
	for i in STEPS.size():
		if STEPS[i]["id"] == id and not _done.has(id):
			_show(STEPS[i])
			return


func _on_mission(mid: String) -> void:
	if mid == "m01_last_call":
		_step = 0
		_hint_cd = 3.0


func _advance_prologue() -> void:
	# nudge the next relevant hint when objectives change
	if _hint_cd > 6.0:
		_hint_cd = 2.0
