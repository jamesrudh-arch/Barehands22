extends Node
## Db — static game data registry. Loads all JSON definitions from res://data
## once at boot and offers typed accessors. Data is the single source of truth
## for items, weapons, characters, city layout, missions, dialogue, events.

var items: Dictionary = {}          # id -> item def
var weapons: Dictionary = {}        # id -> weapon def
var armor: Dictionary = {}          # id -> armor def
var outfits: Dictionary = {}        # id -> outfit def
var vehicles: Dictionary = {}       # id -> vehicle def
var characters: Dictionary = {}     # id -> named character def
var peds: Dictionary = {}           # id -> pedestrian archetype def
var districts: Dictionary = {}      # id -> district def
var missions: Dictionary = {}       # id -> mission def
var dialogue: Dictionary = {}       # id -> dialogue tree def
var events: Dictionary = {}         # id -> world event def
var shops: Dictionary = {}          # id -> shop def
var radio: Dictionary = {}          # station -> def
var news_templates: Array = []
var barks: Dictionary = {}          # context -> list of lines
var collectibles: Dictionary = {}
var combat_styles: Dictionary = {}
var properties: Dictionary = {}      # id -> buyable business def

const FILES := {
	"items": "res://data/items.json",
	"weapons": "res://data/weapons.json",
	"armor": "res://data/armor.json",
	"outfits": "res://data/outfits.json",
	"vehicles": "res://data/vehicles.json",
	"characters": "res://data/characters.json",
	"peds": "res://data/peds.json",
	"districts": "res://data/city.json",
	"missions": "res://data/missions.json",
	"dialogue": "res://data/dialogue.json",
	"events": "res://data/events.json",
	"shops": "res://data/shops.json",
	"radio": "res://data/radio.json",
	"combat_styles": "res://data/combat_styles.json",
	"properties": "res://data/properties.json",
}


func _ready() -> void:
	for key in FILES:
		var path: String = FILES[key]
		if not FileAccess.file_exists(path):
			push_warning("Db: missing data file " + path)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed == null:
			push_error("Db: bad JSON in " + path)
			continue
		match key:
			"radio":
				radio = parsed
			"districts":
				districts = parsed
			"news":
				news_templates = parsed
			_:
				var d: Dictionary = parsed
				if key == "news_templates":
					news_templates = d.get("templates", [])
				else:
					set(key, d)
	# convenience: news templates file
	if FileAccess.file_exists("res://data/news.json"):
		var f2 := FileAccess.open("res://data/news.json", FileAccess.READ)
		var np = JSON.parse_string(f2.get_as_text())
		f2.close()
		if np is Dictionary:
			news_templates = np.get("templates", [])
			barks = np.get("barks", {})


func item(id: String) -> Dictionary:
	return items.get(id, {})


func weapon(id: String) -> Dictionary:
	return weapons.get(id, {})


func character(id: String) -> Dictionary:
	return characters.get(id, {})


func vehicle(id: String) -> Dictionary:
	return vehicles.get(id, {})


func district(id: String) -> Dictionary:
	return districts.get(id, {})


func mission(id: String) -> Dictionary:
	return missions.get(id, {})


func dialogue_tree(id: String) -> Dictionary:
	return dialogue.get(id, {})


func style(id: String) -> Dictionary:
	return combat_styles.get(id, {})


func style_list() -> Array:
	var out: Array = []
	for k in combat_styles:
		out.append(combat_styles[k])
	out.sort_custom(func(a, b): return a.get("index", 0) < b.get("index", 0))
	return out
