class_name DealRooms
extends RefCounted

# DEVIL AND ANGEL DEALS (docs/deal-rooms-design.md; the owner, 21 Nov 2026) — The
# Binding of Isaac: Repentance's Devil and Angel Rooms, as two events, and
# Batsaac's mechanic of FINDING them the way Isaac does.
#
#   * ANY PLAYER can be dealt the Devil Room as a Rare event, after any game. The
#     Angel Room is never dealt by the bag: it is what the Devil Room's door turns
#     out to be, by Repentance's coin flips (`pick_kind`).
#   * BATSAAC (the `devil_and_angel_deals` mechanic) does not draw them from the
#     bag at all. After a CLEAN game — no enemy took any of his Health: a hit past
#     the Shields, or a status's charge — he rolls Isaac's deal chance (`chance`)
#     for a BONUS deal room, opened before the game's ordinary event. The clean
#     game is his alone: the owner took it off the events and the relics' roll
#     ("batsaac's mechanic already integrates getting hit").
#   * ANY OTHER PLAYER HOLDING A RELIC THAT RAISES THE CHANCE (Book of
#     Revelations, The Book of Belial) gets that much of it (the owner, 21 Nov
#     2026): rolled once a floor, after the game a difficulty up lands in, for a
#     bonus door of the same kind (`roll_item_bonus`). No clean-game gate.
#   * A room has 2-4 items, with 4 the rarest (Repentance's layout weights). Devil
#     items cost Max Health by rarity (2/4/6/8); Isaac's three-soul-heart price is
#     3 Shields when there is no Max Health left to pay with. Angel items are free,
#     and taking one makes the rest vanish.
#
# A FLOOR is one difficulty-up boss's band: it begins when that boss walks on
# (GameLoop2._land_capstone_boss) and its boss fight is the game the boss is
# beaten in. Champion bosses and the Emperor's are not floor bosses.
#
# The state is GameState.deals — run-scope, saved with the event bag, cleared by
# reset_run. These are the rules over it, the split HungerSystem has.

const MECHANIC := &"devil_and_angel_deals"
# The two events (the `events` sheet) and the two item pools (the items sheet's
# `pools` column) share their ids.
const DEVIL := &"devil_room"
const ANGEL := &"angel_room"
# The art the room shows once you are inside, in place of its door
# (images2.0/events/), and the small marks Batsaac's chance chip wears.
const STATUE_ART := {DEVIL: "DevilStatue", ANGEL: "AngelStatue"}
const ICON_ART := {DEVIL: "DevilRoomIcon", ANGEL: "AngelRoomIcon"}

# --- Repentance's Deal with the Devil chance (the wiki, Devil Room page) -------
const BASE_CHANCE := 1.0
# "Taking no (non-self) Red Heart damage against the boss."
const BOSS_CLEAN_BONUS := 35.0
# "Taking no (non-self) Red Heart damage for the entire floor."
const FLOOR_CLEAN_BONUS := 99.0
# "Previous Devil Room door seen less than two floors ago" / "two floors ago".
const SEEN_RECENTLY_MULT := 0.25
const SEEN_TWO_AGO_MULT := 0.5

# --- Repentance's Angel Room coin flips (the wiki, Angel Room page) ------------
# Each flip that lands makes the room an Angel Room; all failing is a Devil Room.
const ANGEL_BASE_FLIP := 50.0
# "Donating 10 coins to the Donation Machine on the current floor."
const DONATION_FLIP := 50.0
const DONATION_NEEDED := 10

# --- the room --------------------------------------------------------------
# How many items a room holds, weighted by Repentance's own layouts: the summed
# weights of every layout with two, three or four deals (devil) or items to
# choose from (angel). 72 / 27 / 1 and 82 / 10 / 8.
const DEVIL_SIZES := {2: 14.85, 3: 5.65, 4: 0.25}
const ANGEL_SIZES := {2: 2.75, 3: 0.35, 4: 0.25}
# A devil item's price in Max Health, by ItemData.Rarity (the owner: start at 2,
# +2 a rarity).
const PRICE_BY_RARITY := [2, 4, 6, 8]
# Isaac: "If Isaac does not have Red Heart Containers… all items will cost 3 Soul
# Hearts." Shields are this game's soul hearts.
const SHIELD_PRICE := 3

# Health lost from one of these is an ENEMY'S doing (GameState.change_hp's
# `source`). Every other loss is a bill the player chose — a Blood Donation
# Machine, an event, a deal — and Isaac does not count self-damage either.
const ENEMY_SOURCES := ["enemy_attack", "status"]

