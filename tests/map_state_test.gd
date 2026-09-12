extends Node
## P3: does what you did to a map survive leaving it?
##
## The first test here is the one the whole task exists for, deliberately not
## the last. Everything else in the phase is reachable by playing badly for a
## minute; this one loses a day's work in silence.
##
## Maps are swapped by tearing the world down and building it again, which is
## what a real transition does, driven through the same signals SceneLoader
## emits. No second map scene is needed to prove the mechanism.

var pass_count := 0
var fail_count := 0

var _world: World


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
	SaveManager.new_game(9)
	await _enter_map(&"farm")

	await _test_leaving_and_returning_keeps_the_farm()
	await _test_another_map_does_not_inherit_it()
	await _test_shipping_bin_survives_the_trip()
	await _test_a_door_does_not_restore_an_old_position()

	SaveManager.delete_slot(9)
	print("\n==================================================")
	print("  map_state_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


# --- Driving transitions -----------------------------------------------------

## Tears down whatever map is loaded, exactly as a real transition does:
## announce the change while the old scene is still readable, then destroy it.
func _leave_map() -> void:
	if _world == null:
		return
	EventBus.scene_change_started.emit("res://somewhere/else.tscn")
	remove_child(_world)
	_world.free()
	_world = null
	await get_tree().process_frame


func _enter_map(map_id: StringName) -> void:
	_world = (load(GameConstants.SCENE_WORLD) as PackedScene).instantiate()
	_world.map_id = map_id
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame


func _grid() -> FarmGrid:
	return get_tree().get_first_node_in_group(&"farm_grid")


## The headline. Dig a field, walk out, walk back in.
func _test_leaving_and_returning_keeps_the_farm() -> void:
	print("\n--- leave the farm and come back ---")
	var cells := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-3, 2)]
	for cell in cells:
		_grid().till(cell)
	_grid().plant(Vector2i(0, 0), Database.get_crop(&"turnip"))
	_grid().water(Vector2i(0, 0))
	check_eq("three cells worked before leaving", _grid().cells().size(), 3)

	await _leave_map()
	await _enter_map(&"farm")

	check_eq("all three are still there", _grid().cells().size(), 3)
	for cell in cells:
		check("%s is still tilled" % cell,
			_grid().get_cell(cell) != null and _grid().get_cell(cell).tilled)
	var soil := _grid().get_cell(Vector2i(0, 0))
	check("the planted cell still has its crop", soil.has_crop())
	check("and is still watered", soil.watered)


## P2 from the other side: a different map must start empty rather than
## inheriting whatever the last one had.
func _test_another_map_does_not_inherit_it() -> void:
	print("\n--- a different map starts empty ---")
	await _leave_map()
	await _enter_map(&"house")
	check_eq("the house has no soil of its own", _grid().cells().size(), 0)

	_grid().till(Vector2i(7, 7))
	await _leave_map()
	await _enter_map(&"farm")

	check_eq("the farm still has exactly its own three", _grid().cells().size(), 3)
	check("and none of the house's", _grid().get_cell(Vector2i(7, 7)) == null)

	await _leave_map()
	await _enter_map(&"house")
	check("the house kept its own cell too",
		_grid().get_cell(Vector2i(7, 7)) != null)
	await _leave_map()
	await _enter_map(&"farm")


func _bin() -> ShippingBin:
	for node in get_tree().get_nodes_in_group(&"interactable"):
		if node is ShippingBin:
			return node
	return null


## Produce left in a bin is the player's property, so it has to survive a walk
## to the shop as surely as it survives a save.
func _test_shipping_bin_survives_the_trip() -> void:
	print("\n--- goods left in the bin ---")
	Inventory.reset()
	Inventory.add_item(&"turnip", 3)
	Inventory.select(0)
	_bin().interact(null)
	var value := _bin().pending_value()
	check("the bin holds something", value > 0)

	await _leave_map()
	await _enter_map(&"farm")

	check_eq("still holding it after the round trip", _bin().pending_value(), value)
	var before := GameState.money
	GameClock.sleep_until_morning()
	check_eq("and it still pays out", GameState.money, before + value)


## D18: the player is a traveller, not part of a map. Re-entering must place
## them at the spawn point rather than where they last stood here.
func _test_a_door_does_not_restore_an_old_position() -> void:
	print("\n--- arriving through a door ---")
	var player: Player = get_tree().get_first_node_in_group(&"player")
	var spawn := player.global_position
	player.global_position = spawn + Vector2(200, 120)
	check("the player moved away from the spawn",
		player.global_position != spawn)

	await _leave_map()
	await _enter_map(&"farm")

	var returned: Player = get_tree().get_first_node_in_group(&"player")
	check_eq("they arrive at the spawn, not where they wandered off to",
		returned.global_position, spawn)
