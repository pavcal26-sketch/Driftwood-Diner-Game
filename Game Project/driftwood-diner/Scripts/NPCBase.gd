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
var _has_sprite: bool = false
var _walk_frame: int  = 0
var _walk_timer: float = 0.0
const WALK_FRAME_INTERVAL: float = 0.18   # seconds per walk frame

@onready var _sprite: Sprite2D = $Sprite
var anim_node: Node2D = null  # Prepared for Spriter Pro or other complex animation nodes

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

	_load_sprite(id)
	queue_redraw()
	_walk_in()

func _load_sprite(id: String) -> void:
	# Try numbered frames first (_0, _1, etc.), then plain name
	var frames: Array[Texture2D] = []
	var i := 0
	while i < 5:
		var path := "res://Assets/npcs/sprites/%s_%d.png" % [id, i]
		var tex := _try_load_texture(path)
		if tex:
			frames.append(tex)
		elif frames.is_empty() and i == 0:
			# If index 0 is missing, it might start at index 1.
			pass
		else:
			break
		i += 1
	if frames.is_empty():
		var tex := _try_load_texture("res://Assets/npcs/sprites/%s.png" % id)
		if tex:
			frames.append(tex)
	if not frames.is_empty():
		_sprite.texture = frames[0]
		_sprite.visible = true
		_has_sprite = true
		anim_node = _sprite
		# store extra frames as metadata for walk cycle
		set_meta("walk_frames", frames)
	else:
		_sprite.visible = false
		_has_sprite = false

static func _try_load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Try raw file load for non-imported assets
	var os_path := ProjectSettings.globalize_path(path)
	var fa := FileAccess.open(os_path, FileAccess.READ)
	if fa == null:
		return null
	var bytes := fa.get_buffer(fa.get_length())
	fa.close()
	if bytes.size() < 8:
		return null
	var img := Image.new()
	var err: int
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	else:
		return null
	if err != OK or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	return tex

func _process(delta: float) -> void:
	if _state in ["entering", "at_counter", "leaving", "returning"]:
		# animate walk cycle
		if _has_sprite and has_meta("walk_frames"):
			_walk_timer += delta
			if _walk_timer >= WALK_FRAME_INTERVAL:
				_walk_timer = 0.0
				var frames: Array = get_meta("walk_frames")
				_walk_frame = (_walk_frame + 1) % frames.size()
				_sprite.texture = frames[_walk_frame]
	elif _state in ["seated", "waiting_food", "queued"]:
		# gentle idle bob
		_bob_time += delta * 2.0
		position.y = floor_y + sin(_bob_time) * 1.5
	queue_redraw()

func _draw() -> void:
	# always draw shadow
	draw_circle(Vector2(0, 4), 18, Color(0, 0, 0, 0.18))

	if _has_sprite:
		# sprite handles rendering — just draw indicator and shadow
		pass
	else:
		# fallback colored rectangle placeholder
		draw_rect(Rect2(-14, -52, 28, 44), _color)
		draw_circle(Vector2(0, -62), 12, _color)
		draw_string(ThemeDB.fallback_font, Vector2(-30, 10),
			npc_id.replace("_", " "), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# state indicator above character regardless of sprite
	var indicator: String = ""
	match _state:
		"waiting_food":
			indicator = "..."
		"satisfied":
			indicator = "v"
		"queued":
			indicator = "..."
	if indicator != "":
		var label_y: float = -90.0 if _has_sprite else -78.0
		draw_string(ThemeDB.fallback_font, Vector2(-6, label_y), indicator,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

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
	_set_direction(-1)  # walking left (entering from right)
	var dist: float = abs(offscreen_x - seat_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", seat_x, dist / WALK_SPEED)
	tween.tween_callback(_on_seated)

func _on_seated() -> void:
	_state = "seated"
	SignalBus.npc_arrived.emit(npc_id)
	DialogueManager.record_visit(npc_id, GameManager.current_weather)
	await get_tree().create_timer(randf_range(1.0, 2.5)).timeout
	if not is_instance_valid(self):
		return
	_request_counter()

func _request_counter() -> void:
	_state = "queued"
	queue_redraw()
	SignalBus.npc_requests_counter.emit(npc_id)

func approach_counter() -> void:
	_state = "at_counter"
	queue_redraw()
	_set_direction(-1)  # walking left toward counter
	var dist: float = abs(seat_x - counter_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", counter_x, dist / WALK_SPEED)
	tween.tween_callback(_on_at_counter)

func _on_at_counter() -> void:
	SignalBus.npc_at_counter.emit(npc_id)
	# reset dialogue state for this visit
	_dialogue_active = true
	_pending_serve_dish = ""
	# Start listening for serves immediately — player can cook while dialogue is up
	SignalBus.npc_served.connect(_on_served)
	SignalBus.dialogue_finished.connect(_on_dialogue_done, CONNECT_ONE_SHOT)

# tracks whether we got served while dialogue was still showing
var _pending_serve_dish: String = ""
var _dialogue_active: bool = true

func _on_dialogue_done(finished_id: String) -> void:
	if not is_instance_valid(self):
		return
	if finished_id != npc_id:
		# not our dialogue — wait for the next one
		SignalBus.dialogue_finished.connect(_on_dialogue_done, CONNECT_ONE_SHOT)
		return
	_dialogue_active = false
	
	# if we got served during dialogue, process it now
	if _pending_serve_dish != "":
		var dish := _pending_serve_dish
		_pending_serve_dish = ""
		_process_serve(dish)
		return
	
	_state = "waiting_food"
	queue_redraw()
	# patience timer — only starts after dialogue ends
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
	
	# if dialogue is still showing, buffer the serve for after it finishes
	if _dialogue_active:
		_pending_serve_dish = dish_id
		return
	
	_process_serve(dish_id)

func _process_serve(dish_id: String) -> void:
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
	if not is_instance_valid(self):
		return
	_leave_from_counter()

func _leave_from_counter() -> void:
	_state = "leaving"
	SignalBus.npc_left_counter.emit(npc_id)
	_set_direction(1)  # walking right toward exit
	var dist: float = abs(position.x - offscreen_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", offscreen_x, dist / WALK_SPEED)
	tween.tween_callback(_on_left)

func _walk_to_seat_then_leave() -> void:
	_state = "returning"
	SignalBus.npc_left_counter.emit(npc_id)
	_set_direction(1)  # walking right back to seat
	var dist: float = abs(counter_x - seat_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", seat_x, dist / WALK_SPEED)
	tween.tween_callback(_idle_then_leave)

func _set_direction(dir: int) -> void:
	# dir: -1 = walking left, 1 = walking right
	if _has_sprite and anim_node:
		if anim_node is Sprite2D:
			anim_node.flip_h = (dir > 0)
		else:
			anim_node.scale.x = abs(anim_node.scale.x) * (-1 if dir > 0 else 1)

func _idle_then_leave() -> void:
	_state = "seated"
	await get_tree().create_timer(randf_range(3.0, 8.0)).timeout
	if not is_instance_valid(self):
		return
	_leave()

func _leave() -> void:
	_state = "leaving"
	_set_direction(1)  # walking right toward exit
	var dist: float = abs(position.x - offscreen_x)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:x", offscreen_x, dist / WALK_SPEED)
	tween.tween_callback(_on_left)

func _on_left() -> void:
	SignalBus.npc_departed.emit(npc_id)
	queue_free()
