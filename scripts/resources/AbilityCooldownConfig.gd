class_name AbilityCooldownConfig
extends Resource

# Phase 6: single tunable that derives tactical cooldowns from deck cards.
#
#   cooldown = card.cooldown_override if >= 0
#            else base + max(0, card.cost) * cost_weight + rarity_weights[rarity]
#
# X-cost cards (cost == -1) are treated as cost 1 for the formula so they
# don't collapse to the floor cooldown.

@export var base_cooldown: int = 2
@export var cost_weight: int = 1
# Indexed by CardData.Rarity (STARTER, COMMON, UNCOMMON, RARE, LEGENDARY).
@export var rarity_weights: Array[int] = [0, 0, 1, 2, 3]

func compute(card: CardData) -> int:
	if card == null:
		return base_cooldown
	if card.cooldown_override >= 0:
		return card.cooldown_override
	var energy: int = card.cost
	if energy < 0:
		energy = 1
	var rw: int = 0
	if card.rarity >= 0 and card.rarity < rarity_weights.size():
		rw = rarity_weights[card.rarity]
	return maxi(1, base_cooldown + energy * cost_weight + rw)