const DEVIL_COLOR := Color(0.85, 0.22, 0.20)
const ANGEL_COLOR := Color(0.70, 0.82, 1.0)


static func active() -> bool:
	return GameState.has_mechanic(MECHANIC)

static func is_deal_event(ev) -> bool:
	return ev is EventData2 and ((ev as EventData2).id == DEVIL or (ev as EventData2).id == ANGEL)

static func _s() -> Dictionary:
	return GameState.deals

# A fresh run's record. Every key is here so a read never has to default it.
static func fresh() -> Dictionary:
	return {
		"lost_game": 0,        # Health enemies took this game
		"lost_total": 0,       # …and this run, which a floor's cleanliness is measured against
		"floor": 0,            # floor bosses that have walked on
		"floor_bosses": {},    # str(instance) -> {floor, lost_at}
		"boss_beaten": {},     # {floor, clean} when a floor boss fell THIS game
		"doors": [],           # the floor each deal door opened on
		"devil_seen": false,   # a Devil Room door has opened this run
		"deal_taken": false,   # a Deal with the Devil was paid for: no more Angels
		"angel_promised": false,  # the first devil door was walked away from
		"donated": {},         # str(floor) -> gold into a Donation Machine
		"rolled_floor": 0,     # the last floor a relic's chance was rolled for
		"room": {},            # the room standing open, if any
	}


# --- what the run tells it ---------------------------------------------------

# GameState._on_health_lost, for every loss in the run.
static func note_health_lost(ctx: Dictionary) -> void:
	if not ENEMY_SOURCES.has(String(ctx.get("source", ""))):
		return
	var n: int = int(ctx.get("amount", 0))
	if n <= 0:
		return
	var s := _s()
	s["lost_game"] = int(s.get("lost_game", 0)) + n
	s["lost_total"] = int(s.get("lost_total", 0)) + n

# A game was chosen (GameLoop2.choose_game): its own record starts clean.
static func note_game_started() -> void:
	var s := _s()
	s["lost_game"] = 0
	s["boss_beaten"] = {}

# A difficulty up (GameLoop2._capstone_if_due): a new floor, whether or not the
# boss roster had a boss to send.
static func note_new_floor() -> void:
	var s := _s()
	s["floor"] = int(s.get("floor", 0)) + 1

# The difficulty up's boss walked on as `instance`: that floor's boss.
static func note_floor_boss(instance: int) -> void:
	if instance <= 0:
		return
	var s := _s()
	var bosses: Dictionary = s.get("floor_bosses", {})
	bosses[str(instance)] = {"floor": int(s.get("floor", 0)),
		"lost_at": int(s.get("lost_total", 0))}
	s["floor_bosses"] = bosses

# A body left the board (GameLoop2._take_off_board). A boss leaves only by its
# goal, so a floor boss leaving is that floor's boss fight won — and the floor was
# clean if no enemy has taken Health since it walked on.
static func note_off_board(instance: int) -> void:
	var s := _s()
	var bosses: Dictionary = s.get("floor_bosses", {})
	var key := str(instance)
	if not bosses.has(key):
		return
	var rec: Dictionary = bosses[key]
	bosses.erase(key)
	s["boss_beaten"] = {"floor": int(rec.get("floor", 0)),
		"clean": int(s.get("lost_total", 0)) == int(rec.get("lost_at", 0))}

# Gold that went into a Donation Machine (ObjectSystem.donate).
static func note_donated(gold: int) -> void:
	if gold <= 0:
		return
	var s := _s()
	var d: Dictionary = s.get("donated", {})
	var key := str(int(s.get("floor", 0)))
	d[key] = int(d.get(key, 0)) + gold
	s["donated"] = d


# --- the gate every deal room is behind --------------------------------------

# No enemy took any of the player's Health this game.
static func clean_game() -> bool:
	return int(_s().get("lost_game", 0)) <= 0

# Health enemies took this game — the events sheet's `enemy_hp_lost` gate stat,
# there for any event that wants it (the deal rooms no longer do).
static func enemy_hp_lost() -> int:
	return int(_s().get("lost_game", 0))


# --- Batsaac's chance --------------------------------------------------------

# Did a door open on the floor the run is on? One a floor, as in Isaac.
static func door_this_floor() -> bool:
	return (_s().get("doors", []) as Array).has(int(_s().get("floor", 0)))

