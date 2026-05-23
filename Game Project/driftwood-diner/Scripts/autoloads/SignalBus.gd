extends Node

# All global signals in one place.
# Connect via: SignalBus.signal_name.connect(callable)
# Emit via:    SignalBus.signal_name.emit(args)

# --- NPC lifecycle ---
signal npc_arrived(npc_id: String)
signal npc_requests_counter(npc_id: String)  # NPC wants to approach
signal npc_at_counter(npc_id: String)        # NPC reached the counter
signal npc_left_counter(npc_id: String)      # NPC walked away from counter
signal npc_served(npc_id: String, dish_id: String)
signal npc_reaction(npc_id: String, line: String)  # post-serve reaction
signal npc_departed(npc_id: String)

# --- Dialogue ---
signal dialogue_started(npc_id: String)
signal dialogue_line_shown(line: String)
signal dialogue_finished(npc_id: String)
signal corkboard_item_received(item_id: String)
signal ingredient_received(ingredient_id: String)

# --- World state ---
signal day_advanced(day_number: int)
signal day_phase_changed(phase: String)   # "day" | "evening" | "night"
signal weather_changed(weather: String)   # "clear" | "fog" | "rain"

# --- Economy ---
signal savings_changed(new_amount: int)
signal passage_unlocked()

# --- Story ---
signal story_signal(signal_id: String)    # drives trigger strings from dialogue.json
signal ending_triggered(ending: String)   # "A" | "B"
