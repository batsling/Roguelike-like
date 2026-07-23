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
# The three combat styles reach the SAME per-floor gold by different delivery,
# all tuned to COMBAT_GOLD_BY_TIER below so no style out-earns another:
#   * Deckbuilder — a flat per-combat purse (elite ×1.5), sized so a floor's
#     ~3.3 combats + 1 elite hit the tier target.
#   * Action      — a chance-based coin dropped after each cleared room (walked
#     over like the consumable ground loot); the floor's room count grows with
#     tier, so a near-flat coin makes each floor's total track the tier target.
#   * Strategy    — per-enemy-kill drops (data-driven via StrategyEnemyData,
#     falling back to STRATEGY_ENEMY_GOLD); its ~6 fights already land on the
#     target, so it is the organic reference the other two are matched to.

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

# --- Strategy: per-archetype enemy-kill gold drop -------------------------
# Fallback for kinds not on the enemiesS sheet; StrategyEnemyData's gold_ fields
# win when present (see strategy_enemy_gold_table). A global multiplier trims
# every strategy drop (data-driven .tres included) so the style stays on the
# ~12%-lower COMBAT_GOLD_BY_TIER target without editing the enemy data.
const STRATEGY_GOLD_MULT := 0.88
const STRATEGY_ENEMY_GOLD := {
	"snake":       { "gold_chance": 0.50, "gold_min":  3, "gold_max":  8 },
	"rattlesnake": { "gold_chance": 0.60, "gold_min":  5, "gold_max": 10 },
	"hobgoblin":   { "gold_chance": 0.60, "gold_min":  4, "gold_max":  9 },
	"troll":       { "gold_chance": 0.90, "gold_min": 12, "gold_max": 24 },
}

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

# Gold-drop table for a strategy enemy `kind`: prefers the data-driven
# StrategyEnemyData fields, falls back to STRATEGY_ENEMY_GOLD. Empty dict = no
# drop. Shape: { gold_chance: float, gold_min: int, gold_max: int }.
static func strategy_enemy_gold_table(kind: String) -> Dictionary:
	var d: StrategyEnemyData = null
	if Data != null:
		d = Data.get_strategy_enemy(StringName(kind))
	if d != null and (d.gold_chance > 0.0 or d.gold_max > 0):
		return { "gold_chance": d.gold_chance, "gold_min": d.gold_min, "gold_max": d.gold_max }
	return STRATEGY_ENEMY_GOLD.get(kind, {})

# Rolls one strategy enemy's gold drop (0 when the chance roll fails or the kind
# has no table). Uses the shared table above so the sim and the live BattleView
# agree exactly.
static func roll_strategy_enemy_gold(kind: String, rng: RandomNumberGenerator) -> int:
	var table: Dictionary = strategy_enemy_gold_table(kind)
	if table.is_empty():
		return 0
	if rng.randf() >= float(table.get("gold_chance", 0.0)):
		return 0
	var raw: int = rng.randi_range(int(table.get("gold_min", 0)), int(table.get("gold_max", 0)))
	# Round (not truncate) so small drops aren't over-cut — the style's many
	# low-value drops would otherwise fall well past the intended ~12%.
	return int(round(raw * STRATEGY_GOLD_MULT))
