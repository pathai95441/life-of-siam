extends Node
## The morning summary. A notice with a lifetime, so what is worth testing is
## when it appears, what it says, and that it goes away on its own.

var pass_count := 0
var fail_count := 0

var _summary: DailySummary


func check(label: String, condition: bool) -> void:
	if condition:
		pass_count += 1
		print("  PASS  ", label)
	else:
		fail_count += 1
		print("  FAIL  ", label)


func check_eq(label: String, got: Variant, want: Variant) -> void:
	check("%s (got %s, want %s)" % [label, got, want], got == want)


func _ready() -> void:
	_summary = (load("res://src/ui/hud/daily_summary.tscn") as PackedScene).instantiate()
	add_child(_summary)
	await get_tree().process_frame

	_test_hidden_until_something_sells()
	_test_shows_the_takings()
	await _test_it_goes_away()
	_test_second_shipment_restarts_the_clock()

	print("\n==================================================")
	print("  daily_summary_test: %d passed, %d failed" % [pass_count, fail_count])
	print("==================================================")
	get_tree().quit(1 if fail_count > 0 else 0)


func _test_hidden_until_something_sells() -> void:
	print("\n--- silent by default ---")
	check("hidden on a fresh morning", not _summary.is_showing())
	# A day with an empty bin emits nothing at all, so there is no summary to
	# suppress -- the silence comes from the bin, not from a check here.
	EventBus.day_started.emit(2, 0, 1)
	check("a day with no shipment stays silent", not _summary.is_showing())


func _test_shows_the_takings() -> void:
	print("\n--- showing the takings ---")
	EventBus.items_shipped.emit(175, 5)
	check("it appeared", _summary.is_showing())
	check_eq("the amount is the money earned", _summary.amount_label.text, "+175 ฿")
	check("the detail names the item count", _summary.detail_label.text.contains("5"))


func _test_it_goes_away() -> void:
	print("\n--- it goes away on its own ---")
	EventBus.items_shipped.emit(40, 1)
	check("showing again", _summary.is_showing())
	check("the clock is running", _summary.seconds_left() > 0.0)

	# Burn the display time rather than waiting four real seconds.
	for _i in 300:
		_summary._process(0.02)
	check("it hid itself once the time was up", not _summary.is_showing())
	check_eq("and the clock stopped", _summary.seconds_left(), 0.0)


## Two shipments landing in one morning must not stack their timers into a
## notice that outstays twice its welcome.
func _test_second_shipment_restarts_the_clock() -> void:
	print("\n--- two shipments in one morning ---")
	EventBus.items_shipped.emit(10, 1)
	_summary._process(2.0)
	var after_first := _summary.seconds_left()
	check("time has been used up", after_first < _summary.DISPLAY_SECONDS)

	EventBus.items_shipped.emit(20, 2)
	check_eq("the clock restarted rather than extending",
		_summary.seconds_left(), _summary.DISPLAY_SECONDS)
	check_eq("and it shows the newer figure", _summary.amount_label.text, "+20 ฿")
	_summary.hide_summary()
