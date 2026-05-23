extends Node

# Infinite Craft style — ingredients combine into dishes AND intermediate ingredients.
# Everything is reusable. Discovery is the progression.

var _recipes: Dictionary = {
	# --- Tier 1: Base combos (ingredient + ingredient → dish) ---
	"fish+water":             "fish_stew",
	"clam+water":             "clam_chowder",
	"mushroom+water":         "mushroom_soup",
	"herb+water":             "herb_broth",
	"flour+water":            "bread_loaf",
	"salt+water":             "brine",
	"fish+salt":              "salted_fish",
	"fish+smoke":             "smoked_fish",
	"fish+herb":              "herb_fish",
	"flour+honey":            "honey_cake",
	"flour+berry":            "berry_pie",
	"flour+apple":            "apple_cake",
	"vegetable+water":        "vegetable_soup",
	"seaweed+water":          "seaweed_broth",

	# --- Tier 2: Dish + ingredient → better dish ---
	"fish_stew+salt":         "salted_fish_stew",
	"fish_stew+herb":         "cured_herb_fish",
	"fish_stew+clam":         "seafood_soup",
	"herb_broth+fish":        "fish_herb_soup",
	"herb_broth+mushroom":    "forest_broth",
	"bread_loaf+herb":        "herb_bread",
	"bread_loaf+honey":       "honey_toast",
	"bread_loaf+fish":        "fish_sandwich",
	"clam_chowder+fish":      "seafood_soup",
	"vegetable_soup+herb":    "garden_soup",
	"vegetable_soup+fish":    "fisherman_stew",
	"seaweed_broth+fish":     "ocean_bowl",
	"brine+fish":             "pickled_fish",
	"brine+vegetable":        "pickled_vegetables",

	# --- Tier 3: Dish + dish → fusion ---
	"fish_stew+bread_loaf":   "fisherman_plate",
	"mushroom_soup+herb_broth": "deep_forest_soup",
	"honey_cake+berry_pie":   "festival_dessert",
	"salted_fish+bread_loaf": "harbour_lunch",
	"smoked_fish+bread_loaf": "traveller_meal",
	"herb_bread+fish_stew":   "comfort_meal",
	"apple_cake+honey":       "golden_apple_cake",
	"clam_chowder+bread_loaf": "dock_workers_special",

	# --- Tier 4: Special / story-gated ---
	"honey_cake+herb":        "memory_cake",
	"fish_stew+mushroom_soup": "island_feast",
	"seafood_soup+herb_bread": "lighthouse_dinner",
	"comfort_meal+honey_cake": "driftwood_special",
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
