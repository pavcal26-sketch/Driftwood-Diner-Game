extends CanvasLayer

# Corkboard UI — a visual pinboard where lore items are displayed as
# scattered note cards with pushpins. Click a card to read its full
# description in the detail panel on the right.

signal closed

# Node references — assigned in _ready from code-built UI
var _board_container: Control       # the main cork area where cards scatter
var _detail_title: Label
var _detail_giver: Label
var _detail_desc: RichTextLabel
var _detail_panel: PanelContainer
var _empty_label: Label

# Card tracking
var _cards: Array[Control] = []
var _selected_card: Control = null

# Preloaded textures
var _pin_texture: Texture2D = null

# Layout constants
const CARD_SIZE := Vector2(200, 120)
const BOARD_MARGIN := Vector2(40, 40)

# Cork-toned colors for the note cards — each NPC gets a distinct tint
const CARD_TINTS: Dictionary = {
	"washed_up_traveller":  Color(0.75, 0.82, 0.90, 0.92),  # pale blue — sea-worn
	"elderly_baker":        Color(0.92, 0.85, 0.72, 0.92),  # warm parchment
	"failing_fisherman":    Color(0.70, 0.80, 0.78, 0.92),  # muted teal
	"newcomer":             Color(0.82, 0.88, 0.75, 0.92),  # soft green
	"musician":             Color(0.88, 0.78, 0.85, 0.92),  # dusty rose
	"storm_visitor":        Color(0.72, 0.72, 0.80, 0.92),  # cold grey-blue
	"lighthouse_keeper":    Color(0.90, 0.82, 0.65, 0.92),  # amber
	"drifting_merchant":    Color(0.85, 0.75, 0.68, 0.92),  # warm brown
}
const DEFAULT_TINT := Color(0.85, 0.83, 0.78, 0.92)  # neutral cream

func _ready() -> void:
	layer = 10
	visible = false
	_pin_texture = _try_load("res://Assets/corkboard/pushpin.png")
	_build_ui()

func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

