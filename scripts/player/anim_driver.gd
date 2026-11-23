class_name AnimDriver
extends RefCounted
## AnimDriver — procedural skeletal animation for LEVERAGE humanoids.
## No canned clips: every pose is computed from state (gait phase locked to
## ground speed => no foot slide), style stance data, attack curve keyframes,
## reactions and activity poses, blended with stiffness for smooth transitions.

var sk: Skeleton3D
var cur: Dictionary = {}        # bone -> Vector3 euler degrees (current, smoothed)
var root_off: Vector3 = Vector3.ZERO
var phase: float = 0.0
var idle_t: float = 0.0
var look_dir: Vector3 = Vector3.ZERO
var talk_t: float = -1.0
var stiffness: float = 14.0

# state inputs (set by owner each frame)
var mode: String = "locomote"   # locomote|attack|hit|down|getup|drive|ride|sit|talk|listen|carry|dead|search
var speed: float = 0.0          # m/s ground speed
var speed01: float = 0.0        # 0..1 walk..run
var sprint: bool = false
var crouch: bool = false
var strafe: float = 0.0
var facing_delta: float = 0.0   # rad/s turning
var air_t: float = 0.0          # >0 when airborne (jump/fall)
var land_t: float = 0.0         # 0..1 landing absorb
var attack_kind: String = ""    # jab|cross|hook|upper|kick_r|teep|heavy|throw|swing_h|swing_v|stab|aim_shot
var attack_t: float = 0.0       # 0..1
var attack_style: Dictionary = {}
var block: bool = false
var aiming: bool = false
var steer: float = 0.0        # -1..1 steering input while driving
var veh_speed01: float = 0.0  # 0..1 speed fraction while driving
var veh_lean: float = 0.0     # bike lean -1..1
var stagger: float = 0.0        # 0..1
var down_t: float = -1.0        # 0..1 knocked down
var getup_t: float = -1.0
var hit_t: float = -1.0
var hit_dir: float = 1.0
var carry: bool = false
var lean: float = 0.0           # vehicle/bike lean deg
var gesture_seed: int = 0

const B := Humanoid.BI


func attach(skeleton: Skeleton3D) -> void:
	sk = skeleton
	cur.clear()
	for bn in Humanoid.BONES:
		cur[bn] = Vector3.ZERO


# ------------------------------------------------------------------ utils --
func _p(pose: Dictionary, bone: String, x: float, y: float, z: float) -> void:
	pose[bone] = pose.get(bone, Vector3.ZERO) + Vector3(x, y, z)


func _setp(pose: Dictionary, bone: String, v: Vector3) -> void:
	pose[bone] = v


func _curve(t: float, keys: Array) -> float:
	# keys: [ [t0,v0], [t1,v1], ... ] smoothstep between
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(keys.size() - 1):
		if t <= keys[i + 1][0]:
			var u: float = (t - keys[i][0]) / maxf(0.0001, keys[i + 1][0] - keys[i][0])
			u = u * u * (3 - 2 * u)
			return lerpf(keys[i][1], keys[i + 1][1], u)
	return keys[keys.size() - 1][1]


# ------------------------------------------------------------- pose layers --
func _stance(pose: Dictionary, st: Dictionary) -> void:
	var leanf: float = st.get("lean", 0.12) * 30.0
	var guard: float = st.get("guard_h", 0.6)
	var feet: float = st.get("feet", 0.5)
	var sway: float = st.get("sway", 0.15)
	_setp(pose, "hips", Vector3(0, 8.0, 0))
	_setp(pose, "spine", Vector3(-leanf * 0.3, -6.0, 0))
	_setp(pose, "chest", Vector3(-leanf * 0.5, -8.0, 0))
	# guard arms
	for sgn in [1.0, -1.0]:
		var side := "l" if sgn > 0 else "r"
		_setp(pose, "shoulder_" + side, Vector3(0, 0, -sgn * 6.0))
		_setp(pose, "upper_arm_" + side, Vector3(-30.0 - guard * 25.0, 0, -sgn * (14.0 + feet * 8.0)))
		_setp(pose, "forearm_" + side, Vector3(-55.0 - guard * 30.0, 0, sgn * 10.0))
		_setp(pose, "hand_" + side, Vector3(-15.0, 0, 0))
	# feet stagger
	_setp(pose, "thigh_l", Vector3(-6.0 - feet * 8.0, 0, -4.0))
	_setp(pose, "thigh_r", Vector3(8.0 + feet * 8.0, 0, 4.0))
	_setp(pose, "shin_l", Vector3(6.0, 0, 0))
	_setp(pose, "shin_r", Vector3(10.0, 0, 0))
	if sway > 0.3:
		var s := sin(idle_t * 1.7) * sway
		_p(pose, "hips", 0, 0, s * 8.0)
		_p(pose, "chest", 0, 0, -s * 6.0)
		_p(pose, "head", 0, 0, s * 5.0)


