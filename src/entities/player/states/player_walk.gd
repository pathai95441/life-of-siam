extends State
## Moving under player input. Drains stamina while running.

var _player: Player


func enter(_msg: Dictionary = {}) -> void:
	_player = actor as Player


func physics_update(delta: float) -> void:
	var direction := _player.read_input()
	if direction.is_zero_approx() and _player.velocity.is_zero_approx():
		machine.transition_to(&"idle")
		return

	var speed := _player.current_speed()
	_player.apply_movement(delta, direction, speed)

	if speed > _player.walk_speed and not direction.is_zero_approx():
		GameState.drain_stamina(GameConstants.STAMINA_PER_RUN_SECOND * delta)


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _player.probe.try_interact():
			_player.get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_tool"):
		machine.transition_to(&"use_tool")
