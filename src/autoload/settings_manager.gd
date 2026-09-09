extends Node
## Player preferences persisted to user://settings.cfg.
##
## Deliberately separate from [SaveManager]: settings are per-machine and must
## survive deleting every save slot, so they never enter the save payload.

const SECTION_AUDIO := "audio"
const SECTION_VIDEO := "video"
const SECTION_GAME := "game"

var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var fullscreen: bool = false
var vsync: bool = true
var language: String = "th"
var show_debug: bool = false

var _config := ConfigFile.new()


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	if _config.load(GameConstants.SETTINGS_PATH) != OK:
		return  # First run: keep defaults, they get written on first save.
	master_volume = _config.get_value(SECTION_AUDIO, "master", master_volume)
	music_volume = _config.get_value(SECTION_AUDIO, "music", music_volume)
	sfx_volume = _config.get_value(SECTION_AUDIO, "sfx", sfx_volume)
	fullscreen = _config.get_value(SECTION_VIDEO, "fullscreen", fullscreen)
	vsync = _config.get_value(SECTION_VIDEO, "vsync", vsync)
	language = _config.get_value(SECTION_GAME, "language", language)
	show_debug = _config.get_value(SECTION_GAME, "show_debug", show_debug)


func save_settings() -> void:
	_config.set_value(SECTION_AUDIO, "master", master_volume)
	_config.set_value(SECTION_AUDIO, "music", music_volume)
	_config.set_value(SECTION_AUDIO, "sfx", sfx_volume)
	_config.set_value(SECTION_VIDEO, "fullscreen", fullscreen)
	_config.set_value(SECTION_VIDEO, "vsync", vsync)
	_config.set_value(SECTION_GAME, "language", language)
	_config.set_value(SECTION_GAME, "show_debug", show_debug)
	var err := _config.save(GameConstants.SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: could not write settings (%d)" % err)


func apply_all() -> void:
	_apply_bus("Master", master_volume)
	_apply_bus("Music", music_volume)
	_apply_bus("SFX", sfx_volume)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	EventBus.settings_applied.emit()


func set_volume(bus_name: String, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	match bus_name:
		"Master": master_volume = linear
		"Music": music_volume = linear
		"SFX": sfx_volume = linear
		_:
			push_warning("SettingsManager: unknown bus '%s'" % bus_name)
			return
	_apply_bus(bus_name, linear)
	save_settings()


func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return  # Bus layout not loaded yet; apply_all() runs again after boot.
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, is_zero_approx(linear))
