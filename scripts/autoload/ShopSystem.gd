extends Node

# SHOPS (docs/games-first-redesign.md §14, §19.1) — what the gold is for.
#
# A shop stands at every SHOP NODE: one of §19's four node kinds, dealt across
# the map at run start (10% of it) and frozen there, so a card's `$` can never
# become a lie. Beating the game on one opens its shelf under the board.
#
# It used to stand at the run's ten HUB games instead — the ten best-connected,
# the genre's landmarks — and §19.7 retired that. The hubs gave routing a second
# axis, but a fixed ten on a fixed map meant the same ten shops every run; the
# kinds give the same axis with a road that is different each time, and §19.3
# guarantees one on every start's route.
#
# THE SHOP BELONGS TO THE NODE, not to the game played there (§19.2). Every
# function here takes a NODE id — the map spot — so a transmuted Shop node plays
# a different game and still sells from the shelf it had. That is the opposite of
# the hub rule, which read the game played and let the shop leave with it.
#
# THREE THINGS DEFINE THE SHAPE, and each is a deliberate answer to "what stops
# this being a second, slower version of the drops":
#
#   * The shelf PERSISTS. Stock is rolled once and kept for the whole run, so
#     buying one of three leaves two standing. Come back to that node later and
#     you are shopping from the shelf you left, which is what makes a return trip
#     something you can plan — and what lets the game's card quote its remaining
#     stock before you commit to going (§14).
#   * REROLLING costs a SCRAMBLE, not gold. Scramble is the run's reroll verb
#     everywhere else (§4 — "re-draw the offering"), so a shelf of three items
#     you don't want is the same kind of problem as an offering of three games
#     you don't want, and it takes the same answer. Pricing it in gold instead
#     would have let a rich player grind the whole 21-item catalog at one shop.
#   * GOLD is scarce and small. A run earns 8-15 (GameLoop2.GOLD_PER_ENEMY /
#     GOLD_PER_BOSS) against prices of 3-9, so a shop is two-to-four purchases a
#     run in total, not per visit.
#
# THE SPLIT: this autoload is the LOGIC. The state — each shop's shelf — lives on
# GameState, and where the shops ARE is GameState.node_kinds (run-scope, saved, reset), the same division
# EventSystem and ScrollSystem use.

# What a shop puts on the shelf. Three is the same number as the base offering
# (Overworld2.BASE_OFFER_COUNT), which is not a coincidence worth breaking: a
# player reads a shop the way they read the offering, and one Scramble redraws
# either.
const STOCK_SLOTS := 3

# …AND THREE PIECES OF LOOT BESIDE THEM (docs/games-first-redesign.md §14). The
# loot kinds grew to eight, and a shop that only ever sold relics was a shop with
# nothing to say about most of what a run carries. Each is rolled exactly as a drop
# is (GameState.roll_loot_entry — the same kind weights, the same Identify tenth),
# so an unidentified potion on the shelf is as unknown as one off a body: the shelf
# draws it through LootSystem, which masks it.
const LOOT_SLOTS := 3

# A PIECE OF LOOT COSTS TWO LESS than a relic of its rarity: Common 1, Uncommon 3,
# Rare 5, Legendary 7. Loot is spent or kept in a slot, a relic is kept for free —
# so the same rarity is worth less as loot.
const LOOT_DISCOUNT := 2

# Price = BASE_PRICE + PRICE_PER_RUNG x the rarity's rung on ItemData.Rarity, so
# Common 3, Uncommon 5, Rare 7, Legendary 9. The ladder was +1 a rung (3-6) while
# a run earned about a dozen gold; Enemies nodes stand two bodies and Fractures
# stand more, so a run earns more than the ladder was set against, and the owner
# widened the steps to two (17 October 2026). Common stays at 3, so the 3-gold
# starting purse still buys one Common item at Fracture 0. This is also the third
# thing that wanted the EPIC rung gone from ItemData.Rarity (see the enum): a hole
# in the ladder would have put a hole in the prices.
const BASE_PRICE := 3
const PRICE_PER_RUNG := 2

# Rerolling the shelf, in Scramble charges.
const REROLL_COST := 1

