class_name GameConstants
extends Object
## Compile-time tuning values and shared enums.
##
## Pure constants only — no state, never instantiated. Anything that needs to
## change at runtime belongs in [GameState] or [SettingsManager] instead.

# --- World grid ---
const TILE_SIZE: int = 16
const TILE_SIZE_V := Vector2i(TILE_SIZE, TILE_SIZE)

# --- Time ---
const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const MINUTES_PER_DAY: int = MINUTES_PER_HOUR * HOURS_PER_DAY
const DAYS_PER_SEASON: int = 28
const MINUTE_TICK: int = 10          ## In-game minutes advanced per tick.
const REAL_SECONDS_PER_TICK: float = 4.0
const DAY_START_MINUTE: int = 6 * MINUTES_PER_HOUR   ## Wake at 06:00.
const DAY_COLLAPSE_MINUTE: int = 26 * MINUTES_PER_HOUR ## Forced sleep at 02:00.

enum Season { SPRING, SUMMER, RAINY, WINTER }
const SEASON_COUNT: int = 4

const SEASON_NAMES: Array[String] = ["Spring", "Summer", "Rainy", "Winter"]
const SEASON_NAMES_TH: Array[String] = ["ฤดูใบไม้ผลิ", "ฤดูร้อน", "ฤดูฝน", "ฤดูหนาว"]

# --- Player ---
const PLAYER_WALK_SPEED: float = 70.0
const PLAYER_RUN_SPEED: float = 120.0
const PLAYER_ACCELERATION: float = 900.0
const PLAYER_FRICTION: float = 1200.0
const PLAYER_MAX_STAMINA: float = 100.0
const STAMINA_PER_TOOL_USE: float = 2.0
const STAMINA_PER_RUN_SECOND: float = 1.5

# --- Economy ---
const STARTING_MONEY: int = 500

# --- Inventory ---
const INVENTORY_SLOTS: int = 30
const HOTBAR_SLOTS: int = 5
const DEFAULT_STACK_SIZE: int = 99

# --- Physics layers (1-indexed bit positions, mirrors project.godot) ---
enum Layer { WORLD = 1, PLAYER = 2, NPC = 3, INTERACTABLE = 4, TRIGGER = 5 }

static func layer_mask(layer: Layer) -> int:
	return 1 << (int(layer) - 1)

# --- Save ---
const SAVE_VERSION: int = 1
const SAVE_DIR: String = "user://saves"
const SAVE_SLOT_COUNT: int = 3
const SETTINGS_PATH: String = "user://settings.cfg"

# --- Scenes ---
const SCENE_MAIN_MENU: String = "res://src/ui/menus/main_menu.tscn"
const SCENE_WORLD: String = "res://src/world/world.tscn"
