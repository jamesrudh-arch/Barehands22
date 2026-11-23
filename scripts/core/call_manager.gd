extends Node
## CallManager — the living phone: scheduled incoming calls with a real
## ringing state machine, answer/decline/missed flow, call log, message
## threads with read state, and story-driven scheduling (mission offers,
## check-ins, warnings). One authoritative implementation; PhoneUI renders
## history/threads from here, the overlay lives here.

enum State { IDLE, RINGING, IN_CALL }

signal incoming_call(info: Dictionary)
signal state_changed(s: int)
signal new_message(thread_id: String)

const RING_TIMEOUT := 22.0

var state: int = State.IDLE
var current: Dictionary = {}          # active call info
var _ring_t := 0.0
var _ring_player: AudioStreamPlayer
var _call_player: AudioStreamPlayer
var _overlay: Control
var _pending: Array = []              # scheduled calls waiting for a calm moment
var _lines: Array = []                # current conversation lines
var _line_i := 0
var _line_t := 0.0


func _hour() -> String:
	var h: float = WorldState.game_hour
	return "%02d:%02d" % [int(h) % 24, int(fmod(h, 1.0) * 60)]


func _ready() -> void:
	_ring_player = AudioStreamPlayer.new()
	_ring_player.bus = "SFX"
	add_child(_ring_player)
	_call_player = AudioStreamPlayer.new()
	_call_player.bus = "SFX"
	add_child(_call_player)
	Bus.game_state_changed.connect(_on_game_state)


# ------------------------------------------------------------- scheduling --
func schedule_call(char_id: String, kind: String, payload: String = "", delay: float = 0.0) -> void:
	var info := {"char": char_id, "kind": kind, "payload": payload,
		"time": _hour(),
		"id": "%s_%d" % [char_id, Time.get_ticks_msec()]}
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): _try_ring(info))
	else:
		_try_ring(info)


func _try_ring(info: Dictionary) -> void:
	if state != State.IDLE or Game.state == Game.State.CINEMATIC or WorldState.wanted > 1:
		_pending.append(info)   # never stack calls; retry when calm
		return
	_start_ring(info)


func _start_ring(info: Dictionary) -> void:
	state = State.RINGING
	current = info
	_ring_t = 0.0
	var st := AudioDirector.stream("res://assets/audio/sfx/phone_ring.wav")
	if st:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_ring_player.stream = st
		_ring_player.play()
	incoming_call.emit(info)
	_show_overlay(info)
	state_changed.emit(state)


func _process(delta: float) -> void:
	if state == State.RINGING:
		_ring_t += delta
		if _ring_t >= RING_TIMEOUT:
			miss_call()
	elif state == State.IN_CALL:
		_line_t += delta
		if _overlay and _line_i < _lines.size():
			var dur: float = _lines[_line_i].get("dur", 3.0)
			if _line_t >= dur:
				_line_i += 1
				_line_t = 0.0
				_update_overlay_line()
				if _line_i >= _lines.size():
					end_call()


# ------------------------------------------------------------------ flows --
func answer_call() -> void:
	if state != State.RINGING:
		return
	_ring_player.stop()
	AudioDirector.sfx("phone_connect", 0.02, 0.9)
	state = State.IN_CALL
	_log("answered")
	state_changed.emit(state)
	if current.get("kind", "") == "mission":
		var mm := get_node_or_null("/root/MissionManager")
		if mm and mm.has_method("answer_phone_call"):
			_hide_overlay()
			mm.answer_phone_call()
			return
	_line_i = 0
	_line_t = 0.0
	_lines = _conversation_for(current)
	_update_overlay_line()


func decline_call() -> void:
	if state != State.RINGING:
		return
	_ring_player.stop()
	_log("missed")
	_hide_overlay()
	state = State.IDLE
	current = {}
	_maybe_story_consequence("declined")
	state_changed.emit(state)


func miss_call() -> void:
	if state != State.RINGING:
		return
	_ring_player.stop()
	_log("missed")
	_hide_overlay()
	state = State.IDLE
	current = {}
	_maybe_story_consequence("missed")
	state_changed.emit(state)


func end_call() -> void:
	if state != State.IN_CALL:
		return
	_log("done")
	_hide_overlay()
	state = State.IDLE
	var finished: Dictionary = current
	current = {}
	state_changed.emit(state)
	_maybe_story_consequence("completed", finished)


func _log(result: String) -> void:
	var log: Array = WorldState.call_log
	log.append({"char": current.get("char", "?"), "kind": current.get("kind", ""),
		"result": result, "hour": _hour(),
		"day": WorldState.day})
	if log.size() > 40:
		log.pop_front()


