class_name Interactable
extends Area2D
## Attach to anything the player can press "interact" on.
##
## The object decides what interaction *means* by overriding [method interact];
## the player only decides *when*. That inversion is what lets NPCs, beds,
## signs and shipping bins share one probe on the player.

## Shown by the HUD when this object has focus.
@export var prompt: String = "คุย"
@export var prompt_en: String = "Talk"
## Higher wins when several interactables overlap the probe at the same time.
## Named focus_priority, not priority: Area2D already defines a native
## `priority` property (area processing order) and shadowing it is a parse error.
@export var focus_priority: int = 0
@export var enabled: bool = true
## Interactables that should not respond while the clock is stopped (cutscene,
## dialogue) can opt out here.
@export var blocked_during_dialogue: bool = true


func _ready() -> void:
	collision_layer = GameConstants.layer_mask(GameConstants.Layer.INTERACTABLE)
	collision_mask = 0  # Detected by the player's probe; detects nothing itself.
	add_to_group(&"interactable")


func can_interact(_actor: Node) -> bool:
	if not enabled:
		return false
	if blocked_during_dialogue and DialogueSystem.is_active():
		return false
	return true


## Override this. The base implementation only announces the interaction so
## that a subclass forgetting to call super() is still observable in logs.
func interact(actor: Node) -> void:
	EventBus.interaction_performed.emit(self, actor)


func label() -> String:
	return prompt if not prompt.is_empty() else prompt_en


## Node name, for diagnostics. Distinct from [method label], which is the verb
## shown to the player.
func owner_label() -> String:
	return String(name)
