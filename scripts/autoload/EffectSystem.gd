extends Node

# Centralized dispatch for structured effects.
#
# An effect is a Dictionary like:
#   { "type": "dmg", "value": 6, "target": "enemy" }
#
# Effects are applied via:
#   EffectSystem.apply(effect, ctx)
#
# `ctx` is a Dictionary carrying the runtime info handlers need:
#   {
#     "source":   <player or enemy ref>,
#     "target":   <target resolved by the caller>,
#     "scene":    <DeckbuilderCombat or other combat scene>,
#     "card":     <the card being played, if any>,
#   }
#
# Handlers are registered with `register(type, callable)`. Each handler
# receives (effect, ctx) and returns nothing. Unknown effect types log
# a warning but don't crash.

var _handlers: Dictionary = {}  # type: String -> Callable
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_register_defaults()

func register(effect_type: String, handler: Callable) -> void:
	_handlers[effect_type] = handler

func apply(effect: Dictionary, ctx: Dictionary) -> void:
	var t: String = effect.get("type", "")
	if t == "":
		push_warning("EffectSystem.apply: missing type in effect %s" % effect)
		return
	var h: Callable = _handlers.get(t, Callable())
	if not h.is_valid():
		push_warning("EffectSystem.apply: no handler for type '%s'" % t)
		return
	h.call(effect, ctx)
	# Opt-in player-facing notification. Authored as a `notify` field on the
	# effect dict; for a chance-wrapped proc this lives on the INNER effect, so
	# it only posts when the (luck-rolled) chance actually passes.
	if effect.has("notify"):
		Notifications.notify(String(effect["notify"]), Color(0.6, 1.0, 0.7))

func apply_all(effects: Array, ctx: Dictionary) -> void:
	for e in effects:
		apply(e, ctx)

# Resolves an effect amount that may be dynamic. When `from_key` is present in
# the effect its value names a live tally (see _dynamic_count) and the amount
# is that count times `mult_key` (default 1); otherwise the static `base_key`
# is used. Lets curse-scaling items stay fully declarative — Death Orb is
# {type:"dmg", value_from:"curses", value_mult:2} and Du-Vu Doll is
# {type:"status", status:"power", stacks_from:"curses"}.
func _dyn_amount(effect: Dictionary, base_key: String, from_key: String, mult_key: String) -> int:
	if effect.has(from_key):
		return _dynamic_count(String(effect[from_key])) * int(effect.get(mult_key, 1))
	return int(effect.get(base_key, 0))

# Live count for a dynamic effect source. "curses" = active curses (NOT curse
# cards); "curse_cards" = CURSE-type cards in the deck; "curses_and_cards" =
# both. Curses and curse cards are intentionally separate quantities.
func _dynamic_count(source: String) -> int:
	match source:
		"curses":
			return GameState.curse_count()
		"curse_cards":
			return GameState.curse_card_count()
		"curses_and_cards":
			return GameState.curse_count() + GameState.curse_card_count()
		# Incremental combat counters (Finisher: attacks played this turn). These
		# are bumped by ItemTriggers.fire and reset on the turn boundary in every
		# mode, so a dmg effect scaling off `attacks_this_turn` resolves the same
		# way in deckbuilder, strategy, and action's turn-tick window.
		"attacks_this_turn", "attacks_total", "turns":
			return GameState.incremental_value(source)
	push_warning("EffectSystem: unknown dynamic count source '%s'" % source)
	return 0

# True when the played card (CardInstance in deckbuilder/strategy, CardData in
# action) is an Attack. Used to strip a scaling attack's own contribution from
# attacks_this_turn so it counts only the attacks that came before it.
func _card_is_attack(card: Variant) -> bool:
	return card != null and card.has_method("is_attack") and card.is_attack()

# ---------------------------------------------------------------------------
# Default handlers — registered at load. The combat scene exposes the
# methods these handlers call back into (deal_damage, gain_block, etc.)
# via the `scene` context entry.
# ---------------------------------------------------------------------------

func _register_defaults() -> void:
	register("dmg", _h_dmg)
	register("block", _h_block)
	register("roll_block", _h_roll_block)
	register("heal", _h_heal)
	register("draw", _h_draw)
	register("gain_energy", _h_gain_energy)
	register("lose_energy", _h_lose_energy)
	register("status", _h_status)
	register("status_temp", _h_status_temp)
	register("exhaust_self", _h_exhaust_self)
	register("gain_gold", _h_gain_gold)
	register("gain_stat", _h_gain_stat)
	register("lose_hp", _h_lose_hp)
	register("conjure", _h_conjure)
	register("conjure_random", _h_conjure_random)
	register("discard", _h_discard)
	register("exhaust", _h_exhaust)
	register("topdeck", _h_topdeck)
	register("recall", _h_recall)
	register("upgrade_hand", _h_upgrade_hand)
	register("upgrade_random_cards", _h_upgrade_random_cards)
	register("boost_cards", _h_boost_cards)
	register("gain_loot", _h_gain_loot)
	register("trigger", _h_trigger)
	register("keep_block", _h_keep_block)
	register("retain", _h_retain)
	register("double_stat", _h_double_stat)
	register("autoplay_top", _h_autoplay_top)
	register("copy_from_hand", _h_copy_from_hand)
	register("exhume", _h_exhume)
	register("multiply_status", _h_multiply_status)
	register("free_hand", _h_free_hand)
	register("nightmare", _h_nightmare)
	register("retrieve", _h_retrieve)
	register("if_target_intent", _h_if_target_intent)
	register("chance", _h_chance)
	register("if_target_status", _h_if_target_status)
	register("if_counter", _h_if_counter)
	register("add_max_hp", _h_add_max_hp)
	register("gain_hp", _h_gain_hp)
	register("gain_max_hp", _h_gain_max_hp)
	register("bump_card_effect", _h_bump_card_effect)
	register("temp_stat", _h_temp_stat)
	register("streak_hit", _h_streak_hit)
	register("streak_reset", _h_streak_reset)
	register("counter", _h_counter)
	register("attack_double", _h_attack_double)
	register("if_hp", _h_if_hp)
	register("free_random_hand_card", _h_free_random_hand_card)
	register("reduce_card_cost", _h_reduce_card_cost)
	register("gain_chest", _h_gain_chest)
	register("roll_gold", _h_roll_gold)
	register("overworld_jump", _h_overworld_jump)

# Determined (addon): an effect may carry `determined: [min, max]`, meaning its
# value is a number rolled ONCE at first use and fixed for the rest of combat
# (e.g. a Louse whose Bite is Determined(5-7)). Resolves through Stats so the
# roll is cached on the source actor; effects without the field keep `fallback`.
# `slot` distinguishes a determined dmg value from a determined block value on
# the same actor when the effect doesn't name an explicit `determined_key`.
func _resolve_determined(effect: Dictionary, ctx: Dictionary, fallback: int, slot: String) -> int:
	var det: Variant = effect.get("determined", null)
	if not (det is Array) or det.size() < 2:
		return fallback
	var lo: int = int(det[0])
	var hi: int = int(det[1])
	var key: String = String(effect.get("determined_key", "%s_%d_%d" % [slot, lo, hi]))
	return Stats.resolve_determined(ctx.get("source"), key, lo, hi)

