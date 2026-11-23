extends Node
## Bus — global signal hub. Every cross-system event flows through here so
## systems stay decoupled (UI listens, gameplay emits).
## LEVERAGE core. Godot 4.7 / Mobile.

# --- flow ---
signal game_state_changed(state: StringName)
signal scene_changed(scene_name: String)
signal loading_progress(p: float)

# --- player vitals / gear ---
signal health_changed(cur: float, maxv: float)
signal stamina_changed(cur: float, maxv: float)
signal armor_changed(cur: float, maxv: float)
signal money_changed(amount: int)
signal inventory_changed()
signal weapon_equipped(weapon_id: String)
signal ammo_changed(mag: int, reserve: int)
signal combat_style_changed(style: String)
signal combat_state_changed(in_combat: bool)
signal player_died(cause: String)
signal player_busted()
signal player_respawned(where: String)

# --- interaction / context ---
signal interaction_available(label: String)
signal interaction_cleared()
signal prompt_hint(text: String)

# --- crime / police ---
signal crime_committed(crime: String, severity: int, pos: Vector3)
signal wanted_changed(level: int)
signal police_state_changed(state: String)

# --- factions / relationships ---
signal faction_rep_changed(faction: String, value: float)
signal relationship_changed(char_id: String, value: float)

# --- story / missions / dialogue ---
signal mission_started(mission_id: String)
signal objective_updated(mission_id: String, text: String)
signal mission_completed(mission_id: String, success: bool)
signal dialogue_started(char_id: String)
signal dialogue_line(speaker: String, text: String, voice: String)
signal dialogue_choice(options: Array)
signal dialogue_ended()
signal cutscene_started(name: String)
signal cutscene_ended(name: String)

# --- world ---
signal hour_changed(hour: float)
signal weather_changed(kind: String, wetness: float)
signal district_changed(district_id: String)
signal world_event(event_id: String, payload: Dictionary)
signal radio_news(text: String)
signal poi_discovered(poi_id: String)

# --- vehicles ---
signal vehicle_entered(vehicle_type: String)
signal vehicle_exited()
signal vehicle_health_changed(hp: float)
signal vehicle_speed_changed(kmh: float)

# --- ui / meta ---
signal notification(text: String, kind: String)
signal phone_opened()
signal phone_closed()
signal map_opened()
signal map_closed()
signal save_completed(slot: int)
signal load_completed(slot: int)
signal settings_changed()
