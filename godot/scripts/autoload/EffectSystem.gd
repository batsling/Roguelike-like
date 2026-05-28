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

func apply_all(effects: Array, ctx: Dictionary) -> void:
	for e in effects:
		apply(e, ctx)

# ---------------------------------------------------------------------------
# Default handlers — registered at load. The combat scene exposes the
# methods these handlers call back into (deal_damage, gain_block, etc.)
# via the `scene` context entry.
# ---------------------------------------------------------------------------

func _register_defaults() -> void:
	register("dmg", _h_dmg)
	register("block", _h_block)
	register("heal", _h_heal)
	register("draw", _h_draw)
	register("gain_energy", _h_gain_energy)
	register("lose_energy", _h_lose_energy)
	register("status", _h_status)
	register("exhaust_self", _h_exhaust_self)
	register("gain_gold", _h_gain_gold)
	register("lose_hp", _h_lose_hp)
	register("conjure", _h_conjure)
	register("discard", _h_discard)
	register("exhaust", _h_exhaust)
	register("recall", _h_recall)
	register("upgrade_hand", _h_upgrade_hand)
	register("boost_cards", _h_boost_cards)
	register("gain_loot", _h_gain_loot)
	register("trigger", _h_trigger)
	register("chance", _h_chance)
	register("add_max_hp", _h_add_max_hp)
	register("bump_card_effect", _h_bump_card_effect)

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
	# `hits` lets a single dmg effect resolve N times (Twin Strike 5x2).
	# Action mode handles its own pacing via _resolve_card_effects and
	# never reaches this path for multi-hit, so the loop here is purely
	# for deckbuilder/strategy where instant N hits are fine.
	# Indiscriminate (Blood Magic's addon) re-rolls the target each
	# iteration so a 3-hit attack lands on 3 random enemies instead of
	# dumping all three into the same actor.
	var hits: int = maxi(1, int(effect.get("hits", 1)))
	var indiscriminate: bool = bool(effect.get("indiscriminate", false))
	for _i in range(hits):
		var tgt: Variant = ctx.get("target")
		if indiscriminate:
			tgt = _pick_random_enemy(ctx.get("scene"))
			if tgt == null:
				return
		scene.deal_damage(ctx.get("source"), tgt, effect.get("value", 0), effect)

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
	if scene == null or not scene.has_method("gain_block"):
		return
	# Block defaults to gaining on self
	var target: Variant = ctx.get("target") if effect.get("target", "self") != "self" else ctx.get("source")
	scene.gain_block(target, effect.get("value", 0))

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
	scene.draw_cards(effect.get("value", 1))

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

func _h_status(effect: Dictionary, ctx: Dictionary) -> void:
	var target: Variant = ctx.get("target") if effect.get("target", "enemy") != "self" else ctx.get("source")
	var status_id := StringName(effect.get("status", ""))
	var stacks: int = int(effect.get("stacks", 1))
	if status_id == &"" or stacks == 0 or target == null:
		return
	var scene: Variant = ctx.get("scene")
	if scene != null and scene.has_method("apply_status"):
		# In-combat path — fires status_applied, triggers Power reactions.
		# Source intentionally not threaded through; scene-level Persistence
		# handling lives outside this dispatcher to avoid double-applying.
		scene.apply_status(target, status_id, stacks)
		return
	# Scene-less fallback — used by enemy_spawned / item-pickup hooks
	# where we just want to decorate an actor before combat starts.
	# Skips Persistence and the status_applied bus on purpose: this is
	# baseline state, not the player actively casting.
	if target.has_method("add_status"):
		target.add_status(status_id, stacks)

func _h_exhaust_self(_effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	var card: Variant = ctx.get("card")
	if scene == null or card == null or not scene.has_method("exhaust_card"):
		return
	scene.exhaust_card(card)

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

func _h_lose_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	GameState.change_hp(-effect.get("value", 0))

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
	var force_upgraded: bool = bool(effect.get("upgraded", false))
	scene.conjure_card(card_id, destination, count, ctx.get("card"), force_upgraded)

func _h_discard(effect: Dictionary, ctx: Dictionary) -> void:
	# Mirror of `draw`. Deckbuilder discards N cards from hand;
	# action/strategy add to a random/lowest ability cooldown to
	# slow the player down. Each scene that wants to react owns its
	# own `discard_cards(n, source_card, random)` method.
	#
	# `random` field flips between player-choice (the default — opens
	# the CardPickerModal in deckbuilder) and engine-picked random
	# (All-Out Attack et al). Action / Strategy ignore the flag.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("discard_cards"):
		return
	scene.discard_cards(int(effect.get("value", 1)), ctx.get("card"), bool(effect.get("random", false)))

func _h_exhaust(effect: Dictionary, ctx: Dictionary) -> void:
	# Deckbuilder-only: pick N cards from hand to send to exhaust.
	# `random: true` skips the picker. Other modes silently no-op.
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("exhaust_cards"):
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
		effect.get("effect", {})
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
