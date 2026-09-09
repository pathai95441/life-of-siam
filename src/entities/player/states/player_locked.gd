extends State
## The player exists but is not driving: dialogue, cutscene, menu, sleeping.
##
## A dedicated state rather than an `is_locked` flag, so that every other state
## stays free of "unless locked" branches.

var _player: Player
var reason: StringName = &""


func enter(msg: Dictionary = {}) -> void:
	_player = actor as Player
	reason = StringName(msg.get("reason", "unknown"))
	_player.velocity = Vector2.ZERO


func physics_update(_delta: float) -> void:
	# Bleed off residual velocity so the player does not slide during dialogue.
	_player.velocity = Vector2.ZERO
	_player.move_and_slide()
