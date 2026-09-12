extends Node
## Unit tests for [WorldObjectData] and its registry in [Database].
##
## Two jobs: prove the authored .tres files match the canonical scale table in
## GAME_DESIGN.md, and prove a malformed definition is caught rather than
## silently producing a zero-sized collider.

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
	_test_canonical_scale()
	_test_derived_bounds()
	_test_origin_offset()
	_test_validation()
	_test_scale_consistency()

	print("\n==================================================")
	print("  world_object_data_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _test_registry() -> void:
	print("\n--- registry ---")
	check_eq("Database loaded 6 world objects", Database.world_objects.size(), 6)
	for id in [&"player", &"npc_adult", &"bed", &"sign_post", &"shipping_bin", &"shop_stall"]:
		check("'%s' is registered" % id, Database.get_world_object(id) != null)
	check("unknown id returns null", Database.get_world_object(&"nope") == null)


## The .tres files must agree with GAME_DESIGN.md section 2. If this fails,
## either the table moved or someone edited a resource without updating it.
func _test_canonical_scale() -> void:
	print("\n--- canonical scale table ---")
	var expected := {
		&"player": [Vector2(0.6, 0.4), 1.8, false, 0.0],
		&"npc_adult": [Vector2(0.6, 0.4), 1.8, true, 0.8],
		&"bed": [Vector2(2.0, 1.5), 0.6, true, 1.0],
		&"sign_post": [Vector2(0.4, 0.2), 1.4, false, 0.8],
		&"shipping_bin": [Vector2(1.0, 1.0), 0.9, true, 1.0],
		&"shop_stall": [Vector2(2.5, 1.2), 2.2, true, 1.0],
	}
	for id in expected:
		var data := Database.get_world_object(id)
		if data == null:
			check("%s exists" % id, false)
			continue
		var want: Array = expected[id]
		check_eq("%s footprint" % id, data.footprint, want[0])
		check_eq("%s height" % id, data.height, want[1])
		check_eq("%s blocks_movement" % id, data.blocks_movement, want[2])
		check_eq("%s interaction_reach" % id, data.interaction_reach, want[3])
		check_eq("%s width() == footprint.x" % id, data.width(), (want[0] as Vector2).x)
		check_eq("%s depth() == footprint.y" % id, data.depth(), (want[0] as Vector2).y)


func _test_derived_bounds() -> void:
	print("\n--- derived bounds ---")
	var player := Database.get_world_object(&"player")
	# 0.6 wu * 32 px, 0.4 wu * 16 px (depth is foreshortened).
	check_eq("player collision screen size",
		player.collision_screen_size(), Vector2(0.6 * 32.0, 0.4 * 16.0))
	var rect := player.footprint_rect(Vector2(10, 10))
	check_eq("footprint centres on the position", rect.get_center(), Vector2(10, 10))
	check_eq("footprint size is the declared footprint", rect.size, Vector2(0.6, 0.4))

	var bed := Database.get_world_object(&"bed")
	var interact := bed.interaction_rect(Vector2.ZERO)
	check_eq("bed interaction rect grows by reach on every side",
		interact.size, bed.footprint + Vector2.ONE * bed.interaction_reach * 2.0)
	check("bed interaction rect contains its footprint",
		interact.encloses(bed.footprint_rect(Vector2.ZERO)))
	check_eq("bed is interactable", bed.is_interactable(), true)
	check_eq("player is not interactable", player.is_interactable(), false)


func _test_origin_offset() -> void:
	print("\n--- origin offset ---")
	var centred := WorldObjectData.new()
	centred.footprint = Vector2(2, 2)
	centred.origin = Vector2(0.5, 0.5)
	check_eq("centred origin needs no shape offset",
		centred.collision_screen_offset(), Vector2.ZERO)

	var front := WorldObjectData.new()
	front.footprint = Vector2(2, 2)
	front.origin = Vector2(0.5, 1.0)
	# Footprint centre is 1 wu behind the position: -1 * 16 px on screen.
	check_eq("front-anchored origin shifts the shape back",
		front.collision_screen_offset(), Vector2(0, -16))
	check_eq("front-anchored footprint front edge is on the position",
		front.footprint_rect(Vector2.ZERO).end.y, 0.0)


func _test_validation() -> void:
	print("\n--- validation ---")
	for data in Database.world_objects.values():
		check("authored '%s' is valid" % data.id, data.is_valid())

	check_eq("empty id is rejected", _errors_for(&"", Vector2.ONE, 1.0,
		Vector2(0.5, 0.5), 0.0).is_empty(), false)
	check_eq("zero footprint is rejected", _errors_for(&"x", Vector2.ZERO, 1.0,
		Vector2(0.5, 0.5), 0.0).is_empty(), false)
	check_eq("negative footprint is rejected", _errors_for(&"x", Vector2(-1, 1), 1.0,
		Vector2(0.5, 0.5), 0.0).is_empty(), false)
	check_eq("negative height is rejected", _errors_for(&"x", Vector2.ONE, -1.0,
		Vector2(0.5, 0.5), 0.0).is_empty(), false)
	check_eq("origin outside 0..1 is rejected", _errors_for(&"x", Vector2.ONE, 1.0,
		Vector2(1.5, 0.5), 0.0).is_empty(), false)
	check_eq("negative reach is rejected", _errors_for(&"x", Vector2.ONE, 1.0,
		Vector2(0.5, 0.5), -1.0).is_empty(), false)
	check_eq("zero height is allowed (flat props)", _errors_for(&"x", Vector2.ONE, 0.0,
		Vector2(0.5, 0.5), 0.0).is_empty(), true)
	# The message must name the problem, not just report failure.
	var errors := _errors_for(&"x", Vector2.ZERO, 1.0, Vector2(0.5, 0.5), 0.0)
	check("error text names the offending field", errors[0].contains("footprint"))


## Scale must stay coherent between object kinds -- rule 18 in AGENTS.md.
func _test_scale_consistency() -> void:
	print("\n--- scale consistency ---")
	var player := Database.get_world_object(&"player")
	var npc := Database.get_world_object(&"npc_adult")
	var bed := Database.get_world_object(&"bed")
	var sign := Database.get_world_object(&"sign_post")
	check_eq("an adult villager is the same size as the player",
		npc.footprint, player.footprint)
	check("a bed is wider than a person", bed.width() > player.width())
	check("a bed is lower than a person is tall", bed.height < player.height)
	check("a sign is taller than a bed but takes less ground",
		sign.height > bed.height and sign.width() < bed.width())
	check("every person is roughly a metre wide, not a tile wide",
		player.width() < 1.0 and player.width() > 0.3)


func _errors_for(id: StringName, footprint: Vector2, height: float,
		origin: Vector2, reach: float) -> Array[String]:
	var data := WorldObjectData.new()
	data.id = id
	data.footprint = footprint
	data.height = height
	data.origin = origin
	data.interaction_reach = reach
	return data.validation_errors()
