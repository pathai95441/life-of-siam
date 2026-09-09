extends Node
## Non-spatial, save-persisted player and world state.
##
## Holds money, story flags and relationships — the things that must outlive
## any single scene. Deliberately does NOT hold: time (see [GameClock]),
## items (see [Inventory]), or anything a scene node can own itself.

const SAVE_ID := &"game_state"

var farm_name: String = "Siam Farm"
var player_name: String = "Player"
var money: int = GameConstants.STARTING_MONEY
var stamina: float = GameConstants.PLAYER_MAX_STAMINA
var max_stamina: float = GameConstants.PLAYER_MAX_STAMINA

## Arbitrary story/quest booleans and counters, keyed by StringName.
var flags: Dictionary = {}
## npc_id -> friendship points.
var relationships: Dictionary = {}

## Where the player re-enters the world after a scene change or load.
var current_map: String = GameConstants.SCENE_WORLD
var spawn_point: StringName = &"default"
var total_playtime: float = 0.0

var _in_game: bool = false


func _ready() -> void:
	add_to_group(SaveManager.GROUP_PROVIDER)
	EventBus.day_started.connect(_on_day_started)


func _process(delta: float) -> void:
	if _in_game:
		total_playtime += delta


func set_in_game(value: bool) -> void:
	_in_game = value


func is_in_game() -> bool:
	return _in_game


func reset() -> void:
	money = GameConstants.STARTING_MONEY
	max_stamina = GameConstants.PLAYER_MAX_STAMINA
	stamina = max_stamina
	flags.clear()
	relationships.clear()
	current_map = GameConstants.SCENE_WORLD
	spawn_point = &"default"
	total_playtime = 0.0


# --- Money -------------------------------------------------------------------

func add_money(amount: int) -> void:
	if amount == 0:
		return
	money = maxi(0, money + amount)
	EventBus.money_changed.emit(money, amount)


## Returns false and changes nothing when the player cannot afford [param cost].
func try_spend(cost: int) -> bool:
	if cost <= 0 or money < cost:
		return false
	money -= cost
	EventBus.money_changed.emit(money, -cost)
	return true


# --- Stamina -----------------------------------------------------------------

func drain_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = clampf(stamina - amount, 0.0, max_stamina)
	EventBus.stamina_changed.emit(stamina, max_stamina)
	if is_zero_approx(stamina):
		EventBus.player_collapsed.emit()


func restore_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, max_stamina)
	EventBus.stamina_changed.emit(stamina, max_stamina)


func has_stamina(amount: float) -> bool:
	return stamina >= amount


# --- Flags -------------------------------------------------------------------

func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[flag] = value
	EventBus.flag_set.emit(flag, value)


func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func has_flag(flag: StringName) -> bool:
	return bool(flags.get(flag, false))


# --- Relationships -----------------------------------------------------------

func add_relationship(npc_id: StringName, points: int) -> void:
	var total := int(relationships.get(npc_id, 0)) + points
	relationships[npc_id] = total
	EventBus.relationship_changed.emit(npc_id, total)


func relationship_points(npc_id: StringName) -> int:
	return int(relationships.get(npc_id, 0))


func hearts(npc_id: StringName) -> int:
	return relationship_points(npc_id) / 250


# --- Reactions ---------------------------------------------------------------

func _on_day_started(_day: int, _season: int, _year: int) -> void:
	restore_stamina(max_stamina)


# --- Save contract -----------------------------------------------------------

func get_save_id() -> StringName:
	return SAVE_ID


func save_state() -> Dictionary:
	return {
		"farm_name": farm_name,
		"player_name": player_name,
		"money": money,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"flags": flags.duplicate(true),
		"relationships": relationships.duplicate(true),
		"current_map": current_map,
		"spawn_point": String(spawn_point),
		"total_playtime": total_playtime,
	}


func load_state(data: Dictionary) -> void:
	farm_name = String(data.get("farm_name", farm_name))
	player_name = String(data.get("player_name", player_name))
	money = int(data.get("money", GameConstants.STARTING_MONEY))
	max_stamina = float(data.get("max_stamina", GameConstants.PLAYER_MAX_STAMINA))
	stamina = float(data.get("stamina", max_stamina))
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	relationships = (data.get("relationships", {}) as Dictionary).duplicate(true)
	current_map = String(data.get("current_map", GameConstants.SCENE_WORLD))
	spawn_point = StringName(data.get("spawn_point", "default"))
	total_playtime = float(data.get("total_playtime", 0.0))
