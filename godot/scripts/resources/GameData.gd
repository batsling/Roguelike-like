class_name GameData
extends Resource

# A node on the influence graph — represents a real video game.

enum GameType { ACTION, STRATEGY, DECKBUILDER, TRADITIONAL }

@export var id: StringName                # canonical key (lowercase slug)
@export var display_name: String
@export var year: int = 0
@export var type: GameType = GameType.DECKBUILDER

# Outgoing influence edges — names (StringName ids) of games this one influenced.
# The graph is directed; build the inverse at load time if needed.
@export var games_influenced: Array[StringName] = []

# Tags layered on top of type (e.g. "traditional", "horror", "platformer").
# Drives flavor without owning the combat mode.
@export var tags: PackedStringArray = PackedStringArray()

# Optional pool overrides — restrict which enemies/items spawn at this floor.
# Empty arrays mean "use the default pool for this type".
@export var enemy_pool: Array[StringName] = []
@export var item_pool: Array[StringName] = []

# Hooks for game-specific special effects (Phase 6 work — left here as a
# placeholder so we don't have to migrate later).
@export var special_effects: PackedStringArray = PackedStringArray()

# Visuals
@export var cover_image: Texture2D
