extends Node
## Buying. Every refusal path is checked for leaving the world untouched,
## because the failure that matters is not "the purchase did not happen" but
## "the purchase did not happen and the money is gone anyway".

var pass_count := 0
var fail_count := 0

var _shop: Shop


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

	_test_stock_and_prices()
	_test_successful_purchase()
	_test_insufficient_money()
	_test_full_bag()
	_test_unstocked_item()
	_test_bad_amounts()
	_test_shop_data_validation()

	print("\n==================================================")
	print("  shop_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _setup() -> void:
	var scene: PackedScene = load("res://src/systems/economy/shop.tscn")
	_shop = scene.instantiate()
	add_child(_shop)
	await get_tree().process_frame
	_reset()


func _reset() -> void:
	GameState.reset()
	Inventory.reset()


## Snapshot of everything a purchase could change.
func _snapshot() -> Array:
	return [GameState.money, Inventory.count_of(&"turnip_seed"),
		Inventory.count_of(&"chili_seed"), Inventory.count_of(&"turnip")]


func _test_stock_and_prices() -> void:
	print("\n--- stock and prices ---")
	check("shop has data", _shop.shop_data != null)
	check_eq("stocks two items", _shop.stock().size(), 2)
	check("sells turnip seeds", _shop.sells(&"turnip_seed"))
	check("does not sell turnips", not _shop.sells(&"turnip"))

	var seed := Database.get_item(&"turnip_seed")
	check_eq("price comes from the item, not the shop",
		_shop.price_of(&"turnip_seed"), seed.buy_price)
	check_eq("price of an unstocked item is zero", _shop.price_of(&"turnip"), 0)
	check_eq("buying five costs five times one",
		_shop.total_price(&"turnip_seed", 5), seed.buy_price * 5)


func _test_successful_purchase() -> void:
	print("\n--- a purchase that works ---")
	_reset()
	var price := _shop.price_of(&"turnip_seed")
	check("the shop says it is allowed", _shop.can_buy(&"turnip_seed", 3))
	check("buy succeeds", _shop.buy(&"turnip_seed", 3))
	check_eq("money fell by exactly the cost", GameState.money,
		GameConstants.STARTING_MONEY - price * 3)
	check_eq("seeds arrived", Inventory.count_of(&"turnip_seed"), 3)


func _test_insufficient_money() -> void:
	print("\n--- not enough money ---")
	_reset()
	GameState.try_spend(GameState.money)
	check_eq("player is broke", GameState.money, 0)

	var before := _snapshot()
	check("can_buy says no", not _shop.can_buy(&"turnip_seed", 1))
	check("buy refuses", not _shop.buy(&"turnip_seed", 1))
	check_eq("nothing changed at all", _snapshot(), before)


## The one that matters: if the bag cannot hold the goods, the money must not
## move. Taking payment and then failing to deliver is how savings disappear.
func _test_full_bag() -> void:
	print("\n--- bag is full ---")
	_reset()
	Inventory.add_item(&"turnip", 99 * GameConstants.INVENTORY_SLOTS)
	check("every slot is occupied", not Inventory.can_accept(&"turnip_seed", 1))

	var before := _snapshot()
	check("can_buy says no", not _shop.can_buy(&"turnip_seed", 1))
	check("buy refuses", not _shop.buy(&"turnip_seed", 1))
	check_eq("money was not taken", GameState.money, before[0])
	check_eq("nothing changed at all", _snapshot(), before)


func _test_unstocked_item() -> void:
	print("\n--- item this shop does not sell ---")
	_reset()
	var before := _snapshot()
	check("buying a turnip is refused", not _shop.buy(&"turnip", 1))
	check("buying an unknown id is refused", not _shop.buy(&"nonexistent", 1))
	check_eq("nothing changed at all", _snapshot(), before)


func _test_bad_amounts() -> void:
	print("\n--- nonsense amounts ---")
	_reset()
	var before := _snapshot()
	check("zero is refused", not _shop.buy(&"turnip_seed", 0))
	check("negative is refused", not _shop.buy(&"turnip_seed", -5))
	check_eq("nothing changed at all", _snapshot(), before)
	check_eq("a negative total never goes below zero",
		_shop.total_price(&"turnip_seed", -5), 0)


func _test_shop_data_validation() -> void:
	print("\n--- shop data validation ---")
	check("the authored shop is valid", _shop.shop_data.is_valid())

	var empty := ShopData.new()
	check("an empty shop is rejected", not empty.is_valid())

	var bad := ShopData.new()
	bad.id = &"bad"
	bad.stock = [&"nonexistent"] as Array[StringName]
	check("stocking an unknown item is rejected", not bad.is_valid())
	check("the error names the item", bad.validation_errors()[0].contains("nonexistent"))

	var free_item := ShopData.new()
	free_item.id = &"free"
	# Turnips have a sell price but no buy price: nobody can purchase one.
	free_item.stock = [&"turnip"] as Array[StringName]
	check("stocking something with no buy price is rejected", not free_item.is_valid())
