class_name LootPassives
extends RefCounted

# THE PACK'S PASSIVES (docs/loot-passives.md) — which pieces of carried loot are
# working from their slot right now, and what each one does.
#
# Two kinds carry a passive: every TRINKET, and the CARDS whose line opens
# "Passive:". Neither is spent. Each sits in a cell of the 3x3 and answers hooks
# from there, the way a relic answers them from the shelf — and that likeness is
# the whole implementation. A passive piece is handed to the relic runner
# (`GameState.fire_run_item_triggers`, `_recompute_item_bonuses`) as a
# RELIC-SHAPED SOURCE: an ItemData built once per definition, carrying the
# piece's triggers, stat grants and status grants. So `gold_gained: 25% chance
# gain_hp 1` on a Bloody Penny is resolved by the same lines that resolve Dragon
# Fruit, Luck steers its roll the same way, and nothing about hooks, gates or
# effects had to be written twice.
#
# WHAT A RELIC DOES NOT HAVE, AND LOOT DOES, IS A PLACE. The pack is a grid you
# arrange, and a piece can read its neighbours (§2): Blueprint does whatever the
# piece to its RIGHT does. Adjacency is asked of `neighbour_slot`, in pack SLOTS
# (what the player sees), never array indices (pickup order) — see
# GameState.loot_layout for why those are two different numbers.
#
# WHAT RIDES ON THE PACK ENTRY, not on the shared definition:
#   counter        — Rocket's growing payout (`bump`, `gain_gold plus=counter`).
#                    Read off the SOURCE piece, so a Blueprint copying a Rocket
#                    pays what that Rocket pays; bumped only by the source itself,
#                    so the copy never grows it twice.
#   once_game      — {hook: game serial} for `once_per_game` triggers, kept on the
#                    FIRING piece, so a Blueprint copying Trading Card has its own
#                    once-a-game and does not spend the original's.
# An entry is a Dictionary saved as-is with the pack, so both survive a save.

# Which way a copier looks. Only "right" is authored (Blueprint).
const DIRECTIONS := {"right": Vector2i(1, 0), "left": Vector2i(-1, 0),
	"up": Vector2i(0, -1), "down": Vector2i(0, 1)}
# The four directions a quarter turn CLOCKWISE apart — how a turned piece's
# authored direction becomes the one it faces (docs/loot-passives.md §2).
const TURNS := ["right", "down", "left", "up"]

# EVERY PIECE CAN BE TURNED, as bags can, and a turn is saved on the piece as
# `rot` (quarter turns clockwise). For most pieces it is only the picture; for a
# piece that reads a neighbour it is WHICH neighbour: a Blueprint turned once
# copies the piece below it, as a directional item does in Backpack Battles.
static func turned(dir: String, rot: int) -> String:
	var at: int = TURNS.find(dir)
	if at < 0:
		return dir
	return String(TURNS[posmod(at + rot, 4)])

# THE DIRECTION A PIECE ACTS IN, if it acts on a neighbour at all — the one
# question every surface asks to draw a piece's ARROW (LootGrid.DirArrow), so a
# new piece that reads a neighbour gets its arrow by answering here. Blueprint's
# copy is the only such rule today; add the next one's field to this function.
static func direction(entry) -> String:
	return facing(entry, def_for(entry))

# The direction the piece in `entry` copies, turned the way it is carried, or ""
# for a piece that copies nothing.
static func facing(entry, def: Resource) -> String:
	var dir: String = copies(def)
	if dir == "" or not (entry is Dictionary):
		return dir
	return turned(dir, int(entry.get("rot", 0)))

# Relic-shaped stand-ins, one per definition. Keyed by "<type>/<id>". The triggers
# they carry are read-only at runtime (all per-piece state is on the entry), so one
# shared proxy per definition is safe.
static var _proxies: Dictionary = {}


# --- what a piece is ------------------------------------------------------------

# The definition behind a carried piece if it is a PASSIVE one, or null.
static func def_for(entry) -> Resource:
	if not (entry is Dictionary):
		return null
	var id := StringName(entry.get("id", ""))
	match String(entry.get("type", "")):
		"trinket":
			return Data.get_trinket(id)
		"card":
			var c: CardData = Data.get_card(id)
			return c if c != null and c.is_passive() else null
		"weapon":
			# A WEAPON WITH A PASSIVE works from its slot as well as being swung
			# (docs/loot-passives.md §12): the Hero swords' aura, King Bomber's gold.
			var w: WeaponData = Data.get_weapon(id)
			return w if w != null and w.is_passive() else null
	return null

