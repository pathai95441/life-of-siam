class_name Player
extends CharacterBody2D
## The player avatar: movement, facing, tool use and interaction.
##
## Behaviour lives in the [StateMachine] child; this script owns only what all
## states share (velocity, facing, node references) and the glue to global
## systems. Keeping the shared surface small is what stops the FSM from
## degenerating into a pile of booleans.

const SAVE_ID := &"player"

@export var walk_speed: float = GameConstants.PLAYER_WALK_SPEED
@export var run_speed: float = GameConstants.PLAYER_RUN_SPEED
@export var acceleration: float = GameConstants.PLAYER_ACCELERATION
@export var friction: float = GameConstants.PLAYER_FRICTION

## Last non-zero movement direction; drives the probe and, later, animation.
var facing: Vector2 = Vector2.DOWN
var input_direction: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var state_machine: StateMachine = $StateMachine
@onready var probe: InteractionProbe = $InteractionProbe
@onready var tool_handler: ToolHandler = $ToolHandler
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	add_to_group(&"player")
	add_to_group(SaveManager.GROUP_SAVEABLE)
	collision_layer = GameConstants.layer_mask(GameConstants.Layer.PLAYER)
	collision_mask = GameConstants.layer_mask(GameConstants.Layer.WORLD) \
		| GameConstants.layer_mask(GameConstants.Layer.NPC)

	# The player must not act while a conversation or menu owns the input.
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)

	probe.point_towards(facing)
	EventBus.player_spawned.emit(self)


func _exit_tree() -> void:
	EventBus.player_despawned.emit()


# --- Shared helpers used by states -------------------------------------------

func read_input() -> Vector2:
	input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return input_direction


func current_speed() -> float:
	var running := Input.is_action_pressed("run") and GameState.has_stamina(1.0)
	return run_speed if running else walk_speed


func apply_movement(delta: float, target_direction: Vector2, speed: float) -> void:
	if target_direction.is_zero_approx():
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		velocity = velocity.move_toward(target_direction * speed, acceleration * delta)
		set_facing(target_direction)
	move_and_slide()


func set_facing(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	# Snap to the dominant axis: 4-way facing reads better than free angles on
	# a tile grid, and it keeps the probe aligned to whole cells.
	facing = Vector2.RIGHT * signf(direction.x) if absf(direction.x) > absf(direction.y) \
		else Vector2.DOWN * signf(direction.y)
	probe.point_towards(facing)


## The cell directly in front of the player — the target of every tool swing.
func target_cell() -> Vector2i:
	var grid := farm_grid()
	if grid == null:
		return Vector2i.ZERO
	return grid.world_to_cell(global_position + facing * float(GameConstants.TILE_SIZE))


## The [FarmGrid] for the current map, or null on maps without one.
func farm_grid() -> FarmGrid:
	return get_tree().get_first_node_in_group(&"farm_grid") as FarmGrid


func lock(reason: StringName = &"dialogue") -> void:
	velocity = Vector2.ZERO
	if state_machine.has_state(&"locked"):
		state_machine.transition_to(&"locked", {"reason": reason})


func unlock() -> void:
	if state_machine.is_in(&"locked"):
		state_machine.transition_to(&"idle")


func _on_dialogue_started(_npc_id: StringName) -> void:
	lock(&"dialogue")


func _on_dialogue_finished(_npc_id: StringName) -> void:
	unlock()


# --- Save contract -----------------------------------------------------------

func get_save_id() -> StringName:
	return SAVE_ID


func save_state() -> Dictionary:
	return {
		"x": global_position.x,
		"y": global_position.y,
		"facing_x": facing.x,
		"facing_y": facing.y,
	}


func load_state(data: Dictionary) -> void:
	global_position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	set_facing(Vector2(float(data.get("facing_x", 0.0)), float(data.get("facing_y", 1.0))))
