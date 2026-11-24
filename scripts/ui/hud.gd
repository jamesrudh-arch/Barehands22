extends CanvasLayer
## HUD — gameplay interface + iPhone touch controls. One authoritative layer:
## vitals, money, wanted stars, clock/weather/district, minimap, objective,
## notifications, interact prompts, the X/Y/A/B combat pad (exact mapping:
## X=PUNCH, Y=HEAVY, A=KICK, B=DODGE/INTERACT), virtual stick, camera drag,
## contextual buttons (sprint/crouch/block/aim/fire/reload/lock/style/enter
## vehicle/brake/handbrake) and the pause menu.

var enabled := false

var _root: Control
var _stick_zone: Control
var _stick_base: Control
var _stick_knob: Control
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _cam_id := -1
var _cam_last := Vector2.ZERO

var _held: Dictionary = {}           # action -> true
var _buttons: Dictionary = {}        # name -> Button
var _hp_bar: ProgressBar
var _xp_bar: ProgressBar
var _focus_bar: ProgressBar
var _focus_vignette: ColorRect
var _lvl_lbl: Label
var _st_bar: ProgressBar
var _ar_bar: ProgressBar
var _money_lbl: Label
var _stars_lbl: Label
var _phone_lbl: Label
var _phone_t := 0.0
var _clock_lbl: Label
var _district_lbl: Label
var _objective_lbl: Label
var _mission_lbl: Label
var _prompt_lbl: Label
var _ammo_lbl: Label
var _style_lbl: Label
var _speed_lbl: Label
var _minimap: Control
var _toasts: VBoxContainer
var _toast_q: Array = []
var _pause_menu: Control
var _crosshair: TextureRect
var _lock_marker: Control

const STICK_R := 62.0
const BTN := 74.0

# action-button table: name -> [action, label, anchor]
const PAD := [
	["btn_x", "punch", "X", "pad_x"],
	["btn_y", "heavy_attack", "Y", "pad_y"],
	["btn_a", "kick", "A", "pad_a"],
	["btn_b", "dodge", "B", "pad_b"],
]


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top()
	_build_bars()
	_build_minimap()
	_build_objective()
	_build_toasts()
	_build_touch()
	_build_pause()
	_fit_centers()
	UiFit.watch(self, _on_vp_resized)
	Bus.settings_changed.connect(_on_vp_resized)   # touch size slider rebuilds the pads
	_root.visible = false
	Bus.notification.connect(_notify)
	Bus.interaction_available.connect(_prompt_show)
	Bus.interaction_cleared.connect(func(): _prompt_lbl.text = "")
	Bus.prompt_hint.connect(_on_prompt_hint)
	Bus.money_changed.connect(func(m): _money_lbl.text = "%d CR" % m)
	Bus.wanted_changed.connect(func(w): _stars_lbl.text = "*".repeat(w))
	Bus.ammo_changed.connect(_on_ammo)
	Bus.combat_style_changed.connect(func(s): _style_lbl.text = Db.style(s).get("name", s).to_upper())
	Bus.vehicle_entered.connect(func(_t): _update_vehicle_ui(true))
	Bus.vehicle_exited.connect(func(): _update_vehicle_ui(false))
	Bus.game_state_changed.connect(_on_state)
	CallManager.state_changed.connect(func(_s): _refresh_phone_badge())
	CallManager.new_message.connect(func(_t): _refresh_phone_badge())


func _on_state(s: StringName) -> void:
	enabled = s == "playing" or s == "paused" or s == "cinematic"
	_root.visible = enabled
	if s == "paused":
		_pause_menu.visible = true
	else:
		_pause_menu.visible = false


