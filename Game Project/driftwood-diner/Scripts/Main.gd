extends Node2D

# Root scene controller.
# Manages NPC spawning with unique seats, counter queue, and UI wiring.

@onready var counter_view : CanvasLayer    = $CounterView
@onready var hud          : CanvasLayer    = $HUD
@onready var cooking_ui   : CanvasLayer    = $CookingUI
@onready var day_trans    : CanvasLayer    = $DayTransition
@onready var npc_layer    : Node2D         = $Diner/NPCLayer
@onready var canvas_mod   : CanvasModulate = $Diner/CanvasModulate
@onready var windows      : Node2D         = $Diner/Windows
@onready var exterior     : Sprite2D       = $Diner/Exterior
@onready var interior     : Sprite2D       = $Diner/Interior
@onready var rain_layer   : Node2D         = $Diner/RainLayer

var _weather_tween: Tween = null
var _ambience_tween: Tween = null
var _recipe_book: CanvasLayer = null
var _recipe_list: VBoxContainer = null   # direct ref — avoids fragile node-path lookup
var _foghorn_timer: Timer = null
var _spawn_timer: Timer = null
var _fog_particles: CPUParticles2D = null

@onready var corkboard_ui : CanvasLayer    = $CorkboardUI
@onready var tutorial     : CanvasLayer    = $Tutorial
@onready var ambience_player : AudioStreamPlayer = $Diner/Ambience
@onready var music_player    : AudioStreamPlayer = $MusicPlayer

const NPC_SCENE := preload("res://Scenes/NPC.tscn")

var _day_trans_anim : AnimationPlayer
var _transitioning  : bool = false


# Computed after background is scaled — NPCs need these to walk on the floor
var _floor_y    : float = 790.0
var _counter_x  : float = 380.0
var _offscreen_x: float = 2100.0

# NPC tracking
var _present_npcs: Array[String] = []

# Counter queue
var _counter_occupied: bool = false
var _counter_queue: Array[String] = []

# Seat positions across the diner width (1920px viewport)
const SEAT_POSITIONS: Array[float] = [650.0, 800.0, 950.0, 1100.0, 1250.0, 1400.0]
var _used_seats: Dictionary = {}

# weather particles
var _rain_particles: CPUParticles2D
var _drizzle_particles: CPUParticles2D

# lighting color table — keyed by hour, lerped between
const LIGHTING_TABLE: Array[Dictionary] = [
	{"hour": 0.0,  "color": Color(0.25, 0.28, 0.50, 1.0)},  # midnight — deep blue
	{"hour": 5.0,  "color": Color(0.30, 0.30, 0.48, 1.0)},  # pre-dawn — still dark
	{"hour": 6.0,  "color": Color(0.70, 0.55, 0.45, 1.0)},  # dawn — warm amber
	{"hour": 7.5,  "color": Color(0.95, 0.88, 0.78, 1.0)},  # morning — warm white
	{"hour": 12.0, "color": Color(1.00, 0.97, 0.90, 1.0)},  # noon — bright
	{"hour": 16.0, "color": Color(1.00, 0.93, 0.82, 1.0)},  # afternoon — slightly warm
	{"hour": 18.0, "color": Color(0.95, 0.72, 0.55, 1.0)},  # evening — golden hour
	{"hour": 19.5, "color": Color(0.65, 0.50, 0.55, 1.0)},  # dusk — purple tint
	{"hour": 21.0, "color": Color(0.35, 0.38, 0.55, 1.0)},  # night falls
	{"hour": 24.0, "color": Color(0.25, 0.28, 0.50, 1.0)},  # wraps to midnight
]

func _ready() -> void:
	_build_day_transition_anims()
	_setup_weather_effects()
	_connect_signals()
	_fit_layers()
	_apply_lighting(GameManager.game_hour)
	_apply_weather(GameManager.current_weather)
	_build_recipe_book()
	# CorkboardUI is now a scene instance — wire its closed signal
	corkboard_ui.closed.connect(_toggle_corkboard)

	_setup_audio()
	_setup_foghorn()
	_setup_spawner()

	# first night — traveller arrives, then kick off the evening spawn schedule
	# (without this, NPCs only spawn on phase CHANGE, so nothing until hour 20)
	await get_tree().create_timer(2.0).timeout
	spawn_npc("washed_up_traveller")
	_schedule_phase_spawns(GameManager.current_phase)
	# ensure weather visuals are correct at boot (default is "clear")
	_apply_weather(GameManager.current_weather)

