extends CanvasLayer

# Tutorial system — contextual hints that appear as the player
# encounters each game system for the first time. Shows as a
# warm parchment-style overlay at the bottom of the screen.
# Tracks completion so hints only show once per save.

var _panel: PanelContainer
var _label: RichTextLabel
var _close_hint: Label
var _active: bool = false
var _current_step: String = ""

# Which tutorials have been shown — persisted with save data
var _completed: Array[String] = []

# Tutorial content — keyed by trigger name
const TUTORIALS: Dictionary = {
	"welcome": {
		"text": "[b]Welcome to the Driftwood Diner[/b]\n\nYou've washed ashore on a fog-covered island and found an abandoned diner. Visitors will come — feed them, listen to their stories, and decide whether to stay or leave.\n\n[color=#b8a080]Click anywhere or press any key to continue.[/color]",
		"delay": 0.5,
	},
	"first_npc": {
		"text": "[b]A Visitor Arrives[/b]\n\nSomeone's walked in. They'll take a seat, then approach the counter to talk.\n[b]Click through their dialogue first to hear their order.[/b]\n\n[color=#b8a080]Once the conversation ends, open the [b]Kitchen[/b] (C key or button) to cook.[/color]",
		"delay": 0.5,
	},
	"cooking_opened": {
		"text": "[b]The Kitchen[/b]\n\nClick ingredients on the left to place them on the workspace.\n[b]Drag items onto each other[/b] to combine them into dishes.\n\nNew combinations are discovered by experimenting — try everything.\nDishes are marked with a ★ star.\n\n[color=#b8a080]Once you have a ★ dish, click a waiting NPC's name to serve it.[/color]",
		"delay": 0.3,
	},
	"first_serve": {
		"text": "[b]Served![/b]\n\nEach NPC has food preferences — serving the right dish earns more money and better reactions. Wrong dishes still work, but the NPC won't be happy about it.\n\nYour savings are shown in the top-right. You'll need them later.\n\n[color=#b8a080]Keep cooking and serving to build relationships.[/color]",
		"delay": 0.5,
	},
	"first_corkboard_item": {
		"text": "[b]Something for the Corkboard[/b]\n\nAn NPC gave you a lore item. Open the [b]Corkboard[/b] (K key or button) to see it pinned up.\n\nCollect more items to piece together the island's story. Some NPCs unlock new dialogue when you've pinned enough items.\n\n[color=#b8a080]The corkboard is the heart of the mystery.[/color]",
		"delay": 0.5,
	},
	"day_end": {
		"text": "[b]End of the Night[/b]\n\nWhen you're ready, press [b]End Night[/b] (N key or button) to advance to the next day.\n\nNew visitors arrive each day. Weather changes. Relationships deepen.\nSome NPCs only appear in storms.\n\n[color=#b8a080]The island has a rhythm. You'll learn it.[/color]",
		"delay": 0.3,
	},
	"recipe_book": {
		"text": "[b]Recipe Book[/b]\n\nAll your discovered combinations are recorded here.\nUse it to remember what you've found.\n\n[color=#b8a080]★ marks servable dishes. Everything else is an ingredient or intermediate.[/color]",
		"delay": 0.2,
	},
}

func _ready() -> void:
	layer = 20  # above everything
	visible = false
	_build_ui()
	_connect_triggers()

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(_on_dismiss)
	add_child(root)

	# Semi-transparent backdrop — doesn't fully darken, just draws focus
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.05, 0.45)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dimmer)

	# Parchment-style panel at the bottom
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.set_anchor(SIDE_LEFT, 0.15)
	_panel.set_anchor(SIDE_RIGHT, 0.85)
	_panel.set_anchor(SIDE_TOP, 0.62)
	_panel.set_anchor(SIDE_BOTTOM, 0.95)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.92, 0.88, 0.78, 0.96)
	style.border_color = Color(0.55, 0.45, 0.35, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(24)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 12
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override("normal_font_size", 16)
	_label.add_theme_font_size_override("bold_font_size", 18)
	_label.add_theme_color_override("default_color", Color(0.22, 0.18, 0.14))
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_label)

	_close_hint = Label.new()
	_close_hint.text = "Click anywhere to dismiss"
	_close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_close_hint.add_theme_font_size_override("font_size", 12)
	_close_hint.add_theme_color_override("font_color", Color(0.5, 0.42, 0.35, 0.6))
	vbox.add_child(_close_hint)

func _connect_triggers() -> void:
	# Hook into game signals to trigger tutorials contextually
	SignalBus.npc_at_counter.connect(_on_first_npc)
	SignalBus.npc_served.connect(_on_first_serve)
	SignalBus.corkboard_item_received.connect(_on_first_corkboard)

	# Welcome tutorial fires after a short delay on first load
	get_tree().create_timer(1.5).timeout.connect(_try_welcome)

func _try_welcome() -> void:
	show_tutorial("welcome")

func _on_first_npc(_npc_id: String) -> void:
	# slight delay so the NPC dialogue doesn't overlap
	get_tree().create_timer(0.3).timeout.connect(func():
		show_tutorial("first_npc")
	)

func _on_first_serve(_npc_id: String, _dish_id: String) -> void:
	get_tree().create_timer(1.0).timeout.connect(func():
		show_tutorial("first_serve")
	)

func _on_first_corkboard(_item_id: String) -> void:
	get_tree().create_timer(0.5).timeout.connect(func():
		show_tutorial("first_corkboard_item")
	)

# Called from Main.gd when specific UIs are opened
func on_cooking_opened() -> void:
	show_tutorial("cooking_opened")

func on_recipes_opened() -> void:
	show_tutorial("recipe_book")

func on_day_advanced() -> void:
	show_tutorial("day_end")

func show_tutorial(step: String) -> void:
	if step in _completed:
		return
	if _active:
		return  # don't stack tutorials
	if not TUTORIALS.has(step):
		return

	_completed.append(step)
	_current_step = step

	var data: Dictionary = TUTORIALS[step]
	_label.text = data.get("text", "")

	# Animate in
	_active = true
	visible = true
	_panel.modulate.a = 0.0
	_panel.position.y += 30
	var target_y: float = _panel.position.y - 30
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(_panel, "position:y", target_y, 0.4)

func _on_dismiss(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton and event.pressed:
		_dismiss()
	elif event is InputEventKey and event.pressed:
		_dismiss()

func _dismiss() -> void:
	if not _active:
		return
	_active = false

	var tw := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.2)
	tw.tween_property(_panel, "position:y", _panel.position.y + 20, 0.25)
	tw.tween_callback(func(): visible = false)

func _input(event: InputEvent) -> void:
	if not _active:
		return
	# Eat all input while tutorial is showing
	if event is InputEventKey and event.pressed:
		_dismiss()
		get_viewport().set_input_as_handled()

# Save/load
func get_save_data() -> Dictionary:
	return {"completed_tutorials": _completed}

func load_save_data(data: Dictionary) -> void:
	var loaded: Array = data.get("completed_tutorials", [])
	_completed.clear()
	for item in loaded:
		_completed.append(item as String)
