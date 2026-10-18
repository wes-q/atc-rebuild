class_name GameSound
extends Node
## Sound effects and music the way the original's NubAudiere and BGM classes played them.
##
## A positioned sound gets its volume and pan once, when it starts (NubAudiere::get_volume,
## get_pan). The listener sits over the camera's plane position but 300 units off the
## plane (World::update sets view_pos.y = 300, scale 2000), so a sound right under the
## camera plays at 0.625 and fades out linearly by about 740 units away. Pan is the
## sideways offset x 0.005, with a dead zone of 50 units.

const ROOT := "res://assets/original/"
const LISTENER_HEIGHT := 300.0
const LISTENER_SCALE := 2000.0
const VOICES := 24

## Plane position under the camera.
var listener := Vector2.ZERO
var enabled := true
## The options page's BGM and EFFECT bars, 0 to 1.
var music_volume := 1.0:
	set(v):
		music_volume = clampf(v, 0.0, 1.0)
		if _music:
			_music.volume_db = linear_to_db(maxf(music_volume, 0.0001))
var effects_volume := 1.0

var _voices: Array[AudioStreamPlayer] = []
var _panners: Array[AudioEffectPanner] = []
var _next := 0
var _streams := {}
var _music: AudioStreamPlayer
var _bgm: Array = []

## NubAudiere::get_volume for a sound on the plane.
static func volume_at(listen: Vector2, at: Vector2) -> float:
	var distance := sqrt(listen.distance_squared_to(at) + LISTENER_HEIGHT * LISTENER_HEIGHT)
	return clampf(1.0 - distance / (LISTENER_SCALE * 0.4), 0.0, 1.0)

## NubAudiere::get_pan.
static func pan_at(listen: Vector2, at: Vector2) -> float:
	var offset := at.x - listen.x
	if absf(offset) < 50.0:
		offset = 0.0
	return clampf(offset * 0.005, -1.0, 1.0)

func _ready() -> void:
	# One bus per voice so each can carry its own pan.
	for i in VOICES:
		var bus := AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, "Voice%d" % i)
		AudioServer.set_bus_send(bus, "Master")
		var panner := AudioEffectPanner.new()
		AudioServer.add_bus_effect(bus, panner)
		_panners.append(panner)
		var p := AudioStreamPlayer.new()
		p.bus = "Voice%d" % i
		add_child(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	var f := FileAccess.open(ROOT + "bgm/bgm.json", FileAccess.READ)
	if f:
		_bgm = JSON.parse_string(f.get_as_text())

## Plays a sound named as the original code names it ("sound/gunfire1") at a plane point.
func play_at(sound: String, at: Vector2) -> void:
	var volume := volume_at(listener, at)
	if volume < 0.01:
		return
	_play(sound, volume, pan_at(listener, at))

## NubAudiere::play(name) without a position: full volume, centred.
func play(sound: String) -> void:
	_play(sound, 1.0, 0.0)

func _play(sound: String, volume: float, pan: float) -> void:
	if not enabled:
		return
	var stream := _stream(sound)
	if stream == null:
		return
	var i := _next
	_next = (_next + 1) % VOICES
	_panners[i].pan = pan
	_voices[i].stream = stream
	_voices[i].volume_db = linear_to_db(maxf(volume * effects_volume, 0.0001))
	_voices[i].play()

func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := ROOT + sound.to_lower() + ("" if sound.to_lower().ends_with(".ogg") else ".ogg")
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]

# --- Music (BGM::play) ----------------------------------------------------------------------

const BGM_BATTLE_COUNT := 19 ## NetManager: play(rand() % 19) when a match starts
const BGM_VICTORY := 19
const BGM_DEFEAT := 23

## BGM::play: stops what was playing and starts entry index. The two entries whose files
## the original could not find stay silent, as they did.
func play_bgm(index: int) -> void:
	_music.stop()
	if not enabled or index < 0 or index >= _bgm.size() or _bgm[index] == null:
		return
	var path := ROOT + "bgm/" + str(_bgm[index])
	if not ResourceLoader.exists(path):
		return
	var stream := (load(path) as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	stream.loop = index != BGM_VICTORY and index != BGM_DEFEAT
	_music.stream = stream
	_music.volume_db = linear_to_db(maxf(music_volume, 0.0001))
	_music.play()

## The track name the options page's player shows: the file name without its folder.
func bgm_name(index: int) -> String:
	if index < 0 or index >= _bgm.size() or _bgm[index] == null:
		return ""
	return str(_bgm[index]).get_basename()

func bgm_count() -> int:
	return _bgm.size()

func is_playing_bgm() -> bool:
	return _music.playing

func play_battle_bgm() -> void:
	play_bgm(randi() % BGM_BATTLE_COUNT)

func stop_bgm() -> void:
	_music.stop()
