extends CanvasLayer

signal closed

@onready var item_list  : VBoxContainer = $Control/Sidebar/VBox/Scroll/ItemList
@onready var workspace  : Control       = $Control/Workspace
@onready var npc_list   : VBoxContainer = $Control/ServePanel/VBox/Scroll/NPCList
@onready var info_label : Label         = $Control/InfoBar/HBox/InfoLabel

var _waiting_npcs: Array[String] = []
var _selected_dish: CraftItem = null  # dish highlighted for serving

# all discovered ingredients / discovered dishes
var discovered: Array[String] = [
	"water", "fish", "flour", "salt", "herb",
	"berry", "honey", "clam", "mushroom", "vegetable",
	"seaweed", "apple", "smoke",
]
var _dishes: Array[String] = []

func _ready() -> void:
	add_to_group("cooking_ui")   # lets CraftItems find us via group fallback
	SignalBus.npc_at_counter.connect(_on_npc_waiting)
	SignalBus.npc_departed.connect(_on_npc_left)
	SignalBus.npc_left_counter.connect(_on_npc_left)
	SignalBus.npc_served.connect(_on_npc_served)
	SignalBus.ingredient_received.connect(_on_ingredient_received)
	
	if GameManager.last_loaded_data.has("cooking_ui"):
		load_save_data(GameManager.last_loaded_data["cooking_ui"])
	else:
		_rebuild_sidebar()
		
	_rebuild_npc_panel()
	$Control/InfoBar/HBox/CloseButton.pressed.connect(func(): closed.emit())
	$Control/InfoBar/HBox/ClearButton.pressed.connect(clear_workspace)

# -----------------------------------------------------------------------
# NPC tracking
# -----------------------------------------------------------------------
func _on_npc_waiting(npc_id: String) -> void:
	if npc_id not in _waiting_npcs:
		_waiting_npcs.append(npc_id)
	_rebuild_npc_panel()

func _on_npc_left(npc_id: String) -> void:
	_waiting_npcs.erase(npc_id)
	_rebuild_npc_panel()

func _on_npc_served(npc_id: String, _dish_id: String) -> void:
	_waiting_npcs.erase(npc_id)
	_selected_dish = null
	_rebuild_npc_panel()

func _on_ingredient_received(ingredient_id: String) -> void:
	if ingredient_id not in discovered:
		discovered.append(ingredient_id)
		_rebuild_sidebar()

# -----------------------------------------------------------------------
# Sidebar — discovered items as clickable spawn buttons
# -----------------------------------------------------------------------
func _rebuild_sidebar() -> void:
	for child in item_list.get_children():
		child.queue_free()

	var sorted: Array[String] = []
	for d in _dishes:
		sorted.append(d)
	for item in discovered:
		if item not in _dishes:
			sorted.append(item)

	for item_id: String in sorted:
		var btn := Button.new()
		var display: String = item_id.replace("_", " ").capitalize()
		var is_dish: bool   = item_id in _dishes
		btn.text = ("★ " + display) if is_dish else display
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_dish:
			btn.modulate = Color(1.0, 0.95, 0.75)
		btn.pressed.connect(_spawn_on_workspace.bind(item_id, is_dish))
		item_list.add_child(btn)

func _spawn_on_workspace(item_id: String, is_dish: bool) -> void:
	var item := CraftItem.new()
	var lbl  := Label.new()
	lbl.name = "Label"
	item.add_child(lbl)
	item.setup(item_id, is_dish)

	# spawn near centre of workspace with small random jitter
	var ws_rect: Rect2  = workspace.get_global_rect()
	var centre: Vector2 = ws_rect.get_center()
	var jitter: Vector2 = Vector2(randf_range(-80, 80), randf_range(-40, 40))
	# item is top_level so position is global
	item.global_position = centre + jitter - item.custom_minimum_size * 0.5

	workspace.add_child(item)
	info_label.text = "Drag items onto each other to combine. Right-click to remove."

# -----------------------------------------------------------------------
# Discovery — called by CraftItem on successful combine
# -----------------------------------------------------------------------
func _on_discovery(result_id: String, is_dish: bool) -> void:
	if result_id not in discovered:
		discovered.append(result_id)
		if is_dish:
			_dishes.append(result_id)
		info_label.text = "★ NEW: " + result_id.replace("_", " ").capitalize() + "!"
		_rebuild_sidebar()
	else:
		info_label.text = result_id.replace("_", " ").capitalize() + " (already known)"

