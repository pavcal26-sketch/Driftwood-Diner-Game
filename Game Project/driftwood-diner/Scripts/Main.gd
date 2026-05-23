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
@onready var background   : Sprite2D       = $Diner/Background

var _recipe_book: CanvasLayer = null
var _recipe_list: VBoxContainer = null   # direct ref — avoids fragile node-path lookup
var _dialogue_opened_cooking: bool = false  # track whether we should reopen cooking UI after dialogue

var _corkboard_ui: CanvasLayer = null
var _corkboard_list: VBoxContainer = null
var _corkboard_detail_title: Label = null
var _corkboard_detail_giver: Label = null
var _corkboard_detail_desc: RichTextLabel = null

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

var _rain_particles: CPUParticles2D

func _ready() -> void:
	_build_day_transition_anims()
	_setup_weather_effects()
	_connect_signals()
	_apply_phase(GameManager.current_phase)
	_apply_weather(GameManager.current_weather)
	_fit_background()
	_build_recipe_book()
	_build_corkboard_ui()

	# first night
	await get_tree().create_timer(2.0).timeout
	spawn_npc("washed_up_traveller")

func _fit_background() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if background.texture == null:
		return
	var tex_size: Vector2 = background.texture.get_size()
	var scale_x: float = vp.x / tex_size.x
	var scale_y: float = vp.y / tex_size.y
	var s: float = maxf(scale_x, scale_y)
	background.scale    = Vector2(s, s)
	background.position = vp * 0.5

	# compute where the visual floor is in world space
	# the diner floor is approximately 73% down the texture
	var floor_frac: float = 0.73
	var tex_floor_y: float = tex_size.y * floor_frac           # pixels from top in texture
	var offset_from_center: float = tex_floor_y - tex_size.y * 0.5
	_floor_y    = vp.y * 0.5 + offset_from_center * s
	_counter_x  = vp.x * 0.30   # 30% from left — in front of the bar, not behind it
	_offscreen_x = vp.x + 200.0  # just off right edge

func _connect_signals() -> void:
	SignalBus.day_phase_changed.connect(_apply_phase)
	SignalBus.day_phase_changed.connect(_schedule_phase_spawns)
	SignalBus.weather_changed.connect(_apply_weather)
	SignalBus.npc_at_counter.connect(_on_npc_at_counter)
	SignalBus.npc_requests_counter.connect(_on_npc_requests_counter)
	SignalBus.npc_left_counter.connect(_on_npc_left_counter)
	SignalBus.dialogue_finished.connect(_on_dialogue_finished)
	SignalBus.npc_arrived.connect(func(id: String): _present_npcs.append(id))
	SignalBus.npc_departed.connect(_on_npc_departed)
	SignalBus.savings_changed.connect(func(v: int): hud.update_savings(v))
	SignalBus.day_advanced.connect(func(d: int): hud.update_day(d))

	hud.cooking_pressed.connect(_toggle_cooking)
	hud.recipes_pressed.connect(_toggle_recipes)
	hud.corkboard_pressed.connect(_toggle_corkboard)
	hud.advance_pressed.connect(_advance_day)
	cooking_ui.closed.connect(_toggle_cooking)

func _input(event: InputEvent) -> void:
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

# -----------------------------------------------------------------------
# NPC spawning with unique seats
# -----------------------------------------------------------------------
func spawn_npc(npc_id: String) -> void:
	if npc_id in _present_npcs:
		return

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
	# let the next queued NPC approach
	if not _counter_queue.is_empty():
		var next_id: String = _counter_queue.pop_front()
		# make sure they're still present
		if next_id in _present_npcs:
			_grant_counter(next_id)
		elif not _counter_queue.is_empty():
			_on_npc_left_counter("")  # try next

func _on_npc_at_counter(npc_id: String) -> void:
	var meta     : Dictionary = DialogueManager.get_npc_meta(npc_id)
	var lines    : Array      = DialogueManager.get_lines(npc_id)
	var name_str : String     = meta.get("display_name",
		npc_id.replace("_", " ").capitalize())
	# hide cooking UI and HUD during pre-serve dialogue; mark that we should reopen it when done
	_dialogue_opened_cooking = cooking_ui.visible
	cooking_ui.visible = false
	hud.visible = false
	counter_view.show_npc(npc_id, lines, name_str)

func _on_dialogue_finished(_npc_id: String) -> void:
	# only restore cooking UI if it was visible before the dialogue, AND this
	# isn't a post-serve reaction (those come from npc_reaction signal, which
	# CounterView handles independently — cooking_ui should stay visible during them)
	if _dialogue_opened_cooking:
		cooking_ui.visible = true
		hud.visible = false
		_dialogue_opened_cooking = false
	else:
		hud.visible = true

