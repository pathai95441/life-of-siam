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

func _ready() -> void:
	var grid: FarmGrid = FarmGrid.new()
	add_child(grid)
	await get_tree().process_frame

	GameClock.reset()
	GameState.reset()
	Inventory.reset()

	print("\n--- clock ---")
	check_eq("starts day 1", GameClock.day, 1)
	check_eq("starts spring", GameClock.season, GameConstants.Season.SPRING)
	check_eq("wakes at 06:00", GameClock.hour(), 6)
	check_eq("absolute_day", GameClock.absolute_day(), 1)

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

	print("\n--- farming ---")
	var cell := Vector2i(0, 0)
	check_eq("till fresh soil", grid.till(cell), true)
	check_eq("till twice fails", grid.till(cell), false)
	check_eq("till outside field fails", grid.till(Vector2i(999, 999)), false)
	var turnip := Database.get_crop(&"turnip")
	check("turnip crop loaded", turnip != null)
	check_eq("plant on tilled soil", grid.plant(cell, turnip), true)
	check_eq("plant twice fails", grid.plant(cell, turnip), false)
	check_eq("water tilled soil", grid.water(cell), true)
	check_eq("water twice fails", grid.water(cell), false)

	var soil := grid.get_cell(cell)
	check_eq("growth starts at 0", soil.growth_days, 0)
	check_eq("not harvestable yet", soil.is_harvestable(), false)

	print("\n--- growth over days (watered) ---")
	var total := turnip.total_growth_days()
	for i in total:
		GameClock.sleep_until_morning()
		grid.water(cell)
	check_eq("grew to maturity in %d days" % total, soil.growth_days, total)
	check_eq("is harvestable", soil.is_harvestable(), true)
	check_eq("day advanced", GameClock.day, 1 + total)

	print("\n--- drought ---")
	var dry_cell := Vector2i(2, 2)
	grid.till(dry_cell)
	grid.plant(dry_cell, turnip)
	for i in turnip.drought_tolerance + 1:
		GameClock.sleep_until_morning()
	check_eq("unwatered crop withers", grid.get_cell(dry_cell).withered, true)

	print("\n--- harvest ---")
	var before := Inventory.count_of(&"turnip")
	check_eq("harvest succeeds", grid.harvest(cell), true)
	check("produce entered bag", Inventory.count_of(&"turnip") > before)
	check_eq("harvest twice fails", grid.harvest(cell), false)

	print("\n--- save round trip ---")
	var farm_snapshot := grid.save_state()
	var inv_snapshot := Inventory.save_state()
	var clock_snapshot := GameClock.save_state()
	var turnips := Inventory.count_of(&"turnip")
	var saved_day := GameClock.day

	# Serialize through JSON exactly as SaveManager does, to prove the payload
	# survives a real file round trip and not just an in-memory copy.
	var json := JSON.stringify({"farm": farm_snapshot, "inv": inv_snapshot, "clock": clock_snapshot})
	var restored: Dictionary = JSON.parse_string(json)
	check("payload survives JSON", restored != null)

	# Corrupt live state, then restore.
	Inventory.reset()
	GameClock.reset()
	grid.load_state({})
	check_eq("state cleared", Inventory.count_of(&"turnip"), 0)

	grid.load_state(restored["farm"])
	Inventory.load_state(restored["inv"])
	GameClock.load_state(restored["clock"])
	check_eq("inventory restored", Inventory.count_of(&"turnip"), turnips)
	check_eq("clock restored", GameClock.day, saved_day)
	check_eq("tilled cell restored", grid.get_cell(cell) != null and grid.get_cell(cell).tilled, true)
	check_eq("withered cell restored", grid.get_cell(dry_cell).withered, true)

	print("\n--- season gating ---")
	var chili := Database.get_crop(&"chili")
	check_eq("chili not in spring", chili.grows_in_season(GameConstants.Season.SPRING), false)
	check_eq("chili in summer", chili.grows_in_season(GameConstants.Season.SUMMER), true)
	check_eq("turnip in spring", turnip.grows_in_season(GameConstants.Season.SPRING), true)

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

	print("\n--- economy ---")
	GameState.reset()
	check_eq("starting money", GameState.money, GameConstants.STARTING_MONEY)
	check_eq("cannot overspend", GameState.try_spend(999999), false)
	check_eq("money untouched", GameState.money, GameConstants.STARTING_MONEY)
	check_eq("can spend 100", GameState.try_spend(100), true)
	check_eq("money after spend", GameState.money, GameConstants.STARTING_MONEY - 100)

	print("\n==================================================")
	print("  %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)
