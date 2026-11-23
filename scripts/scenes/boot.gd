extends Control
## Boot — D'Youngs Games presentation splash, then title.

var _t := 0.0
var _logo: TextureRect
var _name: Label
var _tag: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)  # root must fill the window (XOGOT/device fix)
	var bg := ColorRect.new()
	bg.color = Color(0.027, 0.024, 0.031)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/textures/ui/splash_dyoungs.png")
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.set_meta("fit_half", float(220))
	_logo.offset_top = -150
	_logo.offset_bottom = 110
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.modulate.a = 0.0
	add_child(_logo)
	_name = Label.new()
	_name.text = "D'YOUNGS GAMES"
	_name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_name.set_meta("fit_half", float(300))
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
	_tag.set_meta("fit_half", float(300))
	_tag.offset_top = -104
	_tag.offset_bottom = -76
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.add_theme_font_size_override("font_size", 15)
	_tag.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	_tag.modulate.a = 0.0
	add_child(_tag)
	AudioDirector.play_music("music_menu", 1.0)



	var dbg := Label.new()
	dbg.name = "DbgInfo"
	dbg.position = Vector2(6, 6)
	dbg.add_theme_font_size_override("font_size", 9)
	dbg.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55, 0.9))
	add_child(dbg)
	_dbg = dbg
	_dbg_text()
	_refit()
	UiFit.watch(self, _refit)

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


func _refit() -> void:
	UiFit.refit_tree(self)
	_dbg_text()


var _dbg: Label = null


func _dbg_text() -> void:
	if _dbg == null:
		return
	var vp := get_viewport()
	var vs: Vector2 = vp.get_visible_rect().size if vp else Vector2.ZERO
	_dbg.text = "vp %dx%d | root %dx%d | %s | Godot %s | %s" % [
		int(vs.x), int(vs.y), int(size.x), int(size.y), OS.get_name(),
		str(Engine.get_version_info().get("string", "?")), DisplayServer.get_name()]
