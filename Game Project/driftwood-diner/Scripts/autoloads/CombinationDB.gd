extends Node

# Infinite Craft style — ingredients combine into dishes AND intermediate ingredients.
# Everything is reusable. Discovery is the progression.
# IMPORTANT: all keys MUST be alphabetically sorted (matching _make_key behavior)

var _recipes: Dictionary = {
	# ===================================================================
	# TIER 1 — Base combos (ingredient + ingredient -> dish/intermediate)
	# ===================================================================
	# water combos
	"apple+water":            "apple_cider",
	"berry+water":            "berry_juice",
	"clam+water":             "clam_chowder",
	"fish+water":             "fish_stew",
	"flour+water":            "bread_loaf",
	"herb+water":             "herb_broth",
	"honey+water":            "honey_tea",
	"mushroom+water":         "mushroom_soup",
	"salt+water":             "brine",
	"seaweed+water":          "seaweed_broth",
	"vegetable+water":        "vegetable_soup",

	# salt combos
	"fish+salt":              "salted_fish",
	"mushroom+salt":          "pickled_mushroom",
	"salt+seaweed":           "cured_seaweed",
	"salt+vegetable":         "preserved_vegetables",

	# smoke combos
	"clam+smoke":             "smoked_clam",
	"fish+smoke":             "smoked_fish",
	"mushroom+smoke":         "smoked_mushroom",
	"salt+smoke":             "smoked_salt",

	# herb combos
	"fish+herb":              "herb_fish",
	"herb+mushroom":          "herb_mushroom_mix",
	"herb+vegetable":         "seasoned_greens",

	# flour combos
	"apple+flour":            "apple_cake",
	"berry+flour":            "berry_pie",
	"flour+honey":            "honey_cake",
	"flour+mushroom":         "mushroom_pastry",
	"flour+salt":             "flatbread",

	# fruit/sweet combos
	"apple+berry":            "fruit_medley",
	"apple+herb":             "herbed_apple",
	"apple+honey":            "honey_apple",
	"berry+honey":            "berry_preserves",

	# misc base combos
	"clam+fish":              "mixed_catch",
	"clam+herb":              "herb_clam",
	"clam+salt":              "brined_clam",
	"fish+seaweed":           "nori_wrap",
	"mushroom+vegetable":     "foraged_mix",

	# ===================================================================
	# TIER 2 — Dish/intermediate + ingredient -> better dish
	# ===================================================================
	# fish stew upgrades
	"clam+fish_stew":         "seafood_soup",
	"fish_stew+herb":         "cured_herb_fish",
	"fish_stew+mushroom":     "hearty_fish_stew",
	"fish_stew+salt":         "salted_fish_stew",
	"fish_stew+seaweed":      "ocean_stew",

	# broth/soup upgrades
	"clam+herb_broth":        "clam_herb_soup",
	"clam+seaweed_broth":     "tidal_soup",
	"clam_chowder+fish":      "seafood_soup",
	"clam_chowder+herb":      "seasoned_chowder",
	"fish+herb_broth":        "fish_herb_soup",
	"fish+seaweed_broth":     "ocean_bowl",
	"fish+vegetable_soup":    "fisherman_stew",
	"herb+mushroom_soup":     "fragrant_mushroom_soup",
	"herb+vegetable_soup":    "garden_soup",
	"herb_broth+mushroom":    "forest_broth",
	"herb_broth+vegetable":   "garden_broth",
	"mushroom+vegetable_soup": "harvest_soup",
	"mushroom_soup+salt":     "salted_mushroom_soup",

	# bread upgrades
	"apple+bread_loaf":       "apple_bread",
	"berry+bread_loaf":       "berry_toast",
	"bread_loaf+fish":        "fish_sandwich",
	"bread_loaf+herb":        "herb_bread",
	"bread_loaf+honey":       "honey_toast",
	"bread_loaf+salt":        "salted_bread",
	"fish+flatbread":         "fish_wrap",
	"flatbread+herb":         "herb_flatbread",
	"flatbread+vegetable":    "veggie_wrap",

	# brine upgrades
	"brine+clam":             "pickled_clam",
	"brine+fish":             "pickled_fish",
	"brine+mushroom":         "pickled_mushroom",
	"brine+seaweed":          "pickled_seaweed",
	"brine+vegetable":        "pickled_vegetables",

	# sweet upgrades
	"apple+honey_cake":       "apple_honey_cake",
	"apple_cake+berry":       "fruit_cake",
	"apple_cider+herb":       "mulled_cider",
	"apple_cider+honey":      "spiced_cider",
	"berry+honey_cake":       "berry_honey_cake",
	"berry_juice+honey":      "sweet_berry_drink",
	"berry_pie+honey":        "glazed_berry_pie",
	"flour+honey_apple":      "apple_turnover",
	"herb+honey_tea":         "herbal_tea",

	# smoked upgrades
	"herb+smoked_clam":       "fragrant_smoked_clam",
	"herb+smoked_fish":       "smoked_herb_fish",
	"salt+smoked_fish":       "cured_smoked_fish",

	# ===================================================================
	# TIER 3 — Dish + dish -> fusion
	# ===================================================================
	"apple_cake+apple_cider": "orchard_feast",
	"apple_cake+honey":       "golden_apple_cake",
	"berry_pie+honey_cake":   "festival_dessert",
	"bread_loaf+clam_chowder": "dock_workers_special",
	"bread_loaf+pickled_fish": "harbour_plate",
	"bread_loaf+salted_fish": "harbour_lunch",
	"bread_loaf+seasoned_greens": "garden_plate",
	"bread_loaf+seafood_soup": "sailor_plate",
	"bread_loaf+smoked_fish": "traveller_meal",
	"berry_preserves+bread_loaf": "morning_toast",
	"bread_loaf+fish_stew":   "fisherman_plate",
	"fish_stew+herb_bread":   "comfort_meal",
	"fish_stew+nori_wrap":    "island_bowl",
	"fruit_medley+honey_cake": "island_sweet_plate",
	"garden_soup+herb_bread": "farmer_lunch",
	"herb_bread+smoked_fish": "keeper_supper",
	"herb_broth+mushroom_pastry": "forager_meal",
	"herb_broth+mushroom_soup": "deep_forest_soup",

	# ===================================================================
	# TIER 4 — Special / story-gated / NPC-gifted ingredient recipes
	# ===================================================================
	# pressed_flower (Baker T3) — the key to the Memory Cake
	"bread_loaf+pressed_flower": "remembrance_bread",
	"herb+pressed_flower":    "floral_tea",
	"honey+pressed_flower":   "floral_honey",
	"honey_cake+pressed_flower": "memory_cake",
	"pressed_flower+water":   "flower_water",

	# seeds_packet (Traveller T5) — gardening-themed dishes
	"bread_loaf+fresh_sprouts": "garden_sandwich",
	"fresh_sprouts+herb":     "sprout_salad",
	"heirloom_vegetables+herb_broth": "traveller_garden_stew",
	"heirloom_vegetables+water": "heirloom_soup",
	"seeds_packet+vegetable": "heirloom_vegetables",
	"seeds_packet+water":     "fresh_sprouts",

	# fishing_lure_hand_carved (Fisherman T3) — upgrades fish dishes
	"bread_loaf+deep_water_fish": "legendary_fish_sandwich",
	"bread_loaf+prize_catch": "fisherman_feast",
	"fish+fishing_lure_hand_carved": "prize_catch",
	"fishing_lure_hand_carved+water": "deep_water_fish",
	"herb+prize_catch":       "master_herb_fish",
	"prize_catch+salt":       "trophy_fish",

	# unfamiliar_spices (Newcomer T3) — exotic flavour upgrades
	"bread_loaf+unfamiliar_spices": "spiced_bread",
	"fish+mystery_seasoning":  "newcomer_special",
	"fish_stew+unfamiliar_spices": "spiced_fish_stew",
	"herb+unfamiliar_spices":  "mystery_seasoning",
	"honey_cake+unfamiliar_spices": "spiced_honey_cake",
	"unfamiliar_spices+vegetable_soup": "spiced_vegetable_soup",
	"unfamiliar_spices+water": "spice_tea",

	# exotic_spice_blend (Merchant T0) — trade-route flavours
	"bread_loaf+exotic_spice_blend": "merchant_bread",
	"exotic_spice_blend+fish_stew": "merchant_fish_stew",
	"exotic_spice_blend+herb_broth": "exotic_broth",
	"exotic_spice_blend+honey_cake": "eastern_honey_cake",
	"exotic_spice_blend+salt": "seasoned_salt",
	"exotic_spice_blend+water": "exotic_tea",

	# northern_seaweed (Merchant T1) — cold-water delicacies
	"clam+northern_seaweed":   "archipelago_stew",
	"fish+northern_broth":     "northern_seafood_bowl",
	"fish+northern_seaweed":   "northern_fish_wrap",
	"northern_seaweed+salt":   "northern_cured_seaweed",
	"northern_seaweed+water":  "northern_broth",

	# rare_island_herb (Merchant T3) — best herb in the game
	"bread_loaf+rare_island_herb": "island_herb_bread",
	"fish_stew+rare_island_herb": "island_herb_stew",
	"herb_broth+rare_island_herb": "master_broth",
	"honey+island_tonic":      "healing_tonic",
	"honey_cake+rare_island_herb": "island_herb_cake",
	"rare_island_herb+water":  "island_tonic",

	# ===================================================================
	# TIER 5 — Grand fusions (endgame combos)
	# ===================================================================
	"comfort_meal+honey_cake": "driftwood_special",
	"festival_dessert+spiced_honey_cake": "celebration_platter",
	"fish_stew+mushroom_soup": "island_feast",
	"fisherman_feast+seafood_soup": "ocean_banquet",
	"floral_tea+memory_cake":  "baker_remembrance",
	"herb_bread+seafood_soup": "lighthouse_dinner",
	"island_feast+island_herb_bread": "driftwood_grand_feast",
	"merchant_bread+spiced_fish_stew": "trade_route_dinner",
}

func try_combine(a: String, b: String) -> String:
	var key: String = _make_key([a, b])
	return _recipes.get(key, "")

func try_combine_three(a: String, b: String, c: String) -> String:
	var key: String = _make_key([a, b, c])
	return _recipes.get(key, "")

func _make_key(ingredients: Array) -> String:
	var sorted: Array = ingredients.duplicate()
	sorted.sort()
	return "+".join(sorted)

func is_valid_dish(dish_id: String) -> bool:
	return dish_id in _recipes.values()

func get_all_recipes() -> Dictionary:
	return _recipes

func get_all_combinations() -> Dictionary:
	return _recipes  # alias for recipe book