func _idle_breath(pose: Dictionary, amp: float = 1.0) -> void:
	var b := sin(idle_t * 1.9) * amp
	var w := sin(idle_t * 0.53) * amp   # weight shift
	_p(pose, "chest", b * 1.2, 0, 0)
	_p(pose, "hips", 0, 0, w * 2.5)
	_p(pose, "spine", 0, -w * 1.5, 0)
	# look-around
	var lk := sin(idle_t * 0.31) * 10.0 * amp
	_p(pose, "head", 0, lk, 0)
	_p(pose, "neck", 0, lk * 0.4, 0)


func _gait(pose: Dictionary, sp01: float, spr: bool) -> void:
	var amp := lerpf(18.0, 42.0, sp01) + (14.0 if spr else 0.0)
	var s := sin(phase)
	var c := cos(phase)
	var knee := lerpf(20.0, 55.0, sp01) + (25.0 if spr else 0.0)
	_p(pose, "thigh_l", -s * amp, 0, 0)
	_p(pose, "thigh_r", s * amp, 0, 0)
	_p(pose, "shin_l", maxf(0.0, -sin(phase + 0.9)) * knee + 6.0, 0, 0)
	_p(pose, "shin_r", maxf(0.0, -sin(phase + 0.9 + PI)) * knee + 6.0, 0, 0)
	_p(pose, "foot_l", maxf(0.0, c) * 14.0 - 6.0, 0, 0)
	_p(pose, "foot_r", maxf(0.0, -c) * 14.0 - 6.0, 0, 0)
	# arm swing (reduced if guarding)
	var asw := lerpf(26.0, 46.0, sp01) * (0.45 if mode == "locomote" and speed > 0.5 else 0.3)
	_p(pose, "upper_arm_l", s * asw, 0, 0)
	_p(pose, "upper_arm_r", -s * asw, 0, 0)
	_p(pose, "forearm_l", -absf(s) * 18.0 - 12.0, 0, 0)
	_p(pose, "forearm_r", -absf(c) * 18.0 - 12.0, 0, 0)
	# torso counter-rotation + bob
	_p(pose, "chest", 0, -s * 6.0, 0)
	_p(pose, "hips", 0, s * 4.0, c * 2.0)
	var bob := absf(sin(phase * 1.0)) * lerpf(0.012, 0.045, sp01)
	root_off.y -= bob
	# forward lean with speed
	_p(pose, "spine", -lerpf(2.0, 12.0, sp01) - (6.0 if spr else 0.0), 0, 0)


func _crouch_pose(pose: Dictionary) -> void:
	_p(pose, "hips", 25.0, 0, 0)
	_p(pose, "thigh_l", -50.0, 0, 0)
	_p(pose, "thigh_r", -50.0, 0, 0)
	_p(pose, "shin_l", 70.0, 0, 0)
	_p(pose, "shin_r", 70.0, 0, 0)
	_p(pose, "foot_l", -25.0, 0, 0)
	_p(pose, "foot_r", -25.0, 0, 0)
	_p(pose, "spine", 18.0, 0, 0)
	root_off.y -= 0.42


func _air_pose(pose: Dictionary, t: float) -> void:
	_p(pose, "thigh_l", -45.0, 0, 0)
	_p(pose, "thigh_r", -20.0, 0, 0)
	_p(pose, "shin_l", 60.0, 0, 0)
	_p(pose, "shin_r", 35.0, 0, 0)
	_p(pose, "upper_arm_l", -40.0, 0, -25.0)
	_p(pose, "upper_arm_r", -40.0, 0, 25.0)
	_p(pose, "forearm_l", -50.0, 0, 0)
	_p(pose, "forearm_r", -50.0, 0, 0)


