extends CanvasLayer
## PhoneUI — Eli's phone: apps for Map, Jobs, Radio, Contacts, Inventory,
## Messages, Settings, Save. Touch-first grid; opens with PHONE action.

var open := false
var _root: Control
var _frame: Panel
var _screen: Control
var _app := ""
var _diff_desc: Label = null      # settings: what the chosen difficulty preset does
var _map_view: Control
var _news_i := 0

const CONTACTS := ["ruth", "marcus", "roz", "tess", "dex", "mags", "nia", "okoro", "bishop", "gunnar"]


func _ready() -> void:
	layer = 50
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_frame = Panel.new()
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_top = 0.5
	_frame.anchor_bottom = 0.5
	_frame.set_meta("fit_half", float(240))
	_frame.offset_top = -330
	_frame.offset_bottom = 330
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/textures/ui/panel9.png")
	sb.texture_margin_left = 16
	sb.texture_margin_right = 16
	sb.texture_margin_top = 16
	sb.texture_margin_bottom = 16
	_frame.add_theme_stylebox_override("panel", sb)
	_root.add_child(_frame)
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.set_meta("fit_pad", float(18))
	_screen.offset_top = 18
	_screen.offset_bottom = -18
	_frame.add_child(_screen)
	Bus.phone_opened.connect(func(): open_phone())
	Bus.phone_closed.connect(func(): close_phone())
	Bus.radio_news.connect(_on_news)


	_refit()
	UiFit.watch(self, _refit)

func open_phone() -> void:
	open = true
	_root.visible = true
	AudioDirector.sfx("phone_ring", 0.15)
	_show_home()


func close_phone() -> void:
	open = false
	_root.visible = false
	AudioDirector.sfx("ui_back", 0.12)


func _clear() -> void:
	for c in _screen.get_children():
		c.queue_free()
	if is_instance_valid(_map_view):
		_map_view.queue_free()
	_map_view = null


func _back() -> void:
	_show_home()


func _header(title: String) -> void:
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_TOP_WIDE)
	h.offset_bottom = 44
	_screen.add_child(h)
	var t := Label.new()
	t.text = title
	Type.apply(t, "display")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	h.add_child(t)
	var b := Button.new()
	b.text = "BACK"
	b.custom_minimum_size = Vector2(90, 40)
	b.pressed.connect(_back)
	h.add_child(b)


