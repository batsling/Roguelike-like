extends Node

# EVENTS (docs/event-sheet-authoring.md) — what the run does between games.
#
# An event fires after EVERY game the run plays, on top of whatever the game
# itself paid. It used to hang off dead ends only, as the thing that made a
# two-game round trip worth taking; it is now the run's own rhythm. The games
# this is a graph of are hour-long roguelikes, and an event is the beat between
# two of them — a decision that takes a minute and costs something.
#
# This autoload owns three things:
#   * THE DRAW — which event a game pays, dealt on arrival from a per-rarity
#     shuffle bag (see roll_for_arrival).
#   * GATES — the sheet's Requirement column, and a choice's `needs` clauses.
#   * RESOLUTION — applying a choice's payload, which may leave an event goal or
#     a curse goal behind on GameState for the checklist to carry.
#
# The state itself lives on GameState (run-scope, saved, reset); this is the
# logic, the same split ScrollSystem has.

# AN EVENT AFTER EVERY GAME, ROLLED ON ARRIVAL.
#
# This used to hang events off DEAD ENDS and decide which one by hashing the node
# id against the run seed. The hash was there for a real reason — the offered
# card carried an `EVENT` badge, Overworld2 redraws its offering constantly, and
# a rolled event would have changed under the player between seeing the badge and
# taking the card.
#
# Both halves of that are gone. An event now fires after every game the run
# plays, so there is no longer a subset of nodes to point at and the badge came
# off the cards with the placement that justified it. What replaces the hash is a
# SHUFFLE BAG:
#
#   * roll the rarity ladder (Luck rerolls it, like every other roll) and fall
#     down to the nearest stocked rung — today everything is Common, so every
#     roll lands there;
#   * draw from the events of that rarity NOT YET SEEN this run. Drawing marks an
#     event seen whether or not the player engaged with it — seeing it is what
#     was spent;
#   * when a rarity's bag empties, reshuffle it, except that the event which just
#     emptied it may not be the one that opens the next bag;
#   * an event gated out right now (Requirement unmet, wrong tier) is SKIPPED and
#     stays in the bag for later rather than being burned.
#
# One event per GAME, not per arrival: `event_nodes_fired` spends the node, so
# walking a two-node loop is not an event faucet.
#
# EXCEPT AT A HUB, where the shop is what happens (§12, §14). Two things queued
# on top of each other after one game was one thing too many — the shop mounts
# under the board and the event opens a modal over it, so the shop the player
# walked here for was something they had to dismiss an event to reach. A hub
# already is the thing that happens at a hub; it does not also owe a roll.
#
# Read off the game actually PLAYED at the node, not the node's id: a transmuted
# spot plays an off-map game, off-map games are never hubs, so the shop leaves
# with the game it belonged to and the spot goes back to paying an event.
func roll_for_arrival(game_id: StringName) -> EventData2:
	if game_id == &"" or GameState.event_nodes_fired.has(game_id):
		return null
	var here: GameData = GameLoop2.game_at(game_id)
	if here != null and ShopSystem.is_hub(here.id):
		return null
	var pool: Array = _pool_at_rolled_rarity(game_id)
	if pool.is_empty():
		return null

	var unseen: Array = pool.filter(func(ev): return not GameState.events_seen.has(ev.id))
	if unseen.is_empty():
		# The bag is empty: everything at this rarity has come up. Reshuffle, and
		# refuse to open the new bag on the event that closed the old one.
		_reshuffle(pool)
		unseen = pool.filter(func(ev): return ev.id != GameState.last_event_id)
		if unseen.is_empty():
			unseen = pool     # a one-event rarity has no other answer
	elif unseen.size() > 1:
		unseen = unseen.filter(func(ev): return ev.id != GameState.last_event_id)

	unseen.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return unseen[_roll_rng().randi_range(0, unseen.size() - 1)]


# Everything eligible at the rolled rarity, falling down the ladder when a rung
# is unstocked. The fall-back is measured against the ELIGIBLE set rather than
# the whole catalogue, so a rung whose only events are gated out right now reads
# as unstocked and the roll drops to one that can actually pay.
func _pool_at_rolled_rarity(game_id: StringName) -> Array:
	var eligible: Array = _eligible_for(game_id)
	if eligible.is_empty():
		return []
	return Data.rarity_bucket_of(eligible, Data.roll_item_rarity(_roll_rng()))


# Empty the bag for the rarity `pool` belongs to — and only that one. Rarities
# cycle independently: seeing every Common should not reset the Rares.
func _reshuffle(pool: Array) -> void:
	for ev in pool:
		GameState.events_seen.erase(ev.id)


