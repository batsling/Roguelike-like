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
	register("gain_empty_max_hp", _h_gain_empty_max_hp)
	register("gain_stat", _h_gain_stat)
	register("gain_gold", _h_gain_gold)
	register("gain_chest", _h_gain_chest)
	register("chest_reward", _h_chest_reward)
	register("lose_hp", _h_lose_hp)
	register("take_damage", _h_take_damage)
	register("lose_max_hp", _h_lose_max_hp)
	register("lose_stat", _h_lose_stat)
	register("lose_gold", _h_lose_gold)
	register("heal_full", _h_heal_full)
	register("gain_scroll", _h_gain_scroll)
	register("gain_loot", _h_gain_loot)
	register("none", _h_none)
	register("if_hp", _h_if_hp)
	register("chance", _h_chance)
	register("counter", _h_counter)
	register("reroll_enemies", _h_reroll_enemies)
	register("teleport_type", _h_teleport_type)
	register("obtain_item", _h_obtain_item)
	register("random_item_choice", _h_random_item_choice)
	register("apply_status", _h_apply_status)
	register("apply_tile", _h_apply_tile)
	register("apply_unit", _h_apply_unit)
	register("gain_item", _h_gain_item)
	register("gain_item_per_rarity", _h_gain_item_per_rarity)
	register("add_curse", _h_add_curse)
	register("spawn_enemy", _h_spawn_enemy)
	register("trade_relic", _h_trade_relic)
	# Objects (docs/object-sheet-authoring.md).
	register("gain_pickups", _h_gain_pickups)
	register("gain_item_of", _h_gain_item_of)
	register("donate_gold", _h_donate_gold)
	register("bank_payout", _h_bank_payout)
	register("jam_object", _h_jam_object)
	register("destroy_object", _h_destroy_object)
	register("spawn_object", _h_spawn_object)
	register("spend_bomb", _h_spend_bomb)

# Scene-less heal straight to the run HP pool. Caps at max_hp via change_hp.
func _h_gain_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.change_hp(v)

# Permanent Max Health bump, and the Health to fill it: "+2 Max Health" hands you
# a container that arrives FULL, which is what the phrase means to anyone who has
# played one of the games this one is a graph of. The heal is the size of the
# bump that actually landed, not the size asked for — Handcuffs' max_hp_cap can
# swallow part of a raise, and healing the requested amount there would hand out
# Health the cap just refused to make room for.
func _h_gain_max_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v == 0:
		return
	var before: int = GameState.max_hp
	GameState.set_max_hp(before + v, false)
	var landed: int = GameState.max_hp - before
	if landed > 0:
		GameState.change_hp(landed)

# The other half of the split: the container WITHOUT the Health in it. Authored
# as `gain_empty_max_hp` so an item that wants the bare cap says so out loud,
# rather than the heal being a thing every other author has to remember to add.
func _h_gain_empty_max_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.set_max_hp(GameState.max_hp + v, false)

# Permanent run-scope stat/verb grant (Anchor +1 Shield, a level-up's +1 Dash, …).
# Routes ability verbs (bash/transmute/scramble/block/…) to their backing field.
func _h_gain_stat(effect: Dictionary, _ctx: Dictionary) -> void:
	var stat: String = String(effect.get("stat", ""))
	var value: int = int(effect.get("value", 0))
	if stat == "" or value == 0:
		return
	GameState.grant_run_stat(stat, value)

# --- the cost half of the vocabulary (docs/event-sheet-authoring.md §5) ------
# Events charge for things and a curse is nothing but a charge, so every grant
# above has a mirror here rather than a second code path with its own rounding.