func _show_home() -> void:
	_clear()
	_app = ""
	var clock := Label.new()
	clock.text = "%02d:%02d  •  %d CR" % [int(WorldState.game_hour), int(fmod(WorldState.game_hour * 60.0, 60.0)), WorldState.money]
	clock.set_anchors_preset(Control.PRESET_TOP_WIDE)
	clock.offset_top = 4
	clock.offset_bottom = 30
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_theme_font_size_override("font_size", 15)
	clock.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
	_screen.add_child(clock)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.offset_top = 40
	grid.offset_bottom = -40
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_screen.add_child(grid)
	var apps := [
		["MAP", "i_map", _show_map], ["JOBS", "i_objective", _show_jobs], ["RADIO", "i_radio", _show_radio],
		["CALLS", "i_call", _show_contacts], ["BAG", "i_gun", _show_inventory], ["MSGS", "i_msg", _show_msgs],
		["SAVE", "i_phone", _show_save], ["SETUP", "i_armor", _show_settings], ["NEWS", "i_star", _show_news],
		["STATS", "i_star", _show_stats], ["GARAGE", "i_map", _show_garage],
		["TAXI", "i_money", _show_taxi], ["BIZ", "i_money", _show_biz],
	]
	for a in apps:
		var b := Button.new()
		b.text = a[0]
		b.custom_minimum_size = Vector2(0, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		var icon := load("res://assets/textures/ui/%s.png" % a[1])
		if icon:
			b.icon = icon
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(a[2])
		grid.add_child(b)


# -------------------------------------------------------------------- map ---
func _show_map() -> void:
	_clear()
	_app = "map"
	_header("CINDER CITY")
	_map_view = Control.new()
	_map_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_view.offset_top = 50
	_map_view.offset_bottom = -10
	_map_view.clip_contents = true
	_screen.add_child(_map_view)
	_map_view.draw.connect(_draw_map)
	_map_view.gui_input.connect(_map_tap)
	_map_view.queue_redraw()
	var rb := Button.new()
	rb.text = "ROUTE TO OBJECTIVE"
	rb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	rb.offset_left = -140
	rb.offset_right = 140
	rb.offset_top = -46
	rb.offset_bottom = -12
	rb.add_theme_font_size_override("font_size", 14)
	rb.pressed.connect(func():
		var mm := get_node_or_null("/root/MissionManager")
		if mm and mm.rt.get("pos") is Vector3:
			WorldState.gps_active = true
			WorldState.gps_target = mm.rt["pos"]
			WorldState.gps_label = mm.objective_text() if mm.has_method("objective_text") else "Objective"
			Bus.notification.emit("GPS: %s" % WorldState.gps_label, "info")
		else:
			Bus.notification.emit("No active objective.", "info")
		_map_view.queue_redraw())
	_screen.add_child(rb)


func _map_tap(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton) or not ev.pressed:
		return
	var wr := _map_rect()
	var size := _map_view.size
	var scale := minf(size.x / wr.size.x, size.y / wr.size.y)
	var off := (size - wr.size * scale) * 0.5
	var w := Vector2((ev.position.x - off.x) / scale + wr.position.x,
		(ev.position.y - off.y) / scale + wr.position.y)
	var best := ""
	var bd := 14.0 * 14.0 / maxf(0.001, scale * scale)
	for pid in WorldGen.pois:
		var d2: Dictionary = WorldGen.pois[pid].get("data", {})
		if not d2.has("at"):
			continue
		var at: Array = d2["at"]
		var dd := (Vector2(at[0], at[1]) - w).length_squared()
		if dd < bd:
			bd = dd
			best = pid
	if best != "":
		var dd2: Dictionary = WorldGen.pois[best].get("data", {})
		var at2: Array = dd2["at"]
		WorldState.gps_active = true
		WorldState.gps_target = Vector3(at2[0], 0, at2[1])
		WorldState.gps_label = str(dd2.get("name", best))
		Bus.notification.emit("GPS: %s" % WorldState.gps_label, "info")
		_map_view.queue_redraw()


func _map_rect() -> Rect2:
	# world bounds from district bounds
	var minv := Vector2(1e9, 1e9)
	var maxv := Vector2(-1e9, -1e9)
	for did in WorldGen.district_bounds:
		var r: Rect2 = WorldGen.district_bounds[did]
		minv = minv.min(r.position)
		maxv = maxv.max(r.end)
	minv -= Vector2(40, 40)
	maxv += Vector2(40, 40)
	return Rect2(minv, maxv - minv)


func _draw_map() -> void:
	if _map_view == null:
		return
	var v := _map_view
	var wr := _map_rect()
	var size := v.size
	var scale := minf(size.x / wr.size.x, size.y / wr.size.y)
	var off := (size - wr.size * scale) * 0.5
	var to_screen := func(p: Vector2) -> Vector2:
		return Vector2((p.x - wr.position.x) * scale + off.x, (p.y - wr.position.y) * scale + off.y)
	# water bg
	v.draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.08, 0.12))
	# districts (fog of war: unvisited districts stay dark + unlabeled)
	for did in WorldGen.district_bounds:
		var r: Rect2 = WorldGen.district_bounds[did]
		var p0: Vector2 = to_screen.call(r.position)
		var p1: Vector2 = to_screen.call(r.end)
		var seen: bool = did in WorldState.visited_districts
		if seen:
			v.draw_rect(Rect2(p0, p1 - p0), Color(0.16, 0.15, 0.14), true)
			# district heat bleeds onto the map: angry neighborhoods glow red
			var heat01: float = WorldState.district_heat01(str(did))
			if heat01 > 0.02:
				v.draw_rect(Rect2(p0, p1 - p0), Color(0.9, 0.22, 0.16, 0.05 + heat01 * 0.24), true)
			v.draw_rect(Rect2(p0, p1 - p0), Color(0.4, 0.36, 0.3), false, 1.0)
			var d := Db.district(did)
			v.draw_string(ThemeDB.fallback_font, p0 + Vector2(4, 14), d.get("name", did), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.65, 0.5))
		else:
			v.draw_rect(Rect2(p0, p1 - p0), Color(0.045, 0.05, 0.06), true)
			v.draw_string(ThemeDB.fallback_font, (p0 + p1) * 0.5 - Vector2(6, 0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.25, 0.27, 0.3))
	# roads (lane loops) — only where you have been
	for li in WorldGen.lanes.size():
		var lane: PackedVector3Array = WorldGen.lanes[li]
		if lane.size() < 2:
			continue
		if not (WorldGen.lane_district[li] in WorldState.visited_districts):
			continue
		var pts := PackedVector2Array()
		for p in lane:
			pts.append(to_screen.call(Vector2(p.x, p.z)))
		pts.append(pts[0])
		v.draw_polyline(pts, Color(0.35, 0.33, 0.3), 1.5)
	# owned businesses: your money on the map
	for pid in WorldState.owned_properties:
		var pr: Dictionary = Db.properties.get(str(pid), {})
		var pdid: String = str(pr.get("district", ""))
		if not WorldGen.district_bounds.has(pdid):
			continue
		var br: Rect2 = WorldGen.district_bounds[pdid]
		var c0: Vector2 = to_screen.call(Vector2(br.position.x + br.size.x * 0.5, br.position.y + br.size.y * 0.5))
		v.draw_rect(Rect2(c0 - Vector2(4, 4), Vector2(8, 8)), Color(0.23, 0.91, 0.69), true)
		v.draw_string(ThemeDB.fallback_font, c0 + Vector2(7, 4), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.35, 0.25))
	# GPS route
	if WorldState.gps_active:
		var pl = Game.player
		if pl:
			var path := WorldGen.route_world(pl.global_position, WorldState.gps_target)
			if path.size() > 1:
				var rp := PackedVector2Array()
				for p in path:
					rp.append(to_screen.call(Vector2(p.x, p.z)))
				v.draw_polyline(rp, Color(0.23, 0.91, 0.69, 0.95), 3.0)
			var dp: Vector2 = to_screen.call(Vector2(pl.global_position.x, pl.global_position.z))
			v.draw_circle(dp, 5.0, Color(0.95, 0.72, 0.25))
		var tp: Vector2 = to_screen.call(Vector2(WorldState.gps_target.x, WorldState.gps_target.z))
		v.draw_circle(tp, 6.0, Color(0.23, 0.91, 0.69))
		v.draw_circle(tp, 9.0, Color(0.23, 0.91, 0.69, 0.4), false, 2.0)
	# POIs
	for pid in WorldGen.pois:
		var entry: Dictionary = WorldGen.pois[pid]
		var d: Dictionary = entry.get("data", {})
		if not d.has("at"):
			continue
		var p: Vector2 = to_screen.call(Vector2(d["at"][0], d["at"][1]))
		var pdist: String = WorldGen.pois[pid].get("district", "")
		if not (pid in WorldState.discovered_pois) and not (pdist in WorldState.visited_districts):
			continue
		var col := Color(0.5, 0.8, 0.55)
		match d.get("kind", ""):
			"shop": col = Color(0.95, 0.75, 0.3)
			"home": col = Color(0.5, 0.75, 0.95)
			"law": col = Color(0.55, 0.6, 0.95)
			"place": col = Color(0.75, 0.7, 0.6)
			"fuel": col = Color(0.95, 0.45, 0.25)
		v.draw_circle(p, 3.0, col)
	# mission target
	var mm := get_node_or_null("/root/MissionManager")
	if mm and mm.active_id != "":
		var pos: Vector3 = mm.rt.get("pos", Vector3.ZERO)
		if pos == Vector3.ZERO:
			pos = mm.rt.get("to", Vector3.ZERO)
		if pos != Vector3.ZERO:
			var p: Vector2 = to_screen.call(Vector2(pos.x, pos.z))
			v.draw_circle(p, 7.0, Color(0.95, 0.72, 0.25, 0.85))
			v.draw_string(ThemeDB.fallback_font, p + Vector2(9, 4), "JOB", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.72, 0.25))
	# player arrow
	var g := get_tree().get_nodes_in_group("player")
	if g.size():
		var pp: Vector3 = g[0].global_position
		var p: Vector2 = to_screen.call(Vector2(pp.x, pp.z))
		var pts := PackedVector2Array([p + Vector2(0, -7), p + Vector2(5, 6), p + Vector2(-5, 6)])
		v.draw_colored_polygon(pts, Color(0.95, 0.25, 0.2))
	# wanted stars
	if WorldState.wanted > 0:
		v.draw_string(ThemeDB.fallback_font, Vector2(8, size.y - 10), "WANTED %s" % ("*".repeat(WorldState.wanted)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.3, 0.25))


