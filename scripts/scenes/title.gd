extends Control
## Title screen — LEVERAGE logo over the city night, tap to continue.

var _t := 0.0
var _tap: Label


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/textures/ui/menu_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/textures/ui/logo_leverage.png")
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -360
	logo.offset_right = 360
	logo.offset_top = 70
	logo.offset_bottom = 330
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(logo)
	var tag := Label.new()
	tag.text = "EVERYONE HAS LEVERAGE ON YOU."
	tag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tag.offset_left = -400
	tag.offset_right = 400
	tag.offset_top = 340
	tag.offset_bottom = 372
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 19)
	tag.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	add_child(tag)
	_tap = Label.new()
	_tap.text = "TAP TO CONTINUE"
	_tap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tap.offset_left = -300
	_tap.offset_right = 300
	_tap.offset_top = -90
	_tap.offset_bottom = -50
	_tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap.add_theme_font_size_override("font_size", 22)
	add_child(_tap)
	var ver := Label.new()
	ver.text = "v0.9.0 — a D'Youngs Games story — Godot 4.7 / Mobile"
	ver.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ver.offset_left = -400
	ver.offset_right = 400
	ver.offset_top = -40
	ver.offset_bottom = -14
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.5, 0.48, 0.44))
	add_child(ver)
	AudioDirector.play_music("music_menu", 1.0)


func _process(delta: float) -> void:
	_t += delta
	_tap.modulate.a = 0.55 + 0.45 * sin(_t * 3.0)


func _input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		pressed = event.pressed
	elif event is InputEventKey:
		pressed = event.pressed
	if pressed:
		set_process(false)
		set_process_input(false)
		AudioDirector.sfx("ui_confirm", 0.2)
		Game.goto_scene("res://scenes/menu/notice.tscn")
		Game.set_state(Game.State.MENU)
