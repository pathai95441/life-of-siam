class_name ShippingBin
extends Interactable
## Holds produce overnight and pays for it the next morning.
##
## Deliberately the only way to turn goods into money: the shop buys, the bin
## sells, and neither does the other's job. One place to sell means one place
## where money can be created, which is the only place that needs guarding.
##
## Saveable from the start rather than later. A player who ships a full day's
## harvest and then saves before sleeping must not lose it, and retrofitting
## persistence onto something holding player property is how that bug ships.

const SAVE_ID := &"shipping_bin"

## item_id -> how many are waiting to be sold. Plain counts, not slots: the bin
## has no capacity limit and no ordering, so a slot model would add structure
## nothing uses.
var _contents: Dictionary[StringName, int] = {}


func _ready() -> void:
	super()
	prompt = "ฝากของ"
	prompt_en = "Ship"
	add_to_group(SaveManager.GROUP_SAVEABLE)
	EventBus.day_started.connect(_on_day_started)


func interact(actor: Node) -> void:
	super(actor)
	deposit_held_stack()


# --- Depositing --------------------------------------------------------------

## Moves the whole selected hotbar stack into the bin.
## Returns how many were accepted, zero when the deposit was refused.
func deposit_held_stack() -> int:
	var slot := Inventory.selected_slot()
	if slot.is_empty():
		_refuse(&"", "ไม่มีอะไรจะฝาก")
		return 0

	var item := slot.data()
	if item == null:
		_refuse(slot.item_id, "ของชิ้นนี้ไม่รู้จัก")
		return 0
	# Tools and anything else worth nothing would be destroyed for no money.
	if item.sell_price <= 0:
		_refuse(item.id, "%s ขายไม่ได้" % item.label())
		return 0

	var amount := slot.count
	if not Inventory.remove_at(Inventory.selected_index, amount):
		_refuse(item.id, "หยิบของออกจากกระเป๋าไม่ได้")
		return 0

	_contents[item.id] = _contents.get(item.id, 0) + amount
	EventBus.toast_posted.emit("ฝาก %s x%d" % [item.label(), amount])
	return amount


func _refuse(item_id: StringName, reason: String) -> void:
	EventBus.deposit_refused.emit(item_id, reason)
	EventBus.toast_posted.emit(reason)


# --- Queries -----------------------------------------------------------------

func is_empty() -> bool:
	return _contents.is_empty()


func count_of(item_id: StringName) -> int:
	return int(_contents.get(item_id, 0))


## What the bin would pay out right now. Used by tests to assert that value is
## conserved across a shipment rather than created or lost.
func pending_value() -> int:
	var total := 0
	for item_id in _contents:
		var item := Database.get_item(item_id)
		if item == null:
			push_error("ShippingBin: holding unknown item '%s'" % item_id)
			continue
		total += item.sell_price * int(_contents[item_id])
	return total


# --- Payout ------------------------------------------------------------------

## Sells everything and empties the bin, as one step. Clearing and paying must
## not be separable: a second day_started before the clear would pay twice.
func _on_day_started(_day: int, _season: int, _year: int) -> void:
	if _contents.is_empty():
		return

	var total := pending_value()
	var item_count := 0
	for item_id in _contents:
		item_count += int(_contents[item_id])
	_contents.clear()

	GameState.add_money(total)
	# Reports the fact and stops there. How a day's earnings are shown is the
	# UI's decision, and duplicating it here would put the same news on screen
	# twice the moment anything richer than a toast exists.
	EventBus.items_shipped.emit(total, item_count)


# --- Save contract -----------------------------------------------------------

func get_save_id() -> StringName:
	return SAVE_ID


func save_state() -> Dictionary:
	var out := {}
	for item_id in _contents:
		out[String(item_id)] = int(_contents[item_id])
	return {"contents": out}


func load_state(data: Dictionary) -> void:
	_contents.clear()
	var raw: Dictionary = data.get("contents", {})
	for key in raw:
		_contents[StringName(key)] = int(raw[key])
