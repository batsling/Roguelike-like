class_name WeaponSystem
extends RefCounted

# WEAPONS (docs/loot-passives.md §12) — the eighth loot kind: a piece that sits in
# the pack like a trinket, is aimed at the board like a thrown potion, and charges
# off its own goal.
#
# THE PACK ENTRY is {type: "weapon", id, rarity, charges, uid, goal_game}:
#   charges    how many it holds, 0..max_charges. A new weapon arrives EMPTY.
#   uid        tells two copies of one weapon apart — each has its own goal row on
#              the checklist, and each charges once per game.
#   goal_game  GameState.games_played when its goal last charged it, so the second
#              tick in the same game is refused whatever door it comes through.
#
# HOW IT CHARGES. Ticking its goal while a game is in play is +1 Charge, at most
# once per game (the checklist row is `any time`, keyed by `goal_key`, and locks
# once confirmed). A lost game still pays it: the row resolves the moment it is
# confirmed, and nothing about the game ending afterwards takes it back.
# Everything that charges loot charges a weapon too (GameState.chargeable_things).
#
# HOW IT SWINGS. At full charge it can be used: the board lights the squares its
# `aim` allows, the player clicks one, and its `area` from there is what it hits.
# Every enemy covered takes the Stun ONCE, however many of its squares are covered
# (a 2x2 under a plus takes 1 Stun, not 4). The swing spends every charge.
#
# NO STATE LIVES HERE. It is all on the entry (saved with the pack) or on Data.

const WEAPON_COLOR := Color(0.92, 0.62, 0.36)


# --- what a piece is ------------------------------------------------------------

static func is_weapon(entry) -> bool:
	return entry is Dictionary and String(entry.get("type", "")) == "weapon"

static func def(entry) -> WeaponData:
	if not is_weapon(entry):
		return null
	return Data.get_weapon(StringName(entry.get("id", "")))

# A new pack entry for `w`, EMPTY — a weapon is loaded by playing, not found loaded.
static func new_entry(w: WeaponData) -> Dictionary:
	if w == null:
		return {}
	return {"type": "weapon", "id": w.id, "rarity": w.rarity, "charges": 0,
		"uid": _next_uid(), "goal_game": -1}

# A uid no carried weapon already has. Random rather than counted so an entry
# rolled for a shop shelf and one granted later cannot collide on a shared counter
# that a save would have to carry.
static func _next_uid() -> int:
	var used: Dictionary = {}
	for e in GameState.loot_items:
		if is_weapon(e):
			used[int(e.get("uid", 0))] = true
	var uid: int = randi() % 1000000000 + 1
	while used.has(uid):
		uid = randi() % 1000000000 + 1
	return uid

# The uid of an entry, given one on the spot if it came from somewhere that did not
# (an old save, a hand-built test entry). Written back, so it is stable from then on.
static func uid_of(entry: Dictionary) -> int:
	if int(entry.get("uid", 0)) <= 0:
		entry["uid"] = _next_uid()
	return int(entry["uid"])


# --- charges --------------------------------------------------------------------

static func max_charges(entry) -> int:
	var w: WeaponData = def(entry)
	return w.max_charges if w != null else 0

static func charges_of(entry) -> int:
	return clampi(int(entry.get("charges", 0)), 0, max_charges(entry)) if is_weapon(entry) else 0

static func is_ready(entry) -> bool:
	return is_weapon(entry) and max_charges(entry) > 0 \
		and charges_of(entry) >= max_charges(entry)

# Room left in it.
static func room(entry) -> int:
	return maxi(0, max_charges(entry) - charges_of(entry))

# Add up to `amount` charges; returns how many landed. Full is full — a charge with
# nowhere to go is not banked.
static func add_charges(entry: Dictionary, amount: int) -> int:
	var landed: int = mini(maxi(0, amount), room(entry))
	if landed > 0:
		entry["charges"] = charges_of(entry) + landed
	return landed


# --- its goal -------------------------------------------------------------------

# The checklist row's key for this weapon at this game (GameLoop2.row_answered).
static func goal_key(entry: Dictionary) -> String:
	return "weapon:%d" % uid_of(entry)

# Whether its goal can still charge it at the game in play.
static func goal_open(entry: Dictionary) -> bool:
	return int(entry.get("goal_game", -1)) != GameState.games_played

