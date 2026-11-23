extends CanvasLayer
## ShopUI — full-screen shop: keeper greeting, stock list with prices,
## buy/sell, vehicle dealership, services (heal at clinic). Touch-first.

var open := false
var _shop_id := ""
var _panel: Control
var _title: Label
var _money: Label
var _list: VBoxContainer
var _desc: Label
var _scroll: ScrollContainer
var _tabs: HBoxContainer
var _tab := "buy"


func _ready() -> void:
	layer = 45
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.06, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)
	_title = Label.new()
	_title.position = Vector2(40, 26)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.95, 0.72, 0.25))
	_panel.add_child(_title)
	_money = Label.new()
	_money.anchor_left = 1.0
	_money.anchor_right = 1.0
	_money.offset_left = -300
	_money.offset_right = -40
	_money.offset_top = 30
	_money.offset_bottom = 62
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.add_theme_font_size_override("font_size", 22)
	_panel.add_child(_money)
	_tabs = HBoxContainer.new()
	_tabs.position = Vector2(40, 74)
	_tabs.add_theme_constant_override("separation", 10)
	_panel.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.set_meta("fit_pad", float(40))
	_scroll.offset_top = 130
	_scroll.offset_bottom = -110
	_panel.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	_desc = Label.new()
	_desc.anchor_top = 1.0
	_desc.anchor_bottom = 1.0
	_desc.anchor_right = 1.0
	_desc.offset_left = 40
	_desc.offset_right = -260
	_desc.offset_top = -90
	_desc.offset_bottom = -30
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 15)
	_desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	_panel.add_child(_desc)
	var close := Button.new()
	close.text = "CLOSE"
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.anchor_top = 1.0
	close.anchor_bottom = 1.0
	close.offset_left = -220
	close.offset_right = -40
	close.offset_top = -90
	close.offset_bottom = -30
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_shop)
	_panel.add_child(close)
	Bus.money_changed.connect(func(_m): _refresh_money())


	_refit()
	UiFit.watch(self, _refit)

func open_shop(shop_id: String) -> void:
	var s: Dictionary = Db.shops.get(shop_id, {})
	if s.is_empty():
		return
	_shop_id = shop_id
	open = true
	_panel.visible = true
	_title.text = s.get("name", shop_id)
	_refresh_money()
	_build_tabs(s)
	_tab = "buy"
	_build_list()
	AudioDirector.sfx("shop_bell", 0.2)
	var keeper: String = s.get("keeper", "")
	var dlg: String = s.get("dialogue", "")
	if dlg != "" and Db.dialogue.has(dlg) and not DialogueUI.is_open():
		DialogueUI.start_tree(dlg)


func close_shop() -> void:
	open = false
	_panel.visible = false
	AudioDirector.sfx("ui_back", 0.15)


func _refresh_money() -> void:
	_money.text = "%d CR" % WorldState.money


func _build_tabs(s: Dictionary) -> void:
	for c in _tabs.get_children():
		c.queue_free()
	var tabs := ["buy"]
	if s.get("buys", false):
		tabs.append("sell")
	if s.has("vehicles"):
		tabs = ["vehicles"]
	if _shop_id == "clinic":
		tabs.append("heal")
	if _shop_id == "gunsmith":
		tabs.append("mods")
	for t in tabs:
		var b := Button.new()
		b.text = t.to_upper()
		b.custom_minimum_size = Vector2(120, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func():
			_tab = t
			_build_list())
		_tabs.add_child(b)


