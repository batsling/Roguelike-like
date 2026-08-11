extends Node

# EVENTS (docs/event-sheet-authoring.md) — the payoff for walking into a corner
# of the map.
#
# Roughly 40% of the run graph's games are leaves: one connection, so visiting
# one is a ROUND TRIP — a game there, a game back the way you came — for a single
# game's reward. Every offered card already quotes that cost as a route badge, so
# without something waiting at the end a leaf is a mistake with a label on it. An
# event fires AFTER the game at such a node is beaten, on top of the normal drop,
# and that is what turns the detour into a decision.
#
# This autoload owns three things:
#   * PLACEMENT — which node carries which event, decided deterministically so
#     the badge on a card can never lie (see event_for).
#   * GATES — the sheet's Requirement column, and a choice's `needs` clauses.
#   * RESOLUTION — applying a choice's payload, which may leave an event goal or
#     a curse goal behind on GameState for the checklist to carry.
#
# The state itself lives on GameState (run-scope, saved, reset); this is the
# logic, the same split ScrollSystem has.

# Placement is decided by hashing the node id together with the run seed, NOT by
# rolling when the card is drawn. Overworld2 redraws its offering constantly — a
# bash refilling a slot, a scramble, an arrival — and a rolled event would change
# under the player between seeing the badge and taking the card. `_slot_enemies`
# keyed off `_offer_seed()` solves the same problem for the enemy behind a card.
const _PLACEMENT_SALT := "event-placement"


# The event waiting at `game_id`, or null. Deterministic for a given node + run:
# ask twice, get the same answer.
#
# Every eligible leaf carries one until the pool runs dry — with `Limit 1` across
# the current roster that is at most four badged nodes a run, front-loaded, which
# is the honest shape of a four-event catalogue rather than a rarity dressed up
# as design.
func event_for(game_id: StringName) -> EventData2:
	if game_id == &"":
		return null
	var pool: Array = _eligible_for(game_id)
	if pool.is_empty():
		return null
	# Sorted so the pool's order can't drift with dictionary iteration order —
	# determinism has to survive a reload, not just a redraw.
	pool.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var pick: int = abs(_placement_hash(game_id)) % pool.size()
	return pool[pick]


func _placement_hash(game_id: StringName) -> int:
	return hash("%s|%s|%d" % [_PLACEMENT_SALT, String(game_id), GameState.run_seed])


# Everything that could legally stand at this node right now: not used up, in
# tier, in the right kind of place, and past its Requirement.
func _eligible_for(game_id: StringName) -> Array:
	var out: Array = []
	for ev in Data.all_events2():
		if blockers_for(ev, game_id).is_empty():
			out.append(ev)
	return out