# THE GOAL WAS DONE: +1 Charge, once per game. Returns how many landed (0 when the
# goal already paid this game, or the weapon is full). Called by the checklist row
# on its confirm, which also locks the row.
static func goal_done(entry: Dictionary) -> int:
	if not goal_open(entry):
		return 0
	entry["goal_game"] = GameState.games_played
	var landed: int = GameState.charge_loot_entry(entry, 1)
	GameState.emit_signal("inventory_changed")
	return landed

# Every weapon carried, as [{entry, index}], in pack order — the checklist's rows.
static func carried() -> Array:
	var out: Array = []
	var layout: Array = GameState.loot_layout()
	var seen: Dictionary = {}
	for slot in range(layout.size()):
		var index: int = int(layout[slot])
		if index < 0 or seen.has(index):
			continue
		seen[index] = true
		var entry = GameState.loot_items[index]
		if is_weapon(entry) and def(entry) != null:
			out.append({"entry": entry, "index": index})
	return out


# --- how hard it hits -----------------------------------------------------------

# THE STUN A SWING FROM THE PIECE AT `index` LAYS, broken down so the hover can say
# where each point came from: [{from: name, amount}], its own Effect first.
#   * the weapon's own `stun N`;
#   * +N from every piece whose `weapon_stun` points at it (Whetstone above and
#     below, a Hero sword on any side) — each such piece once;
#   * Stankus' Toothpick: +N for every `per` FOOD pieces touching it.
static func stun_parts(index: int) -> Array:
	if index < 0 or index >= GameState.loot_items.size():
		return []
	var entry = GameState.loot_items[index]
	var w: WeaponData = def(entry)
	if w == null:
		return []
	var parts: Array = [{"from": w.display_name, "amount": w.stun}]
	for row in LootPassives.active():
		var aura: Dictionary = row["def"].get("weapon_stun") \
			if row["def"].get("weapon_stun") is Dictionary else {}
		if aura.is_empty() or int(row.get("slot", -1)) < 0:
			continue
		var src: int = GameState.loot_index_at_slot(int(row["slot"]))
		if src == index:
			continue
		if aura_targets(src, aura, int((row["entry"] as Dictionary).get("rot", 0))).has(index):
			parts.append({"from": String(row["def"].get("display_name")),
				"amount": int(aura.get("amount", 0))})
	var per_food: Dictionary = w.stun_per_food
	if not per_food.is_empty():
		var foods: int = adjacent_food_pieces(index).size()
		@warning_ignore("integer_division")
		var bonus: int = int(per_food.get("amount", 0)) * (foods / maxi(1, int(per_food.get("per", 1))))
		if bonus > 0:
			parts.append({"from": "%d food beside it" % foods, "amount": bonus})
	return parts

static func stun_for(index: int) -> int:
	var n: int = 0
	for p in stun_parts(index):
		n += int(p["amount"])
	return n

# The WEAPONS (indices) a piece at `src` with `aura` reaches: the pieces sharing a
# side with its footprint in each of the aura's directions, turned with the piece.
static func aura_targets(src: int, aura: Dictionary, rot: int = 0) -> Array:
	var out: Array = []
	for slot in GameState.loot_slots_of(src):
		for dir in aura.get("dirs", []):
			var n: int = LootPassives.neighbour_slot(slot, LootPassives.turned(String(dir), rot))
			if n < 0:
				continue
			var other: int = GameState.loot_index_at_slot(n)
			if other >= 0 and other != src and not out.has(other) \
					and is_weapon(GameState.loot_items[other]):
				out.append(other)
	return out

# The food PIECES touching the piece at `index` — every piece, not every kind: two
# Garlics beside Stankus' Toothpick are two food.
static func adjacent_food_pieces(index: int) -> Array:
	return LootPassives.adjacent_pieces(index).filter(
		func(i): return LootPassives.food_id_at(i) != &"")


# --- aiming ---------------------------------------------------------------------

# THE SQUARES A SWING MAY BE AIMED AT (the sheet's `Aim`), on the board as it
# stands. What the board lights up and what it accepts a click on.
#   any        every square
#   front      column 1, next to you        back   the spawn column
#   column N   that column (none if the board is narrower)
#   enemy      every square an enemy is standing on
#   none       nothing to click — see `fixed_cell`
static func aim_cells(entry) -> Array:
	var w: WeaponData = def(entry)
	if w == null:
		return []
	match w.aim:
		"front":
			return GameLoop2.column_cells(1)
		"back":
			return GameLoop2.column_cells(GameLoop2.grid_cols())
		"column":
			return GameLoop2.column_cells(w.aim_column)
		"enemy":
			return GameLoop2.occupancy().keys()
		"none":
			return []
	return GameLoop2.target_cells("all")

