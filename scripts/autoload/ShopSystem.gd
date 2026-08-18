extends Node

# SHOPS (docs/games-first-redesign.md §14) — what the gold is for.
#
# A shop stands at each of the run's ten HUB games: the best-connected games on
# the route, which on the full catalog are the genre's landmarks (Slay the Spire,
# Vampire Survivors, Isaac, Hades, Balatro, Spelunky, FTL, NetHack, Dead Cells,
# Enter the Gungeon). Beating a hub's game opens its shop.
#
# The point of hanging them off the hubs specifically is that it gives ROUTING a
# second axis. Until now every step was measured against one question — does this
# take me closer to the Amulet — with events (docs/event-sheet-authoring.md)
# answering it for the dead ends. Hubs are the opposite shape of detour: they are
# the middle of the map rather than its edges, so a hub is rarely far off the
# road, and "swing through the big node" is a cheap, repeatable decision rather
# than a leaf's two-game round trip.
#
# THREE THINGS DEFINE THE SHAPE, and each is a deliberate answer to "what stops
# this being a second, slower version of the drops":
#
#   * The shelf PERSISTS. Stock is rolled once and kept for the whole run, so
#     buying one of three leaves two standing. Come back to that hub later and
#     you are shopping from the shelf you left, which is what makes a return trip
#     something you can plan — and what lets the game's card quote its remaining
#     stock before you commit to going (§14).
#   * REROLLING costs a SCRAMBLE, not gold. Scramble is the run's reroll verb
#     everywhere else (§4 — "re-draw the offering"), so a shelf of three items
#     you don't want is the same kind of problem as an offering of three games
#     you don't want, and it takes the same answer. Pricing it in gold instead
#     would have let a rich player grind the whole 21-item catalog at one hub.
#   * GOLD is scarce and small. A run earns 8-15 (GameLoop2.GOLD_PER_ENEMY /
#     GOLD_PER_BOSS) against prices of 3-6, so a shop is two-to-four purchases a
#     run in total, not per visit.
#
# THE SPLIT: this autoload is the LOGIC. The state — the frozen hub list and each
# shop's shelf — lives on GameState (run-scope, saved, reset), the same division
# EventSystem and ScrollSystem use.

# What a shop puts on the shelf. Three is the same number as the base offering
# (Overworld2.BASE_OFFER_COUNT), which is not a coincidence worth breaking: a
# player reads a shop the way they read the offering, and one Scramble redraws
# either.
const STOCK_SLOTS := 3

# Price = BASE_PRICE + the rarity's rung on ItemData.Rarity, so Common 3,
# Uncommon 4, Rare 5, Legendary 6. The ladder is flat by one for a reason — the
# whole run's income is around a dozen gold, so a Legendary at double a Common
# would be most of a run and would read as unbuyable rather than as expensive.
# This is also the third thing that wanted the EPIC rung gone from ItemData.Rarity
# (see the enum): a hole in the ladder would have put a hole in the prices.
const BASE_PRICE := 3

# Rerolling the shelf, in Scramble charges.
const REROLL_COST := 1

# Stock rolls are seeded off the run and the hub rather than drawn live, so a
# save reloaded mid-shop puts the same three things back on the shelf.
const _STOCK_SALT := "shop-stock"

# A shop's shelf changed — bought from, or rerolled. The modal and the header
# repaint off this rather than polling.
signal shop_changed(game_id: StringName)


# ---------------------------------------------------------------------------
# Hubs
# ---------------------------------------------------------------------------

# The run's hub games, frozen on first ask (see GameState.hub_games for why it is
# frozen rather than re-derived). Ordered biggest-first, so callers that want
# "the biggest one" can take the head.
func hub_games() -> Array[StringName]:
	if GameState.hub_games.is_empty():
		GameState.hub_games = RunGraph.hub_ids()
	return GameState.hub_games


func is_hub(game_id: StringName) -> bool:
	return game_id != &"" and hub_games().has(game_id)


