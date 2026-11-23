extends Node
## AudioDirector — buses, pooled players, adaptive music, ambient beds,
## dialogue voice blips. All audio is original (tools/forge/forge_audio.py).

var _cache: Dictionary = {}                 # path -> AudioStream
var _sfx_pool: Array = []                   # AudioStreamPlayer (2D/UI)
var _sfx3d_pool: Array = []                 # AudioStreamPlayer3D
const SFX_POOL := 12
const SFX3D_POOL := 16

var bus_master := 0
var bus_music := 1
var bus_sfx := 2
var bus_vox := 3
var bus_ambient := 4

var music_player_a: AudioStreamPlayer
var music_player_b: AudioStreamPlayer
var _music_active := true                    # a is active when true
var _music_fade := 0.0
var _music_fading := false
var current_music: String = ""

var ambient_players: Dictionary = {}         # name -> AudioStreamPlayer(loop)
var ambient_target: Dictionary = {}          # name -> target volume

var vox_player: AudioStreamPlayer
var _vox_queue: Array = []
var _vox_timer := 0.0

var settings: Dictionary = {"master": 0.9, "music": 0.7, "sfx": 0.9, "vox": 0.9}


func _ready() -> void:
	_setup_buses()
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	for i in SFX3D_POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.max_distance = 60.0
		add_child(p)
		_sfx3d_pool.append(p)
	music_player_a = AudioStreamPlayer.new()
	music_player_a.bus = "Music"
	add_child(music_player_a)
	music_player_b = AudioStreamPlayer.new()
	music_player_b.bus = "Music"
	add_child(music_player_b)
	vox_player = AudioStreamPlayer.new()
	vox_player.bus = "Vox"
	add_child(vox_player)
	for nm in ["rain", "traffic", "crowd", "interior", "fire", "siren"]:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
		add_child(p)
		ambient_players[nm] = p
		ambient_target[nm] = 0.0
	Bus.weather_changed.connect(_on_weather)
	Bus.dialogue_line.connect(_on_dialogue_line)


func _setup_buses() -> void:
	var idx := AudioServer.bus_count
	for name in ["Music", "SFX", "Vox", "Ambient"]:
		AudioServer.add_bus()
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
		idx += 1
	apply_settings()


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(settings["master"]))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(settings["music"]))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(settings["sfx"]))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Vox"), linear_to_db(settings["vox"]))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), linear_to_db(settings["sfx"]))


func stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_warning("AudioDirector: missing " + path)
		return null
	var s := load(path)
	_cache[path] = s
	return s


func sfx(name: String, pitch_var: float = 0.08, volume: float = 1.0) -> void:
	var s := stream("res://assets/audio/sfx/%s.wav" % name)
	if s == null:
		return
	var p: AudioStreamPlayer = _free(_sfx_pool)
	if p == null:
		return
	p.stream = s
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = linear_to_db(volume)
	p.play()


func sfx_at(name: String, pos: Vector3, volume: float = 1.0, pitch_var: float = 0.08) -> void:
	var s := stream("res://assets/audio/sfx/%s.wav" % name)
	if s == null:
		return
	var p: AudioStreamPlayer3D = _free(_sfx3d_pool)
	if p == null:
		return
	p.stream = s
	p.global_position = pos
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.volume_db = linear_to_db(volume)
	p.play()


func _free(pool: Array):
	for p in pool:
		if not p.playing:
			return p
	return null


# ------------------------------------------------------------------ music --
func play_music(track: String, fade: float = 1.5) -> void:
	if track == current_music:
		return
	var path := "res://assets/audio/music/%s.ogg" % track
	var s := stream(path)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		s.loop = true
	var incoming := music_player_b if _music_active else music_player_a
	var outgoing := music_player_a if _music_active else music_player_b
	incoming.stream = s
	incoming.volume_db = -40
	incoming.play()
	_music_active = not _music_active
	_music_fading = true
	_music_fade = fade
	current_music = track


func stop_music(fade: float = 1.0) -> void:
	if current_music == "":
		return
	_music_fading = true
	_music_fade = fade
	current_music = ""


func _process(delta: float) -> void:
	if _music_fading:
		var a := music_player_a if _music_active else music_player_b
		var b := music_player_b if _music_active else music_player_a
		a.volume_db = move_toward(a.volume_db, 0.0, delta * (40.0 / maxf(_music_fade, 0.1)))
		b.volume_db = move_toward(b.volume_db, -45.0, delta * (40.0 / maxf(_music_fade, 0.1)))
		if not b.playing and a.volume_db > -1.0:
			_music_fading = false
	# ambient volumes
	for nm in ambient_players:
		var p: AudioStreamPlayer = ambient_players[nm]
		var target: float = ambient_target.get(nm, 0.0)
		if target > 0.001 and not p.playing and p.stream != null:
			p.volume_db = -40
			p.play()
		if p.playing:
			p.volume_db = move_toward(p.volume_db, linear_to_db(maxf(target, 0.001)), delta * 1.5)
			if target < 0.002 and p.volume_db < -39.0:
				p.stop()
	# vox blips
	if _vox_queue.size() and not vox_player.playing:
		_vox_timer -= delta
		if _vox_timer <= 0.0:
			vox_player.stream = _vox_queue.pop_front()
			vox_player.play()
			_vox_timer = 0.075


func ambient(name: String, path: String, volume: float) -> void:
	var p: AudioStreamPlayer = ambient_players.get(name)
	if p == null:
		return
	ambient_target[name] = volume
	if p.stream == null:
		var s := stream(path)
		if s == null:
			return
		if "loop" in s:
			s.loop = true
		p.stream = s


func ambient_off(name: String) -> void:
	ambient_target[name] = 0.0


func _on_weather(kind: String, _wet: float) -> void:
	if kind == "rain":
		ambient("rain", "res://assets/audio/sfx/rain_loop.wav", 0.5)
	else:
		ambient_off("rain")


# ------------------------------------------------------------ dialogue vox --
func _on_dialogue_line(_speaker: String, text: String, voice: String) -> void:
	if not Game.settings.get("subtitles", true):
		pass  # blips play regardless; subtitles handled by UI
	speak(voice, text)


func speak(voice: String, text: String) -> void:
	_vox_queue.clear()
	var words := text.split(" ")
	var n := clampi(words.size(), 1, 14)
	for i in n:
		var v := i % 3
		var s := stream("res://assets/audio/vox/%s_%d.wav" % [voice, v])
		if s:
			_vox_queue.append(s)
