extends Node

# PotionSystem (autoload) — the games-first (2.0) POTION brain
# (docs/potions-design.md). A potion is the third loot consumable and the first
# one that is TWO EFFECTS IN ONE PIECE: every row authors a quaff side and a throw
# side, and the player chooses which they are buying when they spend it.
#
# BOTH VERBS LIVE HERE (§11 steps 4 and 5). `quaff_potion` applies the sheet's
# `On Player` side to the drinker; `throw_potion` takes a CELL of the battlefield
# in `ctx.target` and applies the `On Tile` side around it. The board geometry
# itself is GameLoop2's (`area_cells`) — this file says which shapes a clause
# reaches and what lands in them, never what a shape means.
#
# It is PillSystem's shape with three differences, all of them from §6:
#
#   * THE ALPHABET IS DEALT FROM A MUCH BIGGER BAG. 37 vials on disk, 15 potions,
#     so a run binds 15 and leaves 22 meaning nothing. That spare pile is what
#     stops deduction: knowing fourteen colours tells you nothing about the
#     fifteenth, because it may well be one of the twenty-two that never drop.
#   * AN UNKNOWN BOTTLE NAMES ITS COLOUR (§6.4, decision #18) — "Swirly Potion",
#     "Ruby Potion". A pill never spells its capsule out, because a game that
#     wrote "green is Bad Trip" would hand back the deduction the spare capsules
#     exist to prevent. Naming a colour is not naming what is IN it, and 37 vials
#     cannot be told apart in a run log any other way.
#   * AN IDENTIFIED POTION HAS ART OF ITS OWN, where a pill only ever has its
#     capsule. Nine of the fifteen do; the other six keep wearing the run's bottle
#     forever, and that fallback IS the design (§6.3, decision #29).
#
# Identification is of the TYPE and covers BOTH VERBS (§6.5, decision #22): drink
# an unknown swirly bottle, learn it was Fire Potion, and you know what throwing a
# swirly one does as well.
#
# Content lives in the `potions2.0` sheet of tools/Roguelikes.xlsx, generated into
# data/potions2.0/*.tres by tools/generate_potion2_tres.py.

const POTION_COLOR := Color(0.62, 0.55, 0.86)

# The 37 vials in images2.0/potions_unidentified/, as their file bases. A const
# list rather than a directory scan, for PillSystem's reason: the deal has to be
# reproducible from the save (potion_color_map stores these names, not indices),
# and a file going missing should fail as one broken texture rather than as a
# silently smaller alphabet. test_potion_system.gd checks this list against the
# folder IN BOTH DIRECTIONS — art that ships without being listed is art no run
# can ever show, which is the one gap test_pill_system.gd has.
const COLORS := [
	"Amber_Shattered_Pixel_Dungeon", "Azure_Shattered_Pixel_Dungeon",
	"Bistre_Shattered_Pixel_Dungeon", "Black_NetHack", "Brilliant_Blue_NetHack",
	"Brown_NetHack", "Bubbly_NetHack", "Charcoal_Shattered_Pixel_Dungeon",
	"Cloudy_NetHack", "Crimson_Shattered_Pixel_Dungeon", "Cyan_NetHack",
	"Dark_Green_NetHack", "Dark_NetHack", "Effervescent_NetHack",
	"Emerald_NetHack", "Fizzy_NetHack", "Golden_NetHack",
	"Golden_Shattered_Pixel_Dungeon", "Indigo_Shattered_Pixel_Dungeon",
	"Ivory_Shattered_Pixel_Dungeon", "Jade_Shattered_Pixel_Dungeon",
	"Magenta_NetHack", "Magenta_Shattered_Pixel_Dungeon", "Milky_NetHack",
	"Murky_NetHack", "Orange_NetHack", "Pink_NetHack", "Puce_NetHack",
	"Purple-Red_NetHack", "Ruby_NetHack", "Silver_Shattered_Pixel_Dungeon",
	"Sky_Blue_NetHack", "Smoky_NetHack", "Swirly_NetHack",
	"Turquoise_Shattered_Pixel_Dungeon", "White_NetHack", "Yellow_NetHack",
]

