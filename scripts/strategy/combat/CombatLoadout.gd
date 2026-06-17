class_name CombatLoadout
extends RefCounted

# The player's tactical loadout for a single combat: up to 3 cards chosen
# on the pre-combat screen from the run deck. Replaces the old AbilityPool
# (whole-deck-as-cooldown-abilities) model.
#
# Each slotted card is played by spending one of its run-persistent uses
# (tracked on GameState.card_uses, NOT here). The loadout itself is just the
# chosen-card list plus a couple of authoring helpers; per-turn play limits
# (one card play baseline, +1 per gain-energy) live on BattleView, and use
# accounting lives on GameState.

const MAX_SLOTS := 3

# The chosen card INSTANCES (Array[CardInstance], length 0..MAX_SLOTS). Each is
# a distinct physical card from the deck, so two copies of the same card are
# two independent slots with their own uses (CardInstance.uses).
var cards: Array = []
# The equipped weapon card INSTANCE or null. One per combat; it replaces the
# basic Attack action and is usable once per turn with no use depletion.
var weapon: CardInstance = null

# The choosable pool for the 3 slots: every non-basic, non-weapon card INSTANCE
# in the deck. NOT deduped — each copy is its own slottable card. Basics live on
# Attack/Defend; weapons live in the weapon slot (see weapon_cards_from_deck).
static func available_from_deck(deck: Array) -> Array:
	var out: Array = []
	for entry in deck:
		if not (entry is CardInstance) or entry.data == null:
			continue
		if _is_basic(entry.data):
			continue
		# Weapons live in the weapon slot, not the card pool.
		if is_weapon(entry.data) or entry.source_weapon_id != 0:
			continue
		out.append(entry)
	return out

# Weapon card INSTANCES in the deck (each copy listed). A card is a weapon if
# it's tagged "weapon" or was granted by a weapon item (source_weapon_id).
static func weapon_cards_from_deck(deck: Array) -> Array:
	var out: Array = []
	for entry in deck:
		if not (entry is CardInstance) or entry.data == null:
			continue
		if is_weapon(entry.data) or entry.source_weapon_id != 0:
			out.append(entry)
	return out

static func is_weapon(card: CardData) -> bool:
	return card != null and card.tags.has("weapon")

static func _is_basic(card: CardData) -> bool:
	return card.tags.has("strike") or card.tags.has("defend")

# True if any of the card's effects targets a single enemy — the BattleView
# uses this to decide whether a play needs an enemy click.
static func wants_enemy_target(card: CardData) -> bool:
	# Indiscriminate cards pick their own random targets, so the play UI must
	# not ask for an enemy click (Bouncing Flask, Blood Magic).
	if card.addons.has(&"indiscriminate") or card.addons.has(&"cleave"):
		return false
	for e in card.effects:
		if bool(e.get("indiscriminate", false)):
			return false
		if str(e.get("target", "")) == "enemy":
			return true
	return false
