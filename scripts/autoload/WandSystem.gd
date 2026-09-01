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
#   * IT IS OUTSIDE ECHO CHAMBER ENTIRELY (§4.4). A wand's use never joins the
#     memory and never fires the copies, because both halves of the relic assume a
#     piece that was consumed: a wand that echoed itself would spend one charge for
#     four effects, and a wand that only FIRED the memory would be three free
#     replays of your last pill, six times over, for the price of one slot.
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

# The two concrete things a `random` wand can turn out to want, rolled per zap.
const CONCRETE_TARGETING := ["ray", "non_directional"]

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
func identify(id: StringName) -> bool:
	if id == &"" or GameState.identified_wand_types.has(id):
		return false
	GameState.identified_wand_types.append(id)
	var w: WandData = Data.get_wand(id)
	var nm: String = w.display_name if w != null else String(id)
	Notifications.notify("Identified: %s!" % nm, WAND_COLOR)
	return true

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

# Is there anything left to fire? A wand at zero is not a wand any more — it is
# consumed the moment its last charge resolves — so this is a guard against a
# stale index rather than a state the pack is ever left holding.
func has_charge(entry: Dictionary) -> bool:
	return charges_of(entry) > 0

# ===========================================================================
# Aiming (§4.2)
# ===========================================================================

# Does spending this one need a square of the board first?
#
# AN UNKNOWN WAND ALWAYS DOES, even the one that turns out to be non-directional
# and ignores the cell. The button is skipped only for a KNOWN wand that fires
# where it stands; asking only the ray-shaped unknowns to aim would tell the player
# which half of the roster a mystery stick belongs to before they had spent
# anything, which is exactly the fact the identification gamble is selling.
func needs_target(entry: Dictionary) -> bool:
	var w: WandData = data_for(entry)
	if w == null:
		return false
	return w.aims() or not is_identified(w.id)

# What this zap turns out to want. `random` rolls fresh EVERY TIME, which is Wand
# of Nothing's whole disguise: a wand that behaved identically twice running would
# announce itself as the do-nothing one before its second charge was spent.
func resolve_targeting(wand: WandData, rng: RandomNumberGenerator) -> String:
	if wand == null:
		return "non_directional"
	if wand.targeting != "random":
		return wand.targeting
	return String(CONCRETE_TARGETING[rng.randi_range(0, CONCRETE_TARGETING.size() - 1)])

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
# IDENTIFY FIRST, ALWAYS. The gamble pays its information out even when the effect
# lands on nothing (§4.5) — a Wand of Nothing that fizzled anonymously would be a
# stick the player could spend six times without ever learning it was the joke.
func zap_wand(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	var wand: WandData = data_for(entry)
	if wand == null:
		return out
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	identify(wand.id)
	notify_used(wand)

	var mode: String = resolve_targeting(wand, rng)
	var target = ctx.get("target")
	var cell = target if (target is Vector2i and mode == "ray") else null

	if wand.effect.is_empty():
		# Wand of Nothing, and it should read as the joke it is rather than as a
		# charge that reported nothing. The line does not mention the roll: which
		# way a `random` wand came up is the disguise, not the outcome.
		out["logs"].append("Nothing happens.")
		return out

	if mode == "ray" and not (cell is Vector2i):
		# A ray with nowhere to land. Not reachable from the UI — the picker is the
		# only way to arm one — but a caller that forgot the cell should get the
		# fizzle rather than a silent no-op with the charge already gone.
		out["logs"].append("The bolt goes wide and fades on nothing.")
		return out

	var landed: bool = false
	for op in wand.effect:
		if op is Dictionary:
			landed = _apply_one(op, cell, out, rng) or landed
	if not landed and out["logs"].is_empty():
		out["logs"].append("The bolt fades without finding anything.")
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

# The game a stick's material was lifted from, for the card's credit line. Empty
# once the wand is identified — from then on the wand's own `reference` is the
# credit, and the material is just the shape it arrived in.
func material_credit(entry: Dictionary) -> String:
	var wand: WandData = data_for(entry)
	if wand == null or is_identified(wand.id):
		return ""
	return material_source(material_for(wand.id))

# What the wand does, in words. The sheet's own prose once it is known, and the
# gamble line before that — with the CHARGES said either way, because how many
# times a stick can be fired is the one fact about it that is never hidden. It is
# what the player is buying a slot for, and a mystery wand you cannot count is a
# mystery about whether to carry it as well as about what it does.
func description(entry: Dictionary) -> String:
	var wand: WandData = data_for(entry)
	if wand == null:
		return ""
	var left: int = charges_of(entry)
	var counted: String = "%d charge%s left." % [left, "" if left == 1 else "s"]
	if not is_identified(wand.id):
		return "You don't know what this one does. Zapping it is how you find out. %s" % counted
	return "%s  %s" % [wand.description, counted]

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
