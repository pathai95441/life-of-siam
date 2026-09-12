extends Node
## Draw-order test that actually looks at the rendered pixels.
##
## Must run windowed, not headless: headless renders nothing, so it can only
## ever check the sort key, never the result. Run with
##     godot --path . tests/depth_sort_test.tscn
##
## The contract under test is the one WorldSpace.depth_key documents: an
## object's ground contact point decides what is in front, and its height does
## not. A tall thing standing behind a short thing must stay behind it, however
## far up the screen its art reaches.

const BACK_COLOR := Color(1, 0, 0)
const FRONT_COLOR := Color(0, 0, 1)

var pass_count := 0
var fail_count := 0

var _image: Image
var _scale: float = 1.0


func check(label: String, condition: bool) -> void:
	if condition:
		pass_count += 1
		print("  PASS  ", label)
	else:
		fail_count += 1
		print("  FAIL  ", label)


func _ready() -> void:
	# Left: the tall one stands behind. Right: the tall one stands in front.
	# Same sizes, only the ground positions swap.
	_build_pair(Vector2(120, 110), Vector2(0, 0), Vector2(40, 60),
		Vector2(0, 0.5), Vector2(40, 24))
	_build_pair(Vector2(300, 110), Vector2(0, 0.5), Vector2(40, 60),
		Vector2(0, 0), Vector2(40, 24))

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_image = get_viewport().get_texture().get_image()
	_scale = float(_image.get_width()) / float(
		ProjectSettings.get_setting("display/window/size/viewport_width"))

	_test_tall_object_behind()
	_test_tall_object_in_front()

	print("\n==================================================")
	print("  depth_sort_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


## One y-sorted container holding two markers at given ground offsets.
##
## The front marker is added to the tree FIRST on purpose: if y-sorting were
## not doing the work, tree order would paint it underneath and these tests
## would fail rather than passing by luck.
func _build_pair(origin: Vector2, back_ground: Vector2, back_size: Vector2,
		front_ground: Vector2, front_size: Vector2) -> void:
	var container := Node2D.new()
	container.position = origin
	container.y_sort_enabled = true
	add_child(container)
	container.add_child(_marker(FRONT_COLOR, front_ground, front_size))
	container.add_child(_marker(BACK_COLOR, back_ground, back_size))


func _marker(color: Color, ground: Vector2, size: Vector2) -> Polygon2D:
	var marker := Polygon2D.new()
	var half := size * 0.5
	marker.polygon = PackedVector2Array([
		-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	marker.color = color
	# Anchored by its ground point, exactly as entities are.
	marker.position = WorldSpace.ground_to_screen(ground)
	return marker


## Colour at a point given in canvas coordinates.
func _sample(canvas_point: Vector2) -> Color:
	return _image.get_pixel(int(canvas_point.x * _scale), int(canvas_point.y * _scale))


func _is(sampled: Color, expected: Color) -> bool:
	return sampled.is_equal_approx(expected)


## Tall marker centred at ground 0 spans canvas y 80..140.
## Short marker at ground 0.5 (8 px down) spans 106..130.
func _test_tall_object_behind() -> void:
	print("\n--- tall object standing behind a short one ---")
	check("above both, the tall one is visible",
		_is(_sample(Vector2(120, 90)), BACK_COLOR))
	check("where they overlap, the nearer short one wins",
		_is(_sample(Vector2(120, 118)), FRONT_COLOR))
	check("below the short one, the tall one is still there",
		_is(_sample(Vector2(120, 136)), BACK_COLOR))


## Same shapes, ground positions swapped: now the tall one is nearer and must
## cover the short one. This is what proves depth follows the ground point
## rather than the size or the tree order.
func _test_tall_object_in_front() -> void:
	print("\n--- tall object standing in front of a short one ---")
	check("where they overlap, the nearer tall one wins",
		_is(_sample(Vector2(300, 118)), BACK_COLOR))
	check("the short one is completely covered",
		not _is(_sample(Vector2(300, 112)), FRONT_COLOR))
