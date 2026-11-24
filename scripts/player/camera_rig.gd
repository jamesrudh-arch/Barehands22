extends Node3D
## CameraRig — third-person orbit camera: collision-aware spring arm,
## combat lock-on framing, FOV kicks, look-ahead, cinematic override hooks.
## Touch/mouse/stick agnostic: owner feeds look deltas.

var yaw: float = 0.0
var pitch: float = -12.0
var dist: float = 3.4
var dist_target: float = 3.4
var target: Node3D = null            # player
var lock_target: Node3D = null
var sensitivity: float = 1.0
var invert_y: bool = false
var shake_enabled: bool = true

var _cam: Camera3D
var _cur_pos: Vector3 = Vector3.ZERO
var _initialized := false
var fov_base: float = 68.0
var fov_kick: float = 0.0
var cin_active := false
var cin_transform: Transform3D = Transform3D()
# HIT-DIRECTION PUNCH: getting hit shoves the FRAME, not just the body —
# a short damped impulse opposite the blow direction (fight-game standard)
var _punch_vec: Vector3 = Vector3.ZERO
var _punch_t := 0.0
# dynamic combat framing: the camera widens when you're outnumbered
var _frame_wide := 0.0

const PITCH_MIN := -55.0
const PITCH_MAX := 35.0


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = fov_base
	_cam.near = 0.05
	_cam.far = 900.0
	add_child(_cam)
	Effects.register_camera(_cam)
	add_to_group("cam_rig")
	_apply_settings()
	Bus.settings_changed.connect(_apply_settings)
	Bus.player_damaged.connect(func(d: Vector3, amt: float):
		kick_dir(d, clampf(amt / 30.0, 0.25, 1.0)))


func _apply_settings() -> void:
	## the SETTINGS app promises these; make it true
	sensitivity = float(Game.settings.get("sensitivity", 1.0))
	invert_y = bool(Game.settings.get("invert_y", false))


func look(dx: float, dy: float) -> void:
	if cin_active:
		return
	yaw -= dx * 0.16 * sensitivity
	pitch -= dy * 0.12 * sensitivity * (-1.0 if invert_y else 1.0)
	pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)


func set_lock(node: Node3D) -> void:
	lock_target = node


func kick_fov(amount: float) -> void:
	fov_kick = minf(fov_kick + amount, 18.0)


func kick_dir(world_dir: Vector3, strength: float = 1.0) -> void:
	## shove the frame along world_dir (already normalized by caller)
	var d := world_dir
	d.y = 0.0
	if d.length_squared() < 0.001:
		return
	_punch_vec = d.normalized() * clampf(strength, 0.0, 1.0)
	_punch_t = 1.0


func start_cinematic() -> void:
	cin_active = true


func end_cinematic() -> void:
	cin_active = false


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if cin_active:
		_cam.global_transform = _cam.global_transform.interpolate_with(cin_transform, minf(1.0, delta * 6.0))
		return
	var focus := target.global_position + Vector3(0, 1.45, 0)
	if lock_target and is_instance_valid(lock_target):
		focus = focus.lerp(lock_target.global_position + Vector3(0, 1.2, 0), 0.35)
		dist_target = 4.2
	else:
		dist_target = 3.4
	# DYNAMIC COMBAT FRAMING: outnumbered -> pull back so threats stay
	# readable in frame (the reason fight cams in good games "breathe")
	var threats := 0
	var in_combat: bool = target.get("combat") != null and bool(target.combat.in_combat)
	if in_combat:
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or e.get("hostile") != true:
				continue
			var ec = e.get("combat")
			if ec == null or bool(ec.dead):
				continue
			if (e.global_position - target.global_position).length() < 14.0:
				threats += 1
	var wide_goal := 0.0
	if threats >= 3:
		wide_goal = 1.5
	elif threats == 2:
		wide_goal = 0.8
	elif threats == 1:
		wide_goal = 0.35
	_frame_wide = lerpf(_frame_wide, wide_goal, minf(1.0, delta * 3.0))
	dist_target += _frame_wide
	dist = lerpf(dist, dist_target, minf(1.0, delta * 5.0))
	# hit-direction punch: damped spring back to neutral
	if _punch_t > 0.0:
		_punch_t = maxf(0.0, _punch_t - delta * 4.5)
		focus -= _punch_vec * (sin(_punch_t * PI) * 0.22)
	# desired orbit position
	var dir := Vector3(
		sin(yaw) * cos(pitch * PI / 180.0),
		-sin(pitch * PI / 180.0),
		cos(yaw) * cos(pitch * PI / 180.0))
	var desired := focus + dir * dist
	# collision: ray from focus to desired, pull in on hit
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.from = focus
	q.to = desired
	q.collision_mask = 1 | 4     # world + vehicles
	q.exclude = [target.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = hit["position"] - dir * 0.18
	if not _initialized:
		_cur_pos = desired
		_initialized = true
	_cur_pos = _cur_pos.lerp(desired, minf(1.0, delta * 18.0))
	_cam.global_position = _cur_pos
	var look_at := focus
	# slight look-ahead with player velocity
	if target.has_method("get_velocity_look"):
		look_at += target.get_velocity_look()
	_cam.look_at(look_at, Vector3.UP)
	# fov kick decay
	fov_kick = maxf(0.0, fov_kick - delta * 24.0)
	var spd := 0.0
	if target.has_method("current_speed"):
		spd = target.current_speed()
	var target_fov := fov_base + clampf(spd * 1.1, 0.0, 8.0) + fov_kick
	_cam.fov = lerpf(_cam.fov, target_fov, minf(1.0, delta * 6.0))
