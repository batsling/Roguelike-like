class_name CombatEconomy
extends RefCounted

# Single source of truth for the run's GOLD economy — every gold reward the
# player earns from combat and from clearing a game section is defined here, so
# the live combat scenes and the offline economy simulator (tools/economy_sim)
# read the exact same numbers. Tune the economy by editing the constants below;
# nothing else hard-codes a gold reward.
#
# Pure + side-effect free (no scene, no GameState writes) so it is trivially
# unit-testable and safe to call from the simulator. Callers apply the returned
# amounts via GameState.change_gold themselves.
#
# The two combat styles reach the SAME per-floor gold by different delivery,
# both tuned to COMBAT_GOLD_BY_TIER below so neither style out-earns the other:
#   * Deckbuilder — a flat per-combat purse (elite ×1.5), sized so a floor's
#     ~3.3 combats + 1 elite hit the tier target.
#   * Action      — a chance-based coin dropped after each cleared room (walked
#     over like the consumable ground loot); the floor's room count grows with
#     tier, so a near-flat coin makes each floor's total track the tier target.

# --- Shared target: combat gold per FLOOR, by run tier --------------------
# Indexed by RunDifficulty.Tier (LOW, MEDIUM, HIGH, INSANE). This is the
# balanced amount every combat style aims to pay per game floor (excluding the
# section reward). The per-style tables below are tuned to hit it; verify with
# tools/economy_sim after changing anything here. Trimmed ~12% below the earlier
# 72/95/110/135 curve to bring whole-run income down ~10% (the fixed section
# reward is unchanged, so combat carries the full cut).
const COMBAT_GOLD_BY_TIER := [63, 84, 97, 119]

# --- Deckbuilder: flat per-combat purse by tier ---------------------------
# Per non-elite combat; the elite/boss pays ELITE_GOLD_MULT×. A floor's ~3.3
# combats + 1 elite (= ~4.8 purses) land on COMBAT_GOLD_BY_TIER.
const DECKBUILDER_COMBAT_GOLD_BY_TIER := [13, 18, 20, 25]
const ELITE_GOLD_MULT := 1.5

# --- Section reward: granted once per game beaten, by run difficulty tier --
# Indexed by RunDifficulty.Tier (LOW, MEDIUM, HIGH, INSANE).
const SECTION_GOLD_BY_TIER := [10, 15, 25, 35]

# --- Action: chance-based per-room gold drop ------------------------------
# A coin may drop after each cleared room / boss (roll_action_combat_gold). The
# action floor's ROOM COUNT grows with tier at almost exactly the rate
# COMBAT_GOLD_BY_TIER does, so a FLAT coin makes each floor's total track the
# target across all tiers on its own — no per-tier scaling needed. Chance-based
# on purpose (action rooms also drop consumables). Mean coin ~35 over ~3.5-6.4
# fights/floor at 50% each lands on the target.
const ACTION_GOLD_DROP_CHANCE := 0.5
const ACTION_GOLD_MIN := 23
const ACTION_GOLD_MAX := 47

# --- Shop item prices: ONE coherent scale for every shop -------------------
# Indexed by item rarity (Common, Uncommon, Rare, Epic, Legendary). Every shop —
# the deckbuilder merchant, the action-floor merchant, and the overworld
# encounter shop — prices items from this one table, so identical rarities cost
# the same wherever the player buys them. Sized against measured run income (see
# tools/economy_sim): with run income trimmed ~10%, the low/mid tiers
# (Common/Uncommon/Rare) are nudged up so a run affords a meaningful-but-limited
# handful of items across all its shops (items compete with potions / removal).
const SHOP_ITEM_PRICE_BY_RARITY := [30, 55, 85, 115, 160]

# Purse for one deckbuilder combat at `tier`, before the elite multiplier.
static func deckbuilder_combat_gold(tier: int, is_elite: bool) -> int:
	var t: int = clampi(tier, 0, DECKBUILDER_COMBAT_GOLD_BY_TIER.size() - 1)
	var amt: int = int(DECKBUILDER_COMBAT_GOLD_BY_TIER[t])
	if is_elite:
		amt = int(amt * ELITE_GOLD_MULT)
	return amt

# Section-clear reward for the given run tier (clamped into range).
static func section_reward_gold(tier: int) -> int:
	return SECTION_GOLD_BY_TIER[clampi(tier, 0, SECTION_GOLD_BY_TIER.size() - 1)]

# Rolls the gold dropped by one cleared action room: 0 when the chance roll
# fails, otherwise a flat coin amount. Callers drop the returned amount on the
# floor as a pickup. `tier` is unused (per-floor gold scales via room count, not
# coin size) but kept so callers can pass it uniformly with the other styles.
static func roll_action_combat_gold(_tier: int, rng: RandomNumberGenerator) -> int:
	if rng.randf() >= ACTION_GOLD_DROP_CHANCE:
		return 0
	return rng.randi_range(ACTION_GOLD_MIN, ACTION_GOLD_MAX)

# Shop price for an item of `rarity` (0..4), the same in every shop. Clamped so
# an out-of-range rarity falls back to the nearest end of the scale.
static func shop_item_price(rarity: int) -> int:
	var r: int = clampi(rarity, 0, SHOP_ITEM_PRICE_BY_RARITY.size() - 1)
	return int(SHOP_ITEM_PRICE_BY_RARITY[r])
