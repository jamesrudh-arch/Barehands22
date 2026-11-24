extends CanvasLayer
## Incoming / in-call overlay: caller identity, answer & decline, subtitles.

var root: Control
var _sub: Label
var _who: Label
var _hint: Label


func setup(info: Dictionary) -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var ch: Dictionary = Db.character(info.get("char", "eli"))
	# caller card
	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.set_meta("fit_half", 190.0)
	card.offset_top = 150
	card.offset_bottom = 430
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/textures/ui/panel9.png")
	sb.texture_margin_left = 16
	sb.texture_margin_right = 16
	sb.texture_margin_top = 16
	sb.texture_margin_bottom = 16
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	var face := TextureRect.new()
	var fi: int = int(ch.get("app", {}).get("face", 0))
	face.texture = load("res://assets/textures/faces/face_%02d.png" % (fi % 24))
	face.set_anchors_preset(Control.PRESET_CENTER_TOP)
	face.offset_left = -60
	face.offset_right = 60
	face.offset_top = 170
	face.offset_bottom = 290
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(face)
	_who = Label.new()
	Type.apply(_who, "display")
	_who.text = str(ch.get("name", info.get("char", "UNKNOWN")))
	_who.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_who.set_meta("fit_half", 180.0)
	_who.offset_top = 300
	_who.offset_bottom = 330
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_who.add_theme_font_size_override("font_size", 22)
	_who.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	root.add_child(_who)
	_hint = Label.new()
	_hint.text = "INCOMING CALL — RINGING"
	_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint.set_meta("fit_half", 180.0)
	_hint.offset_top = 332
	_hint.offset_bottom = 356
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.66))
	root.add_child(_hint)
	# answer / decline
	var ya := Button.new()
	ya.text = "ANSWER"
	ya.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ya.offset_left = -170
	ya.offset_right = -20
	ya.offset_top = 372
	ya.offset_bottom = 420
	ya.add_theme_font_size_override("font_size", 17)
	ya.pressed.connect(func():
		CallManager.answer_call())
	root.add_child(ya)
	var yn := Button.new()
	yn.text = "DECLINE"
	yn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	yn.offset_left = 20
	yn.offset_right = 170
	yn.offset_top = 372
	yn.offset_bottom = 420
	yn.add_theme_font_size_override("font_size", 17)
	yn.pressed.connect(func():
		CallManager.decline_call())
	root.add_child(yn)
	_answer_btn = ya
	_decline_btn = yn
	# subtitle line (in-call)
	_sub = Label.new()
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.set_meta("fit_half", 260.0)
	_sub.offset_top = -160
	_sub.offset_bottom = -90
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", Color(0.92, 0.9, 0.85))
	_sub.visible = false
	root.add_child(_sub)
	var hang := Button.new()
	hang.text = "HANG UP"
	hang.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hang.offset_left = -80
	hang.offset_right = 80
	hang.offset_top = -80
	hang.offset_bottom = -36
	hang.add_theme_font_size_override("font_size", 15)
	hang.visible = false
	hang.pressed.connect(func():
		CallManager.end_call())
	root.add_child(hang)
	_hang_btn = hang
	UiFit.refit_tree(root)
	UiFit.watch(root, _refit)


var _answer_btn: Button
var _decline_btn: Button
var _hang_btn: Button


func _refit() -> void:
	UiFit.refit_tree(root)


func set_line(line: Dictionary) -> void:
	if _sub == null:
		return
	_sub.visible = true
	_hint.text = "CALL IN PROGRESS"
	_answer_btn.visible = false
	_decline_btn.visible = false
	_hang_btn.visible = true
	var who: String = line.get("who", "")
	_sub.text = ("%s: %s" % [who, line.get("text", "")]) if who != "SYS" else line.get("text", "")