# ------------------------------------------------------------------- jobs ---
func _show_jobs() -> void:
	_clear()
	_app = "jobs"
	_header("JOBS")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	var mm := get_node_or_null("/root/MissionManager")
	if mm == null:
		return
	if mm.active_id != "":
		var m := Db.mission(mm.active_id)
		vb.add_child(_job_row(m.get("title", ""), "ACTIVE — " + mm.objective_text(), Color(0.95, 0.72, 0.25), null))
	if mm.story_offer != "":
		var m := Db.mission(mm.story_offer)
		vb.add_child(_job_row("STORY: " + m.get("title", ""), m.get("summary", ""), Color(0.9, 0.35, 0.3), _accept.bind(mm.story_offer)))
	for sid in mm.side_offer:
		var m := Db.mission(sid)
		var rew: Dictionary = m.get("rewards", {})
		vb.add_child(_job_row(m.get("title", sid), "%s — pays %d cr%s" % [m.get("summary", ""), int(rew.get("money", 0)), " (repeatable)" if m.get("repeatable", false) else ""], Color(0.55, 0.8, 0.55), _accept.bind(sid)))


func _job_row(title: String, sub: String, col: Color, cb) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 74)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 15)
	b.text = "%s\n%s" % [title, sub]
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if cb != null:
		b.pressed.connect(cb)
	else:
		b.disabled = true
	return b


func _accept(mid: String) -> void:
	var mm := get_node_or_null("/root/MissionManager")
	if mm and mm.start_mission(mid):
		close_phone()


# ------------------------------------------------------------------ radio ---
func _show_radio() -> void:
	_clear()
	_app = "radio"
	_header("RADIO")
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 54
	vb.add_theme_constant_override("separation", 8)
	_screen.add_child(vb)
	for st in Db.radio.get("stations", []):
		var b := Button.new()
		b.text = "%s — %s" % [st.get("name", ""), st.get("tag", "")]
		b.custom_minimum_size = Vector2(0, 54)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_tune.bind(st.get("id", "")))
		vb.add_child(b)


