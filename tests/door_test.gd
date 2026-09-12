extends Node
## Doors, including a real scene change -- the first test in the project to
## perform one.
##
## A scene change frees the outgoing current_scene, which would normally take
## this test with it. Handing the role to a throwaway node first lets the test
## outlive the transition and inspect what arrived. Everything before now
## checked the decision to travel; this checks the travelling.
##
## No second map is needed: a door leading back to the farm at a different
## spawn exercises the whole path -- fade, threaded load, spawn placement and
## the state that has to survive it.

var pass_count := 0
var fail_count := 0


func check(label: String, condition: bool) -> void:
	if condition:
		pass_count += 1
		print("  PASS  ", label)
	else:
		fail_count += 1
		print("  FAIL  ", label)


func check_eq(label: String, got: Variant, want: Variant) -> void:
	check("%s (got %s, want %s)" % [label, got, want], got == want)


func _ready() -> void:
	# One frame first: during _ready the root is still setting up its children
	# and will refuse add_child, which leaves the stand-in unparented and
	# set_current_scene rejecting it.
	await get_tree().process_frame
	_step_aside()

	# Not SaveManager.new_game: that starts a transition of its own, and a test
	# about transitions should be the only thing starting them.
	GameClock.reset()
	GameState.reset()
	Inventory.reset()

	_test_a_broken_door_refuses()
	await _test_travelling_through_a_door()
	await _test_the_farm_came_with_us()

	SaveManager.delete_slot(9)
	print("\n==================================================")
	print("  door_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


## Gives up being the current scene so the scene change does not free us.
func _step_aside() -> void:
	var stand_in := Node.new()
	stand_in.name = "SceneStandIn"
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in


func _make_door(target_map: StringName, spawn: StringName) -> Door:
	var door: Door = (load("res://src/world/door.tscn") as PackedScene).instantiate()
	door.target_map = target_map
	door.target_spawn = spawn
	return door


func _player() -> Player:
	return get_tree().get_first_node_in_group(&"player")


func _spawn_position(spawn_name: String) -> Vector2:
	var world := get_tree().current_scene as World
	var marker := world.get_node_or_null("SpawnPoints/%s" % spawn_name) as Node2D
	return marker.global_position if marker != null else Vector2.INF


## A door pointing nowhere must say so rather than fading to black and staying
## there.
func _test_a_broken_door_refuses() -> void:
	print("\n--- a door that leads nowhere ---")
	var broken := _make_door(&"atlantis", &"default")
	add_child(broken)
	check("it knows it is broken", not broken.leads_somewhere())
	check("and refuses to be used", not broken.can_interact(null))

	broken.interact(null)
	check("no transition was started", not SceneLoader.is_changing())
	broken.queue_free()

	var good := _make_door(&"farm", &"default")
	add_child(good)
	check("a door to a real map is fine", good.leads_somewhere())
	good.queue_free()


## The real thing: load a map, walk through a door, land on the named spawn.
func _test_travelling_through_a_door() -> void:
	print("\n--- walking through ---")
	await SceneLoader.change_to_map(&"farm", &"default")
	check("the farm loaded", get_tree().current_scene is World)
	check_eq("and is remembered as where we are",
		GameState.current_map, GameConstants.SCENE_WORLD)

	var default_spawn := _spawn_position("Default")
	var porch := _spawn_position("Porch")
	check("the two spawns are different places", default_spawn != porch)
	check_eq("the player started at the default spawn",
		_player().global_position, default_spawn)

	var door := _make_door(&"farm", &"porch")
	get_tree().current_scene.add_child(door)
	door.interact(_player())
	check("a transition began", SceneLoader.is_changing())
	await EventBus.scene_change_finished

	check("we arrived somewhere", get_tree().current_scene is World)
	check_eq("at the spawn the door named", _player().global_position, porch)
	check("which is not where we left from", _player().global_position != default_spawn)


## M3 said map state survives a transition. This is the first time a real one
## has happened, so it is worth asking again.
func _test_the_farm_came_with_us() -> void:
	print("\n--- the field survived a real transition ---")
	var grid: FarmGrid = get_tree().get_first_node_in_group(&"farm_grid")
	grid.till(Vector2i(4, 1))
	grid.till(Vector2i(4, 2))
	check_eq("two cells worked", grid.cells().size(), 2)

	var door := _make_door(&"farm", &"default")
	get_tree().current_scene.add_child(door)
	door.interact(_player())
	await EventBus.scene_change_finished

	var grid_again: FarmGrid = get_tree().get_first_node_in_group(&"farm_grid")
	check_eq("both are still worked after travelling", grid_again.cells().size(), 2)
	check("and it is a different grid node than before", grid_again != grid)
	check_eq("the player is back at the default spawn",
		_player().global_position, _spawn_position("Default"))
