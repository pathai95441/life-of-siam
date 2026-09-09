class_name ToolHandler
extends Node
## Turns "the player swung the held item at the tile in front" into a concrete
## effect on the world.
##
## The dispatch table lives here rather than in [FarmGrid] or [Player] so that
## adding a tool touches exactly one file, and so the grid stays a pure model
## that does not know what a hoe is.

## Untyped on purpose: [Player] already type-references [ToolHandler], and
## naming Player back here would make the two scripts a cyclic dependency,
## which GDScript resolves unreliably. Calls below are dynamic.
var _player: Variant = null


func _ready() -> void:
	_player = owner


## Runs the held item against the tile in front of the player.
## Returns true when something actually happened — the caller uses that to
## decide whether to play the swing animation and charge stamina.
func use_selected() -> bool:
	var item := Inventory.selected_item()
	# Explicit types on the way out of the untyped _player reference, so the
	# rest of this file is statically checked again.
	var grid: FarmGrid = _player.farm_grid()
	if grid == null:
		return false
	var cell: Vector2i = _player.target_cell()

	# An empty hand harvests: the most common action should need no tool.
	if item == null:
		return grid.harvest(cell)

	match item.category:
		ItemData.Category.TOOL:
			return _use_tool(grid, cell, item)
		ItemData.Category.SEED:
			return _plant_seed(grid, cell, item)
		_:
			return grid.harvest(cell)


func _use_tool(grid: FarmGrid, cell: Vector2i, item: ItemData) -> bool:
	if not GameState.has_stamina(item.stamina_cost):
		EventBus.toast_posted.emit("หมดแรงแล้ว")
		return false

	var acted := false
	match item.tool_type:
		ItemData.ToolType.HOE:
			acted = grid.till(cell)
		ItemData.ToolType.WATERING_CAN:
			acted = grid.water(cell)
		ItemData.ToolType.SCYTHE:
			acted = grid.harvest(cell) or grid.clear_plant(cell)
		_:
			acted = false

	if acted:
		GameState.drain_stamina(maxf(item.stamina_cost, GameConstants.STAMINA_PER_TOOL_USE))
	return acted


func _plant_seed(grid: FarmGrid, cell: Vector2i, item: ItemData) -> bool:
	var crop := item.crop as CropData
	if crop == null:
		push_warning("ToolHandler: seed '%s' has no crop assigned" % item.id)
		return false
	if not grid.plant(cell, crop):
		return false
	# Consume exactly one seed, and only after the plant succeeded.
	Inventory.remove_at(Inventory.selected_index, 1)
	return true