# Stock rolls are seeded off the run and the node rather than drawn live, so a
# save reloaded mid-shop puts the same three things back on the shelf.
const _STOCK_SALT := "shop-stock"

# A shop's shelf changed — bought from, or rerolled. The modal and the header
# repaint off this rather than polling.
signal shop_changed(game_id: StringName)


# ---------------------------------------------------------------------------
# Where the shops are
# ---------------------------------------------------------------------------

# Whether a shop stands at this NODE: its kind is Shop (§19.1). Read off the map
# spot, never the game played there — see the header.
func is_shop(node_id: StringName) -> bool:
	return node_id != &"" and GameState.node_kinds.has(node_id) \
		and GameState.node_kind(node_id) == RunGraph.NodeKind.SHOP


# Every Shop node on the map, in a stable order (the kinds are a Dictionary, and
# a teleport drawing from its key order would ride insertion order).
func shop_nodes() -> Array[StringName]:
	var out: Array[StringName] = []
	for gid in GameState.node_kinds.keys():
		if int(GameState.node_kinds[gid]) == RunGraph.NodeKind.SHOP:
			out.append(StringName(gid))
	# By NAME. A bare sort() on StringNames orders them by where they were
	# interned, which depends on what the process happened to touch first — the
	# same two ids came back in either order depending on which tests had run.
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


# ---------------------------------------------------------------------------
# Who keeps it (§14.6)
# ---------------------------------------------------------------------------
#
# Every Shop node is dealt one keeper from Data.all_shopkeepers(), at random and
# per run: the roster is shuffled off the run's seed and handed out across the Shop
# nodes in their stable order, so no keeper stands at two shops until every one is
# standing somewhere, and the same seed deals the same keepers. With no roster
# every shop is the plain one, keeper null, and nothing below changes a thing.

# The deal for the run in progress, node -> keeper id, and the seed it was made
# for. Rebuilt whenever the seed or the roster moves; never saved, because a
# shelf pins its keeper the moment it is rolled (shop_for) and that IS saved.
var _deal: Dictionary = {}
var _deal_key: String = ""

# The keeper standing at this node: the one pinned on its shelf once it has one,
# else the one the deal hands it. null for a plain shop or a node with no shop.
func keeper_for(node_id: StringName) -> ShopkeeperData:
	if not is_shop(node_id):
		return null
	# A shelf that exists answers for itself — including one saved before keepers
	# were dealt, which was rolled plain and stays plain.
	if not peek(node_id).is_empty():
		return keeper_at(node_id)
	var id: String = String(_dealt().get(node_id, ""))
	return Data.get_shopkeeper(StringName(id)) if id != "" else null

# keeper_for without the is_shop gate, for the rolls inside shop_for — the shelf
# exists by then, so the pinned keeper is the one asked.
func keeper_at(node_id: StringName) -> ShopkeeperData:
	var id: String = String(peek(node_id).get("keeper", ""))
	return Data.get_shopkeeper(StringName(id)) if id != "" else null

# Whether this node's keeper carries the rule token `token` (the sheet's Effect
# column). The hook a keeper rule asks once it is built; nothing asks yet.
func keeper_has(node_id: StringName, token: String) -> bool:
	var keeper: ShopkeeperData = keeper_for(node_id)
	return keeper != null and keeper.effect.has(token.to_lower())

# The number a keeper's rule carries (`steal 3` -> 3), or 0 without the rule.
func keeper_number(node_id: StringName, token: String) -> int:
	var keeper: ShopkeeperData = keeper_for(node_id)
	if keeper == null:
		return 0
	for e in keeper.effect:
		var parts: PackedStringArray = String(e).split(" ", false)
		if parts.size() == 2 and parts[0] == token:
			return int(parts[1])
	return 0

