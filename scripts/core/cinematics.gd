extends Node
## Cinematics — the fight-feel layer: hit-stop, slow-mo kill cams, FOV
## punches and camera shake budgets. Everything here is micro-cinematic:
## fractions of a second that make impacts read like a film beat, never
## cutscenes that steal the controls.
##
## Time scale is arbitrated with the player's FOCUS bullet-time: whoever
## wants the world slower wins, and both restore cleanly.

var _hitstop_t := 0.0
var _slowmo_t := 0.0
var _slowmo_scale := 0.25
var _base_scale := 1.0


func _process(delta: float) -> void:
	var want := 1.0
	if _hitstop_t > 0.0:
		_hitstop_t -= delta * maxf(Engine.time_scale, 0.05)
		want = minf(want, 0.08)
	if _slowmo_t > 0.0:
		_slowmo_t -= delta * maxf(Engine.time_scale, 0.05)
		want = minf(want, _slowmo_scale)
	if want >= 1.0 and Engine.time_scale < 1.0 and not _focus_busy():
		Engine.time_scale = 1.0
	elif want < 1.0:
		# never fight FOCUS: take the slower of the two
		Engine.time_scale = minf(Engine.time_scale if _focus_busy() else 1.0, want)


func _focus_busy() -> bool:
	var g := get_tree().get_nodes_in_group("player")
	return not g.is_empty() and bool(g[0].get("focus_active"))


## Freeze-frame on a crushing blow (0.05–0.12 s reads best).
func hitstop(t: float = 0.08) -> void:
	if _focus_busy():
		return                       # FOCUS already slows the world
	_hitstop_t = maxf(_hitstop_t, t)


## Kill-cam slow-mo: last enemy of a fight, finishers, big wrecks.
func slowmo(t: float = 0.7, scale: float = 0.25) -> void:
	if _focus_busy():
		return
	_slowmo_t = maxf(_slowmo_t, t)
	_slowmo_scale = scale


## FOV punch through the player's camera rig (safe no-op when absent).
func fov_punch(amount: float) -> void:
	var g := get_tree().get_nodes_in_group("player")
	if g.is_empty():
		return
	var rig = g[0].get("cam_rig")
	if rig != null and rig.has_method("kick_fov"):
		rig.kick_fov(amount)