# Every term of the chance, for the chip's tooltip as much as for the roll.
# `games_before` is the games the run had handed in BEFORE this one: never on the
# first game, as Isaac never opens one on the first floor.
static func chance_parts(games_before: int = -1) -> Dictionary:
	var s := _s()
	if games_before < 0:
		games_before = GameState.games_played
	var out := {"base": 0.0, "boss": 0.0, "floor": 0.0, "items": 0.0,
		"mult": 1.0, "total": 0.0, "why": ""}
	if games_before < 1:
		out["why"] = "never on the first game"
		return out
	if not clean_game():
		out["why"] = "an enemy took Health this game"
		return out
	if door_this_floor():
		out["why"] = "a door already opened this floor"
		return out
	out["base"] = BASE_CHANCE
	var beaten: Dictionary = s.get("boss_beaten", {})
	if not beaten.is_empty():
		out["boss"] = BOSS_CLEAN_BONUS
		if bool(beaten.get("clean", false)):
			out["floor"] = FLOOR_CLEAN_BONUS
	out["items"] = item_bonus()
	out["mult"] = seen_multiplier()
	var raw: float = (float(out["base"]) + float(out["boss"]) + float(out["floor"])
		+ float(out["items"])) * float(out["mult"])
	out["total"] = clampf(raw, 0.0, 100.0)
	return out

static func chance(games_before: int = -1) -> float:
	return float(chance_parts(games_before)["total"])

# Relics that raise it: `deal_chance` in an item's stat bonuses (Book of
# Revelations' +17.5%, and whatever Pentagram-likes the sheet adds later).
static func item_bonus() -> float:
	var total: float = 0.0
	for it in GameState.inventory:
		if it is ItemData and not (it as ItemData).stat_bonuses.is_empty():
			total += float((it as ItemData).stat_bonuses.get("deal_chance", 0.0))
	return total

# ×0.25 when a door opened on this floor or the last one, ×0.5 when one opened two
# floors ago — the worse of the two when both did.
static func seen_multiplier() -> float:
	var s := _s()
	var now: int = int(s.get("floor", 0))
	var mult: float = 1.0
	for f in s.get("doors", []):
		var ago: int = now - int(f)
		if ago <= 1:
			mult = minf(mult, SEEN_RECENTLY_MULT)
		elif ago == 2:
			mult = minf(mult, SEEN_TWO_AGO_MULT)
	return mult

# The roll itself, after a clean game (Overworld2.report). Luck is for it: a deal
# room is the outcome the player wants.
static func roll_bonus(rng: RandomNumberGenerator, games_before: int) -> bool:
	if not active():
		return false
	var c: float = chance(games_before)
	if c <= 0.0:
		return false
	return Stats.roll_chance(rng, c, Stats.Favour.HIGH)


# --- any other player: the relics' share, once a floor -----------------------

# Does a player WITHOUT the mechanic hold anything that raises the chance?
static func item_roll_active() -> bool:
	return not active() and item_bonus() > 0.0

# Is there a chance to show at all — Batsaac's, or a relic's for anyone else?
static func chip_active() -> bool:
	return active() or item_bonus() > 0.0

# A difficulty up has landed since the relics' chance was last rolled.
static func item_roll_due() -> bool:
	var s := _s()
	return int(s.get("floor", 0)) > int(s.get("rolled_floor", 0))

# The relics' chance for a player without the mechanic: only what they hold, cut
# by a recent door like Batsaac's, and nothing on a floor that has already had its
# door. Whether an enemy hurt you does not come into it (the owner, 21 Nov 2026).
static func item_chance_parts() -> Dictionary:
	var out := {"items": item_bonus(), "mult": seen_multiplier(), "total": 0.0, "why": ""}
	if float(out["items"]) <= 0.0:
		out["why"] = "no relic that raises it"
		return out
	if door_this_floor():
		out["why"] = "a door already opened this floor"
		return out
	out["total"] = clampf(float(out["items"]) * float(out["mult"]), 0.0, 100.0)
	return out

static func item_chance() -> float:
	return float(item_chance_parts()["total"])

# After a report (Overworld2.report): when a difficulty up has landed since the
# last roll, the relics' chance is rolled ONCE for it, as Isaac has one chance a
# floor.
static func roll_item_bonus(rng: RandomNumberGenerator) -> bool:
	if active() or not item_roll_due():
		return false
	_s()["rolled_floor"] = int(_s().get("floor", 0))
	var c: float = item_chance()
	if c <= 0.0:
		return false
	return Stats.roll_chance(rng, c, Stats.Favour.HIGH)

# EVERY bonus door a report can open, whoever the player is: Batsaac's after any
# clean game, anyone else's relic chance after any difficulty up.
static func roll_after_game(rng: RandomNumberGenerator, games_before: int) -> bool:
	if active():
		return roll_bonus(rng, games_before)
	return roll_item_bonus(rng)