# The games the vials came from, longest first so the split below never stops at
# the wrong underscore. The file name is content (§6.4): it carries a colour AND
# the game that named it, and the card credits the source the way every other row
# in this project does.
const SOURCES := ["Shattered_Pixel_Dungeon", "NetHack"]

# ===========================================================================
# Reading a vial's file name
# ===========================================================================

# "Swirly_NetHack" -> "Swirly"; "Dark_Green_NetHack" -> "Dark Green".
func color_name(base: String) -> String:
	for src in SOURCES:
		if base.ends_with("_" + src):
			return base.substr(0, base.length() - src.length() - 1).replace("_", " ")
	return base.replace("_", " ")

# "Swirly_NetHack" -> "NetHack". "" when the file is not named for a game.
func color_source(base: String) -> String:
	for src in SOURCES:
		if base.ends_with("_" + src):
			return src.replace("_", " ")
	return ""

# ===========================================================================
# The run's alphabet: which vial means which potion
# ===========================================================================

# Deal every potion a distinct vial, once per run. 37 vials and 15 potions, so 22
# are left over — and unlike the pills' three, that leftover pile is most of the
# bag, which is exactly what makes the last potion undeducible.
#
# THE DEAL IS BY COLOUR NAME, NOT BY FILE. Two pairs of vials share a colour word
# — Golden and Magenta each ship in a NetHack and a Shattered Pixel Dungeon
# version — and decision #18 has an unknown bottle introduce itself BY that word.
# Two potions both answering "Golden Potion" would make the run log ambiguous
# about a mystery the player is being asked to track, so the bag is shuffled and
# then drawn from with one vial per distinct colour name. Both files stay in the
# pool; at most one of each pair is ever dealt.
#
# Idempotent: a run reloaded from a save already has its map and must keep it, or
# the alphabet the player spent the run learning would be redealt underneath them.
func ensure_colors() -> void:
	if not GameState.potion_color_map.is_empty():
		return
	var potions: Array = Data.all_potions()
	if potions.is_empty():
		return
	var bag: Array = COLORS.duplicate()
	bag.shuffle()
	var taken_names: Dictionary = {}
	var deal: Array = []
	for base in bag:
		var nm: String = color_name(base)
		if taken_names.has(nm):
			continue
		taken_names[nm] = true
		deal.append(base)
		if deal.size() >= potions.size():
			break
	if deal.size() < potions.size():
		# More potions than distinct colours — the sheet outgrew the art. Bind what
		# can be bound rather than leaving some potions colourless further down.
		push_warning("PotionSystem: %d potions but only %d distinct colours"
			% [potions.size(), deal.size()])
	for i in range(potions.size()):
		if i >= deal.size():
			break
		GameState.potion_color_map[String(potions[i].id)] = deal[i]

# The vial a potion wears this run ("Swirly_NetHack"), or "" if never dealt one.
func color_for(id: StringName) -> String:
	ensure_colors()
	return String(GameState.potion_color_map.get(String(id), ""))

# The potion a vial means this run, or null.
func potion_for_color(base: String) -> PotionData:
	ensure_colors()
	for id in GameState.potion_color_map.keys():
		if String(GameState.potion_color_map[id]) == base:
			return Data.get_potion(StringName(id))
	return null

# The vials this run dealt to nothing — 22 of them, and the fact the whole
# identification design rests on, so a test can assert it rather than trusting the
# arithmetic.
func unused_colors() -> Array:
	ensure_colors()
	var used: Array = GameState.potion_color_map.values()
	return COLORS.filter(func(c): return not used.has(c))

# ===========================================================================
# Identification (the potion TYPE's, and it covers both verbs)
# ===========================================================================

func is_identified(id: StringName) -> bool:
	return GameState.identified_potion_types.has(id)