# Everything that could legally stand at this node right now: in tier, in the
# right kind of place, and past its Requirement.
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
	# `shields` is the PER-GAME pool, which the player reads as Temporary Shields
	# (GameState.TEMP_SHIELD_NAME); `bonus_shields` is the one that stays and is
	# simply Shields. The field names are the older ones — see GameState.
	"scramble": "Scramble", "shields": "Temporary Shields",
	"bonus_shields": "Shields", "relics": "Tradeable Relics",
	# The pack again: bottles carried, identified or not.
	"potions": "Potions",
}

# A Requirement dictionary in words: "Health <= 70%". One implementation, read by
# the Collection's event page and by the dev panel.
#
# A multi-clause Requirement — `{"all": [...]}`, what the sheet's `and` compiles
# to — reads as its clauses joined the way they were authored, so the phrase the
# player sees is the phrase in the cell.
static func requirement_text(req: Dictionary) -> String:
	if req.is_empty():
		return "nothing"
	if req.has("all"):
		var parts := PackedStringArray()
		for clause in req.get("all", []):
			if clause is Dictionary:
				parts.append(requirement_text(clause))
		return " and ".join(parts) if parts.size() > 0 else "nothing"
	var stat: String = String(req.get("stat", ""))
	return "%s %s %s%s" % [
		String(GATE_STAT_NAMES.get(stat, stat.capitalize())),
		String(req.get("op", "<=")), str(req.get("value", 0)),
		"%" if bool(req.get("percent", false)) else ""]


# Blank is the ordinary case and means "anywhere" — an event fires after every
# game, so the column answers no placement question today. It stays wired for the
# per-location work (locations2.0): "this one only at a dead end", "this one only
# at its own game".
func _where_allows(ev: EventData2, game_id: StringName) -> bool:
	match ev.where:
		"dead_end":
			# A leaf: exactly one way in and the same way back out.
			return RunGraph.degree(game_id) <= 1
		"game":
			var g: GameData = Data.get_game(game_id)
			return g != null and g.display_name == ev.source_game
		_:
			return true


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
# Filled with whatever relic a `gain_item_of` rolled, for prose that has to name
# the thing the roll produced. Braces rather than angle brackets to match the
# sheet's other {…} holes, and read before _fill_holes would try the arithmetic.
const ITEM_HOLE := "{ITEM}"
# The other two name holes, and the other half of the same idea. `<give>` names
# a relic the trader picked out to swap; these name the one thing the run has
# picked out to be HANDED OVER — Ranwid's middle and bottom buttons, which cost
# a potion and a relic rather than a number.
const POTION_HOLE := "<potion>"
const RELIC_HOLE := "<relic>"
# The third thing Ranwid asks for on his first meeting (§16): a card out of the
# pack. Rolled with the rest of the offering and named on the button, because
# "give me a card" is not a price anyone can weigh.
const CARD_HOLE := "<card>"

var _trade_offers: Array = []   # [{ "give": StringName, "get": StringName }]
# What this event will take off you if you let it: one loot entry out of the
# pack and one relic id out of the inventory, rolled when the event opens for
# the same reason the trader's pairing is. A button that says "Give Swirly
# Potion" has to name the same bottle when it is pressed as it named when it was
# drawn, and a per-repaint roll would rename it under the player's cursor.
var _offered_potion: Dictionary = {}
var _offered_relic: StringName = &""
var _offered_card: Dictionary = {}
# What the event is already OFFERING when it opens (`EventData2.opens_with`) —
# the Potion Lab's three bottles. Rolled here, once, for the same reason the
# trade pairing is: the modal repaints on every press and a per-repaint roll
# would deal three different potions each time the player looked away.
var _opening_loot: Array = []


# An event is opening: roll whatever live content it needs. Called by EventModal2
# beside mark_fired, and by any test or dev-panel path that opens one.
func begin_event(ev: EventData2) -> void:
	_trade_offers.clear()
	_offered_potion = {}
	_offered_relic = &""
	_offered_card = {}
	_opening_loot.clear()
	if ev == null:
		return
	if _wants_trades(ev):
		_trade_offers = _roll_trades()
	if _wants(ev, "lose_potion"):
		_offered_potion = _roll_offered_potion()
	if _wants(ev, "lose_relic"):
		_offered_relic = _roll_offered_relic()
	_offered_card = _roll_offered_card(ev)
	_opening_loot = _roll_opening_loot(ev)


func _wants_trades(ev: EventData2) -> bool:
	for choice in ev.choices:
		if _trade_slot(choice) > 0:
			return true
	return false


# Does any choice on this event carry `type`? Read off the effects rather than
# authored anywhere, so an event that starts asking for a potion gets its roll
# without a second cell saying so.
func _wants(ev: EventData2, type: String) -> bool:
	for choice in ev.choices:
		if _has_effect(choice, type):
			return true
	return false


func _has_effect(choice: Dictionary, type: String) -> bool:
	for eff in choice.get("effects", []):
		if eff is Dictionary and String(eff.get("type", "")) == type:
			return true
	return false


