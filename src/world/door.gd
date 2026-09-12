class_name Door
extends Interactable
## Takes the player to another map.
##
## Holds a map id and a spawn name, never a file path: moving a scene should
## not break every door pointing at it. Both are validated at load, because a
## door that leads nowhere fails mid-transition with the screen already black.
##
## Deliberately not blocking: standing in a doorway is normal, and a door you
## cannot stand in is a door you have to aim at.

## Map to travel to, matching a [MapData] id.
@export var target_map: StringName = &""
## Spawn point to arrive at, matching a child of the target map's SpawnPoints.
@export var target_spawn: StringName = &"default"


func _ready() -> void:
	super()
	prompt = "เข้าไป"
	prompt_en = "Enter"
	add_to_group(&"door")
	_warn_if_broken()


func _warn_if_broken() -> void:
	if target_map == &"":
		push_error("Door '%s' has no target_map" % name)
	elif Database.get_map(target_map) == null:
		push_error("Door '%s' points at unknown map '%s'" % [name, target_map])


func can_interact(actor: Node) -> bool:
	return super(actor) and leads_somewhere() and not SceneLoader.is_changing()


## Whether this door has a destination that exists.
func leads_somewhere() -> bool:
	return target_map != &"" and Database.get_map(target_map) != null


func interact(actor: Node) -> void:
	super(actor)
	if not leads_somewhere():
		EventBus.toast_posted.emit("ประตูนี้ไปไหนไม่ได้")
		return
	SceneLoader.change_to_map(target_map, target_spawn)