# The chance the chip quotes, for whichever player this is.
static func chip_chance() -> float:
	var raw: float = chance() if active() else item_chance()
	return Stats.effective_chance(raw, Stats.Favour.HIGH) if raw > 0.0 else 0.0


# --- Devil or Angel ----------------------------------------------------------

# The flips that could make the next door an Angel Room, as percentages — empty
# when it cannot be one at all. Decided when the door OPENS, as in Isaac.
static func angel_flips() -> Array:
	var s := _s()
	if bool(s.get("deal_taken", false)) or not bool(s.get("devil_seen", false)):
		return []
	if bool(s.get("angel_promised", false)):
		return [100.0]
	var flips: Array = [ANGEL_BASE_FLIP]
	var d: Dictionary = s.get("donated", {})
	if int(d.get(str(int(s.get("floor", 0))), 0)) >= DONATION_NEEDED:
		flips.append(DONATION_FLIP)
	return flips

# The odds the next door is an Angel's: one minus every flip failing.
static func angel_chance() -> float:
	var fail: float = 1.0
	for f in angel_flips():
		fail *= 1.0 - clampf(float(f), 0.0, 100.0) / 100.0
	return (1.0 - fail) * 100.0

# Neither side is the better one, so Luck stays out of it (Favour.NONE).
static func pick_kind(rng: RandomNumberGenerator) -> StringName:
	for f in angel_flips():
		if Stats.roll_chance(rng, float(f), Stats.Favour.NONE):
			return ANGEL
	return DEVIL


# --- the door ----------------------------------------------------------------

# A deal door opens: decide which, record it, and hand back the event to show.
static func open_door(rng: RandomNumberGenerator) -> EventData2:
	var s := _s()
	var kind: StringName = pick_kind(rng)
	if kind == ANGEL:
		s["angel_promised"] = false
	var first_devil: bool = kind == DEVIL and not bool(s.get("devil_seen", false))
	if kind == DEVIL:
		s["devil_seen"] = true
	var doors: Array = s.get("doors", [])
	doors.append(int(s.get("floor", 0)))
	s["doors"] = doors
	s["room"] = {"kind": String(kind), "entered": false, "items": [],
		"first_devil": first_devil}
	return Data.get_event2(kind)

# A room for `kind` when none was opened by its door — the dev panel's event
# starter, a test. It records no door: nothing about the run's chance moves.
static func ensure_room(kind: StringName) -> void:
	if room_kind() == kind:
		return
	_s()["room"] = {"kind": String(kind), "entered": false, "items": [],
		"first_devil": false}

static func room() -> Dictionary:
	return _s().get("room", {})

static func room_kind() -> StringName:
	return StringName(String(room().get("kind", "")))

static func is_entered() -> bool:
	return bool(room().get("entered", false))

# Walk in: the statue replaces the door and the items are laid out.
static func enter(rng: RandomNumberGenerator) -> void:
	var r: Dictionary = room()
	if r.is_empty() or bool(r.get("entered", false)):
		return
	r["entered"] = true
	var kind: StringName = room_kind()
	var size: int = roll_size(rng, kind)
	var items: Array = []
	for it in roll_items(rng, kind, size):
		items.append({"id": String((it as ItemData).id), "taken": false})
	r["items"] = items
	GameLog.add("You enter the %s." % ("Angel Room" if kind == ANGEL else "Devil Room"),
		ANGEL_COLOR if kind == ANGEL else DEVIL_COLOR)

# The room closes with its event. Walking away from the FIRST devil door without
# going in promises the next door to an Angel (Repentance).
static func close_room() -> void:
	var s := _s()
	var r: Dictionary = room()
	if not r.is_empty() and bool(r.get("first_devil", false)) \
			and not bool(r.get("entered", false)):
		s["angel_promised"] = true
	s["room"] = {}

static func roll_size(rng: RandomNumberGenerator, kind: StringName) -> int:
	var sizes: Dictionary = ANGEL_SIZES if kind == ANGEL else DEVIL_SIZES
	var total: float = 0.0
	for n in sizes:
		total += float(sizes[n])
	var pick: float = rng.randf() * total
	for n in [2, 3, 4]:
		pick -= float(sizes[n])
		if pick < 0.0:
			return n
	return 2

# `count` different items from the room's pool that the player does not already
# own. Fewer when the pool runs short (the owner: nothing fills an empty slot).
static func pool_of(kind: StringName) -> Array:
	return Data.reward_item2_pool().filter(func(it):
		return (it as ItemData).in_pool(kind) and not GameState.has_item((it as ItemData).id))

static func roll_items(rng: RandomNumberGenerator, kind: StringName, count: int) -> Array:
	var pool: Array = pool_of(kind)
	pool.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


