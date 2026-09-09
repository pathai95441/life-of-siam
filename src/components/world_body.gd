class_name WorldBody
extends Node
## Builds an object's collision and interaction shapes from its
## [WorldObjectData], at runtime, so no scene carries a hand-tuned size.
##
## Scope is deliberately narrow: this component decides how big a shape is and
## where it sits. It never touches collision layers or masks -- those already
## have owners ([Interactable], [InteractionProbe], [Player], and the Body
## nodes in each scene), and splitting size from physics-graph membership is
## what keeps either from becoming a place where everything happens.
##
## Wiring is explicit rather than discovered. The scene says which nodes to
## size through [member collision_body] and [member interaction_area]; the
## resource says how big. Nothing is found by walking the tree, so reading a
## scene tells you the whole story.
##
## The shape nodes are created here, not authored, which is the point: an
## authored CollisionShape2D is a number someone eyeballed once and nobody
## revisits. Expect the assigned bodies to look shapeless in the editor.

## Physical definition. Without it the component does nothing and says so.
@export var data: WorldObjectData

@export_group("Wiring")
## Body whose solid footprint stops movement. Leave empty for objects that can
## be walked through.
@export var collision_body: CollisionObject2D
## Area defining where the object can be interacted with. Sized to the
## footprint grown by [member WorldObjectData.interaction_reach].
@export var interaction_area: Area2D

const COLLISION_SHAPE_NAME := "WorldBodyCollision"
const INTERACTION_SHAPE_NAME := "WorldBodyInteraction"


func _ready() -> void:
	# Deferred, not immediate: during scene instantiation the parent is still
	# setting up its children and the engine rejects add_child outright
	# ("Parent node is busy setting up children"). One frame later it is safe,
	# and the deferred queue is flushed before gameplay runs.
	rebuild.call_deferred()


## Recreates both shapes from the current [member data]. Public so a tool or a
## live tweak can re-apply a changed resource without reloading the scene.
func rebuild() -> void:
	if data == null:
		push_error("WorldBody on '%s' has no WorldObjectData" % _owner_name())
		return
	var errors := data.validation_errors()
	if not errors.is_empty():
		for error in errors:
			push_error("WorldBody on '%s': %s" % [_owner_name(), error])
		return
	_build_collision()
	_build_interaction()


func _build_collision() -> void:
	if collision_body == null:
		# Data and wiring disagree: something declared solid has nothing to be
		# solid with, and would silently be walked through.
		if data.blocks_movement:
			push_error("WorldBody on '%s': data blocks movement but no collision_body is wired"
				% _owner_name())
		return
	_apply_shape(collision_body, COLLISION_SHAPE_NAME,
		data.collision_screen_size(), data.collision_screen_offset())


func _build_interaction() -> void:
	if interaction_area == null:
		return
	if not data.is_interactable():
		push_warning("WorldBody on '%s': interaction_area is wired but interaction_reach is 0"
			% _owner_name())
		return
	_apply_shape(interaction_area, INTERACTION_SHAPE_NAME,
		data.interaction_screen_size(), data.collision_screen_offset())


## Creates the named [CollisionShape2D] under [param target], or reuses it if
## [method rebuild] has run before, so repeated builds cannot stack up shapes.
func _apply_shape(target: CollisionObject2D, node_name: String,
		size: Vector2, offset: Vector2) -> CollisionShape2D:
	var shape_node := target.get_node_or_null(node_name) as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = node_name
		target.add_child(shape_node)

	var rect := RectangleShape2D.new()
	rect.size = size
	shape_node.shape = rect
	shape_node.position = offset
	return shape_node


# --- Queries ----------------------------------------------------------------

func collision_shape() -> CollisionShape2D:
	if collision_body == null:
		return null
	return collision_body.get_node_or_null(COLLISION_SHAPE_NAME) as CollisionShape2D


func interaction_shape() -> CollisionShape2D:
	if interaction_area == null:
		return null
	return interaction_area.get_node_or_null(INTERACTION_SHAPE_NAME) as CollisionShape2D


func _owner_name() -> String:
	var node := owner if owner != null else get_parent()
	return String(node.name) if node != null else "<detached>"
