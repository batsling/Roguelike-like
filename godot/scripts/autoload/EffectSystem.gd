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

func _ready() -> void:
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
	register("status", _h_status)
	register("exhaust_self", _h_exhaust_self)
	register("gain_gold", _h_gain_gold)
	register("lose_hp", _h_lose_hp)
	register("conjure", _h_conjure)

func _h_dmg(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("deal_damage"):
		return
	# `hits` lets a single dmg effect resolve N times (Twin Strike 5x2).
	# Action mode handles its own pacing via _resolve_card_effects and
	# never reaches this path for multi-hit, so the loop here is purely
	# for deckbuilder/strategy where instant N hits are fine.
	var hits: int = maxi(1, int(effect.get("hits", 1)))
	for _i in range(hits):
		scene.deal_damage(ctx.get("source"), ctx.get("target"), effect.get("value", 0), effect)

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

func _h_status(effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	if scene == null or not scene.has_method("apply_status"):
		return
	var target: Variant = ctx.get("target") if effect.get("target", "enemy") != "self" else ctx.get("source")
	scene.apply_status(target, effect.get("status", ""), effect.get("stacks", 1))

func _h_exhaust_self(_effect: Dictionary, ctx: Dictionary) -> void:
	var scene: Variant = ctx.get("scene")
	var card: Variant = ctx.get("card")
	if scene == null or card == null or not scene.has_method("exhaust_card"):
		return
	scene.exhaust_card(card)

func _h_gain_gold(effect: Dictionary, _ctx: Dictionary) -> void:
	GameState.change_gold(effect.get("value", 0))

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
