extends CanvasLayer

signal cooking_pressed
signal recipes_pressed
signal advance_pressed
signal corkboard_pressed

@onready var day_label     : Label = $Control/DayCounter
@onready var clock_label   : Label = $Control/ClockDisplay
@onready var phase_label   : Label = $Control/PhaseLabel
@onready var savings_label : Label = $Control/SavingsDisplay/SavingsAmount

func _ready() -> void:
	$Control/ActionButtons/OpenCooking.pressed.connect(func(): cooking_pressed.emit())
	$Control/ActionButtons/OpenRecipes.pressed.connect(func(): recipes_pressed.emit())
	$Control/ActionButtons/OpenCorkboard.pressed.connect(func(): corkboard_pressed.emit())
	$Control/ActionButtons/AdvanceDay.pressed.connect(func(): advance_pressed.emit())
	SignalBus.clock_tick.connect(_on_clock_tick)
	update_day(GameManager.current_day)
	_update_clock(GameManager.game_hour)
	update_savings(Economy.savings)

func _on_clock_tick(hour: float) -> void:
	_update_clock(hour)

func _update_clock(hour: float) -> void:
	clock_label.text = GameManager.get_clock_string()
	phase_label.text = GameManager.current_phase.capitalize()

func update_day(day: int) -> void:
	day_label.text = "Day %d" % day

func update_phase(_phase: String) -> void:
	# kept for backward compat — clock_tick handles display now
	pass

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
