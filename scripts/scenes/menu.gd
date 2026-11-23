extends Control
## Main menu — New Game, Continue (3 slots), Settings, Credits.

var _panel: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)  # root must fill the window (XOGOT/device fix)
	Game.set_state(Game.State.MENU)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/textures/ui/menu_bg.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.04, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/textures/ui/logo_leverage.png")
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.set_meta("fit_half", float(260))
	logo.offset_top = 44
	logo.offset_bottom = 240
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(logo)
	_panel = VBoxContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.set_meta("fit_half", float(230))
	_panel.offset_top = -60
	_panel.offset_bottom = 260
	_panel.add_theme_constant_override("separation", 12)
	add_child(_panel)
	_build_main()
	AudioDirector.play_music("music_menu", 1.0)


	_refit()
	UiFit.watch(self, _refit)

func _clear_panel() -> void:
	for c in _panel.get_children():
		c.queue_free()


func _menu_btn(text: String, cb: Callable, big := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 62 if big else 52)
	b.add_theme_font_size_override("font_size", 19 if big else 16)
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/textures/ui/button9.png")
	sb.texture_margin_left = 14
	sb.texture_margin_right = 14
	sb.texture_margin_top = 14
	sb.texture_margin_bottom = 14
	b.add_theme_stylebox_override("normal", sb)
	var sh := StyleBoxTexture.new()
	sh.texture = load("res://assets/textures/ui/button9_hot.png")
	sh.texture_margin_left = 14
	sh.texture_margin_right = 14
	sh.texture_margin_top = 14
	sh.texture_margin_bottom = 14
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.pressed.connect(cb)
	_panel.add_child(b)
	return b


func _build_main() -> void:
	_clear_panel()
	_menu_btn("NEW GAME", func():
		AudioDirector.sfx("ui_confirm", 0.25)
		Game.new_game(), true)
	var any_save := false
	for slot in 3:
		if SaveSystem.has_save(slot):
			any_save = true
	var cb := _menu_btn("CONTINUE", func(): _build_continue(), true)
	cb.disabled = not any_save
	if not any_save:
		cb.text = "CONTINUE (no saves)"
	_menu_btn("SETTINGS", func(): _build_settings())
	_menu_btn("CREDITS", func(): _build_credits())
	var q := Label.new()
	q.text = "Tap a slot to load. Autosave writes to Slot 1."
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_theme_font_size_override("font_size", 12)
	q.add_theme_color_override("font_color", Color(0.55, 0.53, 0.48))
	_panel.add_child(q)


func _build_continue() -> void:
	_clear_panel()
	for slot in 3:
		var meta := SaveSystem.meta(slot)
		var label := "SLOT %d — %s" % [slot + 1, meta.get("label", "empty")] if not meta.is_empty() else "SLOT %d — empty" % (slot + 1)
		var b := _menu_btn(label, func():
			AudioDirector.sfx("ui_confirm", 0.2)
			Game.continue_game(slot))
		b.disabled = meta.is_empty()
	_menu_btn("BACK", func(): _build_main())


func _build_settings() -> void:
	_clear_panel()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 380)
	_panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)
	for row in [["master", "Master volume"], ["music", "Music"], ["sfx", "Effects"], ["vox", "Voice"]]:
		vb.add_child(_slider(row[0], row[1], 0.0, 1.0, 0.05))
	vb.add_child(_slider("sensitivity", "Look sensitivity", 0.3, 2.5, 0.1))
	vb.add_child(_slider("touch_scale", "Touch controls size", 0.7, 1.5, 0.05))
	for row in [["subtitles", "Subtitles"], ["shake", "Camera shake"], ["invert_y", "Invert look Y"]]:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = row[1]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 15)
		h.add_child(l)
		var cb := CheckButton.new()
		cb.button_pressed = bool(Game.settings.get(row[0], true))
		cb.toggled.connect(func(on):
			Game.settings[row[0]] = on
			Game.save_settings())
		h.add_child(cb)
		vb.add_child(h)
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "Quality"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 15)
	h.add_child(l)
	var ob := OptionButton.new()
	ob.add_item("Low")
	ob.add_item("Medium")
	ob.add_item("High")
	ob.selected = int(Game.settings.get("quality", 1))
	ob.item_selected.connect(func(i):
		Game.settings["quality"] = i
		Game.save_settings()
		Bus.settings_changed.emit())
	h.add_child(ob)
	vb.add_child(h)
	_menu_btn("BACK", func(): _build_main())


func _slider(key: String, label: String, mn: float, mx: float, step: float) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	l.add_theme_font_size_override("font_size", 14)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Game.settings.get(key, 0.8))
	s.custom_minimum_size = Vector2(220, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v):
		Game.settings[key] = v
		Game.save_settings())
	h.add_child(s)
	return h


func _build_credits() -> void:
	_clear_panel()
	var t := Label.new()
	t.text = """LEVERAGE — v0.9.0
a D'Youngs Games story

Design, code, art, audio, writing:
generated in-house for this project.

Engine: Godot 4.7 (Mobile renderer)
Target device: iPhone via XOGOT
Fonts: DejaVu (Bitstream Vera / Arev license)
All textures, music, SFX and voice barks:
original procedural assets (see ASSET_REGISTER.md).

Everyone has leverage on you."""
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(440, 340)
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", Color(0.8, 0.78, 0.72))
	_panel.add_child(t)
	_menu_btn("BACK", func(): _build_main())


func _refit() -> void:
	UiFit.refit_tree(self)
