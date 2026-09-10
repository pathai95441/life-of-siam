class_name InteractionProbe
extends Area2D
## Sits in front of the player and tracks the best [Interactable] in range.
##
## "Best" = highest priority, nearest on a tie. Focus changes are broadcast so
## the HUD can show a prompt without polling every frame.

## How far in front of the actor the probe sits, in world units.
@export var reach_units: float = GameConstants.PROBE_REACH_UNITS

var focused: Interactable = null

var _actor: Node2D


const SENSOR_SHAPE_NAME := "ProbeSensor"


func _ready() -> void:
	_actor = owner as Node2D
	collision_layer = 0
	collision_mask = GameConstants.layer_mask(GameConstants.Layer.INTERACTABLE)
	monitoring = true
	# Deferred for the same reason as WorldBody.rebuild -- see that comment.
	_build_sensor.call_deferred()


## Built here rather than authored, for the same reason [WorldBody] builds its
## shapes: a sensor size sitting in a .tscn is a number nobody revisits.
func _build_sensor() -> void:
	var shape_node := get_node_or_null(SENSOR_SHAPE_NAME) as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = SENSOR_SHAPE_NAME
		add_child(shape_node)
	var rect := RectangleShape2D.new()
	rect.size = WorldSpace.footprint_screen_size(GameConstants.PROBE_SIZE_UNITS)
	shape_node.shape = rect


## Called by the actor whenever its facing changes.
##
## [param facing] is a direction on the ground plane. The offset is projected,
## so the probe lands exactly where [method Player.target_cell] points and the
## prompt can never appear for a cell the tool cannot reach.
func point_towards(facing: Vector2) -> void:
	if facing.is_zero_approx():
		return
	position = WorldSpace.ground_to_screen(facing.normalized() * reach_units)


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