func _dealt() -> Dictionary:
	var roster: Array = Data.all_shopkeepers()
	var nodes: Array[StringName] = shop_nodes()
	# The roster by ID, not by count: the same number of different keepers is a
	# different deal.
	var key: String = "%d|%s|%s" % [GameState.run_seed,
		",".join(roster.map(func(k): return String(k.id))), ",".join(nodes)]
	if key == _deal_key:
		return _deal
	_deal_key = key
	_deal = {}
	if roster.is_empty():
		return _deal
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [_KEEPER_SALT, GameState.run_seed])
	var deck: Array = []
	for node in nodes:
		# Drawn WITHOUT replacement, weighted by rarity (Data.RARITY_WEIGHTS): more
		# Shop nodes than keepers refills the deck, so a keeper repeats only once
		# every keeper has had a shop.
		if deck.is_empty():
			deck = roster.duplicate()
		var total: float = 0.0
		for k in deck:
			total += _keeper_weight(k)
		var roll: float = rng.randf() * total
		var pick: int = deck.size() - 1
		for i in range(deck.size()):
			roll -= _keeper_weight(deck[i])
			if roll < 0.0:
				pick = i
				break
		_deal[node] = String((deck[pick] as ShopkeeperData).id)
		deck.remove_at(pick)
	return _deal

func _keeper_weight(k: ShopkeeperData) -> float:
	return float(Data.RARITY_WEIGHTS[rarity_rung(k.rarity)])

const _KEEPER_SALT := "shop-keeper"


# ---------------------------------------------------------------------------
# Prices
# ---------------------------------------------------------------------------

# What a relic of `rarity` costs on a shelf rolled now: the ladder, plus a
# Fracture's surcharge (docs/fracture-design.md §3). A shopkeeper's sale is applied
# on top of this by the shelf, not here, so this stays "the going rate".
func price_for(rarity: int) -> int:
	return BASE_PRICE + PRICE_PER_RUNG * clampi(rarity, 0, ItemData.Rarity.LEGENDARY) \
		+ Fracture.shop_surcharge()


# What `entry` costs NOW: the price it was rolled at, times every run-wide cut
# (GameState.shop_price_cuts — Steam Sale, a beaten keeper), multiplied and
# rounded up. Applied here, at reading, because a cut can arrive after the shelf
# was rolled.
func price_of(entry: Dictionary) -> int:
	return discounted(int(entry.get("price", BASE_PRICE)))

# `price` after the run's cuts. Integer arithmetic, so 5 at -20% is 4 and not a
# float a hair over it rounded up to 5.
func discounted(price: int) -> int:
	var num: int = price
	var den: int = 1
	for pct in GameState.shop_price_cuts():
		num *= 100 - clampi(int(pct), 0, 100)
		den *= 100
	@warning_ignore("integer_division")
	return (num + den - 1) / den

# What a card pack costs, before a keeper's sale and the run's cuts.
const PACK_PRICE := 4
# How many cards a pack opens to; the player keeps one.
const PACK_CARDS := 3

# What a piece of loot of `rarity` ("Common".."Legendary") costs on a shelf.
func loot_price_for(rarity: String) -> int:
	return maxi(1, price_for(rarity_rung(rarity)) - LOOT_DISCOUNT)

# "Common".."Legendary" as a rung on ItemData.Rarity — loot carries its rarity as
# a word, items as the enum.
static func rarity_rung(rarity: String) -> int:
	return {"uncommon": 1, "rare": 2, "legendary": 3}.get(rarity.to_lower(), 0)


# ---------------------------------------------------------------------------
# The shelf
# ---------------------------------------------------------------------------

# This node's shop, rolling its stock if this is the first time anyone has asked.
# Returns {} for a game with no shop, so callers can use it as the test.
func shop_for(game_id: StringName) -> Dictionary:
	if not is_shop(game_id):
		return {}
	if not GameState.shops.has(game_id):
		# The keeper is PINNED on the shelf the moment it is rolled, so the deal
		# below can never hand this node a different one later in the run (a rift
		# or a reload re-dealing over a changed node list).
		var keeper: ShopkeeperData = keeper_for(game_id)
		GameState.shops[game_id] = {
			"keeper": String(keeper.id) if keeper != null else "",
			"rerolls": 0,
			"seen": false,
		}
		var counts: Vector2i = _slot_counts(keeper)
		GameState.shops[game_id]["stock"] = _roll_stock(game_id, 0, counts.x)
		GameState.shops[game_id]["loot"] = _roll_loot(game_id, counts.y, true)
		GameState.shops[game_id]["packs"] = _roll_packs(game_id,
			keeper.pack_slots if keeper != null else 0, true)
	# A shelf saved before loot was sold gets its loot row the first time it is
	# asked for, rather than standing half-empty for the rest of that run.
	if not (GameState.shops[game_id] as Dictionary).has("loot"):
		GameState.shops[game_id]["loot"] = _roll_loot(game_id, LOOT_SLOTS, false)
	return GameState.shops[game_id]

