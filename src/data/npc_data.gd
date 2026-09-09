class_name NpcData
extends Resource
## Static definition of one villager.

@export var id: StringName = &""
@export var display_name: String = ""
@export var display_name_th: String = ""
@export var portrait: Texture2D
@export var sprite: Texture2D

@export_group("Dialogue")
@export var default_dialogue: DialogueData
## Dialogue keyed by flag name; the first entry whose flag is set in
## [GameState] wins over [member default_dialogue].
@export var conditional_dialogue: Dictionary = {}

@export_group("Relationship")
@export var max_hearts: int = 10
@export var liked_items: Array[StringName] = []
@export var disliked_items: Array[StringName] = []


func label() -> String:
	return display_name_th if not display_name_th.is_empty() else display_name
