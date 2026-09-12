extends Node
## Economy tests. Money is the thing players forgive least, so every path that
## can create or destroy it is checked, including the ones that should not.

var pass_count := 0
var fail_count := 0

var _bin: ShippingBin


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

	_test_deposit_moves_goods()
	_test_refusals()
	_test_overnight_payout()
	_test_value_is_conserved()
	_test_no_double_payout()
	await _test_contents_survive_save()

	print("\n==================================================")
	print("  economy_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _setup() -> void:
	var scene: PackedScene = load("res://src/systems/economy/shipping_bin.tscn")
	_bin = scene.instantiate()
	add_child(_bin)
	await get_tree().process_frame
	_reset()


func _reset() -> void:
	GameClock.reset()
	GameState.reset()
	Inventory.reset()
	_bin.load_state({})


## Selects a slot holding [param amount] of [param item_id] and returns it.
func _hold(item_id: StringName, amount: int) -> void:
	Inventory.reset()
	Inventory.add_item(item_id, amount)
	Inventory.select(0)


func _test_deposit_moves_goods() -> void:
	print("\n--- depositing ---")
	_reset()
	_hold(&"turnip", 4)
	check_eq("deposit reports what it took", _bin.deposit_held_stack(), 4)
	check_eq("goods left the bag", Inventory.count_of(&"turnip"), 0)
	check_eq("goods are in the bin", _bin.count_of(&"turnip"), 4)
	check_eq("money is untouched until morning", GameState.money,
		GameConstants.STARTING_MONEY)

	_hold(&"turnip", 3)
	check_eq("a second deposit stacks", _bin.deposit_held_stack(), 3)
	check_eq("bin now holds both", _bin.count_of(&"turnip"), 7)


## Every refusal must leave the world exactly as it found it.
func _test_refusals() -> void:
	print("\n--- refusals ---")
	_reset()

	Inventory.reset()
	Inventory.select(0)
	check_eq("empty hand deposits nothing", _bin.deposit_held_stack(), 0)
	check("the bin stays empty", _bin.is_empty())

	# A hoe sells for 0: depositing it would destroy a tool for no money.
	_hold(&"hoe", 1)
	check_eq("a worthless item is refused", _bin.deposit_held_stack(), 0)
	check_eq("the tool is still in the bag", Inventory.count_of(&"hoe"), 1)
	check("the bin is still empty", _bin.is_empty())
	check_eq("nothing was paid", GameState.money, GameConstants.STARTING_MONEY)


func _test_overnight_payout() -> void:
	print("\n--- overnight payout ---")
	_reset()
	var turnip := Database.get_item(&"turnip")
	_hold(&"turnip", 5)
	_bin.deposit_held_stack()

	var expected := turnip.sell_price * 5
	check_eq("bin values the load correctly", _bin.pending_value(), expected)

	GameClock.sleep_until_morning()
	check_eq("money went up by the sale", GameState.money,
		GameConstants.STARTING_MONEY + expected)
	check("the bin is empty afterwards", _bin.is_empty())
	check_eq("nothing is left to pay", _bin.pending_value(), 0)


## The invariant: shipping moves value, it does not create or destroy it.
func _test_value_is_conserved() -> void:
	print("\n--- value is conserved ---")
	_reset()
	var turnip := Database.get_item(&"turnip")
	var chili := Database.get_item(&"chili")
	_hold(&"turnip", 3)
	_bin.deposit_held_stack()
	_hold(&"chili", 2)
	_bin.deposit_held_stack()

	var before := GameState.money + _bin.pending_value()
	var expected_sale := turnip.sell_price * 3 + chili.sell_price * 2
	check_eq("mixed load is valued correctly", _bin.pending_value(), expected_sale)

	GameClock.sleep_until_morning()
	var after := GameState.money + _bin.pending_value()
	check_eq("money plus bin value is unchanged by the sale", after, before)


## day_started can fire more than once across a save load or a festival skip.
## Paying and clearing happen together precisely so it cannot pay twice.
func _test_no_double_payout() -> void:
	print("\n--- two nights in a row ---")
	_reset()
	_hold(&"turnip", 2)
	_bin.deposit_held_stack()
	var paid_for := _bin.pending_value()

	GameClock.sleep_until_morning()
	var after_first := GameState.money
	check_eq("first night pays", after_first,
		GameConstants.STARTING_MONEY + paid_for)

	GameClock.sleep_until_morning()
	check_eq("second night pays nothing more", GameState.money, after_first)

	# And an extra day_started with an empty bin must be silent too.
	EventBus.day_started.emit(GameClock.day, GameClock.season, GameClock.year)
	check_eq("a repeated day_started pays nothing", GameState.money, after_first)


## A player who ships a day's harvest and saves before sleeping must not lose
## it. This is the reason the bin was saveable from its first commit.
func _test_contents_survive_save() -> void:
	print("\n--- contents survive a save ---")
	_reset()
	_hold(&"turnip", 6)
	_bin.deposit_held_stack()
	var value := _bin.pending_value()

	# Through real JSON, exactly as SaveManager writes it.
	var restored: Dictionary = JSON.parse_string(JSON.stringify(_bin.save_state()))
	check("bin state survives JSON", restored != null)

	_bin.load_state({})
	check("bin was really cleared before restoring", _bin.is_empty())

	_bin.load_state(restored)
	check_eq("the load came back", _bin.count_of(&"turnip"), 6)
	check_eq("and is still worth the same", _bin.pending_value(), value)

	GameClock.sleep_until_morning()
	check_eq("restored goods still pay out", GameState.money,
		GameConstants.STARTING_MONEY + value)
	await get_tree().process_frame
