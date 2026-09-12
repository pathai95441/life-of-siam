extends Node
## Integration tests for entities: that their extents come from resources
## (W4, W5) and that the interaction probe still reaches them.
##
## Split out of world_test once that file passed the 250-line limit. Both need
## the world scene; this one is about what is in it, that one about the level
## itself.

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
	var world: World = load("res://src/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_player_world_body()
	_test_entities_are_data_driven()
	await _test_interaction_reach_band()

	print("\n==================================================")
	print("  entity_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


## W4: the player's collider must come from wo_player.tres, not from a shape
## somebody sized by eye in player.tscn.
func _test_player_world_body() -> void:
	print("\n--- player world body (W4) ---")
	var player: Player = get_tree().get_first_node_in_group(&"player")
	if player == null:
		check("player exists", false)
		return
	var body := player.world_body
	check("player has a WorldBody component", body != null)
	if body == null:
		return
	check("it is wired to wo_player.tres", body.data != null and body.data.id == &"player")
	check("it is wired to the player body itself", body.collision_body == player)

	_check_player_collider(player, body)
	_check_player_probe(player)
	_check_player_sprite_scale(player, body)


func _check_player_collider(player: Player, body: WorldBody) -> void:
	var shape_node := body.collision_shape()
	check("a collider was built at runtime", shape_node != null)
	if shape_node == null:
		return
	check("the collider is a rectangle, not the old circle",
		shape_node.shape is RectangleShape2D)
	check_eq("collider size comes from the resource",
		(shape_node.shape as RectangleShape2D).size, body.data.collision_screen_size())
	check_eq("collider is centred, matching a centred origin",
		shape_node.position, Vector2.ZERO)
	check("the player still collides with the world layer",
		player.collision_mask & GameConstants.layer_mask(GameConstants.Layer.WORLD) != 0)


func _check_player_probe(player: Player) -> void:
	var probe_shape := player.probe.get_node_or_null(
		InteractionProbe.SENSOR_SHAPE_NAME) as CollisionShape2D
	check("the probe built its own sensor", probe_shape != null)
	if probe_shape != null:
		check_eq("sensor size comes from PROBE_SIZE_UNITS",
			(probe_shape.shape as RectangleShape2D).size,
			WorldSpace.footprint_screen_size(GameConstants.PROBE_SIZE_UNITS))
	check("the probe sits in front of the player, not on top of it",
		not player.probe.position.is_zero_approx())


## Rule 18: the placeholder art must match the size the data declares, or the
## screen lies about how big things are.
func _check_player_sprite_scale(player: Player, body: WorldBody) -> void:
	var sprite_height: float = player.sprite.texture.get_height() * player.sprite.scale.y
	var declared_height := body.data.height * WorldSpace.height_px()
	check("sprite height matches the declared height (%.1f px)" % declared_height,
		is_equal_approx(sprite_height, declared_height))
	check("sprite stands on the ground position, not through it",
		player.sprite.position.y < 0.0)


## W5: every interactable in the world must get its extents from a resource,
## with every node reference actually resolved. A NodePath written without
## node_paths= in the scene leaves the property null and silent, which is how
## npc.tscn shipped a dead sprite_node for two tasks.
func _test_entities_are_data_driven() -> void:
	print("\n--- entities are data driven (W5) ---")
	var expected := {
		&"Somchai": &"npc_adult", &"Bed": &"bed", &"SignPost": &"sign_post",
		&"ShippingBin": &"shipping_bin", &"Shop": &"shop_stall",
	}
	for target in get_tree().get_nodes_in_group(&"interactable"):
		var interactable := target as Interactable
		if interactable != null:
			_check_entity(interactable, expected)

	var npc := get_tree().get_first_node_in_group(&"npc") as Npc
	check("npc sprite_node resolved (the node_paths bug)",
		npc != null and npc.sprite_node != null)


func _check_entity(interactable: Interactable, expected: Dictionary) -> void:
	var label := interactable.owner_label()
	var body := interactable.get_node_or_null("WorldBody") as WorldBody
	check("'%s' has a WorldBody" % label, body != null)
	if body == null or body.data == null:
		check("'%s' has data" % label, false)
		return
	check("'%s' has data" % label, true)
	if expected.has(StringName(label)):
		check_eq("'%s' uses the right resource" % label,
			body.data.id, expected[StringName(label)])

	_check_entity_interaction(label, body)
	_check_entity_blocking(label, body)
	_check_entity_visual(label, interactable)


func _check_entity_interaction(label: String, body: WorldBody) -> void:
	check("'%s' interaction_area resolved (not a null NodePath)" % label,
		body.interaction_area != null)
	var shape_node := body.interaction_shape()
	check("'%s' interaction shape was built" % label, shape_node != null)
	if shape_node != null:
		check_eq("'%s' interaction size comes from data" % label,
			(shape_node.shape as RectangleShape2D).size,
			body.data.interaction_screen_size())


## blocks_movement must match whether anything solid actually exists.
func _check_entity_blocking(label: String, body: WorldBody) -> void:
	if body.data.blocks_movement:
		check("'%s' declares blocking and has a collider" % label,
			body.collision_body != null and body.collision_shape() != null)
	else:
		check("'%s' declares no blocking and has no collider" % label,
			body.collision_shape() == null)


func _check_entity_visual(label: String, interactable: Interactable) -> void:
	var visual := interactable.get_node_or_null("PlaceholderVisual") as PlaceholderVisual
	check("'%s' has a PlaceholderVisual" % label, visual != null)
	if visual != null:
		check("'%s' visual wiring resolved" % label,
			visual.world_body != null and visual.target != null)


## W4 moved the probe from a hand-picked 12 px to 1 world unit (32 px), while
## NPCs, beds and signs still carry hand-sized areas until W5 replaces them
## with data-derived ones. Rather than assert one distance, this sweeps and
## reports the band each object is actually reachable in, so the effect of W5
## is measurable instead of hoped for.
func _test_interaction_reach_band() -> void:
	print("\n--- interaction reach band (W4 transitional) ---")
	var player: Player = get_tree().get_first_node_in_group(&"player")
	if player == null:
		check("player exists", false)
		return

	var probe_offset := player.probe.reach_units * WorldSpace.ground_px()
	print("    probe sits %.0f px in front of the player" % probe_offset)

	for target in get_tree().get_nodes_in_group(&"interactable"):
		var interactable := target as Interactable
		if interactable == null:
			continue
		var band := await _reach_band(player, interactable)
		var label := interactable.owner_label()
		if band.is_empty():
			check("'%s' is reachable at some distance" % label, false)
			continue
		print("    %-10s reachable at %d-%d px%s" % [label, band[0], band[-1],
			"  <-- covers the probe offset" if band.has(int(probe_offset)) else ""])
		check("'%s' is reachable at some distance" % label, true)
		check("'%s' is reachable at the probe offset" % label,
			band.has(int(probe_offset)))


## Distances, in whole pixels, at which [param target] gets probe focus.
func _reach_band(player: Player, target: Interactable) -> Array[int]:
	var hits: Array[int] = []
	for distance in range(4, 64, 4):
		player.global_position = target.global_position + Vector2(distance, 0)
		player.set_facing(Vector2.LEFT)
		player.force_update_transform()
		await get_tree().physics_frame
		await get_tree().physics_frame
		if player.probe.focused == target:
			hits.append(distance)
	return hits


