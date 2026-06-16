extends CanvasLayer

signal cooking_pressed
signal recipes_pressed
signal advance_pressed
signal corkboard_pressed

@onready var day_label     : Label = $Control/DayCounter
@onready var clock_label   : Label = $Control/ClockDisplay
@onready var phase_label   : Label = $Control/PhaseLabel
@onready var savings_label : Label = $Control/SavingsDisplay/SavingsAmount

var _passage_btn: Button

func _ready() -> void:
	$Control/ActionButtons/OpenCooking.pressed.connect(func(): cooking_pressed.emit())
	$Control/ActionButtons/OpenRecipes.pressed.connect(func(): recipes_pressed.emit())
	$Control/ActionButtons/OpenCorkboard.pressed.connect(func(): corkboard_pressed.emit())
	$Control/ActionButtons/AdvanceDay.pressed.connect(func(): advance_pressed.emit())
	SignalBus.clock_tick.connect(_on_clock_tick)
	SignalBus.passage_unlocked.connect(_on_passage_unlocked)
	update_day(GameManager.current_day)
	_update_clock(GameManager.game_hour)
	update_savings(Economy.savings)
	
	_passage_btn = Button.new()
	_passage_btn.text = "Passage ($5K)"
	_passage_btn.custom_minimum_size = Vector2(150, 44)
	_passage_btn.add_theme_font_size_override("font_size", 18)
	_passage_btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	_passage_btn.pressed.connect(_on_passage_pressed)
	$Control/ActionButtons.add_child(_passage_btn)
	_passage_btn.visible = false
	
	if Economy.savings >= 5000:
		_passage_btn.visible = true

func _on_passage_unlocked() -> void:
	_passage_btn.visible = true

func _on_passage_pressed() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.title = "Leave the Island?"
	confirm.dialog_text = "Pay $5,000 to secure passage on the next boat and leave the island for good?\n\nThis will end the game."
	confirm.get_ok_button().text = "Pay $5,000"
	confirm.get_cancel_button().text = "Stay"
	confirm.confirmed.connect(func():
		Economy.spend_savings(5000)
		SignalBus.story_signal.emit("play_ending_a_sequence")
	)
	add_child(confirm)
	confirm.popup_centered()

func _on_clock_tick(hour: float) -> void:
	_update_clock(hour)

func _update_clock(_hour: float) -> void:
	clock_label.text = GameManager.get_clock_string()
	phase_label.text = GameManager.current_phase.capitalize()

func update_day(day: int) -> void:
	day_label.text = "Day %d" % day

func update_savings(amount: int) -> void:
	savings_label.text = "$%s" % _comma(amount)

func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		if c > 0 and c % 3 == 0:
			out = "," + out
		out = s[i] + out
		c += 1
	return out