# Which offer a choice is the button for — 1-based, 0 for a choice that trades
# nothing. Read off the effects rather than off the choice's position, so the
# sheet can order the rows however it likes and mix non-trade choices in among
# them.
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


# --- what the event will take off you ---------------------------------------
#
# Ranwid the Elder (docs/event-sheet-authoring.md §14) pays in relics for things
# out of your pack, and two of his three prices are a THING rather than a number:
# a potion, and a relic. Which one is the run's to say, not the sheet's — so it is
# rolled here when the event opens and held for as long as it is on screen, the
# same contract the trader's pairing has and for the same reason: the button
# names what it is about to take, and it must still mean that bottle when it is
# pressed.

# One bottle out of the pack, whatever it is. Straight random: an unidentified
# potion is as good a gift as a known one, and nothing here knows which of the
# two the player would rather keep.
func _roll_offered_potion() -> Dictionary:
	var held: Array = GameState.loot_potions()
	if held.is_empty():
		return {}
	return held[_roll_rng().randi_range(0, held.size() - 1)]


# One relic out of the pack, drawn from the ROLLABLE ones only — the same
# is_rollable() line the trader draws: a starter, a Boss relic and an Event relic
# are the three classes nothing may take off you, and an old man's appetite is
# not the exception.
func _roll_offered_relic() -> StringName:
	var mine: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.is_rollable():
			mine.append(it.id)
	if mine.is_empty():
		return &""
	return StringName(mine[_roll_rng().randi_range(0, mine.size() - 1)])


# --- what the event is offering before it asks anything ---------------------
#
# `EventData2.opens_with` (§15) — the Potion Lab's bench. The pieces are rolled
# here rather than granted: nothing has entered the pack, and nothing will until
# the player drags one in. What draws them is EventModal2, which embeds the same
# drop table every other payout uses.
func _roll_opening_loot(ev: EventData2) -> Array:
	var opens: Dictionary = ev.opens_with
	if opens.is_empty() or String(opens.get("type", "")) != "offer_loot":
		return []
	var kind: String = String(opens.get("kind", "loot"))
	var out: Array = []
	for _i in range(maxi(1, int(opens.get("value", 1)))):
		var entry: Dictionary = GameState.roll_loot_entry(kind)
		if not entry.is_empty():
			out.append(entry)
	return out


func opening_loot() -> Array:
	return _opening_loot


# The curse behind `add_curse random` (§16). PERMANENT CURSES ARE NOT IN THE BAG,
# and that is the rule rather than the Golden Monkey's own exception: a permanent
# curse is a price something specific charges for something specific — Curse of
# the Bell is what the Calling Bell hangs on you — and a random roll that can land
# one turns every idle button in the game into a coin flip on the rest of the run.
# So "a random curse" means a curse with a clock on it, and a curse authored with
# `timer: 0` is opted out of every random draw by saying so.
#
# &"" when nothing qualifies, which the caller treats as "no curse" rather than
# reaching for a permanent one to fill the gap.
func roll_random_curse() -> StringName:
	var pool: Array = []
	for cd in Data.all_curses2():
		if cd is CurseData2 and cd.timer > 0:
			pool.append(cd.id)
	if pool.is_empty():
		return &""
	pool.sort_custom(func(a, b): return String(a) < String(b))
	return StringName(pool[_roll_rng().randi_range(0, pool.size() - 1)])


# One card out of the pack. `min_rarity` on the effect narrows the draw the way
# We Meet Again narrows it — Ranwid wants something worth studying, so a Common
# is not a card he will take — and an event that wants any card at all simply
# does not author it.
func _roll_offered_card(ev: EventData2) -> Dictionary:
	var want: Dictionary = _effect_of(ev, "lose_card")
	if want.is_empty():
		return {}
	var floor_rarity: String = String(want.get("min_rarity", ""))
	var held: Array = []
	for entry in GameState.loot_cards():
		if floor_rarity == "" or _rarity_at_least(entry, floor_rarity):
			held.append(entry)
	if held.is_empty():
		return {}
	return held[_roll_rng().randi_range(0, held.size() - 1)]


# Is this loot entry's rarity `floor_rarity` or better? Read off the ladder Data
# already ranks items and loot by, so "Uncommon+" means the same thing here as it
# does on a chest.
func _rarity_at_least(entry: Dictionary, floor_rarity: String) -> bool:
	var ladder: Array = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
	var have: int = ladder.find(String(entry.get("rarity", "Common")).capitalize())
	var want: int = ladder.find(floor_rarity.capitalize())
	return have >= want and have >= 0


