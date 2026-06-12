class_name ActionTranslation
extends Resource

# Central, editable mapping from turn-based (deckbuilder/strategy) combat
# concepts to their real-time Action-combat equivalents. ActionCombat reads
# every "what does this idea mean in the arena?" tunable from here, so the feel
# can be retuned in one place (edit data/action_translation.tres) and any item
# whose effects route through the shared EffectSystem inherits the translation
# for free.
#
# Reference it from anywhere via Data.action_translation.
#
# === Concept map ===
#   Turn (one-shot) -> Combat room. Entering the Nth combat room counts as the
#                      Nth "turn" for turn-NUMBER-gated one-shots (Horn Cleat's
#                      "2nd turn", if_turn). Toggle with room_is_turn.
#   Turn (recurring)-> A real-time tick every turn_tick_secs seconds (the
#                      turn_tick heartbeat). Decays stack statuses
#                      (Vulnerable/Weak/Blind/…) AND paces recurring per-turn
#                      item effects — the per-turn attack window (Ornamental
#                      Fan / Shuriken) and "every N turns" grants (Happy
#                      Flower) — so they're time-based, not tied to room
#                      transitions. Matches the deckbuilder/strategy turn cadence.
#   Energy (gain)   -> Haste window. Each point grants energy_buff_secs_per_point
#                      seconds during which every cooldown ticks haste_multiplier
#                      faster (Adrenaline, Nunchaku/Happy Flower's +Energy).
#   Energy (lose)   -> Slow window (slow_multiplier).
#   Draw 1          -> One temporary extra auto-cast slot living
#                      draw_temp_slot_secs seconds: more deck cards cool down
#                      and fire in parallel for a burst.
#   Discard 1       -> Collapse one temporary auto-slot early; with none left,
#                      lengthen the base slot's cooldown by discard_base_penalty
#                      seconds.
#   Block / Heal /  -> Applied unchanged — same stat on the shared CombatActor,
#   Status             so they need no translation and aren't parameterised here.
#
# To translate a NEW concept: add a tunable + (if useful) a helper below, wire
# the matching scene callback in ActionCombat to read it, and document the row
# in the concept map above.

# --- Turn <-> room -----------------------------------------------------------
# When true, each combat room entered advances the turn counter that turn-gated
# items read (the Nth room == the Nth turn).
@export var room_is_turn: bool = true
# Real-time length of one "turn" for the status-decay tick.
@export var turn_tick_secs: float = 10.0

# --- Energy <-> tempo --------------------------------------------------------
# Seconds of Haste/Slow granted per point of energy gained/lost.
@export var energy_buff_secs_per_point: float = 1.0
# Cooldown speed-up while a Haste window is live (>1 = faster).
@export var haste_multiplier: float = 1.3
# Cooldown slow-down while a Slow window is live (<1 = slower).
@export var slow_multiplier: float = 0.7

# --- Draw / discard <-> auto-cast slots -------------------------------------
# Lifetime of a draw-spawned temporary auto-cast slot.
@export var draw_temp_slot_secs: float = 6.0
# Seconds added to the base auto-slot cooldown when a discard can't collapse a
# temporary slot.
@export var discard_base_penalty: float = 1.5

# --- Click slots -------------------------------------------------------------
# Floor on click-slot cooldown so a 0-cost Strike can't fire every frame.
@export var min_click_cooldown: float = 0.35

# --- Curses ------------------------------------------------------------------
# An eot curse card runs as a dedicated "bad slot" whose long cooldown is this
# many turns' worth of real time (curse_cooldown_turns * turn_tick_secs). When
# it elapses the curse applies its translated eot effect to the player. The
# deckbuilder "end of turn" maps to this slow cooldown in the real-time arena.
@export var curse_cooldown_turns: float = 3.0

# Seconds of Haste/Slow granted for `points` of energy.
func energy_to_seconds(points: int) -> float:
	return float(points) * energy_buff_secs_per_point

# Net cooldown tempo multiplier given which timed windows are currently live.
# Haste and Slow can overlap (e.g. gain_energy then lose_energy) and resolve to
# their product.
func tempo_multiplier(haste_active: bool, slow_active: bool) -> float:
	var mult: float = 1.0
	if haste_active:
		mult *= haste_multiplier
	if slow_active:
		mult *= slow_multiplier
	return mult
