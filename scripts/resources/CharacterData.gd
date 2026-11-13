class_name CharacterData
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
# The real roguelike this character comes from (the sheet's Game column,
# e.g. "Slay the Spire"; several are joined by ", "). Shown as a "From: <game>" line on character
# select / Collection, like the HTML details panel. Purely informational.
@export var source_game: String = ""
# The same games one by one, exactly as the games sheet spells them — what to match
# against when a character comes from several (a game name can hold a comma, so
# `source_game` cannot be split back apart).
@export var source_games: PackedStringArray = PackedStringArray()
# The games whose SOUNDTRACKS this character's ranks draw songs from
# (docs/games-first-redesign.md §20.9): every game in the sheet's Game column
# (`;`-separated) that is on the chart. Isaac draws from two, The Binding of
# Isaac and Rebirth.
@export var music_games: Array[StringName] = []

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

# Starting items — array of item ids (the RELICS of the sheet's Starting loadout)
@export var starting_items: Array[StringName] = []

# The LOOT of the sheet's Starting loadout, put in the pack at run start
# (GameState.grant_starting_loot): {type, id} for a named piece — a weapon starts
# EMPTY, like one found — or {type, count[, tag]} for "N random [tag] <kind>"
# ("1 random joker card", "1 random wand"), rolled fresh each run.
@export var starting_loot: Array = []

# Starting weapon id (or &"" for none)
@export var starting_weapon: StringName = &""

# === Games-first redesign (2.0) starting loadout ===
# A character gives four things (docs/players-design.md §3): its level-up
# condition, its Health (`base_max_hp`, reused as GameState.hp / max_hp), its
# gold, and its starting loot. NO stats — the starting verbs (Bash, Dash, Push,
# …) and their Random points were taken off the sheet on 13 Nov 2026, and the
# mechanics that differ between runs belong to the PLAYER (PlayerData).
#
# `start_gold` (§14) is the gold the character opens the run holding, and it is
# the WHOLE of a run's starting purse — gold never carries between runs.
@export var start_gold: int = 0

# === Level-up mechanic ===
# Each character levels up by meeting `level_up_condition` — an honour-system
# Yes/No question shown on the post-game verification modal. On a level-up the
# `level_up_stats` are applied and a reward of `level_up_reward_type` is granted.
# `level_up_reward` stays as the human-readable summary shown on the modal.
@export var level_up_condition: String = ""
@export var level_up_reward: String = ""

# What a level-up pays besides its reward type: only Max Health and gold now
# ({"max_hp": 1} for Rodney, {"gold": 1} for the Manager). A character gives no
# stats (docs/players-design.md §3) — the generator refuses a Reward naming a
# verb. Applied through GameState.apply_level_up_stats.
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

# THE ART AS WORN (Customization, docs/customization.md): the costume the player
# has chosen for this character's full portrait / icon, else its own. Every screen
# that draws a character reads these, not `portrait` and `icon`; `icon` already
# falls back to the portrait here, so `ch.icon if ch.icon != null else ch.portrait`
# is `shown_icon()`.
func shown_portrait() -> Texture2D:
	var cos: Node = _cosmetics()
	return cos.portrait_of(self) if cos != null else portrait

func shown_icon() -> Texture2D:
	var cos: Node = _cosmetics()
	if cos != null:
		return cos.icon_of(self)
	return icon if icon != null else portrait

func _cosmetics() -> Node:
	var tree := Engine.get_main_loop()
	return (tree as SceneTree).root.get_node_or_null(^"Cosmetics") if tree is SceneTree else null

# Art base name, falling back to the de-spaced display name when `file` is unset
# (mirrors GoalEnemyData.art_file()).
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