# ---------------------------------------------------------------------------
# Prices
# ---------------------------------------------------------------------------

func price_for(rarity: int) -> int:
	return BASE_PRICE + clampi(rarity, 0, ItemData.Rarity.LEGENDARY)


func price_of(entry: Dictionary) -> int:
	return int(entry.get("price", BASE_PRICE))


# ---------------------------------------------------------------------------
# The shelf
# ---------------------------------------------------------------------------

# This hub's shop, rolling its stock if this is the first time anyone has asked.
# Returns {} for a game with no shop, so callers can use it as the test.
func shop_for(game_id: StringName) -> Dictionary:
	if not is_hub(game_id):
		return {}
	if not GameState.shops.has(game_id):
		GameState.shops[game_id] = {
			"stock": _roll_stock(game_id, 0),
			"rerolls": 0,
			"seen": false,
		}
	return GameState.shops[game_id]


# The shop as it STANDS, without rolling one into existence. This is what the
# offering's card asks: drawing a card must not decide what is in a shop the
# player has not walked into yet, exactly as EventSystem refuses to roll an
# event when a card is drawn.
func peek(game_id: StringName) -> Dictionary:
	return GameState.shops.get(game_id, {})


# Whether the player has actually stood in this shop. Until they have, the card's
# popup says a shop is here and nothing more — the stock is a discovery the first
# visit is for (§14).
func has_seen(game_id: StringName) -> bool:
	return bool(peek(game_id).get("seen", false))


func mark_seen(game_id: StringName) -> void:
	var shop: Dictionary = shop_for(game_id)
	if shop.is_empty() or bool(shop.get("seen", false)):
		return
	shop["seen"] = true
	# Lord's Parasol resolves HERE — the moment the player stands in the shop for
	# the first time — because "when encountering a shop" is a moment, and this is
	# the only place that moment is recorded. Behind the `seen` guard, so a second
	# visit to a hub does not re-sweep a shelf that was rerolled since.
	sweep(game_id)


# Lord's Parasol (§8, Boss): take the whole shelf, no gold spent. Returns what was
# taken, empty when nothing owned sweeps or the shelf was already bare.
#
# FREE, not "buy everything you can afford". A boss relic whose payout is capped
# by the purse would be at its weakest exactly when the shelf is at its best, and
# the whole point of the thing is walking out with the shop.
func sweep(game_id: StringName) -> Array:
	var taken: Array = []
	if not GameState.sweeps_shops():
		return taken
	for entry in remaining(game_id):
		var template: ItemData = Data.get_item2(StringName(entry.get("item", &"")))
		if template == null:
			continue
		entry["sold"] = true
		# add_item, exactly as `buy` does: a Pickup swept off the shelf has to land
		# the same way one paid for does.
		GameState.add_item(template)
		taken.append(template)
		GameLog.add("Lord's Parasol takes %s off the shelf." % template.display_name,
			UITheme.COIN_GOLD)
	if not taken.is_empty():
		Notifications.notify("Lord's Parasol empties the shop — %d item%s."
			% [taken.size(), "" if taken.size() == 1 else "s"], UITheme.SHOP_GREEN)
		shop_changed.emit(game_id)
	return taken


# Everything on the shelf, sold slots included — the modal draws those greyed so
# the shelf doesn't reflow under a purchase.
func stock(game_id: StringName) -> Array:
	return peek(game_id).get("stock", [])


# Only what is still buyable. What the card's popup quotes.
func remaining(game_id: StringName) -> Array:
	var out: Array = []
	for entry in stock(game_id):
		if not bool(entry.get("sold", false)):
			out.append(entry)
	return out


func is_sold_out(game_id: StringName) -> bool:
	return not stock(game_id).is_empty() and remaining(game_id).is_empty()


# ---------------------------------------------------------------------------
# Buying
# ---------------------------------------------------------------------------

func can_afford(entry: Dictionary) -> bool:
	return GameState.gold >= price_of(entry)


