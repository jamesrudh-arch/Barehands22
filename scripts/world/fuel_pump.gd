extends Area3D
## fuel_pump — an interactable forecourt pump on the Smoke Line's sister
## system: Cinder City's filling stations.
##
## Design notes, all deliberate:
##  * You can fill from the driver's seat. That is how a forecourt works and
##    it does not make you climb out of a car in a rainstorm for a menu.
##  * You are billed BY THE LITRE as it flows, not up front. Running out of
##    cash mid-fill shuts the nozzle off — a small, legible failure.
##  * Driving off mid-fill is THEFT. It costs street rep, raises district
##    heat, and the world already has a witness/snitch system to notice.
##  * Price moves with street_rep: respected gets a discount, a known thief
##    pays a premium — which is exactly the incentive to steal instead.

const FILL_LPS := 14.0        ## litres per second through the nozzle
const REACH := 5.2            ## how far a car may be from the pump and still fill
const DRIVE_OFF := 7.5        ## leaving this far mid-fill counts as theft
const FLOW_PATH := "res://assets/audio/sfx/fuel_pump.wav"

var station_id: String = ""
var station_name: String = "Filling Station"
var price_per_l: float = 2.20
var diesel: bool = false
var district: String = ""
var pump_index: int = 0
var interact_label: String = "Refuel"

var filling := false
var target: Node = null       ## the vehicle currently on the nozzle
var litres := 0.0             ## delivered on this visit (harness + receipts)
var paid := 0                 ## money taken on this visit
var broke := false            ## shut off because the player ran out of cash
var stolen := false           ## shut off because the player drove away

var _flow: AudioStreamPlayer3D = null
var _owed := 0.0              ## fractional dollars accrued, billed in whole units
var _label_t := 0.0


func _ready() -> void:
	add_to_group("interact")
	monitoring = false
	collision_layer = 0
	collision_mask = 0
	_build_flow()
	_refresh_label()


func _build_flow() -> void:
	## the hose is a looping positional emitter on the pump, not a 2D blip —
	## you should hear it thin out as you walk away from the forecourt
	_flow = AudioStreamPlayer3D.new()
	_flow.name = "Flow"
	_flow.bus = "SFX"
	_flow.unit_size = 7.0
	_flow.max_distance = 42.0
	_flow.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_flow.volume_db = -6.0
	var s: AudioStream = load(FLOW_PATH)
	if s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_begin = 0
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
	_flow.stream = s
	# BUG the harness caught: an AudioStreamPlayer3D that is not a child of
	# anything is not in the scene tree, and Godot refuses to play it — the
	# pump would have filled every tank in complete silence.
	add_child(_flow)


func _refresh_label() -> void:
	var kind: String = "Diesel" if diesel else "Fuel"
	interact_label = "Refuel — %s $%.2f/L" % [kind, unit_price()]


# ------------------------------------------------------- vehicle accessors --
## A vehicle reaches this pump typed as Node (vehicle.gd has no class_name,
## matching the repo convention). Node.get() takes ONE argument — the 2-arg
## default form belongs to Dictionary — so the safe read is: Variant first,
## null test, then cast. float(null) throws and kills the rest of the method.
func _veh_f(v: Node, key: String, dflt: float) -> float:
	var raw: Variant = v.get(key)
	return dflt if raw == null else float(raw)


func _veh_b(v: Node, key: String) -> bool:
	return v.get(key) == true


func _veh_set(v: Node, key: String, val: Variant) -> void:
	if v.get(key) != null:
		v.set(key, val)


# ------------------------------------------------------------------ pricing --
func _fuel_cfg() -> Dictionary:
	var w: Dictionary = Db.districts.get("world", {})
	return w.get("fuel", {})


func unit_price() -> float:
	## what a litre costs HERE, right now, to YOU
	var p: float = price_per_l
	var cfg: Dictionary = _fuel_cfg()
	var max_disc: float = float(cfg.get("rep_discount_max", 0.15))
	var grudge_at: float = float(cfg.get("rep_discount_at", -25))
	var rep: int = WorldState.street_rep()
	if rep >= 8:
		# the block likes you: the keeper knocks something off
		p *= 1.0 - max_disc * clampf(float(rep) / 30.0, 0.0, 1.0)
	elif float(rep) <= grudge_at:
		# the block knows what you are: a premium, and he watches the pump
		p *= 1.0 + 0.25 * clampf((grudge_at - float(rep)) / 30.0, 0.0, 1.0)
	return maxf(0.10, p)


