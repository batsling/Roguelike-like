extends Node

# PillSystem (autoload) — the games-first (2.0) PILL brain
# (docs/games-first-redesign.md §4.3). Pills are the scroll's identification
# minigame (§4.1) held by a COLOUR instead of by a type, which changes three
# things and leaves everything else the same shape as ScrollSystem:
#
#   * THERE IS NO MYSTERY ART. A scroll hides behind one shared Unidentified.png;
#     a pill always shows its capsule, because the capsule is the thing being
#     learned. What an unidentified pill hides is its NAME and its Preference.
#   * THE ALPHABET IS DEALT PER RUN. 13 colours on disk, 10 pills, so every run
#     binds all ten and leaves three colours meaning nothing — which is what stops
#     the tenth pill from being deducible once the other nine are known.
#   * EVERY PILL IS TWO DOSES. A drop rolls HORSE_CHANCE to arrive oversized and
#     read the row's horse_effect instead. The roll belongs to the piece of loot,
#     not to the type, so one colour can be carried both ways at once — and
#     identification is the COLOUR's, so learning either dose learns both.
#
# Taking a pill identifies its colour (learn-by-use) and applies one dose's ops.
# Ops that mutate the run resolve here; ops that need overworld movement come back
# as `requests` for the calling UI to fulfil, exactly as ScrollSystem's do.
#
# Content lives in the `pills2.0` sheet of tools/Roguelikes.xlsx, generated into
# data/pills2.0/*.tres by tools/generate_pill2_tres.py.

const PILL_COLOR := Color(0.45, 0.78, 0.55)

# The 13 capsules in images2.0/pills/. A const list rather than a directory scan:
# the deal has to be reproducible from the save (pill_color_map stores names, not
# indices), and a colour going missing from disk should fail as one broken texture
# rather than as a silently smaller alphabet. test_pill_system.gd checks the list
# against the folder, so adding art without adding it here is caught.
const COLORS := [
	"BlackYellow", "BlueBlue", "BlueCyan", "OrangeOrange", "PinkRed",
	"RedSpecled", "SpottedWhiteWhite", "WhiteBlack", "WhiteBlue", "WhiteCyan",
	"WhiteWhite", "WhiteYellow", "YellowOrange",
]

# The chance a dropped pill arrives as the horse dose (§4.3).
const HORSE_CHANCE := 0.05

# ===========================================================================
# The run's alphabet: which colour means which pill
# ===========================================================================

# Deal every pill a distinct colour, once per run. There are more colours than
# pills, so the leftovers are exactly the "sitting out" set — nothing has to
# choose them, they are what is left when all ten are bound.
#
# Idempotent: a run reloaded from a save already has its map and must keep it, or
# the alphabet the player spent the run learning would be redealt underneath them.
func ensure_colors() -> void:
	if not GameState.pill_color_map.is_empty():
		return
	var pills: Array = Data.all_pills()
	if pills.is_empty():
		return
	var bag: Array = COLORS.duplicate()
	bag.shuffle()
	if bag.size() < pills.size():
		# More pills than capsules — the sheet outgrew the art. Bind what can be
		# bound rather than leaving some pills colourless further down the call.
		push_warning("PillSystem: %d pills but only %d colours" % [pills.size(), bag.size()])
	for i in range(pills.size()):
		if i >= bag.size():
			break
		GameState.pill_color_map[String(pills[i].id)] = bag[i]

# The art base a pill wears this run ("BlueCyan"), or "" if it was never dealt one.
func color_for(id: StringName) -> String:
	ensure_colors()
	return String(GameState.pill_color_map.get(String(id), ""))

# The pill a colour means this run, or null. The reverse lookup the loot window's
# tooltip uses when it wants to say what a known capsule is without holding one.
func pill_for_color(color: String) -> PillData:
	ensure_colors()
	for id in GameState.pill_color_map.keys():
		if String(GameState.pill_color_map[id]) == color:
			return Data.get_pill(StringName(id))
	return null

# The colours this run dealt to nothing. Not used by the game — a pill can only
# drop as one of the ten — but it is the fact the design rests on, so a test can
# assert it rather than trusting the arithmetic.
func unused_colors() -> Array:
	ensure_colors()
	var used: Array = GameState.pill_color_map.values()
	return COLORS.filter(func(c): return not used.has(c))

# ===========================================================================
# Identification (the colour's, not the dose's)
# ===========================================================================

