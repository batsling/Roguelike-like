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
	return null

static func is_passive(entry) -> bool:
	return def_for(entry) != null

# Does this piece work by copying a neighbour rather than on its own?
static func copies(def: Resource) -> String:
	if def == null:
		return ""
	return String(def.get("copy_neighbour"))


# --- where it is ----------------------------------------------------------------

# How wide the pack is drawn. The one statement of it — LootGrid draws with this —
# because "the slot to the right" is only a fact about the grid the player sees.
# Three columns; a capacity that is a larger multiple of three widens instead of
# growing a fourth row (LootGrid's reasoning, kept here so both read one rule).
static func pack_columns() -> int:
	var cap: int = GameState.loot_capacity()
	if cap > 9 and cap % 3 == 0:
		@warning_ignore("integer_division")
		return cap / 3
	return 3

# The slot `dir` of `slot`, or -1 off the edge. A row does NOT wrap: the last cell
# of a row has nothing to its right, which is the rule that makes the right-hand
# column a real cost for a Blueprint.
static func neighbour_slot(slot: int, dir: String) -> int:
	var step: Vector2i = DIRECTIONS.get(dir, Vector2i.ZERO)
	if step == Vector2i.ZERO or slot < 0:
		return -1
	var cols: int = pack_columns()
	var cap: int = GameState.loot_capacity()
	var col: int = slot % cols + step.x
	@warning_ignore("integer_division")
	var row: int = slot / cols + step.y
	if col < 0 or col >= cols or row < 0:
		return -1
	var out: int = row * cols + col
	return out if out < cap else -1


# --- what is working right now --------------------------------------------------

# Every passive at work in the pack, in slot order:
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
		var entry = GameState.loot_items[index]
		var def: Resource = def_for(entry)
		if def == null:
			continue
		var src: Dictionary = resolve(slot, layout)
		if src.is_empty():
			continue
		out.append({"item": proxy(src["def"]), "def": src["def"],
			"entry": entry, "source": src["entry"],
			# is_same, not ==: Dictionaries compare by VALUE, and two Goat Hoofs picked
			# up the same way are equal rows that are still two pieces.
			"copy": not is_same(src["entry"], entry), "slot": slot, "copier": def})
	return out

# What the piece in `slot` actually does: {def, entry} of the passive it runs, or
# {} when it runs nothing. A plain passive answers with itself; a copier walks.
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
			return {}
		var dir: String = copies(def)
		if dir == "":
			return {"def": def, "entry": entry}
		at = neighbour_slot(at, dir)
	return {}

# The piece a copier in `slot` is copying, as a display name, or "" for nothing.
# What the pack's hover card says under a Blueprint.
static func copying_name(slot: int) -> String:
	var src: Dictionary = resolve(slot)
	if src.is_empty():
		return ""
	return String(src["def"].get("display_name"))

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
	if def is CardData:
		return CardSystem.art_texture({"type": "card", "id": def.id}, true)
	return null

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