# -----------------------------------------------------------------------
# Background layering — exterior behind rain behind interior
# -----------------------------------------------------------------------
func _fit_layers() -> void:
	var vp: Vector2 = get_viewport_rect().size

	# Interior (windowless, 1024x583) is the primary layer — scale to fill viewport.
	# Exterior (full diner, 2752x1566) is the same image at ~2.69x resolution.
	# Scale the exterior down by the resolution ratio so both overlap pixel-perfectly.
	if interior.texture != null:
		var int_size: Vector2 = interior.texture.get_size()
		var sx: float = vp.x / int_size.x
		var sy: float = vp.y / int_size.y
		var s: float = maxf(sx, sy)

		interior.scale    = Vector2(s, s)
		interior.position = vp * 0.5

		# scale exterior to match — it's higher res, so scale down proportionally
		if exterior.texture != null:
			var ext_size: Vector2 = exterior.texture.get_size()
			var ratio_x: float = int_size.x / ext_size.x
			var ratio_y: float = int_size.y / ext_size.y
			exterior.scale    = Vector2(s * ratio_x, s * ratio_y)
			exterior.position = vp * 0.5

		# compute floor position from the interior layer
		var floor_frac: float = 0.73
		var tex_floor_y: float = int_size.y * floor_frac
		var offset_from_center: float = tex_floor_y - int_size.y * 0.5
		_floor_y    = vp.y * 0.5 + offset_from_center * s
		_counter_x  = vp.x * 0.30
		_offscreen_x = vp.x + 200.0

func _connect_signals() -> void:
	SignalBus.day_phase_changed.connect(_schedule_phase_spawns)
	SignalBus.day_phase_changed.connect(func(_p): _update_ambience())
	SignalBus.weather_changed.connect(_apply_weather)
	SignalBus.weather_changed.connect(func(_w): _update_ambience())
	SignalBus.clock_tick.connect(_apply_lighting)
	SignalBus.npc_at_counter.connect(_on_npc_at_counter)
	SignalBus.npc_requests_counter.connect(_on_npc_requests_counter)
	SignalBus.npc_left_counter.connect(_on_npc_left_counter)
	SignalBus.dialogue_finished.connect(_on_dialogue_finished)
	# npc_arrived no longer needs to register in _present_npcs — spawn_npc does that
	# immediately. Keep listening for other uses (e.g. dialogue visit tracking).
	SignalBus.npc_departed.connect(_on_npc_departed)
	SignalBus.savings_changed.connect(func(v: int): hud.update_savings(v))
	SignalBus.day_advanced.connect(func(d: int): hud.update_day(d))
	SignalBus.debug_spawn_npc.connect(spawn_npc)
	SignalBus.story_signal.connect(_on_story_signal)
	SignalBus.passage_unlocked.connect(_on_passage_unlocked)

	hud.cooking_pressed.connect(_toggle_cooking)
	hud.recipes_pressed.connect(_toggle_recipes)
	hud.corkboard_pressed.connect(_toggle_corkboard)
	# Note: corkboard_ui.closed is connected in _ready after scene is loaded
	hud.advance_pressed.connect(_advance_day)
	cooking_ui.closed.connect(_toggle_cooking)

func _input(event: InputEvent) -> void:
	if counter_view and counter_view.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_all_ui()
	if event.is_action_pressed("action_cook"):
		_toggle_cooking()
	if event.is_action_pressed("action_recipes"):
		_toggle_recipes()
	if event.is_action_pressed("action_corkboard"):
		_toggle_corkboard()
	if event.is_action_pressed("action_end_night"):
		_advance_day()

func _on_story_signal(trigger: String) -> void:
	if trigger == "play_ending_a_sequence" or trigger == "play_ending_b_sequence":
		# Save state before ending
		GameManager.save_all()
		GameManager.set_meta("ending_type", "A" if trigger == "play_ending_a_sequence" else "B")
		get_tree().change_scene_to_file("res://Scenes/EndingCutscene.tscn")
	elif trigger == "force_day_advance":
		_advance_day()
	elif trigger == "unlock_both_endings":
		# Narrative gate met — check if economic gate is also met
		_check_ending_gates()