# The first effect of `type` on any of this event's choices, or {} — how the
# offering finds out WHAT it has been asked to roll.
func _effect_of(ev: EventData2, type: String) -> Dictionary:
	for choice in ev.choices:
		for eff in choice.get("effects", []):
			if eff is Dictionary and String(eff.get("type", "")) == type:
				return eff
	return {}


func offered_card() -> Dictionary:
	return _offered_card


# Hand the rolled card over: it leaves the pack.
func take_offered_card() -> bool:
	if _offered_card.is_empty():
		return false
	for i in range(GameState.loot_items.size()):
		if is_same(GameState.loot_items[i], _offered_card):
			GameState.remove_loot_at(i)
			return true
	return false


func offered_potion() -> Dictionary:
	return _offered_potion


func offered_relic() -> StringName:
	return _offered_relic


# Hand the rolled potion over: it leaves the pack. False when there was nothing
# to hand over, which is what keeps the choice off the screen in the first place.
func take_offered_potion() -> bool:
	if _offered_potion.is_empty():
		return false
	for i in range(GameState.loot_items.size()):
		if is_same(GameState.loot_items[i], _offered_potion):
			GameState.remove_loot_at(i)
			return true
	return false


# And the rolled relic. Returns WHICH one went, so the payout in the same breath
# can avoid handing it straight back — see EffectSystem's `given_item`.
func take_offered_relic() -> StringName:
	if _offered_relic == &"":
		return &""
	for it in GameState.inventory:
		if it is ItemData and it.id == _offered_relic:
			GameState.remove_item(it)
			return _offered_relic
	return &""


# `<give>` / `<get>` / `<potion>` / `<relic>` filled in from what this event
# rolled. A line carrying none of them is returned untouched, so this is safe to
# run over every label, every cost line and every rung of prose.
func fill_name_holes(text: String, choice: Dictionary) -> String:
	if text == "":
		return text
	if text.contains(GIVE_HOLE) or text.contains(GET_HOLE):
		var offer: Dictionary = trade_offer(_trade_slot(choice))
		text = text.replace(GIVE_HOLE, _item_name(offer.get("give", &""))) \
			.replace(GET_HOLE, _item_name(offer.get("get", &"")))
	if text.contains(POTION_HOLE):
		text = text.replace(POTION_HOLE, offered_potion_name())
	if text.contains(RELIC_HOLE):
		text = text.replace(RELIC_HOLE, _item_name(_offered_relic))
	if text.contains(CARD_HOLE):
		text = text.replace(CARD_HOLE, offered_card_name())
	return text


# "a potion" and not "" for an unresolved hole, the same fallback `<give>` has:
# the Collection's event page draws these lines outside any run, where there is
# no pack to roll from, and the sentence still has to read.
func offered_potion_name() -> String:
	if _offered_potion.is_empty():
		return "a potion"
	return PotionSystem.display_name(_offered_potion)


# The card, face UP: it is in the pack, so it is itself. What Ranwid is asking
# for is a particular card, and a button that said "a card" would be hiding the
# one thing the choice turns on.
func offered_card_name() -> String:
	if _offered_card.is_empty():
		return "a card"
	return CardSystem.display_name(_offered_card)


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
	# Several clauses, ANDed. Only AND: an event is dealt when the run can afford
	# everything the event is ABOUT, and Ranwid's three buttons are three
	# different prices — a run short of any one of them would open him on a
	# shelf he cannot fill, which is the thing the Relic Trader's gate exists to
	# prevent one price at a time.
	if req.has("all"):
		for clause in req.get("all", []):
			if clause is Dictionary and not _compare_stat(clause):
				return false
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
		# The pack, not a counter: relics a stranger could actually take off you.
		# Starter, Boss and Event relics are excluded by the same is_rollable()
		# rule the trade itself uses, so the gate cannot pass on five relics none
		# of which he would touch.
		"relics": return GameState.tradeable_relic_count()
		# Bottles in the pack, whatever they are. No is_rollable() equivalent to
		# apply: every potion carried is a potion that can be handed over, and an
		# unidentified one is handed over exactly as readily as a known one.
		"potions": return GameState.loot_potions().size()
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
	# The same argument for a price paid in KIND: a button that says "Give a
	# potion" on a run holding none is a button that takes nothing and pays a
	# relic for it. The event's Requirement is what normally keeps that off the
	# screen; this is what holds once the pack changes underneath it.
	if _has_effect(choice, "lose_potion") and _offered_potion.is_empty():
		return false
	if _has_effect(choice, "lose_relic") and _offered_relic == &"":
		return false
	if _has_effect(choice, "lose_card") and _offered_card.is_empty():
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
	# A gate on the MACHINE rather than on the player (objects2.0 only). Asked of
	# ObjectSystem because only it knows which machine is being pressed — the
	# choice dict is shared by every copy of a machine on screen.
	if gate.has("flag"):
		return ObjectSystem.flag_passes(String(gate["flag"]))
	return _run_stat(String(gate.get("resource", ""))) >= int(gate.get("value", 0))


