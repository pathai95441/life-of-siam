class_name DialogueData
extends Resource
## An ordered sequence of lines, run by [DialogueSystem].
##
## Branching is intentionally out of scope for v1. When it lands, add a
## `choices` array to [DialogueLine] and a jump table here — the runner already
## walks by index, so it can honour jumps without touching callers.

@export var id: StringName = &""
@export var lines: Array[DialogueLine] = []
## Emitted through [signal EventBus.dialogue_finished] consumers; lets a
## conversation raise a flag once seen (e.g. "met_somchai").
@export var sets_flag: StringName = &""
## Only playable once per save when true.
@export var one_shot: bool = false


func is_empty() -> bool:
	return lines.is_empty()