func _tune(sid: String) -> void:
	var st: Dictionary = {}
	for s2 in Db.radio.get("stations", []):
		if s2.get("id", "") == sid:
			st = s2
	if st.is_empty():
		AudioDirector.stop_music(1.0)
		Bus.notification.emit("Radio off.", "info")
		close_phone()
		return
	var tracks: Array = st.get("tracks", [])
	if tracks.is_empty():
		close_phone()
		return
	AudioDirector.play_music(tracks[randi() % tracks.size()], 1.0)
	WorldState.phone_station = sid
	Bus.notification.emit("Tuned to %s" % st.get("name", sid), "info")
	close_phone()


# --------------------------------------------------------------- contacts ---
func _show_contacts() -> void:
	_clear()
	_app = "calls"
	_header("CONTACTS")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	for cid in CONTACTS:
		var c: Dictionary = Db.character(cid)
		var rel: int = int(WorldState.relationships.get(cid, 0))
		var b := Button.new()
		b.text = "%s  (rel %+d)" % [c.get("name", cid), rel]
		b.custom_minimum_size = Vector2(0, 48)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_call.bind(cid))
		vb.add_child(b)
	var sep := Label.new()
	sep.text = "— RECENT CALLS —"
	sep.add_theme_font_size_override("font_size", 12)
	sep.add_theme_color_override("font_color", Color(0.6, 0.6, 0.58))
	vb.add_child(sep)
	_show_calls_log(vb)
	# answer mission call if pending
	var mm := get_node_or_null("/root/MissionManager")
	if mm and mm.active_id != "" and mm.stage.get("type", "") == "phone" and mm.rt.get("rang", false):
		var b := Button.new()
		b.text = ">> ANSWER INCOMING CALL <<"
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func():
			mm.answer_phone_call()
			close_phone())
		vb.add_child(b)


func _call(cid: String) -> void:
	close_phone()
	CallManager.place_outgoing(cid)
	var tree: String = "chat_" + str({"padre_sol": "padre", "crowe_jr": "julian"}.get(cid, cid))
	if Db.dialogue.has(tree):
		DialogueUI.start_tree(tree)
	elif Db.dialogue.has("chat_ruth"):
		DialogueUI.start_tree("chat_ruth")
	else:
		Bus.notification.emit("No answer.", "info")


# -------------------------------------------------------------- inventory ---
func _show_inventory() -> void:
	_clear()
	_app = "bag"
	_header("BAG — %d cr" % WorldState.money)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	scroll.add_child(vb)
	# weapons
	var wl := Label.new()
	wl.text = "WEAPONS"
	wl.add_theme_font_size_override("font_size", 13)
	wl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	vb.add_child(wl)
	for wid in WorldState.weapons:
		var w := Db.weapon(wid)
		var b := Button.new()
		b.text = "%s%s" % [w.get("name", wid), "  [EQUIPPED]" if _player_weapon() == wid else ""]
		b.custom_minimum_size = Vector2(0, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_equip_weapon.bind(wid))
		vb.add_child(b)
	# armor
	var al := Label.new()
	al.text = "ARMOR — %s" % Db.armor.get(WorldState.equipped_armor, {}).get("name", "None")
	al.add_theme_font_size_override("font_size", 13)
	al.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	vb.add_child(al)
	for aid in Db.armor:
		if aid == "armor_none":
			continue
		var owned: bool = bool(WorldState.get_flag("armor_" + aid, false)) or aid == "armor_jacket"
		var a: Dictionary = Db.armor[aid]
		var b := Button.new()
		b.text = "%s (%d%% prot)%s" % [a.get("name", aid), int(a.get("protection", 0) * 100), "" if owned else " — NOT OWNED"]
		b.custom_minimum_size = Vector2(0, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.disabled = not owned
		if owned:
			b.pressed.connect(func():
				WorldState.equip_armor(aid)
				_show_inventory())
		vb.add_child(b)
	# consumables
	var cl := Label.new()
	cl.text = "ITEMS"
	cl.add_theme_font_size_override("font_size", 13)
	cl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	vb.add_child(cl)
	for iid in WorldState.inventory:
		var q: int = WorldState.inventory[iid]
		if q <= 0:
			continue
		var it := Db.item(iid)
		var b := Button.new()
		b.text = "%s x%d%s" % [it.get("name", iid), q, " — USE" if it.get("kind", "") == "consumable" else ""]
		b.custom_minimum_size = Vector2(0, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		if it.get("kind", "") == "consumable":
			b.pressed.connect(_use_item.bind(iid))
		else:
			b.disabled = true
		vb.add_child(b)


func _player_weapon() -> String:
	var g := get_tree().get_nodes_in_group("player")
	if g.size() and g[0].weapons:
		return g[0].weapons.equipped
	return ""


func _equip_weapon(wid: String) -> void:
	var g := get_tree().get_nodes_in_group("player")
	if g.size() and g[0].weapons:
		g[0].weapons.equip(wid)
	_show_inventory()


func _use_item(iid: String) -> void:
	var g := get_tree().get_nodes_in_group("player")
	if g.size() and g[0].has_method("use_item"):
		g[0].use_item(iid)
	_show_inventory()


# ------------------------------------------------------------------- msgs ---
func _show_msgs() -> void:
	_clear()
	_app = "msgs"
	_header("MESSAGES")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	var msgs: Variant = WorldState.get_flag("messages", [])
	if msgs is Array:
		for m in msgs:
			var l := Label.new()
			l.text = "%s: %s" % [m.get("from", "?"), m.get("text", "")]
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 14)
			vb.add_child(l)
	_show_threads(vb)
	if vb.get_child_count() == 0:
		var l := Label.new()
		l.text = "No messages. The city is quiet — for now."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(l)


# ------------------------------------------------------------------- save ---
func _show_save() -> void:
	_clear()
	_app = "save"
	_header("SAVE")
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 54
	vb.add_theme_constant_override("separation", 10)
	_screen.add_child(vb)
	for slot in 3:
		var meta := SaveSystem.meta(slot)
		var b := Button.new()
		b.text = ("SLOT %d — %s" % [slot + 1, meta.get("label", "empty")]) if not meta.is_empty() else "SLOT %d — empty" % (slot + 1)
		b.custom_minimum_size = Vector2(0, 56)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_save_slot.bind(slot))
		vb.add_child(b)
		var l := Button.new()
		l.text = "  load slot %d" % (slot + 1)
		l.custom_minimum_size = Vector2(0, 40)
		l.alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.add_theme_font_size_override("font_size", 13)
		l.disabled = meta.is_empty()
		l.pressed.connect(func():
			close_phone()
			Game.continue_game(slot))
		vb.add_child(l)


