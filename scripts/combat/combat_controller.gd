class_name CombatController
extends RefCounted
## CombatController — melee + stance combat execution shared by player & NPCs.
## Attacks run on explicit windup/active/recovery timelines; hits are validated
## against reach + arc so damage only lands when the swing visually connects.

signal died(cause: String)
signal attacked(attacker: Node3D, victim: Node3D, dmg: float)

var owner_node: Node3D
var anim: AnimDriver
var skeleton: Skeleton3D

var hp: float = 100.0
var max_hp: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0
var armor_prot: float = 0.0
var speed_mod: float = 1.0

var style_id: String = "brawler"
var style: Dictionary = {}
var in_combat: bool = false
var combat_timer: float = 0.0

# attack runtime
var attacking: bool = false
var attack_kind: String = ""
var attack_t: float = 0.0
var attack_dur: float = 0.5
var attack_hit_done: bool = false
var combo_idx: int = 0
var combo_window: float = 0.0
var queued_attack: String = ""

# defense runtime
var blocking: bool = false
var block_t: float = 0.0          # time since block started (parry window)
var dodging: bool = false
var dodge_t: float = 0.0
var dodge_dir: Vector3 = Vector3.FORWARD
var iframes: float = 0.0

# states
var counter_t: float = 0.0        # post-parry counter window
var stagger: float = 0.0          # accumulates; threshold -> knockdown
var stagger_decay: float = 0.0
var knocked: bool = false
var knock_t: float = 0.0
var dead: bool = false
var hit_flash: float = 0.0

var hostile_to: Callable = func(_n): return false    # set by owner
var is_player: bool = false

const TIMELINES := {
	"jab": [0.12, 0.10, 0.18], "cross": [0.14, 0.10, 0.22],
	"hook": [0.18, 0.12, 0.26], "upper": [0.20, 0.12, 0.30],
	"kick_r": [0.22, 0.14, 0.30], "kick_l": [0.22, 0.14, 0.30], "teep": [0.25, 0.12, 0.32],
	"heavy": [0.30, 0.14, 0.40], "throw": [0.25, 0.20, 0.45],
	"swing_h": [0.28, 0.14, 0.38], "swing_v": [0.30, 0.16, 0.42], "stab": [0.14, 0.08, 0.20],
	# mastery unlocks (Progression LADDER)
	"haymaker": [0.34, 0.16, 0.46], "kick_high": [0.26, 0.14, 0.34],
	"axe_kick": [0.36, 0.16, 0.48], "suplex": [0.30, 0.18, 0.52],
	"ground_pound": [0.24, 0.14, 0.40], "sway_strike": [0.18, 0.10, 0.26],
	"flurry": [0.10, 0.08, 0.16], "executioner": [0.30, 0.14, 0.44],
}


func setup(node: Node3D, driver: AnimDriver, sk: Skeleton3D, player: bool = false) -> void:
	owner_node = node
	anim = driver
	skeleton = sk
	is_player = player
	set_style("brawler")
	max_hp = 100.0
	hp = 100.0


func set_style(id: String) -> void:
	style_id = id
	style = Db.style(id)
	if style.is_empty():
		style = Db.style("brawler")


func current_reach() -> float:
	var base: float = style.get("reach", 1.0)
	var wid: String = ""
	if owner_node.has_method("melee_weapon_id"):
		wid = owner_node.melee_weapon_id()
	if wid != "":
		var wd := Db.weapon(wid)
		base = wd.get("reach", 1.0)
	return base * owner_node.get_meta("height_scale", 1.0)


func request_attack(kind: String) -> bool:
	if dead or knocked or dodging:
		return false
	if attacking:
		# allow queue during recovery for combos
		if attack_t > (TIMELINES[attack_kind][0] + TIMELINES[attack_kind][1]) / attack_dur:
			queued_attack = kind
		return false
	if stamina < 8.0:
		return false
	_start_attack(kind)
	return true


func _start_attack(kind: String) -> void:
	var tl = TIMELINES.get(kind, TIMELINES["jab"])
	attack_kind = kind
	attack_dur = (tl[0] + tl[1] + tl[2]) / style.get("speed", 1.0)
	attack_t = 0.0
	attacking = true
	attack_hit_done = false
	anim.mode = "attack"
	anim.attack_kind = kind
	anim.attack_style = style
	# stamina + sfx whoosh
	stamina = maxf(0.0, stamina - 7.0 * style.get("stamina_cost", 1.0))
	var w := "whoosh_light"
	if kind in ["heavy", "hook", "swing_h", "swing_v", "kick_r", "kick_l", "teep"]:
		w = "whoosh_heavy" if kind != "teep" else "whoosh_kick"
	if kind == "stab":
		w = "whoosh_light"
	AudioDirector.sfx(w, 0.1)
	in_combat = true
	combat_timer = 6.0


