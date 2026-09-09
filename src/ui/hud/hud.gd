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

func _build_hotbar() -> void:
	for child in hotbar.get_children():
		child.queue_free()
	for i in GameConstants.HOTBAR_SLOTS:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(28, 28)
		cell.name = "Slot%d" % i

		var count := Label.new()
		count.name = "Count"
		count.set_anchors_preset(Control.PRESET_FULL_RECT)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(count)

		hotbar.add_child(cell)


func _refresh_hotbar() -> void:
	for i in hotbar.get_child_count():
		var cell := hotbar.get_child(i) as Panel
		var count := cell.get_node("Count") as Label
		if i >= Inventory.slots.size():
			count.text = ""
			continue
		var slot := Inventory.slots[i]
		if slot.is_empty():
			count.text = ""
			cell.tooltip_text = ""
		else:
			var item := slot.data()
			# No icons during blockout: show a short name and the stack count.
			var short_name := item.label().left(4) if item != null else "?"
			count.text = "%s\n%d" % [short_name, slot.count] if slot.count > 1 else short_name
			cell.tooltip_text = item.label() if item != null else ""
		cell.modulate = Color.WHITE if i != Inventory.selected_index else Color(1.4, 1.4, 0.8)


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
