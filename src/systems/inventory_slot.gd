class_name InventorySlot
extends RefCounted
## One inventory cell: a reference to an [ItemData] plus how many are stacked.
##
## Intentionally not a [Resource] — slots are runtime-only and serialize to
## plain dictionaries, so they must never be confused with authored data.

var item_id: StringName = &""
var count: int = 0


func _init(p_item_id: StringName = &"", p_count: int = 0) -> void:
	item_id = p_item_id
	count = p_count


func is_empty() -> bool:
	return item_id == &"" or count <= 0


func clear() -> void:
	item_id = &""
	count = 0


func data() -> ItemData:
	return Database.get_item(item_id) if not is_empty() else null


func stack_size() -> int:
	var d := data()
	return d.stack_size if d != null else GameConstants.DEFAULT_STACK_SIZE


func space_left() -> int:
	if is_empty():
		return stack_size()
	return maxi(0, stack_size() - count)


func accepts(p_item_id: StringName) -> bool:
	return is_empty() or (item_id == p_item_id and space_left() > 0)


func to_dict() -> Dictionary:
	return {"id": String(item_id), "count": count}


static func from_dict(d: Dictionary) -> InventorySlot:
	return InventorySlot.new(StringName(d.get("id", "")), int(d.get("count", 0)))
