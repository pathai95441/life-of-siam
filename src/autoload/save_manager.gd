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
## Things that move between maps and therefore belong to no map -- the player,
## and one day anything following them. Restored when a save is loaded, and
## deliberately not when a door is walked through: arriving somewhere should put
## you at the door, not where you stood last time you were here.
const GROUP_TRAVELLER := &"traveller"

## The slot the current session reads and writes. Slot 0 is the autosave /
## quick-save slot; the menu picks 1..N.
var current_slot: int = 0

## Every map's scene state, for the whole session -- not just the map on
## screen. Captured when a map is left and handed back when it is re-entered,
## so walking out of the farm and back does not empty it.
var _scene_state: Dictionary = {}

## Traveller state waiting for a scene. Applied once, on the first map after a
## load, then dropped so later transitions use spawn points instead.
var _pending_traveller: Dictionary = {}

var _loading: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(GameConstants.SAVE_DIR)
	EventBus.world_ready.connect(_on_world_ready)
	# The old map is still in the tree when this fires, which is the only
	# moment its contents can still be read.
	EventBus.scene_change_started.connect(_on_scene_change_started)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save") and GameState.is_in_game():
		save_to_slot(0)
		get_viewport().set_input_as_handled()


# --- Slots -------------------------------------------------------------------
# Thin pass-throughs to SaveFile. Menus and tests speak to the manager; where
# the bytes live is its business, not theirs.

static func slot_path(slot: int) -> String:
	return SaveFile.path_for(slot)


static func slot_exists(slot: int) -> bool:
	return SaveFile.exists(slot)


# --- New game ----------------------------------------------------------------

func new_game(slot: int = 0, farm_name: String = "Siam Farm", player_name: String = "Player") -> void:
	current_slot = slot
	_scene_state.clear()
	_pending_traveller.clear()
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

	# The map on screen has unsaved changes in it; fold them in before writing.
	_capture_current_map()
	var payload := {
		"header": _build_header(),
		"providers": _collect(GROUP_PROVIDER),
		"scene": _scene_state.duplicate(true),
		"traveller": _collect(GROUP_TRAVELLER),
	}

	if not SaveFile.write(slot, payload):
		EventBus.save_completed.emit(slot, false)
		return false

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


## Files the map currently on screen into [member _scene_state].
##
## The map prefix is added here rather than by the nodes themselves: a
## [FarmGrid] should be a FarmGrid wherever it is placed, and making each
## saveable look up which map it is in would put that knowledge in every one of
## them. Without the prefix two maps holding soil write to the same key and one
## of them is dropped.
func _capture_current_map() -> void:
	# While restoring, the map on screen is the one being replaced. Capturing it
	# would overwrite the freshly loaded state for that very map with whatever
	# the abandoned session had in it.
	if _loading:
		return
	var map_id := current_map_id()
	if map_id == &"":
		return
	_scene_state[String(map_id)] = _collect(GROUP_SAVEABLE)


func _on_scene_change_started(_path: String) -> void:
	_capture_current_map()


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
	var payload := SaveFile.read(slot)
	return payload.get("header", {}) if not payload.is_empty() else {}


func load_from_slot(slot: int) -> bool:
	if _loading:
		return false
	var payload := SaveFile.read(slot)
	if payload.is_empty():
		EventBus.load_completed.emit(slot, false)
		return false

	_loading = true
	current_slot = slot
	EventBus.load_started.emit(slot)

	payload = SaveMigration.migrate(payload)

	# Autoloads first: the scene we are about to build reads their state.
	_apply(GROUP_PROVIDER, payload.get("providers", {}))
	# Scene nodes cannot exist yet; hold everything until each map is built.
	_scene_state = (payload.get("scene", {}) as Dictionary).duplicate(true)
	_pending_traveller = (payload.get("traveller", {}) as Dictionary).duplicate(true)

	SceneLoader.change_scene(GameState.current_map, GameState.spawn_point)
	_loading = false
	EventBus.load_completed.emit(slot, true)
	return true


func _apply(group: StringName, states: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group(group):
		if not _is_participant(node):
			continue
		var id := String(node.call(&"get_save_id"))
		if not states.has(id):
			continue  # Saved before this system existed: leave it at defaults.
		node.call(&"load_state", states[id])


func _on_world_ready(_world: Node) -> void:
	var block: Dictionary = _scene_state.get(String(current_map_id()), {})
	if not block.is_empty():
		_apply(GROUP_SAVEABLE, block)
		# Kept, not consumed: this map will be entered again.

	if not _pending_traveller.is_empty():
		_apply(GROUP_TRAVELLER, _pending_traveller)
		# Dropped now. Only the first map after a load restores an exact
		# position; every door after it places the player at its spawn.
		_pending_traveller.clear()


func delete_slot(slot: int) -> void:
	SaveFile.remove(slot)