# Reveals a potion for the rest of the run. Returns true if this call newly
# identified it, so callers can show a one-time toast. BOTH SIDES AT ONCE
# (decision #22): learning it from a quaff teaches the throw too, because the
# alternative is thirty facts instead of fifteen and a quaff-or-throw choice that
# turns into a research task.
func identify(id: StringName) -> bool:
	if id == &"" or GameState.identified_potion_types.has(id):
		return false
	GameState.identified_potion_types.append(id)
	var p: PotionData = Data.get_potion(id)
	var nm: String = p.display_name if p != null else String(id)
	Notifications.notify("Identified: %s!" % nm, POTION_COLOR)
	return true

func unidentify(id: StringName) -> void:
	GameState.identified_potion_types.erase(id)

# ===========================================================================
# Display: names, art
# ===========================================================================

# What a carried potion is called. An unknown one says its COLOUR — "Swirly
# Potion" — which is the one place potions deliberately depart from pills (§6.4).
# A vial the run never dealt a colour to falls back to the generic word rather
# than to nothing.
func display_name(entry: Dictionary) -> String:
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null:
		return "Potion"
	if is_identified(potion.id):
		return potion.display_name
	var base: String = color_for(potion.id)
	return "Potion" if base == "" else "%s Potion" % color_name(base)

# The game a bottle's colour was lifted from, for the card's credit line. Empty
# once the potion is identified — from then on the potion's own `reference` is the
# credit, and the vial is just the wrapper it arrived in.
func color_credit(entry: Dictionary) -> String:
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null or is_identified(potion.id):
		return ""
	return color_source(color_for(potion.id))

# What the potion does, in words — BOTH verbs once it is known, because the
# quaff-or-throw choice only works when both halves are on the card (§6.5). The
# sheet's own prose, never a line assembled from ops.
func description(entry: Dictionary) -> String:
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null:
		return ""
	if not is_identified(potion.id):
		return "You don't know what this one does. Using it is how you find out."
	var parts: Array = []
	if potion.quaff_text != "":
		parts.append("Quaff: %s" % potion.quaff_text)
	if potion.throw_text != "":
		parts.append("Throw: %s" % potion.throw_text)
	elif not potion.has_throw():
		# Raise Level: no throw effect AND no throw prose. Said out loud, because a
		# missing row reads as missing text rather than as a fact about the bottle.
		parts.append("Throw: nothing — this one cannot be thrown.")
	return "  ".join(parts)

# The Preference, hidden until the bottle is known — the gamble is only a gamble
# because this is hidden, exactly as it is for a scroll and a pill.
func preference(entry: Dictionary) -> String:
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null or not is_identified(potion.id):
		return ""
	return potion.preference

# The bottle. An identified potion shows its OWN art where it has any; everything
# else — unidentified, or identified with no `File`, or a `File` that does not
# resolve — shows the vial the run dealt it. That last case is not a fallback for
# a bug, it is six of the fifteen rows and it is the design (§6.3, decision #29).
func art_texture(entry: Dictionary) -> Texture2D:
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null:
		return null
	if is_identified(potion.id) and potion.art_file() != "":
		var path := "res://images2.0/potions_identified/%s.png" % potion.art_file()
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				return tex
	return _load_vial(color_for(potion.id))

func _load_vial(base: String) -> Texture2D:
	if base == "":
		return null
	var path := "res://images2.0/potions_unidentified/%s.png" % base
	if not ResourceLoader.exists(path):
		return null
	return load(path)

# HOW MUCH BIGGER THIS PIECE DRAWS THAN THE SURFACE'S BASE SIZE — a CAP rather
# than the pills' multiplier (§6.2). Two vial sets ship at two sizes (NetHack's
# 16x16 and Shattered Pixel Dungeon's 48x42) and the identified bottles are
# 256x256, so a box that took its size from the art the way a horse capsule's does
# would draw a mystery vial as a postage stamp beside a known bottle. Every potion
# is drawn at the surface's own size; the ratio is 1.0 and this exists so the
# reason is written down where the next person looks for it.
func art_scale(_entry: Dictionary) -> float:
	return 1.0

# ===========================================================================
# Rolling one as loot
# ===========================================================================

