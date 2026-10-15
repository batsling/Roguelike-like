extends Node

# WandSystem (autoload) — the games-first (2.0) WAND brain (docs/wands-design.md).
#
# A wand is the fifth loot consumable and the first one that OUTLIVES ITS OWN USE.
# Scrolls, pills, potions and cards are each one slot for one effect: you pick the
# moment, you spend it, the slot comes back. A wand is one slot for up to six, and
# the question it asks is the other one — not "when is this worth spending" but
# "is this worth carrying", because it holds a ninth of the pack until it is empty.
#
# It is PotionSystem's shape with three differences, all of them from §4 and §6:
#
#   * THE CHARGE IS ON THE ENTRY, NOT ON THE RESOURCE. `charges_of` reads the pack
#     entry's own count and `spend_charge` writes it back, for the reason a pill's
#     dose rides on its entry: two Wands of Fire in one pack are two different
#     amounts of wand, and a count on the shared WandData would make them one.
#   * EVERY COPY ABILITY COPIES A ZAP (docs/loot-passives.md §9). It used to stand
#     outside Echo Chamber entirely, on the argument that a copied zap was extra
#     effects for one charge; that is what a copy IS, and a pill copied is extra
#     effects for one pill. The charge is spent once, by LootSystem.use_loot, and
#     never by a copy — a copy only re-runs `zap_wand`, which spends nothing.
#   * ITS ALPHABET IS 28 MATERIALS AND ITS ROSTER IS 12. Sixteen are dealt to
#     nothing — the same argument the potions' twenty-two spare vials make. The
#     ratio matters more than the count: with twelve wands and twelve materials,
#     the twelfth would be free.
#
# Identification is of the TYPE and covers every charge (§6.5). Zap an unknown
# runed wand, learn it is Wand of Fire, and the five charges left are five
# decisions rather than five gambles — which is what makes the first zap worth
# taking on a stick you know nothing about.
#
# THE COUNT IS PART OF WHAT IDENTIFYING BUYS (§6.2). An unknown stick does not say
# how many zaps are in it, on any surface: the two Legendaries carry one charge
# each and the Commons three or four, so a readable count would hand the player the
# rarity ladder for free. `LootSystem.charges_known` is the one gate every screen
# asks; `charges_of` stays the mechanical answer and does not care.
#
# Content lives in the `wands` sheet of tools/Roguelikes.xlsx, generated into
# data/wands2.0/*.tres by tools/generate_wand2_tres.py.

const WAND_COLOR := Color(0.55, 0.74, 0.86)

# The 28 sticks in images2.0/wands_unidentified/, as their file bases. A const
# list rather than a directory scan, for PotionSystem's reason: the deal has to be
# reproducible from the save (wand_material_map stores these names, not indices),
# and a file going missing should fail as one broken texture rather than as a
# silently smaller alphabet. test_wand_system.gd checks this list against the
# folder IN BOTH DIRECTIONS — art that ships without being listed is art no run can
# ever show.
const MATERIALS := [
	"Aluminum_NetHack", "Balsa_NetHack", "Brass_NetHack", "Copper_NetHack",
	"Crystal_NetHack", "Curved_NetHack", "Ebony_NetHack", "Forked_NetHack",
	"Glass_NetHack", "Hexagonal_NetHack", "Iridium_NetHack", "Iron_NetHack",
	"Jeweled_NetHack", "Long_NetHack", "Maple_NetHack", "Marble_NetHack",
	"Oak_NetHack", "Pine_NetHack", "Platinum_NetHack", "Redwood_NetHack",
	"Runed_NetHack", "Short_NetHack", "Silver_NetHack", "Spiked_NetHack",
	"Steel_NetHack", "Tin_NetHack", "Uranium_NetHack", "Zinc_NetHack",
]

# The games the sticks came from, longest first so the split below never stops at
# the wrong underscore. Every material ships from NetHack today; the list is a list
# for the reason PotionSystem's is — the moment a second set lands, a one-element
# constant would be a special case rather than a rule.
const SOURCES := ["NetHack"]