# -----------------------------------------------------------------------
# Ending Choice System
# -----------------------------------------------------------------------
var _ending_choice_ui: CanvasLayer = null
var _endings_narrative_unlocked: bool = false
var _endings_economic_unlocked: bool = false

func _check_ending_gates() -> void:
	_endings_narrative_unlocked = true
	if Economy.savings >= Economy.PASSAGE_COST:
		_endings_economic_unlocked = true
	if _endings_narrative_unlocked and _endings_economic_unlocked:
		# Both gates met — show choice after a short dramatic pause
		get_tree().create_timer(2.0).timeout.connect(_show_ending_choice)

func _on_passage_unlocked() -> void:
	_endings_economic_unlocked = true
	if _endings_narrative_unlocked and _endings_economic_unlocked:
		get_tree().create_timer(2.0).timeout.connect(_show_ending_choice)

func _show_ending_choice() -> void:
	if _ending_choice_ui != null:
		return  # already showing
	
	_close_all_ui()
	
	_ending_choice_ui = CanvasLayer.new()
	_ending_choice_ui.layer = 15
	add_child(_ending_choice_ui)
	
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ending_choice_ui.add_child(root)
	
	# dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.08, 0.85)
	bg.modulate.a = 0.0
	root.add_child(bg)
	
	# centered panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_anchor(SIDE_LEFT, 0.2)
	panel.set_anchor(SIDE_RIGHT, 0.8)
	panel.set_anchor(SIDE_TOP, 0.2)
	panel.set_anchor(SIDE_BOTTOM, 0.8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.95)
	style.border_color = Color(0.45, 0.55, 0.75, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "A Choice"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	vbox.add_child(title)
	
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.text = "[center]You've saved enough. The Baker's story is told. The pressed flower sits framed on the corkboard.\n\nThe ferry leaves at dawn. You could be on it.\nOr you could stay. Keep the lights on. Wait for the next soul the tide brings in.\n\n[color=#b8a080]What will you do?[/color][/center]"
	desc.fit_content = true
	desc.scroll_active = false
	desc.add_theme_font_size_override("normal_font_size", 16)
	desc.add_theme_color_override("default_color", Color(0.75, 0.72, 0.68))
	vbox.add_child(desc)
	
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 40)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)
	
	var leave_btn := Button.new()
	leave_btn.text = "Leave the Island"
	leave_btn.custom_minimum_size = Vector2(200, 50)
	leave_btn.add_theme_font_size_override("font_size", 16)
	leave_btn.pressed.connect(func(): _on_ending_chosen("A"))
	btn_box.add_child(leave_btn)
	
	var stay_btn := Button.new()
	stay_btn.text = "Stay and Rebuild"
	stay_btn.custom_minimum_size = Vector2(200, 50)
	stay_btn.add_theme_font_size_override("font_size", 16)
	stay_btn.pressed.connect(func(): _on_ending_chosen("B"))
	btn_box.add_child(stay_btn)
	
	# fade in
	var tw := create_tween()
	tw.tween_property(bg, "modulate:a", 1.0, 1.5)

func _on_ending_chosen(ending: String) -> void:
	# Record the choice
	DialogueManager.set_ending_choice(ending)
	GameManager.save_all()
	
	# Remove choice UI
	if _ending_choice_ui:
		_ending_choice_ui.queue_free()
		_ending_choice_ui = null
	
	# Spawn the Traveller for their farewell — T9/T10 will now unlock
	# because ending_chosen condition is met
	spawn_npc("washed_up_traveller")

