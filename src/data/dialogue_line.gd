class_name DialogueLine
extends Resource
## A single spoken line inside a [DialogueData] sequence.

@export var speaker: String = ""
@export_multiline var text: String = ""
## Optional portrait override; falls back to the speaking NPC's portrait.
@export var portrait: Texture2D
## Played once when the line is shown.
@export var voice: AudioStream
