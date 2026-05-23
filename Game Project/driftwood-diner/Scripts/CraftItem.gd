class_name CraftItem
extends PanelContainer

# Draggable item on the crafting workspace.
# Label mouse filter set to IGNORE so clicks always hit the panel.

var item_id: String = ""
var is_dish: bool = false
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO  # to distinguish tap vs drag
var label: Label = null

func setup(id: String, dish: bool = false) -> void:
	item_id = id
	is_dish = dish
	custom_minimum_size = Vector2(130, 42)

	label = get_node_or_null("Label")
	if label == null:
		label = Label.new()
		label.name = "Label"
		add_child(label)

	# critical — let clicks pass through to the PanelContainer
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var display: String = id.replace("_", " ").capitalize()
	label.text = ("★ " + display) if dish else display
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if dish:
		modulate = Color(1.0, 0.92, 0.65)
	else:
		modulate = Color(0.85, 0.92, 1.0)

	mouse_filter = Control.MOUSE_FILTER_STOP
	# stay in global space so position doesn't shift when reparented mid-drag
	set_as_top_level(true)

	# spawn animation — pop in from nothing
	scale = Vector2.ZERO
	var tw: Tween = create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector2.ONE, 0.25)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				_drag_start_pos = get_global_mouse_position()
				var p: Node = get_parent()
				if p:
					p.move_child(self, p.get_child_count() - 1)
				var tw: Tween = create_tween()
				tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.1)
			else:
				_dragging = false
				var tw: Tween = create_tween()
				tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
				tw.tween_property(self, "scale", Vector2.ONE, 0.2)
				var moved: float = _drag_start_pos.distance_to(get_global_mouse_position())
				if moved < 8.0 and is_dish:
					# tap on a dish = select it for serving
					var cui: Node = _find_cooking_ui()
					if cui and cui.has_method("select_dish"):
						cui.select_dish(self)
				else:
					_check_overlap()
			accept_event()

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var tw: Tween = create_tween()
			tw.tween_property(self, "scale", Vector2.ZERO, 0.15)
			tw.tween_callback(queue_free)
			accept_event()

func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		global_position = get_global_mouse_position() - _drag_offset
		get_viewport().set_input_as_handled()

func _check_overlap() -> void:
	var my_rect: Rect2 = get_global_rect()
	var workspace: Node = get_parent()
	if workspace == null:
		return
	for child in workspace.get_children():
		if child == self or not (child is CraftItem):
			continue
		var other: CraftItem = child as CraftItem
		if my_rect.intersects(other.get_global_rect()):
			_try_combine_with(other)
			return

func _try_combine_with(other: CraftItem) -> void:
	var result: String = CombinationDB.try_combine(item_id, other.item_id)
	if result == "":
		# fail — shake both items apart
		var push: Vector2 = (position - other.position).normalized() * 40.0
		var tw1: Tween = create_tween()
		tw1.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		tw1.tween_property(self, "position", position + push, 0.3)
		var tw2: Tween = other.create_tween()
		tw2.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
		tw2.tween_property(other, "position", other.position - push, 0.3)
		# red flash
		modulate = Color(1.0, 0.4, 0.4)
		other.modulate = Color(1.0, 0.4, 0.4)
		var tw3: Tween = create_tween()
		tw3.tween_property(self, "modulate", _base_color(), 0.4)
		var tw4: Tween = other.create_tween()
		tw4.tween_property(other, "modulate", other._base_color(), 0.4)
		return

	# success!
	var mid_pos: Vector2 = (position + other.position) / 2.0
	var result_is_dish: bool = CombinationDB.is_valid_dish(result)

	# notify CookingUI
	var cooking_ui: Node = _find_cooking_ui()
	if cooking_ui and cooking_ui.has_method("_on_discovery"):
		cooking_ui._on_discovery(result, result_is_dish)

	# collapse the other item into us
	var collapse_tw: Tween = other.create_tween()
	collapse_tw.tween_property(other, "position", mid_pos, 0.15)
	collapse_tw.parallel().tween_property(other, "scale", Vector2.ZERO, 0.15)
	collapse_tw.tween_callback(other.queue_free)

	# transform into result with a flash
	item_id = result
	is_dish = result_is_dish
	position = mid_pos
	var display: String = result.replace("_", " ").capitalize()
	label.text = ("★ " + display) if is_dish else display

	# burst effect — scale up then settle
	scale = Vector2(1.5, 1.5)
	modulate = Color(0.4, 1.0, 0.5)
	var tw: Tween = create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(self, "scale", Vector2.ONE, 0.35)
	tw.parallel().tween_property(self, "modulate", _base_color(), 0.5)

func _base_color() -> Color:
	return Color(1.0, 0.92, 0.65) if is_dish else Color(0.85, 0.92, 1.0)

func _find_cooking_ui() -> Node:
	# try walking up the tree first (fast path)
	var node: Node = self
	while node != null:
		if node.has_method("_on_discovery"):
			return node
		node = node.get_parent()
	# fallback: find by group (handles edge cases with top_level reparenting)
	var group := get_tree().get_nodes_in_group("cooking_ui")
	if not group.is_empty():
		return group[0]
	return null