# A dropped potion: rarity-weighted through Data.roll_potion, so LUCK rides it for
# free (§16) and a Rare bottle is a Rare bottle. Unlike a pill — which has no
# rarity, being one of the ten the run dealt — a potion's rung is authored.
# Returns {} when no potions are loaded.
func roll_potion_loot(rng: RandomNumberGenerator = null) -> Dictionary:
	var potion: PotionData = Data.roll_potion(rng)
	if potion == null:
		return {}
	ensure_colors()
	return {"type": "potion", "id": potion.id, "rarity": potion.rarity}

# ===========================================================================
# Quaffing one
# ===========================================================================

# Drink `entry` ({type, id}): identify the bottle, then apply its quaff side.
# Returns { "logs": Array[String], "requests": Array[Dictionary] } — the same
# contract ScrollSystem.read_scroll and PillSystem.take_pill answer with, so one
# caller can spend any of the three.
#   ctx (optional): { "rng": RandomNumberGenerator }
#
# IDENTIFY FIRST, ALWAYS. The gamble pays its information out even when the effect
# lands on nothing (§4.5) — a Potion of Uselessness that fizzled anonymously would
# be a piece of loot the player could spend twice without learning anything.
func quaff_potion(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null:
		return out
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	identify(potion.id)

	var ops: Array = potion.quaff
	if ops.is_empty():
		# Potion of Uselessness, and it should read as the joke it is rather than
		# as a use that reported nothing.
		out["logs"].append("Nothing happens.")
		return out
	for op in ops:
		if op is Dictionary:
			_apply_one(op, out, rng)
	return out

# Which of an op's numbers Sacred Bark's "double the effect" doubles (§8.2). Named
# per op rather than "every integer in the dict", for ScrollSystem's reason.
const LOOT_SCALED_FIELDS := {
	"take_damage": ["value"],
	"gain_hp": ["value"],
	"gain_max_hp": ["value"],
	"gain_stat": ["value"],
	"apply_status": ["value"],
	"gain_level": ["value"],
	# The throw side. `deal_damage` and the three grants move a value like their
	# quaff-side twins; the `area` every throw clause carries is the unusual half
	# and goes up the ladder below instead.
	"deal_damage": ["value"],
	"grant_shield": ["value"],
	"grant_health": ["value"],
	"grant_max_health": ["value"],
	"apply_tile": [],
}

func _scaled_value(op: Dictionary, field: String, fallback: int) -> int:
	var raw: int = int(op.get(field, fallback))
	var fields: Array = LOOT_SCALED_FIELDS.get(String(op.get("op", "")), [])
	if not fields.has(field):
		return raw
	var mult: int = GameState.loot_multiplier()
	if mult <= 1:
		return raw
	return maxi(1, raw) * mult

# A GRID HAS NO WAY TO BE EXACTLY TWICE AS BIG, so Sacred Bark widens a throw's
# shape by ONE STEP of a ladder rather than by a multiplier (§8.2, decision #19).
#
# Two rungs want saying out loud. A BOTTLE AIMED AT ONE SQUARE STILL HITS ONE
# SQUARE: the radius the potion authored is zero and twice nothing is nothing, and
# a Bark that turned every single-target throw into a nine-cell blast would make
# aiming pointless. A LINE BECOMES THE CROSS because that is the widening this
# game already has a word for — it is exactly what Brimstone does to a bomb, so a
# doubled Explosive Ampoule reads as a shape the player has seen before.
#
# `board` is already everything, so it doubles to itself for the same reason
# `cell` does.
const AREA_LADDER := {
	"cell": "cell",
	"3x3": "5x5",
	"5x5": "5x5",
	"row": "cross",
	"col": "cross",
	"cross": "cross",
	"board": "board",
}

# The shape a clause actually covers for THIS player: the authored `area`, one
# rung up the ladder when the Bark is in the pack. An area the ladder has never
# heard of is left exactly as authored rather than guessed at.
func _scaled_area(op: Dictionary) -> String:
	var area: String = String(op.get("area", "cell")).to_lower()
	if GameState.loot_multiplier() <= 1:
		return area
	return String(AREA_LADDER.get(area, area))

func _apply_one(op: Dictionary, out: Dictionary, _rng: RandomNumberGenerator) -> void:
	match String(op.get("op", "")):
		"take_damage":
			# THROUGH THE BOARD'S OWN HIT PATH, so shields stop it and every relic
			# that watches for damage sees it. A potion that subtracted Health
			# directly would be the one source of damage the run's armour ignored.
			var dmg: int = _scaled_value(op, "value", 1)
			GameLoop2.damage_player(dmg)
			out["logs"].append("You take %d damage." % dmg)
		"gain_hp":
			var healed: int = _scaled_value(op, "value", 1)
			GameState.change_hp(healed)
			out["logs"].append("You gain +%d Health." % healed)
		"gain_max_hp":
			# The container arrives full, exactly as Health Up does (spec §3).
			var up: int = _scaled_value(op, "value", 1)
			GameState.change_max_hp(up)
			GameState.change_hp(up)
			out["logs"].append("You gain +%d Max Health." % up)
		"gain_stat":
			var stat: String = String(op.get("stat", ""))
			var amount: int = _scaled_value(op, "value", 1)
			GameState.grant_run_stat(stat, amount)
			out["logs"].append("You gain +%d %s." % [amount, _pretty_stat(stat)])
		"apply_status":
			_apply_status(op, out)
		"gain_level":
			# The character's ordinary level-up path with the condition simply not
			# consulted (§7.3, decision #7): the same stats and the same reward a
			# level always pays, so a Rare potion invents no new payout content.
			var levels: int = maxi(1, _scaled_value(op, "value", 1))
			for _i in range(levels):
				# grant_level_up needs a character to know what a level PAYS, and a
				# run without one cannot level. Read the counter rather than trusting
				# the call, so the line always follows the fact (§4.5: a dead end is
				# a fizzle, and a fizzle says so).
				var was: int = GameState.player_level
				var gained: Array = GameState.grant_level_up()
				if GameState.player_level == was:
					out["logs"].append("It fizzles — there is nothing to level up.")
					break
				out["logs"].append("You reach level %d%s." % [
					GameState.player_level,
					"" if gained.is_empty() else " — %s" % ", ".join(PackedStringArray(gained))])
		_:
			push_warning("PotionSystem: unknown quaff op '%s'" % String(op.get("op", "")))

# A status on the drinker, with the potion's clock if it authored one (§5.2).
#
# `games` RIDES STRAIGHT THROUGH to the timed layer built in step 1 — there is no
# second path for a timed stack, and adding one is the mistake that layer was
# built early to prevent. A clause with no `games` is permanent, which is what
# every apply_status written before potions already meant.
func _apply_status(op: Dictionary, out: Dictionary) -> void:
	var status: StatusData = Data.get_status(StringName(String(op.get("status", ""))))
	if status == null:
		return
	var stacks: int = _scaled_value(op, "value", 1)
	var games: int = int(op.get("games", 0))
	var applied: int = GameState.apply_status(status.id, stacks, games)
	if applied <= 0:
		return
	out["logs"].append("You gain +%d %s%s." % [
		applied, status.display_name, StatusData.clock_suffix(games)])

func _pretty_stat(stat: String) -> String:
	return stat.replace("_", " ").capitalize()

# ===========================================================================
# Throwing one (§4.2 — §4.7)
# ===========================================================================

# Throw `entry` at a square of the battlefield: identify the bottle, then apply
# its throw side around `ctx.target`. Same answer shape as the quaff, so one
# caller can spend a potion either way.
#   ctx: { "target": Vector2i, "rng": RandomNumberGenerator }
#
# THE CELL ARRIVES IN `ctx.target` AND IS NOT A REQUEST (§4.2). A request is
# fulfilled AFTER the piece resolved, and a throw has nothing to resolve until it
# knows where it landed — routing it through the request queue would mean an Echo
# Chamber replay asking for four targets after the fact. `ctx.target` carrying a
# Vector2i is the existing convention (EffectSystem._effect_cells reads exactly
# that key), so a thrown potion and an aimed Red Candle reach the ground the same
# way. The consequence, said now rather than discovered later: an ECHOED potion
# re-throws at the SAME cell, because the player aimed once and the copies land
# where the original did.
#
# IDENTIFY FIRST, ALWAYS, exactly as the quaff does — the gamble pays its
# information out even when the bottle smashes on empty ground (§4.5).
func throw_potion(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if potion == null:
		return out

	identify(potion.id)

	var target = ctx.get("target")
	if not (target is Vector2i):
		# Nowhere to land. Not reachable from the UI — the picker is the only way
		# to arm a throw — but a caller that forgot the cell should get the fizzle
		# rather than a silent no-op with the bottle already spent.
		out["logs"].append("It goes wide and smashes on nothing.")
		return out
	var cell: Vector2i = target

	var ops: Array = potion.throw
	if ops.is_empty():
		# Potion of Uselessness in both directions, and Raise Level in this one.
		# An UNKNOWN bottle can still be thrown even when it turns out to be one of
		# these — hiding the button for unknowns would leak which bottles have no
		# throw (§4.5) — so this line is a real outcome the player can buy.
		out["logs"].append("It smashes. Nothing happens.")
		return out

	var landed: bool = false
	for op in ops:
		if op is Dictionary:
			landed = _throw_one(op, cell, out) or landed
	if not landed:
		out["logs"].append("It smashes on empty ground.")
	return out

# One throw clause. Returns whether it actually DID anything, so a bottle that
# found nothing to land on can say so once at the end rather than once per clause.
#
# THE AREA RESOLVES TWICE and the two lists are not the same (§4.3): `cells` for
# the tile clause, `area_instances` — deduped bodies — for everything aimed at
# somebody. A 2x2 standing under a 3x3 throw takes the clause ONCE.
func _throw_one(op: Dictionary, cell: Vector2i, out: Dictionary) -> bool:
	var area: String = _scaled_area(op)
	var cells: Array = GameLoop2.area_cells(cell, area)
	if cells.is_empty():
		return false
	match String(op.get("op", "")):
		"apply_tile":
			return _throw_tile(op, cells, out)
		"deal_damage":
			return _throw_damage(op, cells, out)
		"apply_status":
			return _throw_status(op, cells, out)
		"grant_shield":
			return _throw_shield(op, cells, out)
		"grant_health":
			return _throw_health(op, cells, out)
		"grant_max_health":
			return _throw_max_health(op, cells, out)
		_:
			push_warning("PotionSystem: unknown throw op '%s'" % String(op.get("op", "")))
			return false

# GROUND, through the board's own tile path — so fire laid on a mine annihilates
# with it and fire laid under a body bites it on the spot, exactly as a Red
# Candle's would (§17). Counted by the cells that are CARRYING the tile
# afterwards, since a cell that took it straight back off did not catch light.
func _throw_tile(op: Dictionary, cells: Array, out: Dictionary) -> bool:
	var tile: TileEffectData = Data.get_tile(StringName(String(op.get("tile", ""))))
	if tile == null:
		return false
	var laid: int = 0
	for c in cells:
		if GameLoop2.apply_tile(c, tile.id):
			laid += 1
	if laid <= 0:
		return false
	out["logs"].append("%s covers %d square%s." % [
		tile.display_name, laid, "" if laid == 1 else "s"])
	return true

# DAMAGE, per body and NOT as a bomb (§4.4). Bodies first, then the ground: a mine
# the area covered goes up after whatever the bottle killed is already gone, which
# is the ordering §4.7 asks for and the one `_explode` already uses.
#
# The mine's blast IS a bomb — Brimstone widens it, Blood Bombs is paid by it —
# because that is what a proxy bomb is for. What stays un-upgraded is this
# clause's own damage.
func _throw_damage(op: Dictionary, cells: Array, out: Dictionary) -> bool:
	var dmg: int = maxi(1, _scaled_value(op, "value", 1))
	var hits: int = 0
	var destroyed: int = 0
	for inst in GameLoop2.area_instances(cells):
		hits += 1
		if GameLoop2.damage_enemy_instance(inst, dmg):
			destroyed += 1
	var mines: int = GameLoop2.damage_ground(cells, dmg)
	if hits > 0:
		out["logs"].append("It deals %d damage to %d enem%s%s." % [
			dmg, hits, "y" if hits == 1 else "ies",
			"" if destroyed == 0 else " — %d destroyed" % destroyed])
	if mines > 0:
		out["logs"].append("The blast sets off %d unit%s on the ground." % [
			mines, "" if mines == 1 else "s"])
	return hits > 0 or mines > 0

# A STATUS ON EVERY BODY THE AREA COVERS, with the potion's clock if it authored
# one. `games` rides straight through to the timed layer, as it does on the quaff
# side — GameLoop2.apply_status_to already takes it, and a second path for a timed
# stack is the mistake that layer was built early to prevent (§5.4).
func _throw_status(op: Dictionary, cells: Array, out: Dictionary) -> bool:
	var status: StatusData = Data.get_status(StringName(String(op.get("status", ""))))
	if status == null:
		return false
	var stacks: int = _scaled_value(op, "value", 1)
	var games: int = int(op.get("games", 0))
	var landed: int = 0
	for inst in GameLoop2.area_instances(cells):
		if GameLoop2.apply_status_to(inst, status.id, stacks, games) > 0:
			landed += 1
	if landed <= 0:
		return false
	out["logs"].append("%d enem%s gain%s +%d %s%s." % [
		landed, "y" if landed == 1 else "ies", "s" if landed == 1 else "",
		stacks, status.display_name, StatusData.clock_suffix(games)])
	return true

func _throw_shield(op: Dictionary, cells: Array, out: Dictionary) -> bool:
	var amount: int = maxi(1, _scaled_value(op, "value", 1))
	var landed: int = 0
	for inst in GameLoop2.area_instances(cells):
		if GameLoop2.grant_enemy_shield(inst, amount) > 0:
			landed += 1
	if landed <= 0:
		return false
	out["logs"].append("%d enem%s gain%s +%d Shield." % [
		landed, "y" if landed == 1 else "ies", "s" if landed == 1 else "", amount])
	return true

# HEALING A BODY, capped at its own ceiling (§4.6). Thrown at an undamaged enemy
# it is a wasted potion AND THE SCREEN SAYS SO — that sentence is the whole reason
# this reports the bodies it found separately from the Health it moved.
func _throw_health(op: Dictionary, cells: Array, out: Dictionary) -> bool:
	var amount: int = maxi(1, _scaled_value(op, "value", 1))
	var found: int = 0
	var healed: int = 0
	for inst in GameLoop2.area_instances(cells):
		found += 1
		healed += GameLoop2.grant_enemy_health(inst, amount)
	if found <= 0:
		return false
	if healed <= 0:
		out["logs"].append("It splashes over %s. It is already whole." % (
			"the enemy" if found == 1 else "them"))
		return true
	out["logs"].append("It heals %d Health across %d enem%s." % [
		healed, found, "y" if found == 1 else "ies"])
	return true

# RAISING a body's ceiling and its pool together (§4.6). A 1-Health goblin becomes
# a 3-Health goblin: three bombs, not one, and the price of a misthrown Rare
# bottle.
func _throw_max_health(op: Dictionary, cells: Array, out: Dictionary) -> bool:
	var amount: int = maxi(1, _scaled_value(op, "value", 1))
	var landed: int = 0
	for inst in GameLoop2.area_instances(cells):
		if GameLoop2.grant_enemy_max_health(inst, amount) > 0:
			landed += 1
	if landed <= 0:
		return false
	out["logs"].append("%d enem%s gain%s +%d Max Health." % [
		landed, "y" if landed == 1 else "ies", "s" if landed == 1 else "", amount])
	return true