# DONATION SHELF (§14.6): how many slots the profile's best Donation Machine bank
# had unlocked when this run started. Items take 1-2 of them (1 on the smallest),
# loot the rest.
const DONATION_TIERS := [[600, 6], [200, 5], [100, 4], [20, 3], [0, 2]]

func donation_slots(best: int) -> int:
	for tier in DONATION_TIERS:
		if best >= int(tier[0]):
			return int(tier[1])
	return 2

# (items, loot) a fresh shelf holds.
func _slot_counts(keeper: ShopkeeperData) -> Vector2i:
	if keeper == null:
		return Vector2i(STOCK_SLOTS, LOOT_SLOTS)
	if keeper.effect.has("donation_shelf"):
		var total: int = donation_slots(GameState.donation_best)
		var items: int = 1 if total <= 2 else 1 + randi() % 2
		return Vector2i(items, total - items)
	return Vector2i(keeper.item_slots, keeper.loot_slots)


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
	# visit to a shop does not re-sweep a shelf that was rerolled since.
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
	# The loot row too — "purchase everything in it" — as far as the pack has room.
	for row in remaining_loot(game_id):
		if GameState.take_loot_entry((row["entry"] as Dictionary).duplicate(true)):
			row["sold"] = true
			GameLog.add("Lord's Parasol takes %s off the shelf."
				% LootSystem.display_name(row["entry"]), UITheme.COIN_GOLD)
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
	return not (stock(game_id).is_empty() and loot_stock(game_id).is_empty()) \
		and remaining(game_id).is_empty() and remaining_loot(game_id).is_empty()

# The pack row, sold slots included: [{pack, price, sold, cards}].
func pack_stock(game_id: StringName) -> Array:
	return peek(game_id).get("packs", [])

func remaining_packs(game_id: StringName) -> Array:
	return pack_stock(game_id).filter(func(r): return not bool(r.get("sold", false)))

# The loot row, sold slots included: [{entry, price, sold}].
func loot_stock(game_id: StringName) -> Array:
	return peek(game_id).get("loot", [])

func remaining_loot(game_id: StringName) -> Array:
	return loot_stock(game_id).filter(func(r): return not bool(r.get("sold", false)))


# ---------------------------------------------------------------------------
# Buying
# ---------------------------------------------------------------------------

# Whether the player can pay for `entry` in what it is priced in. Health has to
# leave at least 1 behind: a shop is not a way to end the run.
func can_afford(entry: Dictionary) -> bool:
	if pays_in_health(entry):
		return GameState.hp > price_of(entry)
	return GameState.gold >= price_of(entry)

func pays_in_health(entry: Dictionary) -> bool:
	return String(entry.get("currency", "gold")) == "health"

# Take the price. spend_gold, not change_gold: this is the player CHOOSING to pay,
# which is what Keeper's Sack counts (GameState.spend_gold). Health goes through
# change_hp, so it is a Health loss like any other (Piggy Bank hears it).
func _pay(entry: Dictionary) -> void:
	if pays_in_health(entry):
		GameState.change_hp(-price_of(entry), "shop")
	else:
		GameState.spend_gold(price_of(entry))

# "5 gold" / "2 Health", for the log.
func price_words(entry: Dictionary) -> String:
	return "%d %s" % [price_of(entry), "Health" if pays_in_health(entry) else "gold"]


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
	_pay(entry)
	entry["sold"] = true
	# add_item duplicates the template and fires item_acquired, so a Pickup bought
	# from a shop lands exactly as one taken off a corpse.
	var owned: ItemData = GameState.add_item(template)
	GameLog.add("Bought %s for %s." % [template.display_name, price_words(entry)],
		Color(1.0, 0.84, 0.4))
	shop_changed.emit(game_id)
	return owned


