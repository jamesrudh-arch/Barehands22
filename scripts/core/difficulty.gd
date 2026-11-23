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

const STORY_TOTAL := 12.0

var _deaths_since_clear := 0


func reset() -> void:
	_deaths_since_clear = 0


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
	return clampf(story * 0.75 + lvl * 0.35 - relief, 0.0, 1.6)


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
