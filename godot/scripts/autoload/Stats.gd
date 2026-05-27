extends Node

# Mode-aware stat dispatcher. Loads StatDefinitions at startup and
# exposes the queries combat scenes / events / HUD use to read stats.
# See godot/docs/stat-dispatcher.md for the full design.

enum Mode { DECKBUILDER, ACTION, STRATEGY }

const ACTION_DASH_REGEN_SECONDS := 4.0

# Action mode runs "turns" on a real-time timer since there's no
# discrete turn structure. One ACTION_TURN_TICK is the cadence at
# which decaying statuses (Vulnerable, Weak, Frail, Burn, Blind …)
# step down by 1 on every actor in the arena. Picked to feel like a
# Slay-the-Spire-length turn (~15s of arena play ≈ one deckbuilder
# turn of dialogue + planning).
const ACTION_TURN_TICK_SECONDS := 15.0

# Statuses that step down by 1 each turn (deckbuilder + strategy) or
# each ACTION_TURN_TICK (action). Owned here so all three modes
# decay the same set without re-declaring it.
const DECAY_STATUSES: Array[StringName] = [
	&"vulnerable", &"weak", &"frail",
	&"burn", &"poison", &"regeneration",
	&"dodge",   # dodge decays on use too; the 1/turn safety mirrors JS
	&"blind",
]

# Blind: an attacker afflicted with Blind has BLIND_MISS_PCT% chance
# to miss each hit. Roll routes through luck (see roll_blind_miss).
const BLIND_MISS_PCT := 30

var _stat_defs: Dictionary = {}     # StringName -> StatDefinition

func _ready() -> void:
	_load_stat_defs()

func _load_stat_defs() -> void:
	var dir := DirAccess.open("res://data/stats/")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".tres") or fname.ends_with(".res")):
			var res: Resource = load("res://data/stats/" + fname)
			if res is StatDefinition and res.id != &"":
				_stat_defs[res.id] = res
		fname = dir.get_next()
	print("[Stats] Loaded %d stat definitions" % _stat_defs.size())

# ---------------------------------------------------------------------------
# Universal lookups
# ---------------------------------------------------------------------------

func get_value(stat_id: StringName) -> int:
	# Reads the matching field on GameState by name. The stat id must
	# match the GameState field exactly (strength / dexterity / etc.).
	return int(GameState.get(String(stat_id)))

func get_definition(stat_id: StringName) -> StatDefinition:
	return _stat_defs.get(stat_id)

func event_roll_bonus(stat_id: StringName) -> int:
	var def: StatDefinition = _stat_defs.get(stat_id)
	if def == null or not def.grants_event_roll_bonus:
		return 0
	return get_value(stat_id)

# ---------------------------------------------------------------------------
# Combat-start hook — applies universal derived statuses + drains the
# event-queued pending statuses into the actor. Called by every combat
# scene at start_combat() time.
# ---------------------------------------------------------------------------

func apply_derived_statuses(actor: CombatActor, _mode: Mode) -> void:
	for stat_id in _stat_defs:
		var def: StatDefinition = _stat_defs[stat_id]
		if def.derived_status == &"":
			continue
		var per: int = maxi(1, def.derived_per)
		@warning_ignore("integer_division")
		var stacks: int = get_value(stat_id) / per
		if stacks > 0:
			actor.add_status(def.derived_status, stacks)
	for s in GameState.pending_combat_statuses:
		actor.add_status(s.get("status", &""), s.get("stacks", 0))
	GameState.pending_combat_statuses.clear()

# ---------------------------------------------------------------------------
# Damage-type bonus — query during damage resolution. Adds the right
# extras on top of source.power based on damage_type + current mode.
# ---------------------------------------------------------------------------

func damage_bonus(source: CombatActor, damage_type: String, mode: Mode, power_multiplier: int = 1) -> int:
	if source == null:
		return 0
	var bonus: int = source.get_status(&"power") * power_multiplier
	match damage_type:
		"magic":
			bonus += source.get_status(&"arcane")
		"ranged":
			# Dexterity drives ranged damage in both Action and Strategy.
			# Deckbuilder has no ranged distinction — Power covers it.
			if mode == Mode.STRATEGY:
				bonus += _knob_int(&"dexterity", "strategy_ranged_dmg_per_point", 1) * get_value(&"dexterity")
			elif mode == Mode.ACTION:
				bonus += _knob_int(&"dexterity", "action_ranged_dmg_per_point", 1) * get_value(&"dexterity")
		_:
			# melee — Power already counted; STR per-point bonuses in
			# action / strategy land when those modes do.
			pass
	return bonus

