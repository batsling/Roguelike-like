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
# Strength / Dexterity / Intelligence / Charisma drive the derived
# combat statuses (Power / Defense / Arcane / Persistence) and the
# event-roll bonuses. Constitution is roll-only for now. Speed is
# mode-interpreted (extra cards / move speed / tile-move speed) and
# starts at 0 — gained via items / level-up only.
var strength: int = 0
var dexterity: int = 0
var intelligence: int = 0
var charisma: int = 0
var constitution: int = 0
var luck: int = 0
var speed: int = 0

# === Economy ===
var gold: int = 99

# === Deck / items ===
# Each entry is a CardInstance (runtime wrapper around CardData) — see
# CardInstance.gd in scripts/runtime/. For Phase 1a we'll allow raw
# CardData here too and upgrade to wrappers when upgrades land.
var deck: Array = []
var inventory: Array = []                # Array[ItemData]
var equipped_weapon: ItemData = null

# === Action-mode loadout (StringName ids resolved via Data) ===
# Empty / unset means "auto-pick from deck on combat start".
var action_basic_attack_id: StringName = &""
var action_ability_ids: Array[StringName] = []

# === Run-scope resources ===
# Skip is removed from the stat set — the only "skip" is the
# verification-screen "didn't play the real game" choice with the
# fixed HP penalty.
var dash_charges: int = 0
var reroll_charges: int = 0
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
	constitution = 0
	luck = 0
	speed = 0
	gold = 99
	deck.clear()
	inventory.clear()
	equipped_weapon = null
	action_basic_attack_id = &""
	action_ability_ids.clear()
	dash_charges = 0
	reroll_charges = 0
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
	constitution = char_data.base_constitution
	luck = char_data.base_luck
	speed = char_data.base_speed

	deck.clear()
	for card_id in char_data.starting_deck:
		var c: CardData = Data.get_card(card_id)
		if c != null:
			deck.append(CardInstance.from_data(c))

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

func set_current_game(id: StringName) -> void:
	current_game_id = id
	emit_signal("current_game_changed", id)

func set_max_hp(new_max: int, heal_to_full: bool = false) -> void:
	# Routes through Stats so Constitution auto-gain fires off the
	# delta. Pass heal_to_full=true to restore HP to the new max
	# (e.g., on level-up). Otherwise current HP is just clamped.
	var old_max: int = max_hp
	max_hp = max(1, new_max)
	if heal_to_full:
		hp = max_hp
	else:
		hp = mini(hp, max_hp)
	Stats.note_max_hp_change(max_hp, old_max)
	emit_signal("hp_changed", hp, max_hp)

func change_max_hp(delta: int) -> void:
	set_max_hp(max_hp + delta)

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

# ---------------------------------------------------------------------------
# Action-mode loadout
# ---------------------------------------------------------------------------

const ACTION_ABILITY_SLOTS := 3

# Returns { "basic": CardData, "abilities": Array of CardData|null (size 3) }.
# If the player hasn't set a loadout, auto-fills from the deck so the
# action arena is always playable. Equipment screen in commit 6 will
# let the player customize.
func get_action_loadout() -> Dictionary:
	var basic: CardData = Data.get_card(action_basic_attack_id)
	var abilities: Array = []
	for id in action_ability_ids:
		abilities.append(Data.get_card(id))
	while abilities.size() < ACTION_ABILITY_SLOTS:
		abilities.append(null)

	if basic == null:
		basic = _auto_pick_basic()
	var taken: Array[StringName] = []
	if basic != null:
		taken.append(basic.id)
	for i in range(ACTION_ABILITY_SLOTS):
		if abilities[i] != null:
			taken.append(abilities[i].id)
			continue
		var pick: CardData = _auto_pick_ability(taken)
		if pick != null:
			abilities[i] = pick
			taken.append(pick.id)
	return {"basic": basic, "abilities": abilities}

func _auto_pick_basic() -> CardData:
	# Prefer a Strike (its tags include "strike"); otherwise first
	# Attack-type card in the deck.
	for c in deck:
		if c is CardInstance and c.data != null and c.data.tags.has("strike"):
			return c.data
	for c in deck:
		if c is CardInstance and c.data != null and c.data.is_attack():
			return c.data
	return null

func _auto_pick_ability(exclude_ids: Array[StringName]) -> CardData:
	for c in deck:
		if not (c is CardInstance) or c.data == null:
			continue
		if c.data.id in exclude_ids:
			continue
		return c.data
	return null