# ===========================================================================
# Reading a material's file name
# ===========================================================================

# "Oak_NetHack" -> "Oak".
func material_name(base: String) -> String:
	for src in SOURCES:
		if base.ends_with("_" + src):
			return base.substr(0, base.length() - src.length() - 1).replace("_", " ")
	return base.replace("_", " ")

# "Oak_NetHack" -> "NetHack". "" when the file is not named for a game.
func material_source(base: String) -> String:
	for src in SOURCES:
		if base.ends_with("_" + src):
			return src.replace("_", " ")
	return ""

# ===========================================================================
# The run's alphabet: which stick means which wand
# ===========================================================================

# Deal every wand a distinct material, once per run. 28 sticks and 4 wands, so 24
# are left over — six spares for every wand in the roster, which is the ratio that
# makes the last one undeducible. Learn three, and the fourth is still one of
# twenty-five things it could look like.
#
# THE DEAL IS BY MATERIAL NAME, NOT BY FILE, for the reason the potions' is: an
# unknown wand introduces itself BY that word, and two wands both answering "Oak
# Wand" would make the run log ambiguous about a mystery the player is tracking.
# No two materials share a name today; the rule is here so that adding a second
# art set cannot quietly break it.
#
# Idempotent: a run reloaded from a save already has its map and must keep it, or
# the alphabet the player spent the run learning would be redealt underneath them.
func ensure_materials() -> void:
	if not GameState.wand_material_map.is_empty():
		return
	var wands: Array = Data.all_wands()
	if wands.is_empty():
		return
	var bag: Array = MATERIALS.duplicate()
	bag.shuffle()
	var taken_names: Dictionary = {}
	var deal: Array = []
	for base in bag:
		var nm: String = material_name(base)
		if taken_names.has(nm):
			continue
		taken_names[nm] = true
		deal.append(base)
		if deal.size() >= wands.size():
			break
	if deal.size() < wands.size():
		# More wands than distinct materials — the sheet outgrew the art. Bind what
		# can be bound rather than leaving some wands materialless further down.
		push_warning("WandSystem: %d wands but only %d distinct materials"
			% [wands.size(), deal.size()])
	for i in range(wands.size()):
		if i >= deal.size():
			break
		GameState.wand_material_map[String(wands[i].id)] = deal[i]

# The stick a wand wears this run ("Oak_NetHack"), or "" if never dealt one.
func material_for(id: StringName) -> String:
	ensure_materials()
	return String(GameState.wand_material_map.get(String(id), ""))

# The wand a material means this run, or null.
func wand_for_material(base: String) -> WandData:
	ensure_materials()
	for id in GameState.wand_material_map.keys():
		if String(GameState.wand_material_map[id]) == base:
			return Data.get_wand(StringName(id))
	return null

# The sticks this run dealt to nothing — 24 of them, and the fact the whole
# identification design rests on, so a test can assert it rather than trusting the
# arithmetic.
func unused_materials() -> Array:
	ensure_materials()
	var used: Array = GameState.wand_material_map.values()
	return MATERIALS.filter(func(m): return not used.has(m))

# ===========================================================================
# Identification (the wand TYPE's, and it covers every charge)
# ===========================================================================

func is_identified(id: StringName) -> bool:
	return GameState.identified_wand_types.has(id)

# Reveals a wand for the rest of the run. Returns true if this call newly
# identified it, so callers can show a one-time toast. ONE ZAP TEACHES THE WHOLE
# STICK (§6.5): the charges left over are the reward for having gambled the first
# one, and a wand that had to be learned six times would be six gambles for the
# price of one slot, which is the opposite of what the kind is for.
# `announce` is FALSE when the caller does not yet know whether the use will land
# (see the spend paths): the type goes on the identified list straight away, so the
# effect itself can see it — Amnesia's whole trick is forgetting the name it has
# just taught — and the toast waits until the use is known to have done something.
# A use that turns out to have done nothing calls `unidentify` and no toast was
# ever shown.
func identify(id: StringName, announce: bool = true) -> bool:
	if id == &"" or GameState.identified_wand_types.has(id):
		return false
	GameState.identified_wand_types.append(id)
	if announce:
		announce_identified(id)
	return true

