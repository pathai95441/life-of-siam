extends Node
## The whole economy loop through the real world scene and the real nodes.
##
## Every piece below has unit tests already. What this checks is that they are
## actually wired to each other in world.tscn -- the failure mode where every
## test passes and the game still does nothing, because something was built but
## never placed.
##
## It goes through interact() rather than calling deposit or buy directly, so
## the interactable, the probe's target and the player's lock are all exercised.

var pass_count := 0
var fail_count := 0

var _player: Player
var _grid: FarmGrid
var _bin: ShippingBin
var _shop: Shop
var _panel: CanvasLayer


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
	await _setup()

	_test_everything_is_in_the_world()
	_test_grow_ship_and_get_paid()
	_test_spend_it_at_the_shop()
	_test_a_full_day_conserves_value()

	print("\n==================================================")
	print("  economy_loop_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _setup() -> void:
	var world: World = (load("res://src/world/world.tscn") as PackedScene).instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	_player = get_tree().get_first_node_in_group(&"player")
	_grid = get_tree().get_first_node_in_group(&"farm_grid")
	for node in get_tree().get_nodes_in_group(&"interactable"):
		if node is ShippingBin:
			_bin = node
		elif node is Shop:
			_shop = node
	_panel = world.get_node_or_null("Ui/ShopPanel")

	GameClock.reset()
	GameState.reset()
	Inventory.reset()
	_bin.load_state({})


## The wiring check. Building a shop nobody placed is the quiet failure this
## whole file exists to catch.
func _test_everything_is_in_the_world() -> void:
	print("\n--- everything is actually placed ---")
	check("a shipping bin is in the world", _bin != null)
	check("a shop is in the world", _shop != null)
	check("the shop panel is in the UI layer", _panel != null)
	check("the shop has stock", _shop != null and not _shop.stock().is_empty())


## DoD 1: plant, grow, harvest, ship, sleep, get paid.
func _test_grow_ship_and_get_paid() -> void:
	print("\n--- grow it, ship it, get paid ---")
	var turnip_crop := Database.get_crop(&"turnip")
	var cell := Vector2i(0, 0)
	_grid.till(cell)
	check("planted", _grid.plant(cell, turnip_crop))

	for _i in turnip_crop.total_growth_days():
		_grid.water(cell)
		GameClock.sleep_until_morning()
	check("harvested into the bag", _grid.harvest(cell))

	var carried := Inventory.count_of(&"turnip")
	check("the bag actually has produce", carried > 0)
	var expected := Database.get_item(&"turnip").sell_price * carried

	Inventory.select(_slot_holding(&"turnip"))
	_bin.interact(_player)
	check_eq("produce left the bag", Inventory.count_of(&"turnip"), 0)
	check_eq("and is waiting in the bin", _bin.pending_value(), expected)

	var before := GameState.money
	GameClock.sleep_until_morning()
	check_eq("morning pays for it", GameState.money, before + expected)


## DoD 2: open the shop and buy something, through the real panel.
func _test_spend_it_at_the_shop() -> void:
	print("\n--- spend it at the shop ---")
	var before := GameState.money
	check("the player has money to spend", before > 0)

	_shop.interact(_player)
	check("the panel opened", _panel.is_open())
	check("the player is locked while shopping",
		_player.state_machine.is_in(&"locked"))

	var price := _shop.price_of(&"turnip_seed")
	_panel.buy_button_for(&"turnip_seed").pressed.emit()
	check_eq("money fell by the price", GameState.money, before - price)
	check_eq("the seed is in the bag", Inventory.count_of(&"turnip_seed"), 1)

	_panel.close()
	check("the panel closed", not _panel.is_open())
	check("the player can move again", not _player.state_machine.is_in(&"locked"))


## Across a whole day of trading, money only moves for reasons we asked for.
func _test_a_full_day_conserves_value() -> void:
	print("\n--- a day of trading adds up ---")
	var start_money := GameState.money
	var seed_price := _shop.price_of(&"chili_seed")

	_shop.interact(_player)
	_panel.buy_button_for(&"chili_seed").pressed.emit()
	_panel.close()

	Inventory.add_item(&"turnip", 2)
	Inventory.select(_slot_holding(&"turnip"))
	_bin.interact(_player)
	var shipped := _bin.pending_value()
	GameClock.sleep_until_morning()

	check_eq("money moved by exactly what was bought and sold",
		GameState.money, start_money - seed_price + shipped)


func _slot_holding(item_id: StringName) -> int:
	for i in Inventory.slots.size():
		if Inventory.slots[i].item_id == item_id:
			return i
	return 0