# ---------------------------------------------------------------------------
# Speed — mode-specific accessors
# ---------------------------------------------------------------------------

func deckbuilder_bonus_draws_turn_1() -> int:
	var per_3: int = _knob_int(&"speed", "deckbuilder_draws_per_3", 1)
	@warning_ignore("integer_division")
	return (get_value(&"speed") / 3) * per_3

func action_movement_speed() -> float:
	var base: float = _knob_float(&"speed", "action_base_movespeed", 200.0)
	var per: float = _knob_float(&"speed", "action_movespeed_per_point", 10.0)
	return base + get_value(&"speed") * per

func strategy_tiles_per_turn() -> int:
	var base: int = _knob_int(&"speed", "strategy_base_tiles", 1)
	var per: int = _knob_int(&"speed", "strategy_tiles_per_point", 1)
	return base + get_value(&"speed") * per

# ---------------------------------------------------------------------------
# Dash (action mode — others spend the GameState counter directly)
# ---------------------------------------------------------------------------

func action_max_dash_charges() -> int:
	return GameState.dash_charges

# ---------------------------------------------------------------------------
# Luck
# ---------------------------------------------------------------------------

func roll_d20_with_luck(rng: RandomNumberGenerator) -> int:
	return _luck_roll(rng, 20)

# ---------------------------------------------------------------------------
# Addons (Fishing Weight et al)
# ---------------------------------------------------------------------------
#
# "Addons" are named card modifiers from the Keywords column on the
# cardsnew sheet — the compute-style ones with behavior at play time,
# distinct from the bool flags (Exhaust, Ethereal, …) that have been
# CardData fields since day one. Existing bool keywords stay on
# CardData; new entries go into CardData.addons as free-form names
# and dispatch through this file.
#
# The hook point is apply_addons_to_effect, called by each combat
# mode at play resolution — same slot as the existing
# `_apply_card_boosts`. It returns a (possibly new) effect dict with
# any addon-driven values folded in. Damage downstream (Vulnerable,
# Weak, Power) layers on top, matching how boost_cards already works.

func apply_addons_to_effect(effect: Dictionary, card) -> Dictionary:
	# Returns the effect dict, modified for any addons on the card.
	# Today only `dmg` effects get touched (addon-driven block / heal /
	# whatever can follow when a card needs it). The original effect
	# is left alone when the card has no addons.
	if card == null:
		return effect
	var addons: PackedStringArray = card.addons if "addons" in card else PackedStringArray()
	if addons.is_empty():
		return effect
	if String(effect.get("type", "")) != "dmg":
		return effect
	var bonus: int = addon_damage_bonus(card, String(effect.get("damage_type", "")))
	if bonus == 0:
		return effect
	var dup: Dictionary = effect.duplicate()
	dup["value"] = int(dup.get("value", 0)) + bonus
	return dup

func addon_damage_bonus(card, _damage_type: String) -> int:
	# Sum every addon-driven flat damage modifier on the card. Add a
	# damage_type gate inside each arm if an addon should only apply
	# to certain types (Fishing Weight is intentionally type-agnostic
	# since the user said "more damage" — applies to whatever the
	# card already deals).
	if card == null or not ("addons" in card):
		return 0
	var total: int = 0
	for addon_name in card.addons:
		match String(addon_name):
			"fishing_weight":
				total += _fishing_weight_bonus()
			_:
				pass
	return total

func _fishing_weight_bonus() -> int:
	# +1 dmg for every 3 Common, 2 Uncommon, or 1 Rare fish in the
	# loot inventory. Fish loot doesn't exist yet, so this returns
	# 0 today. When fish counters land in GameState.loot (or wherever
	# fish-by-rarity tallies live), swap the body for the real
	# formula — the rest of the pipeline is already wired:
	#
	#   var common: int = int(GameState.loot.get("fish_common", 0))
	#   var uncommon: int = int(GameState.loot.get("fish_uncommon", 0))
	#   var rare: int = int(GameState.loot.get("fish_rare", 0))
	#   @warning_ignore("integer_division")
	#   return common / 3 + uncommon / 2 + rare
	return 0

