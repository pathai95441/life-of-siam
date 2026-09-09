class_name World
extends Node2D
## Root of a playable map. Places the player, starts the clock, announces
## readiness so parked save data can be applied.
##
## Every gameplay map uses this script (or a subclass). The announcement order
## in [method _ready] is load-bearing:
##   1. spawn the player at the requested spawn point,
##   2. emit world_ready -> SaveManager restores scene-node state, overriding
##      that spawn position when this is a load rather than a door transition,
##   3. start the clock, so no time passes during restoration.
##
## Note what is NOT here: this scene never emits day_started. Views read the
## clock directly in their own _ready; faking a rollover to refresh a label
## would run FarmGrid's daily tick and silently advance every crop on load.

@export var world_music: AudioStream
## Fallback spawn used when the requested spawn point does not exist.
@export var default_spawn: NodePath
## Playable extent of this map in world pixels. The follow camera is clamped to
## it, so the view never shows past the map edge. Per-map level data, which is
## why it lives on the scene rather than in GameConstants.
##
## Must exceed the base viewport in both axes or the clamp cannot help: a map
## narrower than the screen leaves bare ground visible at the sides no matter
## where the camera sits.
@export var bounds := Rect2(-480, -360, 960, 720)

@onready var spawn_points: Node = $SpawnPoints
@onready var entities: Node2D = $Entities


func _ready() -> void:
	add_to_group(&"world")
	_place_player()

	# Scene nodes are in the tree now; let parked save state land on them.
	EventBus.world_ready.emit(self)

	GameState.set_in_game(true)
	GameClock.set_running(true)

	if world_music != null:
		AudioManager.play_music(world_music)


func _place_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		push_error("World: no node in group 'player' — is the Player instanced in %s?" % name)
		return
	var target := _find_spawn(GameState.spawn_point)
	if target != null:
		player.global_position = target.global_position
	if player.has_method("set_camera_limits"):
		player.set_camera_limits(bounds)


func _find_spawn(id: StringName) -> Node2D:
	for child in spawn_points.get_children():
		if StringName(String(child.name).to_snake_case()) == id:
			return child as Node2D
	if not default_spawn.is_empty():
		return get_node_or_null(default_spawn) as Node2D
	if spawn_points.get_child_count() > 0:
		return spawn_points.get_child(0) as Node2D
	return null
