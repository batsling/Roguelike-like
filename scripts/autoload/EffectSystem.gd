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

# Permanent run-scope stat/verb grant (Vajra +1 Bash, Anchor +1 Block, …).
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
