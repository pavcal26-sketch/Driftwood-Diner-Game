extends Control

# Ending cutscene slideshow. Reads which ending from GameManager meta.
# Ending A: ending_1 -> ending_5 (leaving the island)  
# Ending B: ending_b_1 -> ending_b_4 + stay_1 -> stay_4 (staying and rebuilding)

@onready var texture_rect = $TextureRect
@onready var fader = $Fader

var _slides: Array[String] = []
var _current_slide: int = 0
var _can_advance: bool = false
var _is_ending: bool = false

func _ready() -> void:
	# determine which ending set to show
	var ending_type: String = "A"
	if GameManager.has_meta("ending_type"):
		ending_type = GameManager.get_meta("ending_type")
	
	if ending_type == "B":
		# Ending B: the diner upgrade + staying montage
		_slides = [
			"res://Assets/ending/ending_b_1.png",
			"res://Assets/ending/ending_b_2.png",
			"res://Assets/ending/ending_b_3.png",
			"res://Assets/ending/ending_b_4.png",
			"res://Assets/ending/stay_1.png",
			"res://Assets/ending/stay_2.png",
			"res://Assets/ending/stay_3.png",
			"res://Assets/ending/stay_4.png",
		]
	else:
		# Ending A: leaving the island — chronological order
		_slides = [
			"res://Assets/ending/ending_3.png",   # walking on the path
			"res://Assets/ending/ending_2.png",   # handing the envelope / port fee
			"res://Assets/ending/ending_4.png",   # looking back at the diner
			"res://Assets/ending/ending_1.png",   # getting into the boat
			"res://Assets/ending/ending_5.png",   # sailing away
		]
	
	# start from black
	fader.color = Color.BLACK
	fader.modulate.a = 1.0
	_show_slide(0)

func _show_slide(index: int) -> void:
	if index >= _slides.size():
		_end_sequence()
		return
	
	_current_slide = index
	_can_advance = false
	
	# load texture — gracefully skip missing files
	var tex = load(_slides[index]) as Texture2D
	if tex:
		texture_rect.texture = tex
	else:
		# skip broken slide
		_show_slide(index + 1)
		return
	
	# fade in from black
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 0.0, 2.0)
	tw.tween_interval(3.0)  # hold the image for a moment
	tw.tween_callback(func(): _can_advance = true)

func _input(event: InputEvent) -> void:
	if _is_ending:
		return
	if not _can_advance:
		# allow skip of entire cutscene with Escape
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_end_sequence()
		return
	# any click or key press advances to next slide
	if event is InputEventMouseButton and event.pressed:
		_advance()
	elif event is InputEventKey and event.pressed:
		_advance()

func _advance() -> void:
	_can_advance = false
	# fade to black, then show next slide
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 1.0, 1.5)
	tw.tween_callback(func(): _show_slide(_current_slide + 1))

func _end_sequence() -> void:
	if _is_ending:
		return
	_is_ending = true
	# fade to black and return to title screen
	var tw := create_tween()
	tw.tween_property(fader, "color:a", 1.0, 2.0)
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")
	)