func _save_slot(slot: int) -> void:
	if slot == 0:
		Game.request_autosave()
	else:
		SaveSystem.save_game(slot, Game._save_extra())
	Bus.notification.emit("Saved to slot %d." % (slot + 1), "info")
	_show_save()


# --------------------------------------------------------------- settings ---
func _show_settings() -> void:
	_clear()
	_app = "settings"
	_header("SETTINGS")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)
	for key in [["master", "Master volume"], ["music", "Music"], ["sfx", "SFX"], ["vox", "Voice"]]:
		vb.add_child(_slider(key[0], key[1], 0.0, 1.0, 0.05))
	vb.add_child(_slider("sensitivity", "Look sensitivity", 0.3, 2.5, 0.1))
	vb.add_child(_slider("touch_scale", "Touch controls size", 0.7, 1.5, 0.05))
	for key in [["subtitles", "Subtitles"], ["shake", "Camera shake"], ["invert_y", "Invert look Y"]]:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = key[1]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 15)
		h.add_child(l)
		var cb := CheckButton.new()
		cb.button_pressed = Game.settings.get(key[0], true)
		cb.toggled.connect(func(on):
			Game.settings[key[0]] = on
			Game.save_settings())
		h.add_child(cb)
		vb.add_child(h)
	# ---- difficulty preset --------------------------------------------------
	# Sits ABOVE quality because it changes the game, not the framerate. It
	# scales Difficulty's progress-derived threat curve rather than replacing
	# it, so the story still escalates on every preset.
	var dh := HBoxContainer.new()
	var dl := Label.new()
	dl.text = "Difficulty"
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.add_theme_font_size_override("font_size", 15)
	dh.add_child(dl)
	var dob := OptionButton.new()
	var diff96 := get_node_or_null("/root/Difficulty")
	for i96 in diff96.preset_count():
		dob.add_item(diff96.preset_name(i96))
	dob.selected = clampi(int(Game.settings.get("difficulty", 1)), 0, diff96.preset_count() - 1)
	dob.custom_minimum_size = Vector2(150, 0)
	dob.item_selected.connect(func(i96b: int):
		Game.settings["difficulty"] = i96b
		Game.save_settings()
		_refresh_diff_desc())
	dh.add_child(dob)
	vb.add_child(dh)
	_diff_desc = Label.new()
	_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_desc.custom_minimum_size = Vector2(0, 34)
	_diff_desc.add_theme_font_size_override("font_size", 12)
	_diff_desc.add_theme_color_override("font_color", Color(0.62, 0.62, 0.57))
	vb.add_child(_diff_desc)
	_refresh_diff_desc()

	# quality
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


func _refresh_diff_desc() -> void:
	## Say what the preset actually DOES. A difficulty menu that only names
	## three levels tells the player nothing about what changed.
	if _diff_desc == null or not is_instance_valid(_diff_desc):
		return
	var diff := get_node_or_null("/root/Difficulty")
	if diff == null:
		return
	var i := clampi(int(Game.settings.get("difficulty", 1)), 0, diff.preset_count() - 1)
	var mult: float = float(diff.PRESETS[i]["mult"])
	_diff_desc.text = "%s  (threat x%.2f)\n%s" % [diff.preset_name(i), mult, diff.preset_desc(i)]


