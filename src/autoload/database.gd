extends Node
## Read-only registry of every authored [Resource] definition, keyed by id.
##
## Scans res://resources/ once at boot so gameplay code never touches file
## paths. Exported builds keep .tres files, so directory scanning works there
## too — but the scan is O(files), which is why it happens exactly once.

var items: Dictionary[StringName, ItemData] = {}
var crops: Dictionary[StringName, CropData] = {}
var npcs: Dictionary[StringName, NpcData] = {}
var dialogues: Dictionary[StringName, DialogueData] = {}
var world_objects: Dictionary[StringName, WorldObjectData] = {}
var shops: Dictionary[StringName, ShopData] = {}

const _DIRS := {
	"items": "res://resources/items",
	"crops": "res://resources/crops",
	"npcs": "res://resources/npcs",
	"dialogue": "res://resources/dialogue",
	"world_objects": "res://resources/world_objects",
	"shops": "res://resources/shops",
}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	for res in _scan(_DIRS["items"]):
		_register(items, res)
	for res in _scan(_DIRS["crops"]):
		_register(crops, res)
	for res in _scan(_DIRS["npcs"]):
		_register(npcs, res)
	for res in _scan(_DIRS["dialogue"]):
		_register(dialogues, res)
	for res in _scan(_DIRS["world_objects"]):
		_register(world_objects, res)
	# Shops last: their validation reads the item registry.
	for res in _scan(_DIRS["shops"]):
		_register(shops, res)
	_validate_world_objects()
	_validate_shops()
	print("[Database] %d items, %d crops, %d npcs, %d dialogues, %d world objects, %d shops"
		% [items.size(), crops.size(), npcs.size(), dialogues.size(),
			world_objects.size(), shops.size()])


## A shop stocking something unbuyable would show an item nobody can purchase,
## which is far easier to catch here than in a UI.
func _validate_shops() -> void:
	for id in shops:
		for error in (shops[id] as ShopData).validation_errors():
			push_error("Database: shop '%s' is invalid: %s" % [id, error])


## Physical definitions are load-bearing for collision and interaction, so a
## malformed one is reported at boot rather than becoming a mystery later.
func _validate_world_objects() -> void:
	for id in world_objects:
		var errors := (world_objects[id] as WorldObjectData).validation_errors()
		for error in errors:
			push_error("Database: world object '%s' is invalid: %s" % [id, error])


func _scan(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Database: missing directory %s" % dir_path)
		return out
	for file in dir.get_files():
		# Exported projects rename .tres to .remap; strip either suffix.
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var res := load(dir_path.path_join(file_name))
		if res == null:
			push_error("Database: failed to load %s" % file_name)
			continue
		out.append(res)
	return out


func _register(target: Dictionary, res: Resource) -> void:
	var raw_id: Variant = res.get("id")
	if raw_id == null or StringName(raw_id) == &"":
		push_error("Database: %s has an empty id and was skipped" % res.resource_path)
		return
	var id := StringName(raw_id)
	if target.has(id):
		push_error("Database: duplicate id '%s' (%s)" % [id, res.resource_path])
		return
	target[id] = res


func get_item(id: StringName) -> ItemData:
	return items.get(id) as ItemData


func get_crop(id: StringName) -> CropData:
	return crops.get(id) as CropData


func get_npc(id: StringName) -> NpcData:
	return npcs.get(id) as NpcData


func get_dialogue(id: StringName) -> DialogueData:
	return dialogues.get(id) as DialogueData


func get_world_object(id: StringName) -> WorldObjectData:
	return world_objects.get(id) as WorldObjectData


func get_shop(id: StringName) -> ShopData:
	return shops.get(id) as ShopData


func has_item(id: StringName) -> bool:
	return items.has(id)