func _build_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var s: Dictionary = Db.shops.get(_shop_id, {})
	match _tab:
		"buy":
			for id in s.get("stock", []):
				var entry := _stock_entry(id)
				if not entry.is_empty():
					_list.add_child(_row(entry["name"], "%d cr" % entry["price"], entry.get("blurb", ""), _make_buy.bind(id, entry["price"])))
		"sell":
			var any := false
			for id in WorldState.inventory:
				var q: int = WorldState.inventory[id]
				if q <= 0:
					continue
				var entry := _stock_entry(id)
				var price := int(entry.get("price", 20)) / 2
				any = true
				_list.add_child(_row("%s (x%d)" % [entry.get("name", id), q], "sell %d cr" % price, "", _make_sell.bind(id, price)))
			for id in WorldState.owned_weapons:
				if id == "fists":
					continue
				var w := Db.weapon(id)
				var price := int(w.get("price", 50)) / 2
				any = true
				_list.add_child(_row(w.get("name", id), "sell %d cr" % price, "", _make_sell_weapon.bind(id, price)))
			if not any:
				_list.add_child(_row("Nothing to sell.", "", "", null))
		"vehicles":
			for id in s.get("vehicles", []):
				var v := Db.vehicle(id)
				_list.add_child(_row(v.get("name", id), "%d cr" % int(v.get("price", 3000)), v.get("type", "car"), _make_buy_vehicle.bind(id)))
		"heal":
			_list.add_child(_row("Full treatment", "120 cr", "Patch every wound, top off stamina.", _heal))
		"mods":
			_build_mods()


func _build_mods() -> void:
	## Ghost Recon-lite workbench: pick a gun you own, then buy/fit
	## attachments per slot. Bought parts live in inventory until fitted;
	## fitting is free and swappable — loadouts per weapon persist in saves.
	for wid in WorldState.owned_weapons:
		var w := Db.weapon(wid)
		if w.get("kind", "") != "gun":
			continue
		var fitted: Dictionary = WorldState.weapon_attachments.get(wid, {})
		var fitted_txt := ", ".join(fitted.values()) if not fitted.is_empty() else "stock"
		_list.add_child(_row(w.get("name", wid), "", "fitted: %s" % fitted_txt, null))
		for aid in Db.weapons:
			var a := Db.weapon(aid)
			if a.get("kind", "") != "attachment":
				continue
			if wid not in a.get("fits", []):
				continue
			var owned_part: bool = WorldState.inventory.get(aid, 0) > 0
			var slot: String = a.get("slot", "misc")
			var label: String = "%s — %s" % [a.get("name", aid), slot]
			if fitted.get(slot, "") == aid:
				_list.add_child(_row("   " + label, "FITTED", a.get("blurb", ""), null))
			elif owned_part:
				_list.add_child(_row("   " + label, "own part", "fit it", _fit_attachment.bind(wid, aid)))
			else:
				_list.add_child(_row("   " + label, "%d cr" % int(a.get("price", 100)), a.get("blurb", ""), _make_buy_attachment.bind(wid, aid, int(a.get("price", 100)))))


func _make_buy_attachment(wid: String, aid: String, price: int) -> void:
	if WorldState.money < price:
		Bus.notification.emit("Not enough credits.", "error")
		AudioDirector.sfx("ui_error", 0.2)
		return
	WorldState.add_money(-price)
	WorldState.add_item(aid, 1)
	_fit_attachment(wid, aid)


func _fit_attachment(wid: String, aid: String) -> void:
	var a := Db.weapon(aid)
	var slot: String = a.get("slot", "misc")
	if not WorldState.weapon_attachments.has(wid):
		WorldState.weapon_attachments[wid] = {}
	WorldState.weapon_attachments[wid][slot] = aid
	WorldState.remove_item(aid, 1)
	AudioDirector.sfx("reload_magin", 0.15)
	Bus.notification.emit("%s fitted to %s." % [a.get("name", aid), Db.weapon(wid).get("name", wid)], "info")
	_refresh_money()
	_build_list()


func _stock_entry(id: String) -> Dictionary:
	if Db.items.has(id):
		return Db.items[id]
	if Db.weapons.has(id):
		var w = Db.weapons[id].duplicate()
		w["blurb"] = w.get("kind", "") + (" — %d dmg" % w["dmg"] if w.has("dmg") else "")
		return w
	if Db.armor.has(id):
		var a = Db.armor[id].duplicate()
		a["blurb"] = "Armor — %d%% protection" % int(a.get("protection", 0) * 100)
		return a
	if Db.outfits.has(id):
		var o = Db.outfits[id].duplicate()
		o["blurb"] = "Outfit — changes your look."
		return o
	return {}