# Whether it needs a click at all.
static func needs_aim(entry) -> bool:
	var w: WeaponData = def(entry)
	return w != null and w.aim != "none"

# Where an `aim: none` swing is laid: the front column's middle row, so a drawn
# shape reads from the square in front of you.
static func fixed_cell() -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(1, (GameLoop2.grid_rows() - 1) / 2)

# WHERE IT AIMS, in the words the hover prints.
static func aim_words(w: WeaponData) -> String:
	match w.aim:
		"front":
			return "at the front column"
		"back":
			return "at the back column"
		"column":
			return "at column %d" % w.aim_column
		"enemy":
			return "at an enemy"
		"none":
			return "at a fixed spot"
	return "anywhere"

# WHAT SHAPE IT HITS, in the same words.
static func area_words(area: String) -> String:
	var low: String = area.to_lower()
	match low:
		"cell":
			return "single square"
		"row", "col", "column", "cross":
			return low
		"3x3", "5x5":
			return "%s square" % low
		"board", "all":
			return "whole board"
		"plus":
			return "plus"
		"diagonals":
			return "diagonal cross"
	var m := RegEx.create_from_string("^(\\d+)x(\\d+)$").search(low)
	if m != null:
		return "%s-row by %s-column block" % [m.get_string(1), m.get_string(2)]
	return "drawn shape"

# The squares a swing aimed at `cell` hits (its `area` from there, clipped).
static func hit_cells(entry, cell: Vector2i) -> Array:
	var w: WeaponData = def(entry)
	if w == null:
		return []
	return GameLoop2.area_cells(cell, w.area)


# --- the swing ------------------------------------------------------------------

# SWING the weapon `entry` (already off its charges, see LootSystem.use_loot) at
# `ctx.target`, laying `ctx.weapon_stun` Stun on every enemy its area covers, once
# each. `ctx.weapon_slot` is where it sat, for the `weapon_stunned` hook.
static func swing(entry: Dictionary, ctx: Dictionary) -> Dictionary:
	var out := {"logs": [], "requests": []}
	var w: WeaponData = def(entry)
	if w == null:
		return out
	var at = ctx.get("target")
	var cell: Vector2i = at if at is Vector2i else fixed_cell()
	var stun: int = int(ctx.get("weapon_stun", w.stun))
	var hit: Array = GameLoop2.area_instances(hit_cells(entry, cell))
	var stunned: int = 0
	for inst in hit:
		if stun > 0 and GameLoop2.stun(int(inst), stun):
			stunned += 1
			TriggerBus.weapon_stunned.emit({"slot": int(ctx.get("weapon_slot", -1)),
				"instance": int(inst), "weapon": w.id})
	if stunned == 0:
		(out["logs"] as Array).append("%s hits nothing." % w.display_name)
	else:
		(out["logs"] as Array).append("%s stuns %d %s (+%d Stun)." % [w.display_name,
			stunned, "enemy" if stunned == 1 else "enemies", stun])
	GameLoop2.loop_changed.emit()
	return out


# --- evolving (docs/loot-passives.md §13) ----------------------------------------
#
# A WEAPON EVOLVES WHEN THE RUN HOLDS WHAT IT ASKS FOR: the `evolutions` sheet names
# the weapon (Requirement 1) and N things carrying a tag (Requirement 2) — a relic
# on the shelf (Crown) or a trinket in the pack (Garlic, Whetstone), WHEREVER they
# are. The weapon's card grows an Evolve button; pressing it turns the weapon into
# the result, and uses up the tagged things when the Outcome says `Consume All`
# (`Consume None` keeps them — King Bomber keeps its Crown). With more eligible
# things than it needs, the player picks which.
#
# A CANDIDATE is {kind: "item", item: ItemData} for a relic, or {kind: "loot",
# entry: Dictionary} for a trinket in the pack — by reference, so the one picked is
# the one removed.