# The toast on its own, so a spend path can record the type now and say so
# later — see the `announce` argument above.
func announce_identified(id: StringName) -> void:
	var w: WandData = Data.get_wand(id)
	var nm: String = w.display_name if w != null else String(id)
	Notifications.notify("Identified: %s!" % nm, WAND_COLOR)

func unidentify(id: StringName) -> void:
	GameState.identified_wand_types.erase(id)

# ===========================================================================
# Charges — the one piece of runtime state a loot entry carries
# ===========================================================================

func data_for(entry: Dictionary) -> WandData:
	return Data.get_wand(StringName(entry.get("id", "")))

# What this stick has left. An entry with no `charges` key at all is read as a
# FRESH wand rather than as an empty one: a wand granted by a path that predates
# this key (an old save, a DevTools grant, a hand-written test entry) should arrive
# usable, and "the field is missing" is never the same fact as "it has been used up".
func charges_of(entry: Dictionary) -> int:
	if entry.has("charges"):
		return maxi(0, int(entry.get("charges", 0)))
	return max_charges(entry)

# What a fresh one of this type ships with — the ceiling `add_charges` clamps to,
# and the denominator the pack's "3 / 6" plate is drawn from.
func max_charges(entry: Dictionary) -> int:
	var w: WandData = data_for(entry)
	return w.starting_charges() if w != null else 1

# Spend one, IN PLACE. Returns what is left, so the caller can tell the last charge
# from every other one — which is the whole of what it has to decide (LootSystem
# keeps a wand with charges left and consumes one without).
func spend_charge(entry: Dictionary) -> int:
	var left: int = maxi(0, charges_of(entry) - 1)
	entry["charges"] = left
	return left

# Top one up, clamped to its own ceiling. Returns whether the bar actually moved,
# so a caller can tell "charged it" from "it was already full" and say the right
# thing — GameState.charge_item's contract, deliberately, because 48 Hour Energy
# reaches both through one loop (§7).
func add_charges(entry: Dictionary, amount: int) -> bool:
	if amount == 0:
		return false
	var before: int = charges_of(entry)
	var after: int = clampi(before + amount, 0, max_charges(entry))
	entry["charges"] = after
	return after != before

# ===========================================================================
# Aiming (§4.2)
# ===========================================================================

# Does spending this one need a square of the board first?
#
# WHAT A WAND AIMS AT IS PUBLIC, identified or not (the owner, Oct 2026: "let the
# player know what aim type the wand has beforehand"). A mystery stick used to
# ask for a square whatever it was, so the aiming step could not tell the player
# which half of the roster it belonged to; that secret is given up on purpose. The
# Aim is printed on every wand's card (`aim_text`), so asking for a square only
# when the wand really takes one — and fencing and previewing it by its real Aim —
# tells the player nothing the card has not. What stays hidden until the wand is
# identified is what it DOES (and so the shape it hits: see `preview_cells`).
func needs_target(entry: Dictionary) -> bool:
	var w: WandData = data_for(entry)
	return w != null and w.aims()

# THE SQUARES THE BOARD LIGHTS for a zap, and the ones it takes a click on: the
# wand's Aim, in the weapons' words (WeaponSystem.cells_for_aim) — a ray takes any
# square, since the click is only a direction.
func aim_cells(entry: Dictionary) -> Array:
	var w: WandData = data_for(entry)
	if w == null or not w.aims():
		return []
	return WeaponSystem.cells_for_aim(w.aim, w.aim_column)

# Whether the board draws this zap's ray before it is fired: every ray wand, known
# or not, since its Aim is on its card.
func previews_ray(entry: Dictionary) -> bool:
	var w: WandData = data_for(entry)
	return w != null and w.aim == "ray"