# -----------------------------------------------------------------------
# Build the entire UI in code — keeps it self-contained
# -----------------------------------------------------------------------
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Cork background texture
	var bg_tex: Texture2D = _try_load("res://Assets/corkboard/corkboard_bg.png")
	if bg_tex:
		var bg := TextureRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.texture = bg_tex
		bg.expand_mode = 1  # EXPAND_IGNORE_SIZE
		bg.stretch_mode = 6 # KEEP_ASPECT_COVERED
		root.add_child(bg)
	else:
		# Fallback — warm brown color
		var bg := ColorRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.color = Color(0.35, 0.25, 0.18, 1.0)
		root.add_child(bg)

	# Dim vignette overlay for depth
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0, 0, 0, 0.15)
	root.add_child(vignette)

	# Title pinned to the top
	var title_card := PanelContainer.new()
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = Color(0.92, 0.88, 0.78, 0.95)
	title_style.border_color = Color(0.6, 0.5, 0.4, 0.4)
	title_style.set_border_width_all(1)
	title_style.set_corner_radius_all(2)
	title_style.set_content_margin_all(12)
	title_card.add_theme_stylebox_override("panel", title_style)
	title_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_card.position = Vector2(860, 20)
	title_card.custom_minimum_size = Vector2(200, 40)
	root.add_child(title_card)

	var title_lbl := Label.new()
	title_lbl.text = "THE CORKBOARD"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.25, 0.20, 0.15))
	title_card.add_child(title_lbl)

	# Pin on the title card
	if _pin_texture:
		var pin := TextureRect.new()
		pin.texture = _pin_texture
		pin.position = Vector2(90, -12)
		pin.z_index = 5
		title_card.add_child(pin)

	# Main horizontal split — board area (left 65%) + detail panel (right 35%)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.set_anchor(SIDE_TOP, 0.08)
	hbox.set_anchor(SIDE_BOTTOM, 0.92)
	hbox.set_anchor(SIDE_LEFT, 0.02)
	hbox.set_anchor(SIDE_RIGHT, 0.98)
	hbox.add_theme_constant_override("separation", 16)
	root.add_child(hbox)

	# Board area — where cards scatter
	_board_container = Control.new()
	_board_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_container.size_flags_stretch_ratio = 0.62
	_board_container.clip_contents = true
	hbox.add_child(_board_container)

	# Empty board message
	_empty_label = Label.new()
	_empty_label.text = "The board is empty.\n\nListen to visitors;\nsome may give you notes\nor objects to pin up."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_label.add_theme_font_size_override("font_size", 18)
	_empty_label.add_theme_color_override("font_color", Color(0.55, 0.45, 0.35, 0.7))
	_board_container.add_child(_empty_label)

	# Detail panel — right side
	_detail_panel = PanelContainer.new()
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_stretch_ratio = 0.38
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(0.90, 0.86, 0.78, 0.95)
	detail_style.border_color = Color(0.5, 0.4, 0.3, 0.5)
	detail_style.set_border_width_all(2)
	detail_style.set_corner_radius_all(3)
	detail_style.set_content_margin_all(20)
	# subtle shadow
	detail_style.shadow_color = Color(0, 0, 0, 0.2)
	detail_style.shadow_size = 6
	_detail_panel.add_theme_stylebox_override("panel", detail_style)
	hbox.add_child(_detail_panel)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 10)
	_detail_panel.add_child(detail_vbox)

	# Detail title
	_detail_title = Label.new()
	_detail_title.text = "Select an item to inspect"
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_title.add_theme_color_override("font_color", Color(0.25, 0.20, 0.15))
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_vbox.add_child(_detail_title)

	# Detail giver
	_detail_giver = Label.new()
	_detail_giver.text = ""
	_detail_giver.add_theme_font_size_override("font_size", 13)
	_detail_giver.add_theme_color_override("font_color", Color(0.45, 0.38, 0.30))
	detail_vbox.add_child(_detail_giver)

	# Separator
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(0.5, 0.42, 0.35, 0.4)
	detail_vbox.add_child(sep)

	# Description
	_detail_desc = RichTextLabel.new()
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_desc.bbcode_enabled = true
	_detail_desc.text = ""
	_detail_desc.add_theme_font_size_override("normal_font_size", 15)
	_detail_desc.add_theme_color_override("default_color", Color(0.20, 0.18, 0.15))
	detail_vbox.add_child(_detail_desc)

	# Close button at the bottom of the detail panel
	var close_btn := Button.new()
	close_btn.text = "Close  [ K ]"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(func(): closed.emit())
	detail_vbox.add_child(close_btn)

# -----------------------------------------------------------------------
# Refresh — called when opening the corkboard
# -----------------------------------------------------------------------
func refresh() -> void:
	_clear_cards()

	var items: Array = DialogueManager.get_pinned_items()
	_empty_label.visible = items.is_empty()

	if items.is_empty():
		_detail_title.text = "Select an item to inspect"
		_detail_giver.text = ""
		_detail_desc.text = ""
		return

	# Scatter cards across the board with slight random rotation and offset
	var board_size: Vector2 = _board_container.size
	if board_size.x < 100:
		# fallback if container hasn't been laid out yet
		board_size = Vector2(1200, 800)

	# Calculate a loose grid with randomness
	var cols: int = maxi(1, int(board_size.x / (CARD_SIZE.x + 30)))
	var rows: int = maxi(1, int(board_size.y / (CARD_SIZE.y + 20)))

	for i in range(items.size()):
		var item_id: String = items[i]
		var item_data: Dictionary = DialogueManager.get_corkboard_item(item_id)
		if item_data.is_empty():
			continue
		_create_card(item_id, item_data, i, board_size, cols, rows)

func _clear_cards() -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()
	_selected_card = null