# Buy slot `slot` at `game_id`. Returns the item the player now owns, or null if
# the purchase couldn't happen (no shop, bad slot, already sold, can't afford).
# Every one of those is checked here rather than trusted from the UI: the modal
# disables what it can, but a purchase is gold leaving the run and the state
# it's spent against has to be the state that's checked.
func buy(game_id: StringName, slot: int) -> ItemData:
	var shop: Dictionary = shop_for(game_id)
	if shop.is_empty():
		return null
	var shelf: Array = shop.get("stock", [])
	if slot < 0 or slot >= shelf.size():
		return null
	var entry: Dictionary = shelf[slot]
	if bool(entry.get("sold", false)) or not can_afford(entry):
		return null
	var template: ItemData = Data.get_item2(StringName(entry.get("item", &"")))
	if template == null:
		return null
	var price: int = price_of(entry)
	# spend_gold, not change_gold: this is the player CHOOSING to pay, which is
	# what Keeper's Sack counts (GameState.spend_gold).
	GameState.spend_gold(price)
	entry["sold"] = true
	# add_item duplicates the template and fires item_acquired, so a Pickup bought
	# from a shop lands exactly as one taken off a corpse.
	var owned: ItemData = GameState.add_item(template)
	GameLog.add("Bought %s for %d gold." % [template.display_name, price],
		Color(1.0, 0.84, 0.4))
	shop_changed.emit(game_id)
	return owned


# ---------------------------------------------------------------------------
# Rerolling
# ---------------------------------------------------------------------------

func can_reroll(game_id: StringName) -> bool:
	return not shop_for(game_id).is_empty() and GameState.scramble >= REROLL_COST


# Spend a Scramble and redraw the whole shelf — SOLD SLOTS INCLUDED. Refilling
# what you bought is the generous reading, and it is the right one: gold is the
# real limiter here (three fresh items you cannot afford is not a reward), and
# Scramble is scarce enough that this is not a faucet. It also means a reroll
# does the same thing to a shop that a Scramble does to the offering — replaces
# what is in front of you, wholesale — rather than being a different verb wearing
# the same name.
func reroll(game_id: StringName) -> bool:
	if not can_reroll(game_id):
		return false
	var shop: Dictionary = shop_for(game_id)
	GameState.scramble -= REROLL_COST
	shop["rerolls"] = int(shop.get("rerolls", 0)) + 1
	shop["stock"] = _roll_stock(game_id, int(shop["rerolls"]))
	GameState.emit_signal("stats_changed")
	GameLog.add("Rerolled the shop — %d Scramble left." % GameState.scramble,
		Color(0.6, 0.75, 1.0))
	shop_changed.emit(game_id)
	return true


# ---------------------------------------------------------------------------
# Saying it in words
#
# THE ONE PLACE a shop's state becomes prose. The card's flag tooltip and the
# game popup's shop block both come through here, on the same principle
# StatusData.tooltip_for exists for (§13.3): two views of one thing that write
# their own copy will eventually disagree about it, and the player will believe
# whichever one is wrong.
# ---------------------------------------------------------------------------

# The headline: what this shop is, in one line, phrased for where the player is.
# Before they have stood in it, that is deliberately only that a shop is here —
# the stock is what the first visit is FOR (§14).
func headline(game_id: StringName) -> String:
	if not is_hub(game_id):
		return ""
	if not has_seen(game_id):
		return "A shop stands here. Beat this game and it opens."
	var left: int = remaining(game_id).size()
	if left == 0:
		return "You cleared this shop out. A Scramble would restock it."
	return "You left %d item%s on this shelf." % [left, "" if left == 1 else "s"]


# The remaining stock, one "Name — Rarity · N gold" line each. Empty until the
# player has been, so a card can never quote a shelf they haven't seen.
func stock_lines(game_id: StringName) -> Array:
	var out: Array = []
	if not has_seen(game_id):
		return out
	for entry in remaining(game_id):
		var item: ItemData = Data.get_item2(StringName(entry.get("item", &"")))
		if item == null:
			continue
		out.append("%s — %s · %d gold" % [
			item.display_name, UITheme.rarity_name(int(item.rarity)), price_of(entry)])
	return out


