class_name Bed
extends Interactable
## Ends the day: rolls the clock to the next morning and autosaves.
##
## Saving on sleep rather than on quit is the genre convention and it gives the
## save system a natural, testable trigger point.

@export var confirm_before_sleep: bool = false


func _ready() -> void:
	super()
	prompt = "นอน"
	prompt_en = "Sleep"
	focus_priority = 10  # A bed should win over anything decorative next to it.


func interact(actor: Node) -> void:
	super(actor)
	var player := actor as Player
	if player != null:
		player.lock(&"sleeping")

	EventBus.player_slept.emit()
	# day_started fires inside here; FarmGrid and GameState react to it.
	GameClock.sleep_until_morning()
	SaveManager.save_to_slot(SaveManager.current_slot)

	if player != null:
		player.unlock()
