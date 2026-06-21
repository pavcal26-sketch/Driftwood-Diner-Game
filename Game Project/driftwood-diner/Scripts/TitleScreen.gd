extends Control

@onready var play_button        = $VBoxContainer/PlayButton
@onready var delete_save_button = $VBoxContainer/DeleteSaveButton
@onready var quit_button        = $VBoxContainer/QuitButton
@onready var confirm_dialog     = $ConfirmDeleteDialog

const SAVE_PATH := "user://save.json"

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	delete_save_button.pressed.connect(_on_delete_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	confirm_dialog.confirmed.connect(_on_delete_confirmed)
	
	# only show delete button if a save file actually exists
	delete_save_button.visible = FileAccess.file_exists(SAVE_PATH)

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/IntroCutscene.tscn")

func _on_delete_pressed() -> void:
	confirm_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	# nuke the save file
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	
	# also reset in-memory state so a fresh play doesn't load stale data
	if get_node_or_null("/root/GameManager"):
		GameManager.current_day = 1
		GameManager.nights_survived = 0
		GameManager.game_hour = 19.0
		GameManager.current_weather = "clear"
	if get_node_or_null("/root/Economy"):
		Economy.savings = 0
	if get_node_or_null("/root/DialogueManager"):
		DialogueManager.load_save_data({})
	
	# flush on web
	if OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge"):
		JavaScriptBridge.eval("if(typeof FS!=='undefined')FS.syncfs(false,function(e){});")
	
	# hide the button now that there's nothing to delete
	delete_save_button.visible = false

func _on_quit_pressed() -> void:
	get_tree().quit()
