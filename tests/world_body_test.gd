extends Node
## Integration tests for [WorldBody].
##
## Rigs are built in code rather than as fixture scenes: the whole point of the
## component is that scenes stop carrying shapes, so a fixture scene with
## authored shapes would test the opposite of what we want.

var pass_count := 0
var fail_count := 0
var _rig_count := 0


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
	await _test_collision_from_data()
	await _test_interaction_from_data()
	await _test_non_interactable()
	await _test_walkthrough_object()
	await _test_rebuild_is_idempotent()
	await _test_origin_offset_applied()
	await _test_authored_resources_drive_real_sizes()

	print("\n==================================================")
	print("  world_body_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


# --- Rig --------------------------------------------------------------------

## Builds owner -> {StaticBody2D, Area2D, WorldBody} and waits for _ready.
func _rig(data: WorldObjectData, wire_body: bool = true,
		wire_area: bool = true) -> Dictionary:
	var root := Node2D.new()
	root.name = "Rig%d" % _rig_count
	_rig_count += 1
	add_child(root)

	var body := StaticBody2D.new()
	body.name = "Body"
	root.add_child(body)

	var area := Area2D.new()
	area.name = "Zone"
	root.add_child(area)

	var world_body := WorldBody.new()
	world_body.name = "WorldBody"
	world_body.data = data
	world_body.collision_body = body if wire_body else null
	world_body.interaction_area = area if wire_area else null
	root.add_child(world_body)

	await get_tree().process_frame
	return {"root": root, "body": body, "area": area, "world_body": world_body}


func _make_data(footprint: Vector2, reach: float, blocks: bool,
		origin := Vector2(0.5, 0.5)) -> WorldObjectData:
	var data := WorldObjectData.new()
	data.id = &"rig"
	data.footprint = footprint
	data.height = 1.0
	data.origin = origin
	data.blocks_movement = blocks
	data.interaction_reach = reach
	return data


# --- Tests ------------------------------------------------------------------

func _test_collision_from_data() -> void:
	print("\n--- collision shape is built from data ---")
	var data := _make_data(Vector2(2, 1), 0.0, true)
	var rig := await _rig(data, true, false)
	var world_body: WorldBody = rig["world_body"]
	var shape_node := world_body.collision_shape()

	check("a collision shape was created", shape_node != null)
	if shape_node == null:
		return
	check_eq("shape node name", shape_node.name, WorldBody.COLLISION_SHAPE_NAME)
	check("shape is a rectangle", shape_node.shape is RectangleShape2D)
	# 2 wu * 32 px wide, 1 wu * 16 px deep -- depth foreshortened.
	check_eq("size comes from the footprint, foreshortened in depth",
		(shape_node.shape as RectangleShape2D).size, Vector2(64, 16))
	check_eq("size equals what the data derives",
		(shape_node.shape as RectangleShape2D).size, data.collision_screen_size())
	rig["root"].queue_free()


func _test_interaction_from_data() -> void:
	print("\n--- interaction shape is the footprint grown by reach ---")
	var data := _make_data(Vector2(2, 1), 1.0, true)
	var rig := await _rig(data)
	var world_body: WorldBody = rig["world_body"]
	var shape_node := world_body.interaction_shape()

	check("an interaction shape was created", shape_node != null)
	if shape_node == null:
		return
	# footprint + reach on both sides: 4 x 3 wu -> 128 x 48 px.
	check_eq("interaction size includes the reach",
		(shape_node.shape as RectangleShape2D).size, Vector2(128, 48))
	var collision := world_body.collision_shape()
	check("interaction area is larger than the collision footprint",
		(shape_node.shape as RectangleShape2D).size
			> (collision.shape as RectangleShape2D).size)
	rig["root"].queue_free()


func _test_non_interactable() -> void:
	print("\n--- reach 0 builds no interaction shape ---")
	# Area deliberately wired despite reach 0: this is the case that must warn
	# rather than silently produce an interaction zone of the bare footprint.
	var rig := await _rig(_make_data(Vector2.ONE, 0.0, true))
	var world_body: WorldBody = rig["world_body"]
	check("no interaction shape when reach is 0", world_body.interaction_shape() == null)
	check("collision shape is still built", world_body.collision_shape() != null)
	rig["root"].queue_free()


func _test_walkthrough_object() -> void:
	print("\n--- no collision_body wired means no collision shape ---")
	var rig := await _rig(_make_data(Vector2(0.4, 0.2), 0.8, false), false, true)
	var world_body: WorldBody = rig["world_body"]
	check("nothing solid is created", world_body.collision_shape() == null)
	check("the wired body really has no shape child",
		(rig["body"] as StaticBody2D).get_child_count() == 0)
	check("interaction still works", world_body.interaction_shape() != null)
	rig["root"].queue_free()


func _test_rebuild_is_idempotent() -> void:
	print("\n--- rebuild reuses shape nodes ---")
	var rig := await _rig(_make_data(Vector2(2, 2), 1.0, true))
	var world_body: WorldBody = rig["world_body"]
	var body: StaticBody2D = rig["body"]
	var before := body.get_child_count()

	world_body.rebuild()
	world_body.rebuild()
	check_eq("three builds still leave one shape child", body.get_child_count(), before)

	# A changed resource must be picked up, not ignored for being cached.
	world_body.data.footprint = Vector2(4, 4)
	world_body.rebuild()
	check_eq("rebuild applies the new footprint",
		(world_body.collision_shape().shape as RectangleShape2D).size, Vector2(128, 64))
	rig["root"].queue_free()


func _test_origin_offset_applied() -> void:
	print("\n--- non-centred origin offsets the shape ---")
	var centred := await _rig(_make_data(Vector2(2, 2), 0.0, true), true, false)
	check_eq("centred origin leaves the shape at zero",
		(centred["world_body"] as WorldBody).collision_shape().position, Vector2.ZERO)
	centred["root"].queue_free()

	var front := await _rig(_make_data(Vector2(2, 2), 0.0, true, Vector2(0.5, 1.0)), true, false)
	var shape_node := (front["world_body"] as WorldBody).collision_shape()
	# Footprint centre sits 1 wu behind the position: -16 px on screen.
	check_eq("front-anchored origin pushes the shape back",
		shape_node.position, Vector2(0, -16))
	front["root"].queue_free()


## The real authored resources must produce the sizes W4 and W5 will rely on.
func _test_authored_resources_drive_real_sizes() -> void:
	print("\n--- authored resources ---")
	var bed := Database.get_world_object(&"bed")
	var rig := await _rig(bed)
	var world_body: WorldBody = rig["world_body"]
	# Bed is 2.0 x 1.5 wu -> 64 x 24 px, replacing the authored 24 x 16.
	check_eq("bed collision size from wo_bed.tres",
		(world_body.collision_shape().shape as RectangleShape2D).size, Vector2(64, 24))
	# Reach 1.0 -> 4.0 x 3.5 wu -> 128 x 56 px, replacing the authored 32 x 28.
	check_eq("bed interaction size from wo_bed.tres",
		(world_body.interaction_shape().shape as RectangleShape2D).size, Vector2(128, 56))
	rig["root"].queue_free()

	var player := Database.get_world_object(&"player")
	var player_rig := await _rig(player, true, false)
	check_eq("player collision size from wo_player.tres",
		((player_rig["world_body"] as WorldBody).collision_shape().shape
			as RectangleShape2D).size, Vector2(0.6 * 32.0, 0.4 * 16.0))
	player_rig["root"].queue_free()