# -----------------------------------------------------------------------
# NPC serve panel
# -----------------------------------------------------------------------
func _rebuild_npc_panel() -> void:
	for child in npc_list.get_children():
		child.queue_free()

	if _waiting_npcs.is_empty():
		var lbl := Label.new()
		lbl.text = "No one waiting"
		lbl.modulate = Color(0.5, 0.5, 0.5)
		npc_list.add_child(lbl)
		return

	for npc_id: String in _waiting_npcs:
		var btn := Button.new()
		var display: String = npc_id.replace("_", " ").capitalize()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# preference hint
		if NPCBase.NPC_PREFERENCES.has(npc_id):
			var accepts: Array = NPCBase.NPC_PREFERENCES[npc_id].get("accepts", [])
			if not accepts.is_empty():
				btn.text = display + "\n wants: " + ", ".join(accepts.slice(0, 3))
			else:
				btn.text = display
		else:
			btn.text = display

		btn.modulate = Color(1.0, 0.85, 0.55)
		btn.pressed.connect(_on_serve_npc_pressed.bind(npc_id))
		npc_list.add_child(btn)

	# instruction line below buttons
	var hint := Label.new()
	hint.text = "First click a ★ dish on the\nworkspace, then press Serve."
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	npc_list.add_child(hint)

# called when the player clicks an NPC's serve button
func _on_serve_npc_pressed(npc_id: String) -> void:
	# find selected dish — prefer explicitly selected, then scan workspace
	var dish_item: CraftItem = _selected_dish
	if dish_item == null or not is_instance_valid(dish_item):
		for child in workspace.get_children():
			if child is CraftItem and (child as CraftItem).is_dish:
				dish_item = child as CraftItem
				break

	if dish_item == null:
		info_label.text = "Craft a ★ dish first, then press Serve."
		_shake($Control/ServePanel)
		return

	var dish_id: String    = dish_item.item_id
	var disp_dish: String  = dish_id.replace("_", " ").capitalize()
	var disp_npc: String   = npc_id.replace("_", " ").capitalize()

	# Warn if it's not their preference, but don't block the serve.
	# Wrong dishes should be servable — NPCBase handles the reaction.
	if not NPCBase.accepts_dish(npc_id, dish_id):
		info_label.text = "Served " + disp_dish + " to " + disp_npc + "... they seem unsure."
	else:
		info_label.text = "Served " + disp_dish + " to " + disp_npc + "!"

	_selected_dish = null

	# poof dish away
	var tw: Tween = dish_item.create_tween()
	tw.tween_property(dish_item, "scale", Vector2.ZERO, 0.15)
	tw.tween_callback(dish_item.queue_free)

	SignalBus.npc_served.emit(npc_id, dish_id)
	DialogueManager.record_dish_served(npc_id, dish_id)

	# kick player out of cooking UI after the poof animation finishes
	await get_tree().create_timer(0.15).timeout
	closed.emit()

# called by CraftItem when clicked to select it for serving
func select_dish(item: CraftItem) -> void:
	# deselect previous
	if _selected_dish != null and is_instance_valid(_selected_dish):
		_selected_dish.modulate = _selected_dish._base_color()
	_selected_dish = item
	if item != null:
		item.modulate = Color(0.6, 1.0, 0.6)  # green highlight = selected
		info_label.text = item.item_id.replace("_", " ").capitalize() + " selected — now press Serve."

func _shake(node: Control) -> void:
	var orig_x: float = node.position.x
	var tw := create_tween()
	tw.tween_property(node, "position:x", orig_x + 10.0, 0.05)
	tw.tween_property(node, "position:x", orig_x - 10.0, 0.05)
	tw.tween_property(node, "position:x", orig_x + 6.0, 0.04)
	tw.tween_property(node, "position:x", orig_x, 0.04)

func clear_workspace() -> void:
	for child in workspace.get_children():
		child.queue_free()
	_selected_dish = null
	info_label.text = "Click any item to start"

func get_save_data() -> Dictionary:
	return {"discovered": discovered, "dishes": _dishes}

func load_save_data(data: Dictionary) -> void:
	if data.has("discovered"):
		discovered.clear()
		for item in data["discovered"]:
			discovered.append(item as String)
	if data.has("dishes"):
		_dishes.clear()
		for item in data["dishes"]:
			_dishes.append(item as String)
	_rebuild_sidebar()