func _create_card(item_id: String, item_data: Dictionary, index: int, board_size: Vector2, cols: int, rows: int) -> void:
	var giver: String = item_data.get("giver", "unknown")
	var label: String = item_data.get("label", item_id.replace("_", " ").capitalize())

	# Position — grid-based with jitter so it looks natural, not mechanical
	var col: int = index % cols
	var row: int = index / cols
	var cell_w: float = board_size.x / float(cols)
	var cell_h: float = board_size.y / float(rows + 1)
	var base_x: float = col * cell_w + (cell_w - CARD_SIZE.x) * 0.5
	var base_y: float = row * cell_h + (cell_h - CARD_SIZE.y) * 0.5
	var jitter_x: float = randf_range(-25, 25)
	var jitter_y: float = randf_range(-15, 15)
	var pos := Vector2(
		clampf(base_x + jitter_x, BOARD_MARGIN.x, board_size.x - CARD_SIZE.x - BOARD_MARGIN.x),
		clampf(base_y + jitter_y, BOARD_MARGIN.y, board_size.y - CARD_SIZE.y - BOARD_MARGIN.y)
	)

	# Card container
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	var tint: Color = CARD_TINTS.get(giver, DEFAULT_TINT)
	card_style.bg_color = tint
	card_style.border_color = Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 0.5)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(2)
	card_style.set_content_margin_all(10)
	# subtle paper shadow
	card_style.shadow_color = Color(0, 0, 0, 0.25)
	card_style.shadow_size = 4
	card_style.shadow_offset = Vector2(2, 3)
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.position = pos

	# Slight random rotation for that scattered-papers look
	var angle: float = randf_range(-0.06, 0.06)  # ~3.5 degrees max
	card.rotation = angle
	card.pivot_offset = CARD_SIZE * 0.5

	# Card content
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = label
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.20, 0.18, 0.15))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.custom_minimum_size.y = 36
	vbox.add_child(title_lbl)

	# Thin line
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = Color(0.4, 0.35, 0.30, 0.3)
	vbox.add_child(line)

	var giver_lbl := Label.new()
	giver_lbl.text = "— " + giver.replace("_", " ").capitalize()
	giver_lbl.add_theme_font_size_override("font_size", 11)
	giver_lbl.add_theme_color_override("font_color", Color(0.40, 0.35, 0.30, 0.7))
	vbox.add_child(giver_lbl)

	# Preview text — first 60 chars of description
	var desc: String = item_data.get("description", "")
	var preview: String = desc.substr(0, 55) + "..." if desc.length() > 55 else desc
	var preview_lbl := Label.new()
	preview_lbl.text = preview
	preview_lbl.add_theme_font_size_override("font_size", 10)
	preview_lbl.add_theme_color_override("font_color", Color(0.35, 0.30, 0.25, 0.6))
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_lbl.clip_text = true
	preview_lbl.custom_minimum_size.y = 30
	vbox.add_child(preview_lbl)

	# Pushpin at the top
	if _pin_texture:
		var pin := TextureRect.new()
		pin.texture = _pin_texture
		pin.position = Vector2(CARD_SIZE.x * 0.5 - 16 + randf_range(-20, 20), -14)
		pin.z_index = 5
		card.add_child(pin)

	# Make it clickable
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(card, item_data))

	# Hover effect
	card.mouse_entered.connect(_on_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_card_hover.bind(card, false))

	_board_container.add_child(card)
	_cards.append(card)

	# Entrance animation — cards float in from slightly below
	card.modulate.a = 0.0
	card.position.y += 20
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(index * 0.08)
	tw.parallel().tween_property(card, "position:y", pos.y, 0.4).set_delay(index * 0.08)

func _on_card_input(event: InputEvent, card: Control, item_data: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_card(card, item_data)

func _on_card_hover(card: Control, entered: bool) -> void:
	if card == _selected_card:
		return
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if entered:
		tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.15)
		card.z_index = 10
	else:
		tw.tween_property(card, "scale", Vector2.ONE, 0.15)
		card.z_index = 0

func _select_card(card: Control, item_data: Dictionary) -> void:
	# Deselect previous
	if _selected_card != null and is_instance_valid(_selected_card):
		var tw := create_tween().set_ease(Tween.EASE_OUT)
		tw.tween_property(_selected_card, "scale", Vector2.ONE, 0.15)
		_selected_card.z_index = 0

	_selected_card = card
	card.z_index = 15

	# Pop animation
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(card, "scale", Vector2(1.08, 1.08), 0.2)

	# Fill detail panel
	var label: String = item_data.get("label", "Unknown Item")
	var giver: String = item_data.get("giver", "unknown")
	var tier: int = item_data.get("tier_given", 0)
	var desc: String = item_data.get("description", "")

	_detail_title.text = label
	_detail_giver.text = "Given by: %s  ·  Tier %d" % [giver.replace("_", " ").capitalize(), tier]
	_detail_desc.text = desc

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("action_corkboard"):
		closed.emit()
		get_viewport().set_input_as_handled()