func _on_npc_departed(npc_id: String) -> void:
	_present_npcs.erase(npc_id)
	_used_seats.erase(npc_id)
	_counter_queue.erase(npc_id)

# -----------------------------------------------------------------------
# Phase / Weather
# -----------------------------------------------------------------------
func _setup_weather_effects() -> void:
	_rain_particles = CPUParticles2D.new()
	_rain_particles.emitting = false
	_rain_particles.amount = 300
	_rain_particles.lifetime = 1.2
	_rain_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain_particles.emission_rect_extents = Vector2(1200, 10)
	_rain_particles.position = Vector2(960, -50)
	_rain_particles.direction = Vector2(-0.2, 1.0)
	_rain_particles.spread = 2.0
	_rain_particles.gravity = Vector2(0, 1200)
	_rain_particles.initial_velocity_min = 600.0
	_rain_particles.initial_velocity_max = 800.0
	_rain_particles.scale_amount_min = 2.0
	_rain_particles.scale_amount_max = 4.5
	_rain_particles.color = Color(0.6, 0.75, 0.95, 0.5)
	windows.add_child(_rain_particles)

func _apply_phase(phase: String) -> void:
	var target_color := Color.WHITE
	var day_alpha := 0.0
	var night_alpha := 0.0

	match phase:
		"day":
			target_color = Color(1.0, 0.96, 0.88, 1.0)
			day_alpha = 1.0
			night_alpha = 0.0
		"evening":
			target_color = Color(0.95, 0.75, 0.60, 1.0)
			day_alpha = 1.0
			night_alpha = 0.5
		"night":
			target_color = Color(0.35, 0.40, 0.60, 1.0) # Much darker and moodier for night
			day_alpha = 0.0
			night_alpha = 1.0

	var t = create_tween().set_parallel(true)
	t.tween_property(canvas_mod, "color", target_color, 8.0)
	var day_win = windows.get_node("Day")
	var night_win = windows.get_node("Night")
	day_win.visible = true
	night_win.visible = true
	t.tween_property(day_win, "modulate:a", day_alpha, 8.0)
	t.tween_property(night_win, "modulate:a", night_alpha, 8.0)

func _apply_weather(weather: String) -> void:
	var fog = windows.get_node("FogOverlay")
	var static_rain = windows.get_node("Rain")
	static_rain.visible = false

	fog.visible = true
	var t = create_tween()
	if weather == "fog":
		t.tween_property(fog, "modulate:a", 0.6, 5.0)
	else:
		t.tween_property(fog, "modulate:a", 0.0, 5.0)

	if _rain_particles:
		_rain_particles.emitting = (weather == "rain")

# -----------------------------------------------------------------------
# UI
# -----------------------------------------------------------------------
func _toggle_cooking() -> void:
	cooking_ui.visible = not cooking_ui.visible
	hud.visible = not cooking_ui.visible
	if _recipe_book:
		_recipe_book.visible = false

func _toggle_recipes() -> void:
	if _recipe_book == null:
		return
	_recipe_book.visible = not _recipe_book.visible
	hud.visible = not _recipe_book.visible
	if cooking_ui.visible:
		cooking_ui.visible = false
	_refresh_recipe_book()

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
	if _corkboard_ui:
		_corkboard_ui.visible = false
	hud.visible = true

func _advance_day() -> void:
	if _transitioning:
		return
	_do_day_transition()

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

func _schedule_phase_spawns(phase: String) -> void:
	if _transitioning:
		return
		
	var full_pool: Array[String] = [
		"washed_up_traveller", "elderly_baker", "failing_fisherman",
		"newcomer", "musician", "harbour_worker", "soup_regular",
		"quiet_farmer", "elderly_couple", "night_shift_guard",
		"lighthouse_keeper", "drifting_merchant", "strange_child"
	]
	
	var count: int = randi_range(1, 2)
	if phase == "night":
		count = randi_range(1, 3)
		
	var shuffled: Array[String] = full_pool.duplicate()
	shuffled.shuffle()

	for i in range(mini(count, shuffled.size())):
		var delay = randf_range(2.0, 15.0) if phase != "night" else randf_range(2.0, 8.0)
		get_tree().create_timer(delay).timeout.connect(func():
			if not _transitioning:
				spawn_npc(shuffled[i])
		)

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
# Corkboard UI
# -----------------------------------------------------------------------
func _toggle_corkboard() -> void:
	if _corkboard_ui == null:
		return
	_corkboard_ui.visible = not _corkboard_ui.visible
	hud.visible = not _corkboard_ui.visible
	if cooking_ui.visible:
		cooking_ui.visible = false
	if _recipe_book:
		_recipe_book.visible = false
	_refresh_corkboard()

