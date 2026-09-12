extends Node
## Save format and migration. Pure data, no scene: [SaveMigration] takes a
## dictionary and returns one, which is exactly why it was pulled out of
## SaveManager -- a payload written by hand is a complete test case.

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
	_test_current_version_is_left_alone()
	_test_v1_scene_state_moves_under_the_starting_map()
	_test_v1_keeps_every_cell()
	_test_v1_without_scene_state()
	_test_newer_saves_are_not_mangled()
	_test_two_maps_do_not_collide()
	_test_v2_lifts_the_player_out_of_the_map()
	_test_v1_walks_the_whole_chain()

	print("\n==================================================")
	print("  save_format_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


## A real v1 payload, in the shape the game actually wrote before this phase.
func _v1_payload() -> Dictionary:
	return {
		"header": {"version": 1, "money": 720, "day": 9},
		"providers": {"game_state": {"money": 720}},
		"scene": {
			"farm_grid": {"cells": {"0,0": {"tilled": true, "crop_id": "turnip"},
				"1,0": {"tilled": true, "watered": true}}},
			"shipping_bin": {"contents": {"turnip": 4}},
		},
	}


## v2 filed the player under a map, so walking back in put them where they
## last stood rather than at the door they came through.
func _test_v2_lifts_the_player_out_of_the_map() -> void:
	print("\n--- v2 moves the player out of the map ---")
	var v2 := {
		"header": {"version": 2},
		"scene": {"farm": {
			"farm_grid": {"cells": {"2,2": {"tilled": true}}},
			"player": {"x": 64.0, "y": 32.0},
		}},
	}
	var out := SaveMigration.migrate(v2)
	check_eq("stamped as current", SaveMigration.version_of(out), GameConstants.SAVE_VERSION)
	check("the player is in their own block",
		(out.get("traveller", {}) as Dictionary).has("player"))
	check_eq("with their position intact", out["traveller"]["player"]["x"], 64.0)
	check("and no longer inside the map",
		not (out["scene"]["farm"] as Dictionary).has("player"))
	check("the map keeps everything else",
		out["scene"]["farm"]["farm_grid"]["cells"].has("2,2"))


## Players skip versions. A save from the first build has to walk every step,
## which is the whole reason old branches are never deleted.
func _test_v1_walks_the_whole_chain() -> void:
	print("\n--- v1 all the way to the current format ---")
	var out := SaveMigration.migrate(_v1_payload())
	check_eq("arrives at the current version",
		SaveMigration.version_of(out), GameConstants.SAVE_VERSION)
	check("it went through the map-nesting step",
		(out["scene"] as Dictionary).has(String(GameConstants.STARTING_MAP)))
	check("and through the traveller step", out.has("traveller"))
	check("with the field intact after both",
		out["scene"][String(GameConstants.STARTING_MAP)]["farm_grid"]["cells"].has("0,0"))


func _test_current_version_is_left_alone() -> void:
	print("\n--- a current save needs no work ---")
	var payload := {"header": {"version": GameConstants.SAVE_VERSION},
		"scene": {"farm": {"farm_grid": {}}}}
	var out := SaveMigration.migrate(payload.duplicate(true))
	check_eq("version unchanged", SaveMigration.version_of(out), GameConstants.SAVE_VERSION)
	check("scene state untouched", out["scene"].has("farm"))


## The point of the whole format change: v1 had nowhere to say which map its
## scene state belonged to, because there was only one.
func _test_v1_scene_state_moves_under_the_starting_map() -> void:
	print("\n--- v1 scene state gets a map ---")
	var out := SaveMigration.migrate(_v1_payload())
	check_eq("stamped as current", SaveMigration.version_of(out), GameConstants.SAVE_VERSION)

	var scene: Dictionary = out["scene"]
	check("state now lives under a map key",
		scene.has(String(GameConstants.STARTING_MAP)))
	check("and not loose at the top any more", not scene.has("farm_grid"))


## Migrating must not quietly cost the player their field.
func _test_v1_keeps_every_cell() -> void:
	print("\n--- nothing is lost on the way ---")
	var out := SaveMigration.migrate(_v1_payload())
	var block: Dictionary = out["scene"][String(GameConstants.STARTING_MAP)]

	check("the farm grid came across", block.has("farm_grid"))
	check_eq("with both of its cells", (block["farm_grid"]["cells"] as Dictionary).size(), 2)
	check("the planted cell still names its crop",
		block["farm_grid"]["cells"]["0,0"]["crop_id"] == "turnip")
	check("the watered cell is still watered",
		block["farm_grid"]["cells"]["1,0"]["watered"])
	check("the shipping bin came across too", block.has("shipping_bin"))
	check_eq("with its contents", block["shipping_bin"]["contents"]["turnip"], 4)
	check_eq("and the providers are untouched",
		out["providers"]["game_state"]["money"], 720)


func _test_v1_without_scene_state() -> void:
	print("\n--- a v1 save from before anything was built ---")
	var out := SaveMigration.migrate({"header": {"version": 1}, "providers": {}})
	check_eq("still upgraded", SaveMigration.version_of(out), GameConstants.SAVE_VERSION)
	check("scene state is an empty map table, not missing",
		out.has("scene") and (out["scene"] as Dictionary).is_empty())


## A file from a future build must be left alone rather than rearranged by
## rules that predate it.
func _test_newer_saves_are_not_mangled() -> void:
	print("\n--- a save from a newer build ---")
	var future := {"header": {"version": GameConstants.SAVE_VERSION + 5},
		"scene": {"somewhere_new": {"thing": {}}}}
	var out := SaveMigration.migrate(future.duplicate(true))
	check_eq("its version is preserved", SaveMigration.version_of(out),
		GameConstants.SAVE_VERSION + 5)
	check("its scene state is preserved", out["scene"].has("somewhere_new"))


## P2: two maps each holding a farm grid used to write to the same key, and
## SaveManager dropped one of them with an error.
func _test_two_maps_do_not_collide() -> void:
	print("\n--- two maps, same systems ---")
	var payload := {
		"header": {"version": GameConstants.SAVE_VERSION},
		"scene": {
			"farm": {"farm_grid": {"cells": {"0,0": {"tilled": true}}}},
			"greenhouse": {"farm_grid": {"cells": {"5,5": {"tilled": true}}}},
		},
	}
	var scene: Dictionary = payload["scene"]
	check_eq("both maps are present", scene.size(), 2)
	check("each keeps its own grid",
		scene["farm"]["farm_grid"]["cells"].has("0,0")
			and scene["greenhouse"]["farm_grid"]["cells"].has("5,5"))
	check("neither sees the other's cells",
		not scene["farm"]["farm_grid"]["cells"].has("5,5"))
