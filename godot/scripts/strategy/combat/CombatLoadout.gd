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

# The chosen cards (Array[CardData], length 0..MAX_SLOTS).
var cards: Array = []

# The choosable pool: every non-basic, deduped card in the deck. Basic
# strikes/defends live on the basic Attack/Defend actions, so they're
# filtered out (same rule the old AbilityPool used).
static func available_from_deck(deck: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for entry in deck:
		var card: CardData = _extract_card(entry)
		if card == null or _is_basic(card):
			continue
		if seen.has(card.id):
			continue
		seen[card.id] = true
		out.append(card)
	return out

static func _extract_card(entry) -> CardData:
	if entry == null:
		return null
	if entry is CardData:
		return entry
	if entry is CardInstance and entry.data is CardData:
		return entry.data
	return null

static func _is_basic(card: CardData) -> bool:
	return card.tags.has("strike") or card.tags.has("defend")

# True if any of the card's effects targets a single enemy — the BattleView
# uses this to decide whether a play needs an enemy click.
static func wants_enemy_target(card: CardData) -> bool:
	for e in card.effects:
		if str(e.get("target", "")) == "enemy":
			return true
	return false
