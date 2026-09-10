class_name PlaceholderVisual
extends Node
## Sizes a stand-in visual from [WorldObjectData] so the screen tells the truth
## about scale before any real art exists.
##
## Temporary by design. Every object is drawn as an upright quad standing on
## its ground position -- the honest 2.5D reading of "something this wide and
## this tall" -- and the proportions come from the resource, never the reverse.
## When real sprites are authored at the correct size, delete this component
## and its wiring; nothing else depends on it.
##
## Reads its dimensions through a sibling [WorldBody] rather than taking its
## own [WorldObjectData], so an object's size is declared in exactly one place.

## Sibling component holding the resource. Size comes from its data.
@export var world_body: WorldBody
## Stand-in to resize: a [Sprite2D] or a [ColorRect].
@export var target: CanvasItem


func _ready() -> void:
	# Same deferral as WorldBody: the parent is still setting up children, and
	# a Sprite2D's texture may not be resolved yet during instantiation.
	apply.call_deferred()


func apply() -> void:
	if world_body == null or world_body.data == null or target == null:
		push_error("PlaceholderVisual on '%s' is not fully wired" % _owner_name())
		return
	var size := _screen_size(world_body.data)
	if target is Sprite2D:
		_fit_sprite(target as Sprite2D, size)
	elif target is ColorRect:
		_fit_rect(target as ColorRect, size)
	else:
		push_error("PlaceholderVisual on '%s': target must be a Sprite2D or ColorRect"
			% _owner_name())


## Width from the footprint, height from the elevation. A flat object still
## gets a sliver of height so it does not vanish during blockout.
func _screen_size(data: WorldObjectData) -> Vector2:
	return Vector2(
		data.width() * WorldSpace.ground_px(),
		maxf(data.height * WorldSpace.height_px(), WorldSpace.depth_px() * data.depth())
	)


## Scaled non-uniformly on purpose: a placeholder icon squashed to the right
## proportions is more useful than an undistorted one that lies about size.
func _fit_sprite(sprite: Sprite2D, size: Vector2) -> void:
	var texture := sprite.texture
	if texture == null:
		return
	sprite.scale = size / Vector2(texture.get_size())
	sprite.position = Vector2(0.0, -size.y * 0.5)


func _fit_rect(rect: ColorRect, size: Vector2) -> void:
	rect.size = size
	rect.position = Vector2(-size.x * 0.5, -size.y)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _owner_name() -> String:
	var node := owner if owner != null else get_parent()
	return String(node.name) if node != null else "<detached>"
