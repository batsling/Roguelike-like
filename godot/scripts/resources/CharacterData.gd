class_name CharacterData
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

# Starting stats
@export var base_max_hp: int = 75
@export var base_strength: int = 0
@export var base_dexterity: int = 0
@export var base_intelligence: int = 0
@export var base_charisma: int = 0
@export var base_luck: int = 0
@export var base_max_energy: int = 3
@export var base_hand_size: int = 5

# Starting deck — array of card ids. Duplicates are allowed (e.g. five Strikes).
@export var starting_deck: Array[StringName] = []

# Starting items — array of item ids
@export var starting_items: Array[StringName] = []

# Starting weapon id (or &"" for none)
@export var starting_weapon: StringName = &""

# Level-up trigger (description; mechanic added later)
@export var level_up_condition: String = ""
@export var level_up_reward: String = ""

# Visuals
@export var portrait: Texture2D
@export var portrait_color: Color = Color.WHITE