func _land_pose(pose: Dictionary, t: float) -> void:
	var k := sin(clampf(t, 0, 1) * PI)
	_p(pose, "hips", 30.0 * k, 0, 0)
	_p(pose, "thigh_l", -35.0 * k, 0, 0)
	_p(pose, "thigh_r", -35.0 * k, 0, 0)
	_p(pose, "shin_l", 50.0 * k, 0, 0)
	_p(pose, "shin_r", 50.0 * k, 0, 0)
	_p(pose, "spine", 20.0 * k, 0, 0)
	_p(pose, "upper_arm_l", -20.0 * k, 0, -20.0 * k)
	_p(pose, "upper_arm_r", -20.0 * k, 0, 20.0 * k)
	root_off.y -= 0.15 * k


# ---------------------------------------------------------------- attacks ---
func _attack_pose(pose: Dictionary) -> void:
	var t := attack_t
	var st := attack_style
	# mastery-unlock moves reuse and intensify base poses
	var k := attack_kind
	match k:
		"haymaker": k = "heavy"
		"kick_high": k = "kick_r"
		"axe_kick": k = "kick_r"
		"suplex": k = "throw"
		"ground_pound": k = "heavy"
		"sway_strike": k = "hook"
		"flurry": k = "jab"
		"executioner": k = "swing_v"
	match k:
		"jab", "cross":
			var side := "l" if k == "jab" else "r"
			var o := "r" if side == "l" else "l"
			var ext := _curve(t, [[0, 0], [0.3, 1], [0.55, 1], [1, 0]])
			var wind := _curve(t, [[0, 0], [0.15, 1], [0.3, 0]])
			_p(pose, "upper_arm_" + side, -lerpf(30.0, 88.0, ext) - wind * 10.0, 0, 0)
			_p(pose, "forearm_" + side, -lerpf(80.0, 4.0, ext), 0, 0)
			_p(pose, "chest", 0, -18.0 * ext * (1 if side == "r" else -1), 0)
			_p(pose, "hips", 0, 10.0 * ext * (1 if side == "r" else -1), 0)
			_p(pose, "upper_arm_" + o, -35.0, 0, 0)
			_p(pose, "forearm_" + o, -85.0, 0, 0)
			# step
			_p(pose, "thigh_" + side, -14.0 * ext, 0, 0)
			_p(pose, "thigh_" + o, 10.0 * ext, 0, 0)
		"hook":
			var ext := _curve(t, [[0, 0], [0.25, 0.6], [0.45, 1], [1, 0]])
			_p(pose, "upper_arm_l", -55.0, -lerpf(-20.0, 75.0, ext), 0)
			_p(pose, "forearm_l", -70.0, 0, 0)
			_p(pose, "chest", 0, lerpf(15.0, -35.0, ext), 0)
			_p(pose, "hips", 0, lerpf(8.0, -20.0, ext), 0)
			_p(pose, "forearm_r", -90.0, 0, 0)
		"upper":
			var ext := _curve(t, [[0, 0], [0.2, -0.3], [0.5, 1], [1, 0]])
			_p(pose, "upper_arm_r", -lerpf(40.0, -35.0, clampf(ext, -0.3, 1)), 0, 0)
			_p(pose, "forearm_r", -lerpf(100.0, 10.0, clampf(ext, 0.0, 1)), 0, 0)
			_p(pose, "hips", -8.0 * ext, 0, 0)
			_p(pose, "spine", -10.0 * ext, 0, 0)
		"kick_r", "kick_l":
			var side := k.right(1)
			var o := "l" if side == "r" else "r"
			var raise := _curve(t, [[0, 0], [0.35, 1], [0.6, 1], [1, 0]])
			var snap := _curve(t, [[0, 0], [0.3, 0.2], [0.5, 1], [0.75, 0.4], [1, 0]])
			_p(pose, "thigh_" + side, -lerpf(0.0, 85.0, raise), 0, 0)
			_p(pose, "shin_" + side, lerpf(20.0, 95.0, 1.0 - snap), 0, 0)
			_p(pose, "hips", 0, 0, -10.0 * raise * (1 if side == "r" else -1))
			_p(pose, "chest", 8.0 * raise, 12.0 * raise * (1 if side == "r" else -1), 0)
			_p(pose, "upper_arm_l", -30.0, 0, -30.0 * raise)
			_p(pose, "upper_arm_r", -20.0, 0, 35.0 * raise)
			_p(pose, "thigh_" + o, 6.0, 0, 0)
		"teep":
			var ext := _curve(t, [[0, 0], [0.4, 1], [0.65, 1], [1, 0]])
			_p(pose, "thigh_r", -lerpf(10.0, 70.0, ext), 0, 0)
			_p(pose, "shin_r", lerpf(60.0, 5.0, ext), 0, 0)
			_p(pose, "spine", 12.0 * ext, 0, 0)
			_p(pose, "upper_arm_l", -40.0, 0, -20.0)
			_p(pose, "upper_arm_r", -25.0, 0, 25.0)
		"heavy":
			var wind := _curve(t, [[0, 0], [0.3, 1], [0.45, 1], [0.5, 0]])
			var slam := _curve(t, [[0.45, 0], [0.62, 1], [1, 0.2]])
			_p(pose, "upper_arm_r", -lerpf(30.0, -70.0, wind) - slam * 60.0, 0, lerp(20.0, -15.0, slam))
			_p(pose, "forearm_r", -lerpf(60.0, 120.0, wind) + slam * 100.0, 0, 0)
			_p(pose, "chest", 0, lerpf(25.0, -30.0, slam), 0)
			_p(pose, "hips", 0, lerpf(15.0, -18.0, slam), 0)
			_p(pose, "spine", -8.0 * slam, 0, 0)
			_p(pose, "thigh_l", -10.0 * slam, 0, 0)
		"throw":
			var grab := _curve(t, [[0, 0], [0.2, 1], [0.5, 1], [1, 0]])
			var twist := _curve(t, [[0.3, 0], [0.55, 1], [0.8, 1], [1, 0.3]])
			_p(pose, "upper_arm_l", -lerpf(30.0, 70.0, grab), 0, -20.0 * grab)
			_p(pose, "upper_arm_r", -lerpf(30.0, 70.0, grab), 0, 20.0 * grab)
			_p(pose, "forearm_l", -lerpf(70.0, 30.0, grab), 0, 0)
			_p(pose, "forearm_r", -lerpf(70.0, 30.0, grab), 0, 0)
			_p(pose, "hips", 10.0 * grab, -50.0 * twist, 0)
			_p(pose, "chest", -10.0 * grab, -30.0 * twist, 0)
			_p(pose, "spine", 15.0 * twist, 0, 0)
		"swing_h", "swing_v", "stab":
			var wind := _curve(t, [[0, 0], [0.3, 1], [0.42, 1], [0.5, 0]])
			var cut := _curve(t, [[0.42, 0], [0.6, 1], [1, 0.15]])
			if attack_kind == "swing_h":
				_p(pose, "upper_arm_r", -40.0, lerpf(-60.0, 70.0, cut) - wind * 40.0, 0)
				_p(pose, "forearm_r", -lerpf(90.0, 10.0, cut), 0, 0)
				_p(pose, "upper_arm_l", -45.0, 20.0 - cut * 40.0, 0)
				_p(pose, "chest", 0, lerpf(30.0, -35.0, cut), 0)
				_p(pose, "hips", 0, lerpf(18.0, -22.0, cut), 0)
			elif attack_kind == "swing_v":
				_p(pose, "upper_arm_r", -lerpf(-80.0, 60.0, cut) - wind * 30.0, 0, 10.0)
				_p(pose, "forearm_r", -lerpf(40.0, 5.0, cut), 0, 0)
				_p(pose, "upper_arm_l", -lerpf(-70.0, 50.0, cut), 0, -10.0)
				_p(pose, "spine", -15.0 * cut, 0, 0)
			else:
				var ext := _curve(t, [[0, 0], [0.35, 1], [0.6, 1], [1, 0]])
				_p(pose, "upper_arm_r", -lerpf(20.0, 85.0, ext), 0, 5.0)
				_p(pose, "forearm_r", -lerpf(95.0, 5.0, ext), 0, 0)
				_p(pose, "chest", 0, -12.0 * ext, 0)
		"aim_shot":
			_p(pose, "upper_arm_l", -78.0, 0, -12.0)
			_p(pose, "upper_arm_r", -80.0, 0, 8.0)
			_p(pose, "forearm_l", -18.0, 0, 8.0)
			_p(pose, "forearm_r", -6.0, 0, 0)
			_p(pose, "head", -4.0, 0, 0)