# Max Health down. Floors at 1 — a Max Health of 0 is a run that ended without
# anything saying so.
#
# Losing the cap does NOT cost Health: the mirror of `gain_max_hp` is deliberately
# not symmetrical, because a full container is a gift and an emptied one is a
# second punishment on top of the one the event already charged. set_max_hp only
# clamps, so Health moves solely when it no longer FITS — 20/30 losing 5 is
# 20/25, while 30/30 losing 5 is 25/25 and there is nowhere else for it to go.
func _h_lose_max_hp(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.set_max_hp(maxi(1, GameState.max_hp - v), false)

func _h_lose_stat(effect: Dictionary, _ctx: Dictionary) -> void:
	var stat: String = String(effect.get("stat", ""))
	var value: int = int(effect.get("value", 0))
	if stat == "" or value == 0:
		return
	GameState.grant_run_stat(stat, -value)

# `lose_gold all` empties the purse. The price names a POOL rather than a number,
# which is the whole point of it — an event can charge everything you are carrying
# without the sheet knowing how much that is, and the trade stays honest whether
# the player walked in with 3 gold or 30.
func _h_lose_gold(effect: Dictionary, _ctx: Dictionary) -> void:
	if bool(effect.get("all", false)):
		GameState.set_gold(0)
		return
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.change_gold(-v)

func _h_heal_full(_effect: Dictionary, _ctx: Dictionary) -> void:
	GameState.set_hp(GameState.max_hp)

# LOOT is a category, not a synonym for scroll: today the only loot type is the
# scroll, so both land in the same place, but an event authored as `gain_loot`
# widens on its own the day a second type exists (§5).
func _h_gain_scroll(effect: Dictionary, _ctx: Dictionary) -> void:
	_grant_loot(int(effect.get("value", 1)))

func _h_gain_loot(effect: Dictionary, _ctx: Dictionary) -> void:
	_grant_loot(int(effect.get("value", 1)))

func _grant_loot(n: int) -> void:
	if n > 0:
		GameState.add_loot("scroll", n)

# An authored no-op, so "this choice does nothing" is a thing the sheet can say
# rather than a blank cell that reads as unfinished.
func _h_none(_effect: Dictionary, _ctx: Dictionary) -> void:
	pass

func _h_gain_gold(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v != 0:
		GameState.change_gold(v)

# Grants N chests (item rewards, §8.2), banked in GameState for the RewardScreen.
func _h_gain_chest(effect: Dictionary, _ctx: Dictionary) -> void:
	var n: int = _dyn_amount(effect, "value", "value_from", "value_mult")
	if not effect.has("value") and not effect.has("value_from"):
		n = 1
	# `choices` is the SIZE — small 1, medium 2, large 3, huge 5 — and dropping it
	# was why a "small chest" offered two items: grant_chest's 0 means "take the
	# reward screen's own default", which is BASE_ITEM_CHOICES plus Discovery.
	# A sized chest has to carry its size all the way to the screen.
	GameState.grant_chest(n, int(effect.get("choices", 0)))

# A [chest reward] (§8.2): `value` chest POINTS spent on the size ladder rather
# than a count of identically-sized chests. Data owns the equation — 3 points is
# one Large, 6 is a Huge and a Medium — and the chests it names are banked in ONE
# grant, so a reward the player was promised as a single line arrives as a single
# line rather than as one toast per chest.
func _h_chest_reward(effect: Dictionary, _ctx: Dictionary) -> void:
	var points: int = _dyn_amount(effect, "value", "value_from", "value_mult")
	if not effect.has("value") and not effect.has("value_from"):
		points = 1
	GameState.grant_chests(Data.chest_reward_sizes(points))

# Applies a STATUS (§13) — the hook a location, item, or scroll uses to reach into
# the run's goals without knowing anything about them. `target` picks the SIDE the
# status acts through, and what that side does is the sheet's business, not this
# handler's:
#   player                  -> the status's On Player side (Vajra's +1 Strength)
#   current | all | random  -> its On Enemy side, via GameLoop2's targeting
# Defaults to the player, since that is the side a pickup usually lands on.
func _h_apply_status(effect: Dictionary, ctx: Dictionary) -> void:
	var status_id := StringName(String(effect.get("status", "")))
	if status_id == &"":
		return
	var stacks: int = int(effect.get("value", 1))
	if stacks == 0:
		return
	var target: String = String(effect.get("target", "player")).to_lower()
	if target == "player" or target == "self":
		GameState.apply_status(status_id, stacks)
		return
	# `target=enemy` is the sheet asking for a body to be POINTED AT rather than
	# named by a rule (Staff of Flame). The instance rides `ctx.target`, put there
	# by whoever did the aiming — GameState.use_item passes it through — so a
	# firing with nobody picked lands on nothing rather than falling through to
	# "current" and burning whatever happens to be standing closest.
	if target == "enemy":
		var aimed: Variant = ctx.get("target")
		if not (aimed is int) or int(aimed) <= 0:
			push_warning("EffectSystem.apply_status: target=enemy fired with no body aimed")
			return
		GameLoop2.apply_status_to(int(aimed), status_id, stacks)
		return
	GameLoop2.apply_enemy_status(status_id, stacks, target)

# TILE EFFECTS AND UNITS (§17) — the two ways an item or a scroll reaches the
# GROUND rather than a body. Both take the same target vocabulary, and the split
# in it is the same one `apply_status` has: a word that names a RULE (`front`,
# `all`, `back`, `random_empty`) resolves itself, while `tile` is the sheet asking
# for a cell to be POINTED AT, with the pick riding `ctx.target` exactly as an
# aimed body does. A firing with nothing picked lays nothing rather than falling
# through to a rule and covering ground the player never chose.
func _h_apply_tile(effect: Dictionary, ctx: Dictionary) -> void:
	var tile_id := StringName(String(effect.get("tile", "")))
	if tile_id == &"":
		return
	for cell in _effect_cells(effect, ctx, "apply_tile"):
		GameLoop2.apply_tile(cell, tile_id)

func _h_apply_unit(effect: Dictionary, ctx: Dictionary) -> void:
	var unit_id := StringName(String(effect.get("unit", "")))
	if unit_id == &"":
		return
	for cell in _effect_cells(effect, ctx, "apply_unit"):
		GameLoop2.apply_unit(cell, unit_id)

# Which cells a ground effect covers. Shared by the two handlers above so a target
# word cannot mean one thing for a tile and another for a unit.
func _effect_cells(effect: Dictionary, ctx: Dictionary, what: String) -> Array:
	var target: String = String(effect.get("target", "tile")).to_lower()
	if target == "tile" or target == "cell":
		var aimed: Variant = ctx.get("target")
		if not (aimed is Vector2i):
			push_warning("EffectSystem.%s: target=tile fired with no cell aimed" % what)
			return []
		# The reach the sheet authored (Red Candle's `cols=2-3`) is enforced HERE
		# as well as in the board's aiming highlight, so a cell that arrived some
		# other way — a test, DevTools, a future keyboard target — obeys the same
		# fence the mouse does.
		var cell: Vector2i = aimed
		var lo: int = int(effect.get("col_min", 0))
		var hi: int = int(effect.get("col_max", 0))
		if lo > 0 and (cell.x < lo or cell.x > hi):
			push_warning("EffectSystem.%s: column %d is outside the authored %d-%d"
				% [what, cell.x, lo, hi])
			return []
		return [cell]
	if target == "random_empty":
		var free: Vector2i = GameLoop2.random_empty_cell()
		# A board with nothing free lays nothing. Landmines quietly skipping a game
		# where every cell is occupied is the honest outcome — there is no ground
		# for a mine to be on.
		return [free] if free.x <= GameLoop2.grid_cols() else []
	return GameLoop2.target_cells(target)

# A NAMED item, handed straight over (the Golden Idol event's `gain_item
# golden_idol`). The counterpart to the random draws above: an authored reward
# whose whole point is which item it is.
func _h_gain_item(effect: Dictionary, _ctx: Dictionary) -> void:
	var template: ItemData = Data.get_item2(StringName(String(effect.get("item", ""))))
	if template == null:
		push_warning("EffectSystem.gain_item: no items2.0 item '%s'" % effect.get("item", ""))
		return
	GameState.add_item(template)

# Calling Bell: `count` items, ONE PER RARITY off the bottom of the ladder —
# Common, then Uncommon, then Rare. Not `count` rolls: a rarity roll is 75%
# Common, so three of them are three Commons most of the time, and the relic is
# supposed to be a boss's payout rather than a handful of change. Prefers what the
# player does not already own, the same preference a shop shelf has.
func _h_gain_item_per_rarity(effect: Dictionary, _ctx: Dictionary) -> void:
	var count: int = clampi(int(effect.get("count", 3)), 1, int(ItemData.Rarity.LEGENDARY) + 1)
	var taken: Dictionary = {}
	for rarity in range(count):
		var bucket: Array = Data.reward_item2_pool_of(rarity)
		if bucket.is_empty():
			continue
		var fresh: Array = bucket.filter(func(it):
			return not taken.has(it.id) and not GameState.has_item(it.id))
		var pick_from: Array = fresh if not fresh.is_empty() else bucket
		var pick: ItemData = pick_from[_rng.randi_range(0, pick_from.size() - 1)]
		taken[pick.id] = true
		GameState.add_item(pick)

# Calling Bell's other half: a curse goal (docs/event-sheet-authoring.md §6) from
# an ITEM rather than from an event. `games` of 0 means the curse's own Timer,
# which for Curse of the Bell is "never" — an item that hands out a permanent bill
# is exactly what a Boss relic with a downside should be.
func _h_add_curse(effect: Dictionary, _ctx: Dictionary) -> void:
	GameState.add_curse_goal(StringName(String(effect.get("curse", ""))), &"",
		int(effect.get("games", 0)))

# What every CURSE now costs: a fresh enemy at the run's current difficulty, put
# straight onto the following stack. Same conjuring the Scroll of Create Monster
# does (§4.1) — a curse's bill is a body on the board, not a number off a bar.
#
# roll_conjured_enemy and not roll_enemy: the difficulty is the whole of what a
# conjured body is priced on, so it is not allowed to widen into the rest of the
# roster the way an offering's roll may.
#
# An optional `tag` narrows the roll to the enemies carrying it — Punch Off's
# robots — so an event can conjure a body that belongs to the scene it just
# described rather than whatever the roster happened to hand over.
func _h_spawn_enemy(effect: Dictionary, _ctx: Dictionary) -> void:
	var tag := StringName(String(effect.get("tag", "")))
	var names: Array = []
	for _i in range(maxi(1, int(effect.get("value", 1)))):
		var enemy: GoalEnemyData = GameLoop2.roll_conjured_enemy(-1, tag)
		if enemy == null:
			break
		GameLoop2.spawn_to_stack(enemy)
		names.append(enemy.display_name)
	if names.is_empty():
		return
	Notifications.notify("%s starts following you." % ", ".join(PackedStringArray(names)),
		UITheme.CURSE)
	GameLog.add("%s joined the stack." % ", ".join(PackedStringArray(names)), UITheme.CURSE)

# The Relic Trader's swap. The pairing lives on EventSystem, which rolled it when
# the event opened — this handler only names the slot the button belongs to.
func _h_trade_relic(effect: Dictionary, _ctx: Dictionary) -> void:
	EventSystem.resolve_trade(int(effect.get("slot", 1)))

# DAMAGE, as against `lose_hp`'s bill: it resolves on the battlefield, so the tries
# absorb it first and the player's own statuses scale it (Burn's "or take 3
# Damage", §13). GameLoop2 owns that arithmetic and is the one place damage reaches
# the player, so this hands off to it rather than reaching for Health itself.
#
# GameLoop2 bills a missed `demand` through the same function directly, with the
# resolve's summary to write into; a `take_damage` authored anywhere else lands
# here and simply has no summary to bill.
func _h_take_damage(effect: Dictionary, _ctx: Dictionary) -> void:
	var v: int = int(effect.get("value", 0))
	if v <= 0:
		return
	GameLoop2.damage_player(v)

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
#
# Which way Luck points is read off the INNER effect: a proc that hands you
# something is one you want to fire, and a proc that jams the machine or takes
# something off you is one Luck should be steering you away from. Reading it
# from the payload rather than authoring a direction per clause keeps the sheet
# free of a field whose right answer is always derivable.
func _h_chance(effect: Dictionary, ctx: Dictionary) -> void:
	var percent: float = float(effect.get("percent", 0.0))
	var inner: Dictionary = effect.get("effect", {})
	if inner.is_empty():
		return
	if not Stats.roll_chance(_rng, percent, favour_of(inner)):
		return
	apply(inner, ctx)


# The INCREMENTAL wrapper: "every Nth time this happens, do the thing" (Charm of
# the Vampire's third body). Bumps the owning relic's counter and fires the nested
# `effects` only on the tick that trips it, then rolls the count back to zero.
#
# The count lives on the ITEM (ItemData.counter_value), which the run-scope trigger
# runner hands over as ctx.item — one counter per inventory slot, so two copies each
# count the same body once and each pay out on their own third, and a copy picked up
# mid-run starts at zero. That is the difference from the combat-era `counter`, which
# read a shared GameState tally and needed the tally bumped centrally to stop two
# copies double-counting one event. The counter drawn on the item's art is this
# number (see Overworld2._counter_badge).
#
# Fires nothing without an item to count on — a counter with no owner is a counter
# with no memory, and silently paying out every time would be worse than not firing.
func _h_counter(effect: Dictionary, ctx: Dictionary) -> void:
	var item = ctx.get("item")
	if not (item is ItemData):
		return
	var every: int = maxi(1, int(effect.get("every", 1)))
	var inner: Array = effect.get("effects", [])
	if inner.is_empty():
		return
	item.counter_value = int(item.counter_value) + 1
	if item.counter_value < every:
		GameState.emit_signal("inventory_changed")
		return
	item.counter_value = 0
	var label: String = String(effect.get("label", item.display_name))
	GameLog.add("%s reaches %d — it pays out." % [label, every], Color(0.85, 0.9, 0.7))
	apply_all(inner, ctx)
	GameState.emit_signal("inventory_changed")


# D10: re-roll every non-boss body on the battlefield at its own difficulty and
# game type (GameLoop2.reroll_enemies owns the rule; this is only the wiring).
# Says so even when it changes nothing, because a charge was spent either way and
# a silent active reads as a broken one.
func _h_reroll_enemies(_effect: Dictionary, _ctx: Dictionary) -> void:
	var swapped: int = GameLoop2.reroll_enemies()
	if swapped > 0:
		GameLog.add("The board is re-rolled — %d enem%s changed."
			% [swapped, "y" if swapped == 1 else "ies"], Color(0.6, 0.75, 1.0))
		Notifications.notify("Re-rolled %d enem%s."
			% [swapped, "y" if swapped == 1 else "ies"], Color(0.6, 0.75, 1.0))
	else:
		GameLog.add("Nothing on the board could be re-rolled.", Color(0.8, 0.8, 0.8))
		Notifications.notify("Nothing to re-roll.", Color(0.8, 0.8, 0.8))


# The effect types a player does NOT want to land. Everything not named here is
# a payout, so Favour.HIGH is the default and a new reward verb inherits the
# right direction without being listed.
const UNWANTED_EFFECTS := [
	"jam_object", "lose_hp", "take_damage", "lose_max_hp", "lose_gold", "lose_stat",
	"add_curse", "spawn_enemy", "item_downgrade", "forget",
]

func favour_of(effect: Dictionary) -> int:
	return Stats.Favour.LOW if UNWANTED_EFFECTS.has(String(effect.get("type", ""))) \
		else Stats.Favour.HIGH


# --- objects (docs/object-sheet-authoring.md) ------------------------------
#
# The handlers a MACHINE needs. Each of the five that touch a machine's own state
# reads `ctx.object` — the instance that was pressed — because the choice dict is
# shared by every copy of that machine on screen, and "this one jams" has to mean
# the one under the player's cursor rather than the kind.

# `gain_pickups 2-4 hp|gold` — loose change on the floor. Each pickup is rolled
# independently from `kinds`, so 3 pickups is as likely to be three coins as it
# is two hearts and a coin.
#
# The COUNT is Favour.HIGH (more is better). Which kind each one lands on is
# Favour.NONE: a heart is not better than a coin, it is different, and letting
# Luck pick would be Luck deciding it knows what the player needs.
func _h_gain_pickups(effect: Dictionary, _ctx: Dictionary) -> void:
	var kinds: Array = effect.get("kinds", [])
	if kinds.is_empty():
		return
	var count: int = Stats.roll_range(_rng, int(effect.get("min", 1)),
		int(effect.get("max", 1)), Stats.Favour.HIGH)
	var hearts: int = 0
	var coins: int = 0
	for _i in range(count):
		match String(kinds[_rng.randi_range(0, kinds.size() - 1)]):
			"hp":
				hearts += 1
			"gold":
				coins += 1
	if hearts > 0:
		GameState.change_hp(hearts)
	if coins > 0:
		GameState.change_gold(coins)
	var said: Array = []
	if hearts > 0:
		said.append("%d Health" % hearts)
	if coins > 0:
		said.append("%d Gold" % coins)
	if not said.is_empty():
		Notifications.notify("+%s" % " and ".join(PackedStringArray(said)),
			Color(0.6, 1.0, 0.7))


# `gain_item_of blood_bag|iv_bag` — one named relic at random. Favour.NONE on
# WHICH: neither bag is the better bag, so this is a straight coin flip however
# much Luck the run is carrying.
#
# Writes the name it granted back into `ctx` so the prose can say what appeared
# (EventSystem's {ITEM} hole).
func _h_gain_item_of(effect: Dictionary, ctx: Dictionary) -> void:
	var ids: Array = effect.get("items", [])
	if ids.is_empty():
		return
	var pick: StringName = StringName(String(ids[_rng.randi_range(0, ids.size() - 1)]))
	var template: ItemData = Data.get_item2(pick)
	if template == null:
		push_warning("EffectSystem.gain_item_of: no items2.0 item '%s'" % pick)
		return
	GameState.add_item(template)
	ctx["granted_item"] = pick
	ctx["granted_item_name"] = template.display_name


func _h_donate_gold(effect: Dictionary, ctx: Dictionary) -> void:
	ObjectSystem.donate(ctx.get("object"), int(effect.get("value", 1)))


func _h_bank_payout(effect: Dictionary, ctx: Dictionary) -> void:
	var want: int = Stats.roll_range(_rng, int(effect.get("min", 1)),
		int(effect.get("max", 1)), Stats.Favour.HIGH)
	ObjectSystem.withdraw(ctx.get("object"), want)


func _h_jam_object(_effect: Dictionary, ctx: Dictionary) -> void:
	ObjectSystem.jam(ctx.get("object"))


func _h_destroy_object(effect: Dictionary, ctx: Dictionary) -> void:
	ObjectSystem.destroy(ctx.get("object"), String(effect.get("scope", "")) == "run")


func _h_spawn_object(effect: Dictionary, _ctx: Dictionary) -> void:
	ObjectSystem.spawn_by_tag(StringName(String(effect.get("tag", ""))),
		int(effect.get("min", 1)), int(effect.get("max", 1)))


# A Bomb spent somewhere that is not the battlefield. Fires the same bomb_used
# trigger the board does — Blood Bombs says "when using a Bomb" and blowing up a
# vending machine is using one — with no enemy behind it, which every surviving
# listener already tolerates (GameState only forwards it to item triggers).
func _h_spend_bomb(effect: Dictionary, _ctx: Dictionary) -> void:
	var want: int = maxi(1, int(effect.get("value", 1)))
	if GameState.bombs < want:
		return
	GameState.bombs -= want
	GameState.emit_signal("stats_changed")
	TriggerBus.bomb_used.emit({
		"instance": -1, "enemy": null, "hits": 0, "destroyed": 0})

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