# WHY `ev` cannot stand at `game_id` right now — one short phrase per gate it
# fails, empty when it is eligible. This is the single statement of the gates:
# `_eligible_for` is `blockers_for(...).is_empty()`, so the list an author reads
# in the dev panel and the rule the roller applies cannot drift apart. Authoring
# an event that never turns up is the commonest way to lose an afternoon here,
# and it is invisible without this.
func blockers_for(ev: EventData2, game_id: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if ev == null:
		return PackedStringArray(["no event"])
	if not _limit_allows(ev):
		out.append("used %d/%d this run"
			% [int(GameState.events_fired.get(ev.id, 0)), ev.run_limit])
	if not _where_allows(ev, game_id):
		out.append("not a %s" % ev.where.replace("_", " "))
	if not ev.tier_allows(RunDifficulty.tier_name(RunDifficulty.current_tier())):
		out.append("wrong tier")
	if not requirement_met(ev):
		out.append("needs %s" % requirement_text(ev.requirement))
	if not _play_pools_stocked(ev):
		out.append("no game carries its play_game tag")
	return out


# What each gate stat is called in front of a player. `capitalize()` alone turned
# `hp` into "Hp" and `games` into "Games", neither of which is the name anything
# else in the game uses for it.
const GATE_STAT_NAMES := {
	"hp": "Health", "max_hp": "Max Health", "gold": "Gold",
	"games": "Games played", "keys": "Keys", "bombs": "Bombs", "bash": "Bash",
	"dash": "Dash", "push": "Push", "transmute": "Transmute",
	"scramble": "Scramble", "shields": "Shields",
}

# A Requirement dictionary in words: "Health <= 70%". One implementation, read by
# the Collection's event page and by the dev panel.
static func requirement_text(req: Dictionary) -> String:
	if req.is_empty():
		return "nothing"
	var stat: String = String(req.get("stat", ""))
	return "%s %s %s%s" % [
		String(GATE_STAT_NAMES.get(stat, stat.capitalize())),
		String(req.get("op", "<=")), str(req.get("value", 0)),
		"%" if bool(req.get("percent", false)) else ""]


func _limit_allows(ev: EventData2) -> bool:
	if ev.run_limit <= 0:
		return true
	return int(GameState.events_fired.get(ev.id, 0)) < ev.run_limit


func _where_allows(ev: EventData2, game_id: StringName) -> bool:
	match ev.where:
		"any":
			return true
		"game":
			var g: GameData = Data.get_game(game_id)
			return g != null and g.display_name == ev.source_game
		_:
			# "dead_end": the whole point (§1). A leaf has exactly one way in and
			# the same way back out.
			return RunGraph.degree(game_id) <= 1


# An event that sends the player to a tagged game is only worth staging if such
# a game EXISTS for this run. Punch Off's whole bargain is "do the work and take
# everything" against "take the treasure and wear the Injury"; with no mecha game
# to go and play, the work option is a dead button and the event is a worse
# version of itself. So the pool is checked before the event is ever placed —
# which also means it is checked before the badge is drawn, and the badge stays
# honest.
#
# Derived from the event's own content rather than authored in a Requirement
# cell: a future `play_game tag=<whatever>` gets the same protection without
# anyone remembering to ask for it.
func _play_pools_stocked(ev: EventData2) -> bool:
	for choice in ev.choices:
		var play: Dictionary = choice.get("play", {})
		if play.is_empty():
			continue
		if games_with_tag(StringName(String(play.get("tag", "")).to_lower())).is_empty():
			return false
	return true


# Every game this run could actually be sent to that carries `tag`. ONE
# definition, used both by the gate above and by the roll that picks the
# destination — if those two disagreed, an event would advertise a detour it
# could not deliver.
#
# Respects the run's game filter (Settings.game_filter), so an OWNED run is only
# ever sent to a game the player owns, and skips bashed games, which are off the
# board for the rest of the run.
func games_with_tag(tag: StringName) -> Array:
	var pool: Array = []
	if tag == &"":
		return pool
	for g in Data.all_games():
		if not (g is GameData) or not RunGraph.passes_filter(g):
			continue
		if GameLoop2.is_bashed(g.id):
			continue
		for t in g.tags:
			if StringName(String(t).to_lower()) == tag:
				pool.append(g.id)
				break
	return pool


# --- the Relic Trader's shelf ------------------------------------------------
#
# Most events are the same event every time they fire. The Relic Trader is not:
# his three offers are built out of what YOU are carrying, so the row on the sheet
# says "Take the Top One" and only the run can say what the top one is.
#
# The pairing is rolled ONCE, when the event opens (begin_event), and held here
# for as long as it is on screen. It cannot be rolled per-draw the way placement
# is hashed, because it depends on the inventory rather than on the node — and it
# must not be re-rolled per repaint, or the button would name a different relic
# every time the modal re-rendered.
#
# The sheet keeps the wording: `<give>` and `<get>` are holes in the choice's
# prose and in its mechanical line, filled in here. Nothing about this event is
# hardcoded in GDScript except the two hole names and the verb.
const TRADE_SLOTS := 3
const GIVE_HOLE := "<give>"
const GET_HOLE := "<get>"

var _trade_offers: Array = []   # [{ "give": StringName, "get": StringName }]


# An event is opening: roll whatever live content it needs. Called by EventModal2
# beside mark_fired, and by any test or dev-panel path that opens one.
func begin_event(ev: EventData2) -> void:
	_trade_offers.clear()
	if ev == null or not _wants_trades(ev):
		return
	_trade_offers = _roll_trades()


func _wants_trades(ev: EventData2) -> bool:
	for choice in ev.choices:
		if _trade_slot(choice) > 0:
			return true
	return false


# Which offer a choice is the button for — 1-based, 0 for a choice that trades
# nothing. Read off the effects rather than off the choice's position, so the
# sheet can put "Trade Nothing" anywhere in the list.
func _trade_slot(choice: Dictionary) -> int:
	for eff in choice.get("effects", []):
		if eff is Dictionary and String(eff.get("type", "")) == "trade_relic":
			return int(eff.get("slot", 0))
	return 0


# Up to TRADE_SLOTS pairings of one relic you hold against one you don't.
#
# Both halves are drawn from the ROLLABLE pool (ItemData.is_rollable) — no
# starters, no Boss relics, no Event relics. A starter is the character you
# picked, a Boss relic is a boss you beat and an Event relic is an event you
# walked into; none of them is a thing to find in a stranger's coat, in either
# direction.
func _roll_trades() -> Array:
	var rng := _roll_rng()
	var mine: Array = []
	var held: Dictionary = {}
	for it in GameState.inventory:
		if it is ItemData and it.is_rollable() and not held.has(it.id):
			held[it.id] = true
			mine.append(it.id)
	var theirs: Array = []
	for it in Data.reward_item2_pool():
		if not held.has(it.id):
			theirs.append(it.id)
	var offers: Array = []
	for _i in range(TRADE_SLOTS):
		if mine.is_empty() or theirs.is_empty():
			break
		var give: StringName = mine.pop_at(rng.randi_range(0, mine.size() - 1))
		var get_id: StringName = theirs.pop_at(rng.randi_range(0, theirs.size() - 1))
		offers.append({"give": give, "get": get_id})
	return offers


func trade_offers() -> Array:
	return _trade_offers


# The offer behind slot `slot` (1-based), or {} when there isn't one — which is
# how a run carrying only one relic ends up being shown one trade instead of
# three, rather than two buttons that swap nothing.
func trade_offer(slot: int) -> Dictionary:
	if slot < 1 or slot > _trade_offers.size():
		return {}
	return _trade_offers[slot - 1]


# Do the swap. Deliberately does NOT consume the offer: the choice that fires it
# closes the event, and the prose printed on the way out still has to be able to
# name both halves.
func resolve_trade(slot: int) -> bool:
	var offer: Dictionary = trade_offer(slot)
	if offer.is_empty():
		return false
	var taking: ItemData = Data.get_item2(StringName(offer.get("get", &"")))
	if taking == null:
		return false
	for it in GameState.inventory:
		if it is ItemData and it.id == StringName(offer.get("give", &"")):
			GameState.remove_item(it)
			break
	GameState.add_item(taking)
	return true


# `<give>` / `<get>` filled in from this choice's offer. A choice that trades
# nothing is returned untouched, so this is safe to run over every line.
func fill_trade_names(text: String, choice: Dictionary) -> String:
	if text == "" or not (text.contains(GIVE_HOLE) or text.contains(GET_HOLE)):
		return text
	var offer: Dictionary = trade_offer(_trade_slot(choice))
	return text.replace(GIVE_HOLE, _item_name(offer.get("give", &""))) \
		.replace(GET_HOLE, _item_name(offer.get("get", &"")))


# "a relic" and not "" for an unresolved hole: the Collection's event page draws
# these lines outside any run, where there is no pack to build an offer from, and
# the sentence still has to read.
func _item_name(id) -> String:
	var it: ItemData = Data.get_item2(StringName(id))
	return it.display_name if it != null else "a relic"


# --- gates ------------------------------------------------------------------

# The Requirement column: a condition on the RUN, distinct from tier (the ladder)
# and where (the map). An unparseable or unknown stat reads as NOT met, so a
# typo'd gate hides its event rather than firing it everywhere.
func requirement_met(ev: EventData2) -> bool:
	return _compare_stat(ev.requirement)


func _compare_stat(req: Dictionary) -> bool:
	if req.is_empty():
		return true
	var stat: String = String(req.get("stat", ""))
	var have: float = float(_run_stat(stat))
	if have < 0.0:
		return false
	var want: float = float(req.get("value", 0))
	if bool(req.get("percent", false)):
		# A percentage reads against the stat's own maximum; only hp has one.
		var maximum: float = float(GameState.max_hp) if stat == "hp" else 100.0
		want = maximum * want / 100.0
	match String(req.get("op", ">=")):
		"<": return have < want
		"<=": return have <= want
		">": return have > want
		"==": return is_equal_approx(have, want)
		_: return have >= want


# -1 for a stat this build doesn't have, which every comparison then fails.
func _run_stat(stat: String) -> int:
	match stat:
		"hp": return GameState.hp
		"max_hp": return GameState.max_hp
		"gold": return GameState.gold
		"games": return GameState.games_played
		"keys": return GameState.keys
		"bombs": return GameState.bombs
		"bash": return GameState.bash
		"dash": return GameState.dash_charges
		"push": return GameState.push
		"transmute": return GameState.transmute
		"scramble": return GameState.scramble
		"shields": return GameState.shields
		_: return -1


# Is a choice offered right now? `picks` is choice id -> times taken so far in
# THIS event, which is what lets a two-stage event ("Immerse", then "Linger")
# live on one row.
func choice_available(choice: Dictionary, picks: Dictionary) -> bool:
	if not _repeat_allows(choice, picks):
		return false
	# A trade button with no offer behind it would swap nothing for nothing. The
	# Relic Trader shows one row per thing he could actually take off you, which on
	# a run carrying a single relic is one row and not three.
	var slot: int = _trade_slot(choice)
	if slot > 0 and trade_offer(slot).is_empty():
		return false
	for gate in choice.get("gates", []):
		if not _gate_passes(gate, picks):
			return false
	return true


func _repeat_allows(choice: Dictionary, picks: Dictionary) -> bool:
	var taken: int = int(picks.get(choice.get("id", ""), 0))
	match String(choice.get("repeat", "end")):
		"again":
			var cap: int = int(choice.get("repeat_max", 0))
			return cap <= 0 or taken < cap
		_:
			# "end" and "stay" are both once — the difference is what happens to
			# the EVENT afterwards, not to the choice.
			return taken < 1


func _gate_passes(gate: Dictionary, picks: Dictionary) -> bool:
	if gate.has("choice"):
		var have: int = int(picks.get(String(gate["choice"]), 0))
		var want: int = int(gate.get("value", 0))
		match String(gate.get("op", ">=")):
			"<": return have < want
			"<=": return have <= want
			">": return have > want
			"==": return have == want
			_: return have >= want
	return _run_stat(String(gate.get("resource", ""))) >= int(gate.get("value", 0))


# --- resolving a choice -----------------------------------------------------

# Apply one choice. `taken` is how many times this choice has ALREADY been picked
# (so the first pick is 0) — it is the X the sheet's {expr} holes scale on.
#
# Returns {"result", "text", "close", "play", "rolled", "won"}:
#   result  the prose to print — the choice's own, or the event's chance_won /
#           chance_lost when this choice gambled
#   text    what it did, in words
#   close   true when the event should shut (Repeat: End, or a won gamble)
#   play    a play_game request for the caller to run, or {}
#   rolled  whether this choice carried a `chance`
#   won     whether that roll landed (always false when it didn't roll)
func resolve_choice(ev: EventData2, choice: Dictionary, taken: int) -> Dictionary:
	var words: Array = []

	for eff in choice.get("effects", []):
		EffectSystem.apply(_scaled(eff, taken), {})
	if String(choice.get("effects_text", "")) != "":
		words.append(fill_trade_names(_fill_holes(String(choice["effects_text"]), taken), choice))

	# The gamble. Rolled AFTER the certain costs, because that is the order the
	# player experiences: the acid burns whether or not there was a relic in there.
	var chance: Dictionary = choice.get("chance", {})
	var rolled: bool = not chance.is_empty()
	var won: bool = false
	if rolled:
		won = Stats.roll_chance_with_luck(_roll_rng(), chance_percent(chance, taken))
		if won:
			for eff in chance.get("effects", []):
				EffectSystem.apply(_scaled(eff, taken), {})
			if String(chance.get("effects_text", "")) != "":
				words.append(_fill_holes(String(chance["effects_text"]), taken))

	var goal: Dictionary = choice.get("goal", {})
	if not goal.is_empty():
		GameState.add_event_goal(ev.id, String(goal.get("condition", "")),
			int(goal.get("games", 1)), goal.get("effects", []),
			String(goal.get("effects_text", "")))
		words.append("Goal: %s" % goal.get("condition", ""))

	var curse: Dictionary = choice.get("curse", {})
	if not curse.is_empty():
		GameState.add_curse_goal(StringName(curse.get("curse", &"")), ev.id,
			int(curse.get("games", 0)))

	# A gamble's prose comes from the EVENT, because it depends on the roll rather
	# than on which button produced it — Scrap Ooze's two reaches print the same
	# two strings. The choice's own `results` rung still stands in when the event
	# left them blank, so a gamble is authorable without them.
	var result: String = fill_trade_names(result_for(choice, taken), choice)
	if rolled:
		var prose: String = ev.chance_won if won else ev.chance_lost
		if prose != "":
			result = prose

	return {
		"result": result,
		"text": ", ".join(PackedStringArray(words)),
		# A won gamble closes the event whatever Repeat says: `Again` is what
		# happens when you LOSE, and there is nothing left to reach for once the
		# relic is in your hand.
		"close": won or String(choice.get("repeat", "end")) == "end",
		"play": choice.get("play", {}),
		"rolled": rolled,
		"won": won,
	}


# The prose a choice prints on THIS press. `results` is a ladder — one rung per
# press, the LAST rung standing for every press after it — so a `Repeat: Again`
# choice can escalate what it says the way {X} escalates what it costs, without
# an authored column group per press.
#
# The last rung sticking is what makes an unbounded ladder authorable: Abyssal
# Baths' Linger climbs forever, and its final rung is the warning that the next
# dip kills you, which is exactly the line that should keep printing while the
# player keeps pressing.
func result_for(choice: Dictionary, taken: int) -> String:
	var ladder: Array = choice.get("results", [])
	if ladder.is_empty():
		return ""
	return String(ladder[clampi(taken, 0, ladder.size() - 1)])


# The odds of a `chance` on THIS press, with its {expr} hole resolved against how
# often the choice has been taken and clamped to a real percentage — an unbounded
# ladder like Scrap Ooze's 25, 35, 45… runs past 100 if you keep reaching.
func chance_percent(chance: Dictionary, taken: int) -> int:
	return clampi(int(_scaled(chance, taken).get("percent", 0)), 0, 100)


# Lazily created and randomised. Events roll at press time — unlike PLACEMENT,
# which is hashed so the card's badge cannot change under the player, a gamble is
# supposed to be unknown until it is taken.
var _rng: RandomNumberGenerator = null

func _roll_rng() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	return _rng


# An effect whose amount is a {expr} hole, resolved against X = `taken`. The
# expression machinery is StatusData's — one Expression implementation for the
# whole project, and the generator has already rewritten `a^b` into pow(a, b).
func _scaled(effect: Dictionary, taken: int) -> Dictionary:
	var scaled: Dictionary = effect.get("scaled", {})
	if scaled.is_empty():
		return effect
	var out: Dictionary = effect.duplicate(true)
	out.erase("scaled")
	for field in scaled.keys():
		out[field] = int(round(_evaluate(String(scaled[field]), taken)))
	return out


# What an {expr} hole may name, beyond X.
#
# X alone was enough while every hole scaled on how often a choice had been
# pressed. A cost expressed as a FRACTION OF THE PLAYER needs the player in it:
# the Golden Idol charges 25% of Max Health, and the whole point of writing it
# that way is that the button prints "-3 Health" rather than the percentage. So
# the run's own numbers are bound too, and the sheet can say
# `lose_hp {max(1,round(0.25*MAX_HP))}`.
#
# A closed list, in a fixed order, because Expression binds by POSITION — the
# names here and the values in _evaluate are one list written twice and they must
# stay in step.
const EXPR_VARS := ["X", "MAX_HP", "HP", "GOLD", "GAMES"]

func _evaluate(expr: String, x: int) -> float:
	var e := Expression.new()
	if e.parse(expr.strip_edges(), EXPR_VARS) != OK:
		push_warning("EventSystem: cannot parse '%s' (%s)" % [expr, e.get_error_text()])
		return float(x)
	var value: Variant = e.execute([x, GameState.max_hp, GameState.hp, GameState.gold,
		GameState.games_played], null, false)
	if e.has_execute_failed():
		push_warning("EventSystem: cannot evaluate '%s'" % expr)
		return float(x)
	return float(value) if (value is float or value is int) else float(x)


# The same holes inside a words-string, so a button can say what THIS press costs
# ("-5 Health") rather than quoting the formula at the player.
func _fill_holes(text: String, x: int) -> String:
	var out: String = ""
	var rest: String = text
	while true:
		var open_at: int = rest.find("{")
		if open_at < 0:
			return out + rest
		var close_at: int = rest.find("}", open_at)
		if close_at < 0:
			return out + rest
		out += rest.substr(0, open_at)
		out += StatusData.format_number(_evaluate(rest.substr(open_at + 1, close_at - open_at - 1), x))
		rest = rest.substr(close_at + 1)
	return out


# The mechanical line under a choice's button: what THIS press costs and pays,
# with every {expr} hole already resolved against how often the choice has been
# taken. That is what replaces Slay the Spire 2's "the baths may kill you"
# warning — the escalation is a pure function of X, so the button can just say
# the number instead of quoting the formula.
func describe_choice(choice: Dictionary, taken: int) -> String:
	var parts: Array = []
	var text: String = String(choice.get("effects_text", ""))
	if text != "":
		parts.append(fill_trade_names(_fill_holes(text, taken), choice))

	var goal: Dictionary = choice.get("goal", {})
	if not goal.is_empty():
		var games: int = int(goal.get("games", 1))
		parts.append("Goal for %d %s: %s → %s" % [
			games, "game" if games == 1 else "games",
			goal.get("condition", ""), goal.get("effects_text", "")])

	var curse: Dictionary = choice.get("curse", {})
	if not curse.is_empty():
		var cd: CurseData2 = Data.get_curse2(StringName(curse.get("curse", &"")))
		if cd != null:
			var games: int = int(curse.get("games", 0))
			if games <= 0:
				games = cd.timer
			# 0 here means the curse's own Timer is 0, which is PERMANENT — the same
			# -1 sentinel GameState.add_curse_goal will store.
			parts.append("Curse (%s): %s" % [
				CurseData2.window_text(games if games > 0 else -1), cd.describe()])

	var play: Dictionary = choice.get("play", {})
	if not play.is_empty():
		parts.append("Go play a %s game, then: %s"
			% [play.get("tag", ""), play.get("effects_text", "")])

	# "25%: +1 Small Chest" — the shape Slay the Spire's own option line uses, and
	# the odds for THIS press, since they climb with every failed one.
	var chance: Dictionary = choice.get("chance", {})
	if not chance.is_empty():
		parts.append("%d%%: %s" % [chance_percent(chance, taken),
			_fill_holes(String(chance.get("effects_text", "")), taken)])

	return " · ".join(PackedStringArray(parts))


# Record that an event has run, so its `run_limit` closes it off for the run.
func mark_fired(ev: EventData2) -> void:
	if ev == null:
		return
	GameState.events_fired[ev.id] = int(GameState.events_fired.get(ev.id, 0)) + 1
