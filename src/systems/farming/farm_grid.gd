class_name FarmGrid
extends Node2D
## Authoritative model of every tilled tile and growing crop on one map.
##
## Model, not view. Cells live in a sparse [Dictionary] keyed by [Vector2i] so
## an empty 200x200 field costs nothing, and growth advances once per day in
## response to [signal EventBus.day_started] rather than per frame.
##
## Rendering is currently a debug [method _draw] pass. Swapping in art means
## replacing _draw with a TileMapLayer (soil) plus pooled Sprite2Ds (crops);
## nothing outside this file needs to change, which is the point of keeping
## the model separate.

const SAVE_ID := &"farm_grid"

## Tiles the player is allowed to till, as a rect in cell coordinates.
@export var arable_region := Rect2i(-16, -12, 32, 24)
@export var debug_draw: bool = true

var _cells: Dictionary[Vector2i, SoilCell] = {}


func _ready() -> void:
	add_to_group(&"farm_grid")
	add_to_group(SaveManager.GROUP_SAVEABLE)
	EventBus.day_started.connect(_on_day_started)


# --- Coordinates -------------------------------------------------------------

func world_to_cell(world_position: Vector2) -> Vector2i:
	var local := to_local(world_position)
	return Vector2i(floori(local.x / GameConstants.TILE_SIZE), floori(local.y / GameConstants.TILE_SIZE))


func cell_to_world(cell: Vector2i) -> Vector2:
	return to_global(Vector2(cell * GameConstants.TILE_SIZE) + Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE) * 0.5)


func is_arable(cell: Vector2i) -> bool:
	return arable_region.has_point(cell)


func get_cell(cell: Vector2i) -> SoilCell:
	return _cells.get(cell) as SoilCell


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
	queue_redraw()
	return true


func water(cell: Vector2i) -> bool:
	var soil := _cells.get(cell) as SoilCell
	if soil == null or not soil.tilled or soil.watered:
		return false
	soil.watered = true
	soil.dry_days = 0
	EventBus.tile_watered.emit(cell)
	queue_redraw()
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
	queue_redraw()
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
	queue_redraw()
	return true


## Removes a withered or unwanted plant, leaving the soil tilled.
func clear_plant(cell: Vector2i) -> bool:
	var soil := _cells.get(cell) as SoilCell
	if soil == null or not soil.has_crop():
		return false
	soil.clear_crop()
	queue_redraw()
	return true


# --- Daily tick --------------------------------------------------------------

func _on_day_started(_day: int, season: int, _year: int) -> void:
	for cell in _cells:
		var soil: SoilCell = _cells[cell]
		if soil.has_crop() and not soil.withered:
			_advance_crop(cell, soil, season)
		# Soil dries out overnight; the player waters again each morning.
		soil.watered = false
	queue_redraw()


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


# --- Debug rendering ---------------------------------------------------------

func _draw() -> void:
	if not debug_draw:
		return
	var size := Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)

	# Field outline, so the arable area is visible during blockout.
	draw_rect(Rect2(
		Vector2(arable_region.position * GameConstants.TILE_SIZE),
		Vector2(arable_region.size * GameConstants.TILE_SIZE)
	), Color(1, 1, 1, 0.06), false, 1.0)

	for cell in _cells:
		var soil: SoilCell = _cells[cell]
		var origin := Vector2(cell * GameConstants.TILE_SIZE)
		if soil.tilled:
			var soil_color := Color(0.35, 0.22, 0.12) if not soil.watered else Color(0.22, 0.15, 0.10)
			draw_rect(Rect2(origin, size), soil_color)
			draw_rect(Rect2(origin, size), Color(0, 0, 0, 0.25), false, 1.0)
		if not soil.has_crop():
			continue
		var crop := soil.crop()
		if crop == null:
			continue
		if soil.withered:
			draw_rect(Rect2(origin + size * 0.35, size * 0.3), Color(0.45, 0.4, 0.25))
			continue
		# Plant height grows with its stage; gold once ripe.
		var t := float(soil.growth_days) / maxf(1.0, float(crop.total_growth_days()))
		var height := size.y * lerpf(0.2, 0.8, clampf(t, 0.0, 1.0))
		var color := Color(0.95, 0.8, 0.25) if crop.is_mature(soil.growth_days) else Color(0.25, 0.7, 0.3)
		draw_rect(Rect2(origin + Vector2(size.x * 0.35, size.y - height), Vector2(size.x * 0.3, height)), color)


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
	queue_redraw()
