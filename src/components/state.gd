class_name State
extends Node
## Base class for one node in a [StateMachine].
##
## States are plain child nodes so they are visible and reorderable in the
## editor, and so each one can hold its own exported tuning values.

var machine: StateMachine
## The node the machine drives — the scene root that owns the machine.
var actor: Node


func setup(p_machine: StateMachine, p_actor: Node) -> void:
	machine = p_machine
	actor = p_actor


## Called once when this state becomes current. [param msg] carries hand-off
## data (e.g. which tool triggered a use_tool state).
func enter(_msg: Dictionary = {}) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass
