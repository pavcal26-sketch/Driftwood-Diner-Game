extends Node

# --- Continuous clock ---
# game_hour is a float from 0.0 to 24.0
# 1 real second = ~3 game-minutes → full 24h cycle ≈ 8 real minutes
var game_hour: float = 18.0   # start at 6 PM (evening)
const GAME_MINUTES_PER_SECOND: float = 3.0

# derived phase — backward compat with anything listening for phase strings
var current_phase: String = "evening"

# --- State ---
var current_day: int = 1
var current_weather: String = "clear"   # "clear" | "fog" | "rain"
var nights_survived: int = 0

const WEATHER_CHANCES: Dictionary = {
	"clear": 0.5,
	"fog":   0.3,
	"rain":  0.2,
}

# Which NPCs are eligible to visit tonight (set by npc_spawn_manager)
var tonight_roster: Array[String] = []

# track last emitted minute so we only fire clock_tick once per game-minute
var _last_emitted_minute: int = -1

func _ready() -> void:
	current_phase = _phase_from_hour(game_hour)

func _process(delta: float) -> void:
	var old_phase: String = current_phase
	
	# tick the clock forward
	game_hour += (GAME_MINUTES_PER_SECOND * delta) / 60.0
	
	# wrap around midnight
	if game_hour >= 24.0:
		game_hour -= 24.0
	
	# auto-advance day at dawn (5:00 AM)
	# only trigger once by checking old hour was before 5 and new is after
	var new_phase: String = _phase_from_hour(game_hour)
	current_phase = new_phase
	
	# emit clock_tick every game-minute
	var current_minute: int = int(game_hour * 60.0)
	if current_minute != _last_emitted_minute:
		_last_emitted_minute = current_minute
		SignalBus.clock_tick.emit(game_hour)
	
	# emit phase change if it crossed a boundary
	if new_phase != old_phase:
		SignalBus.day_phase_changed.emit(new_phase)

# maps hour to phase string — backward compatible with existing listeners
func _phase_from_hour(h: float) -> String:
	if h >= 5.0 and h < 7.0:
		return "dawn"
	elif h >= 7.0 and h < 17.0:
		return "day"
	elif h >= 17.0 and h < 20.0:
		return "evening"
	else:
		return "night"  # 20:00–5:00

# returns a formatted clock string like "9:42 PM"
func get_clock_string() -> String:
	var total_minutes: int = int(game_hour * 60.0)
	var hours_24: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	
	var period: String = "AM" if hours_24 < 12 else "PM"
	var hours_12: int = hours_24 % 12
	if hours_12 == 0:
		hours_12 = 12
	
	return "%d:%02d %s" % [hours_12, minutes, period]

func advance_day() -> void:
	current_day += 1
	nights_survived += 1
	game_hour = 5.0  # jump to dawn
	_last_emitted_minute = -1
	_roll_weather()
	current_phase = _phase_from_hour(game_hour)
	SignalBus.day_phase_changed.emit(current_phase)
	SignalBus.clock_tick.emit(game_hour)
	SignalBus.day_advanced.emit(current_day)

func set_phase(phase: String) -> void:
	# legacy compat — lets code force a phase if needed
	if phase == current_phase:
		return
	current_phase = phase
	SignalBus.day_phase_changed.emit(phase)

func _roll_weather() -> void:
	var roll := randf()
	var cumulative := 0.0
	for weather in WEATHER_CHANCES:
		cumulative += WEATHER_CHANCES[weather]
		if roll <= cumulative:
			if weather != current_weather:
				current_weather = weather
				SignalBus.weather_changed.emit(weather)
			return

# --- Save / Load ---
const SAVE_PATH := "user://save.json"

func save_game(extra_data: Dictionary = {}) -> void:
	var data := {
		"day": current_day,
		"weather": current_weather,
		"nights": nights_survived,
		"game_hour": game_hour,
	}
	data.merge(extra_data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var result: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if result is Dictionary:
		var d := result as Dictionary
		current_day     = d.get("day", 1)
		current_weather = d.get("weather", "clear")
		nights_survived = d.get("nights", 0)
		game_hour       = d.get("game_hour", 18.0)
		current_phase   = _phase_from_hour(game_hour)
		return d
	return {}
