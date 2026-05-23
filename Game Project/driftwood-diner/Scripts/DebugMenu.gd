extends CanvasLayer

@onready var npc_list = $Panel/Margin/VBox/Scroll/NPCList

func _ready() -> void:
	$Panel/Margin/VBox/EconomyBox/AddMoneyBtn.pressed.connect(func():
		Economy.add_savings(1000)
	)
	$Panel/Margin/VBox/EconomyBox/ClearMoneyBtn.pressed.connect(func():
		Economy.spend_savings(Economy.savings)
	)
	$Panel/Margin/VBox/TimeBox/SkipPhaseBtn.pressed.connect(func():
		var gm = GameManager
		if gm.current_phase == "day":
			gm._set_phase("evening")
		elif gm.current_phase == "evening":
			gm._set_phase("night")
		else:
			gm.advance_day()
	)
	$Panel/Margin/VBox/TimeBox/ToggleRainBtn.pressed.connect(func():
		if GameManager.current_weather == "rain":
			GameManager.current_weather = "clear"
			SignalBus.weather_changed.emit("clear")
		else:
			GameManager.current_weather = "rain"
			SignalBus.weather_changed.emit("rain")
	)
	
	_populate_npcs()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()

func _populate_npcs() -> void:
	var npcs = [
		"washed_up_traveller", "elderly_baker", "failing_fisherman",
		"newcomer", "musician", "harbour_worker", "soup_regular",
		"quiet_farmer", "elderly_couple", "night_shift_guard",
		"lighthouse_keeper", "drifting_merchant", "strange_child"
	]
	
	for npc in npcs:
		var hbox = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = npc.capitalize()
		lbl.custom_minimum_size = Vector2(180, 0)
		hbox.add_child(lbl)
		
		var add_visit = Button.new()
		add_visit.text = "+1 Visit"
		add_visit.pressed.connect(func():
			DialogueManager.debug_add_visit(npc)
			print("Added visit to ", npc)
		)
		hbox.add_child(add_visit)
		
		var max_tier = Button.new()
		max_tier.text = "Force Tier 4"
		max_tier.pressed.connect(func():
			DialogueManager.debug_force_tier(npc, 4)
			print("Forced tier 4 for ", npc)
		)
		hbox.add_child(max_tier)
		
		npc_list.add_child(hbox)
