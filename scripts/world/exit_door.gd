extends Area3D
var interact_label: String = "Leave"

func _ready() -> void:
	add_to_group("interact")
	monitoring = false

func interact(_who: Node) -> void:
	AudioDirector.sfx("door_wood_close", 0.05)
	InteriorManager.exit()