# -----------------------------------------------------------------------
# NPC spawning with unique seats
# -----------------------------------------------------------------------
func spawn_npc(npc_id: String) -> void:
	if npc_id in _present_npcs:
		return
	# register IMMEDIATELY to prevent duplicate spawns from timers firing
	# before walk-in animation completes (the npc_arrived signal is too late)
	_present_npcs.append(npc_id)

	var seat: float = _assign_seat(npc_id)

	var npc: Node2D = NPC_SCENE.instantiate()
	npc_layer.add_child(npc)
	# pass computed floor/counter positions so NPC walks on the actual diner floor
	var npc_base: NPCBase = npc as NPCBase
	if npc_base:
		npc_base.floor_y     = _floor_y
		npc_base.counter_x   = _counter_x
		npc_base.offscreen_x = _offscreen_x
	npc.setup(npc_id, seat)

	# Play bell sound to notify the player when NPC enters
	var bell := AudioStreamPlayer.new()
	bell.stream = _load_audio_with_fallbacks("res://Assets/Audio/customer_bell")
	bell.volume_db = 8.0
	bell.finished.connect(bell.queue_free)
	add_child(bell)
	bell.play()

func _assign_seat(npc_id: String) -> float:
	# find the first unused seat position
	for sx in SEAT_POSITIONS:
		var taken: bool = false
		for used_seat: float in _used_seats.values():
			if abs(used_seat - sx) < 10.0:
				taken = true
				break
		if not taken:
			_used_seats[npc_id] = sx
			return sx
	# all seats taken — offset from last
	var fallback: float = SEAT_POSITIONS[-1] + (_used_seats.size() * 80.0)
	_used_seats[npc_id] = fallback
	return fallback

# -----------------------------------------------------------------------
# Counter queue
# -----------------------------------------------------------------------
func _on_npc_requests_counter(npc_id: String) -> void:
	if _counter_occupied:
		_counter_queue.append(npc_id)
	else:
		_grant_counter(npc_id)

func _grant_counter(npc_id: String) -> void:
	_counter_occupied = true
	# find the NPC node and tell it to approach
	for child in npc_layer.get_children():
		if child is NPCBase and (child as NPCBase).npc_id == npc_id:
			(child as NPCBase).approach_counter()
			return

func _on_npc_left_counter(_npc_id: String) -> void:
	_counter_occupied = false
	# let the next queued NPC approach (iterative, not recursive)
	while not _counter_queue.is_empty():
		var next_id: String = _counter_queue.pop_front()
		if next_id in _present_npcs:
			_grant_counter(next_id)
			return
	# nobody left in queue — counter is free

func _on_npc_at_counter(npc_id: String) -> void:
	var meta     : Dictionary = DialogueManager.get_npc_meta(npc_id)
	var lines    : Array      = DialogueManager.get_lines(npc_id)
	var name_str : String     = meta.get("display_name",
		npc_id.replace("_", " ").capitalize())
		
	# close any open UIs to show the dialogue
	_close_all_ui()
	
	# pause all OTHER NPCs so their timers don't tick during dialogue
	_pause_npcs_except(npc_id)
	counter_view.show_npc(npc_id, lines, name_str)

func _on_dialogue_finished(_npc_id: String) -> void:
	_unpause_all_npcs()

# -----------------------------------------------------------------------
# NPC pause/unpause — freezes timers, tweens, and process during dialogue
# -----------------------------------------------------------------------
func _pause_npcs_except(active_npc_id: String) -> void:
	for child in npc_layer.get_children():
		if child is NPCBase and (child as NPCBase).npc_id != active_npc_id:
			child.set_process(false)
			child.set_physics_process(false)
			# PROCESS_MODE_DISABLED pauses tweens and await timers
			child.process_mode = Node.PROCESS_MODE_DISABLED

func _unpause_all_npcs() -> void:
	for child in npc_layer.get_children():
		if child is NPCBase:
			child.process_mode = Node.PROCESS_MODE_INHERIT
			child.set_process(true)
			child.set_physics_process(true)

func _on_npc_departed(npc_id: String) -> void:
	_present_npcs.erase(npc_id)
	_used_seats.erase(npc_id)
	_counter_queue.erase(npc_id)

# -----------------------------------------------------------------------
# Continuous lighting — lerps CanvasModulate based on game_hour
# -----------------------------------------------------------------------
func _apply_lighting(hour: float) -> void:
	var color: Color = _lerp_lighting(hour)
	canvas_mod.color = color

	# also drive the window overlays based on time
	var day_win = windows.get_node("Day")
	var night_win = windows.get_node("Night")
	day_win.visible = true
	night_win.visible = true

	# day windows bright during day, night windows bright at night
	var night_factor: float = 0.0
	if hour >= 20.0 or hour < 5.0:
		night_factor = 1.0
	elif hour >= 18.0:
		night_factor = (hour - 18.0) / 2.0  # fade in 18-20
	elif hour >= 5.0 and hour < 7.0:
		night_factor = 1.0 - ((hour - 5.0) / 2.0)  # fade out 5-7

	day_win.modulate.a = 1.0 - night_factor
	night_win.modulate.a = night_factor

