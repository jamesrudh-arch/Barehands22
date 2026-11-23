extends Node
## SaveSystem — 3 manual slots + autosave, JSON in user://.
## Serializes WorldState + player transform + active mission runtime.

const SLOT_PATH := "user://save_slot_%d.json"
const META_PATH := "user://save_meta.json"
const SLOT_COUNT := 3


func _slot_path(slot: int) -> String:
	return SLOT_PATH % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func meta(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		return d.get("meta", {})
	return {}


func all_metas() -> Array:
	var out: Array = []
	for i in range(SLOT_COUNT):
		out.append(meta(i))
	return out


func save_game(slot: int, extra: Dictionary = {}) -> bool:
	var payload := {
		"meta": {
			"slot": slot,
			"timestamp": Time.get_datetime_string_from_system(),
			"day": WorldState.day,
			"hour": WorldState.hour_of_day_string(),
			"money": WorldState.money,
			"district": extra.get("district", "unknown"),
			"playtime_min": int(WorldState.stats.get("playtime", 0.0) / 60.0),
			"autosave": slot == -1,
		},
		"world": WorldState.serialize(),
		"player": extra.get("player", {}),
		"missions": extra.get("missions", {}),
		"worldgen": extra.get("worldgen", {}),
	}
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: cannot write slot %d" % slot)
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	Bus.save_completed(slot)
	return true


func load_game(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary):
		return {}
	WorldState.deserialize(d.get("world", {}))
	Bus.load_completed(slot)
	return d


func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(_slot_path(slot))