# ------------------------------------------------------------------- build --
func _lbl(size: int, col: Color = Color(0.92, 0.9, 0.85)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, w: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, 9)
	b.size = Vector2(w, 9)
	b.show_percentage = false
	b.max_value = 100.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	b.add_theme_stylebox_override("background", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _refresh_phone_badge() -> void:
	if _phone_lbl == null:
		return
	if CallManager.state == 1:
		var nm: String = Db.character(CallManager.current.get("char", "")).get("short", "Unknown")
		_phone_lbl.text = "☎ %s CALLING — open PHONE" % nm.to_upper()
		_phone_lbl.modulate = Color(1, 0.85, 0.4)
	elif CallManager.state == 2:
		_phone_lbl.text = "☎ IN CALL"
		_phone_lbl.modulate = Color(0.6, 1, 0.8)
	else:
		var u: int = CallManager.unread_count()
		_phone_lbl.text = "✉ %d UNREAD" % u if u > 0 else ""
		_phone_lbl.modulate = Color(0.95, 0.72, 0.25)


func _build_top() -> void:
	_money_lbl = _lbl(20, Color(0.6, 0.9, 0.6))
	_money_lbl.anchor_left = 1.0
	_money_lbl.anchor_right = 1.0
	_money_lbl.offset_left = -220
	_money_lbl.offset_right = -16
	_money_lbl.offset_top = 12
	_money_lbl.offset_bottom = 40
	_money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_money_lbl)
	_stars_lbl = _lbl(20, Color(0.95, 0.3, 0.25))
	_stars_lbl.anchor_left = 1.0
	_stars_lbl.anchor_right = 1.0
	_stars_lbl.offset_left = -220
	_stars_lbl.offset_right = -16
	_stars_lbl.offset_top = 38
	_stars_lbl.offset_bottom = 64
	_stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_stars_lbl)
	_clock_lbl = _lbl(14, Color(0.75, 0.73, 0.68))
	_clock_lbl.anchor_left = 0.5
	_clock_lbl.anchor_right = 0.5
	_clock_lbl.offset_left = -120
	_clock_lbl.offset_right = 120
	_clock_lbl.offset_top = 8
	_clock_lbl.offset_bottom = 28
	_clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_clock_lbl)
	# phone status badge: ringing call / unread messages
	_phone_lbl = _lbl(13, Color(0.95, 0.72, 0.25))
	_phone_lbl.anchor_left = 0.5
	_phone_lbl.anchor_right = 0.5
	_phone_lbl.offset_left = -140
	_phone_lbl.offset_right = 140
	_phone_lbl.offset_top = 30
	_phone_lbl.offset_bottom = 48
	_phone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_lbl.text = ""
	_root.add_child(_phone_lbl)
	_district_lbl = _lbl(16, Color(0.95, 0.72, 0.25))
	_district_lbl.anchor_left = 0.5
	_district_lbl.anchor_right = 0.5
	_district_lbl.offset_left = -160
	_district_lbl.offset_right = 160
	_district_lbl.offset_top = 26
	_district_lbl.offset_bottom = 48
	_district_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_district_lbl)
	# GUARD-POSTURE BAR: floats under the district name whenever you've
	# locked a trained fighter. Chip it with pressure; break it and punish.
	_posture_bar = _bar(Color(0.95, 0.45, 0.2), 220.0)
	_posture_bar.anchor_left = 0.5
	_posture_bar.anchor_right = 0.5
	_posture_bar.offset_left = -110
	_posture_bar.offset_right = 110
	_posture_bar.offset_top = 50
	_posture_bar.offset_bottom = 58
	_posture_bar.custom_minimum_size = Vector2(220, 8)
	_posture_bar.visible = false
	_root.add_child(_posture_bar)
	# STREET REP chip: the block's verdict on you, always in view
	_street_lbl = _lbl(13, Color(0.7, 0.85, 0.75))
	_street_lbl.anchor_left = 0.5
	_street_lbl.anchor_right = 0.5
	_street_lbl.offset_left = -160
	_street_lbl.offset_right = 160
	_street_lbl.offset_top = 62
	_street_lbl.offset_bottom = 80
	_street_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_street_lbl)
	_ammo_lbl = _lbl(17, Color(0.9, 0.85, 0.7))
	_ammo_lbl.anchor_left = 1.0
	_ammo_lbl.anchor_right = 1.0
	_ammo_lbl.offset_left = -200
	_ammo_lbl.offset_right = -16
	_ammo_lbl.offset_top = -260
	_ammo_lbl.offset_bottom = -236
	_ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_lbl.visible = false
	_root.add_child(_ammo_lbl)
	_style_lbl = _lbl(13, Color(0.7, 0.75, 0.9))
	_style_lbl.anchor_left = 1.0
	_style_lbl.anchor_right = 1.0
	_style_lbl.offset_left = -200
	_style_lbl.offset_right = -16
	_style_lbl.offset_top = -284
	_style_lbl.offset_bottom = -264
	_style_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_style_lbl)
	_speed_lbl = _lbl(22, Color(0.85, 0.85, 0.8))
	_speed_lbl.anchor_left = 1.0
	_speed_lbl.anchor_right = 1.0
	_speed_lbl.offset_left = -240
	_speed_lbl.offset_right = -150
	_speed_lbl.offset_top = -200
	_speed_lbl.offset_bottom = -170
	_speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_lbl.visible = false
	_root.add_child(_speed_lbl)
	# crosshair (aim mode)
	_crosshair = TextureRect.new()
	_crosshair.texture = load("res://assets/textures/ui/crosshair.png")
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -16
	_crosshair.offset_right = 16
	_crosshair.offset_top = -16
	_crosshair.offset_bottom = 16
	_crosshair.visible = false
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)
	# lock-on marker
	_lock_marker = Control.new()
	_lock_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_marker.visible = false
	_lock_marker.draw.connect(_draw_lock)
	_root.add_child(_lock_marker)