func _lerp_lighting(hour: float) -> Color:
	# find the two table entries we're between and lerp
	for i in range(LIGHTING_TABLE.size() - 1):
		var a: Dictionary = LIGHTING_TABLE[i]
		var b: Dictionary = LIGHTING_TABLE[i + 1]
		if hour >= a["hour"] and hour < b["hour"]:
			var t: float = (hour - a["hour"]) / (b["hour"] - a["hour"])
			return (a["color"] as Color).lerp(b["color"] as Color, t)
	# fallback — shouldn't happen, but just in case
	return LIGHTING_TABLE[0]["color"]

func _apply_weather(weather: String) -> void:
	var fog = windows.get_node("FogOverlay")
	var static_rain = windows.get_node("Rain")
	static_rain.visible = false
	fog.visible = true

	# kill any leftover weather tween so they don't fight
	if _weather_tween and _weather_tween.is_valid():
		_weather_tween.kill()
	_weather_tween = create_tween().set_parallel(true)
	var t := _weather_tween

	match weather:
		"fog":
			t.tween_property(fog, "modulate:a", 0.92, 4.0)
			if _rain_particles:
				_rain_particles.emitting = false
			if _drizzle_particles:
				_drizzle_particles.emitting = false
			if _fog_particles:
				_fog_particles.emitting = true

		"rain":
			# rain gets particles + light fog for atmosphere
			t.tween_property(fog, "modulate:a", 0.35, 3.0)
			if _rain_particles:
				_rain_particles.emitting = true
			if _drizzle_particles:
				_drizzle_particles.emitting = true
			if _fog_particles:
				_fog_particles.emitting = false

		_:  # "clear" and anything else
			t.tween_property(fog, "modulate:a", 0.0, 5.0)
			if _rain_particles:
				_rain_particles.emitting = false
			if _drizzle_particles:
				_drizzle_particles.emitting = false
			if _fog_particles:
				_fog_particles.emitting = false

# -----------------------------------------------------------------------
# Weather particles — rain falls between the two background layers
# -----------------------------------------------------------------------
func _setup_weather_effects() -> void:
	var vp: Vector2 = get_viewport_rect().size

	# main rain streaks — visible through the window cutout
	_rain_particles = CPUParticles2D.new()
	_rain_particles.emitting = false
	_rain_particles.amount = 200
	_rain_particles.lifetime = 0.9
	_rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	# cover the full width so rain shows through whatever windows exist
	_rain_particles.emission_rect_extents = Vector2(vp.x * 0.5, 10)
	_rain_particles.position = Vector2(vp.x * 0.5, -20)
	_rain_particles.direction = Vector2(-0.3, 1.0)
	_rain_particles.spread = 4.0
	_rain_particles.gravity = Vector2(-60, 1000)
	_rain_particles.initial_velocity_min = 550.0
	_rain_particles.initial_velocity_max = 800.0
	_rain_particles.scale_amount_min = 2.0
	_rain_particles.scale_amount_max = 4.0
	_rain_particles.color = Color(0.7, 0.82, 0.95, 0.8)
	rain_layer.add_child(_rain_particles)

	# fine drizzle — smaller, slower, more transparent
	_drizzle_particles = CPUParticles2D.new()
	_drizzle_particles.emitting = false
	_drizzle_particles.amount = 100
	_drizzle_particles.lifetime = 1.1
	_drizzle_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drizzle_particles.emission_rect_extents = Vector2(vp.x * 0.5, 10)
	_drizzle_particles.position = Vector2(vp.x * 0.5, -30)
	_drizzle_particles.direction = Vector2(-0.2, 1.0)
	_drizzle_particles.spread = 5.0
	_drizzle_particles.gravity = Vector2(-30, 700)
	_drizzle_particles.initial_velocity_min = 350.0
	_drizzle_particles.initial_velocity_max = 500.0
	_drizzle_particles.scale_amount_min = 1.0
	_drizzle_particles.scale_amount_max = 2.0
	_drizzle_particles.color = Color(0.7, 0.82, 0.95, 0.5)
	rain_layer.add_child(_drizzle_particles)

	# fog particles - soft drifting mist shapes
	_fog_particles = CPUParticles2D.new()
	_fog_particles.emitting = false
	_fog_particles.amount = 45
	_fog_particles.lifetime = 12.0
	_fog_particles.preprocess = 10.0
	_fog_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_fog_particles.emission_rect_extents = Vector2(vp.x * 0.5, vp.y * 0.5)
	_fog_particles.position = vp * 0.5
	_fog_particles.direction = Vector2(-1.0, 0.1)
	_fog_particles.spread = 15.0
	_fog_particles.gravity = Vector2.ZERO
	_fog_particles.initial_velocity_min = 10.0
	_fog_particles.initial_velocity_max = 30.0
	_fog_particles.scale_amount_min = 120.0
	_fog_particles.scale_amount_max = 300.0
	_fog_particles.color = Color(0.8, 0.82, 0.88, 0.28)
	
	# Gradient to fade in and out smoothly
	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(0.8, 0.82, 0.88, 0.0))
	color_ramp.add_point(0.2, Color(0.8, 0.82, 0.88, 0.28))
	color_ramp.add_point(0.8, Color(0.8, 0.82, 0.88, 0.28))
	color_ramp.add_point(1.0, Color(0.8, 0.82, 0.88, 0.0))
	_fog_particles.color_ramp = color_ramp
	
	rain_layer.add_child(_fog_particles)

