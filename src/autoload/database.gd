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

const _DIRS := {
	"items": "res://resources/items",
	"crops": "res://resources/crops",
	"npcs": "res://resources/npcs",
	"dialogue": "res://resources/dialogue",
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
	print("[Database] %d items, %d crops, %d npcs, %d dialogues"
		% [items.size(), crops.size(), npcs.size(), dialogues.size()])


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


func has_item(id: StringName) -> bool:
	return items.has(id)