# Whether the piece is one that is NEVER USED — it only works from its slot. A
# weapon is never that, passive or not: it has a swing.
static func is_passive(entry) -> bool:
	var def: Resource = def_for(entry)
	return def != null and not (def is WeaponData)

# Does this piece work by copying a neighbour rather than on its own?
static func copies(def: Resource) -> String:
	if def == null:
		return ""
	return String(def.get("copy_neighbour"))


# --- where it is ----------------------------------------------------------------

# The slot `dir` of `slot`, or -1 when the pack has no cell there. Asked of the
# CELLS the player sees (GameState.pack_cells), not of slot arithmetic: a bag
# attached to the right of the 3x3 puts real cells to the right of its last column,
# and a Blueprint there copies across into the bag (docs/loot-passives.md §6) —
# adjacency is a fact about the grid, as it is in Backpack Battles, whichever bag a
# cell belongs to. Nothing wraps: past the edge of the pack there is nothing.
static func neighbour_slot(slot: int, dir: String) -> int:
	var step: Vector2i = DIRECTIONS.get(dir, Vector2i.ZERO)
	if step == Vector2i.ZERO or slot < 0 or slot >= GameState.loot_capacity():
		return -1
	return GameState.pack_slot_at(GameState.pack_cell_of(slot) + step)


# --- what is working right now --------------------------------------------------

# Every passive at work in the pack, in slot order (a piece covering several cells
# is read once, at its anchor):
#   {item: ItemData proxy, entry: the piece doing the firing (live pack row),
#    source: the piece whose passive it is (live row; == entry unless copying),
#    copy: bool, slot: int}
#
# A COPIER RESOLVES THROUGH A CHAIN, as Balatro's Blueprint does: a Blueprint
# whose right neighbour is another Blueprint copies whatever THAT one copies. The
# walk stops at the first piece with a passive of its own, at the edge, at a piece
# with no passive (nothing to copy — the copier does nothing), or on a cycle.
static func active() -> Array:
	var out: Array = []
	var layout: Array = GameState.loot_layout()
	for slot in range(layout.size()):
		var index: int = int(layout[slot])
		if index < 0 or index >= GameState.loot_items.size():
			continue
		if layout.find(index) != slot:
			continue
		var entry = GameState.loot_items[index]
		var def: Resource = def_for(entry)
		if def == null:
			continue
		var src: Dictionary = resolve(slot, layout)
		if not src.has("def"):
			continue
		out.append({"item": proxy(src["def"]), "def": src["def"],
			"entry": entry, "source": src["entry"],
			# is_same, not ==: Dictionaries compare by VALUE, and two Goat Hoofs picked
			# up the same way are equal rows that are still two pieces.
			"copy": not is_same(src["entry"], entry), "slot": slot, "copier": def})
	# THE BAGS THAT DO SOMETHING (docs/loot-passives.md §6), after the pieces. A
	# bag is not in a slot — it is slots — so `slot` is -1 and `bag` is its index in
	# `pack_bags`, which is what the `if_in_bag` gate compares a spent piece's slot
	# against. Its row in `pack_bags` is the entry, so a once-a-game claim or an
	# every-N count rides it and is saved with it. Nothing copies a bag.
	for i in range(GameState.pack_bags.size()):
		var bag = GameState.pack_bags[i]
		var bdef: BagData = GameState.bag_def(bag)
		if bdef == null or not bdef.is_passive():
			continue
		out.append({"item": proxy(bdef), "def": bdef, "entry": bag, "source": bag,
			"copy": false, "slot": -1, "copier": bdef, "bag": i})
	return out

