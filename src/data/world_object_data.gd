class_name WorldObjectData
extends Resource
## The physical definition of one kind of world object, in world units.
##
## This resource is the single authority on how big something is. Sprite
## dimensions must never be read back into gameplay: art gets redrawn, and the
## rules must not change when it does.
##
## The 2.5D contract keeps four extents apart, and this resource covers the
## three that gameplay is allowed to see:
##
##   logical footprint   [member footprint] -- the ground the object stands on.
##                       Every rule that asks "where is this" means this.
##   collision bounds    derived from the footprint, see
##                       [method collision_screen_size].
##   interaction bounds  the footprint grown by [member interaction_reach].
##   visual bounds       NOT here. It belongs to the sprite and feeds nothing.
##
## [member height] carries no collision in a 2.5D projection; it exists so
## sprite proportions and shadow placement have an authoritative number, and so
## the scale stays consistent between a person, a fence and a tree.

@export var id: StringName = &""
@export var display_name_th: String = ""

@export_group("Footprint")
## Ground extent in world units: x is width (east-west), y is depth
## (north-south into the screen). One unit is roughly one metre.
@export var footprint := Vector2.ONE
## Elevation in world units. Visual and proportional only; nothing collides
## with it in an oblique projection.
@export var height: float = 1.0
## Where the object's position sits inside its footprint, normalised.
## (0.5, 0.5) centres it; (0.5, 1.0) puts the front edge on the position.
@export var origin := Vector2(0.5, 0.5)

@export_group("Bounds")
## Whether other bodies are stopped by this object's footprint.
@export var blocks_movement: bool = false
## How far beyond the footprint this object can be interacted with, in world
## units. 0 means it is not interactable at all.
@export var interaction_reach: float = 0.0


# --- Named extents (the 2.5D vocabulary) ------------------------------------

func width() -> float:
	return footprint.x


func depth() -> float:
	return footprint.y


# --- Derived bounds ---------------------------------------------------------

## Ground rectangle this object occupies when standing at [param ground].
func footprint_rect(ground: Vector2) -> Rect2:
	return WorldSpace.footprint_rect(ground, footprint, origin)


## Ground rectangle within which the object can be interacted with.
func interaction_rect(ground: Vector2) -> Rect2:
	return footprint_rect(ground).grow(interaction_reach)


func is_interactable() -> bool:
	return interaction_reach > 0.0


## Collision shape size in screen pixels, foreshortened along the depth axis.
## Task W3 builds shapes from this instead of hand-tuned numbers in scenes.
func collision_screen_size() -> Vector2:
	return WorldSpace.footprint_screen_size(footprint)


func interaction_screen_size() -> Vector2:
	return WorldSpace.footprint_screen_size(footprint + Vector2.ONE * interaction_reach * 2.0)


## Screen offset from the object's position to the centre of its footprint.
## Non-zero whenever [member origin] is not centred, which is why shape
## placement must go through here rather than being eyeballed per scene.
func collision_screen_offset() -> Vector2:
	var centre_in_footprint := Vector2(0.5, 0.5) - origin
	return WorldSpace.ground_to_screen(centre_in_footprint * footprint)


# --- Validation -------------------------------------------------------------

## Every reason this definition is unusable, empty when it is fine.
## Returned as text rather than a bool so a bad .tres names its own problem.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	if footprint.x <= 0.0 or footprint.y <= 0.0:
		errors.append("footprint must be positive on both axes, got %s" % footprint)
	if height < 0.0:
		errors.append("height cannot be negative, got %f" % height)
	if origin.x < 0.0 or origin.x > 1.0 or origin.y < 0.0 or origin.y > 1.0:
		errors.append("origin must be normalised to 0..1, got %s" % origin)
	if interaction_reach < 0.0:
		errors.append("interaction_reach cannot be negative, got %f" % interaction_reach)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