func is_identified(id: StringName) -> bool:
	return GameState.identified_pill_types.has(id)

# Reveals a pill's colour for the rest of the run. Returns true if this call newly
# identified it, so callers can show a one-time toast. Both doses are covered:
# a horse pill is the same capsule at a bigger size, and learning one and not the
# other would mean the player who took the rare dose knows less than the one who
# took the common one.
func identify(id: StringName) -> bool:
	if id == &"" or GameState.identified_pill_types.has(id):
		return false
	GameState.identified_pill_types.append(id)
	var p: PillData = Data.get_pill(id)
	var nm: String = p.display_name if p != null else String(id)
	Notifications.notify("Identified: %s!" % nm, PILL_COLOR)
	return true

func unidentify(id: StringName) -> void:
	GameState.identified_pill_types.erase(id)

# ===========================================================================
# Display: names, art
# ===========================================================================

# What a carried pill is called. An unknown capsule says only what it looks like;
# a known one says what it is, and the horse dose says so out loud because the
# oversized art is the one thing the player can always read off the tile.
#
# BAD TRIP NAMES ITSELF FROM YOUR HEALTH (§4.3): a dose that would take the last
# Health heals to full instead, so an identified Bad Trip reads "Full Health"
# while you are in death range and "Bad Trip" the rest of the time. The label
# follows what the pill would DO right now, which is why two colours can both
# claim to be Full Health — and why this cannot be a stored name.
func display_name(entry: Dictionary) -> String:
	var horse: bool = bool(entry.get("horse", false))
	var pill: PillData = Data.get_pill(StringName(entry.get("id", "")))
	if pill == null:
		return "Horse Pill" if horse else "Pill"
	if not is_identified(pill.id):
		return "Unidentified Horse Pill" if horse else "Unidentified Pill"
	var nm: String = pill.display_name
	if would_save_you(pill, horse):
		var swap: PillData = Data.get_pill(&"full_health")
		if swap != null:
			nm = swap.display_name
	return "Horse %s" % nm if horse else nm

# The line an identified pill's card shows for the dose being held, with the same
# health-dependent swap the name gets — a card promising −4 Health beside a name
# that says Full Health would be describing a different pill.
func description(entry: Dictionary) -> String:
	var horse: bool = bool(entry.get("horse", false))
	var pill: PillData = Data.get_pill(StringName(entry.get("id", "")))
	if pill == null:
		return ""
	if not is_identified(pill.id):
		return "You don't know what this one does. Taking it is how you find out."
	if would_save_you(pill, horse):
		return "It would kill you, so it does the opposite: heal to full health."
	return pill.line(horse)

# The Preference, or "" while the colour is unknown — the gamble is only a gamble
# because this is hidden, exactly as it is for a scroll.
func preference(entry: Dictionary) -> String:
	var pill: PillData = Data.get_pill(StringName(entry.get("id", "")))
	if pill == null or not is_identified(pill.id):
		return ""
	return pill.preference

# Would this dose, taken right now, kill the player — and therefore heal them to
# full instead? Reads the dose's own `lethal=` op (Bad Trip's, and only its), so
# the horse dose's bigger number moves the threshold with it.
func would_save_you(pill: PillData, horse: bool) -> bool:
	if pill == null:
		return false
	for op in pill.ops(horse):
		if not (op is Dictionary):
			continue
		if String(op.get("op", "")) != "lose_hp":
			continue
		if String(op.get("lethal", "")) != "heal_full":
			continue
		if GameState.hp <= _scaled_value(op, "value", 1):
			return true
	return false

# The capsule. Always the colour's own art, identified or not — the whole point of
# a pill is that you can see it and not know it. Falls back to the normal dose's
# art when a horse file is missing, and to null when the colour is unknown, which
# only a pill that was never dealt one can be.
func art_texture(entry: Dictionary) -> Texture2D:
	var color: String = color_for(StringName(entry.get("id", "")))
	if color == "":
		return null
	if bool(entry.get("horse", false)):
		var horse_tex: Texture2D = _load_color("%sHorse" % color)
		if horse_tex != null:
			return horse_tex
	return _load_color(color)

func _load_color(base: String) -> Texture2D:
	var path := "res://images2.0/pills/%s.png" % base
	if not ResourceLoader.exists(path):
		return null
	return load(path)

