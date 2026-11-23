extends Node
## WorldState — the persistent soul of Cinder City: clock, weather, economy,
## heat, factions, relationships, memory, inventory, flags, mission progress.

enum Weather { CLEAR, OVERCAST, RAIN, FOG }

# --- clock ---
var game_hour: float = 21.5          # 24h float; story opens at night
var day: int = 1
const MINUTES_PER_REAL_SECOND := 1.0 # 1 real second = 1 game minute
var time_frozen := false

# --- weather ---
var weather: int = Weather.RAIN
var weather_timer: float = 900.0
var wetness: float = 0.8             # 0..1 road/surface wetness

# --- economy / status ---
var money: int = 180
var wanted: int = 0
var heat_decay: float = 0.0

# --- factions: family (Vane), corp (Halcyon), crew (Ashfall Syndicate) ---
var factions: Dictionary = {"family": 40.0, "corp": -10.0, "crew": 0.0}

# --- people ---
var relationships: Dictionary = {}   # char_id -> -100..100
var memory: Dictionary = {}          # char_id -> Array[String] of remembered deeds

# --- progression ---
var flags: Dictionary = {}           # string -> bool/int
var mission_state: Dictionary = {}   # mission_id -> {stage:int, done:bool, failed:bool}
var stats: Dictionary = {
	"playtime": 0.0, "on_foot_km": 0.0, "driven_km": 0.0,
	"kos": 0, "arrests": 0, "deaths": 0, "jobs_done": 0,
	"collectibles": 0, "races_won": 0, "fights_won": 0,
}

# --- inventory ---
var inventory: Dictionary = {}       # item_id -> qty
var owned_weapons: Array = []        # weapon ids
var weapon_attachments: Dictionary = {}  # weapon_id -> {slot -> attachment_id}
var equipped_weapon: String = ""     # "" = fists
var equipped_armor: String = ""
var equipped_outfit: String = "outfit_default"
var current_style: String = "brawler"

# --- world knowledge ---
var discovered_pois: Array = []
var visited_districts: Array = []   # fog of war
var collected: Array = []
var owned_vehicles: Array = []

# --- phone ---
var phone_station: String = ""
var call_log: Array = []
var gps_active: bool = false
var gps_target: Vector3 = Vector3.ZERO
var gps_label: String = ""
var msg_threads: Dictionary = {}
var messages_read: Array = []
var messages_pending: Array = []
var calls_made: Array = []

# --- radio/news state ---
var news_queue: Array = []
var last_news: String = ""

const SAVE_VERSION := 3


func _ready() -> void:
	reset_all()
	if not Bus.poi_discovered.is_connected(_on_poi_discovered):
		Bus.poi_discovered.connect(_on_poi_discovered)


func _on_poi_discovered(pid: String) -> void:
	if not (pid in discovered_pois):
		discovered_pois.append(pid)


func reset_all() -> void:
	game_hour = 21.5
	day = 1
	weather = Weather.RAIN
	wetness = 0.8
	weather_timer = 900.0
	money = 180
	wanted = 0
	heat_decay = 0.0
	factions = {"family": 40.0, "corp": -10.0, "crew": 0.0}
	relationships = {}
	memory = {}
	flags = {}
	mission_state = {}
	stats = {"playtime": 0.0, "on_foot_km": 0.0, "driven_km": 0.0, "kos": 0,
		"arrests": 0, "deaths": 0, "jobs_done": 0, "collectibles": 0,
		"races_won": 0, "fights_won": 0}
	inventory = {"bandage": 2, "lockpick": 1}
	owned_weapons = []
	equipped_weapon = ""
	equipped_armor = ""
	equipped_outfit = "outfit_default"
	current_style = "brawler"
	discovered_pois = []
	visited_districts = []
	collected = []
	owned_vehicles = []
	phone_station = ""
	messages_read = []
	messages_pending = ["msg_intro_ruth"]
	calls_made = []
	news_queue = []
	last_news = ""


func _process(delta: float) -> void:
	stats["playtime"] += delta
	if time_frozen:
		return
	var prev := game_hour
	game_hour += delta * MINUTES_PER_REAL_SECOND / 60.0
	if game_hour >= 24.0:
		game_hour -= 24.0
		day += 1
	if int(prev) != int(game_hour):
		Bus.hour_changed.emit(game_hour)
	# weather drift
	weather_timer -= delta
	if weather_timer <= 0.0:
		_roll_weather()
	# wetness drifts toward weather target
	var target := 0.9 if weather == Weather.RAIN else (0.25 if weather == Weather.OVERCAST else 0.0)
	wetness = move_toward(wetness, target, delta * 0.01)
	# heat decay when out of sight of police
	if wanted > 0:
		heat_decay += delta
		if heat_decay > 25.0:
			set_wanted(wanted - 1)
			heat_decay = 0.0


func _roll_weather() -> void:
	var r := randf()
	var roll := Weather.CLEAR
	if r < 0.34:
		roll = Weather.RAIN
	elif r < 0.62:
		roll = Weather.OVERCAST
	elif r < 0.72:
		roll = Weather.FOG
	if roll != weather:
		weather = roll
		Bus.weather_changed.emit(weather_name(), wetness)
	weather_timer = randf_range(420.0, 1200.0)


func set_weather(kind: String) -> void:
	var idx := ["clear", "overcast", "rain", "fog"].find(kind)
	if idx >= 0 and idx != weather:
		weather = idx
		weather_timer = randf_range(420.0, 1200.0)
		Bus.weather_changed.emit(weather_name(), wetness)


