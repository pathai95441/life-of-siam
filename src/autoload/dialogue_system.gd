extends Node
## Runs one conversation at a time and broadcasts it through [EventBus].
##
## Owns conversation *state* only. The visual dialogue box is a pure view: it
## listens for [signal EventBus.dialogue_line_shown] and calls [method advance].
## That split lets cutscenes, signs and NPCs share one runner, and lets the UI
## be replaced without touching game logic.

var _current: DialogueData = null
var _npc_id: StringName = &""
var _index: int = -1


func is_active() -> bool:
	return _current != null


## Begins [param dialogue]. Returns false when it is already running, empty, or
## a one-shot that this save has already seen.
func start(dialogue: DialogueData, npc_id: StringName = &"") -> bool:
	if is_active() or dialogue == null or dialogue.is_empty():
		return false
	if dialogue.one_shot and GameState.has_flag(_seen_flag(dialogue)):
		return false

	_current = dialogue
	_npc_id = npc_id
	_index = -1
	EventBus.dialogue_started.emit(_npc_id)
	advance()
	return true


func start_by_id(dialogue_id: StringName, npc_id: StringName = &"") -> bool:
	return start(Database.get_dialogue(dialogue_id), npc_id)


## Shows the next line, or finishes the conversation when there are none left.
func advance() -> void:
	if not is_active():
		return
	_index += 1
	if _index >= _current.lines.size():
		_finish()
		return
	var line: DialogueLine = _current.lines[_index]
	var portrait := line.portrait
	if portrait == null and _npc_id != &"":
		var npc := Database.get_npc(_npc_id)
		if npc != null:
			portrait = npc.portrait
	EventBus.dialogue_line_shown.emit(line.speaker, line.text, portrait)
	if line.voice != null:
		AudioManager.play_sfx_stream(line.voice)


func current_line() -> DialogueLine:
	if not is_active() or _index < 0 or _index >= _current.lines.size():
		return null
	return _current.lines[_index]


## Ends the conversation early (menu opened, scene change, player walked away).
func cancel() -> void:
	if is_active():
		_finish()


func _finish() -> void:
	var finished := _current
	var npc := _npc_id
	_current = null
	_npc_id = &""
	_index = -1

	if finished != null:
		if finished.one_shot:
			GameState.set_flag(_seen_flag(finished))
		if finished.sets_flag != &"":
			GameState.set_flag(finished.sets_flag)

	EventBus.dialogue_finished.emit(npc)


func _seen_flag(dialogue: DialogueData) -> StringName:
	return StringName("seen_dialogue_%s" % dialogue.id)
