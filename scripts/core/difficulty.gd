extends Node
## Difficulty — the escalating-threat director.
##
## Design rule (from requirements): the game must get HARDER as the story
## advances, and nothing is artificially capped — enemy counts, police
## response and crowd density all scale with threat. Mobile performance is
## protected by streaming/culling radii (existing), not by tiny hard caps.
##
## Threat is derived from real progress, never from a menu slider:
##   - story missions completed (0..12)  -> the dominant term
##   - player level                       -> rewards progression
##   - recent deaths                      -> light rubber-band relief so a
##                                           stuck player gets a breather
## Threat is clamped 0..1.6 (late game can exceed 1.0 — no ceiling on pain).
##
## The DIFFICULTY PRESET does not replace that rule, it scales it. A preset is
## a single multiplier on the progress-derived curve, so a Street player still
## escalates exactly as the story advances — just along a gentler slope, with
## the same headroom at the top. Nothing is flattened and nothing is a flat
## stat bonus bolted on beside the real director.

const STORY_TOTAL := 12.0

## Presets, in menu order. `mult` scales threat and only threat, so every
## consumer (enemy HP/damage/accuracy/aggression/loadout, mission wave counts,
## police cap and dispatch, crowd + traffic density, fight purses) moves
## together and stays internally consistent.
const PRESETS := [
	{"id": "street", "name": "STREET", "mult": 0.72,
	 "desc": "The city still keeps score, but it lets you keep some of your teeth."},
	{"id": "ledger", "name": "LEDGER", "mult": 1.0,
	 "desc": "As authored. Threat climbs with the story and nothing is forgiven."},
	{"id": "crowe", "name": "CROWE", "mult": 1.34,
	 "desc": "Somebody is reading your book too. Harder hits, more of them, faster."},
]

var _deaths_since_clear := 0
## Index into PRESETS. Persisted through Game.settings["difficulty"], NOT the
## save file: it is a player preference, so it survives starting a new game.
var preset: int = 1


func reset() -> void:
	_deaths_since_clear = 0


# ----------------------------------------------------------------- presets --
func preset_count() -> int:
	return PRESETS.size()


func preset_mult() -> float:
	var i := clampi(preset, 0, PRESETS.size() - 1)
	return float(PRESETS[i]["mult"])


func preset_name(i: int = -999) -> String:
	var k := clampi(i if i != -999 else preset, 0, PRESETS.size() - 1)
	return String(PRESETS[k]["name"])


func preset_desc(i: int = -999) -> String:
	var k := clampi(i if i != -999 else preset, 0, PRESETS.size() - 1)
	return String(PRESETS[k]["desc"])


func set_preset(i: int, announce: bool = true) -> void:
	var k := clampi(i, 0, PRESETS.size() - 1)
	if k == preset and not announce:
		return
	preset = k
	if announce:
		Bus.notification.emit("DIFFICULTY — %s" % preset_name(), "info")
		AudioDirector.sfx("ui_confirm", 0.3)
	Bus.settings_changed.emit()


func note_death() -> void:
	_deaths_since_clear += 1


func note_mission_cleared() -> void:
	_deaths_since_clear = 0


func threat() -> float:
	var story := 0.0
	var mm := _mm()
	if mm:
		for mid in mm.completed.keys():
			if str(mid).begins_with("m"):
				story += 1.0
	story = clampf(story / STORY_TOTAL, 0.0, 1.0)
	var lvl: float = clampf(float(Progression.level - 1) / 14.0, 0.0, 1.0)
	var relief: float = clampf(float(_deaths_since_clear) * 0.08, 0.0, 0.24)
	# Shape first, then scale. The clamp scales with the preset so Crowe keeps
	# the same late-game headroom instead of saturating at the Ledger ceiling.
	var base := clampf(story * 0.75 + lvl * 0.35 - relief, 0.0, 1.6)
	var m := preset_mult()
	return clampf(base * m, 0.0, 1.6 * m)


# ------------------------------------------------------------ enemy stats --
func enemy_hp_mult() -> float:
	return 1.0 + threat() * 1.3


func enemy_dmg_mult() -> float:
	return 1.0 + threat() * 0.9


## Added to gunner base hit chance (they also keep distance falloff).
func accuracy_bonus() -> float:
	return threat() * 0.16


## Melee enemies re-evaluate tactics faster and flank more often with threat.
func aggression() -> float:
	return clampf(0.35 + threat() * 0.5, 0.0, 1.0)


## Higher threat: thugs arrive armed/armoured instead of fists-only.
func loadout_roll() -> float:
	return clampf(threat() * 0.55, 0.0, 0.75)


# ------------------------------------------------------------------ counts --
## Mission enemy counts scale UP from the authored base (never below it).
func scale_count(base: int) -> int:
	return maxi(base, int(round(float(base) * (1.0 + threat() * 0.8))))


## Police presence: the old flat cap of 8 units is gone. Cap grows with
## threat; dispatch per incident grows with wanted level + threat.
func police_cap() -> int:
	return 4 + int(threat() * 12.0)          # 4 .. 23


func dispatch_count(wanted: int) -> int:
	return clampi(wanted + int(threat() * 3.0), 1, 8)


## Crowd + traffic targets (city_life applies culling radii for perf).
func ped_target(base: int) -> int:
	return base + int(threat() * 14.0)       # 26 .. 47


func traffic_target(base: int) -> int:
	return base + int(threat() * 8.0)        # 12 .. 24


## Fight-club purse + challenger escalate with the player's reputation.
func fight_purse(base: int) -> int:
	return int(float(base) * (1.0 + threat() * 0.6))


func _mm() -> Node:
	return get_node_or_null("/root/MissionManager")
