extends Node
## Map identity and the rule that decides what gets remembered as the player's
## location. Pure checks: performing a real scene change would replace this
## test scene out from under itself.

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
	_test_registry()
	_test_validation()
	_test_map_lookup()
	_test_what_counts_as_a_map()
	_test_scene_declares_its_id()

	print("\n==================================================")
	print("  map_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _test_registry() -> void:
	print("\n--- registry ---")
	check("the farm is registered", Database.get_map(&"farm") != null)
	check("an unknown map is null", Database.get_map(&"nowhere") == null)
	check_eq("the farm points at the world scene",
		Database.get_map(&"farm").scene_path, GameConstants.SCENE_WORLD)


func _test_validation() -> void:
	print("\n--- validation ---")
	for id in Database.maps:
		check("authored map '%s' is valid" % id, (Database.maps[id] as MapData).is_valid())

	var blank := MapData.new()
	check("an empty map is rejected", not blank.is_valid())

	var missing := MapData.new()
	missing.id = &"ghost"
	missing.scene_path = "res://does/not/exist.tscn"
	check("a map pointing at nothing is rejected", not missing.is_valid())
	check("the error names the path",
		missing.validation_errors()[0].contains("does/not/exist"))


func _test_map_lookup() -> void:
	print("\n--- lookup by id ---")
	check_eq("known id resolves to its path",
		SceneLoader.map_path(&"farm"), GameConstants.SCENE_WORLD)
	check_eq("unknown id resolves to nothing", SceneLoader.map_path(&"nowhere"), "")


## P1: current_map used to be assigned only when the target was one hardcoded
## path, so a save made anywhere else reloaded into the farm. The rule is now
## the scene's root type, which covers maps that do not exist yet.
func _test_what_counts_as_a_map() -> void:
	print("\n--- what counts as a map ---")
	var world: Node = (load(GameConstants.SCENE_WORLD) as PackedScene).instantiate()
	check("the farm scene is a map", SceneLoader.is_map_scene(world))
	world.free()

	var menu: Node = (load(GameConstants.SCENE_MAIN_MENU) as PackedScene).instantiate()
	check("the main menu is not a map", not SceneLoader.is_map_scene(menu))
	menu.free()

	check("nothing is not a map", not SceneLoader.is_map_scene(null))


## Save data for a scene's contents is filed under its map_id, so a map without
## one cannot be saved. The farm has to declare it in the scene, not at runtime.
func _test_scene_declares_its_id() -> void:
	print("\n--- the scene declares its id ---")
	var world: World = (load(GameConstants.SCENE_WORLD) as PackedScene).instantiate()
	check_eq("the farm scene knows it is the farm", world.map_id, &"farm")
	check("its id is one the registry knows",
		Database.get_map(world.map_id) != null)
	world.free()
