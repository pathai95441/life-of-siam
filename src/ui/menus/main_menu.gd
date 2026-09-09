extends Control
## Boot scene. Starts a new game, continues an existing one, or quits.
##
## This is the project's [member ProjectSettings.application/run/main_scene]:
## booting into the menu rather than the world means the autoloads finish
## initialising (Database scan, settings load) before any gameplay exists.

@onready var new_game_button: Button = %NewGameButton
@onready var continue_button: Button = %ContinueButton
@onready var slots_box: VBoxContainer = %SlotsBox
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel
@onready var settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	GameState.set_in_game(false)
	GameClock.set_running(false)
	get_tree().paused = false

	new_game_button.pressed.connect(_on_new_game)
	continue_button.pressed.connect(_on_continue)
	settings_button.pressed.connect(func() -> void: settings_menu.open())
	quit_button.pressed.connect(func() -> void: get_tree().quit())

	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	_build_slot_list()
	new_game_button.grab_focus()


func _build_slot_list() -> void:
	for child in slots_box.get_children():
		child.queue_free()

	var any_slot := false
	for slot in GameConstants.SAVE_SLOT_COUNT:
		var header := SaveManager.read_slot_header(slot)
		var button := Button.new()
		if header.is_empty():
			button.text = "ช่อง %d — ว่าง" % (slot + 1)
			button.disabled = true
		else:
			any_slot = true
			button.text = "ช่อง %d — %s · วันที่ %d %s ปีที่ %d · %d฿" % [
				slot + 1,
				header.get("farm_name", "?"),
				int(header.get("day", 1)),
				GameConstants.SEASON_NAMES_TH[clampi(int(header.get("season", 0)), 0, 3)],
				int(header.get("year", 1)),
				int(header.get("money", 0)),
			]
			button.pressed.connect(_on_load_slot.bind(slot))
		slots_box.add_child(button)

	continue_button.disabled = not any_slot


func _on_new_game() -> void:
	# First free slot, or slot 0 when every slot is taken.
	var target := 0
	for slot in GameConstants.SAVE_SLOT_COUNT:
		if not SaveManager.slot_exists(slot):
			target = slot
			break
	GameState.set_in_game(true)
	SaveManager.new_game(target, "Siam Farm", GameState.player_name)


func _on_continue() -> void:
	# The most recently saved slot is the one "Continue" means.
	var best_slot := -1
	var best_time := ""
	for slot in GameConstants.SAVE_SLOT_COUNT:
		var header := SaveManager.read_slot_header(slot)
		if header.is_empty():
			continue
		var saved_at := String(header.get("saved_at", ""))
		if best_slot < 0 or saved_at > best_time:
			best_slot = slot
			best_time = saved_at
	if best_slot >= 0:
		_on_load_slot(best_slot)


func _on_load_slot(slot: int) -> void:
	GameState.set_in_game(true)
	if not SaveManager.load_from_slot(slot):
		GameState.set_in_game(false)
		push_error("MainMenu: could not load slot %d" % slot)
