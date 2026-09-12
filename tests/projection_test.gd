extends Node
## W6 integration tests: everything spatial goes through [WorldSpace].
##
## Needs the world scene because it exercises the real [FarmGrid] transform and
## the real [Player], not stand-ins.

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
	var world: World = load("res://src/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_movement_is_isotropic()
	_test_screen_velocity_is_projected()
	_test_cell_round_trip()
	_test_cell_screen_shape()
	_test_target_cell_directions()
	_test_probe_matches_target()
	_test_entity_depth_agrees_with_ground(world)

	print("\n==================================================")
	print("  projection_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


## Godot sorts by screen y; our model sorts by ground y. Those agree only
## because screen y is ground y times the depth ratio, and only while entity
## nodes sit at their ground point with any height carried by a child offset.
## If someone ever moves a node up to "raise" it, sorting silently breaks --
## so the equivalence is asserted rather than assumed.
func _test_entity_depth_agrees_with_ground(world: World) -> void:
	print("\n--- entity depth order follows the ground point ---")
	var entities := world.get_node_or_null("Entities") as Node2D
	check("Entities exists", entities != null)
	if entities == null:
		return
	check("Entities is y-sorted", entities.y_sort_enabled)

	var ordered: Array[Node2D] = []
	for child in entities.get_children():
		if child is Node2D:
			ordered.append(child)
	check("there are entities to order", ordered.size() >= 2)

	for node in ordered:
		var ground := WorldSpace.screen_to_ground(node.position)
		check_eq("'%s' screen y matches its ground depth key" % node.name,
			snappedf(node.position.y, 0.001),
			snappedf(WorldSpace.depth_key(ground), 0.001))

	# Sorting by screen y and by ground depth must produce the same sequence.
	var by_screen := ordered.duplicate()
	by_screen.sort_custom(_screen_before)
	var by_ground := ordered.duplicate()
	by_ground.sort_custom(_ground_before)
	check("screen order and ground order are the same sequence", by_screen == by_ground)

	# Height must not leak into depth: the tallest object is not automatically
	# the frontmost one.
	var tallest := _tallest(ordered)
	var frontmost: Node2D = by_ground[-1]
	print("    tallest: %s   frontmost: %s" % [
		tallest.name if tallest else "-", frontmost.name])


static func _screen_before(a: Node2D, b: Node2D) -> bool:
	return a.position.y < b.position.y


static func _ground_before(a: Node2D, b: Node2D) -> bool:
	var key_a := WorldSpace.depth_key(WorldSpace.screen_to_ground(a.position))
	var key_b := WorldSpace.depth_key(WorldSpace.screen_to_ground(b.position))
	return key_a < key_b


func _tallest(nodes: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var best_height := -1.0
	for node in nodes:
		var body := node.get_node_or_null("WorldBody") as WorldBody
		if body == null or body.data == null:
			continue
		if body.data.height > best_height:
			best_height = body.data.height
			best = node
	return best


func _player() -> Player:
	return get_tree().get_first_node_in_group(&"player")


func _grid() -> FarmGrid:
	return get_tree().get_first_node_in_group(&"farm_grid")


## D13, the bug this task exists to fix: at equal input the player must cover
## the same ground per second in every direction. Before W6 the velocity was
## integrated in screen pixels, so heading south crossed twice the world
## distance of heading east.
func _test_movement_is_isotropic() -> void:
	print("\n--- movement is isotropic in world units (D13) ---")
	var player := _player()
	if player == null:
		check("player exists", false)
		return

	var east := _settled_ground_speed(player, Vector2.RIGHT)
	var south := _settled_ground_speed(player, Vector2.DOWN)
	var north := _settled_ground_speed(player, Vector2.UP)
	var west := _settled_ground_speed(player, Vector2.LEFT)

	print("    ground speed east %.3f  south %.3f  north %.3f  west %.3f wu/s"
		% [east, south, north, west])
	check("east and south cover the same ground", is_equal_approx(east, south))
	check("north and west cover the same ground", is_equal_approx(north, west))
	check("all four axes agree", is_equal_approx(east, north))
	check_eq("settled speed is the configured walk speed",
		snappedf(east, 0.001), snappedf(player.walk_speed, 0.001))


## Drives the movement model to a steady state and returns the ground speed.
func _settled_ground_speed(player: Player, direction: Vector2) -> float:
	player.ground_velocity = Vector2.ZERO
	for _i in 200:
		player.integrate_ground_velocity(1.0 / 60.0, direction, player.walk_speed)
	return player.ground_velocity.length()


## The screen velocity must still be asymmetric -- that asymmetry is the
## projection doing its job. Equal on screen would mean it was never applied.
func _test_screen_velocity_is_projected() -> void:
	print("\n--- screen velocity stays foreshortened ---")
	var player := _player()
	player.ground_velocity = Vector2.ZERO
	player.integrate_ground_velocity(10.0, Vector2.RIGHT, player.walk_speed)
	var screen_east := WorldSpace.ground_to_screen(player.ground_velocity)

	player.ground_velocity = Vector2.ZERO
	player.integrate_ground_velocity(10.0, Vector2.DOWN, player.walk_speed)
	var screen_south := WorldSpace.ground_to_screen(player.ground_velocity)

	print("    screen px/s east %.1f  south %.1f" % [screen_east.x, screen_south.y])
	check("moving east covers more pixels than moving south",
		screen_east.x > screen_south.y)
	check_eq("the ratio is exactly the depth ratio",
		snappedf(screen_south.y / screen_east.x, 0.0001),
		snappedf(GameConstants.DEPTH_RATIO, 0.0001))
	player.ground_velocity = Vector2.ZERO


func _test_cell_round_trip() -> void:
	print("\n--- cell <-> screen round trip through the grid ---")
	var grid := _grid()
	if grid == null:
		check("farm grid exists", false)
		return
	for cell in [Vector2i(0, 0), Vector2i(3, 5), Vector2i(-4, -7), Vector2i(11, -2)]:
		check_eq("%s survives cell -> screen -> cell" % cell,
			grid.world_to_cell(grid.cell_to_world(cell)), cell)


## A cell is a square on the ground and a foreshortened rectangle on screen.
func _test_cell_screen_shape() -> void:
	print("\n--- cell shape on screen ---")
	var grid := _grid()
	var origin := grid.cell_to_world(Vector2i(0, 0))
	var east := grid.cell_to_world(Vector2i(1, 0))
	var south := grid.cell_to_world(Vector2i(0, 1))

	check_eq("one cell east is one ground unit of pixels",
		east.x - origin.x, WorldSpace.ground_px())
	check_eq("one cell south is foreshortened",
		south.y - origin.y, WorldSpace.depth_px())
	check("a cell is wider than it is tall on screen",
		(east.x - origin.x) > (south.y - origin.y))


## The tool must hit the cell the player is facing, in all four directions.
func _test_target_cell_directions() -> void:
	print("\n--- tool targeting follows facing ---")
	var player := _player()
	var grid := _grid()
	var start := Vector2i(2, 3)
	player.global_position = grid.cell_to_world(start)

	var cases := {
		"east": [Vector2.RIGHT, Vector2i(1, 0)],
		"west": [Vector2.LEFT, Vector2i(-1, 0)],
		"south": [Vector2.DOWN, Vector2i(0, 1)],
		"north": [Vector2.UP, Vector2i(0, -1)],
	}
	for direction_name in cases:
		var case: Array = cases[direction_name]
		player.set_facing(case[0])
		check_eq("facing %s targets the adjacent cell" % direction_name,
			player.target_cell(), start + (case[1] as Vector2i))


## The prompt and the tool must agree: the probe has to sit over the very cell
## target_cell reports, or the player sees "press E" for something out of reach.
func _test_probe_matches_target() -> void:
	print("\n--- probe and target agree ---")
	var player := _player()
	var grid := _grid()
	player.global_position = grid.cell_to_world(Vector2i(0, 0))
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		player.set_facing(direction)
		var probe_cell := grid.world_to_cell(player.probe.global_position)
		check_eq("facing %s: probe sits on the targeted cell" % direction,
			probe_cell, player.target_cell())