# -----------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------
func _toggle_cooking() -> void:
	if not cooking_ui.visible:
		if counter_view and counter_view.visible:
			return
		cooking_ui.visible = true
		hud.visible = false
		if _recipe_book:
			_recipe_book.visible = false
		corkboard_ui.visible = false
		tutorial.on_cooking_opened()
	else:
		cooking_ui.visible = false
		hud.visible = true

func _toggle_recipes() -> void:
	if _recipe_book == null:
		return
	if not _recipe_book.visible:
		if counter_view and counter_view.visible:
			return
		_recipe_book.visible = true
		cooking_ui.visible = false
		corkboard_ui.visible = false
		hud.visible = false
		_refresh_recipe_book()
		tutorial.on_recipes_opened()
	else:
		_recipe_book.visible = false
		hud.visible = true

func _build_recipe_book() -> void:
	# create a simple CanvasLayer overlay listing all known combinations
	_recipe_book = CanvasLayer.new()
	_recipe_book.layer = 9
	_recipe_book.visible = false
	add_child(_recipe_book)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_recipe_book.add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.10, 0.92)
	root.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_anchor(SIDE_LEFT,   0.1)
	panel.set_anchor(SIDE_TOP,    0.05)
	panel.set_anchor(SIDE_RIGHT,  0.9)
	panel.set_anchor(SIDE_BOTTOM, 0.95)
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  24)
	margin.add_theme_constant_override("margin_top",    20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Recipe Book"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "RecipeList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_recipe_list = list   # store direct reference

	var close_btn := Button.new()
	close_btn.text = "Close  [ R ]"
	close_btn.pressed.connect(_toggle_recipes)
	vbox.add_child(close_btn)

func _refresh_recipe_book() -> void:
	if _recipe_book == null:
		return
	var list: VBoxContainer = _recipe_list
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()

	var combos: Dictionary = CombinationDB.get_all_combinations()
	if combos.is_empty():
		var lbl := Label.new()
		lbl.text = "No combinations discovered yet."
		lbl.modulate = Color(0.6, 0.6, 0.6)
		list.add_child(lbl)
		return

	var discovered_set: Array[String] = cooking_ui.discovered
	for key: String in combos.keys():
		var parts: PackedStringArray = key.split("+")
		if parts.size() < 2:
			continue
		var result: String = combos[key]
		# only show if both inputs AND result have been discovered
		if parts[0] not in discovered_set or parts[1] not in discovered_set:
			continue
		if result not in discovered_set:
			continue
		var is_dish: bool = CombinationDB.is_valid_dish(result)
		var lbl := Label.new()
		var a: String = parts[0].replace("_", " ").capitalize()
		var b: String = parts[1].replace("_", " ").capitalize()
		var r: String = result.replace("_", " ").capitalize()
		lbl.text = a + " + " + b + "  →  " + ("★ " if is_dish else "") + r
		if is_dish:
			lbl.modulate = Color(1.0, 0.92, 0.6)
		list.add_child(lbl)

func _close_all_ui() -> void:
	cooking_ui.visible = false
	if _recipe_book:
		_recipe_book.visible = false
	corkboard_ui.visible = false
	hud.visible = true

func _advance_day() -> void:
	if _transitioning:
		return
	if counter_view and counter_view.visible:
		return
	_do_day_transition()
	tutorial.on_day_advanced()

func _do_day_transition() -> void:
	_transitioning = true
	_close_all_ui()

	# force-remove all NPCs
	for child in npc_layer.get_children():
		child.queue_free()
	_present_npcs.clear()
	_used_seats.clear()
	_counter_queue.clear()
	_counter_occupied = false

	day_trans.get_node("Fill/TransitionLabel").text = "Day %d begins..." % (GameManager.current_day + 1)
	day_trans.visible = true
	_day_trans_anim.play("fade_in")
	await _day_trans_anim.animation_finished
	GameManager.advance_day()
	await get_tree().create_timer(0.6).timeout
	_day_trans_anim.play("fade_out")
	await _day_trans_anim.animation_finished
	day_trans.visible = false
	_transitioning = false

func _setup_spawner() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)