# THE SQUARES A ZAP AIMED AT `cell` WOULD COVER, for the board's preview while the
# player aims (BattlefieldView._show_swing_preview). A ray: every square its line
# strikes or stops on. A square-aimed wand: the shape its clauses cover from that
# square once the wand is IDENTIFIED — and only the square itself while it is not,
# since a 3x3 lit around the cursor would say what the stick does.
func preview_cells(entry: Dictionary, cell: Vector2i) -> Array:
	var w: WandData = data_for(entry)
	if w == null:
		return []
	if w.aim == "ray":
		var out: Array = []
		for imp in RayAim.impacts(RayAim.trace(cell, w.bounce)):
			if imp.get("cell") is Vector2i and not out.has(imp["cell"]):
				out.append(imp["cell"])
		return out
	if not is_identified(w.id):
		return [cell]
	var lit: Array = []
	for op in w.effect:
		if not (op is Dictionary) or String((op as Dictionary).get("area", "cell")).to_lower() == "board":
			continue
		for c in _cells_for(op, cell):
			if not lit.has(c):
				lit.append(c)
	if lit.is_empty():
		lit.append(cell)
	return lit

# THE AIM IN WORDS, for every wand's card and hover: "Aim: in a line from you,
# bouncing once" / "Aim: at a random enemy" / "Aim: fires where it stands".
static func aim_text(w: WandData) -> String:
	if w == null:
		return ""
	match w.aim:
		"none":
			return "Aim: none — it fires where it stands"
		"random":
			return "Aim: none — it picks a random enemy"
	return "Aim: " + WeaponSystem.aim_phrase(w.aim, w.aim_column, w.bounce)

# WHERE THIS ZAP LANDS, as RayAim's impacts — [{instance, cell}], cell null for a
# zap that is not aimed at anything:
#   ray     every enemy the line from you strikes (bounces included), or the square
#           it stopped on when it struck nobody. The board is told the path
#           (GameLoop2.last_strike) so it can draw where the bolt went.
#   none    one impact on nothing — it fires where it stands.
#   random  a random enemy on the board (WeaponSystem.random_cell), or nothing.
#   else    the square clicked.
func impacts_for(wand: WandData, target, label: String = "") -> Array:
	match wand.aim:
		"none":
			return [{"instance": 0, "cell": null}]
		"random":
			var c: Vector2i = WeaponSystem.random_cell()
			return [{"instance": 0, "cell": c if c != GameLoop2.OFF_FIELD else null}]
		"ray":
			if not (target is Vector2i):
				return []
			var path: Dictionary = RayAim.trace(target, wand.bounce)
			var hit: Array = []
			var cells: Array = []
			for h in path["hits"]:
				hit.append(int(h["instance"]))
			var landed: Array = RayAim.impacts(path)
			for imp in landed:
				cells.append(imp["cell"])
			GameLoop2.set_last_strike(label if label != "" else wand.display_name,
				[{"cells": cells, "instances": hit, "ray": (path["points"] as Array).duplicate()}])
			return landed
	if target is Vector2i:
		return [{"instance": 0, "cell": target}]
	return []

# Whether a clause is about WHERE the bolt landed, so it runs once per impact —
# against each enemy a ray struck. The rest (a pick from every item, a body called
# up, a status on the hand holding the wand, the whole board) run ONCE per zap
# however many enemies it hit.
static func _per_impact(op: Dictionary) -> bool:
	if String(op.get("area", "cell")).to_lower() == "board":
		return false
	match String(op.get("op", "")):
		"apply_tile", "deal_damage", "kill", "cancel_abilities", "grant_ability", \
				"split", "polymorph", "teleport":
			return true
		"apply_status":
			return String(op.get("target", "enemy")) != "player"
	return false

# ===========================================================================
# Rolling one as loot
# ===========================================================================

