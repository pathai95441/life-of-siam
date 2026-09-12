class_name DailySummary
extends CanvasLayer
## Shows what the shipping bin sold overnight, once, each morning.
##
## A separate layer rather than more of [Hud]: the HUD is a permanent readout
## that never decides when to appear, and this is a notice with a lifetime.
## Mixing the two would give the HUD a timer and a visibility rule it does not
## otherwise need.
##
## Silent on days with nothing to report, because [signal EventBus.items_shipped]
## only fires when the bin actually had something in it.

const DISPLAY_SECONDS := 4.0

@onready var panel: Control = %Panel
@onready var amount_label: Label = %AmountLabel
@onready var detail_label: Label = %DetailLabel

var _seconds_left: float = 0.0


func _ready() -> void:
	EventBus.items_shipped.connect(_on_items_shipped)
	panel.hide()


func _process(delta: float) -> void:
	if _seconds_left <= 0.0:
		return
	_seconds_left -= delta
	if _seconds_left <= 0.0:
		hide_summary()


func is_showing() -> bool:
	return panel.visible


func seconds_left() -> float:
	return _seconds_left


func hide_summary() -> void:
	_seconds_left = 0.0
	panel.hide()


func _on_items_shipped(total_value: int, item_count: int) -> void:
	amount_label.text = "+%d ฿" % total_value
	detail_label.text = "ขายของเมื่อวาน %d ชิ้น" % item_count
	panel.show()
	# Restarts the clock rather than adding to it, so two shipments in one
	# morning cannot leave the notice up for eight seconds.
	_seconds_left = DISPLAY_SECONDS