func _schedule_phase_spawns(phase: String) -> void:
	if _transitioning:
		return
	
	if phase == "dawn" or phase == "day":
		_spawn_timer.stop()
		return
		
	# Start recurring spawn checks during evening and night (check every 20-30s)
	_spawn_timer.wait_time = randf_range(20.0, 30.0)
	_spawn_timer.start()
	
	# Also spawn 1-2 initial customers immediately (with short delays)
	var count := randi_range(1, 2)
	for i in range(count):
		var delay := randf_range(1.0, 5.0)
		get_tree().create_timer(delay).timeout.connect(func():
			if not _transitioning and GameManager.current_phase in ["evening", "night"]:
				_spawn_random_npc()
		)

func _on_spawn_timer_timeout() -> void:
	if _transitioning or GameManager.current_phase not in ["evening", "night"]:
		return
		
	# Limit maximum simultaneous NPCs in diner to 4
	if _present_npcs.size() < 4:
		_spawn_random_npc()
		
	# Randomize next spawn check time
	_spawn_timer.wait_time = randf_range(25.0, 45.0)

func _spawn_random_npc() -> void:
	var full_pool: Array[String] = [
		"washed_up_traveller", "elderly_baker", "failing_fisherman",
		"newcomer", "musician", "harbour_worker", "soup_regular",
		"quiet_farmer", "elderly_couple", "night_shift_guard",
		"lighthouse_keeper", "drifting_merchant", "strange_child", "storm_visitor"
	]
	
	var valid_pool: Array[String] = []
	for npc in full_pool:
		# Don't spawn if they are already present
		if npc in _present_npcs:
			continue
			
		var meta = DialogueManager.get_npc_meta(npc)
		var schedule: String = meta.get("schedule", "most_nights")
		if schedule == "fog_or_rain_only" and GameManager.current_weather not in ["fog", "rain"]:
			continue
		if schedule == "rain_only" and GameManager.current_weather != "rain":
			continue
		if schedule == "rare" and randf() > 0.3:
			continue
		valid_pool.append(npc)
		
	if valid_pool.is_empty():
		return
		
	var chosen = valid_pool[randi() % valid_pool.size()]
	spawn_npc(chosen)