# Why a gate refuses, for the disabled button's label — "Jammed", "Full", "No
# Bombs". One implementation so the reason shown and the rule applied cannot
# drift, the same argument blockers_for makes for placement.
func gate_refusal(gate: Dictionary, picks: Dictionary) -> String:
	if _gate_passes(gate, picks):
		return ""
	if gate.has("flag"):
		return ObjectSystem.flag_refusal(String(gate["flag"]))
	if gate.has("resource"):
		var stat: String = String(gate["resource"])
		return "Needs %d %s" % [int(gate.get("value", 0)),
			String(GATE_STAT_NAMES.get(stat, stat.capitalize()))]
	return ""


# The first reason this choice is unavailable, or "" when it is available or
# when nothing has a reason worth printing.
func choice_refusal(choice: Dictionary, picks: Dictionary) -> String:
	for gate in choice.get("gates", []):
		var why: String = gate_refusal(gate, picks)
		if why != "":
			return why
	return ""


# --- how close a choice is to killing you -----------------------------------
#
# Some buttons cost Health, and one of them will eventually be the last one. The
# build's answer is NOT to disable it: the Blood Donation Machine is a
# push-your-luck machine, Abyssal Baths' Linger climbs until the prose tells you
# the next dip is fatal, and a greyed-out button would take the decision away
# from the player at exactly the moment it became interesting. So the button
# stays live and the WARNING does the work — the cost line reddens as the press
# gets closer to lethal, and says so outright when it is.
#
# The CERTAIN cost and the POSSIBLE one are two different questions and the
# player is owed both. What a press definitely spends is what reddens the cost
# line and what says "this will kill you"; what it COULD spend if every roll in
# it goes the wrong way is a separate, weaker claim — "this might kill you" —
# and it must never be dressed up as the first, or a warning that is usually
# wrong stops being read at all.

# The Health `effects` would take. `worst` folds in the payload of any `roll` in
# the list — the independent procs that might fire and might not — which is the
# whole difference between what a press costs and what it could cost.
func _health_from(effects: Array, taken: int, worst: bool) -> int:
	var total: int = 0
	for eff in effects:
		if not (eff is Dictionary):
			continue
		var resolved: Dictionary = _scaled(eff, taken)
		match String(resolved.get("type", "")):
			"lose_hp":
				# `non_lethal` costs are clamped to leave you at 1, so they can
				# never be the press that ends the run.
				if not bool(resolved.get("non_lethal", false)):
					total += int(resolved.get("value", 0))
			"lose_max_hp":
				# Only bites Health when the cap drops below what you are holding.
				total += maxi(0, GameState.hp - (GameState.max_hp
					- int(resolved.get("value", 0))))
			"chance":
				# A `roll`: fires or doesn't, so it is only ever part of the worst
				# case. Recursive, because its payload is an effect list like any
				# other and may carry a roll of its own.
				if worst:
					total += _health_from(resolved.get("effects", []), taken, worst)
	return maxi(0, total)


# The Health this press would definitely spend.
func health_cost(choice: Dictionary, taken: int) -> int:
	return _health_from(choice.get("effects", []), taken, false)


# The most Health this press could take if everything in it goes the wrong way:
# the certain cost, every `roll` firing, and the WORSE of the headline gamble's
# two branches — a two-sided `chance` pays one of them whatever happens, so the
# bad branch is a real outcome rather than an extra.
func possible_health_cost(choice: Dictionary, taken: int) -> int:
	var total: int = _health_from(choice.get("effects", []), taken, true)
	var chance: Dictionary = choice.get("chance", {})
	if not chance.is_empty():
		total += maxi(
			_health_from(chance.get("effects", []), taken, true),
			_health_from(chance.get("else_effects", []), taken, true))
	return total


# Would taking this press end the run?
func is_lethal(choice: Dictionary, taken: int) -> bool:
	var cost: int = health_cost(choice, taken)
	return cost > 0 and cost >= GameState.hp


# COULD taking this press end the run, without it being certain? False once it is
# certain — that is `is_lethal`'s answer and the two warnings must not both fire.
func is_possibly_lethal(choice: Dictionary, taken: int) -> bool:
	if is_lethal(choice, taken):
		return false
	var worst: int = possible_health_cost(choice, taken)
	return worst > 0 and worst >= GameState.hp


# Either way of dying, for the views: a button that can end the run is painted
# red whether the death is certain or only on the table. The distinction the
# player acts on is in the WORDS under it (will / might), not in the colour —
# two shades of red would be a difference nobody could read at a glance.
func is_deadly(choice: Dictionary, taken: int) -> bool:
	return is_lethal(choice, taken) or is_possibly_lethal(choice, taken)


