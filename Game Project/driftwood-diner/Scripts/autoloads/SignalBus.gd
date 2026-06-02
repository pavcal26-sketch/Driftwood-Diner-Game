@warning_ignore("unused_signal")
extends Node

# All global signals in one place.
# Connect via: SignalBus.signal_name.connect(callable)
# Emit via:    SignalBus.signal_name.emit(args)

# --- NPC lifecycle ---
@warning_ignore("unused_signal")
signal npc_arrived(npc_id: String)
@warning_ignore("unused_signal")
signal npc_requests_counter(npc_id: String)  # NPC wants to approach
@warning_ignore("unused_signal")
signal npc_at_counter(npc_id: String)        # NPC reached the counter
@warning_ignore("unused_signal")
signal npc_left_counter(npc_id: String)      # NPC walked away from counter
@warning_ignore("unused_signal")
signal npc_served(npc_id: String, dish_id: String)
@warning_ignore("unused_signal")
signal npc_reaction(npc_id: String, line: String)  # post-serve reaction
@warning_ignore("unused_signal")
signal npc_departed(npc_id: String)

# --- Dialogue ---
@warning_ignore("unused_signal")
signal dialogue_started(npc_id: String)
@warning_ignore("unused_signal")
signal dialogue_line_shown(line: String)
@warning_ignore("unused_signal")
signal dialogue_finished(npc_id: String)
@warning_ignore("unused_signal")
signal corkboard_item_received(item_id: String)
@warning_ignore("unused_signal")
signal ingredient_received(ingredient_id: String)

# --- Debug ---
@warning_ignore("unused_signal")
signal debug_spawn_npc(npc_id: String)

# --- World state ---
@warning_ignore("unused_signal")
signal day_advanced(day_number: int)
@warning_ignore("unused_signal")
signal day_phase_changed(phase: String)   # "day" | "evening" | "night"
@warning_ignore("unused_signal")
signal weather_changed(weather: String)   # "clear" | "fog" | "rain"
@warning_ignore("unused_signal")
signal clock_tick(hour: float)            # fires every game-minute with current hour

# --- Economy ---
@warning_ignore("unused_signal")
signal savings_changed(new_amount: int)
@warning_ignore("unused_signal")
signal passage_unlocked()

# --- Story ---
@warning_ignore("unused_signal")
signal story_signal(signal_id: String)    # drives trigger strings from dialogue.json
@warning_ignore("unused_signal")
signal ending_triggered(ending: String)   # "A" | "B"