func _build_bars() -> void:
	var vb := VBoxContainer.new()
	vb.position = Vector2(16, 64)
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vb)
	_hp_bar = _bar(Color(0.85, 0.22, 0.18), 190.0)
	vb.add_child(_hp_bar)
	_ar_bar = _bar(Color(0.35, 0.55, 0.85), 190.0)
	vb.add_child(_ar_bar)
	_st_bar = _bar(Color(0.85, 0.75, 0.3), 190.0)
	vb.add_child(_st_bar)
	_xp_bar = _bar(Color(0.23, 0.91, 0.69), 190.0)
	vb.add_child(_xp_bar)
	_focus_bar = _bar(Color(0.45, 0.75, 1.0), 190.0)
	_focus_bar.visible = false
	vb.add_child(_focus_bar)
	# bullet-time vignette: cold blue edges while FOCUS is active
	_focus_vignette = ColorRect.new()
	_focus_vignette.color = Color(0.35, 0.55, 0.95, 0.10)
	_focus_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_focus_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# HURT VIGNETTE: at low HP the edges of the screen throb red on a
	# heartbeat rhythm — the body failing, not a UI meter
	_hurt_vignette = ColorRect.new()
	_hurt_vignette.color = Color(0.55, 0.05, 0.05, 0.0)
	_hurt_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_vignette.visible = false
	_root.add_child(_hurt_vignette)
	# DAMAGE DIRECTION RING: red arcs flash at the screen edge toward
	# whoever just hit you (FPS-standard spatial read, drawn in 2D)
	_dmg_ring = Control.new()
	_dmg_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dmg_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_ring.draw.connect(_draw_dmg_ring)
	_root.add_child(_dmg_ring)
	Bus.player_damaged.connect(_on_player_damaged)
	_focus_vignette.visible = false
	_root.add_child(_focus_vignette)
	_lvl_lbl = Label.new()
	_lvl_lbl.add_theme_font_size_override("font_size", 12)
	_lvl_lbl.add_theme_color_override("font_color", Color(0.23, 0.91, 0.69))
	_lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_lvl_lbl)


func _build_minimap() -> void:
	_minimap = Control.new()
	_minimap.position = Vector2(14, 170)
	_minimap.size = Vector2(170, 170)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.clip_contents = true
	_minimap.draw.connect(_draw_minimap)
	_root.add_child(_minimap)
	var frame := TextureRect.new()
	frame.texture = load("res://assets/textures/ui/minimap_frame.png")
	frame.position = Vector2(14, 170)
	frame.size = Vector2(170, 170)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)


func _build_objective() -> void:
	_mission_lbl = _lbl(14, Color(0.95, 0.72, 0.25))
	_mission_lbl.position = Vector2(16, 350)
	_root.add_child(_mission_lbl)
	_objective_lbl = _lbl(14, Color(0.88, 0.86, 0.8))
	_objective_lbl.position = Vector2(16, 370)
	_objective_lbl.custom_minimum_size = Vector2(340, 40)
	_objective_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_objective_lbl)
	_prompt_lbl = _lbl(17, Color(0.95, 0.95, 0.9))
	_prompt_lbl.anchor_left = 0.5
	_prompt_lbl.anchor_right = 0.5
	_prompt_lbl.anchor_top = 1.0
	_prompt_lbl.anchor_bottom = 1.0
	_prompt_lbl.offset_left = -260
	_prompt_lbl.offset_right = 260
	_prompt_lbl.offset_top = -268
	_prompt_lbl.offset_bottom = -240
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_prompt_lbl)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.anchor_top = 0.0
	_toasts.offset_left = -260
	_toasts.offset_right = 260
	_toasts.offset_top = 96
	_toasts.offset_bottom = 240
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 4)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


