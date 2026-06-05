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
# Slay-the-Spire-length turn (~10s of arena play ≈ one deckbuilder
# turn of dialogue + planning).
const ACTION_TURN_TICK_SECONDS := 10.0

# Statuses that step down by 1 each turn (deckbuilder + strategy) or
# each ACTION_TURN_TICK (action). Owned here so all three modes
# decay the same set without re-declaring it.
const DECAY_STATUSES: Array[StringName] = [
	&"vulnerable", &"weak", &"frail",
	&"burn", &"poison", &"regeneration",
	&"dodge",   # dodge decays on use too; the 1/turn safety mirrors JS
	&"blind",
]

# Statuses that GROW by 1 at end of turn (Bleed). Mirror of
# DECAY_STATUSES — same callsites, opposite operation. Per-turn DoT
# damage still happens BEFORE the grow (see tick_actor_statuses) so
# the player takes the current-stack bite, then the next turn's bite
# is one bigger.
const GROW_STATUSES: Array[StringName] = [
	&"bleed",
]

# Blind: an attacker afflicted with Blind has BLIND_MISS_PCT% chance
# to miss each hit. Roll routes through luck (see roll_blind_miss).
const BLIND_MISS_PCT := 30

# Status icon art lives in res://images/statuses/ as PascalCase PNGs.
# Combat StringName keys are snake_case, so this table bridges the two.
# Shared by all three combat modes (deckbuilder / action / strategy) so
# the same status shows the same icon everywhere. Unmapped statuses fall
# back to Unknown.png.
const STATUS_ICON_DIR := "res://images/statuses/"
const STATUS_ICONS := {
	&"power": "Power.png",
	&"strength": "Strength.png",
	&"vulnerable": "Vulnerable.png",
	&"weak": "Weak.png",
	&"frail": "Frail.png",
	&"poison": "Poison.png",
	&"burn": "Burn.png",
	&"bleed": "Bleed.png",
	&"bleed_thorns": "BleedThorns.png",
	&"dodge": "Dodge.png",
	&"blind": "Blind.png",
	&"defense": "Defense.png",
	&"arcane": "Arcane.png",
	&"regeneration": "Regeneration.png",
	&"persistence": "Persistence.png",
	&"thorns": "Thorns.png",
	&"soul_link": "SoulLink.png",
	&"crit_chance_up": "CritChanceUp.png",
	&"bruise": "Bruise.png",
	&"leeches": "Leeches.png",
}

var _status_icon_cache: Dictionary = {}     # StringName -> Texture2D

var _stat_defs: Dictionary = {}     # StringName -> StatDefinition

# Fallback RNG for the shared combat resolvers when a caller doesn't pass
# its own. Scenes normally hand in their seeded _rng so blind/dodge rolls
# stay deterministic per scene; this just keeps resolve_damage callable
# from anywhere.
var _resolve_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Debuffs whose applied stack count gets boosted by the source's
# Persistence. Player-applied only (enforced in status_apply_stacks).
# Shared so deckbuilder / action / strategy agree on which statuses scale.
const PERSISTENCE_DEBUFFS: Array[StringName] = [
	&"vulnerable", &"weak", &"frail", &"poison", &"burn", &"bleed", &"bruise",
	&"leeches",
]

func _ready() -> void:
	_resolve_rng.randomize()
	_load_stat_defs()
	# Harvesting payout: beating a game grants gold equal to the stat.
	TriggerBus.game_beaten.connect(_on_game_beaten)

