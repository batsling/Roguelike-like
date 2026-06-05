class_name StrategyTranslation
extends Resource

# Central, editable mapping from turn-based combat concepts to their tactical
# (Strategy) equivalents. Strategy keeps turns, block, heal and status as-is
# (real turns; the same stats on the BattleUnit), but ENERGY and DRAW have no
# direct analogue, so they're remapped here. BattleView reads every "what does
# this mean in tactical combat?" tunable from this one resource, so the feel can
# be retuned by editing data/strategy_translation.tres and any item whose
# effects route through the shared EffectSystem inherits the translation.
#
# Reference it from anywhere via Data.strategy_translation.
#
# === Concept map ===
#   Turn / Block /  -> Unchanged. Real discrete turns; block/heal/status apply
#   Heal / Status      directly to the BattleUnit, same as the other modes.
#   Energy (gain)   -> Empower charge. Each point banks empower_per_energy worth
#                      of bonus that boosts your NEXT card's damage / block value
#                      (and status stacks, if empower_scales_status), then the
#                      whole charge resets. Grants no extra plays. Banks across
#                      turns while energy_banks_across_turns is true.
#                      (gain_energy +1 — Nunchaku, Happy Flower, Gremlin Horn.)
#   Energy (lose)   -> Drains banked empower charge, floored at 0.
#   Draw 1          -> Recharge draw_recharges_per_point use(s) on a slotted
#                      card (fewest-uses-first), since there is no hand to draw
#                      into. (draw 1 — Gremlin Horn.)
#   Discard 1       -> Tempo cost: spend discard_plays_per_point card play(s)
#                      this turn.
#   Ice Cream       -> "Energy carries over": a player turn ending without an
#                      ability play banks empower_per_skipped_turn charge. This
#                      accumulates with no cap and persists indefinitely — wait
#                      any number of turns and bank that many charges — until a
#                      card play spends the whole charge at once. (Handled in
#                      BattleView via GameState.has_energy_carryover_item().)
#
# To translate a NEW concept: add a tunable + (if useful) a helper below, wire
# the matching scene callback in BattleView to read it, and document the row.

# --- Energy -> empower charge ---
# Bonus added to a boosted card per banked energy point.
@export var empower_per_energy: int = 1
# Whether a banked charge also adds stacks to status effects (not just
# damage/block value).
@export var empower_scales_status: bool = true
# Whether unspent empower charge persists across your turns (true) or is wiped
# at the end of each of your turns (false). The energy-carryover item (Ice
# Cream) forces persistence regardless, so its banked charge always carries.
@export var energy_banks_across_turns: bool = true
# Ice Cream: empower charge banked each player turn that ends without an ability
# play. Accumulates indefinitely (no cap) and is held until spent.
@export var empower_per_skipped_turn: int = 1

# --- Draw / discard ---
# Card-use recharges granted per point of `draw`.
@export var draw_recharges_per_point: int = 1
# Card plays spent this turn per point of `discard`.
@export var discard_plays_per_point: int = 1

# Total empower bonus for `points` of banked energy.
func empower_amount(points: int) -> int:
	return points * empower_per_energy

# Apply `charge_points` of banked empower to a single effect, returning a fresh
# dict (never mutates the card's shared effect data). dmg/block bump their
# value; status bumps stacks when empower_scales_status. Effects with no
# scalable field pass through unchanged.
func apply_empower(effect: Dictionary, charge_points: int) -> Dictionary:
	var out: Dictionary = effect.duplicate()
	if charge_points <= 0:
		return out
	var amount: int = empower_amount(charge_points)
	match str(out.get("type", "")):
		"dmg", "block":
			out["value"] = int(out.get("value", 0)) + amount
		"status":
			if empower_scales_status:
				out["stacks"] = int(out.get("stacks", 1)) + amount
	return out
