class_name FarmDebugView
extends Node2D
## Blockout renderer for [FarmGrid]. Reads the model, owns no state.
##
## Exists so the model stays a model: FarmGrid decides what the soil is, this
## decides what it looks like. Replacing it with a TileMapLayer for soil and
## pooled sprites for crops touches only this file.
##
## Delete or hide it once real art exists.

## The model to draw. Wired explicitly, never discovered.
@export var grid: FarmGrid
@export var enabled: bool = true


func _ready() -> void:
	if grid == null:
		push_error("FarmDebugView on '%s' has no grid wired" % name)
		return
	grid.changed.connect(queue_redraw)
	# The grid may already hold restored save data by the time this runs.
	queue_redraw()


func _draw() -> void:
	if not enabled or grid == null:
		return
	_draw_field_outline()
	for cell in grid.cells():
		_draw_cell(cell, grid.get_cell(cell))


## Cells project to a foreshortened rectangle, not a square: that shape is the
## clearest signal that the ground plane is tilted.
func _draw_field_outline() -> void:
	var origin := WorldSpace.ground_to_screen(Vector2(grid.arable_region.position))
	var extent := WorldSpace.footprint_screen_size(Vector2(grid.arable_region.size))
	draw_rect(Rect2(origin, extent), Color(1, 1, 1, 0.06), false, 1.0)


func _draw_cell(cell: Vector2i, soil: SoilCell) -> void:
	if soil == null:
		return
	var origin := WorldSpace.ground_to_screen(WorldSpace.cell_origin(cell))
	var size := WorldSpace.footprint_screen_size(Vector2.ONE)

	if soil.tilled:
		var soil_color := Color(0.22, 0.15, 0.10) if soil.watered else Color(0.35, 0.22, 0.12)
		draw_rect(Rect2(origin, size), soil_color)
		draw_rect(Rect2(origin, size), Color(0, 0, 0, 0.25), false, 1.0)

	if soil.has_crop():
		_draw_crop(origin + size * 0.5, soil)


## Plants stand up out of the ground: an upright quad whose height follows the
## crop's growth, matching how every other object is drawn during blockout.
func _draw_crop(base: Vector2, soil: SoilCell) -> void:
	var crop := soil.crop()
	if crop == null:
		return

	var width := WorldSpace.ground_px() * 0.3
	if soil.withered:
		var stub := WorldSpace.height_px() * 0.2
		draw_rect(Rect2(base - Vector2(width * 0.5, stub), Vector2(width, stub)),
			Color(0.45, 0.4, 0.25))
		return

	var progress := clampf(float(soil.growth_days)
		/ maxf(1.0, float(crop.total_growth_days())), 0.0, 1.0)
	var height := GameConstants.CROP_MAX_HEIGHT_UNITS * WorldSpace.height_px() \
		* lerpf(0.25, 1.0, progress)
	var color := Color(0.95, 0.8, 0.25) if crop.is_mature(soil.growth_days) \
		else Color(0.25, 0.7, 0.3)
	draw_rect(Rect2(base - Vector2(width * 0.5, height), Vector2(width, height)), color)
