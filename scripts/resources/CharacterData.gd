class_name CharacterData
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
# The real roguelike this character comes from (the sheet's Game column,
# e.g. "Slay the Spire"). Shown as a "From: <game>" line on character
# select / Collection, like the HTML details panel. Purely informational.
@export var source_game: String = ""

# Starting stats
@export var base_max_hp: int = 75
@export var base_strength: int = 0
@export var base_dexterity: int = 0
@export var base_intelligence: int = 0
@export var base_charisma: int = 0
@export var base_constitution: int = 0
@export var base_luck: int = 0
@export var base_speed: int = 0
@export var base_max_energy: int = 3
@export var base_hand_size: int = 5

# Starting deck — array of card ids. Duplicates are allowed (e.g. five Strikes).
# Generic basics (&"strike" / &"defend") are resolved to this character's
# variant at deck-build time when a card named "<base>_<id>" exists — e.g.
# &"strike" -> &"strike_ironclad". See Data.variant_card_id. So every character
# can keep the same generic deck list yet get its own Strike/Defend.
@export var starting_deck: Array[StringName] = []

# Starting items — array of item ids
@export var starting_items: Array[StringName] = []

# Starting weapon id (or &"" for none)
@export var starting_weapon: StringName = &""

# === Games-first redesign (2.0) starting loadout ===
# The no-combat rework (docs/games-first-redesign.md §3) gives each character a
# tiny starting Health and a small pool of verb/consumable charges instead of a
# combat stat block. Health/Max Health reuse GameState.hp / GameState.max_hp
# (set from `base_max_hp` at run start), so no separate 2.0 health field is
# needed — only the verbs are new. `dash` maps onto GameState.dash_charges;
# the rest map onto same-named GameState fields (see GameState grant_run_stat).
# All default 0, matching the current combat roster which never sets them.
@export var start_bash: int = 0
@export var start_dash: int = 0
# Push (Manager, from Raccoin) — a board-timing verb that shoves a following
# enemy back one space, delaying its next attack by a game (§7.2). Maps onto
# GameState.push, like the other start_* verbs map onto same-named fields.
@export var start_push: int = 0
@export var start_transmute: int = 0
@export var start_scramble: int = 0
@export var start_bombs: int = 0
@export var start_keys: int = 0

# === Level-up mechanic ===
# Each character levels up by meeting `level_up_condition` — an honour-system
# Yes/No question shown on the post-game verification modal. On a level-up the
# `level_up_stats` are applied and a reward of `level_up_reward_type` is granted.
# `level_up_reward` stays as the human-readable summary shown on the modal.
@export var level_up_condition: String = ""
@export var level_up_reward: String = ""

# Stat/ability bonuses granted per level-up. Keys are GameState stat/ability
# ids (strength, dexterity, intelligence, charisma, constitution, luck, speed,
# dash, reroll, fov, discovery, max_hp). The special key "random" grants N
# random points spread across strength/dexterity/intelligence/charisma.
#   Zoe: {"dexterity": 1, "dash": 1}
@export var level_up_stats: Dictionary = {}

# Reward handed out on level-up. One of: &"none", &"gold", &"item", &"card",
# &"scroll_and_potion", &"random_sized_chest" (the chest's SIZE is rolled at grant
# time — Data.roll_chest_size_choices — instead of fixed; Vampire Survivors).
# `level_up_reward_amount` carries the gold amount for the &"gold" type.
@export var level_up_reward_type: StringName = &"none"
@export var level_up_reward_amount: int = 0
# For the &"item" (chest) reward: how many items the chest offers to pick one
# from, when the sheet named a SIZE — Data.CHEST_SIZE_CHOICES, i.e. Small = 1,
# Medium = 2, Large = 3 (Zagreus), Huge = 5. 0 = unsized, so the reward screen
# uses its own default. Ignored by the other reward types; &"random_sized_chest"
# rolls its size at grant time instead of reading this.
@export var level_up_reward_chest_choices: int = 0
# For the &"card" reward: the class tag the offered cards are drawn from
# (e.g. &"ironclad"). Empty = the full reward pool. See Data.reward_card_pool.
@export var level_up_card_tag: StringName = &""

# Visuals
# Art base name (the sheet's File column) — resolves to
# images2.0/characters/Full/<file>.png and images2.0/characters/Icon/<file>.png.
# Needed because a display name and its art stem can differ (Erratic Deck ->
# ErraticDeck); falls back to the de-spaced display name when unset.
@export var file: String = ""
@export var portrait: Texture2D
# Small token image used for the player marker in action & tactical combat
# (the round in-world avatar). Falls back to `portrait` when unset.
@export var icon: Texture2D
@export var portrait_color: Color = Color.WHITE

# Art base name, falling back to the de-spaced display name when `file` is unset
# (mirrors GoalEnemyData.art_file()).
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
