extends Node
## Owns the passage of in-game time and nothing else.
##
## Everything date-driven (crop growth, shop hours, NPC schedules) reacts to
## this node's signals rather than counting its own days. That keeps one source
## of truth and makes time travel (sleep, festivals, debug skips) safe.

const SAVE_ID := &"game_clock"

var year: int = 1
## One of [enum GameConstants.Season]. Stored as int so it round-trips
## through JSON without enum-cast friction.
var season: int = GameConstants.Season.SPRING
var day: int = 1
var minute_of_day: int = GameConstants.DAY_START_MINUTE

## Real seconds per tick; lower = faster days. Exposed for festivals/debug.
var seconds_per_tick: float = GameConstants.REAL_SECONDS_PER_TICK

var _running: bool = false
var _accumulator: float = 0.0


func _ready() -> void:
	# Group membership instead of a direct call: SaveManager may not exist yet
	# at this point in autoload order, and this keeps the order irrelevant.
	add_to_group(SaveManager.GROUP_PROVIDER)


func _process(delta: float) -> void:
	if not _running:
		return
	_accumulator += delta
	while _accumulator >= seconds_per_tick:
		_accumulator -= seconds_per_tick
		_advance(GameConstants.MINUTE_TICK)


# --- Control -----------------------------------------------------------------

func set_running(value: bool) -> void:
	if _running == value:
		return
	_running = value
	_accumulator = 0.0
	EventBus.clock_running_changed.emit(_running)


func is_running() -> bool:
	return _running


## Resets to day 1 of spring, year 1. Called only by a new game.
func reset() -> void:
	year = 1
	season = GameConstants.Season.SPRING
	day = 1
	minute_of_day = GameConstants.DAY_START_MINUTE
	_accumulator = 0.0


## Ends the current day and wakes on the next one at [constant
## GameConstants.DAY_START_MINUTE]. Used by beds and by forced collapse.
func sleep_until_morning() -> void:
	_roll_over_day()


# --- Queries -----------------------------------------------------------------

func hour() -> int:
	return minute_of_day / GameConstants.MINUTES_PER_HOUR


func minute() -> int:
	return minute_of_day % GameConstants.MINUTES_PER_HOUR


## Absolute day index since the start of the save; the stable key for
## scheduling ("grow on day N") that survives season and year rollover.
func absolute_day() -> int:
	var seasons_elapsed := (year - 1) * GameConstants.SEASON_COUNT + season
	return seasons_elapsed * GameConstants.DAYS_PER_SEASON + day


func time_string() -> String:
	var h := hour() % GameConstants.HOURS_PER_DAY
	var suffix := "AM" if h < 12 else "PM"
	var display_h := h % 12
	if display_h == 0:
		display_h = 12
	return "%d:%02d %s" % [display_h, minute(), suffix]


func date_string() -> String:
	return "%s %d, Y%d" % [GameConstants.SEASON_NAMES[season], day, year]


func date_string_th() -> String:
	return "วันที่ %d %s ปีที่ %d" % [day, GameConstants.SEASON_NAMES_TH[season], year]


# --- Internals ---------------------------------------------------------------

func _advance(minutes: int) -> void:
	var previous_hour := hour()
	minute_of_day += minutes
	EventBus.minute_passed.emit(minute_of_day)

	if hour() != previous_hour:
		EventBus.hour_changed.emit(hour())

	if minute_of_day >= GameConstants.DAY_COLLAPSE_MINUTE:
		# Stayed up too late: the player passes out and loses the rest of the
		# night. Listeners decide the penalty; the clock only rolls the day.
		EventBus.player_collapsed.emit()
		_roll_over_day()


func _roll_over_day() -> void:
	EventBus.day_ended.emit(day, season, year)

	day += 1
	minute_of_day = GameConstants.DAY_START_MINUTE
	_accumulator = 0.0

	if day > GameConstants.DAYS_PER_SEASON:
		day = 1
		season += 1
		if season >= GameConstants.SEASON_COUNT:
			season = 0
			year += 1
		EventBus.season_changed.emit(season, year)

	EventBus.day_started.emit(day, season, year)


# --- Save contract -----------------------------------------------------------

func get_save_id() -> StringName:
	return SAVE_ID


func save_state() -> Dictionary:
	return {
		"year": year,
		"season": season,
		"day": day,
		"minute_of_day": minute_of_day,
	}


func load_state(data: Dictionary) -> void:
	year = int(data.get("year", 1))
	season = int(data.get("season", 0))
	day = int(data.get("day", 1))
	minute_of_day = int(data.get("minute_of_day", GameConstants.DAY_START_MINUTE))
	_accumulator = 0.0
