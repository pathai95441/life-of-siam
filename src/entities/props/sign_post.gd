class_name SignPost
extends Interactable
## Reads out a fixed piece of text. The cheapest way to put words in the world
## without authoring an NPC.

@export var dialogue: DialogueData
@export_multiline var inline_text: String = ""
@export var speaker: String = "ป้าย"


func _ready() -> void:
	super()
	prompt = "อ่าน"
	prompt_en = "Read"


func interact(actor: Node) -> void:
	super(actor)
	if dialogue != null:
		DialogueSystem.start(dialogue)
		return
	if inline_text.is_empty():
		return
	# Build a throwaway DialogueData so short signs need no .tres file.
	var line := DialogueLine.new()
	line.speaker = speaker
	line.text = inline_text
	var lines: Array[DialogueLine] = [line]
	var data := DialogueData.new()
	data.id = StringName("sign_%d" % get_instance_id())
	data.lines = lines
	DialogueSystem.start(data)