func _block_pose(pose: Dictionary) -> void:
	_p(pose, "upper_arm_l", -55.0, 0, -22.0)
	_p(pose, "upper_arm_r", -55.0, 0, 22.0)
	_p(pose, "forearm_l", -95.0, 0, 18.0)
	_p(pose, "forearm_r", -95.0, 0, -18.0)
	_p(pose, "chest", 8.0, 0, 0)
	_p(pose, "head", 8.0, 0, 0)


func _hit_pose(pose: Dictionary, t: float) -> void:
	var k := sin(clampf(t, 0, 1) * PI)
	_p(pose, "chest", 14.0 * k * hit_dir, 0, -6.0 * k)
	_p(pose, "head", 18.0 * k * hit_dir, 0, 0)
	_p(pose, "hips", -6.0 * k, 0, 0)
	_p(pose, "upper_arm_l", -10.0 * k, 0, -18.0 * k)
	_p(pose, "upper_arm_r", -10.0 * k, 0, 18.0 * k)


func _down_pose(pose: Dictionary, t: float) -> void:
	var k := clampf(t * 2.0, 0, 1)
	_setp(pose, "hips", Vector3(-70.0 * k, 0, 0))
	_setp(pose, "spine", Vector3(-20.0 * k, 0, 0))
	_setp(pose, "thigh_l", Vector3(35.0 * k, 0, -8.0 * k))
	_setp(pose, "thigh_r", Vector3(25.0 * k, 0, 8.0 * k))
	_setp(pose, "shin_l", Vector3(50.0 * k, 0, 0))
	_setp(pose, "shin_r", Vector3(60.0 * k, 0, 0))
	_setp(pose, "upper_arm_l", Vector3(-30.0 * k, 0, -40.0 * k))
	_setp(pose, "upper_arm_r", Vector3(-30.0 * k, 0, 40.0 * k))
	_setp(pose, "head", Vector3(20.0 * k, 0, 0))
	root_off.y -= 0.0
	root_off.z -= 0.0


