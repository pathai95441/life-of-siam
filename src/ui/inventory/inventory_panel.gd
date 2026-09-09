extends CanvasLayer
## Full-bag view. Toggled with the "inventory" action; click to swap slots.

@onready var panel: Control = %Panel
@onready var grid: GridContainer = %Grid

var _drag_from: int = -1


func _ready() -> void:
	EventBus.inventory_changed.connect(_refresh)
	panel.hide()
	_build()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		_toggle()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("pause"):
		# Close the bag first; a second press then reaches the pause menu.
		_set_open(false)
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_set_open(not panel.visible)


func _set_open(open: bool) -> void:
	if open == panel.visible:
		return
	panel.visible = open
	_drag_from = -1
	if open:
		_refresh()
		EventBus.ui_window_opened.emit(&"inventory")
	else:
		EventBus.ui_window_closed.emit(&"inventory")


func _build() -> void:
	for child in grid.get_children():
		child.queue_free()
	grid.columns = GameConstants.INVENTORY_COLUMNS
	var edge := float(GameConstants.INVENTORY_CELL_SIZE)
	for i in GameConstants.INVENTORY_SLOTS:
		var button := Button.new()
		button.name = "Slot%d" % i
		button.custom_minimum_size = Vector2(edge, edge)
		button.clip_text = true
		button.pressed.connect(_on_slot_pressed.bind(i))
		grid.add_child(button)


func _refresh() -> void:
	for i in grid.get_child_count():
		var button := grid.get_child(i) as Button
		if i >= Inventory.slots.size():
			continue
		var slot := Inventory.slots[i]
		if slot.is_empty():
			button.text = ""
			button.tooltip_text = ""
		else:
			var item := slot.data()
			button.text = "%d" % slot.count if slot.count > 1 else "•"
			button.tooltip_text = "%s\n%s" % [
				item.label() if item != null else String(slot.item_id),
				item.description if item != null else "",
			]
		button.modulate = Color(1.4, 1.4, 0.8) if i == _drag_from else Color.WHITE


## Two clicks = one swap. Simple, keyboard-friendly, and it does not need a
## drag-and-drop layer to be usable.
func _on_slot_pressed(index: int) -> void:
	if _drag_from < 0:
		_drag_from = index
		_refresh()
		return
	if _drag_from == index:
		_drag_from = -1
		_refresh()
		return
	Inventory.swap(_drag_from, index)
	_drag_from = -1
