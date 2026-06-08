extends Control

# Continuously checks the loading status of the target scene.
# Once it reaches 100%, changes the scene.

@onready var progress_label = $VBoxContainer/ProgressLabel
var _target: String = ""

func _ready() -> void:
	_target = SceneManager.get_target_path()
	if _target.is_empty():
		push_error("LoadingScreen loaded but no target scene set in SceneManager!")

func _process(_delta: float) -> void:
	if _target.is_empty():
		return
		
	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(_target, progress)
	
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# progress[0] is a float between 0.0 and 1.0
		var pct: int = int(progress[0] * 100.0)
		progress_label.text = "Loading... %d%%" % pct
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		progress_label.text = "Loading... 100%"
		set_process(false)
		
		# Slight delay to ensure the 100% renders briefly
		var tw = create_tween()
		tw.tween_interval(0.2)
		tw.tween_callback(func():
			var packed_scene = ResourceLoader.load_threaded_get(_target)
			get_tree().change_scene_to_packed(packed_scene)
		)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		progress_label.text = "Error Loading Scene!"
		set_process(false)