# ---------------------------------------------------------------------------
# Rolling the stock
# ---------------------------------------------------------------------------

# STOCK_SLOTS items, each rolled on the game's standard rarity ladder
# (Data.roll_item_rarity — 75/20/5 with a 10% bump off the top), seeded off the
# run + hub + reroll number so the same shelf comes back after a reload.
#
# Two preferences shape the draw, both aimed at the same problem: 21 authored
# items against a run that already gets one free per defeated enemy.
#   * No duplicate slots — three of the same item is not a choice.
#   * Items the player does NOT already own are preferred, so a shop shows you
#     something new rather than selling you a second Anchor.
# Both are PREFERENCES, not filters: when the catalog can't satisfy them the draw
# still fills the shelf. A shop with two slots because the pool was thin would
# read as a bug, and the fallback is invisible.
func _roll_stock(game_id: StringName, reroll_index: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d|%d" % [
		_STOCK_SALT, String(game_id), GameState.run_seed, reroll_index])
	var out: Array = []
	var taken: Dictionary = {}
	for i in range(STOCK_SLOTS):
		var item: ItemData = _draw_one(rng, taken)
		if item == null:
			continue
		taken[item.id] = true
		out.append({
			"item": String(item.id),
			"price": price_for(int(item.rarity)),
			"sold": false,
		})
	return out


# What an item in the `shop` pool counts for when a shelf is drawn. Two, so a
# relic authored as a shop item is twice as likely to be standing at a hub as
# anything else of its rarity (Piggy Bank, There's Options).
#
# A WEIGHT AND NOT A FILTER, deliberately. Isaac's shop pool is a separate table
# and nothing else reaches it; here the catalogue is 30 relics against a run that
# visits at most ten hubs, and a shop that could only ever stock two of them would
# be the same two every run. Doubling the weight says "this belongs in a shop"
# without saying "and nowhere else" — a shop item still drops off a body, and a
# shelf can still come up three ordinary relics.
const SHOP_POOL_WEIGHT := 2

# One item off the rarity ladder, skipping anything already on this shelf and
# preferring what the player doesn't own. Falls back a step at a time — unowned
# in the rolled rarity, then anything in it, then the whole pool — so the only
# way this returns null is an empty catalog. Every step draws through the same
# shop-pool weighting.
func _draw_one(rng: RandomNumberGenerator, taken: Dictionary) -> ItemData:
	var rarity: int = Data.roll_item_rarity(rng)
	var bucket: Array = Data.reward_item2_pool_of(rarity)
	var fresh: Array = bucket.filter(func(it):
		return not taken.has(it.id) and not GameState.has_item(it.id))
	if not fresh.is_empty():
		return _weighted_pick(rng, fresh)
	var unheld: Array = bucket.filter(func(it): return not taken.has(it.id))
	if not unheld.is_empty():
		return _weighted_pick(rng, unheld)
	var whole: Array = Data.reward_item2_pool().filter(func(it): return not taken.has(it.id))
	if not whole.is_empty():
		return _weighted_pick(rng, whole)
	return null


# One item out of `pool`, with everything in the `shop` pool counting
# SHOP_POOL_WEIGHT times. Plain uniform when nothing in the pool is a shop item,
# which is the common case and costs one pass to establish.
func _weighted_pick(rng: RandomNumberGenerator, pool: Array) -> ItemData:
	var total: int = 0
	for it in pool:
		total += SHOP_POOL_WEIGHT if (it as ItemData).in_pool(&"shop") else 1
	if total <= pool.size():
		return pool[rng.randi() % pool.size()]
	var roll: int = rng.randi() % total
	for it in pool:
		roll -= SHOP_POOL_WEIGHT if (it as ItemData).in_pool(&"shop") else 1
		if roll < 0:
			return it
	return pool[pool.size() - 1]
