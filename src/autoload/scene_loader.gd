extends Node
## Fade-covered scene transitions with threaded loading.
##
## Every scene change in the game goes through here so that:
##   - the player never sees a one-frame black flash or a half-built scene,
##   - the fade overlay lives on one always-on-top [CanvasLayer] instead of
##     being re-created per scene,
##   - the target spawn point travels with the request, so a door can say
##     "load the farm, put me at the porch" without the farm knowing who asked.
##
## The overlay is built in code rather than as a .tscn: it is three nodes, and
## keeping it here means the autoload has no external scene dependency that
## could break the boot sequence.

const FADE_TIME := 0.35

var _layer: CanvasLayer
var _fade: ColorRect
var _is_changing: bool = false
var _target_path: String = ""


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128  # Above every in-game CanvasLayer.
	_layer.name = "TransitionLayer"
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	_layer.add_child(_fade)

	# Transitions must run while the tree is paused (pause menu -> main menu).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS


func is_changing() -> bool:
	return _is_changing


## Fades out, swaps to [param path], fades back in. [param spawn_point] is
## written to [GameState] so the incoming level knows where to place the player.
func change_scene(path: String, spawn_point: StringName = &"default") -> void:
	if not _begin_change(path, spawn_point):
		return

	await _fade_to(1.0)

	var scene := await _load_threaded(path)
	if scene == null:
		push_error("SceneLoader: failed to load '%s'" % path)
		await _abort_change()
		return

	if not _swap_to(scene):
		await _abort_change()
		return

	# Let the new scene run two full frames so its _ready chain completes before
	# the curtain lifts and before world_ready listeners see it.
	await get_tree().process_frame
	await get_tree().process_frame

	if path == GameConstants.SCENE_WORLD:
		GameState.current_map = path

	await _fade_to(0.0)
	_is_changing = false
	EventBus.scene_change_finished.emit(path)


## Validates the request and puts the world into a state safe to tear down.
## Returns false when the change must not proceed.
func _begin_change(path: String, spawn_point: StringName) -> bool:
	if _is_changing:
		push_warning("SceneLoader: change to %s ignored, already changing to %s"
			% [path, _target_path])
		return false
	if not ResourceLoader.exists(path):
		push_error("SceneLoader: no such scene '%s'" % path)
		return false

	_is_changing = true
	_target_path = path
	GameState.spawn_point = spawn_point
	EventBus.scene_change_started.emit(path)

	# A conversation must not survive the scene it belongs to.
	DialogueSystem.cancel()
	GameClock.set_running(false)
	return true


func _swap_to(scene: PackedScene) -> bool:
	# Unpause before swapping: a paused tree would freeze the new scene.
	get_tree().paused = false
	var err := get_tree().change_scene_to_packed(scene)
	if err == OK:
		return true
	push_error("SceneLoader: change_scene_to_packed failed (%s)" % error_string(err))
	return false


## Lifts the curtain on whatever is still on screen and releases the lock, so a
## failed change leaves the player looking at the old scene rather than black.
func _abort_change() -> void:
	await _fade_to(0.0)
	_is_changing = false


func to_main_menu() -> void:
	GameState.set_in_game(false)
	GameClock.set_running(false)
	AudioManager.stop_music()
	await change_scene(GameConstants.SCENE_MAIN_MENU)


func _load_threaded(path: String) -> PackedScene:
	var err := ResourceLoader.load_threaded_request(path, "PackedScene")
	if err != OK:
		return null
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				return ResourceLoader.load_threaded_get(path) as PackedScene
			_:
				return null
	return null


func _fade_to(alpha: float) -> void:
	_fade.visible = true
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", alpha, FADE_TIME)
	await tween.finished
	_fade.visible = alpha > 0.0