func decay_actor_statuses(actor: CombatActor) -> void:
	# Step down every decaying status on this actor by 1. Called per
	# actor at end-of-turn (deckbuilder, strategy when statuses land
	# there) and per ACTION_TURN_TICK in action mode.
	#
	# === Canonical turn-boundary ordering ===
	# When the future status-loader wires per-turn ticks (Burn dealing
	# 3, Poison dealing X = stacks, Regen healing X = stacks), the
	# boundary handler MUST follow this order so a Poison stack always
	# lands as damage before it decays:
	#
	#   At turn_start of an actor:
	#     1. Fire every `on_turn_start` status effect using CURRENT
	#        stack counts (so Poison ticks with the stacks it had at
	#        end of previous turn).
	#     2. Call this function to step every `Decay: at start of turn`
	#        status down by 1.
	#
	#   At turn_end of an actor:
	#     1. Fire every `on_turn_end` status effect (Burn flat damage,
	#        Regen heal scaling by stacks).
	#     2. Call this function to step every `Decay: at end of turn`
	#        status down by 1.
	#
	# Today this function decays the entire DECAY_STATUSES list at
	# whichever boundary callers invoke it from. Once Poison's
	# start-of-turn split lands, the loader will partition the list by
	# decay boundary and the order above is the contract. Don't tick
	# AFTER decay or you'll undercount Poison/Regen damage by one stack.
	if actor == null:
		return
	for s in DECAY_STATUSES:
		if actor.get_status(s) > 0:
			actor.add_status(s, -1)

func roll_blind_miss(rng: RandomNumberGenerator, source_is_player: bool) -> bool:
	# Returns true if the attack misses. Player's luck always biases
	# the outcome IN THE PLAYER'S FAVOR, regardless of who's swinging:
	#  - Player attacking (player wants the hit): roll on the inverse
	#    "hit chance" so luck advantage = more hits = fewer misses.
	#  - Enemy attacking the player (player wants the miss): roll on
	#    the miss chance directly so luck advantage = more misses.
	if source_is_player:
		return not roll_chance_with_luck(rng, 100 - BLIND_MISS_PCT)
	return roll_chance_with_luck(rng, BLIND_MISS_PCT)

func roll_chance_with_luck(rng: RandomNumberGenerator, percent: int) -> bool:
	var r1: bool = rng.randi_range(0, 99) < percent
	var luck: int = get_value(&"luck")
	if luck == 0:
		return r1
	var adv_pct: int = clampi(absi(luck) * 10, 0, 100)
	if rng.randi_range(0, 99) >= adv_pct:
		return r1
	var r2: bool = rng.randi_range(0, 99) < percent
	return (r1 or r2) if luck > 0 else (r1 and r2)

func _luck_roll(rng: RandomNumberGenerator, sides: int) -> int:
	var r1: int = rng.randi_range(1, sides)
	var luck: int = get_value(&"luck")
	if luck == 0:
		return r1
	var adv_pct: int = clampi(absi(luck) * 10, 0, 100)
	if rng.randi_range(0, 99) >= adv_pct:
		return r1
	var r2: int = rng.randi_range(1, sides)
	return maxi(r1, r2) if luck > 0 else mini(r1, r2)

# ---------------------------------------------------------------------------
# Constitution auto-gain — call when max_hp grows mid-run
# ---------------------------------------------------------------------------

func note_max_hp_change(new_max: int, old_max: int) -> void:
	var delta: int = new_max - old_max
	if delta <= 0:
		return
	@warning_ignore("integer_division")
	var gained: int = delta / 5
	if gained > 0:
		GameState.constitution += gained
		GameState.emit_signal("stats_changed")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _knob_int(stat_id: StringName, key: String, default: int) -> int:
	var def: StatDefinition = _stat_defs.get(stat_id)
	if def == null:
		return default
	return int(def.mode_data.get(key, default))

func _knob_float(stat_id: StringName, key: String, default: float) -> float:
	var def: StatDefinition = _stat_defs.get(stat_id)
	if def == null:
		return default
	return float(def.mode_data.get(key, default))
