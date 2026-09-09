extends Node
## Music with crossfade plus a small pooled one-shot SFX player.
##
## Pooled rather than spawn-per-sound: allocating an [AudioStreamPlayer] per
## footstep churns the scene tree, and a fixed pool caps the worst case.

const SFX_POOL_SIZE := 12
const CROSSFADE_TIME := 1.2

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _current_music_path: String = ""


func _ready() -> void:
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	_music_active = _music_a
	for _i in SFX_POOL_SIZE:
		_sfx_pool.append(_make_player("SFX"))


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	# Music and UI sound must keep playing while the tree is paused.
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


# --- Music -------------------------------------------------------------------

func play_music(stream: AudioStream, crossfade: bool = true) -> void:
	if stream == null:
		return
	if stream.resource_path == _current_music_path and _music_active.playing:
		return  # Already playing this track; do not restart it.
	_current_music_path = stream.resource_path

	var incoming := _music_b if _music_active == _music_a else _music_a
	incoming.stream = stream
	incoming.volume_db = -40.0 if crossfade else 0.0
	incoming.play()

	if crossfade:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(incoming, "volume_db", 0.0, CROSSFADE_TIME)
		if _music_active.playing:
			var outgoing := _music_active
			tween.tween_property(outgoing, "volume_db", -40.0, CROSSFADE_TIME)
			tween.chain().tween_callback(outgoing.stop)
	else:
		_music_active.stop()

	_music_active = incoming


func stop_music(fade: bool = true) -> void:
	_current_music_path = ""
	if not _music_active.playing:
		return
	if fade:
		var outgoing := _music_active
		var tween := create_tween()
		tween.tween_property(outgoing, "volume_db", -40.0, CROSSFADE_TIME)
		tween.tween_callback(outgoing.stop)
	else:
		_music_active.stop()


# --- SFX ---------------------------------------------------------------------

func play_sfx_stream(stream: AudioStream, pitch_variation: float = 0.0) -> void:
	if stream == null:
		return
	var player := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.volume_db = 0.0
	player.play()


func play_sfx(path: String, pitch_variation: float = 0.0) -> void:
	if not ResourceLoader.exists(path):
		return  # Placeholder assets are expected to be missing during blockout.
	play_sfx_stream(load(path), pitch_variation)