func tick(delta: float, move_dir: Vector3) -> Vector3:
	## Returns dodge impulse vector (added to owner movement).
	var impulse := Vector3.ZERO
	if dead:
		return impulse
	# stamina regen
	if not attacking and not dodging:
		stamina = minf(max_stamina, stamina + delta * (14.0 if not in_combat else 9.0))
	# combat cooldown
	if in_combat:
		combat_timer -= delta
		if combat_timer <= 0.0:
			in_combat = false
			if owner_node.has_method("on_combat_end"):
				owner_node.on_combat_end()
	# iframes
	iframes = maxf(0.0, iframes - delta)
	counter_t = maxf(0.0, counter_t - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	# stagger decay
	if stagger > 0.0:
		stagger_decay += delta
		if stagger_decay > 3.0:
			stagger = maxf(0.0, stagger - delta * 20.0)
	# dodge
	if dodging:
		dodge_t += delta / 0.55
		impulse = dodge_dir * 7.5 * (1.0 - dodge_t)
		anim.mode = "locomote"
		if dodge_t >= 1.0:
			dodging = false
	if knocked:
		knock_t += delta / 2.6
		anim.mode = "down" if knock_t < 0.55 else "getup"
		anim.down_t = clampf(knock_t / 0.55, 0, 1)
		anim.getup_t = clampf((knock_t - 0.55) / 0.45, 0, 1)
		if knock_t >= 1.0:
			knocked = false
			knock_t = 0.0
			stagger = 0.0
			anim.mode = "locomote"
	# attack timeline
	if attacking:
		attack_t += delta / attack_dur
		anim.attack_t = clampf(attack_t, 0, 1)
		var tl = TIMELINES.get(attack_kind, TIMELINES["jab"])
		var wind: float = tl[0] / (attack_dur * style.get("speed", 1.0))
		var act: float = (tl[0] + tl[1]) / (attack_dur * style.get("speed", 1.0))
		if attack_t >= wind and attack_t <= act and not attack_hit_done:
			_resolve_hit()
		if attack_t >= 1.0:
			attacking = false
			combo_window = 0.35
			var clen: int = int(style.get("combo_len", 3))
			if is_player:
				clen += Progression.combo_bonus(style_id)
			combo_idx = (combo_idx + 1) % maxi(1, clen)
			if queued_attack != "":
				var q := queued_attack
				queued_attack = ""
				_start_attack(q)
			else:
				anim.mode = "locomote"
	elif combo_window > 0.0:
		combo_window -= delta
	# block timer
	if blocking:
		block_t += delta
	else:
		block_t = 0.0
	return impulse


func start_dodge(dir: Vector3) -> bool:
	if dead or knocked or dodging or stamina < 12.0:
		return false
	dodging = true
	dodge_t = 0.0
	dodge_dir = dir.normalized()
	iframes = style.get("dodge_iframes", 0.28)
	stamina -= 12.0
	AudioDirector.sfx("dodge_roll", 0.1)
	in_combat = true
	combat_timer = 5.0
	return true


func set_block(b: bool) -> void:
	if b and not blocking:
		block_t = 0.0
	blocking = b and not attacking and not knocked and not dead


# ------------------------------------------------------------------ hits ---
func _resolve_hit() -> void:
	attack_hit_done = true
	var reach := current_reach() + 0.35
	var fwd := -owner_node.global_transform.basis.z
	var dmg := _damage_for(attack_kind)
	var targets := owner_node.get_tree().get_nodes_in_group("humanoid")
	for t in targets:
		if t == owner_node or not is_instance_valid(t):
			continue
		if not hostile_to.call(t):
			continue
		var to: Vector3 = (t.global_position - owner_node.global_position)
		to.y = 0
		var d := to.length()
		if d > reach or d < 0.15:
			continue
		if to.normalized().dot(fwd) < 0.35:
			continue   # arc check: must be in front
		var cc: CombatController = t.get("combat")
		if cc == null:
			continue
		# GROUND FINISHER: hitting a knocked target is a cinematic finisher
		var finisher := cc.knocked and not cc.dead
		if finisher:
			dmg *= 2.2
		if attack_kind == "executioner" and cc.stagger > 30.0:
			dmg *= 1.5                  # executioner bonus vs reeling targets
		cc.take_hit(dmg, fwd, attack_kind, owner_node)
		# connect feedback
		if finisher:
			AudioDirector.sfx_at("slam", t.global_position + Vector3(0, 1.0, 0))
			Effects.burst(t.global_position + Vector3(0, 1.0, 0) + fwd * 0.3, "blood", fwd)
			Effects.add_shake(0.5 if is_player else 0.15)
			if is_player:
				Bus.notification.emit("FINISHER!", "warn")
				Cinematics.hitstop(0.12)
				Cinematics.fov_punch(5.0)
		else:
			AudioDirector.sfx_at(style_hit_sound(attack_kind), t.global_position + Vector3(0, 1.3, 0))
			Effects.burst(t.global_position + Vector3(0, 1.3, 0) + fwd * 0.2, "blood", fwd)
			Effects.add_shake(0.25 if is_player else 0.0)
			if is_player and attack_kind in ["heavy", "haymaker", "axe_kick", "suplex", "ground_pound", "executioner", "swing_v", "env_slam", "kick_high"]:
				Cinematics.hitstop(0.07)
		if is_player and cc.dead:
			_last_kill_check(t)
		if is_player:
			if counter_t > 0.0:
				counter_t = 0.0
				AudioDirector.sfx_at("parry_clang", t.global_position + Vector3(0, 1.4, 0), 0.6)
				Bus.notification.emit("COUNTER!", "info")
			Progression.add_style_xp(style_id, 2.0 if finisher else 1.0)
			if cc.dead or (cc.knocked and not finisher):
				Progression.add_xp(int(15.0 + cc.max_hp * 0.12), "KO")
		attacked.emit(owner_node, t, dmg)


func _last_kill_check(victim: Node3D) -> void:
	## Last enemy within 30 m just died -> brief kill-cam slow-mo.
	for n in owner_node.get_tree().get_nodes_in_group("enemy"):
		if n == victim or not is_instance_valid(n):
			continue
		var c = n.get("combat")
		if c != null and not c.dead and (n.global_position - victim.global_position).length() < 30.0:
			return
	Cinematics.slowmo(0.55, 0.3)
	Cinematics.fov_punch(3.0)


func style_hit_sound(kind: String) -> String:
	if kind.begins_with("kick") or kind == "teep":
		return "kick_hit"
	if kind in ["heavy", "throw", "swing_h", "swing_v"]:
		return "punch_hit_heavy"
	return "punch_hit"


func _damage_for(kind: String) -> float:
	var s := style
	var base := 10.0
	match kind:
		"jab": base = s.get("punch_dmg", 10)
		"cross": base = s.get("punch_dmg", 10) * 1.2
		"hook": base = s.get("punch_dmg", 10) * 1.35
		"upper": base = s.get("punch_dmg", 10) * 1.3
		"kick_r", "kick_l": base = s.get("kick_dmg", 13) * s.get("kick_bonus", 1.0)
		"teep": base = s.get("kick_dmg", 13) * 0.8
		"heavy": base = s.get("heavy_dmg", 22)
		"throw": base = s.get("throw_dmg", 26)
		"swing_h": base = s.get("heavy_dmg", 22) * 1.1
		"swing_v": base = s.get("heavy_dmg", 22) * 1.2
		"stab": base = s.get("punch_dmg", 10) * 1.1
		"haymaker": base = s.get("heavy_dmg", 22) * 1.55
		"kick_high": base = s.get("kick_dmg", 13) * s.get("kick_bonus", 1.0) * 1.45
		"axe_kick": base = s.get("kick_dmg", 13) * s.get("kick_bonus", 1.0) * 1.9
		"suplex": base = s.get("throw_dmg", 26) * 1.5
		"ground_pound": base = s.get("heavy_dmg", 22) * 2.2
		"sway_strike": base = s.get("punch_dmg", 10) * 1.35
		"flurry": base = s.get("punch_dmg", 10) * 0.6
		"executioner": base = s.get("heavy_dmg", 22) * 1.7
	if counter_t > 0.0:
		base *= 1.6                     # parry -> counter strike
	if is_player:
		base *= Progression.dmg_mult(style_id)
	else:
		base *= Difficulty.enemy_dmg_mult()
	var wid := ""
	if owner_node.has_method("melee_weapon_id"):
		wid = owner_node.melee_weapon_id()
	if wid != "":
		base = Db.weapon(wid).get("dmg", base)
	if s.get("dmg_variance", 0.0) > 0.0:
		base *= randf_range(1.0 - s["dmg_variance"], 1.0 + s["dmg_variance"])
	return base


func take_hit(dmg: float, dir: Vector3, kind: String, attacker: Node3D) -> void:
	if dead or iframes > 0.0:
		return
	# dodge iframe handled above; block?
	var fwd := -owner_node.global_transform.basis.z
	var facing_attacker := dir.normalized().dot(fwd) < 0.2
	if dodging:
		return
	if blocking and facing_attacker:
		if block_t < 0.18:
			# PARRY
			AudioDirector.sfx_at("parry_clang", owner_node.global_position + Vector3(0, 1.4, 0))
			Effects.burst(owner_node.global_position + Vector3(0, 1.4, 0), "spark", dir)
			var ac: CombatController = attacker.get("combat")
			if ac:
				ac.apply_stagger(45.0, -dir)
			counter_t = 0.9 * Progression.counter_window_mult(style_id)
			if is_player:
				Bus.tutorial_hint.emit("counter")
			return
		var gs: float = style.get("guard_strength", 0.6)
		dmg *= (1.0 - gs * 0.8)
		AudioDirector.sfx_at("block_hit", owner_node.global_position + Vector3(0, 1.4, 0))
		apply_stagger(6.0, dir)
	else:
		dmg *= (1.0 - armor_prot)
		# SOFT COVER: crouched behind geometry halves incoming damage and
		# kills stagger (you're braced), but you still can't camp forever —
		# flanking AI (aggression) punishes turtles.
		if is_player and owner_node.get("in_cover"):
			dmg *= 0.45
			AudioDirector.sfx_at("block_hit", owner_node.global_position + Vector3(0, 0.8, 0), 0.5)
			hp -= dmg
			if hp <= 0.0:
				_die(kind, attacker)
			return
		var stag := dmg * float(style.get("stagger_bonus", 1.0)) * 0.9
		if is_player:
			stag *= 1.0 - Progression.stagger_resist(style_id)
		apply_stagger(stag, dir)
		AudioDirector.sfx_at("grunt_m_hit" if not _fem() else "grunt_f_hit",
			owner_node.global_position + Vector3(0, 1.4, 0))
		Effects.burst(owner_node.global_position + Vector3(0, 1.3, 0), "blood", dir)
		anim.hit_t = 0.0
		anim.hit_dir = 1.0 if dir.dot(fwd) < 0 else -1.0
	hp -= dmg
	hit_flash = 0.15
	in_combat = true
	combat_timer = 6.0
	if hp <= 0.0:
		_die(kind, attacker)


func _fem() -> bool:
	return owner_node.get_meta("fem", false)


func apply_stagger(amount: float, dir: Vector3) -> void:
	if knocked or dead:
		return
	stagger += amount
	stagger_decay = 0.0
	# push
	if owner_node is CharacterBody3D:
		(owner_node as CharacterBody3D).velocity += dir * amount * 1.6
	if stagger > 55.0:
		knockdown(dir)


func knockdown(dir: Vector3) -> void:
	knocked = true
	knock_t = 0.0
	stagger = 30.0
	attacking = false
	blocking = false
	anim.mode = "down"
	AudioDirector.sfx_at("body_fall", owner_node.global_position)
	if owner_node is CharacterBody3D:
		(owner_node as CharacterBody3D).velocity = dir * 2.0
	if is_player:
		Bus.notification.emit("You're down! Get up!", "warn")


func _die(cause: String, _attacker: Node3D) -> void:
	dead = true
	hp = 0.0
	anim.mode = "dead"
	attacking = false
	blocking = false
	AudioDirector.sfx_at("grunt_m_down" if not _fem() else "grunt_f_hit", owner_node.global_position + Vector3(0, 1.2, 0))
	AudioDirector.sfx_at("body_fall", owner_node.global_position)
	died.emit(cause)


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func revive() -> void:
	dead = false
	knocked = false
	hp = max_hp * 0.6
	stagger = 0.0
	anim.mode = "locomote"