func _on_game_beaten(_ctx: Dictionary) -> void:
	var harvest: int = get_value(&"harvesting")
	if harvest <= 0:
		return
	GameState.change_gold(harvest)
	GameLog.add("Harvesting: +%d gold." % harvest, Color(1.0, 0.85, 0.3))

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
	# Reads the matching field on GameState by name and adds any item
	# bonus stored in GameState.item_stat_bonus (set by
	# GameState._recompute_item_bonuses on every inventory change). The
	# stat id must match the GameState field exactly
	# (strength / dexterity / etc.). Vitals (max_hp, max_energy) are
	# already applied via set_max_hp/max_energy so they're NOT in
	# item_stat_bonus — direct reads return the right value.
	var base: int = int(GameState.get(String(stat_id)))
	var bonus: int = int(GameState.item_stat_bonus.get(String(stat_id), 0))
	# Temporary consumable buffs (pills) layer on top; cleared at the
	# combat/room/event boundary by GameState.clear_temp_buffs().
	var temp: int = int(GameState.temp_stat_bonus.get(String(stat_id), 0))
	return base + bonus + temp

func get_definition(stat_id: StringName) -> StatDefinition:
	return _stat_defs.get(stat_id)

# Returns the icon Texture2D for a status (cached). Used by every combat
# mode's status display. Falls back to Unknown.png for unmapped statuses.
func status_icon(status_name) -> Texture2D:
	var key := StringName(status_name)
	if _status_icon_cache.has(key):
		return _status_icon_cache[key]
	var fname: String = STATUS_ICONS.get(key, "Unknown.png")
	var path: String = STATUS_ICON_DIR + fname
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_status_icon_cache[key] = tex
	return tex

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
	# Crit Chance Up is the in-combat display of the player's POSITIVE
	# crit_chance stat — shown only while above 0. The Luck portion of the
	# crit roll (max(0, 2 x Luck)) stays hidden, and a negative crit_chance
	# still lowers the roll in resolve_damage but is never surfaced here.
	if actor != null and ("is_player" in actor) and actor.is_player:
		var cc: int = get_value(&"crit_chance")
		if cc > 0:
			actor.add_status(&"crit_chance_up", cc)
	for s in GameState.pending_combat_statuses:
		actor.add_status(s.get("status", &""), s.get("stacks", 0))
	GameState.pending_combat_statuses.clear()

# ---------------------------------------------------------------------------
# Damage-type bonus — query during damage resolution. Adds the right
# extras on top of source.power based on damage_type + current mode.
# ---------------------------------------------------------------------------

func damage_bonus(source, damage_type: String, mode: Mode, power_multiplier: int = 1) -> int:
	# Untyped source so both CombatActor (deckbuilder/action) and BattleUnit
	# (strategy) flow through the one formula. Only get_status is read.
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
	# Flat item bonus to the player's attacks (Focus Crystal: +1 melee).
	# Player-only and not multiplied by power_multiplier — it's a flat add.
	if ("is_player" in source) and source.is_player:
		bonus += GameState.attack_damage_bonus(damage_type)
	return bonus

# ---------------------------------------------------------------------------
# Canonical combat resolvers — the single source of truth shared by all
# three modes (deckbuilder / action / strategy). These are PURE math: they
# read statuses, consume Dodge, and drain block, but they never write HP,
# log, animate, or fire triggers. Each scene calls a resolver, then applies
# the returned numbers and runs its own mode-specific tail (death, thorns,
# soul-link, iframes, …). Keep the formula here and nowhere else.
# ---------------------------------------------------------------------------