func _slider(key: String, label: String, mn: float, mx: float, step: float) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(180, 0)
	l.add_theme_font_size_override("font_size", 14)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Game.settings.get(key, 0.8))
	s.custom_minimum_size = Vector2(200, 30)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v):
		Game.settings[key] = v
		Game.save_settings())
	h.add_child(s)
	return h


# ------------------------------------------------------------------- news ---
func _show_stats() -> void:
	_clear()
	_app = "stats"
	_header("ELI — DOSSIER")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	# level + xp
	vb.add_child(_stat_line("LEVEL %d" % Progression.level, "XP %d / %d to next" % [Progression.xp, Progression.xp_for_next()]))
	# style mastery ladder
	for sid in ["brawler", "kickboxing", "grappling", "drunken", "weapon"]:
		var rank: int = Progression.style_rank(sid)
		var moves: Array = Progression.unlocked_moves(sid)
		var mtxt: String = ", ".join(moves) if not moves.is_empty() else "no unlocks yet"
		vb.add_child(_stat_line("%s — MASTERY %d/5" % [Db.style(sid).get("label", sid), rank], mtxt))
	# factions
	for fac in ["family", "crew", "corp"]:
		var rep: float = WorldState.factions.get(fac, 0.0)
		var mood := "allied" if rep > 50 else ("friendly" if rep > 15 else ("neutral" if rep > -25 else ("cold" if rep > -60 else "HUNTING YOU")))
		vb.add_child(_stat_line(fac.to_upper(), "%+d rep — %s" % [int(rep), mood]))
	# district heat
	var hot := []
	for did in WorldState.district_heat:
		if WorldState.district_heat[did] > 12.0:
			hot.append("%s %d%%" % [Db.district(did).get("name", did), int(WorldState.district_heat[did])])
	vb.add_child(_stat_line("STREET HEAT", ", ".join(hot) if not hot.is_empty() else "quiet everywhere"))
	# the street ledger — every number the game has been keeping all along
	var st: Dictionary = WorldState.stats
	var mins := int(float(st.get("playtime", 0.0)) / 60.0)
	vb.add_child(_stat_line("THE STREET LEDGER", "time on the clock: %dh %dm" % [mins / 60, mins % 60]))
	vb.add_child(_stat_line("MOVEMENT", "%.1f km on foot · %.1f km driven" % [float(st.get("on_foot_km", 0.0)), float(st.get("driven_km", 0.0))]))
	vb.add_child(_stat_line("CRIMES", "%d thefts · %d kills · %d arrests · %d deaths" % [int(st.get("thefts", 0)), int(st.get("kos", 0)), int(st.get("arrests", 0)), int(st.get("deaths", 0))]))
	vb.add_child(_stat_line("FIGHTS", "%d won · %d gambles" % [int(st.get("fights_won", 0)), int(st.get("gambled", 0))]))
	vb.add_child(_stat_line("WHEELS", "%d races won · %d wrecks · %d resprays · %d ghost runs" % [int(st.get("races_won", 0)), int(st.get("wrecks", 0)), int(st.get("resprays", 0)), int(st.get("ghost_runs", 0))]))
	vb.add_child(_stat_line("BODIES", "%d found · %d hidden · %d collectibles" % [int(st.get("bodies_found", 0)), int(st.get("bodies_hidden", 0)), int(st.get("collectibles", 0))]))
	vb.add_child(_stat_line("CAREER", "jobs done: %d" % int(st.get("jobs_done", 0))))


func _stat_line(title: String, sub: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	var l1 := Label.new()
	l1.text = title
	l1.add_theme_font_size_override("font_size", 15)
	l1.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	v.add_child(l1)
	var l2 := Label.new()
	l2.text = sub
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.add_theme_font_size_override("font_size", 13)
	l2.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	v.add_child(l2)
	return v


func _player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


func _show_biz() -> void:
	_clear()
	_app = "biz"
	_header("BUSINESSES")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)
	var note := Label.new()
	note.text = "Buy in. Every business pays its cut once a day."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	vb.add_child(note)
	for pid in Db.properties:
		var pr: Dictionary = Db.properties[pid]
		var owned: bool = pid in WorldState.owned_properties
		var b := Button.new()
		b.text = "%s — %s" % [pr.get("name", pid), "OWNED (+%d cr/day)" % int(pr.get("income", 0)) if owned else "%d cr (+%d cr/day)" % [int(pr.get("price", 0)), int(pr.get("income", 0))]]
		b.tooltip_text = str(pr.get("blurb", ""))
		b.custom_minimum_size = Vector2(0, 56)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.disabled = owned
		if not owned:
			b.pressed.connect(_buy_property.bind(str(pid)))
		vb.add_child(b)
		if not owned and str(pr.get("blurb", "")) != "":
			var l := Label.new()
			l.text = "   " + str(pr.get("blurb", ""))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 12)
			l.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
			vb.add_child(l)


