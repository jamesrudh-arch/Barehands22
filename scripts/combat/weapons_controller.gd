class_name WeaponsController
extends RefCounted
## WeaponsController — firearm state machine: equip, aim, fire (hitscan with
## spread/recoil/pellets), reload timeline, ammo reserves, impact reactions.
## Melee weapon identity lives in data/weapons.json + combat style "weapon".

signal ammo_changed_sig(mag: int, reserve: int)
signal shot_fired(origin: Vector3, point: Vector3)

var owner_node: Node3D
var anim: AnimDriver
var weapon_id: String = ""
var mag: int = 0
var reserves: Dictionary = {}     # weapon_id -> reserve ammo
var reloading: bool = false
var reload_t: float = 0.0
var fire_cooldown: float = 0.0
var recoil: float = 0.0
var _shots_fired: int = 0
var _pattern_pitch: float = 0.0
var _pattern_yaw: float = 0.0
var aim: bool = false
var owned: Array = []             # weapon ids owned

const MUZZLE_OFFSET := Vector3(0.12, 1.35, 0.55)


func setup(node: Node3D, driver: AnimDriver) -> void:
	owner_node = node
	anim = driver


func give(wid: String, full: bool = true) -> void:
	if wid not in owned:
		owned.append(wid)
	var w := Db.weapon(wid)
	if full:
		reserves[wid] = w.get("reserve", 30)
	if weapon_id == "":
		equip(wid)


func equip(wid: String) -> void:
	if wid == weapon_id or wid not in owned:
		return
	weapon_id = wid
	var w := Db.weapon(wid)
	mag = mini(int(w.get("mag", 12)), int(w.get("mag", 12)))
	reloading = false
	AudioDirector.sfx("reload_slide", 0.05)
	Bus.weapon_equipped.emit(wid)
	_emit_ammo()


func unequip() -> void:
	weapon_id = ""
	reloading = false
	Bus.weapon_equipped.emit("")


func cycle(dirn: int) -> void:
	if owned.is_empty():
		return
	var i := owned.find(weapon_id)
	i = (i + dirn + owned.size() * 4) % owned.size()
	equip(owned[i])


func def() -> Dictionary:
	## Base stats + fitted attachments (Ghost Recon-lite modding):
	## suppressor quiets & trims, ext-mag fattens, grip tames climb...
	var w: Dictionary = Db.weapon(weapon_id)
	var att: Dictionary = WorldState.weapon_attachments.get(weapon_id, {})
	if att.is_empty():
		return w
	w = w.duplicate()
	for slot in att:
		var a: Dictionary = Db.weapon(str(att[slot]))
		var mods: Dictionary = a.get("mods", {})
		if mods.has("dmg_mult"):
			w["dmg"] = float(w.get("dmg", 10)) * float(mods["dmg_mult"])
		if mods.has("spread_mult"):
			w["spread"] = float(w.get("spread", 1.5)) * float(mods["spread_mult"])
		if mods.has("recoil_mult"):
			w["recoil"] = float(w.get("recoil", 1.0)) * float(mods["recoil_mult"])
			var pat: Array = w.get("recoil_pattern", [])
			if not pat.is_empty():
				var np2: Array = []
				for v in pat:
					np2.append(float(v) * float(mods["recoil_mult"]))
				w["recoil_pattern"] = np2
		if mods.has("rpm_mult"):
			w["rpm"] = float(w.get("rpm", 300)) * float(mods["rpm_mult"])
		if mods.has("mag_add"):
			w["mag"] = int(w.get("mag", 12)) + int(mods["mag_add"])
			w["reload"] = float(w.get("reload", 1.6)) * 1.12
		if mods.has("sound"):
			w["sound"] = mods["sound"]
		if mods.has("crime_sev"):
			w["crime_sev"] = int(mods["crime_sev"])
	return w


func is_gun() -> bool:
	return def().get("kind", "") == "gun"


func can_fire() -> bool:
	return weapon_id != "" and is_gun() and not reloading and fire_cooldown <= 0.0 and mag > 0


