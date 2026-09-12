extends Node
## Orchestrates saving and loading. Owns the file format; owns no game data.
##
## Two kinds of participant, both duck-typed — a participant must implement
## get_save_id() -> StringName, save_state() -> Dictionary and
## load_state(Dictionary) -> void:
##
##   GROUP_PROVIDER  Autoloads that always exist (clock, state, inventory).
##                   Restored immediately on load.
##   GROUP_SAVEABLE  Scene nodes that come and go (farm grid, chests, NPCs).
##                   Their payload is parked until the scene is in the tree,
##                   then applied on [signal EventBus.world_ready].
##
## Format is JSON, not binary: a save you can read in a text editor is a save
## you can debug and hand-migrate. Every file carries [constant
## GameConstants.SAVE_VERSION] so old saves can be upgraded in [method _migrate].

const GROUP_PROVIDER := &"save_provider"
const GROUP_SAVEABLE := &"saveable"

## The slot the current session reads and writes. Slot 0 is the autosave /
## quick-save slot; the menu picks 1..N.
var current_slot: int = 0

## Scene-node state waiting for its scene to exist.
var _pending_scene_state: Dictionary = {}
var _loading: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(GameConstants.SAVE_DIR)
	EventBus.world_ready.connect(_on_world_ready)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save") and GameState.is_in_game():
		save_to_slot(0)
		get_viewport().set_input_as_handled()


# --- Paths -------------------------------------------------------------------

static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [GameConstants.SAVE_DIR, slot]


static func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


# --- New game ----------------------------------------------------------------

func new_game(slot: int = 0, farm_name: String = "Siam Farm", player_name: String = "Player") -> void:
	current_slot = slot
	_pending_scene_state.clear()
	GameClock.reset()
	GameState.reset()
	Inventory.reset()
	GameState.farm_name = farm_name
	GameState.player_name = player_name
	_grant_starter_kit()
	EventBus.new_game_started.emit()
	SceneLoader.change_to_map(GameConstants.STARTING_MAP, &"default")


## What the player wakes up with on day 1. Lives here because this function is
## the single definition of "a new game", and a starter kit is part of that.
func _grant_starter_kit() -> void:
	Inventory.add_item(&"hoe", 1)
	Inventory.add_item(&"watering_can", 1)
	Inventory.add_item(&"scythe", 1)
	Inventory.add_item(&"turnip_seed", 15)


# --- Save --------------------------------------------------------------------

func save_to_slot(slot: int) -> bool:
	current_slot = slot
	EventBus.save_started.emit(slot)

	var payload := {
		"header": _build_header(),
		"providers": _collect(GROUP_PROVIDER),
		"scene": _collect_scene_state(),
	}

	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write slot %d (%s)"
			% [slot, error_string(FileAccess.get_open_error())])
		EventBus.save_completed.emit(slot, false)
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	# Keep the parked scene payload in sync so a load-without-restart is
	# consistent with what we just wrote.
	_pending_scene_state = payload["scene"]

	EventBus.save_completed.emit(slot, true)
	EventBus.toast_posted.emit("บันทึกเกมแล้ว")
	return true


func _build_header() -> Dictionary:
	return {
		"version": GameConstants.SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"farm_name": GameState.farm_name,
		"player_name": GameState.player_name,
		"money": GameState.money,
		"day": GameClock.day,
		"season": GameClock.season,
		"year": GameClock.year,
		"playtime": GameState.total_playtime,
		"map": GameState.current_map,
	}


## Which map the scene-level saveables currently belong to.
func current_map_id() -> StringName:
	var world := get_tree().get_first_node_in_group(&"world") as World
	return world.map_id if world != null else &""


## Scene state, filed under the map it came from.
##
## The map prefix is added here rather than by the nodes themselves: a
## [FarmGrid] should be a FarmGrid wherever it is placed, and making each
## saveable look up which map it is in would put that knowledge in every one of
## them. Without the prefix two maps holding soil write to the same key and one
## of them is dropped.
func _collect_scene_state() -> Dictionary:
	var map_id := current_map_id()
	if map_id == &"":
		return {}
	return {String(map_id): _collect(GROUP_SAVEABLE)}


func _collect(group: StringName) -> Dictionary:
	var out := {}
	for node in get_tree().get_nodes_in_group(group):
		if not _is_participant(node):
			push_error("SaveManager: %s is in group '%s' but does not implement the save contract"
				% [node.name, group])
			continue
		# call() rather than node.get_save_id(): the contract is duck-typed, and
		# a static Node has no such method, so a direct call will not compile.
		var id := StringName(node.call(&"get_save_id"))
		if out.has(id):
			push_error("SaveManager: duplicate save id '%s' in group '%s'" % [id, group])
			continue
		out[String(id)] = node.call(&"save_state")
	return out


static func _is_participant(node: Object) -> bool:
	return node.has_method("get_save_id") \
		and node.has_method("save_state") \
		and node.has_method("load_state")


# --- Load --------------------------------------------------------------------

## Reads just the header, cheaply, for the slot-select UI. Returns {} when the
## slot is absent or unreadable.
func read_slot_header(slot: int) -> Dictionary:
	var payload := _read_slot(slot)
	return payload.get("header", {}) if not payload.is_empty() else {}


func load_from_slot(slot: int) -> bool:
	if _loading:
		return false
	var payload := _read_slot(slot)
	if payload.is_empty():
		EventBus.load_completed.emit(slot, false)
		return false

	_loading = true
	current_slot = slot
	EventBus.load_started.emit(slot)

	payload = SaveMigration.migrate(payload)

	# Autoloads first: the scene we are about to build reads their state.
	_apply(GROUP_PROVIDER, payload.get("providers", {}))
	# Scene nodes cannot exist yet; park their state for _on_world_ready.
	_pending_scene_state = payload.get("scene", {})

	SceneLoader.change_scene(GameState.current_map, GameState.spawn_point)
	_loading = false
	EventBus.load_completed.emit(slot, true)
	return true


func _read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SaveManager: slot %d is empty or unreadable" % slot)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: slot %d is not valid JSON" % slot)
		return {}
	return parsed


func _apply(group: StringName, states: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group(group):
		if not _is_participant(node):
			continue
		var id := String(node.call(&"get_save_id"))
		if not states.has(id):
			continue  # Saved before this system existed: leave it at defaults.
		node.call(&"load_state", states[id])


func _on_world_ready(_world: Node) -> void:
	if _pending_scene_state.is_empty():
		return
	var block: Dictionary = _pending_scene_state.get(String(current_map_id()), {})
	if not block.is_empty():
		_apply(GROUP_SAVEABLE, block)
	# Consumed on arrival. Task M3 makes this state outlive the transition so
	# leaving a map and coming back does not empty it.
	_pending_scene_state.clear()


func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