# ------------------------------------------------------------------ touch --
func _build_touch() -> void:
	# full-screen touch catcher (below buttons)
	_stick_zone = Control.new()
	_stick_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	_stick_zone.gui_input.connect(_on_touch)
	_root.add_child(_stick_zone)
	_stick_base = Control.new()
	var ts: float = float(Game.settings.get("touch_scale", 1.0))
	_stick_base.size = Vector2(STICK_R * 2.6 * ts, STICK_R * 2.6 * ts)
	_stick_base.visible = false
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.draw.connect(_draw_stick_base)
	_root.add_child(_stick_base)
	_stick_knob = Control.new()
	_stick_knob.size = Vector2(STICK_R * ts, STICK_R * ts)
	_stick_knob.visible = false
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.draw.connect(_draw_stick_knob)
	_root.add_child(_stick_knob)
	# movement pad: X/Y/A/B exact mapping
	var vp := get_viewport().get_visible_rect().size
	var cx := vp.x - 118.0
	var cy := vp.y - 118.0
	var pad_pos := {
		"pad_a": Vector2(cx, cy),                     # bottom-right: A KICK
		"pad_b": Vector2(cx - BTN - 14, cy - 8),      # left of A: B DODGE/INTERACT
		"pad_x": Vector2(cx - 8, cy - BTN - 14),      # above A: X PUNCH
		"pad_y": Vector2(cx - BTN - 22, cy - BTN - 22),  # above B: Y HEAVY
	}
	for row in PAD:
		var b := _touch_btn(row[1], row[2], pad_pos[row[3]], Color(0.12, 0.12, 0.14, 0.72))
		_buttons[row[0]] = b
	# utility buttons left column / top
	_buttons["sprint"] = _touch_btn("sprint", "RUN", Vector2(vp.x - 250, vp.y - 86), Color(0.1, 0.14, 0.1, 0.7), 58.0)
	_buttons["crouch"] = _touch_btn("crouch", "CRCH", Vector2(vp.x - 250, vp.y - 156), Color(0.1, 0.12, 0.16, 0.7), 58.0)
	_buttons["jump"] = _touch_btn("jump", "JMP", Vector2(250, vp.y - 170), Color(0.1, 0.13, 0.12, 0.65), 56.0)
	_buttons["block"] = _touch_btn("block", "BLK", Vector2(vp.x - 320, vp.y - 120), Color(0.14, 0.12, 0.1, 0.7), 58.0)
	_buttons["lock_on"] = _touch_btn("lock_on", "LOCK", Vector2(vp.x - 320, vp.y - 190), Color(0.12, 0.1, 0.14, 0.7), 58.0)
	_buttons["style_next"] = _touch_btn("style_next", "STY", Vector2(vp.x - 320, vp.y - 260), Color(0.1, 0.12, 0.14, 0.7), 52.0)
	_buttons["vehicle_enter"] = _touch_btn("vehicle_enter", "CAR", Vector2(vp.x - 118, vp.y - 240), Color(0.1, 0.14, 0.12, 0.75), 62.0)
	_buttons["vehicle_brake"] = _touch_btn("vehicle_brake", "BRK", Vector2(vp.x - 250, vp.y - 118), Color(0.16, 0.1, 0.1, 0.75), 62.0)
	_buttons["horn"] = _touch_btn("horn", "HORN", Vector2(vp.x - 320, vp.y - 90), Color(0.12, 0.12, 0.1, 0.7), 52.0)
	_buttons["radio"] = _sys_btn("radio", "RADIO", Vector2(vp.x - 250, 70), func():
		var cl := _city_life()
		if cl:
			cl.radio_cycle())
	# gun buttons (visible when gun equipped)
	_buttons["aim"] = _touch_btn("aim", "AIM", Vector2(vp.x - 390, vp.y - 150), Color(0.1, 0.12, 0.16, 0.75), 62.0)
	_buttons["fire"] = _touch_btn("fire", "FIRE", Vector2(vp.x - 390, vp.y - 230), Color(0.18, 0.1, 0.08, 0.8), 70.0)
	_buttons["reload"] = _touch_btn("reload", "RLD", Vector2(vp.x - 320, vp.y - 320), Color(0.12, 0.12, 0.12, 0.7), 52.0)
	_buttons["focus"] = _touch_btn("focus", "FOCUS", Vector2(vp.x - 390, vp.y - 320), Color(0.1, 0.14, 0.18, 0.75), 56.0)
	# top-right system buttons
	_buttons["phone"] = _sys_btn("phone", "PHONE", Vector2(vp.x - 130, 70), func(): Bus.phone_opened.emit() if not PhoneUI.open else PhoneUI.close_phone())
	_buttons["map"] = _sys_btn("map", "MAP", Vector2(vp.x - 130, 128), func():
		if not PhoneUI.open:
			PhoneUI.open_phone()
			PhoneUI._show_map())
	_buttons["pause"] = _sys_btn("pause", "II", Vector2(vp.x - 60, 70), func(): Game.pause_toggle())
	_update_visibility()


func _touch_btn(action: String, label: String, pos: Vector2, col: Color, size: float = BTN) -> Button:
	size *= float(Game.settings.get("touch_scale", 1.0))
	var b := Button.new()
	b.text = label
	b.position = pos - Vector2(size * 0.5, size * 0.5)
	b.size = Vector2(size, size)
	b.add_theme_font_size_override("font_size", int(size * 0.26))
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(size * 0.5)
	sb.corner_radius_top_right = int(size * 0.5)
	sb.corner_radius_bottom_left = int(size * 0.5)
	sb.corner_radius_bottom_right = int(size * 0.5)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(0.95, 0.72, 0.25, 0.5)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate()
	sh.bg_color = Color(col.r + 0.15, col.g + 0.15, col.b + 0.12, 0.9)
	sh.border_color = Color(0.95, 0.72, 0.25, 0.95)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.button_mask = 1
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.set_meta("action", action)
	b.button_down.connect(_press.bind(action))
	b.button_up.connect(_release.bind(action))
	_root.add_child(b)
	return b