# Buy loot slot `slot` at `game_id`. Returns the entry now in the pack, or {} when
# it could not happen — no shop, bad slot, sold, too dear, or NO ROOM: a piece you
# cannot carry is not charged for, and stays on the shelf.
func buy_loot(game_id: StringName, slot: int) -> Dictionary:
	var shop: Dictionary = shop_for(game_id)
	if shop.is_empty():
		return {}
	var row_list: Array = shop.get("loot", [])
	if slot < 0 or slot >= row_list.size():
		return {}
	var row: Dictionary = row_list[slot]
	if bool(row.get("sold", false)) or not can_afford(row):
		return {}
	var entry: Dictionary = (row["entry"] as Dictionary).duplicate(true)
	if not GameState.take_loot_entry(entry):
		return {}
	_pay(row)
	row["sold"] = true
	GameLog.add("Bought %s for %s." % [LootSystem.display_name(entry), price_words(row)],
		Color(1.0, 0.84, 0.4))
	shop_changed.emit(game_id)
	return entry

# ---------------------------------------------------------------------------
# Packs (§14.6)
# ---------------------------------------------------------------------------

# Buy pack `slot`: pay, and roll the cards inside (PACK_CARDS, rarities rolled as
# a drop's are). Returns them for the player to pick ONE of (take_pack_card). The
# cards are kept on the row until a pick is made, so a pack closed unopened still
# holds the same three. {} … [] when it could not happen: no shop, bad slot, sold,
# too dear, or no room in the pack for a card.
func buy_pack(game_id: StringName, slot: int) -> Array:
	var shop: Dictionary = shop_for(game_id)
	var rows: Array = shop.get("packs", [])
	if slot < 0 or slot >= rows.size():
		return []
	var row: Dictionary = rows[slot]
	if row.has("cards"):
		return row["cards"]
	if bool(row.get("sold", false)) or not can_afford(row):
		return []
	var cards: Array = []
	for _i in range(PACK_CARDS):
		var c: Dictionary = GameState.roll_loot_entry("card")
		if not c.is_empty():
			cards.append(c)
	if cards.is_empty() or not GameState.loot_fits(cards[0]):
		return []
	_pay(row)
	row["cards"] = cards
	GameLog.add("Bought a pack for %s." % price_words(row), Color(1.0, 0.84, 0.4))
	shop_changed.emit(game_id)
	return cards

# Take card `pick` out of opened pack `slot`; the other two are gone.
func take_pack_card(game_id: StringName, slot: int, pick: int) -> bool:
	var rows: Array = pack_stock(game_id)
	if slot < 0 or slot >= rows.size():
		return false
	var row: Dictionary = rows[slot]
	var cards: Array = row.get("cards", [])
	if pick < 0 or pick >= cards.size():
		return false
	if not GameState.take_loot_entry((cards[pick] as Dictionary).duplicate(true)):
		return false
	row.erase("cards")
	row["sold"] = true
	shop_changed.emit(game_id)
	return true


# ---------------------------------------------------------------------------
# Keeper actions (§14.6)
# ---------------------------------------------------------------------------

func can_steal(game_id: StringName) -> bool:
	return keeper_number(game_id, "steal") > 0 and not bool(shop_for(game_id).get("stolen", false))

# Charon: take `steal N` gold, once, and his boss walks onto the board. The shop
# stays open.
func steal(game_id: StringName) -> bool:
	if not can_steal(game_id):
		return false
	var keeper: ShopkeeperData = keeper_for(game_id)
	shop_for(game_id)["stolen"] = true
	GameState.change_gold(keeper_number(game_id, "steal"))
	var boss: GoalEnemyData = Data.get_boss(keeper.boss)
	if boss != null:
		GameLoop2.spawn_to_stack(boss)
	GameLog.add("Stole from %s." % keeper.display_name, UITheme.DANGER)
	shop_changed.emit(game_id)
	return true

func can_bomb(game_id: StringName) -> bool:
	return keeper_has(game_id, "bombable") and GameState.bombs >= 1 \
		and not bool(shop_for(game_id).get("bombed", false))

func is_bombed(game_id: StringName) -> bool:
	return bool(peek(game_id).get("bombed", false))

