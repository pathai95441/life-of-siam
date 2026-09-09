extends Node
## Unit tests for [WorldSpace]. Pure arithmetic: no scene, no rendering, no
## autoload state. If this file ever needs a node, the projection has leaked.

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


func check_near(label: String, got: Vector2, want: Vector2) -> void:
	check("%s (got %s, want %s)" % [label, got, want], got.is_equal_approx(want))


func _ready() -> void:
	_test_scale()
	_test_projection()
	_test_round_trip()
	_test_grid()
	_test_footprints()
	_test_depth_order()

	print("\n==================================================")
	print("  world_space_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _test_scale() -> void:
	print("\n--- scale (canonical: 32 px/wu, depth 0.5) ---")
	check_eq("ground_px", WorldSpace.ground_px(), 32.0)
	check_eq("depth_px is foreshortened", WorldSpace.depth_px(), 16.0)
	check_eq("height_px", WorldSpace.height_px(), 32.0)
	check("depth is shorter than ground, i.e. the plane is tilted",
		WorldSpace.depth_px() < WorldSpace.ground_px())


func _test_projection() -> void:
	print("\n--- projection ---")
	check_near("origin maps to origin", WorldSpace.ground_to_screen(Vector2.ZERO), Vector2.ZERO)
	check_near("1 wu east = 32 px right",
		WorldSpace.ground_to_screen(Vector2(1, 0)), Vector2(32, 0))
	check_near("1 wu south = 16 px down (foreshortened)",
		WorldSpace.ground_to_screen(Vector2(0, 1)), Vector2(0, 16))
	check_near("3D: elevation raises the point up the screen",
		WorldSpace.world_to_screen(Vector3(1, 1, 1)), Vector2(32, 16 - 32))
	check_near("elevation_offset is purely vertical and negative",
		WorldSpace.elevation_offset(2.0), Vector2(0, -64))
	check_near("z = 0 matches the ground projection",
		WorldSpace.world_to_screen(Vector3(2, 3, 0)),
		WorldSpace.ground_to_screen(Vector2(2, 3)))


func _test_round_trip() -> void:
	print("\n--- round trip: ground -> screen -> ground ---")
	for point in [Vector2.ZERO, Vector2(1, 1), Vector2(-4, 7),
			Vector2(0.25, -0.75), Vector2(123.5, -456.25)]:
		var back := WorldSpace.screen_to_ground(WorldSpace.ground_to_screen(point))
		check("%s survives the round trip (got %s)" % [point, back],
			back.is_equal_approx(point))


func _test_grid() -> void:
	print("\n--- grid ---")
	check_eq("point inside cell 0,0", WorldSpace.ground_to_cell(Vector2(0.5, 0.5)), Vector2i(0, 0))
	check_eq("cell boundary belongs to the higher cell",
		WorldSpace.ground_to_cell(Vector2(1.0, 1.0)), Vector2i(1, 1))
	check_eq("negatives floor away from zero, not toward it",
		WorldSpace.ground_to_cell(Vector2(-0.1, -0.1)), Vector2i(-1, -1))
	check_eq("centre of cell 0,0", WorldSpace.cell_centre(Vector2i(0, 0)), Vector2(0.5, 0.5))
	check_eq("centre of cell -2,3", WorldSpace.cell_centre(Vector2i(-2, 3)), Vector2(-1.5, 3.5))
	check_eq("origin of cell 2,3", WorldSpace.cell_origin(Vector2i(2, 3)), Vector2(2, 3))
	# A cell centre must land back in its own cell -- the classic off-by-one.
	for cell in [Vector2i(0, 0), Vector2i(-1, -1), Vector2i(5, -7)]:
		check_eq("centre of %s resolves back to itself" % cell,
			WorldSpace.ground_to_cell(WorldSpace.cell_centre(cell)), cell)


func _test_footprints() -> void:
	print("\n--- footprints ---")
	var centred := WorldSpace.footprint_rect(Vector2(10, 10), Vector2(2, 1))
	check_eq("centred footprint position", centred.position, Vector2(9, 9.5))
	check_eq("centred footprint size", centred.size, Vector2(2, 1))
	check_eq("centred footprint really is centred", centred.get_center(), Vector2(10, 10))

	var front := WorldSpace.footprint_rect(Vector2(0, 0), Vector2(2, 4), Vector2(0.5, 1.0))
	check_eq("front-anchored footprint extends backwards", front.position, Vector2(-1, -4))
	check_eq("front-anchored footprint front edge sits on the point", front.end.y, 0.0)

	check_eq("screen size is foreshortened in depth only",
		WorldSpace.footprint_screen_size(Vector2(2, 2)), Vector2(64, 32))
	# The player from GAME_DESIGN: 0.6 x 0.4 wu.
	check_eq("player footprint in screen px",
		WorldSpace.footprint_screen_size(Vector2(0.6, 0.4)),
		Vector2(0.6 * 32.0, 0.4 * 16.0))


func _test_depth_order() -> void:
	print("\n--- draw order ---")
	var behind := WorldSpace.depth_key(Vector2(0, 3))
	var in_front := WorldSpace.depth_key(Vector2(0, 5))
	check("larger world y sorts in front", in_front > behind)
	check_eq("objects on the same row are coplanar",
		WorldSpace.depth_key(Vector2(-99, 4)), WorldSpace.depth_key(Vector2(99, 4)))
	# Height must not leak into depth: a tree does not occlude a person
	# standing beside it just because its art is taller.
	check_eq("depth ignores elevation entirely",
		WorldSpace.depth_key(Vector2(0, 2)), WorldSpace.depth_key(Vector2(0, 2)))
	check("a tall object behind still sorts behind",
		WorldSpace.depth_key(Vector2(0, 1)) < WorldSpace.depth_key(Vector2(0, 2)))
