class_name NPCBase
extends Node2D

# NPC lifecycle with preferences, post-serve reactions, and juice.

const NPC_COLORS: Dictionary = {
	"washed_up_traveller":  Color(0.40, 0.60, 0.90),
	"elderly_baker":        Color(0.90, 0.80, 0.50),
	"failing_fisherman":    Color(0.30, 0.65, 0.70),
	"newcomer":             Color(0.70, 0.85, 0.60),
	"musician":             Color(0.85, 0.55, 0.80),
	"storm_visitor":        Color(0.55, 0.55, 0.75),
	"lighthouse_keeper":    Color(0.95, 0.75, 0.40),
	"drifting_merchant":    Color(0.80, 0.50, 0.40),
	"night_shift_guard":    Color(0.50, 0.60, 0.50),
	"strange_child":        Color(0.90, 0.90, 0.60),
	"quiet_farmer":         Color(0.65, 0.75, 0.45),
	"harbour_worker":       Color(0.55, 0.70, 0.85),
	"elderly_couple":       Color(0.80, 0.70, 0.75),
	"soup_regular":         Color(0.75, 0.65, 0.85),
}

# what each NPC will eat. empty = anything goes.
# entries are substring matches — "soup" matches "fish_stew" won't,
# but "stew" would match "fish_stew". use dish IDs or partial keywords.
const NPC_PREFERENCES: Dictionary = {
	"soup_regular": {
		"accepts": ["soup", "chowder", "broth", "stew"],
		"happy": ["This is exactly what I needed.", "Thank you. Really.", "...perfect."],
		"wrong": ["I... only really eat soup.", "Sorry. I can't.", "Just soup. Please."],
	},
	"elderly_baker": {
		"accepts": ["bread", "cake", "pie", "toast", "pastry", "honey"],
		"happy": ["Your technique is improving.", "Acceptable. More than acceptable.", "She'd approve of this."],
		"wrong": ["I appreciate the effort, but this isn't really my area.", "I'll pass. Try something baked."],
	},
	"failing_fisherman": {
		"accepts": ["fish", "seafood", "chowder", "clam", "ocean", "smoked"],
		"happy": ["Good catch.", "That's proper fish. None of that mainland nonsense.", "...reminds me of the good days."],
		"wrong": ["I eat fish. You know that.", "What is this? Where's the fish?"],
	},
	"musician": {
		"accepts": ["cake", "pie", "honey", "berry", "apple", "dessert", "festival", "sweet"],
		"happy": ["Sweet things help. They always have.", "This is lovely. Thank you.", "I might write something tonight."],
		"wrong": ["I usually go for something sweet...", "Not quite my thing. But thanks."],
	},
	"strange_child": {
		"accepts": ["cake", "pie", "honey", "berry", "apple", "cookie", "sweet", "festival"],
		"happy": ["This is SO good.", "You're the best cook ever.", "Can I have another one tomorrow?"],
		"wrong": ["I don't really like that kind of thing...", "Do you have anything sweet?"],
	},
	"quiet_farmer": {
		"accepts": ["stew", "soup", "bread", "vegetable", "hearty", "garden", "comfort"],
		"happy": ["*nods approvingly*", "Good. Real good.", "Keep the change."],
		"wrong": ["*looks at it skeptically*", "I'll eat it. But next time, something heavier."],
	},
}

# post-serve reactions for NPCs without specific preferences (accept anything)
const GENERIC_HAPPY: Array[String] = [
	"That hit the spot.",
	"Not bad at all.",
	"I'll be back for more of that.",
	"Thanks, cook.",
	"Better than I expected.",
]

const GENERIC_WRONG: Array[String] = [
	"...I'll eat it, I guess.",
	"Interesting choice.",
	"Not what I had in mind, but fine.",
]

var npc_id: String = ""
var _color: Color  = Color.WHITE
var _state: String = "entering"
var _bob_time: float = 0.0

var seat_x:      float = 900.0
var counter_x:   float = 380.0
var offscreen_x: float = 2100.0
var floor_y:     float = 790.0   # set from Main after background scaling

const WALK_SPEED: float = 220.0

func setup(id: String, assigned_seat_x: float = 700.0) -> void:
	npc_id = id
	seat_x = assigned_seat_x
	position = Vector2(offscreen_x, floor_y)

	if NPC_COLORS.has(id):
		_color = NPC_COLORS[id]
	else:
		var h: float = float(abs(id.hash()) % 360) / 360.0
		_color = Color.from_hsv(h, 0.6, 0.85)

	queue_redraw()
	_walk_in()

func _process(delta: float) -> void:
	# gentle idle bob when seated or waiting
	if _state in ["seated", "waiting_food", "queued"]:
		_bob_time += delta * 2.0
		position.y = floor_y + sin(_bob_time) * 1.5
		queue_redraw()