# HOW MUCH BIGGER THIS DOSE DRAWS THAN A NORMAL ONE (§4.3).
#
# "Because the art is visibly oversized, the player always knows a horse pill is a
# horse pill" — which was not true of anything on screen. Every surface drew loot
# through UITheme.crisp_tex, which fits the art to a FIXED box (34 in the window,
# 72 on the drop, 96 on the use), and a box that does not care how big the source
# is renders a 19px capsule and a 25px one at exactly the same size. The one tell
# the design promises was being scaled away by the thing drawing it.
#
# So the box takes its size from the art instead: the horse dose's own file is
# ~1.3x the normal dose's, and this returns that ratio for the caller to scale by.
# MEASURED rather than hardcoded, so redrawing the horse art bigger makes it draw
# bigger — the alternative is a constant that silently stops matching the pictures.
# Falls back to 1.0 for anything that isn't a horse dose, or whose pair can't be
# measured (a colour with no horse file already falls back to the normal art).
func art_scale(entry: Dictionary) -> float:
	if not bool(entry.get("horse", false)):
		return 1.0
	var color: String = color_for(StringName(entry.get("id", "")))
	if color == "":
		return 1.0
	var horse: Texture2D = _load_color("%sHorse" % color)
	var normal: Texture2D = _load_color(color)
	if horse == null or normal == null or normal.get_height() <= 0:
		return 1.0
	return maxf(1.0, float(horse.get_height()) / float(normal.get_height()))

# ===========================================================================
# Rolling one as loot
# ===========================================================================

# A dropped pill: a flat pick over the catalog, then the 5% horse roll. Flat
# because a pill has no rarity (§4.3) — it is one of the ten the run dealt, and
# weighting them would mean a colour the player never sees is a colour they can
# never learn. Returns {} when no pills are loaded.
func roll_pill_loot(rng: RandomNumberGenerator = null) -> Dictionary:
	var pills: Array = Data.all_pills()
	if pills.is_empty():
		return {}
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	ensure_colors()
	var pill: PillData = pills[r.randi_range(0, pills.size() - 1)]
	return {"type": "pill", "id": pill.id, "horse": r.randf() < HORSE_CHANCE}

# ===========================================================================
# Taking one
# ===========================================================================

# Take `entry` ({type, id, horse}): identify its colour, then apply the dose.
# Returns { "logs": Array[String], "requests": Array[Dictionary] } — the same
# contract ScrollSystem.read_scroll answers with, so one caller can spend either.
#   ctx (optional): { "rng": RandomNumberGenerator }
func take_pill(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	var pill: PillData = Data.get_pill(StringName(entry.get("id", "")))
	if pill == null:
		return out
	var horse: bool = bool(entry.get("horse", false))
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	# LEARN-BY-USE, AND LEARN THE TRUTH. This happens before any reroll or swap,
	# and it records the pill that was actually in the capsule — Lucky Foot changes
	# the outcome, never the fact (§4.3). A version that identified what you GOT
	# would start lying to the player the moment the relic left the pack.
	identify(pill.id)

	var ops: Array = pill.ops(horse)
	if GameState.pills_reroll_positive() and pill.is_negative():
		var lucky: PillData = _reroll_positive(pill, rng)
		if lucky != null:
			# The horse dose rerolls into the OTHER pill's horse dose: the size of
			# the capsule is what you were handed, and the Foot is not holding a
			# smaller one.
			ops = lucky.ops(horse)
			out["logs"].append("Lucky Foot turns it into %s%s." % [
				"Horse " if horse else "", lucky.display_name])
	elif would_save_you(pill, horse):
		ops = [{"op": "heal_full"}]

	for op in ops:
		if op is Dictionary:
			_apply_one(op, out, rng)
	return out

# Lucky Foot's pool: every Positive pill, INCLUDING the ones whose colours are
# sitting out this run. It rolls over pills rather than over what dropped, so the
# Foot can hand you a pill no capsule in this run means — which is the only reading
# that doesn't make the relic weaker in a run that happened to bench the good ones.
func _reroll_positive(_from: PillData, rng: RandomNumberGenerator) -> PillData:
	var pool: Array = Data.pills_with_preference("Positive")
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]

# ===========================================================================
# The ops
# ===========================================================================

