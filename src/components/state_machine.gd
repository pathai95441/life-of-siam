class_name StateMachine
extends Node
## Drives one [State] child at a time.
##
## Keyed by the child node's snake_cased name, so a node called "UseTool"
## is reached as &"use_tool". Transitions are explicit: no state is entered
## except through [method transition_to].

signal transitioned(from: StringName, to: StringName)

## Which child state to start in. Defaults to the first State child.
@export var initial_state: NodePath

var current: State = null
var current_name: StringName = &""

var _states: Dictionary[StringName, State] = {}


func _ready() -> void:
	var actor := owner if owner != null else get_parent()
	for child in get_children():
		if child is State:
			var key := StringName(String(child.name).to_snake_case())
			_states[key] = child
			child.setup(self, actor)

	if _states.is_empty():
		push_error("StateMachine on %s has no State children" % actor)
		return

	# Deferred so the actor's own _ready has finished before the first
	# enter() runs and starts touching its fields.
	_start.call_deferred()


func _start() -> void:
	var first := &""
	if not initial_state.is_empty():
		var node := get_node_or_null(initial_state)
		if node != null:
			first = StringName(String(node.name).to_snake_case())
	if first == &"" or not _states.has(first):
		first = _states.keys()[0]
	transition_to(first)


func _process(delta: float) -> void:
	if current != null:
		current.update(delta)


func _physics_process(delta: float) -> void:
	if current != null:
		current.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current != null:
		current.handle_input(event)


func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	if not _states.has(state_name):
		push_error("StateMachine: no state '%s'" % state_name)
		return
	if state_name == current_name:
		return

	var previous := current_name
	if current != null:
		current.exit()

	current_name = state_name
	current = _states[state_name]
	current.enter(msg)
	transitioned.emit(previous, current_name)


func is_in(state_name: StringName) -> bool:
	return current_name == state_name


func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)