func _getup_pose(pose: Dictionary, t: float) -> void:
	var k := 1.0 - clampf(t, 0, 1)
	_down_pose(pose, k * 0.5)
	_p(pose, "hips", 30.0 * (1 - k), 0, 0)


func _drive_pose(pose: Dictionary, bike: bool) -> void:
	_setp(pose, "hips", Vector3(-80.0, 0, 0))
	_setp(pose, "spine", Vector3((15.0 + veh_speed01 * 14.0) if bike else 8.0, 0, 0))
	_setp(pose, "thigh_l", Vector3(70.0 if bike else 80.0, 0, -6.0))
	_setp(pose, "thigh_r", Vector3(70.0 if bike else 80.0, 0, 6.0))
	_setp(pose, "shin_l", Vector3(-40.0 if bike else 10.0, 0, 0))
	_setp(pose, "shin_r", Vector3(-40.0 if bike else 10.0, 0, 0))
	_setp(pose, "foot_l", Vector3(20.0, 0, 0))
	_setp(pose, "foot_r", Vector3(20.0, 0, 0))
	if bike:
		_setp(pose, "upper_arm_l", Vector3(-45.0, 0, -14.0))
		_setp(pose, "upper_arm_r", Vector3(-45.0, 0, 14.0))
		_setp(pose, "forearm_l", Vector3(-25.0, 0, 0))
		_setp(pose, "forearm_r", Vector3(-25.0, 0, 0))
	else:
		_setp(pose, "upper_arm_l", Vector3(-55.0, 0, -18.0))
		_setp(pose, "upper_arm_r", Vector3(-55.0, 0, 18.0))
		_setp(pose, "forearm_l", Vector3(-35.0, 0, 10.0))
		_setp(pose, "forearm_r", Vector3(-35.0, 0, -10.0))
	# steering input rotates the wheel: arms counter-rotate, torso follows
	var sw := steer * 38.0
	if bike:
		_p(pose, "upper_arm_l", 0, 0, -sw * 0.35)
		_p(pose, "upper_arm_r", 0, 0, -sw * 0.35)
		# bike lean: whole body inclines into the turn
		var bl := veh_lean * 16.0
		_p(pose, "hips", 0, 0, bl)
		_p(pose, "spine", 0, 0, bl * 0.7)
		_p(pose, "chest", 0, 0, bl * 0.5)
		_p(pose, "head", 0, -bl * 0.4, 0)
		_p(pose, "thigh_l", 0, 0, bl * 0.3)
		_p(pose, "thigh_r", 0, 0, bl * 0.3)
	else:
		_p(pose, "upper_arm_l", 0, 0, sw)
		_p(pose, "upper_arm_r", 0, 0, sw)
		_p(pose, "forearm_l", 0, 0, sw * 0.4)
		_p(pose, "forearm_r", 0, 0, sw * 0.4)
		_p(pose, "chest", 0, steer * 6.0, 0)
		_p(pose, "head", 0, steer * 8.0, 0)
	# road vibration at speed
	if veh_speed01 > 0.3:
		var vib := sin(idle_t * 38.0) * veh_speed01 * (1.6 if bike else 0.5)
		_p(pose, "chest", vib, 0, 0)
		_p(pose, "head", vib * 0.6, 0, 0)