func try_fire(auto: bool, delta: float, from: Vector3, direction: Vector3, shooter_is_player: bool) -> bool:
	fire_cooldown -= delta
	if fire_cooldown > 0.18:
		_shots_fired = 0        # pattern resets when the trigger rests
	if not can_fire():
		if mag <= 0 and not reloading and fire_cooldown <= 0.0:
			AudioDirector.sfx("dry_fire", 0.02)
			fire_cooldown = 0.4
			start_reload()
		return false
	var w := def()
	fire_cooldown = 60.0 / float(w.get("rpm", 300))
	mag -= 1
	recoil = minf(recoil + w.get("recoil", 1.0), 6.0)
	# patterned climb: each gun kicks differently shot-to-shot
	var pat: Array = w.get("recoil_pattern", [])
	var lat: Array = w.get("recoil_lateral", [])
	if not pat.is_empty():
		var i: int = _shots_fired % pat.size()
		_pattern_pitch = float(pat[i])
		_pattern_yaw = float(lat[i]) if i < lat.size() else 0.0
		_shots_fired += 1
	else:
		_pattern_pitch = float(w.get("recoil", 1.0)) * 1.2
		_pattern_yaw = 0.0
	# sfx + fx
	var muz := from + direction * 0.6
	AudioDirector.sfx_at(w.get("sound", "shot_pistol"), muz, 1.0, 0.05)
	Effects.burst(muz, "muzzle", direction)
	Effects.muzzle_flash_light(muz)
	if shooter_is_player:
		Effects.add_shake(0.10 * w.get("recoil", 1.0))
	# pellets
	var pellets: int = int(w.get("pellets", 1))
	for p in pellets:
		var spread: float = deg_to_rad(float(w.get("spread", 1.5))) * (0.45 if aim else 1.0)
		if shooter_is_player:
			spread *= 0.55 if owner_node.get("focus_active") else 1.0   # focus steadies the gun
			spread /= Progression.reload_speed_mult("weapon")     # weapon mastery = steadier hands
		var d := direction
		d = d.rotated(Vector3.UP, randf_range(-spread, spread))
		d = d.rotated(d.cross(Vector3.UP).normalized(), randf_range(-spread, spread))
		_hitscan(muz, d, w, shooter_is_player)
	_emit_ammo()
	shot_fired.emit(muz, from + direction * 40.0)
	# crime + awareness
	if shooter_is_player:
		var sev: int = int(w.get("crime_sev", 2))
		if sev > 0:
			Bus.crime_committed.emit("gunfire", sev, owner_node.global_position)
	return true


func _hitscan(from: Vector3, dir: Vector3, w: Dictionary, shooter_is_player: bool) -> void:
	var space := owner_node.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.from = from
	q.to = from + dir * float(w.get("range", 60))
	q.collision_mask = 1 | 2 | 4   # world | humanoids | vehicles
	q.exclude = [owner_node.get_rid()]
	var hit := space.intersect_ray(q)
	var end := q.to
	if not hit.is_empty():
		end = hit["position"]
		var obj: Object = hit["collider"]
		_impact(obj, hit, w, shooter_is_player)
	Effects.tracer(from, end)


func _impact(obj: Object, hit: Dictionary, w: Dictionary, shooter_is_player: bool) -> void:
	var pos: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	if obj is Node3D and obj.is_in_group("humanoid"):
		var cc: CombatController = obj.get("combat")
		if cc:
			var dmg: float = float(w.get("dmg", 20))
			if shooter_is_player:
				dmg *= 1.0
			cc.take_hit(dmg, (obj.global_position - owner_node.global_position).normalized() * -1.0, "bullet", owner_node)
			if shooter_is_player:
				Bus.crime_committed.emit("assault", 3, pos)
		return
	if obj is Node3D and obj.is_in_group("vehicle"):
		AudioDirector.sfx_at("imp_metal", pos)
		Effects.burst(pos, "spark", nrm)
		if obj.has_method("damage"):
			obj.damage(float(w.get("dmg", 20)) * 0.5)
		return
	# world surface
	var mat := "concrete"
	AudioDirector.sfx_at("imp_" + mat, pos, 0.8)
	Effects.burst(pos, "spark", nrm)
	Effects.decal(pos, nrm, "scorch", 0.25)


func start_reload() -> bool:
	if reloading or weapon_id == "" or not is_gun():
		return false
	var w := def()
	if mag >= int(w.get("mag", 12)) or reserves.get(weapon_id, 0) <= 0:
		return false
	reloading = true
	reload_t = 0.0
	AudioDirector.sfx("reload_magout", 0.04)
	return true


func tick(delta: float) -> void:
	if reloading:
		reload_t += delta
		var w := def()
		var total: float = float(w.get("reload", 1.6))
		if owner_node.is_in_group("player"):
			total /= Progression.reload_speed_mult("weapon")
		if reload_t > total * 0.45 and reload_t - delta <= total * 0.45:
			AudioDirector.sfx("reload_magin", 0.04)
		if reload_t >= total:
			var need: int = int(w.get("mag", 12)) - mag
			var take: int = mini(need, reserves.get(weapon_id, 0))
			mag += take
			reserves[weapon_id] = reserves.get(weapon_id, 0) - take
			reloading = false
			AudioDirector.sfx("reload_slide", 0.04)
			_emit_ammo()
	recoil = maxf(0.0, recoil - delta * 8.0)


func add_ammo(wid: String, amount: int) -> void:
	reserves[wid] = reserves.get(wid, 0) + amount


func _emit_ammo() -> void:
	Bus.ammo_changed.emit(mag, reserves.get(weapon_id, 0))
	ammo_changed_sig.emit(mag, reserves.get(weapon_id, 0))
