extends Node
## Temporary visual-capture harness: builds a representative game state,
## renders it, and writes PNGs so the visual direction can be judged from the
## real engine output instead of a description. Not part of the test suite.

const SHOTS := "user://shots"

var _world: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	_seed_state()
	_world = load("res://src/world/world.tscn").instantiate()
	add_child(_world)
	await _settle(20)

	_seed_farm()
	await _settle(10)
	await _shot("01_world")

	Inventory.select(0)
	await _settle(4)
	await _shot("02_hotbar")

	DialogueSystem.start(Database.get_dialogue(&"somchai_default"), &"somchai")
	await _settle(6)
	await _shot("03_dialogue")

	DialogueSystem.cancel()
	await _settle(4)
	await _shot_shop()

	get_tree().call_group(&"player", "queue_free")
	await _settle(4)

	print("[capture] wrote to ", ProjectSettings.globalize_path(SHOTS))
	get_tree().quit()


func _seed_state() -> void:
	GameClock.reset()
	GameState.reset()
	Inventory.reset()
	for id in [&"hoe", &"watering_can", &"scythe"]:
		Inventory.add_item(id, 1)
	Inventory.add_item(&"turnip_seed", 15)
	Inventory.add_item(&"turnip", 7)


## Tilled soil with crops at several growth stages, so one frame shows the
## whole farming system rather than bare ground.
func _seed_farm() -> void:
	var grid: FarmGrid = get_tree().get_first_node_in_group(&"farm_grid")
	if grid == null:
		push_error("[capture] no farm_grid in world")
		return
	var turnip := Database.get_crop(&"turnip")
	for x in range(-5, 4):
		for y in range(-2, 4):
			var cell := Vector2i(x, y)
			grid.till(cell)
			if (x + y) % 3 != 0:
				grid.plant(cell, turnip)
				grid.water(cell)
				var soil := grid.get_cell(cell)
				soil.growth_days = absi(x + y * 2) % (turnip.total_growth_days() + 1)
	grid.queue_redraw()


## The shop UI has never been looked at; open it so it can be.
func _shot_shop() -> void:
	for node in get_tree().get_nodes_in_group(&"interactable"):
		if node is Shop:
			(node as Shop).interact(get_tree().get_first_node_in_group(&"player"))
			await _settle(6)
			await _shot("04_shop")
			return
	push_warning("[capture] no Shop in the world to photograph")


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOTS, name]
	var err := image.save_png(path)
	print("[capture] %s -> %s (%dx%d)" % [
		"ok" if err == OK else "FAILED", path, image.get_width(), image.get_height()])
