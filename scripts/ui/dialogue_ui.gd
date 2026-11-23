extends CanvasLayer
## DialogueUI — conversation boxes, typewriter lines, voiced barks and choice
## menus. Single instance (autoload). Mission stages and NPC interactions open
## trees through here; choices return via Bus.dialogue_choice.

var active := false
var _tree: Dictionary = {}
var _node_id: String = ""
var _chars := 0.0
var _full := ""
var _spk := ""
var _voice := ""
var _choice_cb := Callable()
var _choice_opts: Array = []

var panel: Panel
var portrait: TextureRect
var name_lbl: Label
var text_lbl: RichTextLabel
var hint_lbl: Label
var choice_box: VBoxContainer
var root: Control


func _ready() -> void:
	layer = 40
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# dim
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	root.add_child(dim)
	_dim = dim
	# panel
	panel = Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -190
	panel.offset_bottom = -30
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/textures/ui/panel9.png")
	sb.texture_margin_left = 14
	sb.texture_margin_right = 14
	sb.texture_margin_top = 14
	sb.texture_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	root.add_child(panel)
	portrait = TextureRect.new()
	portrait.position = Vector2(14, 14)
	portrait.size = Vector2(120, 120)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	panel.add_child(portrait)
	name_lbl = Label.new()
	name_lbl.position = Vector2(148, 16)
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	panel.add_child(name_lbl)
	text_lbl = RichTextLabel.new()
	text_lbl.position = Vector2(148, 44)
	text_lbl.size = Vector2(452, 110)
	text_lbl.bbcode_enabled = false
	text_lbl.scroll_active = false
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.add_theme_font_size_override("normal_font_size", 17)
	panel.add_child(text_lbl)
	hint_lbl = Label.new()
	hint_lbl.text = "TAP TO CONTINUE"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_lbl.position = Vector2(400, 132)
	hint_lbl.size = Vector2(200, 20)
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	panel.add_child(hint_lbl)
	choice_box = VBoxContainer.new()
	choice_box.anchor_left = 0.5
	choice_box.anchor_right = 0.5
	choice_box.anchor_top = 0.5
	choice_box.anchor_bottom = 0.5
	choice_box.offset_left = -220
	choice_box.offset_right = 220
	choice_box.offset_top = -140
	choice_box.offset_bottom = 140
	choice_box.add_theme_constant_override("separation", 10)
	choice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	choice_box.visible = false
	root.add_child(choice_box)
	# tap area (invisible full-screen button when dialogue open)
	_tap = Button.new()
	_tap.flat = true
	_tap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap.visible = false
	_tap.pressed.connect(_advance)
	root.add_child(_tap)
	Bus.dialogue_line.connect(_on_line)


var _dim: ColorRect
var _tap: Button


func is_open() -> bool:
	return active


func start_tree(tree_id: String) -> void:
	var t := Db.dialogue_tree(tree_id)
	if t.is_empty():
		push_warning("DialogueUI: missing tree " + tree_id)
		return
	_tree = t
	active = true
	_dim.visible = true
	panel.visible = true
	_tap.visible = true
	choice_box.visible = false
	Game.cutscene_active = true
	Bus.dialogue_started.emit(tree_id)
	_show_node(t.get("start", "a"))


func start_choices(prompt: String, options: Array, cb: Callable) -> void:
	# options: [{label, ...}] — mission/UI-driven choice
	active = true
	_choice_opts = options
	_choice_cb = cb
	_dim.visible = true
	panel.visible = true
	choice_box.visible = true
	Game.cutscene_active = true
	name_lbl.text = "DECISION"
	portrait.texture = null
	_full = prompt
	_chars = 0.0
	text_lbl.text = prompt
	hint_lbl.text = ""
	_build_choice_buttons(_labels(options))
	AudioDirector.sfx("shop_bell", 0.15)


func _labels(options: Array) -> Array:
	var out := []
	for o in options:
		out.append(o.get("label", "..."))
	return out


func _build_choice_buttons(labels: Array) -> void:
	for c in choice_box.get_children():
		c.queue_free()
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.custom_minimum_size = Vector2(440, 52)
		var sb := StyleBoxTexture.new()
		sb.texture = load("res://assets/textures/ui/button9.png")
		sb.texture_margin_left = 12
		sb.texture_margin_right = 12
		sb.texture_margin_top = 12
		sb.texture_margin_bottom = 12
		b.add_theme_stylebox_override("normal", sb)
		var sbh := StyleBoxTexture.new()
		sbh.texture = load("res://assets/textures/ui/button9_hot.png")
		sbh.margin_left = 12
		sbh.margin_right = 12
		sbh.margin_top = 12
		sbh.margin_bottom = 12
		b.add_theme_stylebox_override("hover", sbh)
		b.add_theme_stylebox_override("pressed", sbh)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_pick.bind(i))
		choice_box.add_child(b)


func _pick(i: int) -> void:
	if _choice_opts.size() > i:
		var opt = _choice_opts[i]
		var cb := _choice_cb
		_choice_cb = Callable()
		_choice_opts = []
		close()
		if cb.is_valid():
			cb.call(opt)
		else:
			Bus.dialogue_choice.emit([opt])