# What the piece in `slot` actually does: {def, entry} of the passive it runs, or
# {} when it runs nothing. A plain passive answers with itself; a copier walks.
#
# BLUEPRINT COPIES ANY LOOT, not only passives (docs/loot-passives.md §2): it copies
# the TEXT of the piece it points at. So a walk that ends on a piece you USE — a
# scroll, a pill, a potion, a card, a wand — answers {usable: that entry}, and the
# Blueprint is then a piece with a Use button that does what that piece does and
# is spent doing it (`usable_copy`, LootSystem.use_loot).
static func resolve(slot: int, layout: Array = []) -> Dictionary:
	var lay: Array = layout if not layout.is_empty() else GameState.loot_layout()
	var seen: Dictionary = {}
	var at: int = slot
	while at >= 0 and at < lay.size() and not seen.has(at):
		seen[at] = true
		var index: int = int(lay[at])
		if index < 0 or index >= GameState.loot_items.size():
			return {}
		var entry = GameState.loot_items[index]
		var def: Resource = def_for(entry)
		if def == null:
			# Nothing passive here. Reached THROUGH a copier it is the thing copied; the
			# walk's own start never answers this way (it is asked only of copiers).
			# A WEAPON IS NOT COPIED AS A SWING: it is aimed and charged, and a
			# Blueprint has neither. A weapon with a passive is copied as that passive
			# (the branch below); one with none gives a copier nothing.
			if at != slot and entry is Dictionary and not LootSystem.is_bag(entry) \
					and String(entry.get("type", "")) != "weapon":
				return {"usable": entry}
			return {}
		var dir: String = facing(entry, def)
		if dir == "":
			return {"def": def, "entry": entry}
		at = neighbour_slot(at, dir)
	return {}

# The piece a copier in `slot` is copying, as a display name, or "" for nothing.
# What the pack's hover card says under a Blueprint.
static func copying_name(slot: int) -> String:
	var src: Dictionary = resolve(slot)
	if src.has("usable"):
		return LootSystem.display_name(src["usable"])
	if src.is_empty():
		return ""
	return String(src["def"].get("display_name"))

# THE PIECE A COPIER AT `index` WOULD BE USED AS — a copy of the usable piece it
# points at, stripped of where that one sits — or {} when the piece at `index` is
# not a copier, or copies a passive (which it runs from its slot) or nothing.
static func usable_copy(index: int) -> Dictionary:
	if index < 0 or index >= GameState.loot_items.size():
		return {}
	var entry = GameState.loot_items[index]
	if copies(def_for(entry)) == "":
		return {}
	var slot: int = GameState.loot_slot_of(index)
	if slot < 0:
		return {}
	var src: Dictionary = resolve(slot)
	if not src.has("usable"):
		return {}
	var out: Dictionary = (src["usable"] as Dictionary).duplicate(true)
	out.erase("pack_slot")
	out.erase("rot")
	return out

# Is the piece at `index` one the player USES rather than one that works from its
# slot? Every non-passive piece, and a Blueprint copying one.
static func is_usable_at(index: int) -> bool:
	if index < 0 or index >= GameState.loot_items.size():
		return false
	var entry = GameState.loot_items[index]
	if not (entry is Dictionary) or LootSystem.is_bag(entry):
		return false
	return not is_passive(entry) or not usable_copy(index).is_empty()

# The relic-shaped stand-in for a definition, built once.
static func proxy(def: Resource) -> ItemData:
	var key: String = "%s/%s" % [def.get_script().get_global_name(), def.get("id")]
	var cached = _proxies.get(key)
	if cached is ItemData:
		return cached
	var it := ItemData.new()
	it.id = StringName("loot_%s" % def.get("id"))
	it.display_name = String(def.get("display_name"))
	it.kind = ItemData.ItemKind.PASSIVE
	it.triggers = (def.get("triggers") as Array).duplicate(true)
	it.stat_bonuses = (def.get("stat_bonuses") as Dictionary).duplicate(true)
	it.status_bonuses = (def.get("status_bonuses") as Dictionary).duplicate(true)
	it.image = art_for(def)
	_proxies[key] = it
	return it

# The picture a passive shows when it fires (the toast) — its face in the pack.
static func art_for(def: Resource) -> Texture2D:
	if def is TrinketData:
		return load_trinket_art(def)
	if def is BagData:
		return load_bag_art(def)
	if def is CardData:
		return CardSystem.art_texture({"type": "card", "id": def.id}, true)
	if def is WeaponData:
		return load_weapon_art(def)
	return null

