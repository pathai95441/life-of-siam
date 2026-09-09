extends Node
## The player's carried items, as a fixed-size array of [InventorySlot].
##
## An autoload because the bag must survive every scene change; the world is
## streamed, the backpack is not. Slot indices 0..HOTBAR_SLOTS-1 double as the
## hotbar, which is why order is stable and slots are never compacted.

const SAVE_ID := &"inventory"

var slots: Array[InventorySlot] = []
var selected_index: int = 0


func _ready() -> void:
	add_to_group(SaveManager.GROUP_PROVIDER)
	_build_slots()


func _build_slots() -> void:
	slots.clear()
	for _i in GameConstants.INVENTORY_SLOTS:
		slots.append(InventorySlot.new())


func reset() -> void:
	_build_slots()
	selected_index = 0
	EventBus.inventory_changed.emit()


# --- Adding ------------------------------------------------------------------

## Adds up to [param amount] of [param item_id], filling partial stacks first.
## Returns the number that did NOT fit, so callers can decide whether to drop
## the remainder on the ground or refuse the pickup outright.
func add_item(item_id: StringName, amount: int = 1) -> int:
	if amount <= 0:
		return 0
	if not Database.has_item(item_id):
		push_error("Inventory: unknown item id '%s'" % item_id)
		return amount

	var remaining := amount

	# Pass 1: top up existing stacks so the bag does not fragment.
	for slot in slots:
		if remaining <= 0:
			break
		if slot.is_empty() or slot.item_id != item_id:
			continue
		var moved := mini(remaining, slot.space_left())
		slot.count += moved
		remaining -= moved

	# Pass 2: claim empty slots.
	for slot in slots:
		if remaining <= 0:
			break
		if not slot.is_empty():
			continue
		slot.item_id = item_id
		var moved := mini(remaining, slot.stack_size())
		slot.count = moved
		remaining -= moved

	var added := amount - remaining
	if added > 0:
		EventBus.item_added.emit(item_id, added)
		EventBus.inventory_changed.emit()
	if remaining > 0:
		EventBus.item_pickup_rejected.emit(item_id, remaining)
	return remaining


func can_accept(item_id: StringName, amount: int = 1) -> bool:
	var room := 0
	for slot in slots:
		if slot.accepts(item_id):
			room += slot.space_left()
			if room >= amount:
				return true
	return false


# --- Removing ----------------------------------------------------------------

func count_of(item_id: StringName) -> int:
	var total := 0
	for slot in slots:
		if not slot.is_empty() and slot.item_id == item_id:
			total += slot.count
	return total


func has_item(item_id: StringName, amount: int = 1) -> bool:
	return count_of(item_id) >= amount


## Removes [param amount] of an item. Returns false and changes nothing when
## the player does not have enough — callers never need to pre-check.
func remove_item(item_id: StringName, amount: int = 1) -> bool:
	if amount <= 0 or not has_item(item_id, amount):
		return false
	var remaining := amount
	# Drain the smallest stacks first to keep large stacks intact.
	for i in range(slots.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var slot := slots[i]
		if slot.is_empty() or slot.item_id != item_id:
			continue
		var taken := mini(remaining, slot.count)
		slot.count -= taken
		remaining -= taken
		if slot.count <= 0:
			slot.clear()
	EventBus.item_removed.emit(item_id, amount)
	EventBus.inventory_changed.emit()
	return true


func remove_at(index: int, amount: int = 1) -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot := slots[index]
	if slot.is_empty() or slot.count < amount:
		return false
	var removed_id := slot.item_id
	slot.count -= amount
	if slot.count <= 0:
		slot.clear()
	EventBus.item_removed.emit(removed_id, amount)
	EventBus.inventory_changed.emit()
	return true


func swap(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= slots.size() or b >= slots.size():
		return
	var tmp := slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	EventBus.inventory_changed.emit()


# --- Hotbar ------------------------------------------------------------------

func select(index: int) -> void:
	index = clampi(index, 0, GameConstants.HOTBAR_SLOTS - 1)
	if index == selected_index:
		return
	selected_index = index
	EventBus.hotbar_selection_changed.emit(selected_index, selected_item_id())


func selected_slot() -> InventorySlot:
	return slots[selected_index] if selected_index < slots.size() else InventorySlot.new()


func selected_item_id() -> StringName:
	return selected_slot().item_id


func selected_item() -> ItemData:
	return selected_slot().data()


# --- Save contract -----------------------------------------------------------

func get_save_id() -> StringName:
	return SAVE_ID


func save_state() -> Dictionary:
	var out: Array = []
	for slot in slots:
		out.append(slot.to_dict())
	return {"slots": out, "selected": selected_index}


func load_state(data: Dictionary) -> void:
	_build_slots()
	var raw: Array = data.get("slots", [])
	for i in mini(raw.size(), slots.size()):
		slots[i] = InventorySlot.from_dict(raw[i])
	selected_index = clampi(int(data.get("selected", 0)), 0, GameConstants.HOTBAR_SLOTS - 1)
	EventBus.inventory_changed.emit()
	EventBus.hotbar_selection_changed.emit(selected_index, selected_item_id())