# Isaac's Shopkeeper, bombed (once a shop; he is gone after): 1% Steam Sale, and
# the rest split in thirds between nothing, 1-5 gold and a spider on the board.
# Returns what happened: "steam_sale", "gold", "spider" or "nothing".
func bomb(game_id: StringName) -> String:
	if not can_bomb(game_id):
		return ""
	GameState.bombs -= 1
	GameState.emit_signal("stats_changed")
	shop_for(game_id)["bombed"] = true
	var roll: int = randi() % 100
	var out: String = "nothing"
	if roll == 99:
		var sale: ItemData = Data.get_item2(STEAM_SALE)
		if sale != null:
			GameState.add_item(sale)
			out = "steam_sale"
	elif roll >= 66:
		var spider: GoalEnemyData = Data.get_goal_enemy(SPIDER)
		if spider != null:
			GameLoop2.spawn_to_stack(spider)
			out = "spider"
	elif roll >= 33:
		GameState.change_gold(1 + randi() % 5)
		out = "gold"
	shop_changed.emit(game_id)
	return out

const STEAM_SALE := &"steam_sale"
const SPIDER := &"spider"

# A keeper's boss beaten (Charon): that keeper's `beaten_sale` comes off every
# price for the rest of the run, once per keeper.
func _on_enemy_defeated(enemy, _cell) -> void:
	if not (enemy is GoalEnemyData):
		return
	for k in Data.all_shopkeepers():
		var keeper: ShopkeeperData = k
		if keeper.boss != (enemy as GoalEnemyData).id:
			continue
		for e in keeper.effect:
			var parts: PackedStringArray = String(e).split(" ", false)
			if parts.size() == 2 and parts[0] == "beaten_sale":
				if not GameState.shop_sales.has(String(keeper.id)):
					GameState.shop_sales[String(keeper.id)] = int(parts[1])
					Notifications.notify("Shops -%s%%" % parts[1], UITheme.SHOP_GREEN)

func _ready() -> void:
	GameLoop2.enemy_defeated.connect(_on_enemy_defeated)


# ---------------------------------------------------------------------------
# Rerolling
# ---------------------------------------------------------------------------

func can_reroll(game_id: StringName) -> bool:
	if shop_for(game_id).is_empty():
		return false
	if keeper_has(game_id, "gold_reroll"):
		return GameState.gold >= gold_reroll_cost(game_id)
	return GameState.scramble >= REROLL_COST

# A `gold_reroll` keeper's next reroll: 1 gold, +1 for each one already bought.
func gold_reroll_cost(game_id: StringName) -> int:
	return discounted(1 + int(peek(game_id).get("gold_rerolls", 0)))


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
	if keeper_has(game_id, "gold_reroll"):
		GameState.spend_gold(gold_reroll_cost(game_id))
		shop["gold_rerolls"] = int(shop.get("gold_rerolls", 0)) + 1
	else:
		GameState.scramble -= REROLL_COST
	shop["rerolls"] = int(shop.get("rerolls", 0)) + 1
	# EVERY ROW, each the size it was: a slot that was an item stays an item, a
	# loot slot stays loot (the donation shelf's split is kept, §14.6). A keeper's
	# chance sale is a first-roll thing and does not come back.
	shop["stock"] = _roll_stock(game_id, int(shop["rerolls"]), stock(game_id).size())
	shop["loot"] = _roll_loot(game_id, loot_stock(game_id).size(), false)
	# …except a pack already paid for and not yet picked from: it is the player's.
	var packs: Array = _roll_packs(game_id, pack_stock(game_id).size(), false)
	for i in range(mini(packs.size(), pack_stock(game_id).size())):
		if (pack_stock(game_id)[i] as Dictionary).has("cards"):
			packs[i] = pack_stock(game_id)[i]
	shop["packs"] = packs
	GameState.emit_signal("stats_changed")
	GameLog.add("Rerolled the shop.", Color(0.6, 0.75, 1.0))
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
	if not is_shop(game_id):
		return ""
	if not has_seen(game_id):
		return "A shop stands here. Beat this game and it opens."
	var left: int = remaining(game_id).size()
	left += remaining_loot(game_id).size() + remaining_packs(game_id).size()
	if left == 0:
		return "You cleared this shop out. A Scramble would restock it."
	return "You left %d thing%s on this shelf." % [left, "" if left == 1 else "s"]


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
		out.append("%s — %s · %s" % [
			item.display_name, UITheme.rarity_name(int(item.rarity)), price_words(entry)])
	# The loot row, in the words the pack uses — an unidentified piece by its mask.
	for row in remaining_loot(game_id):
		out.append("%s — %s · %s" % [LootSystem.display_name(row["entry"]),
			LootSystem.kind_name(row["entry"]), price_words(row)])
	return out


