extends CanvasLayer

# Corkboard UI — a visual pinboard where lore items are displayed as
# scattered note cards with pushpins and item images. Click a card to
# read its full description in the detail panel on the right.

signal closed

# Node references — assigned in _ready from code-built UI
var _board_container: Control       # the main cork area where cards scatter
var _detail_title: Label
var _detail_giver: Label
var _detail_desc: RichTextLabel
var _detail_image: TextureRect      # item image in detail panel
var _detail_panel: PanelContainer
var _empty_label: Label

# Card tracking
var _cards: Array[Control] = []
var _selected_card: Control = null



# Layout constants — cards are now wider to fit image + text side by side
const CARD_SIZE := Vector2(190, 160)
const BOARD_MARGIN := Vector2(20, 40)

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
	_build_ui()

func _try_load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# fallback: try raw file load for non-imported assets
	var fa := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
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
	return ImageTexture.create_from_image(img)

# -----------------------------------------------------------------------
# Build the entire UI in code — keeps it self-contained
# -----------------------------------------------------------------------
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Cork background texture
	var bg_tex: Texture2D = _try_load_tex("res://Assets/corkboard/corkboard_bg.png")
	if bg_tex:
		var bg := TextureRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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





	# Main horizontal split — board area (left 62%) + detail panel (right 38%)
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
	_board_container.size_flags_stretch_ratio = 0.70
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
	_detail_panel.size_flags_stretch_ratio = 0.30
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(0.90, 0.86, 0.78, 0.95)
	detail_style.border_color = Color(0.5, 0.4, 0.3, 0.5)
	detail_style.set_border_width_all(2)
	detail_style.set_corner_radius_all(3)
	detail_style.set_content_margin_all(20)
	detail_style.shadow_color = Color(0, 0, 0, 0.2)
	detail_style.shadow_size = 6
	_detail_panel.add_theme_stylebox_override("panel", detail_style)
	hbox.add_child(_detail_panel)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 10)
	_detail_panel.add_child(detail_vbox)

	# Detail title
	_detail_title = Label.new()
	_detail_title.text = "— select an item to inspect —"
	_detail_title.add_theme_font_size_override("font_size", 22)
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

	# Detail image — shows the item's full-size image
	_detail_image = TextureRect.new()
	_detail_image.custom_minimum_size = Vector2(0, 180)
	_detail_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_image.visible = false
	detail_vbox.add_child(_detail_image)

	# Description
	_detail_desc = RichTextLabel.new()
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_desc.bbcode_enabled = true
	_detail_desc.text = ""
	_detail_desc.add_theme_font_size_override("normal_font_size", 15)
	_detail_desc.add_theme_color_override("default_color", Color(0.20, 0.18, 0.15))
	detail_vbox.add_child(_detail_desc)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close  [K]"
	close_btn.pressed.connect(func(): closed.emit())
	detail_vbox.add_child(close_btn)

# -----------------------------------------------------------------------
# Load item thumbnail — looks in Assets/corkboard/items/{item_id}.png
# -----------------------------------------------------------------------
func _load_item_image(item_id: String) -> Texture2D:
	var path := "res://Assets/corkboard/items/cb_%s.png" % item_id
	return _try_load_tex(path)