# --- the items in the room ---------------------------------------------------

static func items() -> Array:
	return room().get("items", [])

static func item_at(i: int) -> ItemData:
	var list: Array = items()
	if i < 0 or i >= list.size():
		return null
	return Data.get_item2(StringName(String((list[i] as Dictionary).get("id", ""))))

# A devil item's price in Max Health, by its rarity.
static func price_of(item: ItemData) -> int:
	if item == null:
		return 0
	return PRICE_BY_RARITY[clampi(int(item.rarity), 0, PRICE_BY_RARITY.size() - 1)]

# With no Max Health left a deal is paid in Shields instead.
static func pays_in_shields() -> bool:
	return GameState.max_hp <= 0

# What this item would actually take, now: {"max_hp": n} or {"shields": n} for a
# devil's, {} for an angel's. A price bigger than the Max Health held takes all of
# it (the owner's rule A, after Isaac's "two-heart deals can be taken… as long as
# he has one Red Heart").
static func bill(i: int) -> Dictionary:
	if room_kind() != DEVIL:
		return {}
	var item: ItemData = item_at(i)
	if item == null:
		return {}
	if pays_in_shields():
		return {"shields": SHIELD_PRICE}
	return {"max_hp": mini(price_of(item), GameState.max_hp)}

static func cost_text(i: int) -> String:
	if room_kind() == ANGEL:
		return "Free — the others vanish"
	var item: ItemData = item_at(i)
	if item == null:
		return ""
	if pays_in_shields():
		return "-%d Shields" % SHIELD_PRICE
	var price: int = price_of(item)
	var paid: int = int(bill(i).get("max_hp", 0))
	if paid < price:
		return "-%d Max Health (all you have; costs %d)" % [paid, price]
	return "-%d Max Health" % price

static func is_taken(i: int) -> bool:
	var list: Array = items()
	return i >= 0 and i < list.size() and bool((list[i] as Dictionary).get("taken", false))

# An angel's room is spent the moment one item is taken: the rest vanish.
static func is_gone(i: int) -> bool:
	if is_taken(i):
		return true
	if room_kind() != ANGEL:
		return false
	for e in items():
		if bool((e as Dictionary).get("taken", false)):
			return true
	return false

static func can_take(i: int) -> bool:
	return is_entered() and item_at(i) != null and not is_gone(i)

# Would paying for it end the run? Paying the last Max Health with no Shield
# behind it does; so does handing over the last Shields at 0 Max Health.
static func is_deadly(i: int) -> bool:
	var b: Dictionary = bill(i)
	if b.has("shields"):
		return GameState.bonus_shields <= int(b["shields"])
	if b.has("max_hp"):
		return GameState.max_hp - int(b["max_hp"]) <= 0 and GameState.bonus_shields <= 0
	return false

# Take item `i`: pay, mark it, and hand it over. Returns the item now owned, or
# null when it could not be taken.
static func take(i: int) -> ItemData:
	if not can_take(i):
		return null
	var template: ItemData = item_at(i)
	var b: Dictionary = bill(i)
	if b.has("max_hp"):
		GameState.set_max_hp(GameState.max_hp - int(b["max_hp"]), false)
	elif b.has("shields"):
		GameState.bonus_shields = maxi(0, GameState.bonus_shields - int(b["shields"]))
		GameState.emit_signal("stats_changed")
	if room_kind() == DEVIL:
		# ANY deal paid for shuts the Angel Rooms for the rest of the run.
		_s()["deal_taken"] = true
	(items()[i] as Dictionary)["taken"] = true
	var owned: ItemData = GameState.add_item(template)
	if room_kind() == DEVIL:
		GameLog.add("Deal with the Devil: %s for %s." % [template.display_name,
			cost_text_paid(b)], DEVIL_COLOR)
	else:
		GameLog.add("The angel gives you %s." % template.display_name, ANGEL_COLOR)
	return owned

static func cost_text_paid(b: Dictionary) -> String:
	if b.has("shields"):
		return "%d Shields" % int(b["shields"])
	return "%d Max Health" % int(b.get("max_hp", 0))


# --- the art -----------------------------------------------------------------

static func _art(file: String) -> Texture2D:
	var path := "res://images2.0/events/%s.png" % file
	return load(path) if ResourceLoader.exists(path) else null

# The statue that stands in the room once you are in.
static func statue_art(kind: StringName) -> Texture2D:
	return _art(String(STATUE_ART.get(kind, "")))

static func icon_art(kind: StringName) -> Texture2D:
	return _art(String(ICON_ART.get(kind, "")))
