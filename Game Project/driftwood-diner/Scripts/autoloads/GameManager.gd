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

# track last emitted minute so we only fire clock_tick once per game-minute
var _last_emitted_minute: int = -1

func _ready() -> void:
	load_all()
	current_phase = _phase_from_hour(game_hour)

func _process(delta: float) -> void:
	var old_phase: String = current_phase
	
	# tick the clock forward
	game_hour += (GAME_MINUTES_PER_SECOND * delta) / 60.0
	
	# wrap around midnight — this IS the day boundary
	if game_hour >= 24.0:
		game_hour -= 24.0
		# advance to the next day at midnight
		SignalBus.story_signal.emit("force_day_advance")
	
	var new_phase: String = _phase_from_hour(game_hour)
	
	if old_phase == "night" and new_phase == "dawn":
		SignalBus.day_phase_changed.emit(new_phase)
		
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
	@warning_ignore("integer_division")
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
	save_all()  # auto-save at the start of every new day

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
			current_weather = weather
			# always emit — Main needs to re-apply effects even for the same weather
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
	data.merge(extra_data, true)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameManager: Failed to open save file for writing.")
		return
	file.store_string(JSON.stringify(data))
	file.close()
	# On web exports, flush the virtual filesystem to IndexedDB so saves persist
	if OS.has_feature("web"):
		# Godot 4 exposes JS.eval for Emscripten FS sync
		if ClassDB.class_exists("JavaScriptBridge"):
			JavaScriptBridge.eval("if(typeof FS!=='undefined')FS.syncfs(false,function(e){});")

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
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

func save_all() -> void:
	var state := {}
	# Grab state from all orchestrators
	if get_node_or_null("/root/Economy"):
		state["economy"] = Economy.get_save_data()
	if get_node_or_null("/root/DialogueManager"):
		state["dialogue"] = DialogueManager.get_save_data()
	# Can add CookingUI, Tutorial later via direct method calling or signals
	save_game(state)

func load_all() -> void:
	var data := load_game()
	if data.is_empty():
		return
	if data.has("economy") and get_node_or_null("/root/Economy"):
		Economy.load_save_data(data["economy"])
	if data.has("dialogue") and get_node_or_null("/root/DialogueManager"):
		DialogueManager.load_save_data(data["dialogue"])