# Which of an op's numbers Sacred Bark's "double the effect" actually doubles
# (§8), named per op exactly as ScrollSystem's table is. A teleport's `spread` is
# absent for the same reason it is there: doubling how far a landing may VARY is
# not twice the pill, it is a worse one. `add_curse` scales its count, so a
# doubled Amnesia is two curses rather than one bigger nothing.
const LOOT_SCALED_FIELDS := {
	"gain_stat": ["value"],
	"lose_stat": ["value"],
	"gain_hp": ["value"],
	"gain_max_hp": ["value"],
	"lose_max_hp": ["value"],
	"lose_hp": ["value"],
	"charge": ["count"],
	"forget": ["count"],
	"add_curse": ["count"],
}

# One field of an op as it resolves for THIS player, Sacred Bark folded in.
func _scaled_value(op: Dictionary, field: String, fallback: int) -> int:
	var raw: int = int(op.get(field, fallback))
	var fields: Array = LOOT_SCALED_FIELDS.get(String(op.get("op", "")), [])
	if not fields.has(field):
		return raw
	var mult: int = GameState.loot_multiplier()
	if mult <= 1:
		return raw
	# A field the pill never authored takes its own default times the multiplier,
	# which is what "doubled" means for a count nobody wrote down.
	return maxi(1, raw) * mult

