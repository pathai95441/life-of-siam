extends Node
## The shop panel is a view, so what is worth testing is that it shows what the
## shop says and does what the shop allows -- never that it decided anything.
##
## Runs headless: node structure, signal wiring and button state need no
## rendering. Only how it looks does, and that is a manual check.

var pass_count := 0
var fail_count := 0

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

	_test_opens_with_the_shops_stock()
	_test_prices_shown_match_the_shop()
	_test_pressing_buy_buys()
	_test_unaffordable_rows_are_disabled()
	_test_full_bag_disables_rows()
	_test_closing()

	print("\n==================================================")
	print("  shop_ui_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _setup() -> void:
	_shop = (load("res://src/systems/economy/shop.tscn") as PackedScene).instantiate()
	add_child(_shop)
	_panel = (load("res://src/ui/shop/shop_panel.tscn") as PackedScene).instantiate()
	add_child(_panel)
	await get_tree().process_frame
	_reset()


func _reset() -> void:
	GameState.reset()
	Inventory.reset()


func _open() -> void:
	EventBus.shop_opened.emit(_shop)


func _test_opens_with_the_shops_stock() -> void:
	print("\n--- opening ---")
	_reset()
	check("closed to begin with", not _panel.is_open())
	_open()
	check("open after the shop asks", _panel.is_open())
	check_eq("one row per stocked item", _panel.row_count(), _shop.stock().size())
	for item_id in _shop.stock():
		check("'%s' has a buy button" % item_id, _panel.buy_button_for(item_id) != null)
	check("an unstocked item has no row", _panel.buy_button_for(&"turnip") == null)


func _test_prices_shown_match_the_shop() -> void:
	print("\n--- prices come from the shop ---")
	_reset()
	_open()
	for item_id in _shop.stock():
		var row := _panel.get_node("%%Rows/Row_%s" % item_id) as HBoxContainer
		var price_label := row.get_child(1) as Label
		check_eq("'%s' row shows the shop's price" % item_id,
			price_label.text, "%d ฿" % _shop.price_of(item_id))


func _test_pressing_buy_buys() -> void:
	print("\n--- pressing buy ---")
	_reset()
	_open()
	var price := _shop.price_of(&"turnip_seed")
	var before := GameState.money

	_panel.buy_button_for(&"turnip_seed").pressed.emit()

	check_eq("money fell by the price", GameState.money, before - price)
	check_eq("one seed arrived", Inventory.count_of(&"turnip_seed"), 1)


## The panel must not decide affordability itself; it asks the shop. Draining
## the player's money has to be enough to grey the row out.
func _test_unaffordable_rows_are_disabled() -> void:
	print("\n--- cannot afford ---")
	_reset()
	_open()
	check("buying is enabled while the player has money",
		not _panel.buy_button_for(&"turnip_seed").disabled)

	GameState.try_spend(GameState.money)
	check_eq("player is broke", GameState.money, 0)
	check("the row disabled itself when the money went",
		_panel.buy_button_for(&"turnip_seed").disabled)
	check("the shop agrees", not _shop.can_buy(&"turnip_seed", 1))


## Being unable to carry it is a different refusal with the same result on
## screen, which is exactly why the panel asks rather than checks the balance.
func _test_full_bag_disables_rows() -> void:
	print("\n--- cannot carry ---")
	_reset()
	_open()
	Inventory.add_item(&"turnip", 99 * GameConstants.INVENTORY_SLOTS)
	check("player still has money", GameState.money > 0)
	check("but the row is disabled anyway",
		_panel.buy_button_for(&"turnip_seed").disabled)


func _test_closing() -> void:
	print("\n--- closing ---")
	_reset()
	_open()
	var closed_fired := [false]
	var handler := func() -> void: closed_fired[0] = true
	EventBus.shop_closed.connect(handler)

	_panel.close()
	check("panel is closed", not _panel.is_open())
	check("shop_closed was emitted so the player can move again", closed_fired[0])

	_panel.close()
	check("closing twice does not fire again", closed_fired[0])
	EventBus.shop_closed.disconnect(handler)
