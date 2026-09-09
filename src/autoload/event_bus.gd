extends Node
## Global signal hub. The ONLY approved channel for cross-system communication.
##
## Rules of the road:
##   - Systems that do not know about each other talk through here.
##   - A node and its own children use direct signals, never the bus.
##   - Emitters never assume a listener exists; listeners never assume order.
##   - Every signal declared here is documented and typed. If you cannot name
##     the payload, the signal is not ready to exist.
##
## This node owns no state, so it is deliberately not saveable.

# --- Time ---------------------------------------------------------------
signal minute_passed(minute_of_day: int)
signal hour_changed(hour: int)
signal day_started(day: int, season: int, year: int)
signal day_ended(day: int, season: int, year: int)
signal season_changed(season: int, year: int)
signal clock_running_changed(running: bool)

# --- Player -------------------------------------------------------------
signal player_spawned(player: Node2D)
signal player_despawned()
signal stamina_changed(current: float, maximum: float)
signal player_collapsed()
signal player_slept()

# --- Economy ------------------------------------------------------------
signal money_changed(total: int, delta: int)

# --- Inventory ----------------------------------------------------------
signal inventory_changed()
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)
signal item_pickup_rejected(item_id: StringName, amount: int)
signal hotbar_selection_changed(index: int, item_id: StringName)

# --- Interaction --------------------------------------------------------
signal interactable_focused(interactable: Node)
signal interactable_unfocused(interactable: Node)
signal interaction_performed(interactable: Node, actor: Node)

# --- Dialogue -----------------------------------------------------------
signal dialogue_started(npc_id: StringName)
signal dialogue_line_shown(speaker: String, text: String, portrait: Texture2D)
signal dialogue_advance_requested()
signal dialogue_finished(npc_id: StringName)

# --- Farming ------------------------------------------------------------
signal tile_tilled(cell: Vector2i)
signal tile_watered(cell: Vector2i)
signal crop_planted(cell: Vector2i, crop_id: StringName)
signal crop_grown(cell: Vector2i, stage: int)
signal crop_harvested(cell: Vector2i, crop_id: StringName, amount: int)
signal crop_withered(cell: Vector2i, crop_id: StringName)

# --- Relationships ------------------------------------------------------
signal relationship_changed(npc_id: StringName, points: int)
signal flag_set(flag: StringName, value: Variant)

# --- Save / load --------------------------------------------------------
signal save_started(slot: int)
signal save_completed(slot: int, ok: bool)
signal load_started(slot: int)
signal load_completed(slot: int, ok: bool)
signal new_game_started()

# --- Scene flow ---------------------------------------------------------
signal scene_change_started(path: String)
signal scene_change_finished(path: String)
signal world_ready(world: Node)

# --- UI -----------------------------------------------------------------
signal ui_window_opened(id: StringName)
signal ui_window_closed(id: StringName)
signal game_paused(paused: bool)
signal toast_posted(text: String)
signal settings_applied()
