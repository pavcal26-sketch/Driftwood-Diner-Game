extends Control

@onready var texture_rect = $TextureRect
@onready var fader = $Fader

var tex_1: Texture2D
var tex_2: Texture2D
var tex_3: Texture2D

func _ready() -> void:
	# Load textures dynamically so editor doesn't freak out if they are missing/swapped
	tex_1 = load("res://Assets/intro/intro_1.png") as Texture2D
	tex_2 = load("res://Assets/intro/intro_2.png") as Texture2D
	tex_3 = load("res://Assets/intro/intro_3.png") as Texture2D
	
	fader.color = Color.BLACK
	texture_rect.modulate = Color(1.2, 1.2, 1.2)
	
	if tex_1:
		texture_rect.texture = tex_1
		
	_play_sequence()

func _play_sequence() -> void:
	var tween = create_tween()
	
	fader.modulate = Color.WHITE
	fader.color = Color.BLACK
	
	# 1. Shore (fade in, wait, fade out)
	tween.tween_property(fader, "modulate:a", 0.0, 2.0)
	tween.tween_interval(3.5)
	tween.tween_property(fader, "modulate:a", 1.0, 1.5)
	
	# 2. Get up
	tween.tween_callback(func(): 
		if tex_2: texture_rect.texture = tex_2 
		texture_rect.modulate = Color(1.2, 1.2, 1.2)
	)
	tween.tween_property(fader, "modulate:a", 0.0, 2.0)
	tween.tween_interval(3.5)
	tween.tween_property(fader, "modulate:a", 1.0, 1.5)
	
	# 3. Restaurant (dark -> lights turn on)
	tween.tween_callback(func(): 
		if tex_3: texture_rect.texture = tex_3
		# Set to very dark, bluish tint
		texture_rect.modulate = Color(0.12, 0.15, 0.20, 1.0)
	)
	
	tween.tween_property(fader, "modulate:a", 0.0, 2.0)
	tween.tween_interval(2.5)
	
	# Lights turn on suddenly but smoothly
	tween.tween_property(texture_rect, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	tween.tween_interval(4.0)
	
	# Final fade to black and transition
	tween.tween_property(fader, "modulate:a", 1.0, 2.0)
	tween.tween_interval(0.5)
	tween.tween_callback(func(): _transition())

var _is_ending: bool = false

func _transition() -> void:
	if _is_ending: return
	_is_ending = true
	SceneManager.load_scene("res://Scenes/main.tscn")

func _input(event: InputEvent) -> void:
	# Allow skipping with Esc/Space/Click
	if event is InputEventKey and event.pressed:
		_transition()
	elif event is InputEventMouseButton and event.pressed:
		_transition()
