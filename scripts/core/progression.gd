extends Node
## Progression — XP, levels, and per-style mastery with unlockable moves.
##
## Every fight you win and job you pull makes Marcus... makes Eli better.
## Levels raise the floor (HP/stamina/damage); style mastery raises the
## ceiling: each discipline has a 5-rank ladder, and ranks unlock real new
## moves (new attack kinds the combat controller already understands) plus
## passive bonuses. Using a style is how you grow it — no menu-grinding.

signal leveled_up(level: int)
signal style_ranked_up(style_id: String, rank: int, unlock: String)

# rank -> unlock description per style. "" = passive/stat bump only.
const LADDER := {
	"brawler": [
		"", "haymaker", "", "combo_len+1", "iron_jaw"],
	"kickboxing": [
		"", "kick_high", "", "combo_len+1", "axe_kick"],
	"grappling": [
		"", "suplex", "", "throw_dmg+25%", "ground_pound"],
	"drunken": [
		"", "sway_strike", "", "counter_window+40%", "flurry"],
	"weapon": [
		"", "swing_v", "", "reload_speed+20%", "executioner"],
}
const MOVE_NAMES := {
	"haymaker": "HAYMAKER (hold-charge heavy)",
	"kick_high": "HIGH KICK",
	"axe_kick": "AXE KICK (finisher)",
	"suplex": "SUPLEX",
	"ground_pound": "GROUND POUND (downed finisher)",
	"sway_strike": "SWAY STRIKE",
	"flurry": "DRUNKEN FLURRY",
	"swing_v": "VERTICAL SWING",
	"executioner": "EXECUTIONER (bonus vs staggered)",
	"combo_len+1": "EXTENDED COMBOS",
	"throw_dmg+25%": "THROW DAMAGE +25%",
	"counter_window+40%": "WIDER COUNTER WINDOW",
	"iron_jaw": "IRON JAW (stagger resist)",
	"reload_speed+20%": "FASTER RELOADS",
}

var xp := 0
var level := 1
var style_xp := {"brawler": 0.0, "kickboxing": 0.0, "grappling": 0.0, "drunken": 0.0, "weapon": 0.0}


func reset() -> void:
	xp = 0
	level = 1
	for k in style_xp:
		style_xp[k] = 0.0


func xp_for_next() -> int:
	return int(120.0 * pow(float(level), 1.35))


func add_xp(amount: int, reason: String = "") -> void:
	xp += amount
	var ups := 0
	while xp >= xp_for_next():
		xp -= xp_for_next()
		level += 1
		ups += 1
	if ups > 0:
		leveled_up.emit(level)
		Bus.notification.emit("LEVEL %d%s" % [level, (" — " + reason) if reason != "" else ""], "mission")
		AudioDirector.sfx("ui_confirm", 0.3)
		_apply_level_stats()


func refresh() -> void:
	_apply_level_stats()


func _apply_level_stats() -> void:
	var pg := get_tree().get_nodes_in_group("player")
	if pg.is_empty():
		return
	var p: Node = pg[0]
	if p.combat:
		p.combat.max_hp = 100.0 + float(level - 1) * 8.0
		p.combat.hp = p.combat.max_hp
		p.combat.max_stamina = 100.0 + float(level - 1) * 5.0


# ------------------------------------------------------------ style ranks --
func style_rank(id: String) -> int:
	# rank 1..5 from style xp; each rank needs 100 * rank^1.25 cumulative
	var total: float = style_xp.get(id, 0.0)
	var rank := 1
	var need := 0.0
	for r in range(1, 5):
		need += 100.0 * pow(float(r), 1.25)
		if total >= need:
			rank = r + 1
	return rank


func add_style_xp(id: String, amount: float) -> void:
	if not style_xp.has(id):
		return
	var before: int = style_rank(id)
	style_xp[id] += amount
	var after: int = style_rank(id)
	if after > before:
		var unlock: String = LADDER.get(id, ["", "", "", "", ""])[after - 1]
		style_ranked_up.emit(id, after, unlock)
		var nm: String = MOVE_NAMES.get(unlock, unlock.to_upper())
		Bus.notification.emit("%s MASTERY %d — unlocked %s" % [Db.style(id).get("label", id), after, nm], "mission")
		AudioDirector.sfx("ui_confirm", 0.35)


## Moves available to a style at current mastery (base pool + unlocks).
func unlocked_moves(id: String) -> Array:
	var out: Array = []
	var ladder: Array = LADDER.get(id, [])
	var rank := style_rank(id)
	for r in range(1, mini(rank, ladder.size()) + 1):
		var u: String = ladder[r - 1]
		if u != "" and not u.contains("+"):
			out.append(u)
	return out


func has_move(id: String, move: String) -> bool:
	return move in unlocked_moves(id)


## Passive queries used by the combat controller.
func combo_bonus(id: String) -> int:
	return 1 if style_rank(id) >= 4 and "combo_len+1" in LADDER.get(id, []) else 0


func dmg_mult(id: String) -> float:
	var m := 1.0
	if id == "grappling" and style_rank(id) >= 4:
		m += 0.25
	# global level damage bump: +2% per level
	m += float(level - 1) * 0.02
	return m


func stagger_resist(id: String) -> float:
	return 0.35 if (id == "brawler" and style_rank(id) >= 5) else 0.0


func counter_window_mult(id: String) -> float:
	return 1.4 if (id == "drunken" and style_rank(id) >= 4) else 1.0


func reload_speed_mult(id: String) -> float:
	return 1.25 if (id == "weapon" and style_rank(id) >= 4) else 1.0


# ------------------------------------------------------------------ save ---
func serialize() -> Dictionary:
	return {"xp": xp, "level": level, "style_xp": style_xp.duplicate()}


func apply_save(d: Dictionary) -> void:
	xp = int(d.get("xp", 0))
	level = int(d.get("level", 1))
	var sx: Dictionary = d.get("style_xp", {})
	for k in style_xp:
		style_xp[k] = float(sx.get(k, 0.0))