func weather_name() -> String:
	return ["clear", "overcast", "rain", "fog"][weather]


func is_night() -> bool:
	return game_hour < 6.0 or game_hour >= 19.0


func hour_of_day_string() -> String:
	var h := int(game_hour)
	var m := int((game_hour - h) * 60.0)
	return "%02d:%02d" % [h, m]


# ------------------------------------------------------------- mutators ---
func add_money(amount: int) -> void:
	money = max(0, money + amount)
	Bus.money_changed.emit(money)


func set_wanted(level: int) -> void:
	var v := clampi(level, 0, 5)
	if v != wanted:
		wanted = v
		heat_decay = 0.0
		Bus.wanted_changed.emit(wanted)


func add_faction_rep(faction: String, delta: float) -> void:
	if not factions.has(faction):
		return
	factions[faction] = clampf(factions[faction] + delta, -100.0, 100.0)
	Bus.faction_rep_changed.emit(faction, factions[faction])


func add_relationship(char_id: String, delta: float) -> void:
	relationships[char_id] = clampf(relationships.get(char_id, 0.0) + delta, -100.0, 100.0)
	Bus.relationship_changed.emit(char_id, relationships[char_id])


func remember(char_id: String, deed: String) -> void:
	if not memory.has(char_id):
		memory[char_id] = []
	if deed not in memory[char_id]:
		memory[char_id].append(deed)


func set_flag(key: String, value = true) -> void:
	flags[key] = value


func get_flag(key: String, default = false):
	return flags.get(key, default)


func add_item(item_id: String, qty: int = 1) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + qty
	Bus.inventory_changed.emit()


func remove_item(item_id: String, qty: int = 1) -> bool:
	if inventory.get(item_id, 0) < qty:
		return false
	inventory[item_id] -= qty
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	Bus.inventory_changed.emit()
	return true


func give_weapon(weapon_id: String) -> void:
	if weapon_id not in owned_weapons:
		owned_weapons.append(weapon_id)
		Bus.inventory_changed.emit()


# ------------------------------------------------------------- serialize --
func equip_armor(armor_id: String) -> void:
	equipped_armor = armor_id
	Bus.armor_changed.emit(Db.armor.get(armor_id, {}).get("protection", 0.0) * 100.0, 100.0)
	Bus.inventory_changed.emit()


func serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"hour": game_hour, "day": day,
		"weather": weather, "wetness": wetness,
		"money": money, "wanted": wanted,
		"factions": factions.duplicate(),
		"relationships": relationships.duplicate(),
		"memory": memory.duplicate(),
		"flags": flags.duplicate(),
		"mission_state": mission_state.duplicate(true),
		"stats": stats.duplicate(),
		"inventory": inventory.duplicate(),
		"owned_weapons": owned_weapons.duplicate(),
		"weapon_attachments": weapon_attachments.duplicate(true),
		"equipped_weapon": equipped_weapon,
		"equipped_armor": equipped_armor,
		"equipped_outfit": equipped_outfit,
		"current_style": current_style,
		"discovered_pois": discovered_pois.duplicate(),
		"visited_districts": visited_districts.duplicate(),
		"collected": collected.duplicate(),
		"owned_vehicles": owned_vehicles.duplicate(),
		"phone_station": phone_station,
		"call_log": call_log,
		"gps_active": gps_active,
		"gps_target": [gps_target.x, gps_target.y, gps_target.z],
		"gps_label": gps_label,
		"msg_threads": msg_threads,
		"messages_read": messages_read.duplicate(),
		"messages_pending": messages_pending.duplicate(),
	}


func deserialize(d: Dictionary) -> void:
	if d.get("version", 0) != SAVE_VERSION:
		push_warning("WorldState: save version mismatch, partial load")
	game_hour = d.get("hour", 21.5)
	day = d.get("day", 1)
	weather = d.get("weather", Weather.RAIN)
	wetness = d.get("wetness", 0.8)
	money = d.get("money", 0)
	wanted = d.get("wanted", 0)
	factions = d.get("factions", factions)
	relationships = d.get("relationships", {})
	memory = d.get("memory", {})
	flags = d.get("flags", {})
	mission_state = d.get("mission_state", {})
	stats = d.get("stats", stats)
	inventory = d.get("inventory", {})
	owned_weapons = d.get("owned_weapons", [])
	weapon_attachments = d.get("weapon_attachments", {})
	equipped_weapon = d.get("equipped_weapon", "")
	equipped_armor = d.get("equipped_armor", "")
	equipped_outfit = d.get("equipped_outfit", "outfit_default")
	current_style = d.get("current_style", "brawler")
	discovered_pois = d.get("discovered_pois", [])
	visited_districts = d.get("visited_districts", [])
	collected = d.get("collected", [])
	owned_vehicles = d.get("owned_vehicles", [])
	phone_station = d.get("phone_station", 0)
	call_log = d.get("call_log", [])
	gps_active = d.get("gps_active", false)
	var gt: Array = d.get("gps_target", [])
	if gt.size() == 3:
		gps_target = Vector3(gt[0], gt[1], gt[2])
	gps_label = d.get("gps_label", "")
	msg_threads = d.get("msg_threads", {})
	messages_read = d.get("messages_read", [])
	messages_pending = d.get("messages_pending", [])
