extends Node
## The file SaveManager actually writes.
##
## Everything else round-trips state in memory. Nothing until now had opened
## the JSON on disk and looked at its shape, which is a strange gap for the one
## artefact a player cannot afford to have wrong -- and a worse one in the task
## that changes the format.
##
## Loading is exercised only as far as reading the file back: a real
## load_from_slot changes scene and would take this test scene with it.

const TEST_SLOT := 9

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
	var world: World = (load(GameConstants.SCENE_WORLD) as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	GameClock.reset()
	GameState.reset()
	Inventory.reset()
	SaveManager.delete_slot(TEST_SLOT)

	_test_a_written_save_has_the_new_shape()
	_test_header_is_readable_without_loading()
	_test_deleting_a_slot()

	SaveManager.delete_slot(TEST_SLOT)
	print("\n==================================================")
	print("  save_disk_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _written_payload() -> Dictionary:
	var text := FileAccess.get_file_as_string(SaveManager.slot_path(TEST_SLOT))
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _test_a_written_save_has_the_new_shape() -> void:
	print("\n--- what lands on disk ---")
	var grid: FarmGrid = get_tree().get_first_node_in_group(&"farm_grid")
	grid.till(Vector2i(3, 3))
	Inventory.add_item(&"turnip", 2)

	check("save reported success", SaveManager.save_to_slot(TEST_SLOT))
	check("a file exists", SaveManager.slot_exists(TEST_SLOT))

	var payload := _written_payload()
	check("it parses as JSON", not payload.is_empty())
	check_eq("stamped with the current version",
		SaveMigration.version_of(payload), GameConstants.SAVE_VERSION)

	var scene: Dictionary = payload.get("scene", {})
	check("scene state is filed under a map", scene.has("farm"))
	check("and not loose at the top", not scene.has("farm_grid"))
	check("the map block holds the farm grid", scene["farm"].has("farm_grid"))
	check("the tilled cell is really in the file",
		scene["farm"]["farm_grid"]["cells"].has("3,3"))
	check("providers are separate from scene state",
		payload.has("providers") and payload["providers"].has("inventory"))


## The slot list reads headers without loading a whole save, so a corrupt or
## absent slot must not be able to take the menu down with it.
func _test_header_is_readable_without_loading() -> void:
	print("\n--- reading a header ---")
	var header := SaveManager.read_slot_header(TEST_SLOT)
	check("the header comes back", not header.is_empty())
	check_eq("it carries the money", int(header.get("money", -1)), GameState.money)
	check_eq("and the map", String(header.get("map", "")), GameState.current_map)

	var missing := SaveManager.read_slot_header(TEST_SLOT + 1)
	check("an empty slot reads as empty, not as an error", missing.is_empty())


func _test_deleting_a_slot() -> void:
	print("\n--- deleting ---")
	SaveManager.delete_slot(TEST_SLOT)
	check("the file is gone", not SaveManager.slot_exists(TEST_SLOT))
	check("its header reads empty afterwards",
		SaveManager.read_slot_header(TEST_SLOT).is_empty())
	SaveManager.delete_slot(TEST_SLOT)
	check("deleting a slot that is already gone is harmless",
		not SaveManager.slot_exists(TEST_SLOT))
