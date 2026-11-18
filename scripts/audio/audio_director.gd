class_name AudioDirector
extends Node
## Music, ambience and gameplay cues. Every sound is original and generated
## by tools/audio/make_audio.py (royalty-free). Streams left empty in the
## scene fall back to the generated files in res://assets/audio/.

const DEFAULTS := {
	"music": "res://assets/audio/music_golden_hour_line.ogg",
	"ocean_ambience": "res://assets/audio/ambience_ocean.ogg",
	"wind_ambience": "res://assets/audio/ambience_wind.ogg",
	"line_load": "res://assets/audio/sfx_line_load.ogg",
	"takeoff": "res://assets/audio/sfx_takeoff.ogg",
	"landing": "res://assets/audio/sfx_landing.ogg",
	"trick": "res://assets/audio/sfx_trick.ogg",
	"combo": "res://assets/audio/sfx_combo.ogg",
	"super_rebound": "res://assets/audio/sfx_super_rebound.ogg",
	"bail": "res://assets/audio/sfx_bail.ogg",
}

@export_group("Music")
@export var music: AudioStream
@export_range(-40.0, 0.0, 1.0) var music_volume_db: float = -10.0
@export var music_fade_in: float = 3.0
## In slow motion the music dips so the moment stands out.
@export var slowmo_duck_db: float = -7.0
var music_enabled: bool = true

@export_group("Ambience")
@export var ocean_ambience: AudioStream
@export var wind_ambience: AudioStream
@export_range(-40.0, 0.0, 1.0) var ambience_volume_db: float = -18.0

@export_group("Gameplay cues")
@export var line_load: AudioStream
@export var takeoff: AudioStream
@export var landing: AudioStream
@export var trick: AudioStream
@export var combo: AudioStream
@export var super_rebound: AudioStream
@export var bail: AudioStream
@export_range(-30.0, 6.0, 1.0) var effects_volume_db: float = -8.0

var _music_player: AudioStreamPlayer
var _music_fade: float = 0.0
var _ocean_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_state: int = Athlete.State.ON_LINE


func _ready() -> void:
	_load_defaults()
	_music_player = _make_player("Music", music)
	_music_player.volume_db = -60.0
	if music != null and music_enabled:
		_music_player.play()
	_ocean_player = _make_player("OceanAmbience", ocean_ambience)
	_wind_player = _make_player("WindAmbience", wind_ambience)
	_ocean_player.volume_db = ambience_volume_db
	_wind_player.volume_db = ambience_volume_db - 4.0
	if ocean_ambience != null:
		_ocean_player.play()
	if wind_ambience != null:
		_wind_player.play()
	for i in 4:
		_voices.append(_make_player("SFXVoice%d" % i, null))


func _load_defaults() -> void:
	for key in DEFAULTS:
		if get(key) == null and ResourceLoader.exists(DEFAULTS[key]):
			var stream: AudioStream = load(DEFAULTS[key])
			if key in ["music", "ocean_ambience", "wind_ambience"] and stream is AudioStreamOggVorbis:
				stream = stream.duplicate()
				stream.loop = true
			set(key, stream)


func _process(delta: float) -> void:
	if _music_player == null or music == null:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)
	_music_fade = move_toward(_music_fade, 1.0 if music_enabled else 0.0, real / maxf(music_fade_in, 0.01))
	var duck := slowmo_duck_db * clampf((1.0 - Engine.time_scale) / 0.7, 0.0, 1.0)
	_music_player.volume_db = lerpf(-60.0, music_volume_db + duck, _music_fade)
	if music_enabled and not _music_player.playing:
		_music_player.play()
	elif not music_enabled and _music_fade <= 0.0 and _music_player.playing:
		_music_player.stop()


func toggle_music() -> void:
	music_enabled = not music_enabled


func bind(athlete: Athlete, director: Node) -> void:
	if not athlete.state_changed.is_connected(_on_state_changed):
		athlete.state_changed.connect(_on_state_changed)
	if not athlete.contact_started.is_connected(_on_contact_started):
		athlete.contact_started.connect(_on_contact_started)
	if not athlete.tricks.trick_completed.is_connected(_on_trick_completed):
		athlete.tricks.trick_completed.connect(_on_trick_completed)
	if not athlete.tricks.landed.is_connected(_on_tricks_landed):
		athlete.tricks.landed.connect(_on_tricks_landed)
	if not athlete.tricks.bailed.is_connected(_on_bailed):
		athlete.tricks.bailed.connect(_on_bailed)
	if director.has_signal("super_rebound") and not director.super_rebound.is_connected(_on_super_rebound):
		director.super_rebound.connect(_on_super_rebound)


func _make_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player


func _play(stream: AudioStream, volume_offset_db: float = 0.0) -> bool:
	if stream == null or _voices.is_empty():
		return false
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	player.stop()
	player.stream = stream
	player.volume_db = effects_volume_db + volume_offset_db
	player.play()
	return true


func _on_state_changed(new_state: int) -> void:
	if new_state == Athlete.State.AIRBORNE:
		_play(takeoff)
	elif new_state == Athlete.State.ON_LINE and _last_state == Athlete.State.AIRBORNE:
		_play(landing)
	elif new_state == Athlete.State.FALLEN:
		_play(bail)
	_last_state = new_state


func _on_contact_started(_contact_name: String) -> void:
	_play(line_load, -3.0)


func _on_trick_completed(_trick_name: String) -> void:
	_play(trick, -2.0)


func _on_tricks_landed(trick_names: Array, _points: int) -> void:
	if trick_names.size() > 1:
		_play(combo, -1.0)


func _on_bailed(_reason: String) -> void:
	_play(bail)


func _on_super_rebound(_launch_speed: float) -> void:
	_play(super_rebound, 1.0)
