extends CanvasLayer

# NPC dialogue overlay.
# Slides in from bottom using CanvasLayer.offset (not Control position — that breaks anchors).
# Supports multi-frame portrait switching on each E press.

@onready var npc_portrait  : TextureRect   = $Control/NPCPortrait
@onready var placeholder   : ColorRect     = $Control/NPCPlaceholder
@onready var dialogue_line : RichTextLabel = $Control/DialoguePanel/Margin/VBox/DialogueLine
@onready var speaker_name  : Label         = $Control/DialoguePanel/Margin/VBox/SpeakerName
@onready var prompt_hint   : Label         = $Control/DialoguePanel/Margin/VBox/PromptHint

var _lines:     Array  = []
var _line_idx:  int    = 0
var _npc_id:    String = ""
var _accepting: bool   = false
var _typing:    bool   = false
var _full_text: String = ""
var _portraits: Array[Texture2D] = []
var _frame_idx: int    = 0
var _slide_tween: Tween = null
var _is_reaction: bool = false   # true = post-serve reaction, not pre-serve dialogue

const TYPE_SPEED: float = 0.028   # seconds per character
const SLIDE_PX: float   = 180.0   # panel is bottom 24% — slide it in from below

func _ready() -> void:
	visible = false
	SignalBus.npc_reaction.connect(_on_npc_reaction)

# -----------------------------------------------------------------------
# Public
# -----------------------------------------------------------------------
func show_npc(npc_id: String, lines: Array, display_name: String) -> void:
	_npc_id       = npc_id
	_lines        = lines
	_line_idx     = 0
	_accepting    = true
	_frame_idx    = 0
	_is_reaction  = false
	speaker_name.text = display_name
	_load_portraits(npc_id)
	visible = true
	_slide_in()
	_show_line()

func _on_npc_reaction(npc_id: String, line: String) -> void:
	_npc_id    = npc_id
	_lines     = [line]
	_line_idx  = 0
	_accepting = true
	_is_reaction = true
	var meta: Dictionary = DialogueManager.get_npc_meta(npc_id)
	speaker_name.text = meta.get("display_name", npc_id.replace("_", " ").capitalize())
	_load_portraits(npc_id)
	# if already visible (shouldn't normally happen but be safe), just update text
	if not visible:
		visible = true
		_slide_in()
	_show_line()

# -----------------------------------------------------------------------
# Portraits
# -----------------------------------------------------------------------
func _load_portraits(npc_id: String) -> void:
	_portraits.clear()
	var i := 0
	while i < 8:
		var path := "res://Assets/npcs/iso/%s_%d.png" % [npc_id, i]
		var tex := _read_png_texture(path)
		if tex:
			_portraits.append(tex)
			i += 1
		else:
			break
	if _portraits.is_empty():
		var tex := _read_png_texture("res://Assets/npcs/iso/%s.png" % npc_id)
		if tex:
			_portraits.append(tex)

	if not _portraits.is_empty():
		npc_portrait.texture = _portraits[0]
		npc_portrait.visible  = true
		placeholder.visible   = false
	else:
		npc_portrait.visible = false
		placeholder.visible  = true
		if NPCBase.NPC_COLORS.has(npc_id):
			placeholder.color = NPCBase.NPC_COLORS[npc_id]
		else:
			var h := float(abs(npc_id.hash()) % 360) / 360.0
			placeholder.color = Color.from_hsv(h, 0.55, 0.80)

func _read_png_texture(path: String) -> Texture2D:
	# Happy path: import system has a cached .ctex
	var tex := load(path) as Texture2D
	if tex:
		return tex
	# Fallback: read raw bytes and detect actual format from header
	var os_path := ProjectSettings.globalize_path(path)
	var fa := FileAccess.open(os_path, FileAccess.READ)
	if fa == null:
		return null
	var bytes := fa.get_buffer(fa.get_length())
	fa.close()
	var img := Image.new()
	var err: int
	# detect real format from magic bytes — files may lie about their extension
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50:  # PNG
		err = img.load_png_from_buffer(bytes)
	elif bytes.size() >= 2 and bytes[0] == 0xFF and bytes[1] == 0xD8:  # JPEG
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.size() >= 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	else:
		return null
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

func _advance_portrait_frame() -> void:
	if _portraits.size() > 1:
		_frame_idx = (_frame_idx + 1) % _portraits.size()
		npc_portrait.texture = _portraits[_frame_idx]

# -----------------------------------------------------------------------
# Slide animations — use CanvasLayer.offset so anchors aren't disturbed
# -----------------------------------------------------------------------
func _slide_in() -> void:
	if _slide_tween:
		_slide_tween.kill()
	offset = Vector2(0.0, SLIDE_PX)   # Vector2, NOT Vector2i — Godot reads offset as Vector2
	_slide_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(self, "offset", Vector2.ZERO, 0.28)

func _slide_out() -> void:
	_accepting = false
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(self, "offset", Vector2(0.0, SLIDE_PX), 0.22)
	_slide_tween.tween_callback(_on_slide_out_done)

func _on_slide_out_done() -> void:
	visible = false
	# only fire dialogue_finished for real pre-serve dialogue.
	# reactions use a different path — NPC handles its own post-serve flow.
	if not _is_reaction:
		SignalBus.dialogue_finished.emit(_npc_id)
	_is_reaction = false

# -----------------------------------------------------------------------
# Dialogue flow
# -----------------------------------------------------------------------
func _show_line() -> void:
	if _line_idx >= _lines.size():
		_slide_out()
		return
	_full_text = _lines[_line_idx]
	_line_idx += 1
	prompt_hint.text = "[ E ]  Close" if _line_idx >= _lines.size() else "[ E ]  Continue"
	_advance_portrait_frame()
	_start_typewriter()

var _type_tween: Tween

func _start_typewriter() -> void:
	_typing = true
	dialogue_line.text = _full_text
	dialogue_line.visible_characters = 0
	
	if _type_tween:
		_type_tween.kill()
		
	var duration: float = _full_text.length() * TYPE_SPEED
	_type_tween = create_tween()
	_type_tween.tween_property(dialogue_line, "visible_characters", _full_text.length(), duration)
	_type_tween.tween_callback(func(): _typing = false)

func _skip_typewriter() -> void:
	if _type_tween:
		_type_tween.kill()
	_typing = false
	dialogue_line.visible_characters = -1

# -----------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not visible or not _accepting:
		return
	if event.is_action_pressed("action_advance"):
		get_viewport().set_input_as_handled()
		if _typing:
			_skip_typewriter()
		else:
			_show_line()
