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
# The three combat styles pay very differently on purpose:
#   * Deckbuilder — a FLAT per-combat purse that steps up with run progress,
#     multiplied for elite/boss fights.
#   * Action      — NO per-combat gold; action floors earn only the post-game
#     section reward (plus incidental item/King-Bomber gold). Kept explicit here
#     so the asymmetry is visible and tunable in one place.
#   * Strategy    — per-enemy-kill drops rolled from each archetype's table
#     (data-driven via StrategyEnemyData, falling back to STRATEGY_ENEMY_GOLD).

# --- Deckbuilder: flat per-combat purse by games beaten -------------------
# amount = base, stepped up at the two thresholds, then the elite multiplier.
const DECKBUILDER_GOLD_BASE := 20
const DECKBUILDER_GOLD_MID := 35     # once total_games_beaten >= *_MID_AT
const DECKBUILDER_GOLD_HIGH := 55    # once total_games_beaten >= *_HIGH_AT
const DECKBUILDER_GOLD_MID_AT := 5
const DECKBUILDER_GOLD_HIGH_AT := 10
const ELITE_GOLD_MULT := 1.5

# --- Section reward: granted once per game beaten, by run difficulty tier --
# Indexed by RunDifficulty.Tier (LOW, MEDIUM, HIGH, INSANE).
const SECTION_GOLD_BY_TIER := [10, 15, 25, 35]

# --- Shop item prices: ONE coherent scale for every shop -------------------
# Indexed by item rarity (Common, Uncommon, Rare, Epic, Legendary). Both the
# deckbuilder merchant and the overworld encounter shop price items from this
# table, so identical rarities cost the same wherever the player buys them.
# Sized against measured run income (see tools/economy_sim): a mean run earns
# roughly this table's Rare price × ~6 in total gold, so a run affords a
# meaningful-but-limited handful of items across all its shopping.
const SHOP_ITEM_PRICE_BY_RARITY := [25, 45, 75, 115, 160]

# --- Strategy: per-archetype enemy-kill gold drop -------------------------
# Fallback for kinds not on the enemiesS sheet; StrategyEnemyData's gold_ fields
# win when present (see strategy_enemy_gold_table).
const STRATEGY_ENEMY_GOLD := {
	"snake":       { "gold_chance": 0.50, "gold_min":  3, "gold_max":  8 },
	"rattlesnake": { "gold_chance": 0.60, "gold_min":  5, "gold_max": 10 },
	"hobgoblin":   { "gold_chance": 0.60, "gold_min":  4, "gold_max":  9 },
	"troll":       { "gold_chance": 0.90, "gold_min": 12, "gold_max": 24 },
}

# Flat purse for one deckbuilder combat, before the elite multiplier.
static func deckbuilder_combat_gold(total_games_beaten: int, is_elite: bool) -> int:
	var amt: int = DECKBUILDER_GOLD_BASE
	if total_games_beaten >= DECKBUILDER_GOLD_HIGH_AT:
		amt = DECKBUILDER_GOLD_HIGH
	elif total_games_beaten >= DECKBUILDER_GOLD_MID_AT:
		amt = DECKBUILDER_GOLD_MID
	if is_elite:
		amt = int(amt * ELITE_GOLD_MULT)
	return amt

# Section-clear reward for the given run tier (clamped into range).
static func section_reward_gold(tier: int) -> int:
	return SECTION_GOLD_BY_TIER[clampi(tier, 0, SECTION_GOLD_BY_TIER.size() - 1)]

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
	return rng.randi_range(int(table.get("gold_min", 0)), int(table.get("gold_max", 0)))
