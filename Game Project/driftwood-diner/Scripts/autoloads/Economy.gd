extends Node

# Tracks player savings and handles the two ending thresholds.

const PASSAGE_COST   := 5000   # Ending A — leave the island
const STAY_UPGRADE   := 6000   # Ending B — upgrade and stay

var savings: int = 0
var _active_npc_id: String = ""   # who's at the counter right now

func _ready() -> void:
	SignalBus.npc_served.connect(_on_npc_served)
	SignalBus.npc_at_counter.connect(func(id): _active_npc_id = id)
	SignalBus.dialogue_finished.connect(func(_id): _active_npc_id = "")

func add_savings(amount: int) -> void:
	savings += amount
	SignalBus.savings_changed.emit(savings)
	if savings >= PASSAGE_COST:
		SignalBus.passage_unlocked.emit()

func _on_npc_served(npc_id: String, dish_id: String) -> void:
	var meta := DialogueManager.get_npc_meta(npc_id)
	var base: int    = meta.get("payment_base", 0)
	var per_tier: int = meta.get("payment_per_tier", 0)
	var tier: int    = DialogueManager._npc_tiers.get(npc_id, 0)

	# simple affinity check — expand this once CombinationDB dish tags are in
	var affinity: Array = meta.get("affinity", [])
	var multiplier := 1.0
	if dish_id in affinity or "any" in affinity:
		multiplier = 2.0

	var total := int((base + per_tier * tier) * multiplier)
	add_savings(total)
