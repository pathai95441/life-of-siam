extends CanvasLayer
## View for [DialogueSystem]. Shows one line and asks for the next.
##
## Holds no conversation state of its own — that is what makes it replaceable.
## It only knows how to draw a line and how to say "advance".

@onready var panel: Control = %Panel
@onready var speaker_label: Label = %SpeakerLabel
@onready var text_label: RichTextLabel = %TextLabel
@onready var portrait: TextureRect = %Portrait


func _ready() -> void:
	EventBus.dialogue_started.connect(_on_started)
	EventBus.dialogue_line_shown.connect(_on_line_shown)
	EventBus.dialogue_finished.connect(_on_finished)
	panel.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not DialogueSystem.is_active():
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("use_tool"):
		DialogueSystem.advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		DialogueSystem.cancel()
		get_viewport().set_input_as_handled()


func _on_started(_npc_id: StringName) -> void:
	panel.show()
	EventBus.ui_window_opened.emit(&"dialogue")


func _on_line_shown(speaker: String, text: String, portrait_texture: Texture2D) -> void:
	speaker_label.text = speaker
	speaker_label.visible = not speaker.is_empty()
	text_label.text = text
	portrait.texture = portrait_texture
	portrait.visible = portrait_texture != null


func _on_finished(_npc_id: StringName) -> void:
	panel.hide()
	EventBus.ui_window_closed.emit(&"dialogue")