static func load_weapon_art(w: WeaponData) -> Texture2D:
	if w == null:
		return null
	var path: String = "res://images2.0/weapons/%s.png" % w.art_file()
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func load_bag_art(b: BagData) -> Texture2D:
	if b == null:
		return null
	var path: String = "res://images2.0/bags/%s.png" % b.art_file()
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func load_trinket_art(t: TrinketData) -> Texture2D:
	if t == null:
		return null
	var path: String = "res://images2.0/trinkets/%s.png" % t.art_file()
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# --- the rules read by total ------------------------------------------------------
#
# Two passives are not an answer to a hook but a RULE the run consults at one
# moment: Barricade (`bank_shields`, asked as a game resolves) and Echo Form
# (`echo_first_loot`, asked as a piece is spent). Each is read off every working
# piece, so a Blueprint beside one counts as another.

# The pieces at work whose passive carries `field`, as active() rows.
static func holders(field: String) -> Array:
	return active().filter(func(p): return bool(p["def"].get(field)))

# `field` summed over every working piece (a bool counts as 1).
static func total(field: String) -> int:
	var n: int = 0
	for p in active():
		n += int(p["def"].get(field))
	return n

# Toast a held rule that just did something, as the piece that did it — a
# Blueprint copying the rule fires as itself, like every other copy.
static func announce(row: Dictionary, line: String) -> void:
	var def: Resource = row["copier"] if bool(row.get("copy", false)) else row["def"]
	var who: ItemData = proxy(def)
	var label: String = who.display_name
	if bool(row.get("copy", false)):
		label = "%s (%s)" % [who.display_name, String(row["def"].get("display_name"))]
	Notifications.notify("%s: %s" % [label, line], Color(0.85, 0.9, 0.7), who.image, label)


# --- food: triggers that come round sooner beside other food (§11) --------------
#
# A piece tagged `food` in its sheet row (Backpack Battles' "triggers faster for
# each different food beside it") has the ENEMY-DEFEAT requirement of each of its
# `enemy_killed every=N` triggers lowered by one for every DIFFERENT food touching
# it, never below 1. "Touching" is any cell of its footprint sharing a side with
# any cell of the other's, so a 2x1 has six neighbours. "Different" is by id, and
# a piece's own kind does not count: a Garlic beside a Garlic is not a second food.
# A Blueprint copying a food is that food, for itself and for its neighbours.

# The food a piece is (its passive's id, a copier's copied one), or &"" for none.
static func food_id_at(index: int) -> StringName:
	var slot: int = GameState.loot_slot_of(index)
	if slot < 0:
		return &""
	var src: Dictionary = resolve(slot)
	var def = src.get("def")
	if def is TrinketData and (def as TrinketData).is_food():
		return (def as TrinketData).id
	return &""

# The pieces (indices) sharing a side with any cell of the piece at `index`.
static func adjacent_pieces(index: int) -> Array:
	var layout: Array = GameState.loot_layout()
	var out: Array = []
	for slot in range(layout.size()):
		if int(layout[slot]) != index:
			continue
		for dir in DIRECTIONS.keys():
			var n: int = neighbour_slot(slot, dir)
			if n < 0:
				continue
			var other: int = int(layout[n])
			if other >= 0 and other != index and not out.has(other):
				out.append(other)
	return out

# The different foods beside the piece at `index`, as ids — each once, its own
# kind never.
static func adjacent_foods(index: int) -> Array:
	var mine: StringName = food_id_at(index)
	var out: Array = []
	for other in adjacent_pieces(index):
		var f: StringName = food_id_at(other)
		if f != &"" and f != mine and not out.has(f):
			out.append(f)
	return out

# THE N A TRIGGER ACTUALLY COUNTS TO, for the active() row `row` firing it: the
# authored `every`, less one per different adjacent food when the passive is a
# food and the hook is a defeated enemy. Floors at 1.
static func every_for(trig: Dictionary, row: Dictionary) -> int:
	var n: int = int(trig.get("every", 0))
	if n <= 1 or row.is_empty() or String(trig.get("on", "")) != "enemy_killed":
		return n
	var def = row.get("def")
	if not (def is TrinketData and (def as TrinketData).is_food()):
		return n
	var index: int = GameState.loot_index_at_slot(int(row.get("slot", -1)))
	return maxi(1, n - adjacent_foods(index).size())