func _h_dmg(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("deal_damage"):
		return
	# Conditional damage (Bane et al). `if_target_status: "poison"` skips
	# the effect entirely when the target lacks that status. Per-target
	# check so an `all_enemies` cleave can still hit only the poisoned
	# half of the room. Action mode resolves dmg outside this handler
	# and gates the same field in `_apply_damage_effect`.
	var gate: String = String(effect.get("if_target_status", ""))
	if gate != "":
		var tgt = ctx.get("target")
		if tgt == null or not tgt.has_method("get_status") or tgt.get_status(StringName(gate)) <= 0:
			return
	# Hand gate (Clash: if_hand "all_attacks"): the hit whiffs unless every
	# OTHER card in hand is an Attack — statuses and curses spoil it too. The
	# played card is still mid-resolve and in hand, so exclude it. Scenes
	# without a hand (action) never route dmg through here and always pass.
	if String(effect.get("if_hand", "")) == "all_attacks":
		var sc: Variant = ctx.get("scene")
		if sc != null and ("hand" in sc):
			for hc in sc.hand:
				if hc == ctx.get("card"):
					continue
				if hc == null or not hc.has_method("is_attack") or not hc.is_attack():
					GameLog.add("Non-Attack cards in hand — it does nothing!",
						Color(0.85, 0.85, 0.55))
					return
	# Draw-pile gate (Grand Finale: if_draw "empty"): the hit whiffs unless the
	# draw pile is empty at play time. Scenes without a draw pile pass; action
	# resolves dmg outside this handler and gates its auto draw pile in
	# _deliver_attack.
	if String(effect.get("if_draw", "")) == "empty":
		var dsc: Variant = ctx.get("scene")
		if dsc != null and ("draw_pile" in dsc) and not dsc.draw_pile.is_empty():
			GameLog.add("Cards remain in the draw pile — it does nothing!",
				Color(0.85, 0.85, 0.55))
			return
	# `hits` lets a single dmg effect resolve N times (Twin Strike 5x2).
	# Action mode handles its own pacing via _resolve_card_effects and
	# never reaches this path for multi-hit, so the loop here is purely
	# for deckbuilder/strategy where instant N hits are fine.
	# Indiscriminate (Blood Magic's addon) re-rolls the target each
	# iteration so a 3-hit attack lands on 3 random enemies instead of
	# dumping all three into the same actor.
	var hits: int = maxi(1, int(effect.get("hits", 1)))
	# X-cost repeat (Whirlwind / Skewer, hits_from: "energy"): the hit count is
	# the energy spent on the play, threaded through ctx by the combat scene.
	# X = 0 (played on an empty pool) legitimately swings zero times.
	if String(effect.get("hits_from", "")) == "energy":
		hits = maxi(0, int(ctx.get("x_value", 0)))
	# Fiend Fire (hits_from: "exhausted"): one hit per card the preceding
	# exhaust:all sent away this play — the exhaust mirror of conjure's
	# count_from: "discarded". Zero exhausted legitimately swings zero times.
	if String(effect.get("hits_from", "")) == "exhausted":
		var ex_scene: Variant = ctx.get("scene")
		hits = int(ex_scene.last_exhaust_count) \
			if ex_scene != null and ("last_exhaust_count" in ex_scene) else 0
	# Flechettes (hits_from: "skills_in_hand"): one hit per Skill card in hand
	# at play time, the played card excluded. Zero skills = zero hits.
	if String(effect.get("hits_from", "")) == "skills_in_hand":
		hits = _skills_in_hand(ctx)
	var indiscriminate: bool = bool(effect.get("indiscriminate", false))
	# `target: "self"` routes the hit back onto the source (curse cards: Decay
	# deals to the player), mirroring how status/block/heal resolve "self".
	var self_target: bool = String(effect.get("target", "")) == "self"
	# Damage may be curse-scaled (Death Orb: Xx2 where X = curse count) or scaled
	# off a live attacker stat (Body Slam: value_from "block" = the source's
	# current Block, resolved here so deal_damage still applies Power/Weak/etc).
	var dmg_value: int
	if String(effect.get("value_from", "")) == "block":
		var src: Variant = ctx.get("source")
		var blk: int = int(src.block) if src != null and "block" in src else 0
		dmg_value = blk * int(effect.get("value_mult", 1))
	else:
		dmg_value = _dyn_amount(effect, "value", "value_from", "value_mult")
	# A scaling attack does NOT count its own play (Finisher: 0 prior attacks ->
	# 0 damage). attacks_this_turn is bumped on card_played, which fires before
	# the card's own effects, so subtract this card's contribution when the card
	# itself is an Attack — the only card kind that bumps the counter.
	if String(effect.get("value_from", "")) == "attacks_this_turn" and _card_is_attack(ctx.get("card")):
		dmg_value = maxi(0, dmg_value - int(effect.get("value_mult", 1)))
	# Perfected Strike (bonus_per_card_name "strike"): the hit deals
	# bonus_per_card additional damage for every card in the player's combat
	# deck — hand + draw + discard, the played card included — whose display
	# name contains the substring. Counted at play time, so conjured Strikes
	# raise it and exhausted ones drop off.
	var name_sub: String = String(effect.get("bonus_per_card_name", ""))
	if name_sub != "":
		dmg_value += int(effect.get("bonus_per_card", 0)) * _cards_named(ctx, name_sub)
	# Determined (addon): a fixed-per-combat rolled value overrides the static one.
	dmg_value = _resolve_determined(effect, ctx, dmg_value, "dmg")
	# Per-turn scaling (Transient): +M damage for each turn the source has taken.
	# turns_taken is bumped at the actor's turn boundary, so its first attack is
	# unscaled (turns_taken 0) and each subsequent turn adds another M.
	var per_turn: int = int(effect.get("per_turn", 0))
	if per_turn != 0:
		var pt_src: Variant = ctx.get("source")
		if pt_src != null and ("turns_taken" in pt_src):
			dmg_value += per_turn * int(pt_src.turns_taken)
	# Dice (NetHack-style per-hit roll): `dice: [count, sides]` rolls
	# `count` d`sides` FRESH on every application (and every `hits` iteration),
	# replacing the static value — so a sewer rat's 1d3 bite varies 1-3 each
	# time, unlike Determined which fixes one roll for the whole combat.
	var dice: Variant = effect.get("dice", null)
	var dice_n: int = 0
	var dice_sides: int = 0
	if dice is Array and dice.size() == 2:
		dice_n = int(dice[0])
		dice_sides = int(dice[1])
	for _i in hits:
		var tgt: Variant = ctx.get("source") if self_target else ctx.get("target")
		if indiscriminate:
			tgt = _resolve_random_enemy(ctx)
			if tgt == null:
				return
		var hit_value: int = dmg_value
		if dice_n > 0 and dice_sides > 0:
			hit_value = 0
			for _d in dice_n:
				hit_value += _rng.randi_range(1, dice_sides)
		scene.deal_damage(ctx.get("source"), tgt, hit_value, effect)

# Skill cards in the scene's hand, the played card excluded (Flechettes'
# hits_from: "skills_in_hand"). Scenes without a hand (events) count zero —
# action resolves its own analog (Skill cards riding cooldown slots) in
# _deliver_attack and never reaches this path.
func _skills_in_hand(ctx: Dictionary) -> int:
	var scene: Variant = ctx.get("scene")
	if scene == null or not ("hand" in scene):
		return 0
	var n: int = 0
	for hc in scene.hand:
		if hc == ctx.get("card"):
			continue
		if hc != null and hc.has_method("is_skill") and hc.is_skill():
			n += 1
	return n

# Cards whose display name contains `sub` (case-insensitive) across the
# scene's combat piles — hand + draw + discard — for Perfected Strike's
# bonus_per_card_name. The played card counts once wherever it sits: it's
# normally still in hand mid-resolve, but if a scene removes it before
# resolving (or it was conjured straight into play) it's counted explicitly.
func _cards_named(ctx: Dictionary, sub: String) -> int:
	var scene: Variant = ctx.get("scene")
	if scene == null:
		return 0
	var needle: String = sub.to_lower()
	var n: int = 0
	var played: Variant = ctx.get("card")
	var played_seen: bool = false
	for pile_name in ["hand", "draw_pile", "discard_pile"]:
		if not (pile_name in scene):
			continue
		for c in scene.get(pile_name):
			if c == played:
				played_seen = true
			if c != null and c.has_method("get_display_name") \
					and c.get_display_name().to_lower().contains(needle):
				n += 1
	if played != null and not played_seen and played.has_method("get_display_name") \
			and played.get_display_name().to_lower().contains(needle):
		n += 1
	return n

# Mode-agnostic random living enemy for indiscriminate effects. Prefers the
# scene's own picker (strategy's units, action's enemy dicts) and falls back to
# the deckbuilder-style `enemies` array of actors.
func _resolve_random_enemy(ctx: Dictionary) -> Variant:
	var scene: Variant = ctx.get("scene")
	if scene != null and scene.has_method("pick_random_enemy"):
		return scene.pick_random_enemy(ctx.get("source"))
	return _pick_random_enemy(scene)

func _pick_random_enemy(scene: Variant) -> Variant:
	if scene == null or not ("enemies" in scene):
		return null
	var live: Array = []
	for e in scene.enemies:
		if e != null and e.has_method("is_alive") and e.is_alive():
			live.append(e)
	if live.is_empty():
		return null
	return live[_rng.randi_range(0, live.size() - 1)]

func _h_block(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene != null:
		if scene.has_method("gain_block"):
			# Block defaults to gaining on self
			var target: Variant = ctx.get("target") if effect.get("target", "self") != "self" else ctx.get("source")
			var blk_value: int = _resolve_determined(effect, ctx, int(effect.get("value", 0)), "block")
			# Second Wind (value_from: "exhausted"): the value is PER CARD the
			# preceding exhaust:all sent away this play — the block mirror of
			# dmg's hits_from: "exhausted". Zero exhausted = zero block.
			if String(effect.get("value_from", "")) == "exhausted":
				var ex_n: int = int(scene.last_exhaust_count) \
					if ("last_exhaust_count" in scene) else 0
				blk_value = int(effect.get("value", 0)) * ex_n
				if blk_value <= 0:
					return
			scene.gain_block(target, blk_value)
		return
	# Scene-less (event use): bank the block so the next chunk of event
	# damage is soaked. Percs uses this path when played from the event bar.
	GameState.add_event_block(int(effect.get("value", 0)))

# Roll a `sides`-sided die (default 12) and grant that much Block. The roll
# goes through Luck the same way every other die does (Luck advantage =
# re-roll, keep the higher), then hands off to _h_block. Sulfa Powder:
#   {type: "roll_block", sides: 12}
# Overworld active (Winged Boots): hand the jump off to the overworld scene, which
# owns the map UI. ctx.scene is the Overworld when fired from the map (see
# GameState.use_item); a no-op anywhere else (in combat it has no map to move on).
func _h_overworld_jump(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene != null and scene.has_method("begin_overworld_jump"):
		scene.begin_overworld_jump(
			ctx.get("item"),
			String(effect.get("scope", "same_year")),
			int(effect.get("count", 3)))

func _h_roll_block(effect: Dictionary, ctx: Dictionary) -> void:
	var sides: int = int(effect.get("sides", 12))
	var amount: int = Stats.roll_die_with_luck(_rng, sides)
	GameLog.add("Rolled D%d → %d Block" % [sides, amount], Color(0.7, 0.85, 1.0))
	_h_block({"value": amount, "target": effect.get("target", "self")}, ctx)

func _h_heal(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("heal"):
		return
	var target: Variant = ctx.get("target") if effect.get("target", "self") != "self" else ctx.get("source")
	scene.heal(target, effect.get("value", 0))

func _h_draw(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("draw_cards"):
		return
	var n: int = int(effect.get("value", 1))
	# draw count=discarded (Calculated Gamble): one draw per card the preceding
	# discard:all sent away this play — the draw sibling of conjure's
	# count_from: "discarded". Zero discarded legitimately draws zero.
	if String(effect.get("value_from", "")) == "discarded":
		n = int(scene.last_discard_count) if ("last_discard_count" in scene) else 0
	# draw to=N (Expertise): top the hand up to N cards. Scenes without a hand
	# (action translates draws its own way and resolves this in its card loop)
	# fall back to a plain single draw.
	if effect.has("to_hand"):
		var hand_n: int = scene.hand.size() if ("hand" in scene) else 0
		n = maxi(0, int(effect.get("to_hand", 0)) - hand_n)
	if n <= 0:
		return
	var drawn: Variant = scene.draw_cards(n)
	# skill_block=N (Escape Plan): after the draw, gain N Block per drawn card
	# that is a Skill. draw_cards returns the drawn cards in deckbuilder /
	# strategy; a scene still returning void simply skips the rider.
	var per_skill: int = int(effect.get("skill_block", 0))
	if per_skill > 0 and drawn is Array and scene.has_method("gain_block"):
		var skills: int = 0
		for c in drawn:
			if c != null and c.has_method("is_skill") and c.is_skill():
				skills += 1
		if skills > 0:
			scene.gain_block(ctx.get("source"), per_skill * skills)
			GameLog.add("Escape Plan: drew a Skill — +%d Block." % (per_skill * skills),
				Color(0.7, 0.85, 1.0))

func _h_gain_energy(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("gain_energy"):
		return
	scene.gain_energy(effect.get("value", 1))

func _h_lose_energy(effect: Dictionary, ctx: Dictionary) -> void:
	# Each scene implements its own semantics. Deckbuilder drops the
	# per-turn energy pool; Action triggers a brief Slow window;
	# Strategy eats the per-turn bonus-ability budget and then locks
	# the normal ability use if the budget would go negative.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("lose_energy"):
		return
	scene.lose_energy(effect.get("value", 1))

func _h_keep_block(_effect: Dictionary, ctx: Dictionary) -> void:
	# Barricade: the source's Block is no longer removed at the turn boundary
	# (action: no longer fades over time). Sticky for the combat — the flag is
	# read by Stats.keeps_block at every block-reset site and cleared with the
	# actor at combat setup.
	var src: Variant = ctx.get("source")
	if src != null and ("keep_block" in src):
		src.keep_block = true

func _h_retain(_effect: Dictionary, _ctx: Dictionary) -> void:
	# Well-Laid Plans' inner verb. Deliberately inert here: retain must run
	# BEFORE the hand discards, so the combat scenes resolve retain-typed
	# turn_ended triggers in their end-turn intercept (picker / action's
	# cooldown finish). By the time the generic turn_ended trigger pass runs,
	# the hand is already gone — firing again would be wrong.
	pass

func _h_status(effect: Dictionary, ctx: Dictionary) -> void:
	var status_id := StringName(effect.get("status", ""))
	# Stacks may be curse-scaled (Du-Vu Doll: gain X Power where X = curse count).
	var stacks: int
	if String(effect.get("stacks_from", "")) == "energy":
		# X-value gain (Doppelganger: gain X Next Turn Draw): the stack count is
		# the energy spent on the play, threaded through ctx as x_value exactly
		# like dmg's hits_from — plus the upgrade's flat bonus (X+1).
		# stacks_mult -1 (Malaise: inflict -X Power) flips the whole amount into
		# a drain; the bonus is authored pre-flipped (-X-1 -> mult -1, bonus -1).
		stacks = maxi(0, int(ctx.get("x_value", 0))) * int(effect.get("stacks_mult", 1)) \
			+ int(effect.get("stacks_bonus", 0))
	else:
		stacks = _dyn_amount(effect, "stacks", "stacks_from", "stacks_mult")
	if not effect.has("stacks") and not effect.has("stacks_from"):
		stacks = 1
	if status_id == &"" or stacks == 0:
		return
	# `hits` applies the inflict N times; `indiscriminate` re-rolls a random
	# enemy each time (Bouncing Flask: 3 Poison to a random target, 3 times).
	# Both default to the single-target, single-application case.
	var self_target: bool = String(effect.get("target", "enemy")) == "self"
	var indiscriminate: bool = bool(effect.get("indiscriminate", false))
	var hits: int = maxi(1, int(effect.get("hits", 1)))
	# Intent gate (Go for the Eyes: if_target_intent "attack"): the inflict
	# lands only when the target is telegraphing an attack. Per-target so a
	# future cleave variant would debuff only the attackers in the room.
	var intent_gate: String = String(effect.get("if_target_intent", ""))
	for _i in hits:
		var target: Variant = ctx.get("source") if self_target else ctx.get("target")
		if indiscriminate and not self_target:
			target = _resolve_random_enemy(ctx)
		if target == null:
			continue
		if intent_gate != "" and not Stats.actor_intends_attack(target):
			continue
		# Negative stacks (Disarm: Inflict -2 Power) DRAIN the status, and the
		# stored value may go below zero — add_status floors at 0, so route
		# through the direct signed write instead. No Persistence, no
		# status_applied reaction: a drain isn't an inflict.
		if stacks < 0:
			Stats.drain_status(target, status_id, stacks)
			continue
		_apply_one_status(effect, ctx, target, status_id, stacks)

func _apply_one_status(effect: Dictionary, ctx: Dictionary, target: Variant, status_id: StringName, stacks: int) -> void:
	var scene: Variant = ctx.get("scene")
	if scene != null and scene.has_method("apply_status"):
		# In-combat path — the scene's apply_status routes through
		# Stats.apply_status_to (Persistence + its mode-specific reaction:
		# status_applied bus / Power triggers / grid refresh). Thread the
		# inflicter so Persistence scales a player-applied debuff; self-buffs and
		# enemy-applied debuffs are ignored by the shared rule, so it never
		# double-applies.
		scene.apply_status(target, status_id, stacks, ctx.get("source"))
		return
	# Scene-less fallback — used by enemy_spawned / item-pickup hooks where we
	# just want to decorate an actor before combat starts. Routes through the
	# same core (no source -> no Persistence, no reactions): baseline state.
	Stats.apply_status_to(target, status_id, stacks)

# Like `status`, but the stacks expire at the end of the turn (Prayer Beads'
# "+3 Brace until end of turn"). Applies the status normally, then records the
# amount in GameState.temp_status_stacks so ItemTriggers can strip exactly that
# many stacks off the player at the next turn boundary. Self-targeted only — it
# tracks against the single player tally — so a non-self target just falls back
# to a plain status application.
func _h_status_temp(effect: Dictionary, ctx: Dictionary) -> void:
	_h_status(effect, ctx)
	if String(effect.get("target", "self")) != "self":
		return
	var status_id := String(effect.get("status", ""))
	var stacks: int = int(effect.get("stacks", 1))
	if status_id == "" or stacks <= 0:
		return
	GameState.temp_status_stacks[status_id] = int(
		GameState.temp_status_stacks.get(status_id, 0)) + stacks

func _h_exhaust_self(_effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	var card: Variant = ctx.get("card")
	if scene == null or card == null or not scene.has_method("exhaust_card"):
		return
	scene.exhaust_card(card)

func _h_gain_max_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	# Permanent player Max HP bump — survives the item being removed from
	# inventory. Pickup-kind items use this in their item_acquired
	# trigger instead of stat_bonuses {max_hp: N}, because pickups are
	# consumed-on-acquire conceptually: the bonus belongs to the player
	# now, not to the item slot. Does NOT auto-heal — matches the
	# "Max HP and HP are independent" rule. Pair with gain_hp in the
	# same trigger when the pickup also fills the new pool (Lunch).
	var v: int = int(effect.get("value", 0))
	if v == 0:
		return
	GameState.set_max_hp(GameState.max_hp + v, false)

# Grants N "chests" — the project's term for an item reward (a gold-less
# item-choice screen). Golden Beetle uses this on curse / curse-card removal.
# Scene-less: banks the chest in GameState, where the overworld redeems it.
func _h_gain_chest(effect: Dictionary, _ctx: Dictionary) -> void:
	var n: int = _dyn_amount(effect, "value", "value_from", "value_mult")
	if not effect.has("value") and not effect.has("value_from"):
		n = 1
	GameState.grant_chest(n)

func _h_gain_hp(effect: Dictionary, ctx: Dictionary) -> void:
	# Scene-less heal that goes directly to GameState. Used by Lunch's
	# item_acquired trigger to grant a one-shot +N HP on pickup without
	# requiring an active combat scene. Distinct from `heal` (which
	# routes through scene.heal so block / on-heal hooks fire) and from
	# `add_max_hp` (which bumps the pool, never the current value).
	# Caps at max_hp via GameState.change_hp.
	var v: int = int(effect.get("value", 0))
	if v == 0:
		return
	var target: Variant = ctx.get("target")
	if target != null and not (target is Object and target == GameState) \
			and "hp" in target and "max_hp" in target and not target.is_player:
		target.hp = clampi(int(target.hp) + v, 0, int(target.max_hp))
		return
	GameState.change_hp(v)

# Wooden Nickel: roll a luck-weighted rarity tier (Common / Uncommon / Rare,
# weighted 75/20/5 like every other item roll) and grant the matching gold
# amount. `amounts` maps the three tiers low->high; defaults to [1, 5, 10], so
# Common = 1, Uncommon = 5, Rare = 10. Luck biases the roll toward the higher
# (rarer, richer) tiers, exactly like RewardScreen's item-rarity roll. Wrap in a
# `chance` effect for the "50% chance" half.
const _GOLD_TIER_BOUNDS := [75.0, 95.0]  # Common < 75 <= Uncommon < 95 <= Rare
func _h_roll_gold(effect: Dictionary, _ctx: Dictionary) -> void:
	var amounts: Array = effect.get("amounts", [1, 5, 10])
	if amounts.is_empty():
		return
	var tier: int = _roll_gold_tier()
	var amount: int = int(amounts[clampi(tier, 0, amounts.size() - 1)])
	GameState.change_gold(amount)
	GameLog.add("Wooden Nickel paid out %d gold." % amount, Color(1.0, 0.85, 0.35))
	Notifications.notify("+%d gold" % amount, Color(1.0, 0.85, 0.35))

# Returns 0 (Common) / 1 (Uncommon) / 2 (Rare) on a luck-weighted [0,1) roll.
func _roll_gold_tier() -> int:
	var roll: float = _roll01_with_luck() * 100.0
	if roll < _GOLD_TIER_BOUNDS[0]:
		return 0
	if roll < _GOLD_TIER_BOUNDS[1]:
		return 1
	return 2

# Port of RewardScreen._roll_with_luck_advantage: a [0,1) roll where positive
# Luck has a luck*10% chance to keep the higher of two rolls (negative Luck the
# lower). Higher rolls land in the richer tiers.
func _roll01_with_luck() -> float:
	var lv: int = Stats.get_value(&"luck")
	var r: float = _rng.randf()
	if lv > 0 and _rng.randf() < float(lv) * 0.1:
		return maxf(r, _rng.randf())
	if lv < 0 and _rng.randf() < float(absi(lv)) * 0.1:
		return minf(r, _rng.randf())
	return r

func _h_gain_gold(effect: Dictionary, ctx: Dictionary) -> void:
	# Verification rewards (Blasma Pistol et al) pass a `level` in ctx and
	# an `increments` list on the effect — picks the right tier amount
	# when present, falls back to `value` otherwise.
	var amount: int = int(effect.get("value", 0))
	var increments: Array = effect.get("increments", [])
	if not increments.is_empty():
		var lv: int = maxi(1, int(ctx.get("level", 1)))
		amount = int(increments[mini(lv - 1, increments.size() - 1)])
	GameState.change_gold(amount)

# Permanent run-scope stat grant (Secret Technique Instructions: +1 Dash on a
# perfected game). Scene-less, so it works from perfect_effects / pickup hooks.
# Resolves ability stats to their backing field and applies Snowball-style
# amplifiers via GameState.grant_run_stat.
#   {type: "gain_stat", stat: "dash", value: 1}
func _h_gain_stat(effect: Dictionary, _ctx: Dictionary) -> void:
	var stat: String = String(effect.get("stat", ""))
	var value: int = int(effect.get("value", 0))
	if stat == "" or value == 0:
		return
	GameState.grant_run_stat(stat, value)

func _h_lose_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	# `non_lethal: true` clamps the loss so it can never drop the player below
	# 1 HP (Leech Brood's start-of-combat tax shouldn't be able to kill).
	var v: int = int(effect.get("value", 0))
	if v <= 0:
		return
	if bool(effect.get("non_lethal", false)):
		v = mini(v, maxi(0, GameState.hp - 1))
	GameState.change_hp(-v)

func _h_conjure(effect: Dictionary, ctx: Dictionary) -> void:
	# Unified conjure handler. Args on the effect:
	#   card_id:     StringName, or "self" to copy the played card.
	#                Append "+" to force the upgraded form
	#                (e.g. "shiv+"); ignored when card_id == "self"
	#                because self conjures inherit the played card's
	#                upgrade state.
	#   destination: "hand" / "draw" / "discard"
	#   count:       int (default 1)
	#   upgraded:    bool (default false) — alternative to the "+"
	#                suffix; both routes set the same flag.
	# Only meaningful in the deckbuilder; action/strategy have no piles
	# to add to so the scene method just won't exist and we no-op.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("conjure_card"):
		return
	var card_id: StringName = StringName(String(effect.get("card_id", "self")))
	var destination: String = String(effect.get("destination", "discard"))
	var count: int = maxi(1, int(effect.get("count", 1)))
	# count_from: "discarded" (Storm of Steel) — conjure one per card the
	# preceding discard:all sent away this play. Zero discarded = no conjures.
	if String(effect.get("count_from", "")) == "discarded":
		count = int(scene.last_discard_count) if ("last_discard_count" in scene) else 0
		if count <= 0:
			return
	var force_upgraded: bool = bool(effect.get("upgraded", false))
	scene.conjure_card(card_id, destination, count, ctx.get("card"), force_upgraded)

func _h_conjure_random(effect: Dictionary, ctx: Dictionary) -> void:
	# Random-mint conjure (White Noise / Infernal Blade / Distraction). Args:
	#   card_type:   "power" / "attack" / "skill" — filters the conjure pool
	#                (Data.conjure_card_pool: the reward pool scoped to the
	#                deck picked on the New Run screen).
	#   destination: "hand" / "draw" / "discard" (default hand)
	#   count:       int (default 1)
	#   free:        bool — a hand conjure costs 0 for THIS turn (deckbuilder /
	#                strategy: temp_cost_override; action: the one-shot slot
	#                arms at the 0-cost cooldown).
	# Each scene owns the pick (its own RNG) + mode-specific delivery via
	# conjure_random_card; a scene without the method (events) no-ops.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("conjure_random_card"):
		return
	scene.conjure_random_card(
		String(effect.get("card_type", "")),
		String(effect.get("destination", "hand")),
		maxi(1, int(effect.get("count", 1))),
		bool(effect.get("free", false)),
		ctx.get("card"))

func _h_discard(effect: Dictionary, ctx: Dictionary) -> void:
	# Mirror of `draw`. Deckbuilder discards N cards from hand;
	# action/strategy add to a random/lowest ability cooldown to
	# slow the player down. Each scene that wants to react owns its
	# own `discard_cards(n, source_card, random)` method.
	#
	# `random` field flips between player-choice (the default — opens
	# the CardPickerModal in deckbuilder/strategy) and engine-picked
	# random (All-Out Attack et al). Action ignores the flag.
	var scene: Variant = ctx.get("scene")
	if scene == null:
		return
	# `all: true` (Storm of Steel) discards the whole hand — nothing to pick, so
	# it never opens the picker. The scene records how many left as
	# `last_discard_count` for a following conjure count_from: "discarded".
	if bool(effect.get("all", false)):
		if scene.has_method("discard_hand"):
			# `only: "non_attack"` (Unload) narrows the sweep to non-Attacks.
			scene.discard_hand(ctx.get("card"), String(effect.get("only", "")))
		return
	if not scene.has_method("discard_cards"):
		return
	scene.discard_cards(int(effect.get("value", 1)), ctx.get("card"), bool(effect.get("random", false)))

func _h_topdeck(effect: Dictionary, ctx: Dictionary) -> void:
	# Warcry: put N cards from hand on TOP of the draw pile. Deckbuilder and
	# strategy open the CardPickerModal (append `random` in the DSL for the
	# engine-picked variant); action auto-picks its analog (a temp auto-slot's
	# card goes back on top of the auto draw pile). `from: "discard"` (Headbutt)
	# pools the pick from the discard pile instead of hand.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("topdeck_cards"):
		return
	scene.topdeck_cards(int(effect.get("value", 1)), ctx.get("card"),
		bool(effect.get("random", false)), String(effect.get("from", "hand")),
		bool(effect.get("free_until_played", false)))

func _h_exhaust(effect: Dictionary, ctx: Dictionary) -> void:
	# Deckbuilder-only: pick N cards from hand to send to exhaust.
	# `random: true` skips the picker. Other modes silently no-op.
	var scene: Variant = ctx.get("scene")
	if scene == null:
		return
	# `all: true` (Fiend Fire) exhausts the whole hand minus the played card —
	# nothing to pick, so no picker. The scene records how many left as
	# `last_exhaust_count` for a following dmg hits_from: "exhausted".
	if bool(effect.get("all", false)):
		if scene.has_method("exhaust_hand"):
			# `only: "non_attack"` (Sever Soul) narrows the sweep to non-Attacks.
			scene.exhaust_hand(ctx.get("card"), String(effect.get("only", "")))
		return
	if not scene.has_method("exhaust_cards"):
		return
	scene.exhaust_cards(int(effect.get("value", 1)), ctx.get("card"), bool(effect.get("random", false)))

func _h_recall(effect: Dictionary, ctx: Dictionary) -> void:
	# Move cards between piles, no copies created. All for One:
	# `{type: "recall", from: "discard", to: "hand", filter: {cost: 0}}`.
	# Defaults wired for the canonical "All for One" shape so a sheet
	# row of `recall:cost=0` works without spelling out from/to.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("recall_cards"):
		return
	scene.recall_cards(
		String(effect.get("from", "discard")),
		String(effect.get("to", "hand")),
		effect.get("filter", {}),
	)

func _h_upgrade_hand(effect: Dictionary, ctx: Dictionary) -> void:
	# Deckbuilder-only: upgrade in-place (sets CardInstance.upgraded).
	# `value` is the int count, or the string "all" to skip the picker
	# and upgrade the entire hand (Armaments+).
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("upgrade_hand_cards"):
		return
	scene.upgrade_hand_cards(
		effect.get("value", 1),
		ctx.get("card"),
		bool(effect.get("random", false)),
	)

func _h_upgrade_random_cards(effect: Dictionary, _ctx: Dictionary) -> void:
	# Scene-less permanent deck upgrade (Whetstone -> Attacks, War Paint ->
	# Skills). `card_type` filters by CardData type ("" = any); `count` is how
	# many random matching, not-yet-upgraded cards to upgrade. Used from
	# item_acquired so it works without a live combat scene.
	var names: Array = GameState.upgrade_random_deck_cards(
		String(effect.get("card_type", "")), int(effect.get("count", 1)))
	if not names.is_empty():
		Notifications.notify("Upgraded %s." % ", ".join(PackedStringArray(names)),
			Color(1.0, 0.72, 0.3))

func _h_boost_cards(effect: Dictionary, ctx: Dictionary) -> void:
	# Register a persistent in-combat modifier that bumps a stat on
	# every future play of cards matching one of (match_tag,
	# match_type, match_id). Accuracy is the canonical example:
	# `boost_cards:tag=shiv:dmg:4`. Set exactly one matcher.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("add_card_boost"):
		return
	scene.add_card_boost({
		"match_tag": String(effect.get("match_tag", "")),
		"match_type": String(effect.get("match_type", "")),
		"match_id": String(effect.get("match_id", "")),
		"stat": String(effect.get("stat", "dmg")),
		"value": int(effect.get("value", 0)),
	})

func _h_gain_loot(effect: Dictionary, _ctx: Dictionary) -> void:
	# Loot counters live on GameState so they persist across combats.
	# `kind` is "potion" / "scroll" / "key"; `value` defaults to 1.
	# Alchemize: {type: "gain_loot", kind: "potion", value: 1}.
	var kind: String = String(effect.get("kind", ""))
	if kind == "":
		push_warning("EffectSystem.gain_loot: missing 'kind' on effect")
		return
	GameState.add_loot(kind, int(effect.get("value", 1)))

func _h_trigger(effect: Dictionary, ctx: Dictionary) -> void:
	# Persistent in-combat listener. `on` is a TriggerBus signal name
	# (card_played, turn_started, …); `effect` is the inner effect
	# dict to apply when that signal fires. After Image is the
	# canonical example:
	#   {type: "trigger", on: "card_played",
	#    effect: {type: "block", value: 1, target: "self"}}
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("register_trigger"):
		return
	scene.register_trigger(
		String(effect.get("on", "")),
		effect.get("effect", {}),
		String(effect.get("until", ""))
	)

func _h_add_max_hp(effect: Dictionary, ctx: Dictionary) -> void:
	# Adjust a CombatActor's max_hp (and hp on positive deltas) directly.
	# Scene-less: operates on ctx.target. Canonical use is the
	# enemy_spawned trigger — Alien Baby's "all enemies start with +3 HP".
	# Works on any actor exposing max_hp / hp fields; negative values
	# shrink the pool and clamp current hp down.
	var target: Variant = ctx.get("target")
	if target == null or not ("max_hp" in target):
		return
	var v: int = int(effect.get("value", 0))
	if v == 0:
		return
	target.max_hp = maxi(1, int(target.max_hp) + v)
	if "hp" in target:
		if v > 0:
			# Top up so the new headroom is real, not a phantom max
			target.hp = mini(int(target.hp) + v, target.max_hp)
		else:
			target.hp = mini(int(target.hp), target.max_hp)

func _h_bump_card_effect(effect: Dictionary, ctx: Dictionary) -> void:
	# Apply a persistent additive bonus to a weapon-linked CardInstance's
	# effect field. Canonical use is the verification reward path:
	# overworld calls EffectSystem.apply with ctx carrying the weapon's
	# instance_id and current weapon_level, and the effect's `increments`
	# list picks the per-level bonus value.
	#
	# Required: ctx.source_weapon_instance_id (int)
	# Optional: effect.effect_index (default 0), effect.field (default "value"),
	#           effect.increments (Array[int], indexed by ctx.level - 1),
	#           effect.value (int, used when increments missing)
	var weapon_id: int = int(ctx.get("source_weapon_instance_id", 0))
	if weapon_id == 0:
		return
	var idx: int = int(effect.get("effect_index", 0))
	var field: String = String(effect.get("field", "value"))
	var bonus: int = int(effect.get("value", 0))
	var increments: Array = effect.get("increments", [])
	if not increments.is_empty():
		var lv: int = maxi(1, int(ctx.get("level", 1)))
		bonus = int(increments[mini(lv - 1, increments.size() - 1)])
	if bonus == 0:
		return
	var bumped: int = 0
	for card in GameState.deck:
		if not (card is CardInstance):
			continue
		if card.source_weapon_id != weapon_id:
			continue
		card.bump_effect(idx, field, bonus)
		bumped += 1
	if bumped > 0:
		GameState.emit_signal("deck_changed")

func _h_temp_stat(effect: Dictionary, ctx: Dictionary) -> void:
	# Temporary stat buff from a consumable (pills). Adds to the persistent
	# temp layer so event rolls and the next combat-start derived-status pass
	# both see it. When used MID-COMBAT, also applies the equivalent derived
	# status delta to the player actor right now — apply_derived_statuses only
	# runs at combat start, so a pill popped mid-fight wouldn't otherwise
	# convert (5 STR -> +1 Power, 5 DEX -> +1 Defense, 5 INT -> +1 Arcane,
	# 5 CHA -> +1 Persistence). Luck/Speed have no derived status and are read
	# live from get_value() by their consumers.
	var stat := StringName(String(effect.get("stat", "")))
	var value: int = int(effect.get("value", 0))
	if stat == &"" or value == 0:
		return
	GameState.add_temp_stat(stat, value)
	var actor: Variant = ctx.get("source")
	if actor == null or not actor.has_method("add_status"):
		return
	var def: StatDefinition = Stats.get_definition(stat)
	if def == null or def.derived_status == &"":
		return
	var per: int = maxi(1, def.derived_per)
	var total: int = Stats.get_value(stat)
	@warning_ignore("integer_division")
	var delta: int = total / per - (total - value) / per
	if delta != 0:
		actor.add_status(def.derived_status, delta)

func _h_chance(effect: Dictionary, ctx: Dictionary) -> void:
	# Roll once on the EffectSystem RNG, with luck advantage applied
	# the same way events do, and dispatch the inner effect if the
	# roll succeeds. The inner inherits the outer call's ctx, so
	# target / source / scene / card flow through unchanged — author
	# the chance line with the same target you'd put on the inner
	# effect if it weren't wrapped. Bag o' Glitter:
	#   {type: "chance", percent: 10, effect: {type: "exhaust_self"}}
	var percent: int = int(effect.get("percent", 0))
	var inner: Dictionary = effect.get("effect", {})
	if inner.is_empty():
		return
	if not Stats.roll_chance_with_luck(_rng, percent):
		return
	apply(inner, ctx)

# Conditional wrapper gated on the PICKED enemy target's status (Dropkick:
# "If the target has Vulnerable, Gain 1 Energy and Draw 1 Card"). A wrapper —
# not an if_target_status kv on the inner verb — because the inner verbs are
# scene effects (gain_energy / draw) that the card-effect loop would otherwise
# route to the player, losing the enemy from ctx. The wrapper itself defaults
# to target "enemy", so ctx.target is the picked enemy here; the inner effect
# inherits the ctx and its handler acts on the scene/player as usual.
#   {type: "if_target_status", status: "vulnerable",
#    effect: {type: "gain_energy", value: 1}}
# Sneaky Strike (if_counter): resolve the wrapped effect only when the named
# GameState incremental counter is > 0 (discards_this_turn) — the counter
# sibling of the if_target wrapper below. The inner effect resolves through
# the same dispatch with the same ctx, so gain_energy lands on the scene.
func _h_if_counter(effect: Dictionary, ctx: Dictionary) -> void:
	var counter: String = String(effect.get("counter", ""))
	var inner: Dictionary = effect.get("effect", {})
	if counter == "" or inner.is_empty():
		return
	if GameState.incremental_value(counter) <= 0:
		return
	apply(inner, ctx)

# Entrench / Limit Break: double the source's current Block or a named
# status's stacks. Block doubles OUTRIGHT — no Frail cut, matching the StS
# rule (it isn't "gained" block). Statuses double signed, so a Power drained
# below zero (Disarm) doubles further down. Action mode owns its own block
# pool, so a scene exposing double_block gets the call instead.
func _h_double_stat(effect: Dictionary, ctx: Dictionary) -> void:
	var stat: String = String(effect.get("stat", ""))
	if stat == "":
		return
	var src: Variant = ctx.get("source")
	var scene: Variant = ctx.get("scene")
	if stat == "block":
		if scene != null and scene.has_method("double_block"):
			scene.double_block()
			return
		if src != null and ("block" in src) and int(src.block) > 0:
			src.block = int(src.block) * 2
			GameLog.add("Block doubled to %d." % int(src.block), Color(0.7, 0.85, 1.0))
		return
	if src == null or not ("statuses" in src):
		return
	var key := StringName(stat)
	var cur: int = int(src.statuses.get(key, 0))
	if cur == 0:
		return
	src.statuses[key] = cur * 2
	GameLog.add("%s doubled to %d." % [stat.capitalize(), cur * 2], Color(0.85, 0.7, 1.0))

# Havoc: play the top card of the draw pile at no cost, then exhaust it.
# Each scene owns the mode-appropriate reading via autoplay_top_card
# (deckbuilder/strategy: the real draw pile; action: the auto draw pile,
# with the played card leaving the rotation for the combat).
func _h_autoplay_top(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("autoplay_top_card"):
		return
	scene.autoplay_top_card(bool(effect.get("exhaust", false)), ctx.get("card"))

# Dual Wield: choose a hand card matching the filter (attack_or_power) and
# conjure `count` copies of it to hand. Deckbuilder/strategy open the picker;
# action auto-picks a random armed Attack/Power.
func _h_copy_from_hand(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("copy_from_hand_cards"):
		return
	scene.copy_from_hand_cards(
		maxi(1, int(effect.get("count", 1))),
		String(effect.get("filter", "attack_or_power")),
		ctx.get("card"))

# Exhume: move N cards from the exhaust pile back to hand (picker in
# deckbuilder/strategy; action re-arms a random exhausted card).
func _h_exhume(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("exhume_cards"):
		return
	scene.exhume_cards(maxi(1, int(effect.get("value", 1))), ctx.get("card"))

# Catalyst (multiply:poison:2): multiply the PICKED enemy target's stacks of
# the named status by `factor`. A direct signed write like double_stat's
# status arm — no Persistence, no status_applied reaction — so doubling a
# drained-negative stack doubles it further down, and zero stays zero.
func _h_multiply_status(effect: Dictionary, ctx: Dictionary) -> void:
	var status := StringName(String(effect.get("status", "")))
	var factor: int = int(effect.get("factor", 2))
	if status == &"" or factor == 1:
		return
	var tgt = ctx.get("target")
	if tgt == null or not ("statuses" in tgt):
		return
	var cur: int = int(tgt.statuses.get(status, 0))
	if cur == 0:
		GameLog.add("No %s to multiply — it does nothing." % String(status).capitalize(),
			Color(0.85, 0.85, 0.55))
		return
	tgt.statuses[status] = cur * factor
	GameLog.add("%s multiplied to %d!" % [String(status).capitalize(), cur * factor],
		Color(0.6, 1.0, 0.6))

# Bullet Time (free_hand): every card currently in hand costs 0 for THIS turn.
# Each scene owns its translation via make_hand_free (deckbuilder:
# temp_cost_override on the whole hand; action: every armed cooldown finishes).
func _h_free_hand(_effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("make_hand_free"):
		return
	scene.make_hand_free(ctx.get("card"))

# Nightmare: choose a card in hand; at the start of the player's NEXT turn,
# conjure `count` copies of it to hand. Deckbuilder/strategy open the picker
# and bank the pick scene-side; action auto-picks a random armed card and
# opens the copies as one-shot temp slots at the next turn tick.
func _h_nightmare(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("nightmare_cards"):
		return
	scene.nightmare_cards(maxi(1, int(effect.get("count", 3))), ctx.get("card"))

# Hologram / Seek (retrieve): move N cards from the named pile ("discard" /
# "draw") to hand. Deckbuilder/strategy open the picker over that pile;
# action re-arms a random card from its auto analog as a one-shot temp slot.
func _h_retrieve(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("retrieve_cards"):
		return
	scene.retrieve_cards(
		maxi(1, int(effect.get("value", 1))),
		String(effect.get("from", "discard")),
		ctx.get("card"))

# Spot Weakness (if_target_intent as a WRAPPER): resolve the inner effect only
# when the PICKED enemy target is telegraphing an attack — the intent sibling
# of _h_if_target_status, sharing Stats.actor_intends_attack with inflict's
# if_intent=attack gate. Action never routes here (its per-inst predicate
# lives in ActionCombat._enemy_intends_attack).
func _h_if_target_intent(effect: Dictionary, ctx: Dictionary) -> void:
	var inner: Dictionary = effect.get("effect", {})
	if inner.is_empty():
		return
	var tgt = ctx.get("target")
	if tgt == null or not Stats.actor_intends_attack(tgt):
		GameLog.add("Target isn't preparing an attack — no effect.",
			Color(0.85, 0.85, 0.55))
		return
	apply(inner, ctx)

func _h_if_target_status(effect: Dictionary, ctx: Dictionary) -> void:
	var status := StringName(String(effect.get("status", "")))
	var inner: Dictionary = effect.get("effect", {})
	if status == &"" or inner.is_empty():
		return
	var tgt = ctx.get("target")
	if tgt == null or not tgt.has_method("get_status") or tgt.get_status(status) <= 0:
		return
	apply(inner, ctx)

func _h_streak_hit(effect: Dictionary, ctx: Dictionary) -> void:
	# Grow a named consecutive-hit streak against the current target
	# (Dead Eye). The streak lives on GameState so it works in every combat
	# mode; an outgoing attack picks the count up via GameState.streak_attack_bonus
	# (called from each scene's attack path). `attack_bonus` marks the streak as
	# one that adds its count to outgoing player attacks; `label` is the name
	# shown when the bonus lands.
	#   {type: "streak_hit", key: "dead_eye", attack_bonus: true, label: "Dead Eye"}
	GameState.streak_register_hit(
		String(effect.get("key", "")),
		ctx.get("target"),
		bool(effect.get("attack_bonus", false)),
		String(effect.get("label", "")),
	)

func _h_streak_reset(effect: Dictionary, _ctx: Dictionary) -> void:
	# Clear a named streak (Dead Eye on a Blind whiff). {type: "streak_reset", key: "dead_eye"}
	GameState.streak_reset(String(effect.get("key", "")))

func _h_counter(effect: Dictionary, ctx: Dictionary) -> void:
	# "Every Nth …" incremental items (Happy Flower, Nunchaku, Ornamental Fan,
	# Shuriken, Pen Nib). Reads a shared GameState counter (bumped centrally by
	# ItemTriggers.fire) and fires the nested `effects` only when the counter
	# rolls past `every`. The counter itself is NOT incremented here — that
	# happens once per event regardless of how many counter items are owned —
	# so two Nunchakus don't double-count the same attack.
	#   {type: "counter", key: "attacks_total", every: 10, label: "Nunchaku",
	#    effects: [{type: "gain_energy", value: 1}]}
	var every: int = maxi(1, int(effect.get("every", 1)))
	var value: int = GameState.incremental_value(String(effect.get("key", "")))
	if value <= 0 or value % every != 0:
		return
	var label: String = String(effect.get("label", ""))
	if label != "":
		GameLog.add("%s triggers!" % label, Color(0.7, 1.0, 0.7))
	for inner in effect.get("effects", []):
		apply(inner, ctx)

func _h_attack_double(_effect: Dictionary, _ctx: Dictionary) -> void:
	# Pen Nib. Arms the double-damage window for the Attack currently being
	# played; Stats.resolve_damage reads pen_nib_double_active and doubles each
	# of the card's hits. Cleared at the next card play / turn / combat.
	GameState.pen_nib_double_active = true

func _h_if_hp(effect: Dictionary, ctx: Dictionary) -> void:
	# Conditional on the PLAYER's current HP fraction. Fires the inner effect
	# only when the threshold passes. `below: f` -> hp <= max*f (Meat on the
	# Bone: heal when at/below 50%); `above: f` -> hp > max*f (Leech Brood:
	# lose HP only when above 50%). The two are complementary at the boundary.
	#   {type: "if_hp", below: 0.5, effect: {type: "gain_hp", value: 12}}
	if GameState.max_hp <= 0:
		return
	var inner: Dictionary = effect.get("effect", {})
	if inner.is_empty():
		return
	var frac: float = float(GameState.hp) / float(GameState.max_hp)
	var ok: bool = true
	if effect.has("below"):
		ok = frac <= float(effect["below"])
	elif effect.has("above"):
		ok = frac > float(effect["above"])
	if ok:
		apply(inner, ctx)

func _h_free_random_hand_card(_effect: Dictionary, ctx: Dictionary) -> void:
	# Mummified Hand. Each mode interprets "a card becomes free" its own way:
	# deckbuilder zeroes a random hand card's cost this turn; strategy frees a
	# random other slotted ability (no per-turn play cost); action slashes
	# attack cooldowns. The played card is passed so scenes can exclude it.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("make_random_hand_card_free"):
		return
	scene.make_random_hand_card_free(ctx.get("card"))

func _h_reduce_card_cost(effect: Dictionary, ctx: Dictionary) -> void:
	# Empty Tome. At combat start, knock `amount` off the cost of `count` random
	# cards matching an optional tag/type filter (weapon Attack) for the rest of
	# the fight. Cost IS cooldown in action mode (2*cost + rarity), so the same
	# discount shortens the card's cooldown there — one knob, three modes. Each
	# scene owns the mode-appropriate application via reduce_random_card_cost.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("reduce_random_card_cost"):
		return
	scene.reduce_random_card_cost(
		maxi(1, int(effect.get("count", 1))),
		maxi(1, int(effect.get("amount", 1))),
		String(effect.get("if_card_tag", "")),
		String(effect.get("if_card_type", "")),
	)