func _maybe_story_consequence(what: String, info: Dictionary = {}) -> void:
	var src: Dictionary = info if not info.is_empty() else current
	if src.get("kind", "") != "offer":
		return
	var mid: String = src.get("payload", "")
	if mid == "":
		return
	if what == "completed":
		return  # mission already accepted during the call conversation
	# declined/missed a mission offer: it stays available, nudge via message
	send_message(src.get("char", "marcus"), "msg_nudge",
		"Pick up your phone, Eli. That job won't wait forever.")
	MissionManager.story_offer = mid


# ------------------------------------------------------------ conversations --
func _conversation_for(info: Dictionary) -> Array:
	var ch: Dictionary = Db.character(info.get("char", "eli"))
	var name: String = ch.get("name", info.get("char", "???"))
	match info.get("kind", ""):
		"offer":
			var mid: String = info.get("payload", "")
			var m: Dictionary = Db.mission(mid)
			return [
				{"who": name, "text": "Eli. It's %s. Keep your voice down." % name, "dur": 3.2},
				{"who": name, "text": m.get("summary", "There's work. Are you in?"), "dur": 4.2},
				{"who": "Eli", "text": "Where?", "dur": 1.6},
				{"who": name, "text": "Check the job on your phone. And Eli — don't be late.", "dur": 3.4},
				{"who": "SYS", "text": "Mission added: %s" % m.get("title", mid), "dur": 2.4}]
		"checkin":
			return [
				{"who": name, "text": "You eating? You sound like gravel.", "dur": 2.8},
				{"who": "Eli", "text": "I'm fine. Long night.", "dur": 2.2},
				{"who": name, "text": "Then sleep in. The city will still be broken tomorrow.", "dur": 3.4}]
		"warning":
			return [
				{"who": name, "text": "Heads up — cars with plates crossed out have been circling your block.", "dur": 4.0},
				{"who": "Eli", "text": "Halcyon?", "dur": 1.4},
				{"who": name, "text": "Maybe. Keep your head on a swivel.", "dur": 2.6}]
		_:
			return [{"who": name, "text": "Just checking you're still in one piece.", "dur": 2.6}]


func place_outgoing(cid: String) -> void:
	var st := AudioDirector.stream("res://assets/audio/sfx/phone_ringback.wav")
	if st:
		_ring_player.stream = st
		_ring_player.play()
		get_tree().create_timer(1.6).timeout.connect(func(): _ring_player.stop())
	WorldState.call_log.append({"char": cid, "kind": "out", "result": "out",
		"hour": _hour(),
		"day": WorldState.day})


# ---------------------------------------------------------------- messages --
func send_message(char_id: String, thread_tag: String, text: String) -> void:
	var threads: Dictionary = WorldState.msg_threads
	var tid: String = char_id
	if not threads.has(tid):
		threads[tid] = []
	threads[tid].append({"from": char_id, "text": text, "read": false,
		"hour": _hour()})
	AudioDirector.sfx("phone_msg", 0.02, 0.8)
	new_message.emit(tid)


func mark_thread_read(tid: String) -> void:
	var threads: Dictionary = WorldState.msg_threads
	if threads.has(tid):
		for m in threads[tid]:
			m["read"] = true


func unread_count() -> int:
	var n := 0
	for tid in WorldState.msg_threads:
		for m in WorldState.msg_threads[tid]:
			if not m["read"]:
				n += 1
	return n


# ----------------------------------------------------------------- overlay --
func _show_overlay(info: Dictionary) -> void:
	_hide_overlay()
	var layer := CanvasLayer.new()
	layer.name = "CallOverlay"
	layer.layer = 60
	layer.set_script(load("res://scripts/ui/call_overlay.gd"))
	add_child(layer)
	_overlay = layer.get("root") if layer.get("root") != null else null
	layer.setup(info)


func _update_overlay_line() -> void:
	if _overlay_layer() and _line_i < _lines.size():
		_overlay_layer().set_line(_lines[_line_i])


func _overlay_layer():
	return get_node_or_null("CallOverlay")


func _hide_overlay() -> void:
	var o := get_node_or_null("CallOverlay")
	if o:
		o.queue_free()
	_overlay = null


func _on_game_state(s: StringName) -> void:
	if s == "cinematic" and state == State.RINGING:
		miss_call()
	# retry pendings when back to playing
	if s == "playing" and _pending.size() > 0 and state == State.IDLE:
		var info: Dictionary = _pending.pop_front()
		get_tree().create_timer(4.0).timeout.connect(func(): _try_ring(info))