func _buy_property(pid: String) -> void:
	var pr: Dictionary = Db.properties.get(pid, {})
	var price := int(pr.get("price", 0))
	if WorldState.money < price:
		Bus.notification.emit("You need %d cr for this buy-in." % price, "error")
		AudioDirector.sfx("ui_error", 0.2)
		return
	WorldState.add_money(-price)
	WorldState.owned_properties.append(pid)
	AudioDirector.sfx("cash", 0.5)
	Bus.notification.emit("You own %s now. Payouts daily." % pr.get("name", pid), "mission")
	Game.request_autosave()
	_show_biz()


func _show_taxi() -> void:
	_clear()
	_app = "taxi"
	_header("TAXI")
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 54
	vb.add_theme_constant_override("separation", 8)
	_screen.add_child(vb)
	var p := _player()
	if p == null:
		return
	if WorldState.wanted > 0:
		var l := Label.new()
		l.text = "No cab's stopping for you with stars on the board. Lose the heat first."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.9, 0.45, 0.35))
		vb.add_child(l)
		return
	var rides := 0
	for pid in WorldState.discovered_pois:
		var pd: Dictionary = WorldGen.pois.get(str(pid), {})
		var d2: Dictionary = pd.get("data", {})
		if not d2.has("at"):
			continue
		var at: Array = d2["at"]
		var pos := Vector3(at[0], 0, at[1])
		var dist: float = (pos - p.global_position).length()
		if dist < 60.0:
			continue   # walking distance — don't waste the fare
		var fare := int(12.0 + dist * 0.09)
		if WorldState.owns_property("cab_share"):
			fare = maxi(5, int(fare * 0.5))   # medallion owner rides half-rate
		rides += 1
		var b := Button.new()
		b.text = "%s — %d cr  (%d m)" % [d2.get("name", str(pid)), fare, int(dist)]
		b.custom_minimum_size = Vector2(0, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_ride_taxi.bind(pos, fare, d2.get("name", str(pid))))
		vb.add_child(b)
	if rides == 0:
		var l2 := Label.new()
		l2.text = "Nowhere to go that your feet can't manage. Discover more of the city first."
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
		vb.add_child(l2)


func _ride_taxi(pos: Vector3, fare: int, dest: String) -> void:
	if WorldState.money < fare:
		Bus.notification.emit("Fare is %d cr. You're short." % fare, "error")
		AudioDirector.sfx("ui_error", 0.2)
		return
	var p := _player()
	if p == null or WorldState.wanted > 0:
		return
	WorldState.add_money(-fare)
	# the ride takes time — cabs in Cinder don't fly
	var hours := clampf(pos.distance_to(p.global_position) / 2600.0, 0.08, 0.5)
	WorldState.advance_hours(hours)
	p.global_position = pos + Vector3(3.0, 0.2, 3.0)
	if p.in_vehicle != null and p.has_method("exit_vehicle"):
		p.exit_vehicle()
	AudioDirector.sfx("veh_door_close", 0.5)
	Bus.notification.emit("Cab drops you at %s. -%d cr." % [dest, fare], "info")
	close_phone()


func _show_garage() -> void:
	_clear()
	_app = "garage"
	_header("GARAGE")
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 54
	vb.add_theme_constant_override("separation", 8)
	_screen.add_child(vb)
	# keep the car you're sitting in — insurance on a hot ride
	var p := _player()
	if p != null and p.in_vehicle != null:
		var vid: String = str(p.in_vehicle.vehicle_def_id)
		var kb := Button.new()
		if vid in WorldState.owned_vehicles:
			kb.text = "You're driving your own %s." % Db.vehicle(vid).get("name", vid)
			kb.disabled = true
		else:
			kb.text = "KEEP THIS RIDE — %s (files it as yours)" % Db.vehicle(vid).get("name", vid)
			kb.pressed.connect(_keep_ride)
		kb.custom_minimum_size = Vector2(0, 54)
		kb.add_theme_font_size_override("font_size", 14)
		vb.add_child(kb)
	if WorldState.owned_vehicles.is_empty():
		var l := Label.new()
		l.text = "No rides on file. Buy one at a garage, or keep what you're driving."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
		vb.add_child(l)
		return
	var fee := Label.new()
	fee.text = "Delivery to your curb: 40 cr."
	fee.add_theme_font_size_override("font_size", 13)
	fee.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	vb.add_child(fee)
	for vid in WorldState.owned_vehicles:
		var v: Dictionary = Db.vehicle(str(vid))
		var b := Button.new()
		b.text = "SUMMON — %s" % v.get("name", vid)
		b.custom_minimum_size = Vector2(0, 54)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_summon_vehicle.bind(str(vid)))
		vb.add_child(b)


func _keep_ride() -> void:
	var p := _player()
	if p == null or p.in_vehicle == null:
		return
	var vid: String = str(p.in_vehicle.vehicle_def_id)
	if vid not in WorldState.owned_vehicles:
		WorldState.owned_vehicles.append(vid)
	AudioDirector.sfx("ui_confirm", 0.3)
	Bus.notification.emit("%s filed to your garage." % Db.vehicle(vid).get("name", vid), "mission")
	close_phone()