func _sys_btn(name: String, label: String, pos: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.position = pos
	b.size = Vector2(110 if label.length() > 2 else 46, 44)
	b.add_theme_font_size_override("font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.72)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_bottom = 2
	sb.border_color = Color(0.95, 0.72, 0.25, 0.4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(cb)
	_root.add_child(b)
	_buttons[name] = b
	return b


func _press(action: String) -> void:
	_held[action] = true
	if not Input.is_action_pressed(action):
		Input.action_press(action)
	AudioDirector.sfx("ui_click", 0.02)


func _release(action: String) -> void:
	_held.erase(action)
	if Input.is_action_pressed(action):
		Input.action_release(action)


func _on_touch(event: InputEvent) -> void:
	if not enabled or Game.cutscene_active or DialogueUI.is_open() or PhoneUI.open or ShopUI.open:
		return
	var ev := event
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touch_down(ev.index, ev.position)
		else:
			_touch_up(ev.index)
	elif ev is InputEventScreenDrag:
		_touch_drag(ev.index, ev.position)
	elif ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_touch_down(999, ev.position)
			else:
				_touch_up(999)
	elif ev is InputEventMouseMotion and _cam_id == 999:
		_touch_drag(999, ev.position)


func _touch_down(index: int, pos: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	if _stick_id == -1 and pos.x < vp.x * 0.45 and pos.y > vp.y * 0.25:
		_stick_id = index
		_stick_origin = pos
		_stick_base.position = pos - _stick_base.size * 0.5
		_stick_knob.position = pos - _stick_knob.size * 0.5
		_stick_base.visible = true
		_stick_knob.visible = true
	elif _cam_id == -1 and pos.x > vp.x * 0.3:
		_cam_id = index
		_cam_last = pos


func _touch_drag(index: int, pos: Vector2) -> void:
	if index == _stick_id:
		var d := pos - _stick_origin
		var l := d.length()
		if l > STICK_R:
			d = d / l * STICK_R
		_stick_knob.position = _stick_origin + d - _stick_knob.size * 0.5
		var player := _player()
		if player:
			player.touch_move = Vector2(d.x / STICK_R, d.y / STICK_R)
	elif index == _cam_id:
		var d := pos - _cam_last
		_cam_last = pos
		var player := _player()
		if player:
			player.look_input(d * Game.settings.get("sensitivity", 1.0))


func _touch_up(index: int) -> void:
	if index == _stick_id:
		_stick_id = -1
		_stick_base.visible = false
		_stick_knob.visible = false
		var player := _player()
		if player:
			player.touch_move = Vector2.ZERO
	elif index == _cam_id:
		_cam_id = -1


func _draw_stick_base() -> void:
	_stick_base.draw_circle(_stick_base.size * 0.5, STICK_R * 1.2, Color(1, 1, 1, 0.06))
	_stick_base.draw_arc(_stick_base.size * 0.5, STICK_R * 1.2, 0, TAU, 40, Color(0.95, 0.72, 0.25, 0.25), 2.0)


func _draw_stick_knob() -> void:
	_stick_knob.draw_circle(_stick_knob.size * 0.5, STICK_R * 0.5, Color(0.95, 0.72, 0.25, 0.35))


# ----------------------------------------------------------------- updates --
func _process(delta: float) -> void:
	if not enabled:
		return
	var player := _player()
	if player == null:
		return
	# vitals
	if player.combat:
		_hp_bar.value = player.combat.hp / player.combat.max_hp * 100.0
		_st_bar.value = player.combat.stamina / player.combat.max_stamina * 100.0
		_ar_bar.value = clampf(player.combat.armor_prot * 100.0, 0.0, 100.0)
	# focus meter (visible while a gun is out)
	if _focus_bar != null:
		var gun_out: bool = player.weapons != null and player.weapons.is_gun()
		_focus_bar.visible = gun_out
		if gun_out:
			_focus_bar.value = player.focus
			_focus_bar.modulate = Color(1, 1, 1) if not player.focus_active else Color(1.4, 1.5, 2.0)
	if _focus_vignette != null:
		var fa: bool = player.get("focus_active") == true
		_focus_vignette.visible = fa
		if fa:
			_focus_vignette.color.a = 0.08 + 0.05 * sin(Time.get_ticks_msec() * 0.004)
	# low-HP heartbeat vignette
	if _hurt_vignette != null and player.combat != null and not player.combat.dead:
		var hpfrac: float = player.combat.hp / maxf(1.0, player.combat.max_hp)
		if hpfrac < 0.3 and not Game.cutscene_active:
			_hurt_vignette.visible = true
			var beat := absf(sin(_heart_t * 4.2)) * (1.0 - hpfrac / 0.3)
			_hurt_vignette.color.a = 0.04 + 0.10 * beat
			_heart_t += delta
			# thumping heart, twice as loud as the vignette is red
			if fmod(_heart_t, 0.9) < delta:
				AudioDirector.sfx("land_thud", 0.0, 0.10 + 0.1 * beat)
		else:
			_hurt_vignette.visible = false
			_heart_t = 0.0
	# damage arcs decay (redraw every frame so the last arc's expiry
	# actually clears the ring — no ghost arcs)
	if _dmg_ring != null:
		if not _dmg_arcs.is_empty():
			for a in _dmg_arcs.duplicate():
				a["t"] -= delta * 1.7
				if a["t"] <= 0.0:
					_dmg_arcs.erase(a)
		_dmg_ring.queue_redraw()
	# progression
	if _xp_bar != null:
		_xp_bar.value = float(Progression.xp) / float(Progression.xp_for_next()) * 100.0
		var sid: String = player.combat.style_id if player.combat else "brawler"
		_lvl_lbl.text = "LV %d   XP %d/%d   %s MASTERY %d" % [
			Progression.level, Progression.xp, Progression.xp_for_next(),
			str(Db.style(sid).get("label", sid)).capitalize(), Progression.style_rank(sid)]
	# phone badge pulse while ringing; periodic refresh for unread counts
	_phone_t += delta
	if CallManager.state == 1:
		_phone_lbl.modulate.a = 0.55 + 0.45 * sin(_phone_t * 9.0)
	else:
		_phone_lbl.modulate.a = 1.0
	if fmod(_phone_t, 1.0) < delta:
		_refresh_phone_badge()
	# clock/weather/district
	_clock_lbl.text = "%s  •  %s  •  DAY %d" % [WorldState.hour_of_day_string(), WorldState.weather_name().to_upper(), WorldState.day]
	var d := Db.district(Game.current_district)
	_district_lbl.text = d.get("name", "").to_upper()
	# objective
	var mm := get_node_or_null("/root/MissionManager")
	if mm:
		_mission_lbl.text = mm.mission_title().to_upper()
		_objective_lbl.text = mm.objective_text()
	# speed
	if player.in_vehicle:
		_speed_lbl.text = "%d km/h" % int(player.in_vehicle.speed_kmh())
	# minimap & lock marker
	_minimap.queue_redraw()
	if player.lock_target and is_instance_valid(player.lock_target):
		_lock_marker.visible = true
		_lock_marker.queue_redraw()
		_update_lock_pos(player)
	else:
		_lock_marker.visible = false
	# guard-posture readout on the locked target
	if _posture_bar != null:
		var tc = null
		if player.lock_target != null and is_instance_valid(player.lock_target):
			tc = player.lock_target.get("combat")
		if tc != null and (tc.posture > 1.0 or tc.guard_broken_t > 0.0):
			_posture_bar.visible = true
			_posture_bar.value = clampf(tc.posture / tc.posture_max * 100.0, 0.0, 100.0)
			_posture_bar.modulate = Color(1.6, 0.5, 0.3) if tc.guard_broken_t > 0.0 else Color(1, 1, 1)
		else:
			_posture_bar.visible = false
	# street rep chip
	if _street_lbl != null:
		var sr := WorldState.street_rep()
		if sr >= 8:
			_street_lbl.text = "STREET REP: THE BLOCK HAS YOUR BACK"
			_street_lbl.modulate = Color(0.55, 0.95, 0.7)
		elif sr <= -8:
			_street_lbl.text = "STREET REP: THE BLOCK TALKS ABOUT YOU"
			_street_lbl.modulate = Color(0.95, 0.45, 0.4)
		else:
			_street_lbl.text = ""
	_update_visibility()
	# gun UI
	var has_gun: bool = player.weapons != null and bool(player.weapons.is_gun())
	_ammo_lbl.visible = has_gun
	for bn in ["aim", "fire", "reload", "focus"]:
		_buttons[bn].visible = has_gun and not player.in_vehicle
	_crosshair.visible = has_gun and player.weapons.aim
	# hint expiry (don't clobber a live interaction prompt)
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0:
			_prompt_lbl.text = ""
			_prompt_lbl.modulate = Color(1, 1, 1)
	# toasts
	_tick_toasts(delta)


func _on_player_damaged(dir_world: Vector3, amount: float) -> void:
	# convert the shove direction into a screen-edge angle relative to camera
	var cam := get_viewport().get_camera_3d()
	if cam == null or _dmg_ring == null:
		return
	var to_attacker := -dir_world
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.001:
		to_attacker = -cam.global_transform.basis.z
	var local: Vector3 = cam.global_transform.basis.inverse() * to_attacker.normalized()
	var ang := atan2(local.x, -local.z)          # 0 = screen up, cw
	_dmg_arcs.append({"ang": ang, "t": 1.0, "amt": clampf(amount / 30.0, 0.25, 1.0)})
	if _dmg_arcs.size() > 6:
		_dmg_arcs.pop_front()
	_dmg_ring.queue_redraw()


func _draw_dmg_ring() -> void:
	if _dmg_ring == null or _dmg_arcs.is_empty():
		return
	var sz: Vector2 = _dmg_ring.size
	if sz.x < 10.0:
		sz = _dmg_ring.get_viewport_rect().size
	var c := sz * 0.5
	var rad := minf(sz.x, sz.y) * 0.34
	for a in _dmg_arcs:
		var t: float = a["t"]
		var amt: float = a["amt"]
		var col := Color(0.95, 0.18, 0.14, 0.75 * t)
		var ang: float = a["ang"] - PI * 0.5    # draw_arc: 0 = +x axis
		# arc grows outward slightly as it fades (reads as a shove)
		var r2 := rad + (1.0 - t) * 14.0
		_dmg_ring.draw_arc(c, r2, ang - 0.28 - 0.1 * amt, ang + 0.28 + 0.1 * amt,
			14, col, 5.0 + 5.0 * amt, true)


var _lock_screen := Vector2.ZERO
var _posture_bar: ProgressBar = null
var _street_lbl: Label = null
var _dmg_ring: Control = null          # directional damage arcs
var _dmg_arcs: Array = []              # [{ang, t, amt}]
var _hurt_vignette: ColorRect = null   # low-HP heartbeat pulse
var _heart_t := 0.0


func _update_lock_pos(player: Node) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var t: Node3D = player.lock_target
	var p := cam.unproject_position(t.global_position + Vector3(0, 1.4, 0))
	_lock_screen = p


func _draw_lock() -> void:
	var p := _lock_screen
	var s := 22.0
	var col := Color(0.95, 0.3, 0.25, 0.9)
	_lock_marker.draw_line(p + Vector2(-s, -s), p + Vector2(-s * 0.4, -s), col, 2.5)
	_lock_marker.draw_line(p + Vector2(-s, -s), p + Vector2(-s, -s * 0.4), col, 2.5)
	_lock_marker.draw_line(p + Vector2(s, -s), p + Vector2(s * 0.4, -s), col, 2.5)
	_lock_marker.draw_line(p + Vector2(s, -s), p + Vector2(s, -s * 0.4), col, 2.5)
	_lock_marker.draw_line(p + Vector2(-s, s), p + Vector2(-s * 0.4, s), col, 2.5)
	_lock_marker.draw_line(p + Vector2(-s, s), p + Vector2(-s, s * 0.4), col, 2.5)
	_lock_marker.draw_line(p + Vector2(s, s), p + Vector2(s * 0.4, s), col, 2.5)
	_lock_marker.draw_line(p + Vector2(s, s), p + Vector2(s, s * 0.4), col, 2.5)


func _update_visibility() -> void:
	var player := _player()
	if player == null:
		return
	var driving := player.in_vehicle != null
	_buttons["vehicle_enter"].visible = not driving
	_buttons["vehicle_brake"].visible = driving
	_buttons["horn"].visible = driving
	_buttons["radio"].visible = driving
	_speed_lbl.visible = driving
	for bn in ["btn_x", "btn_y", "btn_a", "block", "lock_on", "sprint", "crouch", "jump"]:
		_buttons[bn].visible = not driving
	_buttons["btn_b"].visible = true  # B stays: interact when out of combat
	_buttons["style_next"].visible = not driving


func _update_vehicle_ui(driving: bool) -> void:
	_update_visibility()


func _on_ammo(mag: int, reserve: int) -> void:
	_ammo_lbl.text = "%d / %d" % [mag, reserve]


func _prompt_show(label: String) -> void:
	_prompt_lbl.text = "[B]  %s" % label


# ---------------------------------------------------------------- minimap --
func _draw_minimap() -> void:
	var player := _player()
	if player == null:
		return
	var pp: Vector3 = player.global_position
	var size := _minimap.size
	var c := size * 0.5
	var scale := 0.22  # world units -> px
	# bg
	_minimap.draw_circle(c, c.x - 2, Color(0.05, 0.06, 0.08, 0.85))
	# roads near player
	for lane in WorldGen.lanes:
		var pts := PackedVector2Array()
		for p in lane:
			var rel := (Vector2(p.x, p.z) - Vector2(pp.x, pp.z)) * scale
			if rel.length() < c.x + 20:
				pts.append(c + rel)
		if pts.size() >= 2:
			pts.append(pts[0])
			_minimap.draw_polyline(pts, Color(0.4, 0.38, 0.34), 2.0)
	# POIs
	for pid in WorldGen.pois:
		var entry: Dictionary = WorldGen.pois[pid]
		var d: Dictionary = entry.get("data", {})
		if not d.has("at"):
			continue
		var rel := (Vector2(d["at"][0], d["at"][1]) - Vector2(pp.x, pp.z)) * scale
		if rel.length() < c.x - 4:
			var col := Color(0.55, 0.8, 0.55)
			match d.get("kind", ""):
				"shop": col = Color(0.95, 0.75, 0.3)
				"home": col = Color(0.5, 0.75, 0.95)
				"law": col = Color(0.55, 0.6, 0.95)
			_minimap.draw_circle(c + rel, 2.5, col)
	# mission target
	var mm := get_node_or_null("/root/MissionManager")
	if mm and mm.active_id != "":
		var tpos: Vector3 = mm.rt.get("pos", Vector3.ZERO)
		if tpos == Vector3.ZERO:
			tpos = mm.rt.get("to", Vector3.ZERO)
		if tpos != Vector3.ZERO:
			var rel := (Vector2(tpos.x, tpos.z) - Vector2(pp.x, pp.z)) * scale
			if rel.length() > c.x - 8:
				rel = rel.normalized() * (c.x - 8)
			_minimap.draw_circle(c + rel, 4.5, Color(0.95, 0.72, 0.25))
	# enemies nearby
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var rel := (Vector2(e.global_position.x, e.global_position.z) - Vector2(pp.x, pp.z)) * scale
		if rel.length() < c.x - 4:
			_minimap.draw_circle(c + rel, 2.5, Color(0.95, 0.3, 0.25))
	# player arrow (north-up)
	var pts := PackedVector2Array([c + Vector2(0, -6), c + Vector2(4.5, 5), c + Vector2(-4.5, 5)])
	_minimap.draw_colored_polygon(pts, Color(0.95, 0.95, 0.9))


# ----------------------------------------------------------------- toasts --
var _hint_t := 0.0


func _on_prompt_hint(text: String) -> void:
	## transient stealth/tutorial hints along the interaction prompt line
	_hint_t = 3.0 if text != "" else 0.0
	if _hint_t > 0.0:
		_prompt_lbl.text = text
		_prompt_lbl.modulate = Color(1.0, 0.85, 0.45)
	else:
		_prompt_lbl.text = ""
		_prompt_lbl.modulate = Color(1, 1, 1)


func _notify(text: String, kind: String) -> void:
	var col := Color(0.9, 0.88, 0.82)
	match kind:
		"error": col = Color(0.95, 0.35, 0.3)
		"warn": col = Color(0.95, 0.7, 0.3)
		"mission": col = Color(0.95, 0.72, 0.25)
		"choice": col = Color(0.6, 0.85, 0.95)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(l)
	_toast_q.append([l, 4.0])
	if _toast_q.size() > 4:
		var old: Array = _toast_q.pop_front()
		old[0].queue_free()


func _tick_toasts(delta: float) -> void:
	for t in _toast_q.duplicate():
		t[1] -= delta
		t[0].modulate.a = clampf(t[1], 0.0, 1.0)
		if t[1] <= 0.0:
			t[0].queue_free()
			_toast_q.erase(t)


# -------------------------------------------------------------- pause menu --
func _build_pause() -> void:
	_pause_menu = Control.new()
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.visible = false
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_menu)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.035, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.add_child(bg)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = -180
	vb.offset_right = 180
	vb.offset_top = -220
	vb.offset_bottom = 220
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	_pause_menu.add_child(vb)
	var t := Label.new()
	t.text = "LEVERAGE"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	vb.add_child(t)
	var sub := Label.new()
	sub.text = "PAUSED"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	vb.add_child(sub)
	for row in [["RESUME", func(): Game.pause_toggle()],
		["PHONE / APPS", func(): Game.pause_toggle(); PhoneUI.open_phone()],
		["SAVE GAME", func(): Game.request_autosave(); _notify("Game saved.", "info")],
		["SETTINGS", func(): Game.pause_toggle(); PhoneUI.open_phone(); PhoneUI._show_settings()],
		["QUIT TO MENU", func(): get_tree().paused = false; Game.goto_scene("res://scenes/menu/menu.tscn"); Game.set_state(Game.State.MENU)]]:
		var b := Button.new()
		b.text = row[0]
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(row[1])
		vb.add_child(b)


func _player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


func _city_life() -> Node:
	return get_node_or_null("/root/City/CityLife")


func _fit_centers() -> void:
	UiFit.center(_toasts, 260.0)
	UiFit.center(_prompt_lbl, 260.0)


func _on_vp_resized() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var s: Vector2 = vp.get_visible_rect().size
	if s.x < 2.0 or s.y < 2.0:
		return  # host hasn't sized the window yet; will fire again
	for c in _root.get_children():
		c.queue_free()
	_build_top()
	_build_bars()
	_build_minimap()
	_build_objective()
	_build_toasts()
	_build_touch()
	_build_pause()
	_root.visible = enabled
	_fit_centers()
