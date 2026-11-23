extends Control
## Boot — D'Youngs Games presentation splash, then title.

var _t := 0.0
var _logo: TextureRect
var _name: Label
var _tag: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.027, 0.024, 0.031)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/textures/ui/splash_dyoungs.png")
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.offset_left = -220
	_logo.offset_right = 220
	_logo.offset_top = -150
	_logo.offset_bottom = 110
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.modulate.a = 0.0
	add_child(_logo)
	_name = Label.new()
	_name.text = "D'YOUNGS GAMES"
	_name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name.offset_left = -300
	_name.offset_right = 300
	_name.offset_top = -140
	_name.offset_bottom = -100
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 30)
	_name.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	_name.modulate.a = 0.0
	add_child(_name)
	_tag = Label.new()
	_tag.text = "presents"
	_tag.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tag.offset_left = -300
	_tag.offset_right = 300
	_tag.offset_top = -104
	_tag.offset_bottom = -76
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	_tag.modulate.a = 0.0
	add_child(_tag)
	AudioDirector.play_music("music_menu", 1.0)


func _process(delta: float) -> void:
	_t += delta
	var a := clampf(_t / 1.2, 0.0, 1.0)
	_logo.modulate.a = a
	_name.modulate.a = a
	_tag.modulate.a = clampf((_t - 0.6) / 1.0, 0.0, 1.0)
	if _t > 2.2:
		var fade := clampf((_t - 2.2) / 1.0, 0.0, 1.0)
		modulate.a = 1.0 - fade
	if _t > 3.4:
		set_process(false)
		get_tree().change_scene_to_file("res://scenes/menu/title.tscn")