func _sit_pose(pose: Dictionary) -> void:
	_setp(pose, "hips", Vector3(-85.0, 0, 0))
	_setp(pose, "thigh_l", Vector3(85.0, 0, -4.0))
	_setp(pose, "thigh_r", Vector3(85.0, 0, 4.0))
	_setp(pose, "shin_l", Vector3(-8.0, 0, 0))
	_setp(pose, "shin_r", Vector3(-8.0, 0, 0))
	_setp(pose, "upper_arm_l", Vector3(-20.0, 0, -8.0))
	_setp(pose, "upper_arm_r", Vector3(-20.0, 0, 8.0))
	_setp(pose, "forearm_l", Vector3(-45.0, 0, 0))
	_setp(pose, "forearm_r", Vector3(-45.0, 0, 0))


func _talk_pose(pose: Dictionary) -> void:
	var g := sin(talk_t * 7.0)
	var g2 := sin(talk_t * 4.3 + 1.0)
	_p(pose, "head", 3.0 * g2, 4.0 * g2, 2.0 * g)
	_p(pose, "upper_arm_r", -25.0 - 18.0 * maxf(0.0, g), 0, 12.0 + 8.0 * g)
	_p(pose, "forearm_r", -60.0 - 25.0 * maxf(0.0, g), 0, 0)
	_p(pose, "hand_r", -10.0 * g, 0, 0)
	_p(pose, "upper_arm_l", -15.0, 0, -6.0)
	_p(pose, "forearm_l", -30.0, 0, 0)


func _listen_pose(pose: Dictionary) -> void:
	# arms crossed, weight on one leg
	_setp(pose, "upper_arm_l", Vector3(-30.0, 0, -30.0))
	_setp(pose, "upper_arm_r", Vector3(-30.0, 0, 30.0))
	_setp(pose, "forearm_l", Vector3(-95.0, 0, 35.0))
	_setp(pose, "forearm_r", Vector3(-95.0, 0, -35.0))
	_p(pose, "hips", 0, 0, 3.0)
	_p(pose, "head", 4.0, -5.0, 0)


func _carry_pose(pose: Dictionary) -> void:
	_setp(pose, "upper_arm_l", Vector3(-55.0, 0, -18.0))
	_setp(pose, "upper_arm_r", Vector3(-55.0, 0, 18.0))
	_setp(pose, "forearm_l", Vector3(-70.0, 0, 15.0))
	_setp(pose, "forearm_r", Vector3(-70.0, 0, -15.0))
	_p(pose, "spine", 6.0, 0, 0)


func _search_pose(pose: Dictionary) -> void:
	_p(pose, "hips", 30.0, 0, 0)
	_p(pose, "spine", 25.0, 0, 0)
	_p(pose, "head", -20.0, 0, 0)
	_p(pose, "upper_arm_r", -40.0, 0, 15.0)
	_p(pose, "forearm_r", -50.0, 0, 0)


