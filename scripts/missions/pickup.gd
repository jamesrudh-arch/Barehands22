extends Area3D
## Mission/world pickup — glows, bobs, collected via interact (B).

var interact_label: String = "Pick up"
var _t := 0.0
var _mi: MeshInstance3D


func _ready() -> void:
	add_to_group("interact")
	monitoring = false
	var item: String = get_meta("item", "item")
	var mode: String = get_meta("mode", "world")
	match item:
		"crate_token":
			interact_label = "Grab crate"
		"mission_clue":
			interact_label = "Search"
		"ledger_page":
			interact_label = "Take ledger page"
		"favor_token":
			interact_label = "Collect favor"
	_mi = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.35, 0.35, 0.35) if mode != "search" else Vector3(0.5, 0.3, 0.5)
	_mi.mesh = b
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	match item:
		"crate_token":
			m.albedo_color = Color(0.55, 0.4, 0.2)
			m.emission = Color(0.4, 0.25, 0.1)
		"mission_clue":
			m.albedo_color = Color(0.9, 0.8, 0.3)
			m.emission = Color(0.9, 0.75, 0.2)
		"ledger_page":
			m.albedo_color = Color(0.85, 0.82, 0.7)
			m.emission = Color(0.5, 0.45, 0.3)
		"favor_token":
			m.albedo_color = Color(0.3, 0.7, 0.5)
			m.emission = Color(0.2, 0.6, 0.4)
		_:
			m.albedo_color = Color(0.8, 0.7, 0.2)
			m.emission = Color(0.7, 0.6, 0.15)
	m.emission_energy_multiplier = 2.0
	_mi.material_override = m
	add_child(_mi)
	_t = randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	if _mi:
		_mi.position.y = 0.15 + sin(_t * 2.4) * 0.1
		_mi.rotation.y += delta * 1.6


func interact(_who: Node) -> void:
	var item: String = get_meta("item", "item")
	var mode: String = get_meta("mode", "world")
	match item:
		"crate_token", "mission_clue":
			pass  # mission manager tracks via inventory/event
		_:
			WorldState.add_item(item, 1)
	AudioDirector.sfx("grab_swoosh", 0.2)
	Effects.burst(global_position, "spark")
	Bus.world_event.emit("pickup_found", {"item": item, "mode": mode})
	if mode in ["search", "docks_pickup"] or item in ["crate_token", "mission_clue"]:
		# temporary mission tokens also count in inventory for carry stages
		if item == "crate_token":
			WorldState.add_item("crate_token", 1)
	queue_free()
