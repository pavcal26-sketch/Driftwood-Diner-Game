extends Control

@onready var play_button = $VBoxContainer/PlayButton
@onready var quit_button = $VBoxContainer/QuitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_play_pressed() -> void:
	# Change to IntroCutscene. IntroCutscene will then use SceneManager to load Main.
	get_tree().change_scene_to_file("res://Scenes/IntroCutscene.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
