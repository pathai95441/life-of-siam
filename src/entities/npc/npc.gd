class_name Npc
extends Interactable
## A villager. Blocks movement via its StaticBody2D child and starts a
## conversation when interacted with.
##
## Extends [Interactable] directly so a villager is one node in the editor.
## Schedules (walking a daily route) are deliberately out of scope for v1;
## when they land they belong in a separate NpcSchedule component that moves
## a child body, not in this file.

@export var npc_data: NpcData
@export var sprite_node: Sprite2D


func _ready() -> void:
	super()
	add_to_group(&"npc")
	if npc_data == null:
		push_warning("Npc '%s' has no NpcData assigned" % name)
		return
	prompt = "คุยกับ %s" % npc_data.label()
	if sprite_node != null and npc_data.sprite != null:
		sprite_node.texture = npc_data.sprite


func interact(actor: Node) -> void:
	super(actor)
	if npc_data == null:
		return
	var dialogue := _pick_dialogue()
	if dialogue == null:
		EventBus.toast_posted.emit("%s ไม่มีอะไรจะพูด" % npc_data.label())
		return
	DialogueSystem.start(dialogue, npc_data.id)
	# Talking once a day builds friendship; the flag resets each morning.
	var flag := StringName("talked_%s_day_%d" % [npc_data.id, GameClock.absolute_day()])
	if not GameState.has_flag(flag):
		GameState.set_flag(flag)
		GameState.add_relationship(npc_data.id, 20)


## Conditional lines win over the default so story beats can override chatter.
func _pick_dialogue() -> DialogueData:
	for flag in npc_data.conditional_dialogue:
		if GameState.has_flag(StringName(flag)):
			var candidate: Variant = npc_data.conditional_dialogue[flag]
			if candidate is DialogueData:
				return candidate
	return npc_data.default_dialogue
