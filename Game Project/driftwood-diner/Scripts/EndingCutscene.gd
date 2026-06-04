extends Control

@onready var texture_rect = $TextureRect
@onready var fader = $Fader

var images: Array[Texture2D] = []
var _current_idx: int = 0
var _is_ending: bool = false

func _ready() -> void:
	# The correct chronological sequence based on the uploaded images:
	# 1. Walking on the path (ending_3.png)
	# 2. Handing the envelope / port fee (ending_2.png)
	# 3. Getting into the boat (ending_1.png)
	# 4. Sailing away / looking back (ending_5.png)
	
	var tex_walk  = load("res://Assets/ending/ending_3.png") as Texture2D
	var tex_pay   = load("res://Assets/ending/ending_2.png") as Texture2D
	var tex_board = load("res://Assets/ending/ending_1.png") as Texture2D
	var tex_sail  = load("res://Assets/ending/ending_5.png") as Texture2D
	
	if tex_walk:  images.append(tex_walk)
	if tex_pay:   images.append(tex_pay)
	if tex_board: images.append(tex_board)
	if tex_sail:  images.append(tex_sail)
	
	fader.color = Color.BLACK
	
	if images.size() > 0:
		_play_next_image()
	else:
		_end_sequence()

func _play_next_image() -> void:
	if _current_idx >= images.size():
		_end_sequence()
		return
		
	texture_rect.texture = images[_current_idx]
	_current_idx += 1
	
	var tween = create_tween()
	
	# Fade in
	tween.tween_property(fader, "color:a", 0.0, 2.0)
	# Wait
	tween.tween_interval(4.0)
	# Fade out
	tween.tween_property(fader, "color:a", 1.0, 2.0)
	
	tween.tween_callback(_play_next_image)

func _end_sequence() -> void:
	if _is_ending: return
	_is_ending = true
	# In the full game, this would return to the main menu or close.
	# For now, just boot back to the diner so the player isn't stuck.
	get_tree().change_scene_to_file("res://Scenes/main.tscn")

func _input(event: InputEvent) -> void:
	# Allow skipping with Esc/Space/Click
	if event is InputEventKey and event.pressed:
		_end_sequence()
	elif event is InputEventMouseButton and event.pressed:
		_end_sequence()