func _build_corkboard_ui() -> void:
	_corkboard_ui = CanvasLayer.new()
	_corkboard_ui.layer = 9
	_corkboard_ui.visible = false
	add_child(_corkboard_ui)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_corkboard_ui.add_child(root)

	# Backdrop - dark warm cork/wood brown
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.12, 0.09, 0.08, 0.95)
	root.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.set_anchor(SIDE_LEFT,   0.08)
	panel.set_anchor(SIDE_TOP,    0.05)
	panel.set_anchor(SIDE_RIGHT,  0.92)
	panel.set_anchor(SIDE_BOTTOM, 0.95)
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   32)
	margin.add_theme_constant_override("margin_right",  32)
	margin.add_theme_constant_override("margin_top",    24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "THE CORKBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(1.0, 0.85, 0.6)  # Warm golden tint
	vbox.add_child(title)

	# Main Split Layout
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	# Left side: Scroll List of Pinned Items
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.4
	hbox.add_child(left_panel)

	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 12)
	left_margin.add_theme_constant_override("margin_right", 12)
	left_margin.add_theme_constant_override("margin_top", 12)
	left_margin.add_theme_constant_override("margin_bottom", 12)
	left_panel.add_child(left_margin)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_vbox)

	var list_title := Label.new()
	list_title.text = "Pinned Notes & Items"
	list_title.add_theme_font_size_override("font_size", 16)
	list_title.modulate = Color(0.8, 0.8, 0.8)
	left_vbox.add_child(list_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	_corkboard_list = VBoxContainer.new()
	_corkboard_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_corkboard_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_corkboard_list)

	# Right side: Detail View
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.6
	hbox.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 20)
	right_margin.add_theme_constant_override("margin_right", 20)
	right_margin.add_theme_constant_override("margin_top", 20)
	right_margin.add_theme_constant_override("margin_bottom", 20)
	right_panel.add_child(right_margin)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 12)
	right_margin.add_child(right_vbox)

	_corkboard_detail_title = Label.new()
	_corkboard_detail_title.text = "Select an item to inspect"
	_corkboard_detail_title.add_theme_font_size_override("font_size", 20)
	_corkboard_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_corkboard_detail_title.modulate = Color(0.95, 0.9, 0.8)
	right_vbox.add_child(_corkboard_detail_title)

	_corkboard_detail_giver = Label.new()
	_corkboard_detail_giver.text = ""
	_corkboard_detail_giver.add_theme_font_size_override("font_size", 14)
	_corkboard_detail_giver.modulate = Color(0.6, 0.6, 0.6)
	right_vbox.add_child(_corkboard_detail_giver)

	# Horizontal separator
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(0.3, 0.25, 0.22)
	right_vbox.add_child(sep)

	_corkboard_detail_desc = RichTextLabel.new()
	_corkboard_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_corkboard_detail_desc.bbcode_enabled = true
	_corkboard_detail_desc.text = ""
	_corkboard_detail_desc.add_theme_font_size_override("normal_font_size", 16)
	right_vbox.add_child(_corkboard_detail_desc)

	# Footer close button
	var close_btn := Button.new()
	close_btn.text = "Close  [ K ]"
	close_btn.pressed.connect(_toggle_corkboard)
	vbox.add_child(close_btn)

func _refresh_corkboard() -> void:
	if _corkboard_ui == null or _corkboard_list == null:
		return
		
	# Clear list
	for child in _corkboard_list.get_children():
		child.queue_free()
		
	# Set detail defaults
	_corkboard_detail_title.text = "Select an item to inspect"
	_corkboard_detail_giver.text = ""
	_corkboard_detail_desc.text = ""
	
	var items: Array = DialogueManager._pinned_corkboard
	if items.is_empty():
		var lbl := Label.new()
		lbl.text = "The board is empty.\n\nListen to visitors; some may give you notes or objects to pin up."
		lbl.modulate = Color(0.5, 0.5, 0.5)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_corkboard_list.add_child(lbl)
		return
		
	for item_id: String in items:
		var item_data := DialogueManager.get_corkboard_item(item_id)
		if item_data.is_empty():
			continue
			
		var btn := Button.new()
		btn.text = item_data.get("label", item_id.replace("_", " ").capitalize())
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_show_corkboard_detail.bind(item_data))
		_corkboard_list.add_child(btn)

func _show_corkboard_detail(item_data: Dictionary) -> void:
	var label: String = item_data.get("label", "Unknown Item")
	var giver: String = item_data.get("giver", "unknown")
	var tier: int = item_data.get("tier_given", 0)
	var desc: String = item_data.get("description", "")
	
	_corkboard_detail_title.text = label
	_corkboard_detail_giver.text = "Given by: %s (Tier %d)" % [giver.replace("_", " ").capitalize(), tier]
	_corkboard_detail_desc.text = desc