func _apply_one(op: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var verb := String(op.get("op", ""))
	match verb:
		"gain_stat", "lose_stat":
			_apply_stat(op, verb == "lose_stat", out)
		"gain_hp":
			var healed: int = _scaled_value(op, "value", 1)
			GameState.change_hp(healed)
			out["logs"].append("You gain +%d Health." % healed)
		"gain_max_hp":
			# Raising the cap heals by the same amount (§3) — the container arrives
			# full, which is what makes Health Up worth taking at full Health.
			var up: int = _scaled_value(op, "value", 1)
			GameState.change_max_hp(up)
			GameState.change_hp(up)
			out["logs"].append("You gain +%d Max Health." % up)
		"lose_max_hp":
			# The deliberate NON-mirror (§3): the room goes, the Health stays, and
			# only moves when it no longer fits.
			var down: int = _scaled_value(op, "value", 1)
			GameState.set_max_hp(maxi(1, GameState.max_hp - down), false)
			out["logs"].append("You lose %d Max Health." % down)
		"lose_hp":
			var dmg: int = _scaled_value(op, "value", 1)
			GameState.change_hp(-dmg)
			out["logs"].append("You lose %d Health." % dmg)
		"heal_full":
			GameState.set_hp(GameState.max_hp)
			out["logs"].append("You are healed to full.")
		"add_curse":
			_add_curses(op, out, rng)
		"forget":
			_forget(op, out, rng)
		"charge":
			_charge(op, out, rng)
		"teleport":
			# Telepills — movement belongs to the overworld, so it comes back as a
			# request the way a scroll's does rather than reaching into the map here.
			var req := {"kind": "teleport", "dir": String(op.get("dir", "same"))}
			if req["dir"] == "amulet":
				req["min"] = int(op.get("min", 1))
				req["max"] = int(op.get("max", 3))
			else:
				req["spread"] = int(op.get("spread", 1))
			out["requests"].append(req)
		_:
			push_warning("PillSystem: unknown effect op '%s'" % verb)

# --- gain_stat / lose_stat --------------------------------------------------
# Both directions of the same verb, so Luck Up and Luck Down cannot drift apart.
# `bonus_shields` is the one stat here that is not an ordinary run stat: it is the
# pool that does not expire (§4.3), and it is granted through the same path so a
# pill has no privileged way to reach it that an item wouldn't have.
func _apply_stat(op: Dictionary, negative: bool, out: Dictionary) -> void:
	var stat: String = String(op.get("stat", ""))
	if stat == "":
		return
	var amount: int = _scaled_value(op, "value", 1)
	if amount == 0:
		return
	GameState.grant_run_stat(stat, -amount if negative else amount)
	# The sign belongs to the NUMBER, not to the verb. Splitting the format three
	# ways put a space between them — "You gain + 1 Luck." — which nobody caught
	# while these lines only ever went to the run log, and which is the first thing
	# you read on the screen that now says what a pill did.
	out["logs"].append("You %s %s." % [
		"lose %d" % amount if negative else "gain +%d" % amount, _pretty(stat)])

func _pretty(stat: String) -> String:
	return stat.capitalize()

# --- add_curse (Amnesia) ----------------------------------------------------
# A curse GOAL (§5): a row on the post-game checklist you are trying not to
# complete. `random` picks from the whole authored set each time rather than once
# and repeated, so a doubled Amnesia is two DIFFERENT curses where it can be.
func _add_curses(op: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var count: int = maxi(1, _scaled_value(op, "count", 1))
	var named := StringName(String(op.get("curse", "random")))
	var taken: Array = []
	for _i in range(count):
		var id: StringName = named
		if named == &"random":
			var pool: Array = Data.all_curses2().filter(
				func(c): return c != null and not taken.has(c.id))
			if pool.is_empty():
				pool = Data.all_curses2()
			if pool.is_empty():
				break
			id = pool[rng.randi_range(0, pool.size() - 1)].id
		if GameState.add_curse_goal(id):
			taken.append(id)
	if taken.is_empty():
		out["logs"].append("Nothing sticks.")
		return
	var names: Array = []
	for id in taken:
		var cd = Data.get_curse2(id)
		names.append(cd.display_name if cd != null else String(id))
	out["logs"].append("You are cursed: %s." % ", ".join(PackedStringArray(names)))

# --- forget (horse Amnesia) -------------------------------------------------
# Forgetting is per-KIND so the sheet can say "scroll", "pill" or — the horse
# dose's word — "loot", which is both. A count of -1 is everything.
#
# WHAT IT DOES NOT DO IS REDEAL THE COLOURS. The capsule still means what it
# meant; you have merely stopped knowing it, and taking one is how you find out
# again. Redealing would make the pill unlearnable rather than forgotten.
#
# THE PILL BEING SWALLOWED IS NOT SPARED. Amnesia's horse dose wipes every
# identified piece of loot, and "every" includes the lesson taking it just taught:
# the dose that erases the run's knowledge erases its own name with it. So the
# horse dose can never leave itself known — its colour is learned from the NORMAL
# dose, which forgets a curse's worth of other things and not this.
#
# THE FORGETTING ITSELF IS LootSystem's, shared with the scroll Amnesia, which now
# asks for the same `forget loot` this dose always did (§10). One difference the
# move corrects: a `loot` forget used to run the count against EACH alphabet in
# turn, so "forget 1" forgot one scroll AND one pill. It forgets one thing now,
# drawn from everything known — which is what the sheet's "1 random Identified
# Loot" says, and what a horse `all` meant either way.
func _forget(op: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind: String = String(op.get("kind", "loot")).to_lower()
	var count: int = int(op.get("count", 1))
	if count > 0:
		count = _scaled_value(op, "count", 1)
	var forgot: int = LootSystem.forget_identified(kind, count, rng)
	if forgot <= 0:
		out["logs"].append("You have no loot knowledge to forget.")
		return
	out["logs"].append("You forget what %d %s do%s." % [
		forgot, "thing" if forgot == 1 else "things", "es" if forgot == 1 else ""])

# --- charge (48 Hour Energy) ------------------------------------------------
# Three SEPARATE charges, each landing on a random chargeable relic — so two can
# land on the same one, and a run holding a single D6 gets its bar filled rather
# than two of the three charges evaporating. The horse dose instead picks `count`
# DISTINCT relics and tops each all the way up, which is why `full` walks a
# without-replacement list.
#
# A pack with nothing chargeable in it says so. Reading it into an empty pack is a
# wasted pill, and the log is the only place the player finds that out — the same
# rule ScrollSystem follows for Aggravate Monsters in an empty room.
func _charge(op: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var pool: Array = GameState.chargeable_items()
	if pool.is_empty():
		out["logs"].append("Nothing in the pack takes a charge.")
		return
	var count: int = maxi(1, _scaled_value(op, "count", 1))
	var full: bool = bool(op.get("full", false))
	var touched: Array = []
	if full:
		var bag: Array = pool.duplicate()
		for _i in range(mini(count, bag.size())):
			var idx: int = rng.randi_range(0, bag.size() - 1)
			var it: ItemData = bag[idx]
			bag.remove_at(idx)
			if GameState.charge_item(it, it.max_charge()) and not touched.has(it.display_name):
				touched.append(it.display_name)
	else:
		for _i in range(count):
			var it: ItemData = pool[rng.randi_range(0, pool.size() - 1)]
			if GameState.charge_item(it, 1) and not touched.has(it.display_name):
				touched.append(it.display_name)
	if touched.is_empty():
		out["logs"].append("Everything in the pack is already charged.")
		return
	out["logs"].append("%s %s charged." % [
		", ".join(PackedStringArray(touched)), "is" if touched.size() == 1 else "are"])