# A dropped wand: rarity-weighted through Data.roll_wand, so LUCK rides it for free
# (§16) and a Legendary stick is a Legendary stick. It arrives FULL — the charge
# count is part of what was found, and a wand that dropped half-spent would be a
# piece of loot whose value the player could not read off its card.
func roll_wand_loot(rng: RandomNumberGenerator = null) -> Dictionary:
	var wand: WandData = Data.roll_wand(rng)
	if wand == null:
		return {}
	ensure_materials()
	return {"type": "wand", "id": wand.id, "rarity": wand.rarity,
		"charges": wand.starting_charges()}

# ===========================================================================
# Zapping one
# ===========================================================================

# THE SINGLE CHOKE POINT for "a wand was zapped" (TriggerBus.wand_used), hit by
# nothing else. A wand that fizzled — Nothing, a spawn with nowhere to stand — was
# still zapped and still spent a charge, so this fires for those too.
func notify_used(wand: WandData) -> void:
	if wand == null:
		return
	TriggerBus.wand_used.emit({"wand": wand.id})

# Zap `entry`: identify the stick, then apply its effect once. Returns
# { "logs": Array[String], "requests": Array[Dictionary] } — the contract every
# other consumable answers with, so one caller can spend any of the five.
#   ctx (optional): { "rng": RandomNumberGenerator, "target": Vector2i }
#
# THE CHARGE IS NOT SPENT HERE. LootSystem spends it, for the reason it consumes
# every other kind: what happens AROUND a use — emptying a slot, or not emptying
# it — belongs to the pack rather than to the system that knows what the piece
# does. This function is what ONE charge buys, and it is called once per charge.
#
# NOTHING HAPPENED MEANS NOTHING WAS LEARNED. A zap identifies the stick only when
# the bolt actually LANDED on something — a ray fired at an empty square, and the
# Wand of Nothing whichever square it is pointed at, leave the wand exactly as
# unknown as it was.
#
# This reverses the earlier rule ("identify first, always"), and the argument for
# the reversal is what identification IS. Learning a wand is learning what it does
# by watching it do it; a charge that visibly did nothing showed the player
# nothing, so a run that wrote the name down anyway was handing over knowledge
# nobody had earned. The Wand of Nothing is the sharpest case and the reason the
# old rule existed — it can now only be learned from a Scroll of Identify, which
# is exactly right: there is no way to tell it apart from a wand aimed badly.
func zap_wand(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	var wand: WandData = data_for(entry)
	if wand == null:
		return out
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	# THE CHARGE WAS SPENT WHATEVER HAPPENS, so the relics that watch for a zap see
	# one either way. Only the IDENTIFY hangs on the bolt landing (see the header).
	notify_used(wand)

	if wand.effect.is_empty():
		# Wand of Nothing, and it should read as the joke it is rather than as a
		# charge that reported nothing.
		out["logs"].append("Nothing happens.")
		return out

	var impacts: Array = impacts_for(wand, ctx.get("target"), display_name(entry))
	if impacts.is_empty():
		# A bolt with nowhere to land: a ray that went home without touching
		# anything, or one fired with no square at all (not reachable from the UI —
		# the picker is the only way to arm one — but a caller that forgot the cell
		# should get the fizzle rather than a silent no-op with the charge gone).
		out["logs"].append("The bolt goes wide and fades on nothing.")
		return out

	# Recorded first and rolled back if the bolt finds nothing, so the ops run
	# against a run that already knows the stick — ScrollSystem.read_scroll has the
	# argument. The toast waits for the landing either way.
	var newly: bool = identify(wand.id, false)
	var landed: bool = false
	# EVERY ENEMY THE BOLT STRUCK takes the effect, a ray's bounce included; the
	# clauses that are not about where it landed run on the first impact only.
	for i in range(impacts.size()):
		var imp: Dictionary = impacts[i]
		var cell = RayAim.live_cell(imp) if imp.get("cell") is Vector2i else null
		for op in wand.effect:
			if op is Dictionary and (i == 0 or _per_impact(op)):
				landed = _apply_one(op, cell, out, rng) or landed
	if not landed:
		if out["logs"].is_empty():
			out["logs"].append("The bolt fades without finding anything.")
		if newly:
			unidentify(wand.id)
	elif newly and is_identified(wand.id):
		announce_identified(wand.id)
	return out

# One clause. Returns whether it actually DID anything, so a zap that found nothing
# to land on can say so once at the end rather than once per clause.
func _apply_one(op: Dictionary, cell, out: Dictionary,
		rng: RandomNumberGenerator) -> bool:
	match String(op.get("op", "")):
		"obtain_item":
			# The one op that resolves nowhere near this file: picking any item in
			# the game is a screen, and only whoever opened it can say what was
			# taken. Handed back as a request, exactly as a teleport is.
			out["requests"].append({"kind": "obtain_item",
				"pool": String(op.get("pool", "any"))})
			return true
		"apply_tile":
			return _zap_tile(op, cell, out)
		"apply_status":
			return _zap_status(op, cell, out)
		"deal_damage":
			return _zap_damage(op, cell, out)
		"spawn_enemy":
			return _zap_spawn(op, out, rng)
		"gain_loot":
			return _zap_loot(op, out)
		"kill", "cancel_abilities", "grant_ability", "split", "polymorph", "teleport":
			return _zap_unit(op, cell, out, rng)
		_:
			push_warning("WandSystem: unknown effect op '%s'" % String(op.get("op", "")))
			return false

# The cells one clause covers. A clause that wants the board reaches it whether or
# not the player aimed — `area=board` is not aimed at anything — and every other
# shape is measured from the square they picked, so a clause with no cell has
# nowhere to go and says so by covering nothing.
func _cells_for(op: Dictionary, cell) -> Array:
	var area: String = String(op.get("area", "cell")).to_lower()
	if area == "board":
		return GameLoop2.area_cells(Vector2i(1, 0), "board")
	if not (cell is Vector2i):
		return []
	return GameLoop2.area_cells(cell, area)

# GROUND, through the board's own tile path — so fire laid on a mine annihilates
# with it and fire laid under a body bites it on the spot, exactly as a thrown
# potion's would (§17). Counted by the cells CARRYING the tile afterwards, since a
# cell that took it straight back off did not catch light.
func _zap_tile(op: Dictionary, cell, out: Dictionary) -> bool:
	var tile: TileEffectData = Data.get_tile(StringName(String(op.get("tile", ""))))
	if tile == null:
		return false
	var laid: int = 0
	for c in _cells_for(op, cell):
		if GameLoop2.apply_tile(c, tile.id):
			laid += 1
	if laid <= 0:
		return false
	out["logs"].append("%s covers %d square%s." % [
		tile.display_name, laid, "" if laid == 1 else "s"])
	return true

# A STATUS, on the bodies the area covers or on the hand holding the wand. The two
# are the same verb pointed differently, which is why one op carries both — and the
# `games` clock rides straight through to the timed layer either way, because a
# second path for a timed stack is the mistake that layer was built early to
# prevent (§5.4).
func _zap_status(op: Dictionary, cell, out: Dictionary) -> bool:
	var status: StatusData = Data.get_status(StringName(String(op.get("status", ""))))
	if status == null:
		return false
	var stacks: int = maxi(1, int(op.get("value", 1)))
	var games: int = int(op.get("games", 0))
	if String(op.get("target", "enemy")) == "player":
		var applied: int = GameState.apply_status(status.id, stacks, games)
		if applied <= 0:
			return false
		out["logs"].append("You gain +%d %s%s." % [
			applied, status.display_name, StatusData.clock_suffix(games)])
		return true
	var landed: int = 0
	for inst in GameLoop2.area_instances(_cells_for(op, cell)):
		if GameLoop2.apply_status_to(inst, status.id, stacks, games) > 0:
			landed += 1
	if landed <= 0:
		return false
	out["logs"].append("%d enem%s gain%s +%d %s%s." % [
		landed, "y" if landed == 1 else "ies", "s" if landed == 1 else "",
		stacks, status.display_name, StatusData.clock_suffix(games)])
	return true

# DAMAGE, per body and NOT as a bomb — a bolt is not an explosion, so nothing that
# widens a blast widens this. Bodies first, then the ground, which is the ordering
# a thrown potion already uses: a mine the area covered goes up after whatever the
# bolt killed is already gone.
func _zap_damage(op: Dictionary, cell, out: Dictionary) -> bool:
	var dmg: int = maxi(1, int(op.get("value", 1)))
	var cells: Array = _cells_for(op, cell)
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
		out["logs"].append("The bolt sets off %d unit%s on the ground." % [
			mines, "" if mines == 1 else "s"])
	return hits > 0 or mines > 0

# A BODY ONTO THE BOARD, through the same path Scroll of Create Monster uses — the
# wand and the scroll conjure the same kind of thing and must not be able to
# disagree about what a conjured body is.
#
# It is the run's OWN difficulty by default, which is what makes this wand worse
# the further you get: a Negative piece of loot whose cost stayed flat while the
# roster around it climbed would stop being a cost at all.
func _zap_spawn(op: Dictionary, out: Dictionary, _rng: RandomNumberGenerator) -> bool:
	var count: int = maxi(1, int(op.get("value", 1)))
	var tag := StringName(String(op.get("tag", "")))
	var names: Array = []
	for _i in range(count):
		var enemy: GoalEnemyData = GameLoop2.roll_conjured_enemy(-1, tag)
		if enemy == null:
			break
		GameLoop2.spawn_to_stack(enemy)
		names.append(enemy.display_name)
	if names.is_empty():
		out["logs"].append("The bolt finds nothing to call up.")
		return false
	out["logs"].append("%s answers the wand." % ", ".join(PackedStringArray(names)))
	return true

# ===========================================================================
# The six verbs that aim at a UNIT (docs/wands-design.md §5.5)
# ===========================================================================

# A UNIT is anything standing on the square the bolt landed on: an enemy, a boss,
# or one of the player's own bodies (§17). Eight of the twelve wands are written
# about one, and all six of these verbs are the same shape — resolve the area to
# the units in it, do the thing to each, and say how many it found. So they are
# one function with a `match` in the middle rather than six that differ by a line.
#
# A BOSS IS A UNIT HERE, which is where these part company with the rest of the
# board (a bomb and the D10 both refuse one). What keeps a boss a boss is the
# floor in GameLoop2._damage_enemy — chip it all you like, its last point of
# Health only comes off for its goal — and Wand of Death is the one authored
# exception to that, which is what the Legendary rung and the single charge buy.
#
# ONE INSTANCE AT A TIME, RE-LOOKED-UP, because these verbs move the board under
# themselves: a kill can split a body into two more, a split adds one, a teleport
# frees the cell a queued body then walks into. `area_instances` is a snapshot
# taken before any of that, and GameLoop2 answers "no such instance" for anything
# that has since left.
func _zap_unit(op: Dictionary, cell, out: Dictionary,
		rng: RandomNumberGenerator) -> bool:
	var verb := String(op.get("op", ""))
	var landed: int = 0
	var extra: int = 0
	for inst in GameLoop2.area_instances(_cells_for(op, cell)):
		var did: bool = false
		match verb:
			"kill":
				did = GameLoop2.kill_instance(int(inst))
			"cancel_abilities":
				did = GameLoop2.cancel_abilities(int(inst))
			"grant_ability":
				did = GameLoop2.grant_ability(int(inst),
					StringName(String(op.get("ability", ""))), int(op.get("value", 0)))
			"split":
				did = GameLoop2.split_unit(int(inst)) != 0
			"polymorph":
				var became: GoalEnemyData = GameLoop2.polymorph_instance(int(inst))
				did = became != null
				if did:
					# NAMED, unlike the other five. What a body BECAME is the whole
					# outcome of a polymorph and the player cannot read it off the
					# board without knowing what was standing there a moment ago.
					out["logs"].append("It becomes %s." % became.display_name)
					extra += 1
			"teleport":
				did = GameLoop2.teleport_unit(int(inst), rng)
		if did:
			landed += 1
	if landed <= 0:
		return false
	# The polymorph line above already said it, per body.
	if extra < landed:
		out["logs"].append(UNIT_LINES.get(verb, "%d unit%s felt it.") % [
			landed, "" if landed == 1 else "s"])
	return true

# What each verb reports, in the shape the count is dropped into. Kept out of the
# match above so the sentences read together — they are the wand's voice, and six
# of them scattered through a switch is six places for one of them to drift.
const UNIT_LINES := {
	"kill": "%d unit%s dies where it stands.",
	"cancel_abilities": "%d unit%s forgets what it knew how to do.",
	"grant_ability": "%d unit%s is changed by it.",
	"split": "%d unit%s comes apart into two.",
	"teleport": "%d unit%s is somewhere else now.",
}

# More loot, OFFERED rather than granted — the pack holds nine and the run may be
# carrying eight, and `offer_loot` is the call that asks instead of silently
# swallowing the surplus (§4.3). No row uses it today; it is here because a wand
# that pays out is the obvious next row and the op is one line.
func _zap_loot(op: Dictionary, out: Dictionary) -> bool:
	var kind := String(op.get("kind", "loot"))
	var count: int = maxi(1, int(op.get("count", 1)))
	GameState.offer_loot(kind, count)
	out["logs"].append("%d more piece%s of loot." % [count, "" if count == 1 else "s"])
	return true

# ===========================================================================
# Display: names, art, words
# ===========================================================================

# What a carried wand is called. An unknown one says its MATERIAL — "Oak Wand" —
# which is the potions' rule rather than the pills': 28 sticks cannot be told apart
# in a run log any other way, and naming the wood is not naming what is in it.
func display_name(entry: Dictionary) -> String:
	var wand: WandData = data_for(entry)
	if wand == null:
		return "Wand"
	if is_identified(wand.id):
		return wand.display_name
	var base: String = material_for(wand.id)
	return "Wand" if base == "" else "%s Wand" % material_name(base)

# What the wand does, in words. The sheet's own prose once it is known, and the
# gamble line before that — with the CHARGES said only on the known half. The count
# used to be said either way; it is hidden now for the same reason the Preference
# is (§6.2), and because "one charge" is the tell that would separate the two
# Legendaries from the rest of the ladder without a zap being spent.
func description(entry: Dictionary) -> String:
	var wand: WandData = data_for(entry)
	if wand == null:
		return ""
	if not is_identified(wand.id):
		return LootSystem.UNKNOWN_TEXT
	var left: int = charges_of(entry)
	return "%s  %d charge%s left." % [wand.description, left, "" if left == 1 else "s"]

# The Preference, hidden until the stick is known — the gamble is only a gamble
# because this is hidden, exactly as it is for a scroll and a potion.
func preference(entry: Dictionary) -> String:
	var wand: WandData = data_for(entry)
	if wand == null or not is_identified(wand.id):
		return ""
	return wand.preference

# The stick. An identified wand shows its OWN art where it has any; everything else
# — unidentified, or identified with no `File`, or a `File` that does not resolve —
# shows the material the run dealt it. That last case is EVERY ROW today and it is
# the design (§6.3): the material is a real fact about that wand in that run, and
# it is the fact the player learned it by.
func art_texture(entry: Dictionary) -> Texture2D:
	var wand: WandData = data_for(entry)
	if wand == null:
		return null
	if is_identified(wand.id) and wand.art_file() != "":
		var path := "res://images2.0/wands/%s.png" % wand.art_file()
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				return tex
	return _load_stick(material_for(wand.id))

func _load_stick(base: String) -> Texture2D:
	if base == "":
		return null
	var path := "res://images2.0/wands_unidentified/%s.png" % base
	if not ResourceLoader.exists(path):
		return null
	return load(path)