# Resolve one hit. `base` is the raw card/attack value; `effect` may carry
#   damage_type ("melee"/"ranged"/"magic"/"true"), power_multiplier (int),
#   no_block (skip block soak — DoTs / piercing), ignore_dodge (bypass Dodge).
# Returns { missed, dodged, blocked, hp_loss }:
#   missed  — attacker whiffed via Blind (no dodge consumed, no damage)
#   dodged  — target burned a Dodge stack to negate the hit
#   blocked — amount soaked by block (already drained from target.block)
#   hp_loss — final HP the caller should remove from the target
func resolve_damage(
		source, target, base: int, effect: Dictionary,
		mode: Mode, rng: RandomNumberGenerator = null) -> Dictionary:
	var out := {"missed": false, "dodged": false, "blocked": 0, "hp_loss": 0, "crit": false}
	if target == null:
		return out
	var r: RandomNumberGenerator = rng if rng != null else _resolve_rng
	var damage_type: String = String(effect.get("damage_type", "melee"))
	var has_src: bool = source != null and source.has_method("get_status")
	var has_tgt: bool = target.has_method("get_status")

	# Blind: an attacker with Blind can whiff each melee/ranged swing.
	# Spell damage and DoT ticks (true) are never gated by Blind.
	if has_src and (damage_type == "melee" or damage_type == "ranged") \
			and source.get_status(&"blind") > 0 and roll_blind_miss(r, source.is_player):
		out.missed = true
		return out

	var amount: int = base
	# Outgoing: Power (+arcane/dex via damage_bonus) then Weak (-25%, floor).
	if has_src:
		var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
		amount += damage_bonus(source, damage_type, mode, power_mult)
		if source.get_status(&"weak") > 0:
			amount = int(floor(amount * 0.75))
	# Incoming: Vulnerable (+50%, ceil).
	if has_tgt and target.get_status(&"vulnerable") > 0:
		amount = int(ceil(amount * 1.5))
	# Incoming: Bruise (+1 flat per stack), melee/ranged only — never magic
	# or DoT ("true") damage. Applied after Vulnerable's multiplier.
	if has_tgt and (damage_type == "melee" or damage_type == "ranged"):
		amount += target.get_status(&"bruise")

	# Dodge negates the hit entirely and burns one stack.
	if not bool(effect.get("ignore_dodge", false)) and has_tgt and target.get_status(&"dodge") > 0:
		target.add_status(&"dodge", -1)
		out.dodged = true
		return out

	amount = maxi(0, amount)
	# Little Knife: the player's attacks hit a lower-HP target 25% harder
	# (ceil). source.hp is the player's current HP when the player attacks.
	if has_src and ("is_player" in source) and source.is_player \
			and ("hp" in target) and ("hp" in source):
		var lk_mult: float = GameState.lower_hp_damage_mult()
		if lk_mult > 1.0 and int(target.hp) < int(source.hp):
			amount = int(ceil(amount * lk_mult))
	# Pen Nib: every 10th Attack the player plays deals double damage. The
	# window is armed by the attack_double effect when the counter trips and
	# stays up for all of that card's hits (cleared at the next card play).
	# DoT ticks ("true") never carry an attack card, so they're excluded.
	if has_src and ("is_player" in source) and source.is_player \
			and damage_type != "true" and GameState.pen_nib_double_active:
		amount *= 2
	# Critical hit — applied PRE-block so block soaks the boosted hit. Any
	# attacker can crit: the player from Luck + crit_chance, an enemy only if
	# it carries a Crit Chance Up status (see actor_crit_percent). Fires on
	# every combat damage type — melee, ranged, AND magic; only DoT ticks are
	# excluded (they use "true" damage and route through apply_dot, never
	# reaching this resolver). actor_crit_percent already folds Luck in for
	# the player, so this is a PLAIN roll (no double-counting of advantage).
	if has_src and damage_type != "true":
		var cc: int = actor_crit_percent(source)
		if cc > 0 and r.randi_range(0, 99) < cc:
			out.crit = true
			amount = int(floor(amount * crit_multiplier(source)))
	# Block absorption (skipped for no_block DoTs / piercing).
	if not bool(effect.get("no_block", false)):
		var absorbed: int = mini(maxi(0, target.block), amount)
		target.block -= absorbed
		amount -= absorbed
		out.blocked = absorbed
	out.hp_loss = maxi(0, amount)
	return out

# Resolve block gained. Frail cuts gained block 25% (floor) in every mode.
# `add_defense` folds in the Defense status (Action's bespoke rule today);
# the other modes pass false so behavior is unchanged for them.
func resolve_block(base: int, target, add_defense: bool = false) -> int:
	var amt: int = base
	if target != null and target.has_method("get_status"):
		if add_defense:
			amt += target.get_status(&"defense")
		if target.get_status(&"frail") > 0:
			amt = int(floor(amt * 0.75))
	return maxi(0, amt)

