extends Node
## Integration tests that need the world scene in the tree.
##
## Kept separate from tests/smoke_test.gd, which is pure logic and needs no
## scene. Anything here costs a scene instantiation, so only put things here
## that genuinely cannot be checked without one.

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

	_test_camera_limits(world)
	_test_hud_hotbar()
	_test_scene_change_guards()

	print("\n==================================================")
	print("  world_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _test_camera_limits(world: World) -> void:
	print("\n--- camera limits (D8) ---")
	var player: Player = get_tree().get_first_node_in_group(&"player")
	check("player is in the world", player != null)
	if player == null:
		return
	var cam := player.camera
	check_eq("limit_left matches bounds", cam.limit_left, int(world.bounds.position.x))
	check_eq("limit_top matches bounds", cam.limit_top, int(world.bounds.position.y))
	check_eq("limit_right matches bounds", cam.limit_right, int(world.bounds.end.x))
	check_eq("limit_bottom matches bounds", cam.limit_bottom, int(world.bounds.end.y))
	check("limits form a non-empty box",
		cam.limit_right > cam.limit_left and cam.limit_bottom > cam.limit_top)


func _test_hud_hotbar() -> void:
	print("\n--- hud hotbar (D7) ---")
	var hotbar := _find_hotbar()
	check("hotbar was built", hotbar != null)
	if hotbar == null:
		return
	check_eq("cell count matches HOTBAR_SLOTS",
		hotbar.get_child_count(), GameConstants.HOTBAR_SLOTS)
	var cell := hotbar.get_child(0) as Panel
	check("cell clips its contents so text cannot escape", cell.clip_contents)
	check_eq("cell is square at the configured size",
		cell.custom_minimum_size,
		Vector2(GameConstants.HOTBAR_CELL_SIZE, GameConstants.HOTBAR_CELL_SIZE))
	check("cell has a Count label", cell.get_node_or_null("Count") != null)
	check("cell has a Key label", cell.get_node_or_null("Key") != null)
	# The Thai-truncation bug: no cell may render a clipped item name.
	var key := cell.get_node("Key") as Label
	check_eq("Key shows the hotkey digit, not an item name", key.text, "1")


## The guards in SceneLoader were split out of change_scene in W8. A refused
## change must leave no lock behind, or every later transition is silently
## dropped with only a warning.
func _test_scene_change_guards() -> void:
	print("\n--- scene change guards ---")
	check("not changing at rest", not SceneLoader.is_changing())
	SceneLoader.change_scene("res://this/does/not/exist.tscn")
	check("a missing scene is refused", not SceneLoader.is_changing())
	check("the current scene is untouched", get_tree().current_scene == self)


func _find_hotbar() -> HBoxContainer:
	for node in _all_nodes(get_tree().root):
		if node is HBoxContainer and node.name == "Hotbar":
			return node
	return null


func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		out.append_array(_all_nodes(child))
	return out
