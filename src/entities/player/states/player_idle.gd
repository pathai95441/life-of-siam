extends State
## Standing still. Watches for movement, tool use and interaction.

var _player: Player


func enter(_msg: Dictionary = {}) -> void:
	_player = actor as Player
	_player.velocity = Vector2.ZERO
	_player.ground_velocity = Vector2.ZERO


func physics_update(delta: float) -> void:
	var direction := _player.read_input()
	if not direction.is_zero_approx():
		machine.transition_to(&"walk")
		return
	_player.apply_movement(delta, Vector2.ZERO, 0.0)


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _player.probe.try_interact():
			_player.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_tool"):
		machine.transition_to(&"use_tool")