# -----------------------------------------------------------------------
# Day transition animations
# -----------------------------------------------------------------------
func _build_day_transition_anims() -> void:
	_day_trans_anim = day_trans.get_node("AnimationPlayer") as AnimationPlayer
	var lib := AnimationLibrary.new()

	var fi := Animation.new()
	fi.length = 0.5
	var t1 := fi.add_track(Animation.TYPE_VALUE)
	fi.track_set_path(t1, "Fill:modulate:a")
	fi.track_insert_key(t1, 0.0, 0.0)
	fi.track_insert_key(t1, 0.5, 1.0)
	lib.add_animation("fade_in", fi)

	var fo := Animation.new()
	fo.length = 0.5
	var t2 := fo.add_track(Animation.TYPE_VALUE)
	fo.track_set_path(t2, "Fill:modulate:a")
	fo.track_insert_key(t2, 0.0, 1.0)
	fo.track_insert_key(t2, 0.5, 0.0)
	lib.add_animation("fade_out", fo)

	_day_trans_anim.add_animation_library("", lib)

# -----------------------------------------------------------------------
# Corkboard UI — now a scene instance ($CorkboardUI)
# -----------------------------------------------------------------------
func _toggle_corkboard() -> void:
	if not corkboard_ui.visible:
		if counter_view and counter_view.visible:
			return
		corkboard_ui.visible = true
		hud.visible = false
		if cooking_ui.visible:
			cooking_ui.visible = false
		if _recipe_book:
			_recipe_book.visible = false
		corkboard_ui.refresh()
	else:
		corkboard_ui.visible = false
		hud.visible = true

# -----------------------------------------------------------------------
# Audio Setup — loads and plays looping ocean ambience & music
# -----------------------------------------------------------------------
func _setup_audio() -> void:
	# Keep diner music looping
	var music_stream = _load_audio_with_fallbacks("res://Assets/Audio/diner_music")
	if music_stream:
		music_player.stream = music_stream
		if not music_player.finished.is_connected(music_player.play):
			music_player.finished.connect(music_player.play)
		music_player.play()
		
	# Start initial ambience
	_update_ambience()

func _update_ambience() -> void:
	var target_base := "res://Assets/Audio/ocean_ambience"
	if GameManager.current_weather == "rain":
		target_base = "res://Assets/Audio/light_rain_indoors"
	elif GameManager.current_phase == "night":
		target_base = "res://Assets/Audio/night_ambience"
		
	var target_stream := _load_audio_with_fallbacks(target_base)
	if target_stream == null:
		# Fallback to ocean ambience if rain/night are missing
		target_stream = _load_audio_with_fallbacks("res://Assets/Audio/ocean_ambience")
		if target_stream == null:
			return
			
	if ambience_player.stream == target_stream and ambience_player.playing:
		return
		
	# Smooth crossfade
	if _ambience_tween and _ambience_tween.is_valid():
		_ambience_tween.kill()
		
	_ambience_tween = create_tween()
	var target_vol := -12.0 # Quieter background ambience level
	if ambience_player.playing:
		_ambience_tween.tween_property(ambience_player, "volume_db", -80.0, 1.2)
		_ambience_tween.tween_callback(func():
			ambience_player.stop()
			ambience_player.stream = target_stream
			ambience_player.volume_db = -80.0
			ambience_player.play()
		)
		_ambience_tween.tween_property(ambience_player, "volume_db", target_vol, 1.2)
	else:
		ambience_player.stream = target_stream
		ambience_player.volume_db = -80.0
		ambience_player.play()
		_ambience_tween.tween_property(ambience_player, "volume_db", target_vol, 1.2)

	if not ambience_player.finished.is_connected(ambience_player.play):
		ambience_player.finished.connect(ambience_player.play)

func _setup_foghorn() -> void:
	_foghorn_timer = Timer.new()
	_foghorn_timer.wait_time = 45.0
	_foghorn_timer.one_shot = false
	_foghorn_timer.timeout.connect(_on_foghorn_timer_timeout)
	add_child(_foghorn_timer)
	_foghorn_timer.start()

func _on_foghorn_timer_timeout() -> void:
	var roll := randf()
	var chance := 0.10
	if GameManager.current_weather == "fog":
		chance = 0.40
		
	if roll < chance:
		_play_foghorn()

func _play_foghorn() -> void:
	var stream = _load_audio_with_fallbacks("res://Assets/Audio/foghorn")
	if stream == null:
		return
		
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -12.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func _load_audio_with_fallbacks(base_path: String) -> AudioStream:
	for ext in [".mp3", ".ogg", ".wav"]:
		var path = base_path + ext
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null
