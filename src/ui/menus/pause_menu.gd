extends CanvasLayer
## In-game pause. Owns [member SceneTree.paused] and nothing else.
##
## Only one node in the project is allowed to set `paused`; centralising it
## here is what prevents the classic bug where two menus disagree about
## whether the game is running.

@onready var panel: Control = %Panel
@onready var resume_button: Button = %ResumeButton
@onready var save_button: Button = %SaveButton
@onready var settings_button: Button = %SettingsButton
@onready var menu_button: Button = %MenuButton
@onready var settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	# Must keep processing input while the rest of the tree is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.hide()

	resume_button.pressed.connect(func() -> void: _set_paused(false))
	save_button.pressed.connect(_on_save)
	settings_button.pressed.connect(func() -> void: settings_menu.open())
	menu_button.pressed.connect(_on_main_menu)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if DialogueSystem.is_active() or SceneLoader.is_changing():
		return
	if settings_menu.visible:
		settings_menu.close()
		get_viewport().set_input_as_handled()
		return
	_set_paused(not panel.visible)
	get_viewport().set_input_as_handled()


func _set_paused(paused: bool) -> void:
	panel.visible = paused
	get_tree().paused = paused
	GameClock.set_running(not paused and GameState.is_in_game())
	EventBus.game_paused.emit(paused)
	if paused:
		resume_button.grab_focus()


func _on_save() -> void:
	SaveManager.save_to_slot(SaveManager.current_slot)


func _on_main_menu() -> void:
	_set_paused(false)
	SceneLoader.to_main_menu()