# ---------------------------------------------------------------------------
# Rolling the stock
# ---------------------------------------------------------------------------

# STOCK_SLOTS items, each rolled on the game's standard rarity ladder
# (Data.roll_item_rarity — 75/20/4/1), seeded off the
# run + node + reroll number so the same shelf comes back after a reload.
#
# Two preferences shape the draw, both aimed at the same problem: 21 authored
# items against a run that already gets one free per defeated enemy.
#   * No duplicate slots — three of the same item is not a choice.
#   * Items the player does NOT already own are preferred, so a shop shows you
#     something new rather than selling you a second Anchor.
# Both are PREFERENCES, not filters: when the catalog can't satisfy them the draw
# still fills the shelf. A shop with two slots because the pool was thin would
# read as a bug, and the fallback is invisible.
func _roll_stock(game_id: StringName, reroll_index: int, slots: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d|%d" % [
		_STOCK_SALT, String(game_id), GameState.run_seed, reroll_index])
	var keeper: ShopkeeperData = keeper_at(game_id)
	var pools: PackedStringArray = keeper.pools if keeper != null else PackedStringArray()
	var out: Array = []
	var taken: Dictionary = {}
	for i in range(slots):
		var item: ItemData = _draw_one(rng, taken, pools)
		if item == null:
			continue
		taken[item.id] = true
		out.append(_priced(keeper, {"item": String(item.id), "sold": false},
			price_for(int(item.rarity)), _item_marks(item), reroll_index == 0))
	return out


# LOOT_SLOTS pieces off the drop roll (GameState.roll_loot_entry), each with its
# price. Rolled live rather than seeded like the items: a piece carries run state
# (a pill's dose, a wand's charges, a weapon's uid), and the shelf is saved with the
# run, so a reload puts back what was rolled either way.
func _roll_loot(game_id: StringName, slots: int, first: bool) -> Array:
	var keeper: ShopkeeperData = keeper_at(game_id)
	var out: Array = []
	for _i in range(slots):
		var kind: String = "loot"
		if keeper != null and not keeper.loot_kinds.is_empty():
			kind = _pick_loot_kind(keeper.loot_kinds)
		var entry: Dictionary
		# A keeper's loot tag (Jimbo's jokers) is a card roll by tag; the generator
		# holds the tag to card-only keepers.
		if keeper != null and keeper.loot_tag != "" and kind == "card":
			entry = CardSystem.roll_card_loot(null, keeper.loot_tag)
		else:
			entry = GameState.roll_loot_entry(kind)
		if entry.is_empty():
			continue
		var rarity: String = String(entry.get("rarity", "Common"))
		out.append(_priced(keeper, {"entry": entry, "sold": false},
			loot_price_for(rarity),
			["loot", rarity.to_lower(), String(entry.get("type", ""))], first))
	return out

# `slots` card packs: PACK_PRICE each, art Pack1-4 at random. The cards inside are
# rolled when one is bought (buy_pack), so they are a surprise until then.
func _roll_packs(game_id: StringName, slots: int, first: bool) -> Array:
	var keeper: ShopkeeperData = keeper_at(game_id)
	var out: Array = []
	for _i in range(slots):
		out.append(_priced(keeper, {"pack": 1 + randi() % 4, "sold": false},
			PACK_PRICE + Fracture.shop_surcharge(), ["packs"], first))
	return out

# One of a keeper's loot kinds, weighted the way the drop roll weights them
# (GameState.loot_kind_weight), so a keeper of potions and bags still sells
# potions more often than bags.
func _pick_loot_kind(kinds: PackedStringArray) -> String:
	var total: int = 0
	for k in kinds:
		total += maxi(1, GameState.loot_kind_weight(k))
	var roll: int = randi() % maxi(1, total)
	for k in kinds:
		roll -= maxi(1, GameState.loot_kind_weight(k))
		if roll < 0:
			return k
	return kinds[0]