# The warning under a costly button, or "" when there is nothing to warn about.
func lethal_warning(choice: Dictionary, taken: int) -> String:
	if is_lethal(choice, taken):
		return "☠  This will kill you."
	# A gamble that could take more Health than you are holding. `might`, said
	# plainly, because the press may also cost nothing at all — the odds are on
	# the cost line right above this.
	if is_possibly_lethal(choice, taken):
		return "☠  This might kill you."
	# AND NOTHING ELSE. There used to be a third line here — "⚠ You can die here —
	# this leaves you at N Health" — on any press that took you within one more of
	# the same press. It fired on most of the costly buttons in the game, which is
	# what made it worthless: a warning the player reads on every second event is
	# furniture, and it was drowning the two above it, which are the ones that mean
	# something. The number it was quoting is already on the cost line. Death now
	# announces itself once, on the press that can actually cause it, and asks
	# again when that press is clicked (the views' "Are you sure?").
	return ""


# How red the cost line runs. RED ONLY WHEN THE PRESS CAN END THE RUN — flat
# DANGER when death is certain, a shade off it when death is on the table, and
# the ordinary dim text for every other price however steep.
#
# It used to be a gradient, warming from TEXT_DIM as the Health left after the
# press ran down, on the theory that "how many more of these do I have in me" is
# a slope rather than a switch. It is, but the colour was answering a question
# the player had not asked: a -3 that leaves you at 7 is a normal event cost, and
# painting it half-red taught the player to read pink as "expensive" — which left
# the actual red, the one that means the run ends here, competing with it. Red
# means dead now, and nothing else does.
func danger_color(choice: Dictionary, taken: int) -> Color:
	if is_lethal(choice, taken):
		return UITheme.DANGER
	# A possible death reddens the line too — the gamble that could take it is
	# quoted on that same line — but stops short of the flat DANGER a certain one
	# gets, since it is a weaker claim.
	if is_possibly_lethal(choice, taken):
		return UITheme.DANGER.lerp(UITheme.TEXT_DIM, 0.25)
	return UITheme.TEXT_DIM


# --- the second press ------------------------------------------------------

# Above every modal that can draw a choice button (an event is 123, a machine's
# card 122, the choice modal 124), for the same reason LootTrash's confirmation
# has a layer of its own: the thing being asked about is itself a floating panel,
# and a question parented into it draws underneath it or gets freed by its next
# rebuild.
const CONFIRM_LAYER := 141

