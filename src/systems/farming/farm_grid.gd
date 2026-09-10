class_name FarmGrid
extends Node2D
## Authoritative model of every tilled tile and growing crop on one map.
##
## Model, not view. Cells live in a sparse [Dictionary] keyed by [Vector2i] so
## an empty 200x200 field costs nothing, and growth advances once per day in
## response to [signal EventBus.day_started] rather than per frame.
##
## It draws nothing. [FarmDebugView] renders the blockout view by reading this
## node, and real art will replace that view with a TileMapLayer for soil plus
## pooled sprites for crops. Nothing in this file changes when that happens,
## which is the whole point of the split.

const SAVE_ID := &"farm_grid"

## Emitted whenever any cell changes, so a view can refresh without polling.
signal changed()

## Tiles the player is allowed to till, as a rect in cell coordinates.
## Must stay inside the owning level's bounds. One cell is one world unit,
## which projects to 32x16 screen pixels, so 24x18 cells covers 768x288 px
## against the blockout map's 960x720.
@export var arable_region := Rect2i(-12, -9, 24, 18)

var _cells: Dictionary[Vector2i, SoilCell] = {}


func _ready() -> void:
	add_to_group(&"farm_grid")
	add_to_group(SaveManager.GROUP_SAVEABLE)
	EventBus.day_started.connect(_on_day_started)


# --- Coordinates -------------------------------------------------------------

## Screen position -> cell, through the projection. Local first, so a farm
## placed away from the origin still resolves correctly.
func world_to_cell(world_position: Vector2) -> Vector2i:
	return WorldSpace.ground_to_cell(WorldSpace.screen_to_ground(to_local(world_position)))


## Centre of a cell, back in screen space.
func cell_to_world(cell: Vector2i) -> Vector2:
	return to_global(WorldSpace.ground_to_screen(WorldSpace.cell_centre(cell)))


func is_arable(cell: Vector2i) -> bool:
	return arable_region.has_point(cell)


func get_cell(cell: Vector2i) -> SoilCell:
	return _cells.get(cell) as SoilCell


## Every cell that has ever been worked. Read-only view for renderers; the
## dictionary itself stays private so nothing outside can mutate soil.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_cells.keys())
	return out


# --- Player actions ----------------------------------------------------------

## Breaks new soil. Returns false when the tile is outside the field or already
## worked, so the caller knows not to charge stamina.
func till(cell: Vector2i) -> bool:
	if not is_arable(cell):
		return false
	var soil := _cells.get(cell) as SoilCell
	if soil != null and soil.tilled:
		return false
	if soil == null:
		soil = SoilCell.new()
		_cells[cell] = soil
	soil.tilled = true
	EventBus.tile_tilled.emit(cell)
	changed.emit()
	return true


func water(cell: Vector2i) -> bool:
	var soil := _cells.get(cell) as SoilCell
	if soil == null or not soil.tilled or soil.watered:
		return false
	soil.watered = true
	soil.dry_days = 0
	EventBus.tile_watered.emit(cell)
	changed.emit()
	return true


func plant(cell: Vector2i, crop: CropData) -> bool:
	if crop == null:
		return false
	var soil := _cells.get(cell) as SoilCell
	if soil == null or not soil.tilled or soil.has_crop():
		return false
	if not crop.grows_in_season(GameClock.season):
		EventBus.toast_posted.emit("ปลูกในฤดูนี้ไม่ได้")
		return false
	soil.crop_id = crop.id
	soil.growth_days = 0
	soil.withered = false
	EventBus.crop_planted.emit(cell, crop.id)
	changed.emit()
	return true


## Harvests a mature crop straight into the player's bag. Returns false when
## there is nothing ripe here or the bag is full — the crop stays put either way.
func harvest(cell: Vector2i) -> bool:
	var soil := _cells.get(cell) as SoilCell
	if soil == null or not soil.is_harvestable():
		return false
	var crop := soil.crop()
	if crop == null or crop.produce == null:
		return false

	var amount := crop.roll_yield()
	if not Inventory.can_accept(crop.produce.id, amount):
		EventBus.toast_posted.emit("กระเป๋าเต็ม")
		return false

	Inventory.add_item(crop.produce.id, amount)
	EventBus.crop_harvested.emit(cell, crop.id, amount)

	if crop.regrow_days > 0:
		# Regrowing crop: rewind to the start of its final stage.
		soil.growth_days = maxi(0, crop.total_growth_days() - crop.regrow_days)
		soil.days_since_harvest = 0
	else:
		soil.clear_crop()
	changed.emit()
	return true


## Removes a withered or unwanted plant, leaving the soil tilled.
func clear_plant(cell: Vector2i) -> bool:
	var soil := _cells.get(cell) as SoilCell
	if soil == null or not soil.has_crop():
		return false
	soil.clear_crop()
	changed.emit()
	return true


# --- Daily tick --------------------------------------------------------------

func _on_day_started(_day: int, season: int, _year: int) -> void:
	for cell in _cells:
		var soil: SoilCell = _cells[cell]
		if soil.has_crop() and not soil.withered:
			_advance_crop(cell, soil, season)
		# Soil dries out overnight; the player waters again each morning.
		soil.watered = false
	changed.emit()


func _advance_crop(cell: Vector2i, soil: SoilCell, season: int) -> void:
	var crop := soil.crop()
	if crop == null:
		return

	# Out of season: the crop dies rather than pausing, so seasons matter.
	if not crop.grows_in_season(season):
		soil.withered = true
		EventBus.crop_withered.emit(cell, crop.id)
		return

	if not soil.watered:
		soil.dry_days += 1
		if soil.dry_days > crop.drought_tolerance:
			soil.withered = true
			EventBus.crop_withered.emit(cell, crop.id)
		return  # No water, no growth.

	soil.dry_days = 0
	if crop.is_mature(soil.growth_days):
		return  # Ripe and waiting; do not overgrow.

	var previous_stage := crop.stage_for_days(soil.growth_days)
	soil.growth_days += 1
	var stage := crop.stage_for_days(soil.growth_days)
	if stage != previous_stage:
		EventBus.crop_grown.emit(cell, stage)


# --- Save contract -----------------------------------------------------------

func get_save_id() -> StringName:
	return SAVE_ID


func save_state() -> Dictionary:
	var out := {}
	for cell in _cells:
		# Vector2i keys are not JSON-representable; "x,y" round-trips cleanly.
		out["%d,%d" % [cell.x, cell.y]] = (_cells[cell] as SoilCell).to_dict()
	return {"cells": out}


func load_state(data: Dictionary) -> void:
	_cells.clear()
	var raw: Dictionary = data.get("cells", {})
	for key in raw:
		var parts := String(key).split(",")
		if parts.size() != 2:
			push_warning("FarmGrid: skipping malformed cell key '%s'" % key)
			continue
		_cells[Vector2i(int(parts[0]), int(parts[1]))] = SoilCell.from_dict(raw[key])
	changed.emit()
