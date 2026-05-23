extends Node

# --- State ---
var current_day: int = 1
var current_phase: String = "day"       # "day" | "evening" | "night"
var current_weather: String = "clear"   # "clear" | "fog" | "rain"
var nights_survived: int = 0

const WEATHER_CHANCES: Dictionary = {
	"clear": 0.5,
	"fog":   0.3,
	"rain":  0.2,
}

# Which NPCs are eligible to visit tonight (set by npc_spawn_manager)
var tonight_roster: Array[String] = []

var _phase_timer: Timer

func _ready() -> void:
	_phase_timer = Timer.new()
	_phase_timer.one_shot = true
	_phase_timer.timeout.connect(_on_phase_timeout)
	add_child(_phase_timer)
	_phase_timer.start(45.0)
	SignalBus.day_advanced.connect(_on_day_advanced)

func advance_day() -> void:
	current_day += 1
	nights_survived += 1
	_roll_weather()
	_set_phase("day")
	_phase_timer.start(45.0)
	SignalBus.day_advanced.emit(current_day)

func _on_phase_timeout() -> void:
	if current_phase == "day":
		_set_phase("evening")
		_phase_timer.start(30.0)
	elif current_phase == "evening":
		_set_phase("night")

func set_phase(phase: String) -> void:
	if phase == current_phase:
		return
	current_phase = phase
	SignalBus.day_phase_changed.emit(phase)

func _set_phase(phase: String) -> void:
	set_phase(phase)

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

func _on_day_advanced(_day: int) -> void:
	pass

# --- Save / Load ---
const SAVE_PATH := "user://save.json"

func save_game(extra_data: Dictionary = {}) -> void:
	var data := {
		"day": current_day,
		"weather": current_weather,
		"nights": nights_survived,
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
		return d
	return {}
