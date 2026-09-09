class_name InteractionProbe
extends Area2D
## Sits in front of the player and tracks the best [Interactable] in range.
##
## "Best" = highest priority, nearest on a tie. Focus changes are broadcast so
## the HUD can show a prompt without polling every frame.

## How far in front of the actor the probe sits, in pixels.
@export var reach: float = 12.0

var focused: Interactable = null

var _actor: Node2D


func _ready() -> void:
	_actor = owner as Node2D
	collision_layer = 0
	collision_mask = GameConstants.layer_mask(GameConstants.Layer.INTERACTABLE)
	monitoring = true


## Called by the actor whenever its facing changes.
func point_towards(facing: Vector2) -> void:
	if facing.is_zero_approx():
		return
	position = facing.normalized() * reach


func _physics_process(_delta: float) -> void:
	var best := _pick_best()
	if best == focused:
		return
	if focused != null:
		EventBus.interactable_unfocused.emit(focused)
	focused = best
	if focused != null:
		EventBus.interactable_focused.emit(focused)


func _pick_best() -> Interactable:
	var best: Interactable = null
	var best_priority := -(1 << 30)
	var best_distance := INF
	for area in get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not candidate.can_interact(_actor):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if candidate.focus_priority > best_priority \
			or (candidate.focus_priority == best_priority and distance < best_distance):
			best = candidate
			best_priority = candidate.focus_priority
			best_distance = distance
	return best


## Fires the focused interactable. Returns false when there was nothing to hit.
func try_interact() -> bool:
	if focused == null or not focused.can_interact(_actor):
		return false
	focused.interact(_actor)
	return true
