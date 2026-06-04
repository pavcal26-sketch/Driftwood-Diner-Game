extends Node

# Loads dialogue.json and serves the correct tier lines for any NPC.
# Also tracks visit counts and relationship state per NPC.

const DIALOGUE_PATH := "res://Data/dialogue.json"

var _data: Dictionary = {}           # full parsed dialogue.json
var _npc_visits: Dictionary = {}     # npc_id -> int
var _npc_tiers: Dictionary = {}      # npc_id -> int (current unlocked tier)
var _storm_visits: Dictionary = {}   # npc_id -> int (weather-gated visits)
var _pinned_corkboard: Array = []    # item ids pinned to corkboard
var _completed_signals: Array = []   # story signals already emitted
var _savings_snapshot: int = 0       # cached from Economy for unlock checks
var _debug_forced_tiers: Dictionary = {}

func _ready() -> void:
	_load_dialogue()
	SignalBus.savings_changed.connect(func(v): _savings_snapshot = v)
	SignalBus.corkboard_item_received.connect(_on_corkboard_item)

func _load_dialogue() -> void:
	var file := FileAccess.open(DIALOGUE_PATH, FileAccess.READ)
	if file == null:
		push_error("DialogueManager: couldn't open " + DIALOGUE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("DialogueManager: invalid JSON")

# Returns the NPC's _meta dict or empty dict.
func get_npc_meta(npc_id: String) -> Dictionary:
	return _data.get("npcs", {}).get(npc_id, {}).get("_meta", {})

# Returns lines for the correct tier given current state.
# Call this when an NPC reaches the counter.
func get_lines(npc_id: String) -> Array:
	var npc: Dictionary = _data.get("npcs", {}).get(npc_id, {})
	if npc.is_empty():
		return ["..."]

	var tiers: Array = npc.get("tiers", [])
	var best_tier: Dictionary = tiers[0]  # fallback to tier 0
	var best_tier_idx: int = 0

	for i in range(tiers.size()):
		if _tier_unlocked(npc_id, tiers[i]):
			best_tier = tiers[i]
			best_tier_idx = i

	if _debug_forced_tiers.has(npc_id):
		var forced_idx: int = _debug_forced_tiers[npc_id]
		if forced_idx < tiers.size():
			best_tier = tiers[forced_idx]
			best_tier_idx = forced_idx

	# Track the highest tier this NPC has reached — this is what
	# npc_tier_reached conditions check against. Without this,
	# cross-NPC story gates (Baker T4, Traveller T7, etc.) never unlock.
	_npc_tiers[npc_id] = maxi(_npc_tiers.get(npc_id, 0), best_tier_idx)

	# fire any triggers attached to this tier
	for trigger in best_tier.get("triggers", []):
		_fire_trigger(trigger, npc_id)

	# give item if applicable
	var gives: Variant = best_tier.get("gives_item", null)
	if gives != null:
		_give_item(gives)

	# support new variants schema — pick a random set each visit
	if best_tier.has("variants"):
		var variants: Array = best_tier["variants"]
		if not variants.is_empty():
			return variants[randi() % variants.size()]
	return best_tier.get("lines", ["..."])

# Returns corkboard item description dict or empty.
func get_corkboard_item(item_id: String) -> Dictionary:
	return _data.get("corkboard_items", {}).get(item_id, {})

# Called when an NPC visits — increment count, re-evaluate tier.
func record_visit(npc_id: String, weather: String = "clear") -> void:
	_npc_visits[npc_id] = _npc_visits.get(npc_id, 0) + 1
	if weather in ["fog", "rain"]:
		_storm_visits[npc_id] = _storm_visits.get(npc_id, 0) + 1

# Called after serving a dish.
func record_dish_served(npc_id: String, _dish_id: String) -> void:
	var key := npc_id + "_dishes"
	_npc_visits[key] = _npc_visits.get(key, 0) + 1

func debug_add_visit(npc_id: String) -> void:
	_npc_visits[npc_id] = _npc_visits.get(npc_id, 0) + 1

func debug_force_tier(npc_id: String, tier_idx: int) -> void:
	_debug_forced_tiers[npc_id] = tier_idx

# -----------------------------------------------------------------------
# Private helpers
# -----------------------------------------------------------------------

func _tier_unlocked(npc_id: String, tier: Dictionary) -> bool:
	var cond: Variant = tier.get("unlock_condition", null)
	if cond == null:
		return true

	var weather_req: Variant = tier.get("weather_required", null)
	if weather_req != null and weather_req != "any_storm":
		if GameManager.current_weather != weather_req:
			return false
	if weather_req == "any_storm" and GameManager.current_weather not in ["fog", "rain"]:
		return false

	match cond.get("type", ""):
		"visits":
			return _npc_visits.get(npc_id, 0) >= cond.get("count", 999)
		"dish_served":
			var key := npc_id + "_dishes"
			return _npc_visits.get(key, 0) >= cond.get("cumulative", 999)
		"savings_reached":
			return _savings_snapshot >= cond.get("amount", 999999)
		"corkboard_items_pinned":
			return _pinned_corkboard.size() >= cond.get("count", 999)
		"npc_tier_reached":
			var target_npc: String = cond.get("npc", "")
			var target_tier: int = cond.get("tier", 999)
			return _npc_tiers.get(target_npc, 0) >= target_tier
		"storm_visits":
			return _storm_visits.get(npc_id, 0) >= cond.get("count", 999)
		"storm_visitor_visits":
			return _storm_visits.get("storm_visitor", 0) >= cond.get("count", 999)
		"ending_chosen":
			return false  # handled externally
		"any_ending_reached":
			return _completed_signals.has("ending_reached")
	return false

func _give_item(gives: Dictionary) -> void:
	match gives.get("type", ""):
		"corkboard":
			SignalBus.corkboard_item_received.emit(gives.get("id", ""))
		"ingredient":
			SignalBus.ingredient_received.emit(gives.get("id", ""))
		"counter":
			SignalBus.ingredient_received.emit(gives.get("id", ""))

func _fire_trigger(trigger: String, _npc_id: String) -> void:
	if _completed_signals.has(trigger):
		return
	_completed_signals.append(trigger)
	SignalBus.story_signal.emit(trigger)

func _on_corkboard_item(item_id: String) -> void:
	if not _pinned_corkboard.has(item_id):
		_pinned_corkboard.append(item_id)

# Serialize state for save system.
func get_save_data() -> Dictionary:
	return {
		"npc_visits": _npc_visits,
		"npc_tiers": _npc_tiers,
		"storm_visits": _storm_visits,
		"pinned_corkboard": _pinned_corkboard,
		"completed_signals": _completed_signals,
	}

func load_save_data(data: Dictionary) -> void:
	_npc_visits          = data.get("npc_visits", {})
	_npc_tiers           = data.get("npc_tiers", {})
	_storm_visits        = data.get("storm_visits", {})
	_pinned_corkboard    = data.get("pinned_corkboard", [])
	_completed_signals   = data.get("completed_signals", [])