func _summon_vehicle(vid: String) -> void:
	if WorldState.money < 40:
		Bus.notification.emit("Delivery fee is 40 cr. You're short.", "error")
		AudioDirector.sfx("ui_error", 0.2)
		return
	var p := _player()
	if p == null:
		return
	# nearest point on any traffic lane — "your curb"
	var best: Vector3 = p.global_position + Vector3(5, 0, 0)
	var bd := 1e9
	for lane in WorldGen.lanes:
		for pt in lane:
			var d: float = (pt - p.global_position).length()
			if d < bd:
				bd = d
				best = pt
	var city := get_node_or_null("/root/CityLife")
	if city == null or not city.has_method("give_player_vehicle"):
		return
	WorldState.add_money(-40)
	city.give_player_vehicle(vid, best + Vector3(0, 0.5, 0))
	AudioDirector.sfx("veh_start", 0.4)
	Bus.notification.emit("%s delivered to the nearest curb." % Db.vehicle(vid).get("name", vid), "mission")
	close_phone()


func _show_news() -> void:
	_clear()
	_app = "news"
	_header("CINDER NEWS")
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 50
	_screen.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)
	var templates: Array = WorldState.news_queue
	if templates.is_empty():
		for t in Db.news_templates:
			var line: String = t.get("text", t if t is String else "")
			line = line.replace("{district}", Db.district(Game.current_district).get("name", "the city"))
			vb.add_child(_news_label(line))
			if vb.get_child_count() >= 5:
				break
	else:
		for n in templates.slice(-6):
			vb.add_child(_news_label(n))


func _news_label(text: String) -> Label:
	var l := Label.new()
	l.text = "• " + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	return l


func _on_news(text: String) -> void:
	push_news(text)


## Public: systems (heat milestones, missions) file stories into the feed.
func push_news(text: String) -> void:
	if not WorldState.news_queue.has(text):
		WorldState.news_queue.append(text)
		if WorldState.news_queue.size() > 24:
			WorldState.news_queue.pop_front()


func _input(event: InputEvent) -> void:
	if open and event.is_action_pressed("ui_cancel"):
		close_phone()
		get_viewport().set_input_as_handled()


func _refit() -> void:
	UiFit.refit_tree(self)


func _show_calls_log(list: VBoxContainer) -> void:
	var log: Array = WorldState.call_log.duplicate()
	log.reverse()
	for e in log:
		var ch: Dictionary = Db.character(e.get("char", "eli"))
		var row := HBoxContainer.new()
		var ic := Label.new()
		ic.text = "MISSED" if e.get("result") == "missed" else ("OUT" if e.get("result") == "out" else "IN")
		ic.add_theme_color_override("font_color", Color(0.9, 0.3, 0.25) if e.get("result") == "missed" else Color(0.6, 0.8, 0.6))
		ic.add_theme_font_size_override("font_size", 12)
		row.add_child(ic)
		var nm := Label.new()
		nm.text = str(ch.get("name", e.get("char", "?")))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.add_theme_font_size_override("font_size", 14)
		row.add_child(nm)
		var tm := Label.new()
		tm.text = "%s %s" % [e.get("day", ""), e.get("hour", "")]
		tm.add_theme_font_size_override("font_size", 11)
		tm.add_theme_color_override("font_color", Color(0.6, 0.6, 0.58))
		row.add_child(tm)
		list.add_child(row)
	if log.is_empty():
		var empty := Label.new()
		empty.text = "No recent calls."
		empty.add_theme_font_size_override("font_size", 13)
		list.add_child(empty)


func _show_threads(list: VBoxContainer) -> void:
	var threads: Dictionary = WorldState.msg_threads
	if threads.is_empty():
		var empty := Label.new()
		empty.text = "No messages yet."
		empty.add_theme_font_size_override("font_size", 13)
		list.add_child(empty)
	for tid in threads:
		var ch: Dictionary = Db.character(tid)
		var unread := 0
		for m in threads[tid]:
			if not m["read"]:
				unread += 1
		var b := Button.new()
		var last: Dictionary = threads[tid][-1]
		b.text = "%s%s — %s" % [str(ch.get("name", tid)), (" (%d new)" % unread) if unread > 0 else "", last.get("text", "")]
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(0, 64)
		var tidc: String = str(tid)
		b.pressed.connect(func(): _open_thread(tidc))
		list.add_child(b)


func _open_thread(tid: String) -> void:
	CallManager.mark_thread_read(tid)
	var scr := ScrollContainer.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(scr)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scr.add_child(list)
	var head := Label.new()
	var ch: Dictionary = Db.character(tid)
	head.text = str(ch.get("name", tid))
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	list.add_child(head)
	for m in WorldState.msg_threads[tid]:
		var row := Label.new()
		row.text = "%s · %s: %s" % [m.get("hour", ""), "THEM" if m.get("from") == tid else "YOU", m.get("text", "")]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 13)
		list.add_child(row)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func():
		scr.queue_free()
		_show_msgs())
	list.add_child(back)