func _show_node(nid: String) -> void:
	var nodes: Dictionary = _tree.get("nodes", {})
	var n: Dictionary = nodes.get(nid, {})
	if n.is_empty():
		# tree exhausted
		close()
		return
	_node_id = nid
	_spk = n.get("spk", "")
	var c := Db.character(_spk) if _spk != "" else {}
	name_lbl.text = c.get("name", _spk.to_upper()) if not c.is_empty() else _spk.to_upper()
	if c.has("appearance") and int(c["appearance"].get("face", -1)) >= 0:
		var fi := int(c["appearance"]["face"])
		portrait.texture = load("res://assets/textures/faces/face_%02d.png" % fi)
	else:
		portrait.texture = null
	_full = n.get("text", "")
	_chars = 0.0
	text_lbl.text = ""
	hint_lbl.text = ""
	_voice = c.get("voice", "ped_m") if not c.is_empty() else "ped_m"
	AudioDirector.speak(_voice, _full)
	AudioDirector.sfx("ui_click", 0.05)
	# node-level choices
	if n.has("opts"):
		choice_box.visible = true
		_tap.visible = false
		_choice_opts = n["opts"]
		_choice_cb = func(opt):
			_apply_node_effects(opt)
			if opt.has("next"):
				_show_node(opt["next"])
			else:
				close()
		_build_choice_buttons(_labels(_choice_opts))
	else:
		choice_box.visible = false
		_tap.visible = true


func _apply_node_effects(opt: Dictionary) -> void:
	var e: Dictionary = opt.get("effects", {})
	if e.has("money"):
		WorldState.add_money(int(e["money"]))
	if e.has("faction"):
		WorldState.add_faction_rep(e["faction"][0], float(e["faction"][1]))
	if e.has("rel"):
		WorldState.add_relationship(e["rel"][0], float(e["rel"][1]))
	if e.has("flag"):
		WorldState.set_flag(e["flag"], true)
	if e.has("wanted"):
		WorldState.set_wanted(WorldState.wanted + int(e["wanted"]))
	if e.has("item"):
		WorldState.add_item(e["item"], 1)


func _advance() -> void:
	if not active or choice_box.visible:
		return
	if _chars < _full.length():
		_chars = _full.length()
		text_lbl.text = _full
		return
	var nodes: Dictionary = _tree.get("nodes", {})
	var n: Dictionary = nodes.get(_node_id, {})
	var nxt = n.get("next", null)
	if nxt == null:
		close()
	else:
		_show_node(nxt)


func _process(delta: float) -> void:
	if not active or choice_box.visible:
		return
	_chars += delta * 34.0
	var shown := _full.substr(0, int(_chars))
	if shown != text_lbl.text:
		text_lbl.text = shown
		if int(_chars) % 3 == 0:
			AudioDirector.sfx("phone_msg", 0.02)
	if _chars >= _full.length():
		hint_lbl.text = "TAP TO CONTINUE"


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()


func _on_line(_speaker: String, text: String, voice: String) -> void:
	# ambient bark (not a full tree): show brief subtitle toast
	if active:
		return
	_bark_show(_speaker_label(_speaker), text, voice)


var _bark_lbl: Label


func _speaker_label(spk: String) -> String:
	var c := Db.character(spk)
	return c.get("name", spk) if not c.is_empty() else spk


func _bark_show(who: String, text: String, voice: String) -> void:
	if _bark_lbl == null:
		_bark_lbl = Label.new()
		_bark_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bark_lbl.anchor_left = 0.5
		_bark_lbl.anchor_right = 0.5
		_bark_lbl.anchor_top = 1.0
		_bark_lbl.anchor_bottom = 1.0
		_bark_lbl.offset_left = -300
		_bark_lbl.offset_right = 300
		_bark_lbl.offset_top = -150
		_bark_lbl.offset_bottom = -110
		_bark_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bark_lbl.add_theme_font_size_override("font_size", 15)
		_bark_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		_bark_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_bark_lbl.add_theme_constant_override("shadow_offset_x", 1)
		_bark_lbl.add_theme_constant_override("shadow_offset_y", 1)
		root.add_child(_bark_lbl)
	_bark_lbl.text = "%s: \"%s\"" % [who, text]
	_bark_t = 3.0
	AudioDirector.speak(voice, text)


var _bark_t := 0.0


func _physics_process(delta: float) -> void:
	if _bark_t > 0.0:
		_bark_t -= delta
		if _bark_lbl:
			_bark_lbl.modulate.a = clampf(_bark_t, 0.0, 1.0)
		if _bark_t <= 0.0 and _bark_lbl:
			_bark_lbl.text = ""


func close() -> void:
	active = false
	_dim.visible = false
	panel.visible = false
	_tap.visible = false
	choice_box.visible = false
	if not Cutscene.playing:
		Game.cutscene_active = false
	Bus.dialogue_ended.emit()