# ------------------------------------------------------------------ tick ----
func tick(delta: float, style_stance: Dictionary) -> void:
	idle_t += delta
	if talk_t >= 0.0:
		talk_t += delta
	# gait phase locked to ground speed (stride ~ 0.78m walk .. 1.35 sprint)
	var stride := lerpf(0.78, 1.35, clampf(speed / 6.0, 0, 1))
	if speed > 0.05 and air_t <= 0.0:
		phase += (speed / stride) * TAU * delta
	var target: Dictionary = {}
	root_off = Vector3.ZERO
	match mode:
		"dead":
			_down_pose(target, 1.0)
		"down":
			_down_pose(target, down_t)
		"getup":
			_getup_pose(target, getup_t)
		"drive":
			_drive_pose(target, false)
		"ride":
			_drive_pose(target, true)
		"sit":
			_sit_pose(target)
		"carry":
			_carry_pose(target)
			_gait(target, speed01, sprint)
		"search":
			_search_pose(target)
		_:
			if not attack_style.is_empty() or mode == "attack":
				_stance(target, style_stance)
			if mode == "attack":
				_attack_pose(target)
			elif speed > 0.15 and air_t <= 0.0:
				_gait(target, speed01, sprint)
			else:
				_stance(target, style_stance if mode == "locomote" and _in_combat_stance() else {"lean": 0.05, "guard_h": 0.15, "feet": 0.2, "sway": 0.1})
				_idle_breath(target)
			if crouch and air_t <= 0.0:
				_crouch_pose(target)
			if air_t > 0.0:
				_air_pose(target, air_t)
			if land_t > 0.0:
				_land_pose(target, land_t)
			if block:
				_block_pose(target)
			if aiming:
				_aim_pose(target)
			if hit_t >= 0.0:
				_hit_pose(target, hit_t)
			if mode == "talk":
				_talk_pose(target)
			if mode == "listen":
				_listen_pose(target)
	# turning lean
	if absf(facing_delta) > 0.2 and speed > 1.0:
		_p(target, "hips", 0, 0, clampf(-facing_delta * 2.0, -10.0, 10.0))
		_p(target, "chest", 0, 0, clampf(-facing_delta * 2.0, -10.0, 10.0))
	if absf(lean) > 0.5:
		for bn in ["hips", "spine", "chest"]:
			_p(target, bn, 0, 0, lean * 0.4)
	# head look
	if look_dir.length_squared() > 0.01:
		var yaw := clampf(rad_to_deg(atan2(look_dir.x, look_dir.z)), -55.0, 55.0)
		_p(target, "head", 0, yaw * 0.6, 0)
		_p(target, "neck", 0, yaw * 0.35, 0)
	# smooth + apply
	var k := 1.0 - exp(-stiffness * delta)
	for bn in Humanoid.BONES:
		var t2: Vector3 = target.get(bn, Vector3.ZERO)
		cur[bn] = cur.get(bn, Vector3.ZERO).lerp(t2, k)
		var idx: int = B[bn]
		var rest := sk.get_bone_rest(idx)
		var basis := Basis.from_euler(Vector3(deg_to_rad(cur[bn].x), deg_to_rad(cur[bn].y), deg_to_rad(cur[bn].z)))
		sk.set_bone_pose(idx, Transform3D(basis, rest.origin))
	# root offset (hips bone carries vertical bob/crouch)
	var hips_i := B["hips"]
	var hrest := sk.get_bone_rest(hips_i)
	var hb := Basis.from_euler(Vector3(deg_to_rad(cur["hips"].x), deg_to_rad(cur["hips"].y), deg_to_rad(cur["hips"].z)))
	sk.set_bone_pose(hips_i, Transform3D(hb, hrest.origin + root_off))


func _in_combat_stance() -> bool:
	return mode == "combat_idle"


func _aim_pose(pose: Dictionary) -> void:
	_setp(pose, "upper_arm_l", Vector3(-80.0, 0, -10.0))
	_setp(pose, "upper_arm_r", Vector3(-82.0, 0, 6.0))
	_setp(pose, "forearm_l", Vector3(-14.0, 0, 6.0))
	_setp(pose, "forearm_r", Vector3(-4.0, 0, 0))
	_p(pose, "chest", 0, -8.0, 0)
	_p(pose, "head", -2.0, -6.0, 0)
