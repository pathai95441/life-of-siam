extends State
## One tool swing. Movement is locked for the duration so a swing always
## resolves against the cell the player was facing when they pressed the key.

## Seconds the swing takes. Replace with the animation length once the player
## has a real AnimationPlayer.
@export var swing_time: float = 0.28

var _player: Player
var _elapsed: float = 0.0


func enter(_msg: Dictionary = {}) -> void:
	_player = actor as Player
	_player.velocity = Vector2.ZERO
	_player.ground_velocity = Vector2.ZERO
	_elapsed = 0.0

	var acted: bool = _player.tool_handler.use_selected()
	if not acted:
		# Nothing to hit — return to idle immediately rather than freezing the
		# player for the full swing on a miss.
		machine.transition_to.call_deferred(&"idle")


func physics_update(delta: float) -> void:
	_elapsed += delta
	_player.apply_movement(delta, Vector2.ZERO, 0.0)
	if _elapsed >= swing_time:
		machine.transition_to(&"idle" if _player.read_input().is_zero_approx() else &"walk")
