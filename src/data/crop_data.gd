class_name CropData
extends Resource
## Growth definition for one plantable crop.
##
## [member stage_days] holds the number of in-game days each visual stage
## lasts; the crop is harvestable once its accumulated growth reaches the sum.

@export var id: StringName = &""
@export var display_name: String = ""
@export var display_name_th: String = ""

## Days spent in each growth stage, in order. Size defines the stage count.
@export var stage_days: Array[int] = [2, 2, 2]
## Sprite per stage; index must line up with [member stage_days].
@export var stage_textures: Array[Texture2D] = []

@export var produce: ItemData
@export var produce_min: int = 1
@export var produce_max: int = 1

@export_group("Season")
@export_flags("Spring", "Summer", "Rainy", "Winter") var seasons: int = 0b1111

@export_group("Regrowth")
## 0 = single harvest. Otherwise days to regrow after each harvest.
@export var regrow_days: int = 0

@export_group("Water")
## Days the crop survives unwatered before it withers.
@export var drought_tolerance: int = 2


func total_growth_days() -> int:
	var total := 0
	for d in stage_days:
		total += d
	return total


func stage_count() -> int:
	return stage_days.size()


## Returns the 0-based stage index for a crop that has grown [param days].
func stage_for_days(days: int) -> int:
	var elapsed := 0
	for i in stage_days.size():
		elapsed += stage_days[i]
		if days < elapsed:
			return i
	return stage_days.size() - 1


func is_mature(days: int) -> bool:
	return days >= total_growth_days()


func grows_in_season(season: int) -> bool:
	return (seasons & (1 << season)) != 0


func roll_yield() -> int:
	return randi_range(produce_min, maxi(produce_min, produce_max))