func _row(name: String, price: String, blurb: String, cb) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var nl := Label.new()
	nl.text = name
	nl.custom_minimum_size = Vector2(260, 0)
	nl.add_theme_font_size_override("font_size", 17)
	h.add_child(nl)
	var pl := Label.new()
	pl.text = price
	pl.custom_minimum_size = Vector2(110, 0)
	pl.add_theme_font_size_override("font_size", 16)
	pl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
	h.add_child(pl)
	var b := Button.new()
	b.text = blurb if blurb != "" else "SELECT"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 14)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if cb != null:
		b.pressed.connect(cb)
	else:
		b.disabled = true
	h.add_child(b)
	return h


func _make_buy(id: String, price: int) -> void:
	if WorldState.money < price:
		Bus.notification.emit("Not enough credits.", "error")
		AudioDirector.sfx("ui_error", 0.2)
		return
	WorldState.add_money(-price)
	if Db.items.has(id):
		WorldState.add_item(id, 1)
	elif Db.weapons.has(id):
		if id.begins_with("ammo_"):
			WorldState.add_item(id, 1)
		else:
			var player := _player()
			if player and player.has_method("give_weapon"):
				player.give_weapon(id)
			else:
				WorldState.give_weapon(id)
	elif Db.armor.has(id):
		WorldState.equip_armor(id)
	elif Db.outfits.has(id):
		WorldState.owned_outfits[id] = true
		WorldState.equipped_outfit = id
		var pl := _player()
		if pl and pl.has_method("rebuild_appearance"):
			pl.rebuild_appearance()
		Bus.notification.emit("Outfit equipped — look at you.", "info")
	AudioDirector.sfx("cash", 0.3)
	Bus.notification.emit("Bought %s." % _stock_entry(id).get("name", id), "info")
	_refresh_money()


func _make_sell(id: String, price: int) -> void:
	if WorldState.inventory.get(id, 0) <= 0:
		return
	WorldState.remove_item(id, 1)
	WorldState.add_money(price)
	AudioDirector.sfx("cash", 0.3)
	_build_list()


func _make_sell_weapon(id: String, price: int) -> void:
	WorldState.owned_weapons.erase(id)
	WorldState.add_money(price)
	AudioDirector.sfx("cash", 0.3)
	_build_list()


func _make_buy_vehicle(id: String) -> void:
	var v := Db.vehicle(id)
	var price := int(v.get("price", 3000))
	if price <= 0:
		price = 2500
	if WorldState.money < price:
		Bus.notification.emit("Not enough credits.", "error")
		AudioDirector.sfx("ui_error", 0.2)
		return
	WorldState.add_money(-price)
	# spawn outside the garage door
	var poi: Dictionary = WorldGen.pois.get(Db.shops[_shop_id].get("poi", ""), {})
	var pos := Vector3.ZERO
	var d: Dictionary = poi.get("data", {})
	if d.has("at"):
		pos = Vector3(d["at"][0], 0.5, d["at"][1] + 6.0)
	else:
		var p := _player()
		pos = p.global_position + Vector3(4, 0, 0) if p else Vector3.ZERO
	var city := get_node_or_null("/root/CityLife")
	if city:
		city.give_player_vehicle(id, pos)
	WorldState.owned_vehicles.append(id)
	AudioDirector.sfx("veh_start", 0.4)
	Bus.notification.emit("%s delivered outside." % v.get("name", id), "mission")
	close_shop()


func _heal() -> void:
	if WorldState.money < 120:
		Bus.notification.emit("Not enough credits.", "error")
		return
	WorldState.add_money(-120)
	var p := _player()
	if p and p.combat:
		p.combat.heal(999)
	AudioDirector.sfx("cloth_rustle", 0.4)
	Bus.notification.emit("Patched up.", "info")
	_refresh_money()


func _player() -> Node:
	var g := get_tree().get_nodes_in_group("player")
	return g[0] if g.size() else null


func _refit() -> void:
	UiFit.refit_tree(self)
