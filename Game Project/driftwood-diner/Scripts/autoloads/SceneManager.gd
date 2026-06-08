extends Node

# Handles asynchronous loading of scenes and transitioning via a Loading Screen.

var _target_scene_path: String = ""

func load_scene(path: String) -> void:
	_target_scene_path = path
	# Request async loading in the background
	ResourceLoader.load_threaded_request(_target_scene_path)
	# Immediately switch to the lightweight loading screen
	get_tree().change_scene_to_file("res://Scenes/LoadingScreen.tscn")

func get_target_path() -> String:
	return _target_scene_path
