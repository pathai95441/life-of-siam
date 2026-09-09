class_name SettingsMenu
extends Control
## Volume, display and language. Writes straight through to
## [SettingsManager], which owns persistence.
##
## Reused by both the main menu and the pause menu, so it must never assume
## a game is running.

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var back_button: Button = %BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	master_slider.value_changed.connect(func(v: float) -> void: SettingsManager.set_volume("Master", v))
	music_slider.value_changed.connect(func(v: float) -> void: SettingsManager.set_volume("Music", v))
	sfx_slider.value_changed.connect(func(v: float) -> void: SettingsManager.set_volume("SFX", v))
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(close)


func open() -> void:
	_pull_from_settings()
	show()
	back_button.grab_focus()
	EventBus.ui_window_opened.emit(&"settings")


func close() -> void:
	hide()
	EventBus.ui_window_closed.emit(&"settings")


## Read the live values in rather than trusting the scene's saved defaults.
func _pull_from_settings() -> void:
	master_slider.set_value_no_signal(SettingsManager.master_volume)
	music_slider.set_value_no_signal(SettingsManager.music_volume)
	sfx_slider.set_value_no_signal(SettingsManager.sfx_volume)
	fullscreen_check.set_pressed_no_signal(SettingsManager.fullscreen)


func _on_fullscreen_toggled(pressed: bool) -> void:
	SettingsManager.fullscreen = pressed
	SettingsManager.apply_all()
	SettingsManager.save_settings()
