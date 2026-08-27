extends Node

# Tracks player savings and handles the two ending thresholds.
# Diminishing returns: serving the same dish to the same NPC pays less each time.

const PASSAGE_COST   := 5000   # Ending A — leave the island (also unlocks Stay ending choice)

# payment multiplier curve — first time full, then drops
# index = times_served_before (clamped to last entry)
const DIMINISH_CURVE: Array[float] = [1.0, 0.75, 0.5, 0.25]

var savings: int = 0
var _active_npc_id: String = ""   # who's at the counter right now
var _serve_history: Dictionary = {}  # "npc_id::dish_id" -> int (times served)

var _passage_unlocked_fired: bool = false

func _ready() -> void:
	SignalBus.npc_served.connect(_on_npc_served)
	SignalBus.npc_at_counter.connect(func(id): _active_npc_id = id)
	SignalBus.dialogue_finished.connect(func(_id): _active_npc_id = "")

func add_savings(amount: int) -> void:
	savings += amount
	SignalBus.savings_changed.emit(savings)
	
	if savings >= PASSAGE_COST and not _passage_unlocked_fired:
		_passage_unlocked_fired = true
		SignalBus.passage_unlocked.emit()

func spend_savings(amount: int) -> void:
	savings -= amount
	if savings < 0:
		savings = 0
	SignalBus.savings_changed.emit(savings)

func _on_npc_served(npc_id: String, dish_id: String) -> void:
	var meta := DialogueManager.get_npc_meta(npc_id)
	var base: int    = meta.get("payment_base", 0)
	var per_tier: int = meta.get("payment_per_tier", 0)
	var tier: int    = DialogueManager._npc_tiers.get(npc_id, 0)

	# Affinity bonus — use NPC_PREFERENCES as the single source of truth
	# NPC_PREFERENCES uses substring matching on dish_id which actually works,
	# unlike the _meta.affinity categories which used descriptive labels
	var multiplier := 1.0
	if NPCBase.NPC_PREFERENCES.has(npc_id):
		if NPCBase.accepts_dish(npc_id, dish_id):
			multiplier = 2.0
	else:
		# NPCs without explicit preferences accept and enjoy anything
		multiplier = 1.5

	# diminishing returns — same dish to same NPC pays less each time
	var history_key: String = npc_id + "::" + dish_id
	var times_before: int = _serve_history.get(history_key, 0)
	var diminish_idx: int = mini(times_before, DIMINISH_CURVE.size() - 1)
	var diminish: float = DIMINISH_CURVE[diminish_idx]
	_serve_history[history_key] = times_before + 1

	var total := int((base + per_tier * tier) * multiplier * diminish)
	add_savings(total)

func get_save_data() -> Dictionary:
	return {
		"savings": savings, 
		"serve_history": _serve_history,
		"passage_unlocked": _passage_unlocked_fired
	}

func load_save_data(data: Dictionary) -> void:
	savings = data.get("savings", 0)
	_serve_history = data.get("serve_history", {})
	_passage_unlocked_fired = data.get("passage_unlocked", false)
	SignalBus.savings_changed.emit(savings)
