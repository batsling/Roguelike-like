extends Node

# Canonical run-persistent state. Survives between floors, resets on new run.
# Transient per-combat state lives in DeckbuilderCombat (and equivalents)
# and is not stored here.

signal hp_changed(new_hp: int, new_max: int)
signal gold_changed(new_gold: int)
signal stats_changed
signal deck_changed
signal inventory_changed
signal current_game_changed(game_id: StringName)

# === Identity / progression ===
var character_id: StringName = &""
var current_game_id: StringName = &""
var start_game_id: StringName = &""
var amulet_game_id: StringName = &""
var visited_games: Array[StringName] = []
var beaten_games: Array[StringName] = []
var total_games_beaten: int = 0

# === Player vitals ===
var max_hp: int = 75
var hp: int = 75
var max_energy: int = 3
var hand_size: int = 5

# === Stats ===
var strength: int = 0
var dexterity: int = 0
var intelligence: int = 0
var charisma: int = 0
var luck: int = 0

# === Economy ===
var gold: int = 99

# === Deck / items ===
# Each entry is a CardInstance (runtime wrapper around CardData) — see
# CardInstance.gd in scripts/runtime/. For Phase 1a we'll allow raw
# CardData here too and upgrade to wrappers when upgrades land.
var deck: Array = []
var inventory: Array = []                # Array[ItemData]
var equipped_weapon: ItemData = null

# === Run-scope resources ===
var dash_charges: int = 0
var reroll_charges: int = 0
var skip_charges: int = 0
var fov_bonus: int = 0
var discovery: int = 0

# === Curses / status ===
var active_curses: Array = []            # Array[Dictionary] for now
var pending_combat_statuses: Array = []  # carryover from events

# === Phase ===
enum Phase { MENU, OVERWORLD, EVENT, COMBAT, DEAD, ESCAPE, WIN }
var phase: Phase = Phase.MENU

# ---------------------------------------------------------------------------
# Mutation API — UI and combat scenes go through these so signals fire.
# ---------------------------------------------------------------------------

func reset_run() -> void:
	character_id = &""
	current_game_id = &""
	start_game_id = &""
	amulet_game_id = &""
	visited_games.clear()
	beaten_games.clear()
	total_games_beaten = 0
	max_hp = 75
	hp = 75
	max_energy = 3
	hand_size = 5
	strength = 0
	dexterity = 0
	intelligence = 0
	charisma = 0
	luck = 0
	gold = 99
	deck.clear()
	inventory.clear()
	equipped_weapon = null
	dash_charges = 0
	reroll_charges = 0
	skip_charges = 0
	fov_bonus = 0
	discovery = 0
	active_curses.clear()
	pending_combat_statuses.clear()
	phase = Phase.MENU

func apply_character(char_data: CharacterData) -> void:
	character_id = char_data.id
	max_hp = char_data.base_max_hp
	hp = max_hp
	max_energy = char_data.base_max_energy
	hand_size = char_data.base_hand_size
	strength = char_data.base_strength
	dexterity = char_data.base_dexterity
	intelligence = char_data.base_intelligence
	charisma = char_data.base_charisma
	luck = char_data.base_luck

	deck.clear()
	for card_id in char_data.starting_deck:
		var c: CardData = Data.get_card(card_id)
		if c != null:
			deck.append(c)

	inventory.clear()
	for item_id in char_data.starting_items:
		var it: ItemData = Data.get_item(item_id)
		if it != null:
			inventory.append(it)

	if char_data.starting_weapon != &"":
		equipped_weapon = Data.get_item(char_data.starting_weapon)

	emit_signal("stats_changed")
	emit_signal("hp_changed", hp, max_hp)
	emit_signal("deck_changed")
	emit_signal("inventory_changed")

func set_hp(new_hp: int) -> void:
	hp = clamp(new_hp, 0, max_hp)
	emit_signal("hp_changed", hp, max_hp)

func change_hp(delta: int) -> void:
	set_hp(hp + delta)

func set_gold(new_gold: int) -> void:
	gold = max(0, new_gold)
	emit_signal("gold_changed", gold)

func change_gold(delta: int) -> void:
	set_gold(gold + delta)

func is_dead() -> bool:
	return hp <= 0