# Persistence: a debuff the PLAYER inflicts lands with extra stacks equal to
# the source's Persistence. Buffs and enemy-applied debuffs are unaffected.
# Returns the adjusted stack count to feed into add_status.
func status_apply_stacks(source, status: StringName, stacks: int) -> int:
	if source != null and source.has_method("get_status") \
			and ("is_player" in source) and source.is_player \
			and stacks > 0 and status in PERSISTENCE_DEBUFFS:
		return stacks + source.get_status(&"persistence")
	return stacks

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
# Crit
# ---------------------------------------------------------------------------

# The PLAYER's effective crit chance for one hit, as a percent in [0, 100].
#   crit% = max(0, 2 x Luck) + crit_chance
# Luck only ever helps (negative Luck contributes 0); the crit_chance stat is
# added raw (it can be negative — e.g. Bowler Hat's -3). Going over 100 does
# nothing. Used by the HUD and by actor_crit_percent for the player actor.
func crit_chance_percent() -> int:
	var luck_term: int = maxi(0, 2 * get_value(&"luck"))
	return clampi(luck_term + get_value(&"crit_chance"), 0, 100)

# Per-hit crit chance for ANY combat actor, in [0, 100].
#   - Player: the Luck + crit_chance formula above. Luck only helps the
#     PLAYER — no other actor draws crit from the Luck stat.
#   - Enemies / non-player: crit purely from a Crit Chance Up status applied
#     to them in combat. No status => 0% (they can't crit).
func actor_crit_percent(actor) -> int:
	if actor != null and ("is_player" in actor) and actor.is_player:
		return crit_chance_percent()
	if actor != null and actor.has_method("get_status"):
		return clampi(actor.get_status(&"crit_chance_up"), 0, 100)
	return 0

# Damage multiplier applied on a crit. The PLAYER scales with the crit_damage
# stat (100 => x2); enemies have no crit_damage stat, so an enemy crit is a
# flat double. Give enemies a crit_damage source here if that ever changes.
func crit_multiplier(source) -> float:
	if source != null and ("is_player" in source) and source.is_player:
		return 1.0 + float(get_value(&"crit_damage")) / 100.0
	return 2.0

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
	var indiscriminate: bool = addons.has("indiscriminate")
	if bonus == 0 and not indiscriminate:
		return effect
	var dup: Dictionary = effect.duplicate()
	if bonus != 0:
		dup["value"] = int(dup.get("value", 0)) + bonus
	if indiscriminate:
		# Flag the effect so the dmg handler re-rolls the target per hit
		# (Blood Magic's `2x3` becomes "2 dmg to 3 random enemies"). The
		# flag also feeds CardInstance.wants_target so the play UI skips
		# the manual target picker.
		dup["indiscriminate"] = true
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
			"wealth":
				total += _wealth_bonus()
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

func _wealth_bonus() -> int:
	# Blasma Pistol's Wealth addon: +1 to the affected effect per 10 gold
	# the player is sitting on. Type-agnostic — apply_addons_to_effect
	# only routes dmg today, so callers see it as +1 dmg per 10 gold.
	@warning_ignore("integer_division")
	return int(GameState.gold) / 10

func tick_actor_statuses(actor, scene) -> void:
	# Per-turn damage / heal effects from statuses. MUST run BEFORE
	# decay_actor_statuses on the same boundary so the bite uses the
	# stack count the player has been carrying (and Bleed grows AFTER
	# its bite, not before). Scene needs apply_dot(actor, amount,
	# source_name) for raw-HP damage that bypasses block / weak /
	# vulnerable and never re-triggers thorns. Other DoTs (Burn,
	# Poison) land here too once their tick rules are authored — the
	# canonical order in this function IS the contract.
	#
	# Untyped actor for cross-mode use: actor must expose
	# is_alive() -> bool and get_status(name) -> int.
	if actor == null or not actor.has_method("is_alive") or not actor.is_alive():
		return
	if scene == null or not scene.has_method("apply_dot") or not actor.has_method("get_status"):
		return
	var bleed: int = actor.get_status(&"bleed")
	if bleed > 0:
		scene.apply_dot(actor, bleed, "bleed")
	# Leeches (Jar of Leeches): a leeched ENEMY loses HP equal to its stacks
	# each turn and the player heals the same. Doesn't decay — the drain
	# repeats every turn until the enemy dies. Player-owned only (no Godot
	# enemy inflicts Leeches today), so we just drain non-player actors.
	var leeches: int = actor.get_status(&"leeches")
	if leeches > 0 and ("is_player" in actor) and not actor.is_player:
		scene.apply_dot(actor, leeches, "leeches")
		if scene.has_method("leech_to_player"):
			scene.leech_to_player(leeches)