# "Are you sure?" in front of a press that can end the run.
#
# THE RED BUTTON IS THE WARNING AND THIS IS THE SAFETY CATCH. Events used to hedge
# in prose one press early — "⚠ You can die here" under anything that took you
# within one more of the same cost — which meant the game cried wolf on most of
# its own content and the player learned to scroll past the line that mattered.
# The trade is the other way round now: nothing is said until the press really can
# kill you, and then it is said twice — once in red on the button, once here, with
# a click needed to get past it. A death in this game is the run, and the run is
# hours of somebody actually playing real games; it is worth one extra click.
#
# `host` is the node the layer hangs off, `on_yes` the press itself. Returns true
# when the question was asked (so the caller knows to stop and wait), false when
# there was nothing to ask about and the caller should just go.
func confirm_deadly(host: Node, choice: Dictionary, taken: int, on_yes: Callable) -> bool:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return false
	if not is_deadly(choice, taken):
		return false
	# WILL or MIGHT, said the same way the button says it — a gamble that could
	# take the last of your Health is not the same claim as a cost that certainly
	# will, and the question the player is answering has to be the right one.
	var body: String = ""
	if is_lethal(choice, taken):
		body = ("%s costs %d Health and you are holding %d. Taking it ends the run."
			% [String(choice.get("text", "This")), health_cost(choice, taken), GameState.hp])
	else:
		body = ("%s can cost up to %d Health and you are holding %d. If it goes badly, the run ends here."
			% [String(choice.get("text", "This")), possible_health_cost(choice, taken), GameState.hp])
	var layer := CanvasLayer.new()
	layer.layer = CONFIRM_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var panel := ConfirmPanel.ask(layer, "Are you sure?", body, "Do it anyway", on_yes)
	panel.tree_exited.connect(func():
		if is_instance_valid(layer):
			layer.queue_free())
	return true


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
func resolve_choice(ev: Resource, choice: Dictionary, taken: int,
		ctx: Dictionary = {}) -> Dictionary:
	var words: Array = []

	for eff in choice.get("effects", []):
		EffectSystem.apply(_scaled(eff, taken), ctx)
	if String(choice.get("effects_text", "")) != "":
		words.append(fill_name_holes(_fill_holes(String(choice["effects_text"]), taken), choice))

	# The gamble. Rolled AFTER the certain costs, because that is the order the
	# player experiences: the acid burns whether or not there was a relic in there.
	#
	# Always Favour.HIGH — winning a gamble is the good side by construction, and
	# that stays true for a two-sided one: the Blood Donation Machine's burst pays
	# an Event relic where the loss pays a coin, so Luck making the machine MORE
	# likely to explode is Luck doing its job.
	var chance: Dictionary = choice.get("chance", {})
	var rolled: bool = not chance.is_empty()
	var won: bool = false
	if rolled:
		won = Stats.roll_chance(_roll_rng(), chance_percent(chance, taken), Stats.Favour.HIGH)
		var branch: String = "effects" if won else "else_effects"
		var branch_text: String = "effects_text" if won else "else_effects_text"
		for eff in chance.get(branch, []):
			EffectSystem.apply(_scaled(eff, taken), ctx)
		if String(chance.get(branch_text, "")) != "":
			words.append(_fill_holes(String(chance[branch_text]), taken))

	var goal: Dictionary = choice.get("goal", {})
	if not goal.is_empty():
		GameState.add_event_goal(ev.id, String(goal.get("condition", "")),
			int(goal.get("games", 1)), goal.get("effects", []),
			String(goal.get("effects_text", "")))
		words.append("Goal: %s" % goal.get("condition", ""))

	var curse: Dictionary = choice.get("curse", {})
	if not curse.is_empty():
		# `add_curse random` names no row: the curse is drawn HERE, when the
		# button is pressed, so the player finds out what they caught at the same
		# moment the monkey decides. What it says on the way out names it —
		# `words` is what the modal prints under the result.
		var cid := StringName(curse.get("curse", &""))
		if bool(curse.get("random", false)):
			cid = roll_random_curse()
			var caught: CurseData2 = Data.get_curse2(cid)
			if caught != null:
				words.append("%s: %s" % [caught.display_name, caught.describe()])
		if cid != &"":
			GameState.add_curse_goal(cid, ev.id, int(curse.get("games", 0)))

	# A gamble's prose comes from the EVENT, because it depends on the roll rather
	# than on which button produced it — Scrap Ooze's two reaches print the same
	# two strings. The choice's own `results` rung still stands in when the event
	# left them blank, so a gamble is authorable without them.
	var result: String = fill_name_holes(result_for(choice, taken), choice)
	if rolled:
		var prose: String = String(ev.chance_won if won else ev.chance_lost)
		if prose != "":
			result = prose
	# `{ITEM}` names whichever relic a `gain_item_of` actually rolled — the Blood
	# Donation Machine says "the machine exploded, and X appeared" and only the
	# roll knows what X was. Substituted rather than run through _fill_holes,
	# which evaluates its holes as arithmetic and would print this one as 0.
	if result.contains(ITEM_HOLE):
		result = result.replace(ITEM_HOLE, String(ctx.get("granted_item_name", "something")))

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


# The odds AS AUTHORED on THIS press, with the {expr} hole resolved against how
# often the choice has been taken and clamped to a real percentage — an unbounded
# ladder like Scrap Ooze's 25, 35, 45… runs past 100 if you keep reaching.
#
# Float, because one-in-fifteen is 6.7% and rounding it on the way in would make
# the machine roll something other than what it says.
func chance_percent(chance: Dictionary, taken: int) -> float:
	return clampf(float(_scaled(chance, taken).get("percent", 0.0)), 0.0, 100.0)


# The odds the roll will ACTUALLY use — chance_percent put through the player's
# Luck. This is what a button quotes; chance_percent is what the sheet said.
func chance_odds(chance: Dictionary, taken: int) -> float:
	return Stats.effective_chance(chance_percent(chance, taken), Stats.Favour.HIGH)


# A percentage with no trailing noise: "6.7", "25", never "6.70" or "25.0".
static func percent_text(value: float) -> String:
	return String.num(snappedf(value, 0.1), 1).trim_suffix(".0")


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
		var value: float = _evaluate(String(scaled[field]), taken)
		# Percentages stay FLOAT; every other amount is a count of things and
		# rounds. `lose_hp 4.5` is not a cost anyone can pay, but 6.7% is an odds
		# and rounding it would make the roll disagree with the button.
		out[field] = value if String(field) == "percent" else int(round(value))
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
# How long an objective an event hands over stays live, as the clause that goes
# at the END of the line describing it. It reads as a clock rather than as part
# of the objective's name, which is what it is: "Injury: if you skip a night's
# sleep, take 2 damage · Lasts 3 games" is one sentence about a thing plus how
# long you have it for. Anything under a game is PERMANENT — the -1 sentinel
# GameState.add_curse_goal stores for a curse with no timer.
func lasts_text(games: int) -> String:
	if games < 1:
		return " · Permanent"
	return " · Lasts %d %s" % [games, "game" if games == 1 else "games"]