# ---------------------------------------------------------------- interact ---
func interact(who: Node) -> void:
	if filling:
		# pulling the nozzle yourself is not theft — you pay for what went in
		_stop("pulled", 0.0)
		return
	var veh: Node = _find_vehicle(who)
	if veh == null:
		AudioDirector.sfx("ui_error", 0.35)
		Bus.notification.emit("Pull a car up to the pump first.", "info")
		return
	var tank: float = _veh_f(veh, "tank_l", 0.0)
	var cur: float = _veh_f(veh, "fuel", 0.0)
	if (1.0 - cur) * tank < 0.35:
		AudioDirector.sfx("ui_error", 0.3)
		Bus.notification.emit("Tank's already full.", "info")
		return
	if WorldState.money <= 0:
		AudioDirector.sfx("ui_error", 0.35)
		Bus.notification.emit("No cash. The attendant is not looking away.", "warn")
		return
	target = veh
	filling = true
	litres = 0.0
	paid = 0
	_owed = 0.0
	broke = false
	stolen = false
	AudioDirector.sfx_at("fuel_cap", global_position, 0.85)
	if _flow != null and _flow.stream != null:
		_flow.play()
	Bus.world_event.emit("fuel_start", {"station": station_id, "price": unit_price()})


func _find_vehicle(who: Node) -> Node:
	## the car you drove here, or the nearest one that can reach the nozzle
	if who != null:
		var v: Node = who.get("in_vehicle")
		if v != null and is_instance_valid(v) and v.get("tank_l") != null:
			return v
	var best: Node = null
	var bd := REACH
	for n in get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(n) or n.get("tank_l") == null:
			continue
		var d: float = (n as Node3D).global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = n
	return best


# -------------------------------------------------------------------- tick ---
func _process(delta: float) -> void:
	if not filling or target == null:
		return
	if not is_instance_valid(target):
		_stop("gone", 0.0)
		return
	# driving off mid-fill: the nozzle comes out, the block notices
	if (target as Node3D).global_position.distance_to(global_position) > DRIVE_OFF:
		stolen = true
		WorldState.note_deed("fuel_theft", district, false)
		WorldState.add_district_heat(district, 6.0)
		Bus.notification.emit("Drove off with the nozzle out. People saw that.", "warn")
		_stop("stolen", 0.9)
		return

	var tank: float = _veh_f(target, "tank_l", 0.0)
	var cur: float = _veh_f(target, "fuel", 1.0)
	var take_l: float = minf(FILL_LPS * delta, (1.0 - cur) * tank)
	if take_l <= 0.0005:
		_stop("full", 0.9)
		return

	# billed as it flows, in whole dollars
	var unit: float = unit_price()
	_owed += take_l * unit
	var pay: int = int(_owed)
	if pay > WorldState.money:
		pay = WorldState.money
	if pay > 0:
		WorldState.add_money(-pay)
		paid += pay
		_owed -= float(pay)
	litres += take_l
	_veh_set(target, "fuel", clampf(cur + take_l / tank, 0.0, 1.0))

	# a car that ran dry starts again once there is fuel in the line
	if _veh_b(target, "fuel_dry") and _veh_f(target, "fuel", 1.0) > 0.02:
		_veh_set(target, "fuel_dry", false)
		_veh_set(target, "_dry_warned", false)
		# was "engine_start" — no such file exists, and sfx_at() returns early on a
		# null stream, so the moment a player has just PAID for and the toast
		# announces ("she'll turn over now") landed in complete silence. veh_start
		# is the sound the call always meant. Same class as the wave-45 missing
		# music_finale and the wave-48 silent fuel pumps; step 98 now cross-references
		# every literal audio name in the codebase so this cannot recur.
		AudioDirector.sfx_at("veh_start", (target as Node3D).global_position, 0.8)
		Bus.notification.emit("Fuel in the line — she'll turn over now.", "info")

	if WorldState.money <= 0 and pay <= 0 and _veh_f(target, "fuel", 1.0) < 0.999:
		broke = true
		_stop("broke", 0.9)
		return
	if _veh_f(target, "fuel", 1.0) >= 0.9995:
		_stop("full", 0.9)
		return

	# keep the pump's own prompt honest while it runs
	_label_t -= delta
	if _label_t <= 0.0:
		_label_t = 0.4
		interact_label = "Filling… %d L  $%d  (interact to stop)" % [int(litres), paid]


func _stop(reason: String, clunk: float) -> void:
	filling = false
	if _flow != null:
		_flow.stop()
	if clunk > 0.0:
		AudioDirector.sfx_at("nozzle_off", global_position, clunk)
	var l: int = int(litres)
	match reason:
		"full":
			AudioDirector.sfx("ui_confirm", 0.3)
			Bus.notification.emit("Tank full: %d L for $%d at %s." % [l, paid, station_name], "info")
		"broke":
			Bus.notification.emit("Out of cash mid-fill — %d L, $%d. Nozzle's off." % [l, paid], "warn")
		"stolen":
			pass   # the theft message was already pushed
		"pulled":
			Bus.notification.emit("Stopped at %d L — $%d." % [l, paid], "info")
		_:
			pass
	Bus.world_event.emit("fuel_done", {
		"station": station_id, "litres": litres, "paid": paid,
		"broke": broke, "stolen": stolen, "reason": reason,
	})
	target = null
	_refresh_label()