func _draw() -> void:
	# shadow
	draw_circle(Vector2(0, 0), 16, Color(0, 0, 0, 0.15))  # simple shadow
	# body
	draw_rect(Rect2(-14, -52, 28, 44), _color)
	# head
	draw_circle(Vector2(0, -62), 12, _color)

	# state indicator
	var indicator: String = ""
	match _state:
		"waiting_food":
			indicator = "🍽"  # plate emoji — waiting for food
		"satisfied":
			indicator = "♥"
		"queued":
			indicator = "..."

	if indicator != "":
		draw_string(ThemeDB.fallback_font, Vector2(-8, -78), indicator,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

	# name
	draw_string(ThemeDB.fallback_font, Vector2(-30, 10),
		npc_id.replace("_", " "), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

# -----------------------------------------------------------------------
# Preference checking
# -----------------------------------------------------------------------
static func accepts_dish(npc_id_check: String, dish_id: String) -> bool:
	if not NPC_PREFERENCES.has(npc_id_check):
		return true  # no preference = anything goes
	var prefs: Dictionary = NPC_PREFERENCES[npc_id_check]
	var accepts: Array = prefs.get("accepts", [])
	if accepts.is_empty():
		return true
	for keyword: String in accepts:
		if dish_id.contains(keyword):
			return true
	return false

static func get_reaction(npc_id_check: String, dish_id: String) -> String:
	var liked: bool = accepts_dish(npc_id_check, dish_id)
	if NPC_PREFERENCES.has(npc_id_check):
		var prefs: Dictionary = NPC_PREFERENCES[npc_id_check]
		if liked:
			var lines: Array = prefs.get("happy", GENERIC_HAPPY)
			return lines[randi() % lines.size()]
		else:
			var lines: Array = prefs.get("wrong", GENERIC_WRONG)
			return lines[randi() % lines.size()]
	else:
		if liked:
			return GENERIC_HAPPY[randi() % GENERIC_HAPPY.size()]
		return GENERIC_WRONG[randi() % GENERIC_WRONG.size()]

# -----------------------------------------------------------------------
# Movement
# -----------------------------------------------------------------------
func _walk_in() -> void:
	_state = "entering"
	var dist: float = abs(offscreen_x - seat_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", seat_x, dist / WALK_SPEED)
	tween.tween_callback(_on_seated)

func _on_seated() -> void:
	_state = "seated"
	SignalBus.npc_arrived.emit(npc_id)
	DialogueManager.record_visit(npc_id, GameManager.current_weather)
	await get_tree().create_timer(randf_range(1.0, 2.5)).timeout
	_request_counter()

func _request_counter() -> void:
	_state = "queued"
	queue_redraw()
	SignalBus.npc_requests_counter.emit(npc_id)

func approach_counter() -> void:
	_state = "at_counter"
	queue_redraw()
	var dist: float = abs(seat_x - counter_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", counter_x, dist / WALK_SPEED)
	tween.tween_callback(_on_at_counter)

func _on_at_counter() -> void:
	SignalBus.npc_at_counter.emit(npc_id)
	SignalBus.dialogue_finished.connect(_on_dialogue_done, CONNECT_ONE_SHOT)

func _on_dialogue_done(finished_id: String) -> void:
	if not is_instance_valid(self):
		return
	if finished_id != npc_id:
		# not our dialogue — wait for the next one
		SignalBus.dialogue_finished.connect(_on_dialogue_done, CONNECT_ONE_SHOT)
		return
	_state = "waiting_food"
	queue_redraw()
	SignalBus.npc_served.connect(_on_served)
	# patience timer
	var timer := get_tree().create_timer(45.0)
	await timer.timeout
	# guard: node may have been freed by a day advance
	if not is_instance_valid(self):
		return
	if _state == "waiting_food":
		if SignalBus.npc_served.is_connected(_on_served):
			SignalBus.npc_served.disconnect(_on_served)
		_walk_to_seat_then_leave()

func _on_served(served_npc_id: String, dish_id: String) -> void:
	if served_npc_id != npc_id:
		return
	if SignalBus.npc_served.is_connected(_on_served):
		SignalBus.npc_served.disconnect(_on_served)

	_state = "satisfied"
	queue_redraw()

	# bounce reaction
	var tw: Tween = create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(self, "position:y", floor_y - 12.0, 0.15)
	tw.tween_property(self, "position:y", floor_y, 0.25)

	# emit reaction signal for CounterView to show
	var reaction: String = get_reaction(npc_id, dish_id)
	SignalBus.npc_reaction.emit(npc_id, reaction)

	await get_tree().create_timer(2.5).timeout
	_leave_from_counter()

func _leave_from_counter() -> void:
	_state = "leaving"
	SignalBus.npc_left_counter.emit(npc_id)
	var dist: float = abs(position.x - offscreen_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", offscreen_x, dist / WALK_SPEED)
	tween.tween_callback(_on_left)

func _walk_to_seat_then_leave() -> void:
	_state = "returning"
	SignalBus.npc_left_counter.emit(npc_id)
	var dist: float = abs(counter_x - seat_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", seat_x, dist / WALK_SPEED)
	tween.tween_callback(_idle_then_leave)

func _idle_then_leave() -> void:
	_state = "seated"
	await get_tree().create_timer(randf_range(3.0, 8.0)).timeout
	_leave()

func _leave() -> void:
	_state = "leaving"
	var dist: float = abs(position.x - offscreen_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", offscreen_x, dist / WALK_SPEED)
	tween.tween_callback(_on_left)

func _on_left() -> void:
	SignalBus.npc_departed.emit(npc_id)
	queue_free()