# The words a sale clause can name an item by: `items`, its rarity, its pools
# and its tags.
func _item_marks(item: ItemData) -> Array:
	var marks: Array = ["items", UITheme.rarity_name(int(item.rarity)).to_lower()]
	for p in item.pools:
		marks.append(String(p).to_lower())
	for t in item.tags:
		marks.append(String(t).to_lower())
	return marks

# `row` with its price and currency set: the going rate `base`, then each of the
# keeper's sale clauses whose target is `all` or one of `marks`, in order.
func _priced(keeper: ShopkeeperData, row: Dictionary, base: int, marks: Array,
		first: bool = true) -> Dictionary:
	row["price"] = sale_price(keeper, base, marks, first)
	if row["price"] < base:
		row["on_sale"] = true
	if keeper != null and keeper.pays_in_health():
		row["currency"] = "health"
	return row

# `first` is whether this is the shelf's first roll: a chance clause ("10% half")
# only ever rolls there.
func sale_price(keeper: ShopkeeperData, base: int, marks: Array, first: bool = true) -> int:
	var price: int = base
	if keeper == null:
		return price
	for clause in keeper.sale:
		var parts: PackedStringArray = String(clause).split(" ", false)
		if parts.is_empty():
			continue
		if parts[0].ends_with("%"):
			var chance: int = int(parts[0].trim_suffix("%"))
			parts.remove_at(0)
			if parts.is_empty() or not first or randi() % 100 >= chance:
				continue
		var target: String = parts[1] if parts.size() > 1 else "all"
		if target != "all" and not marks.has(target):
			continue
		match parts[0]:
			"free":
				price = 0
			"half":
				@warning_ignore("integer_division")
				price = (price + 1) / 2
			_:
				price += int(parts[0])
	return maxi(0, price)


# What an item in the `shop` pool counts for when a shelf is drawn. Two, so a
# relic authored as a shop item is twice as likely to be standing on a shelf as
# anything else of its rarity (Piggy Bank, There's Options).
#
# A WEIGHT AND NOT A FILTER, deliberately. Isaac's shop pool is a separate table
# and nothing else reaches it; here the catalogue is 30 relics against a run that
# visits a handful of shops, and a shop that could only ever stock two of them would
# be the same two every run. Doubling the weight says "this belongs in a shop"
# without saying "and nowhere else" — a shop item still drops off a body, and a
# shelf can still come up three ordinary relics.
const SHOP_POOL_WEIGHT := 2

# One item off the rarity ladder, skipping anything already on this shelf and
# preferring what the player doesn't own. Falls back a step at a time — unowned
# in the rolled rarity, then anything in it, then the whole pool — so the only
# way this returns null is an empty catalog. Every step draws through the same
# shop-pool weighting.
func _draw_one(rng: RandomNumberGenerator, taken: Dictionary,
		pools: PackedStringArray = PackedStringArray()) -> ItemData:
	var rarity: int = Data.roll_item_rarity(rng)
	# A KEEPER'S POOL (§14.6) narrows the catalog before anything else, and widens
	# back the same way the rarity does: the rolled rarity's matches, then every
	# rarity's, and only when no item in the game matches does the shelf fall back
	# to the ordinary draw below rather than stand empty.
	if not pools.is_empty():
		var matching: Array = Data.reward_item2_pool().filter(func(it):
			return not taken.has(it.id) and _matches_pool(it, pools))
		if not matching.is_empty():
			var in_rarity: Array = matching.filter(func(it): return int(it.rarity) == rarity)
			var unheld: Array = in_rarity.filter(func(it): return not GameState.has_item(it.id))
			for pick in [unheld, in_rarity, matching]:
				if not (pick as Array).is_empty():
					return _weighted_pick(rng, pick)
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


func _matches_pool(item: ItemData, pools: PackedStringArray) -> bool:
	for p in pools:
		if item.pools.has(p) or item.tags.has(p):
			return true
	return false


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
