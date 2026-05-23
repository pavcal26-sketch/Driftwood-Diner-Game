extends CanvasLayer

signal cooking_pressed
signal recipes_pressed
signal advance_pressed
signal corkboard_pressed

@onready var day_label     : Label = $Control/DayCounter
@onready var phase_label   : Label = $Control/PhaseDisplay
@onready var savings_label : Label = $Control/SavingsDisplay/SavingsAmount

func _ready() -> void:
	$Control/ActionButtons/OpenCooking.pressed.connect(func(): cooking_pressed.emit())
	$Control/ActionButtons/OpenRecipes.pressed.connect(func(): recipes_pressed.emit())
	$Control/ActionButtons/OpenCorkboard.pressed.connect(func(): corkboard_pressed.emit())
	$Control/ActionButtons/AdvanceDay.pressed.connect(func(): advance_pressed.emit())
	SignalBus.day_phase_changed.connect(update_phase)
	update_day(GameManager.current_day)
	update_phase(GameManager.current_phase)
	update_savings(Economy.savings)

func update_day(day: int) -> void:
	day_label.text = "Day %d" % day

func update_phase(phase: String) -> void:
	phase_label.text = "Time: " + phase.capitalize()

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
