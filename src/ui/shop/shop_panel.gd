class_name ShopPanel
extends CanvasLayer
## View for [Shop]. Lists what is for sale and asks the shop to sell it.
##
## Holds no rule about money. It never compares a price to a balance itself --
## it asks [method Shop.can_buy] and [method Shop.buy] and renders the answer.
## Every refusal path was tested without this file existing, and that stays
## true: if a rule ever appears here, it is a rule that cannot be tested
## without rendering.

@onready var panel: Control = %Panel
@onready var title_label: Label = %TitleLabel
@onready var money_label: Label = %MoneyLabel
@onready var rows_box: VBoxContainer = %Rows

var _shop: Shop = null
## item_id -> the button that buys it, so refreshing affordability is a lookup
## rather than a walk of the tree.
var _buy_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	EventBus.shop_opened.connect(_on_shop_opened)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.inventory_changed.connect(_refresh_affordability)
	panel.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return panel.visible


func close() -> void:
	if not is_open():
		return
	panel.hide()
	_shop = null
	EventBus.shop_closed.emit()
	EventBus.ui_window_closed.emit(&"shop")


# --- Opening -----------------------------------------------------------------

func _on_shop_opened(shop: Node) -> void:
	_shop = shop as Shop
	if _shop == null:
		push_error("ShopPanel: shop_opened carried %s, not a Shop" % shop)
		return
	title_label.text = _shop.shop_data.display_name_th
	_build_rows()
	_on_money_changed(GameState.money, 0)
	panel.show()
	EventBus.ui_window_opened.emit(&"shop")


func _build_rows() -> void:
	for child in rows_box.get_children():
		child.queue_free()
	_buy_buttons.clear()
	for item_id in _shop.stock():
		rows_box.add_child(_make_row(item_id))
	_refresh_affordability()


func _make_row(item_id: StringName) -> HBoxContainer:
	var item := Database.get_item(item_id)
	var row := HBoxContainer.new()
	row.name = "Row_%s" % item_id

	var name_label := Label.new()
	name_label.text = item.label() if item != null else String(item_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "%d ฿" % _shop.price_of(item_id)
	row.add_child(price_label)

	var button := Button.new()
	button.name = "Buy"
	button.text = "ซื้อ"
	button.pressed.connect(_on_buy_pressed.bind(item_id))
	row.add_child(button)
	_buy_buttons[item_id] = button
	return row


# --- Reacting ----------------------------------------------------------------

func _on_buy_pressed(item_id: StringName) -> void:
	if _shop == null:
		return
	_shop.buy(item_id, 1)
	_refresh_affordability()


func _on_money_changed(total: int, _delta: int) -> void:
	money_label.text = "%d ฿" % total
	_refresh_affordability()


## Greys out what cannot be bought right now, for whatever reason the shop
## gives -- no money, no room, anything added later.
func _refresh_affordability() -> void:
	if _shop == null:
		return
	for item_id in _buy_buttons:
		(_buy_buttons[item_id] as Button).disabled = not _shop.can_buy(item_id, 1)


# --- Test surface ------------------------------------------------------------

func row_count() -> int:
	return rows_box.get_child_count()


func buy_button_for(item_id: StringName) -> Button:
	return _buy_buttons.get(item_id) as Button
