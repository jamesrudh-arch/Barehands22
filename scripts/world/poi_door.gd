extends Area3D
## poi_door — interactable entry point for interiors/shops/places.
## Emits a world event; the city scene routes it to ShopUI / InteriorManager.

var interact_label: String = "Enter"


func _ready() -> void:
	add_to_group("interact")
	monitoring = false


func interact(who: Node) -> void:
	var pid: String = get_meta("poi_id", "")
	var entry: Dictionary = WorldGen.pois.get(pid, {})
	var data: Dictionary = entry.get("data", {})
	AudioDirector.sfx("door_wood_open", 0.05)
	Bus.world_event.emit("poi_enter", {"poi": pid, "data": data})