# WHERE A PIECE IS TOWARD ITS NEXT ENEMY-DEFEAT TRIGGER, for the number drawn on
# it: {have, need, foods} — `need` already lowered by the food beside it — or {}
# for a piece with no such trigger. The first such trigger answers.
static func kill_progress(index: int) -> Dictionary:
	for row in active():
		if int(row.get("slot", -1)) < 0 \
				or GameState.loot_index_at_slot(int(row["slot"])) != index:
			continue
		var it: ItemData = row["item"]
		for i in range(it.triggers.size()):
			var trig: Dictionary = it.triggers[i]
			if String(trig.get("on", "")) != "enemy_killed" or int(trig.get("every", 0)) <= 1:
				continue
			var counts: Dictionary = (row["entry"] as Dictionary).get("every_count", {})
			var need: int = every_for(trig, row)
			var have: int = int(counts.get("enemy_killed#%d" % i, 0))
			# READY: a move beside more food has lowered the target to at or below
			# what it already holds. It does not pay on the spot — the count only moves
			# on a charge — so it pays on the NEXT one, and the piece says so.
			return {"have": mini(have, need), "need": need, "ready": have >= need,
				"foods": adjacent_foods(index) if need < int(trig["every"]) else []}
	return {}


# --- who is working on whom (the hover glow) -------------------------------------
#
# WHEN A PIECE IS HOVERED, THE PIECES IT WORKS ON LIGHT UP, and so do the pieces
# working on it (docs/loot-passives.md §2). Every rule in the pack that reads a
# NEIGHBOUR answers here, so the glow and the rules cannot disagree:
#   * a copier (Blueprint) works on the piece it points at;
#   * a `weapon_stun` piece (Whetstone, a Hero sword) works on the weapons it reaches;
#   * a food works on every DIFFERENT food touching it (it lowers their target);
#   * Stankus' Toothpick is worked on by the food touching it.
# Returns {affects: [indices], affected_by: [indices]}, each index once.
static func influence(index: int) -> Dictionary:
	var affects: Array = []
	var affected_by: Array = []
	if index < 0 or index >= GameState.loot_items.size():
		return {"affects": affects, "affected_by": affected_by}
	for other in range(GameState.loot_items.size()):
		if other == index:
			continue
		if _works_on(index, other) and not affects.has(other):
			affects.append(other)
		if _works_on(other, index) and not affected_by.has(other):
			affected_by.append(other)
	return {"affects": affects, "affected_by": affected_by}

# Does the piece at `a` work on the piece at `b` through where they sit?
static func _works_on(a: int, b: int) -> bool:
	var slot: int = GameState.loot_slot_of(a)
	if slot < 0 or GameState.loot_slot_of(b) < 0:
		return false
	var entry = GameState.loot_items[a]
	var def: Resource = def_for(entry)
	# A copier, at the piece it points at.
	var dir: String = facing(entry, def)
	if dir != "":
		for s in GameState.loot_slots_of(a):
			var n: int = neighbour_slot(s, dir)
			if n >= 0 and GameState.loot_index_at_slot(n) == b:
				return true
	# What the piece RUNS (its own passive, or the one a copier runs).
	var src: Dictionary = resolve(slot)
	var run = src.get("def")
	for aura_key in ["weapon_stun", "weapon_retrigger"]:
		if run != null and run.get(aura_key) is Dictionary \
				and not (run.get(aura_key) as Dictionary).is_empty():
			if WeaponSystem.aura_targets(a, run.get(aura_key),
					int((entry as Dictionary).get("rot", 0))).has(b):
				return true
	var fa: StringName = food_id_at(a)
	if fa != &"" and adjacent_pieces(b).has(a):
		# A food lowers a DIFFERENT food's target, and feeds a weapon that counts food.
		var fb: StringName = food_id_at(b)
		if fb != &"" and fb != fa:
			return true
		var w: WeaponData = WeaponSystem.def(GameState.loot_items[b])
		if w != null and not w.stun_per_food.is_empty():
			return true
	return false


# --- the status half, held up by the slot ---------------------------------------

# The status stacks every working passive is holding up right now, summed. A
# Blueprint beside a Goat Hoof holds up a second point of Speed, and moving it away
# takes that point back down — so this is recomputed from the arrangement rather
# than put up and taken down per piece (GameState._sync_pack_statuses).
static func desired_statuses() -> Dictionary:
	var out: Dictionary = {}
	for p in active():
		var it: ItemData = p["item"]
		for k in it.status_bonuses.keys():
			out[String(k)] = int(out.get(String(k), 0)) + int(it.status_bonuses[k])
	return out
