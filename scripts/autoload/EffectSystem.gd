extends Node

# Centralized dispatch for structured item effects (post games-first cut, §11).
# The simulated-combat effect handlers (dmg / block / status / draw / energy /
# card manipulation) are gone with the combat scenes; what remains is the
# SCENE-LESS handler set the games-first item layer uses — the effects that fire
# on game_beaten / item_acquired / item_used and mutate the run state directly
# (docs/games-first-redesign.md §8.1).
#
# An effect is a Dictionary like { "type": "gain_hp", "value": 1 }, applied via
#   EffectSystem.apply(effect, ctx)   /   EffectSystem.apply_all(effects, ctx)
# `ctx` carries { source, target, scene, card } but the surviving handlers are
# scene-less, so those are effectively unused. Unknown effect types (e.g. a
# legacy combat handler on a 1.0 item surfaced in a 2.0 run) warn and no-op
# rather than crash.

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
		# A legacy combat effect type on a 1.0 item shown in a 2.0 run — no combat
		# scene to act on, so it silently no-ops.
		return
	h.call(effect, ctx)
	# Opt-in player-facing notification, authored as a `notify` field on the
	# effect dict (on the INNER effect for a chance-wrapped proc).
	if effect.has("notify"):
		Notifications.notify(String(effect["notify"]), Color(0.6, 1.0, 0.7))

func apply_all(effects: Array, ctx: Dictionary) -> void:
	for e in effects:
		apply(e, ctx)

# Resolves an effect amount that may be dynamic: when `from_key` is present its
# value names a live tally and the amount is that count times `mult_key`
# (default 1); otherwise the static `base_key` is used.
func _dyn_amount(effect: Dictionary, base_key: String, from_key: String, mult_key: String) -> int:
	if effect.has(from_key):
		return _dynamic_count(String(effect[from_key])) * int(effect.get(mult_key, 1))
	return int(effect.get(base_key, 0))

# Live count for a dynamic effect source. Curses are shelved (§5) but the count
# helper stays valid; "curses" = active curses currently held.
func _dynamic_count(source: String) -> int:
	match source:
		"curses":
			return GameState.curse_count()
	push_warning("EffectSystem: unknown dynamic count source '%s'" % source)
	return 0

# ---------------------------------------------------------------------------
# Scene-less handlers (games-first item layer)
# ---------------------------------------------------------------------------

func _register_defaults() -> void:
	register("gain_hp", _h_gain_hp)
	register("gain_max_hp", _h_gain_max_hp)
	register("gain_stat", _h_gain_stat)
	register("gain_gold", _h_gain_gold)
	register("gain_chest", _h_gain_chest)
	register("lose_hp", _h_lose_hp)
	register("if_hp", _h_if_hp)
	register("chance", _h_chance)
	register("teleport_type", _h_teleport_type)
	register("obtain_item", _h_obtain_item)
	register("random_item_choice", _h_random_item_choice)
	register("apply_status", _h_apply_status)

# Scene-less heal straight to the run HP pool. Caps at max_hp via change_hp.
func _h_gain_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.change_hp(v)

# Permanent Max HP bump (does NOT auto-heal — Max HP and HP are independent, §3).
func _h_gain_max_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.set_max_hp(GameState.max_hp + v, false)

# Permanent run-scope stat/verb grant (Vajra +1 Bash, Anchor +1 Shield, …).
# Routes ability verbs (bash/transmute/scramble/block/…) to their backing field.
func _h_gain_stat(effect: Dictionary, _ctx: Dictionary) -> void:
	var stat: String = String(effect.get("stat", ""))
	var value: int = int(effect.get("value", 0))
	if stat == "" or value == 0:
		return
	GameState.grant_run_stat(stat, value)

func _h_gain_gold(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.change_gold(v)

# Grants N chests (item rewards, §8.2), banked in GameState for the RewardScreen.
func _h_gain_chest(effect: Dictionary, _ctx: Dictionary) -> void:
	var n: int = _dyn_amount(effect, "value", "value_from", "value_mult")
	if not effect.has("value") and not effect.has("value_from"):
		n = 1
	GameState.grant_chest(n)

# Applies a STATUS (§13) — the hook a location, item, or scroll uses to reach into
# the run's goals without knowing anything about them. `target` picks the side:
#   player                  -> a standing goal (buff) or a tax on every goal (debuff)
#   current | all | random  -> onto enemies, via GameLoop2's targeting
# Defaults to the player, since that is the side a pickup usually lands on.
func _h_apply_status(effect: Dictionary, _ctx: Dictionary) -> void:
	var status_id := StringName(String(effect.get("status", "")))
	if status_id == &"":
		return
	var stacks: int = int(effect.get("value", 1))
	if stacks == 0:
		return
	var target: String = String(effect.get("target", "player")).to_lower()
	if target == "player" or target == "self":
		GameState.apply_status(status_id, stacks)
	else:
		GameLoop2.apply_enemy_status(status_id, stacks, target)

func _h_lose_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v <= 0:
		return
	if bool(effect.get("non_lethal", false)):
		v = mini(v, maxi(0, GameState.hp - 1))
	GameState.change_hp(-v)

# Conditional on the player's current HP fraction (Meat on the Bone heals when
# at/below 50%). `below: f` -> hp <= max*f; `above: f` -> hp > max*f.
func _h_if_hp(effect: Dictionary, ctx: Dictionary) -> void:
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

# Rolls once (luck-weighted) and dispatches the inner effect on success.
func _h_chance(effect: Dictionary, ctx: Dictionary) -> void:
	var percent: int = int(effect.get("percent", 0))
	var inner: Dictionary = effect.get("effect", {})
	if inner.is_empty():
		return
	if not Stats.roll_chance_with_luck(_rng, percent):
		return
	apply(inner, ctx)

# ---------------------------------------------------------------------------
# Games-first (2.0) active-item effects (docs/games-first-redesign.md §8).
# These are overworld actions, so they route through the mounted Overworld2 via
# GameState.overworld_scene; off the map they no-op rather than crash.
# ---------------------------------------------------------------------------

# Ride the Bus: teleport to a random game of a given type on the map.
func _h_teleport_type(effect: Dictionary, _ctx: Dictionary) -> void:
	var scene = GameState.overworld_scene
	if scene == null or not scene.has_method("teleport_to_type"):
		return
	scene.teleport_to_type(StringName(String(effect.get("game_type", "")).to_lower()))

# Wand of Wishing: obtain any one item — opens the overworld's full-catalog
# item picker.
func _h_obtain_item(_effect: Dictionary, _ctx: Dictionary) -> void:
	var scene = GameState.overworld_scene
	if scene == null or not scene.has_method("obtain_any_item"):
		return
	scene.obtain_any_item()

# Unstable Genome: gain 1 of N random items — banked as one chest offering
# `count` choices (§8.2 Large chest), redeemed by the overworld's RewardScreen.
# `destroy_self` consumes the source item that fired the trigger.
func _h_random_item_choice(effect: Dictionary, ctx: Dictionary) -> void:
	var count: int = maxi(1, int(effect.get("count", 3)))
	GameState.grant_chest(1, count)
	if bool(effect.get("destroy_self", false)):
		var item = ctx.get("item")
		if item is ItemData:
			GameState.remove_item(item)