# -----------------------------------------------------------------------
# Refresh — called when opening the corkboard
# -----------------------------------------------------------------------
func refresh() -> void:
	_clear_cards()

	var items: Array = DialogueManager.get_pinned_items()
	_empty_label.visible = items.is_empty()

	if items.is_empty():
		_detail_title.text = "— select an item to inspect —"
		_detail_giver.text = ""
		_detail_desc.text = ""
		_detail_image.visible = false
		return

	# Scatter cards across the board
	var board_size: Vector2 = _board_container.size
	if board_size.x < 100:
		board_size = Vector2(1200, 800)

	var cols: int = maxi(1, int(board_size.x / (CARD_SIZE.x + 16)))
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
	var tint: Color = CARD_TINTS.get(giver, DEFAULT_TINT)

	# Position — grid with controlled jitter
	var col: int = index % cols
	var row: int = index / cols
	var cell_w: float = board_size.x / float(cols)
	var cell_h: float = board_size.y / float(rows)
	var base_x: float = col * cell_w + (cell_w - CARD_SIZE.x) * 0.5
	var base_y: float = row * cell_h + (cell_h - CARD_SIZE.y) * 0.5
	var jitter_x: float = randf_range(-10, 10)
	var jitter_y: float = randf_range(-8, 8)
	var pos := Vector2(
		clampf(base_x + jitter_x, BOARD_MARGIN.x, board_size.x - CARD_SIZE.x - BOARD_MARGIN.x),
		clampf(base_y + jitter_y, BOARD_MARGIN.y, board_size.y - CARD_SIZE.y - BOARD_MARGIN.y)
	)

	# ---- card root: plain Control with fixed size so it never expands ----
	var card := Control.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.clip_contents = false  # let pushpin poke out above
	card.position = pos

	# Slight random rotation
	var angle: float = randf_range(-0.05, 0.05)
	card.rotation = angle
	card.pivot_offset = CARD_SIZE * 0.5

	# ---- card face: PanelContainer fills the card rect ----
	var face := PanelContainer.new()
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = tint
	card_style.border_color = Color(tint.r * 0.65, tint.g * 0.65, tint.b * 0.65, 0.55)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(2)
	card_style.set_content_margin_all(0)  # we manage padding manually
	card_style.shadow_color = Color(0, 0, 0, 0.30)
	card_style.shadow_size = 5
	card_style.shadow_offset = Vector2(2, 3)
	face.add_theme_stylebox_override("panel", card_style)
	card.add_child(face)

	# ---- portrait layout: VBox inside the face ----
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	face.add_child(vbox)

	# Image area — fixed height 90px
	var item_tex: Texture2D = _load_item_image(item_id)
	if item_tex:
		var img_rect := TextureRect.new()
		img_rect.texture = item_tex
		img_rect.custom_minimum_size = Vector2(0, 96)
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		img_rect.clip_contents = true
		vbox.add_child(img_rect)
	else:
		# Tinted placeholder block
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(0, 96)
		placeholder.color = Color(tint.r * 0.80, tint.g * 0.80, tint.b * 0.80, 0.9)
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(placeholder)

	# Thin rule between image and text
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0.4)
	vbox.add_child(rule)

	# Text area — padded container
	var text_margin := MarginContainer.new()
	text_margin.add_theme_constant_override("margin_left", 7)
	text_margin.add_theme_constant_override("margin_right", 7)
	text_margin.add_theme_constant_override("margin_top", 5)
	text_margin.add_theme_constant_override("margin_bottom", 5)
	text_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(text_margin)

	var text_vbox := VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 2)
	text_margin.add_child(text_vbox)

	var title_lbl := Label.new()
	title_lbl.text = label
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.18, 0.15, 0.12))
	title_lbl.clip_text = true              # single line, no height expansion
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_child(title_lbl)

	var giver_lbl := Label.new()
	giver_lbl.text = "— " + giver.replace("_", " ").capitalize()
	giver_lbl.add_theme_font_size_override("font_size", 9)
	giver_lbl.add_theme_color_override("font_color", Color(0.35, 0.30, 0.25, 0.75))
	giver_lbl.clip_text = true
	giver_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_child(giver_lbl)

	# ---- pushpin: sits centered at the top edge, poking above ----
	var pin_tex: Texture2D = _try_load_tex("res://Assets/corkboard/pushpin.png")
	if pin_tex:
		var pin := TextureRect.new()
		pin.texture = pin_tex
		pin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pin.custom_minimum_size = Vector2(18, 24)
		pin.size = Vector2(18, 24)
		pin.position = Vector2((CARD_SIZE.x - 18.0) * 0.5, -12.0)
		pin.z_index = 2
		card.add_child(pin)  # add to card (not face) so it sits on top

	# ---- interactivity ----
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(card, item_id, item_data))
	card.mouse_entered.connect(_on_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_card_hover.bind(card, false))

	_board_container.add_child(card)
	_cards.append(card)

	# Entrance animation — float in from slightly below
	card.modulate.a = 0.0
	card.position.y += 18
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(card, "modulate:a", 1.0, 0.28).set_delay(index * 0.06)
	tw.parallel().tween_property(card, "position:y", pos.y, 0.35).set_delay(index * 0.06)

func _on_card_input(event: InputEvent, card: Control, item_id: String, item_data: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_card(card, item_id, item_data)

func _on_card_hover(card: Control, entered: bool) -> void:
	if card == _selected_card:
		return
	var tw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if entered:
		tw.tween_property(card, "scale", Vector2(1.04, 1.04), 0.12)
		card.z_index = 10
	else:
		tw.tween_property(card, "scale", Vector2.ONE, 0.12)
		card.z_index = 0

func _select_card(card: Control, item_id: String, item_data: Dictionary) -> void:
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

	# Show full-size item image in detail panel
	var full_tex: Texture2D = _load_item_image(item_id)
	if full_tex:
		_detail_image.texture = full_tex
		_detail_image.visible = true
	else:
		_detail_image.visible = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("action_corkboard"):
		closed.emit()
		get_viewport().set_input_as_handled()
