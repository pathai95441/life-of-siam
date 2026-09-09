extends CanvasLayer
## Always-on gameplay readout: clock, date, money, stamina, hotbar, prompts.
##
## Strictly a view. It reads from the autoloads and reacts to [EventBus]; it
## never writes game state. Anything here that starts *deciding* things has
## escaped into the wrong layer.

@onready var clock_label: Label = %ClockLabel
@onready var date_label: Label = %DateLabel
@onready var money_label: Label = %MoneyLabel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var prompt_label: Label = %PromptLabel
@onready var toast_label: Label = %ToastLabel
@onready var hotbar: HBoxContainer = %Hotbar
@onready var selected_label: Label = %SelectedItemLabel

var _toast_timer: float = 0.0


func _ready() -> void:
	EventBus.minute_passed.connect(_on_minute_passed)
	EventBus.day_started.connect(_on_day_started)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.stamina_changed.connect(_on_stamina_changed)
	EventBus.interactable_focused.connect(_on_interactable_focused)
	EventBus.interactable_unfocused.connect(_on_interactable_unfocused)
	EventBus.inventory_changed.connect(_refresh_hotbar)
	EventBus.hotbar_selection_changed.connect(_on_hotbar_selection_changed)
	EventBus.toast_posted.connect(_on_toast_posted)

	_build_hotbar()
	_refresh_all()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_label.hide()


func _refresh_all() -> void:
	_on_minute_passed(GameClock.minute_of_day)
	_on_day_started(GameClock.day, GameClock.season, GameClock.year)
	_on_money_changed(GameState.money, 0)
	_on_stamina_changed(GameState.stamina, GameState.max_stamina)
	_refresh_hotbar()
	prompt_label.hide()
	toast_label.hide()


# --- Hotbar ------------------------------------------------------------------

## Cells show the hotkey digit and the stack count -- never an abbreviated
## item name. Truncating a Thai name splits grapheme clusters and orphans its
## vowel and tone marks, so the full name goes to [member selected_label] and
## the tooltip instead. When item icons exist, the icon replaces the digit.
func _build_hotbar() -> void:
	for child in hotbar.get_children():
		child.queue_free()
	var edge := float(GameConstants.HOTBAR_CELL_SIZE)
	for i in GameConstants.HOTBAR_SLOTS:
		var cell := Panel.new()
		cell.name = "Slot%d" % i
		cell.custom_minimum_size = Vector2(edge, edge)
		cell.clip_contents = true
		cell.add_child(_make_cell_label("Key", str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP))
		cell.add_child(_make_cell_label("Count", "",
			HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_BOTTOM))
		hotbar.add_child(cell)


func _make_cell_label(node_name: String, text: String,
		h_align: HorizontalAlignment, v_align: VerticalAlignment) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = h_align
	label.vertical_alignment = v_align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh_hotbar() -> void:
	for i in hotbar.get_child_count():
		var cell := hotbar.get_child(i) as Panel
		var count := cell.get_node("Count") as Label
		var slot := Inventory.slots[i] if i < Inventory.slots.size() else InventorySlot.new()
		var item := slot.data()
		count.text = str(slot.count) if slot.count > 1 else ""
		cell.tooltip_text = item.label() if item != null else ""
		cell.modulate = Color(1.4, 1.4, 0.8) if i == Inventory.selected_index else Color.WHITE
	_refresh_selected_label()


func _refresh_selected_label() -> void:
	var item := Inventory.selected_item()
	selected_label.text = item.label() if item != null else ""
	selected_label.visible = item != null


func _on_hotbar_selection_changed(_index: int, _item_id: StringName) -> void:
	_refresh_hotbar()


# --- Reactions ---------------------------------------------------------------

func _on_minute_passed(_minute_of_day: int) -> void:
	clock_label.text = GameClock.time_string()


func _on_day_started(_day: int, _season: int, _year: int) -> void:
	date_label.text = GameClock.date_string_th()
	clock_label.text = GameClock.time_string()


func _on_money_changed(total: int, _delta: int) -> void:
	money_label.text = "%d ฿" % total


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current


func _on_interactable_focused(interactable: Node) -> void:
	var target := interactable as Interactable
	if target == null:
		return
	prompt_label.text = "[E] %s" % target.label()
	prompt_label.show()


func _on_interactable_unfocused(_interactable: Node) -> void:
	prompt_label.hide()


func _on_toast_posted(text: String) -> void:
	toast_label.text = text
	toast_label.show()
	_toast_timer = 2.5
