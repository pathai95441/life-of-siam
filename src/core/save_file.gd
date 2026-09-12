class_name SaveFile
extends Object
## Reading and writing save slots on disk.
##
## Split from [SaveManager] so that one is about *what* a save contains and
## this is about *where it lives*. The manager was over the size limit; the
## seam was already there.
##
## Every function tolerates a missing or corrupt file by returning something
## empty rather than raising. A save slot the player has never used and one
## that has been damaged look the same to a menu, and neither should be able to
## take it down.

static func path_for(slot: int) -> String:
	return "%s/slot_%d.json" % [GameConstants.SAVE_DIR, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))


static func write(slot: int, payload: Dictionary) -> bool:
	var file := FileAccess.open(path_for(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveFile: cannot write slot %d (%s)"
			% [slot, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


## The slot's contents, or an empty dictionary when it is absent or unreadable.
static func read(slot: int) -> Dictionary:
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SaveFile: slot %d is empty or unreadable" % slot)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveFile: slot %d is not valid JSON" % slot)
		return {}
	return parsed


static func remove(slot: int) -> void:
	var path := path_for(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