# Does this choice actually DO anything? A choice with no objective, no gamble,
# no errand and nothing but `none` in its effects is a door: the Arcade Room's
# `Leave`, and every exit authored like it.
#
# It matters because such a choice has no outcome to read, and a modal that
# stops to show you one is asking for a second press to tell you nothing. Judged
# on the effects rather than on the words beside them, because the words are the
# generator's rendering of the effects — "Nothing" is what it writes for a `none`.
func does_nothing(choice: Dictionary) -> bool:
	if not (choice.get("goal", {}) as Dictionary).is_empty():
		return false
	if not (choice.get("curse", {}) as Dictionary).is_empty():
		return false
	if not (choice.get("play", {}) as Dictionary).is_empty():
		return false
	if not (choice.get("chance", {}) as Dictionary).is_empty():
		return false
	for eff in choice.get("effects", []):
		if eff is Dictionary and String(eff.get("type", "")) != "none":
			return false
	return true


func describe_choice(choice: Dictionary, taken: int) -> String:
	var parts: Array = []
	var text: String = String(choice.get("effects_text", ""))
	if text != "":
		parts.append(fill_name_holes(_fill_holes(text, taken), choice))

	var goal: Dictionary = choice.get("goal", {})
	if not goal.is_empty():
		# "Event Goal:" and not "Goal for 3 games:" — the label says WHAT KIND of
		# objective this is, which is the part that changes how it is read (an
		# event goal is a bonus you may miss, an enemy's is a debt). How long it
		# runs for goes where every other clock on this line goes: the end.
		parts.append("Event Goal: %s → %s%s" % [
			goal.get("condition", ""), goal.get("effects_text", ""),
			lasts_text(int(goal.get("games", 1)))])

	var curse: Dictionary = choice.get("curse", {})
	if not curse.is_empty():
		# A RANDOM curse cannot be named before it is rolled, and must not be:
		# naming one on the button would be the button lying about which. What
		# the player is owed is the shape of the bargain — that a curse is coming
		# and that it has a clock on it, which every curse in the bag does.
		if bool(curse.get("random", false)):
			parts.append("+1 random Curse")
		var cd: CurseData2 = Data.get_curse2(StringName(curse.get("curse", &"")))
		if cd != null:
			var games: int = int(curse.get("games", 0))
			if games <= 0:
				games = cd.timer
			# The curse is named — "Injury", "Poor Sleep" — rather than announced
			# as the category "Curse". The player is being handed a particular
			# thing, and the name is what the checklist will call it from here on.
			# 0 games here means the curse's own Timer is 0, which is PERMANENT —
			# the same -1 sentinel GameState.add_curse_goal will store.
			parts.append("%s: %s%s" % [cd.display_name, cd.describe(),
				lasts_text(games if games > 0 else -1)])

	var play: Dictionary = choice.get("play", {})
	if not play.is_empty():
		parts.append("Go play a %s game, then: %s"
			% [play.get("tag", ""), play.get("effects_text", "")])

	# "25%: +1 Small Chest" — the shape Slay the Spire's own option line uses, and
	# the odds for THIS press, since they climb with every failed one.
	#
	# The odds quoted are the ones LUCK WILL ACTUALLY ROLL, not the number on the
	# sheet: at 1 Luck the Blood Donation Machine's 6.7% burst really is 12.9%,
	# and a button that said 6.7% would be lying to a player who went and bought
	# a Clover for exactly this.
	#
	# A two-sided roll prints both, likely side first, which is the order the
	# player reads it in: "93.3%: +1 Gold · 6.7%: +Blood Bag or IV Bag".
	var chance: Dictionary = choice.get("chance", {})
	if not chance.is_empty():
		var odds: float = chance_odds(chance, taken)
		if String(chance.get("else_effects_text", "")) != "":
			parts.append("%s%%: %s" % [percent_text(100.0 - odds),
				_fill_holes(String(chance["else_effects_text"]), taken)])
		parts.append("%s%%: %s" % [percent_text(odds),
			_fill_holes(String(chance.get("effects_text", "")), taken)])

	return " · ".join(PackedStringArray(parts))


# Record that an event has run, so its `run_limit` closes it off for the run.
func mark_fired(ev: EventData2, game_id: StringName = &"") -> void:
	if ev == null:
		return
	GameState.events_fired[ev.id] = int(GameState.events_fired.get(ev.id, 0)) + 1
	# Into the bag, and remembered as the last draw so a reshuffle cannot open on
	# it. Marked when the event is SHOWN rather than when a choice is taken:
	# walking straight back out still counts as having seen it.
	GameState.events_seen[ev.id] = true
	GameState.last_event_id = ev.id
	# …and the node is spent, so this game pays no second event this run.
	if game_id != &"":
		GameState.event_nodes_fired[game_id] = true
