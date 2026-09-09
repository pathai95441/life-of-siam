class_name ItemData
extends Resource
## Static definition of one inventory item. Authored as a .tres under
## res://resources/items/ and looked up by [member id] through [Database].
##
## This resource is immutable at runtime. Per-instance state (how many, how
## worn) lives in the [InventorySlot] that references it.

enum Category { TOOL, SEED, CROP, FOOD, MATERIAL, GIFT, QUEST }
enum ToolType { NONE, HOE, WATERING_CAN, AXE, PICKAXE, SCYTHE, FISHING_ROD }

@export var id: StringName = &""
@export var display_name: String = ""
@export var display_name_th: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var category: Category = Category.MATERIAL
@export var stack_size: int = GameConstants.DEFAULT_STACK_SIZE
@export var sell_price: int = 0
@export var buy_price: int = 0

@export_group("Tool")
@export var tool_type: ToolType = ToolType.NONE
@export var stamina_cost: float = 0.0

@export_group("Seed")
## Set on SEED items to link the crop they grow into.
@export var crop: Resource


func is_stackable() -> bool:
	return stack_size > 1


func is_tool() -> bool:
	return category == Category.TOOL and tool_type != ToolType.NONE


func label() -> String:
	return display_name_th if not display_name_th.is_empty() else display_name
