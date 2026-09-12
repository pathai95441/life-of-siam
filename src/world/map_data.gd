class_name MapData
extends Resource
## Identity of one playable map.
##
## Exists so that maps can be referred to by a stable id rather than a file
## path. Save data keyed by "res://src/world/world.tscn" breaks the day someone
## moves the file; keyed by &"farm" it does not.

@export var id: StringName = &""
@export var display_name_th: String = ""
@export_file("*.tscn") var scene_path: String = ""


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	if scene_path.is_empty():
		errors.append("scene_path is empty")
	elif not ResourceLoader.exists(scene_path):
		errors.append("scene_path '%s' does not exist" % scene_path)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
