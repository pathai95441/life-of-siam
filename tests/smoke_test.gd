## Headless smoke test for the core loop. Run with:
##     godot --headless --path . tests/smoke_test.tscn
## Exits non-zero on any failure, so it works as a CI gate. This is a plain
## scene-based harness, not a framework; swap in GdUnit4 when the suite grows.
extends Node

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

# Shared across sections on purpose: this is one run through the core loop, not
# a set of independent cases. The crop planted in _test_farming is the one
# _test_growth matures and _test_harvest picks, so order is load-bearing and
# the sections read top to bottom as a single playthrough.
const CELL := Vector2i(0, 0)
const DRY_CELL := Vector2i(2, 2)

var _grid: FarmGrid
var _turnip: CropData


func _ready() -> void:
	await _setup()

	_test_clock()
	_test_inventory()
	_test_farming()
	_test_growth()
	_test_drought()
	_test_harvest()
	_test_save_round_trip()
	_test_season_gating()
	_test_dialogue()
	_test_economy()

	_report()


func _setup() -> void:
	_grid = FarmGrid.new()
	add_child(_grid)
	await get_tree().process_frame

	GameClock.reset()
	GameState.reset()
	Inventory.reset()
	_turnip = Database.get_crop(&"turnip")


func _report() -> void:
	print("\n==================================================")
	print("  %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _test_clock() -> void:
	print("\n--- clock ---")
	check_eq("starts day 1", GameClock.day, 1)
	check_eq("starts spring", GameClock.season, GameConstants.Season.SPRING)
	check_eq("wakes at 06:00", GameClock.hour(), 6)
	check_eq("absolute_day", GameClock.absolute_day(), 1)


func _test_inventory() -> void:
	print("\n--- inventory ---")
	check_eq("hoe added", Inventory.add_item(&"hoe", 1), 0)
	check_eq("has hoe", Inventory.has_item(&"hoe"), true)
	check_eq("unknown id rejected", Inventory.add_item(&"nonexistent", 5), 5)
	var overflow := Inventory.add_item(&"turnip", 99 * 40)
	check("bag overflow returns remainder", overflow > 0)
	Inventory.reset()
	check_eq("reset empties bag", Inventory.count_of(&"turnip"), 0)
	Inventory.add_item(&"turnip_seed", 5)
	check_eq("remove more than held fails", Inventory.remove_item(&"turnip_seed", 99), false)
	check_eq("still 5 seeds", Inventory.count_of(&"turnip_seed"), 5)


func _test_farming() -> void:
	print("\n--- farming ---")
	check_eq("till fresh soil", _grid.till(CELL), true)
	check_eq("till twice fails", _grid.till(CELL), false)
	check_eq("till outside field fails", _grid.till(Vector2i(999, 999)), false)
	check("turnip crop loaded", _turnip != null)
	check_eq("plant on tilled soil", _grid.plant(CELL, _turnip), true)
	check_eq("plant twice fails", _grid.plant(CELL, _turnip), false)
	check_eq("water tilled soil", _grid.water(CELL), true)
	check_eq("water twice fails", _grid.water(CELL), false)

	var soil := _grid.get_cell(CELL)
	check_eq("growth starts at 0", soil.growth_days, 0)
	check_eq("not harvestable yet", soil.is_harvestable(), false)


func _test_growth() -> void:
	print("\n--- growth over days (watered) ---")
	var total := _turnip.total_growth_days()
	for _i in total:
		GameClock.sleep_until_morning()
		_grid.water(CELL)
	var soil := _grid.get_cell(CELL)
	check_eq("grew to maturity in %d days" % total, soil.growth_days, total)
	check_eq("is harvestable", soil.is_harvestable(), true)
	check_eq("day advanced", GameClock.day, 1 + total)


func _test_drought() -> void:
	print("\n--- drought ---")
	_grid.till(DRY_CELL)
	_grid.plant(DRY_CELL, _turnip)
	for _i in _turnip.drought_tolerance + 1:
		GameClock.sleep_until_morning()
	check_eq("unwatered crop withers", _grid.get_cell(DRY_CELL).withered, true)


func _test_harvest() -> void:
	print("\n--- harvest ---")
	var before := Inventory.count_of(&"turnip")
	check_eq("harvest succeeds", _grid.harvest(CELL), true)
	check("produce entered bag", Inventory.count_of(&"turnip") > before)
	check_eq("harvest twice fails", _grid.harvest(CELL), false)


## Serialises through JSON exactly as SaveManager does, to prove the payload
## survives a real file round trip and not just an in-memory copy.
func _test_save_round_trip() -> void:
	print("\n--- save round trip ---")
	var snapshot := {
		"farm": _grid.save_state(),
		"inv": Inventory.save_state(),
		"clock": GameClock.save_state(),
	}
	var turnips := Inventory.count_of(&"turnip")
	var saved_day := GameClock.day

	var restored: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	check("payload survives JSON", restored != null)

	_corrupt_live_state()
	_restore(restored)

	check_eq("inventory restored", Inventory.count_of(&"turnip"), turnips)
	check_eq("clock restored", GameClock.day, saved_day)
	check_eq("tilled cell restored",
		_grid.get_cell(CELL) != null and _grid.get_cell(CELL).tilled, true)
	check_eq("withered cell restored", _grid.get_cell(DRY_CELL).withered, true)


## Wipes everything the save is meant to bring back, so a passing restore
## cannot be the original state surviving by accident.
func _corrupt_live_state() -> void:
	Inventory.reset()
	GameClock.reset()
	_grid.load_state({})
	check_eq("state cleared", Inventory.count_of(&"turnip"), 0)


func _restore(payload: Dictionary) -> void:
	_grid.load_state(payload["farm"])
	Inventory.load_state(payload["inv"])
	GameClock.load_state(payload["clock"])


func _test_season_gating() -> void:
	print("\n--- season gating ---")
	var chili := Database.get_crop(&"chili")
	check_eq("chili not in spring", chili.grows_in_season(GameConstants.Season.SPRING), false)
	check_eq("chili in summer", chili.grows_in_season(GameConstants.Season.SUMMER), true)
	check_eq("turnip in spring", _turnip.grows_in_season(GameConstants.Season.SPRING), true)


func _test_dialogue() -> void:
	print("\n--- dialogue ---")
	var dlg := Database.get_dialogue(&"somchai_default")
	check("dialogue loaded", dlg != null)
	check_eq("dialogue has 2 lines", dlg.lines.size(), 2)
	check("first line has text", not dlg.lines[0].text.is_empty())
	check_eq("start dialogue", DialogueSystem.start(dlg, &"somchai"), true)
	check_eq("is active", DialogueSystem.is_active(), true)
	check_eq("double start refused", DialogueSystem.start(dlg, &"somchai"), false)
	DialogueSystem.advance()
	DialogueSystem.advance()
	check_eq("finishes after last line", DialogueSystem.is_active(), false)
	check_eq("sets_flag applied", GameState.has_flag(&"met_somchai"), true)


func _test_economy() -> void:
	print("\n--- economy ---")
	GameState.reset()
	check_eq("starting money", GameState.money, GameConstants.STARTING_MONEY)
	check_eq("cannot overspend", GameState.try_spend(999999), false)
	check_eq("money untouched", GameState.money, GameConstants.STARTING_MONEY)
	check_eq("can spend 100", GameState.try_spend(100), true)
	check_eq("money after spend", GameState.money, GameConstants.STARTING_MONEY - 100)