func fire_contact_reactions(target, attacker, scene) -> void:
	# Cross-mode "actor A made physical contact with actor B" hook.
	# Deckbuilder calls this after melee damage resolves; strategy
	# combat will call it from trample / jump-on / knockback-into
	# events once those land. The reactions reach back to the
	# attacker, never to a third party — bystanders don't soak
	# thorns even when an AoE blade sweeps through.
	#
	# Parameters are deliberately untyped: deckbuilder passes
	# CombatActor, strategy passes BattleUnit. Both need to expose
	# get_status(name) -> int and is_alive() -> bool for the gates;
	# scene must expose deal_damage(source, target, amount, effect)
	# and apply_status(target, status, stacks). Missing methods cause
	# graceful no-ops, so strategy can opt in piecemeal — wire
	# deal_damage on a unit first, get thorns; add apply_status, get
	# bleed_thorns.
	#
	# Reactions pass effect.no_reaction = true so the thorns reflect
	# doesn't recurse into the attacker's own thorns.
	if target == null or attacker == null:
		return
	if not target.has_method("is_alive") or not target.is_alive():
		return
	if not target.has_method("get_status"):
		return
	var thorns: int = target.get_status(&"thorns")
	if thorns > 0 and scene != null and scene.has_method("deal_damage"):
		scene.deal_damage(target, attacker, thorns,
			{"damage_type": "melee", "no_reaction": true})
	# Attacker may have died from thorns above — bail before applying bleed.
	if not attacker.has_method("is_alive") or not attacker.is_alive():
		return
	var bleed_thorns: int = target.get_status(&"bleed_thorns")
	if bleed_thorns > 0 and scene != null and scene.has_method("apply_status"):
		scene.apply_status(attacker, &"bleed", bleed_thorns)

func decay_actor_statuses(actor, do_grow: bool = true) -> void:
	# Step down every decaying status on this actor by 1. Called per
	# actor at end-of-turn (deckbuilder, strategy when statuses land
	# there) and per ACTION_TURN_TICK in action mode.
	#
	# do_grow controls the GROW_STATUSES pass (Bleed +1). Deckbuilder /
	# strategy leave it true. Action passes false because its Bleed has a
	# different rule — it only ramps while you keep landing hits and clears
	# the moment you stop (see action_bleed_step).
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
	if do_grow:
		for s in GROW_STATUSES:
			if actor.get_status(s) > 0:
				actor.add_status(s, 1)

# Action-only Bleed rule. In real-time play Bleed ramps while you keep the
# pressure on and evaporates when you let up: each ACTION_TURN_TICK a
# bleeding actor that took at least one hit during the window gains +1
# stack, and one that wasn't hit loses ALL its stacks. The DoT bite itself
# runs through tick_actor_statuses BEFORE this, so the actor still takes its
# current-stack damage on the clearing tick (same ordering contract as the
# deckbuilder: bite first, then adjust stacks).
func action_bleed_step(actor, was_hit: bool) -> void:
	if actor == null or not actor.has_method("get_status"):
		return
	var bleed: int = actor.get_status(&"bleed")
	if bleed <= 0:
		return
	if was_hit:
		actor.add_status(&"bleed", 1)
	else:
		actor.add_status(&"bleed", -bleed)

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