# Every relic and pack trinket carrying `tag`, relics first.
static func tagged_things(tag: String) -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and (it as ItemData).tags.has(tag):
			out.append({"kind": "item", "item": it})
	for e in GameState.loot_items:
		if e is Dictionary and String(e.get("type", "")) == "trinket":
			var t: TrinketData = Data.get_trinket(StringName(e.get("id", "")))
			if t != null and t.tags.has(tag):
				out.append({"kind": "loot", "entry": e})
	return out

# The evolutions the weapon in `entry` can take RIGHT NOW: [{evo, candidates}] for
# every row whose base is this weapon and whose tagged things the run holds enough
# of. Empty for anything else.
static func evolutions_ready(entry) -> Array:
	var out: Array = []
	var w: WeaponData = def(entry)
	if w == null:
		return out
	for evo in Data.evolutions_from(w.id):
		var cands: Array = tagged_things((evo as EvolutionData).need_tag)
		if cands.size() >= (evo as EvolutionData).need_count \
				and Data.get_weapon((evo as EvolutionData).result) != null:
			out.append({"evo": evo, "candidates": cands})
	return out

# The words for a candidate, for the picker.
static func candidate_name(c: Dictionary) -> String:
	if String(c.get("kind", "")) == "item":
		return (c["item"] as ItemData).display_name
	return LootSystem.display_name(c.get("entry", {}))

# The words for what an evolution needs.
static func need_words(evo: EvolutionData) -> String:
	return "%s%s with \"%s\"" % ["" if evo.need_count == 1 else "%d " % evo.need_count,
		"item or trinket" if evo.need_count == 1 else "items or trinkets", evo.need_tag]

# EVOLVE the weapon at pack index `index` by `evo`, using `chosen` (need_count of
# the candidates evolutions_ready listed). Returns the new entry, or {} when it
# could not happen. The new weapon takes the old one's place, charges and
# once-a-game goal claim — it is the same weapon, grown — and is re-seated wherever
# it fits if the bigger shape no longer does where the old one stood.
static func evolve(index: int, evo: EvolutionData, chosen: Array) -> Dictionary:
	if evo == null or index < 0 or index >= GameState.loot_items.size():
		return {}
	var old = GameState.loot_items[index]
	var w: WeaponData = def(old)
	var result: WeaponData = Data.get_weapon(evo.result)
	if w == null or result == null or w.id != evo.base or chosen.size() != evo.need_count:
		return {}
	var valid: Array = tagged_things(evo.need_tag)
	for c in chosen:
		if not valid.any(func(v): return _same_candidate(v, c)):
			return {}
	# What rides across: the charge (clamped to the new weapon's), the claim, the uid.
	var grown: Dictionary = new_entry(result)
	grown["uid"] = uid_of(old)
	grown["goal_game"] = int(old.get("goal_game", -1))
	grown["charges"] = mini(charges_of(old), result.max_charges)
	grown["pack_slot"] = int(old.get("pack_slot", -1))
	grown["rot"] = int(old.get("rot", 0))
	if evo.consumes:
		for c in chosen:
			if String(c.get("kind", "")) == "item":
				GameState.remove_item(c["item"])
			else:
				for i in range(GameState.loot_items.size()):
					if is_same(GameState.loot_items[i], c["entry"]):
						GameState.loot_items.remove_at(i)
						break
	for i in range(GameState.loot_items.size()):
		if is_same(GameState.loot_items[i], old):
			GameState.loot_items.remove_at(i)
			break
	# Where the old one stood, if the new shape fits there; otherwise the first place
	# it fits (GameState.loot_layout re-seats a piece whose slot will not hold it).
	var anchor: int = int(grown["pack_slot"])
	var cells: Array = GameState.piece_slots(grown, anchor, int(grown["rot"])) if anchor >= 0 else []
	if cells.is_empty() or not GameState._all_free(GameState.loot_layout(), cells):
		grown.erase("pack_slot")
		grown["rot"] = 0
		grown = GameState._seated(grown)
	GameState.loot_items.append(grown)
	GameState.emit_signal("inventory_changed")
	GameLog.add("%s evolves into %s!" % [w.display_name, result.display_name], WEAPON_COLOR)
	Notifications.notify("%s evolved into %s!" % [w.display_name, result.display_name],
		WEAPON_COLOR, LootPassives.load_weapon_art(result))
	return grown

static func _same_candidate(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("kind", "")) != String(b.get("kind", "")):
		return false
	if String(a["kind"]) == "item":
		return a.get("item") == b.get("item")
	return is_same(a.get("entry"), b.get("entry"))
