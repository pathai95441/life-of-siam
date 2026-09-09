class_name SoilCell
extends RefCounted
## Runtime state of one tilled tile. Serializes to a plain dictionary.

var tilled: bool = false
var watered: bool = false
## Days of growth accumulated. -1 means "no crop planted".
var growth_days: int = -1
var crop_id: StringName = &""
var withered: bool = false
## Days since the last harvest for a regrowing crop.
var days_since_harvest: int = 0
## Consecutive days ended without water.
var dry_days: int = 0


func has_crop() -> bool:
	return crop_id != &"" and growth_days >= 0


func crop() -> CropData:
	return Database.get_crop(crop_id) if crop_id != &"" else null


func is_harvestable() -> bool:
	if not has_crop() or withered:
		return false
	var c := crop()
	return c != null and c.is_mature(growth_days)


func clear_crop() -> void:
	crop_id = &""
	growth_days = -1
	withered = false
	days_since_harvest = 0
	dry_days = 0


func to_dict() -> Dictionary:
	return {
		"tilled": tilled,
		"watered": watered,
		"growth_days": growth_days,
		"crop_id": String(crop_id),
		"withered": withered,
		"days_since_harvest": days_since_harvest,
		"dry_days": dry_days,
	}


static func from_dict(d: Dictionary) -> SoilCell:
	var cell := SoilCell.new()
	cell.tilled = bool(d.get("tilled", false))
	cell.watered = bool(d.get("watered", false))
	cell.growth_days = int(d.get("growth_days", -1))
	cell.crop_id = StringName(d.get("crop_id", ""))
	cell.withered = bool(d.get("withered", false))
	cell.days_since_harvest = int(d.get("days_since_harvest", 0))
	cell.dry_days = int(d.get("dry_days", 0))
	return cell
