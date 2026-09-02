extends Node

# ScrollSystem (autoload) — the games-first (2.0) SCROLL brain
# (docs/games-first-redesign.md §4.1). Scrolls are the run's consumable-with-an-
# identity: they arrive UNIDENTIFIED and carry a Preference (Positive / Negative
# / Neutral) that colours whether reading a mystery scroll is a gamble. This
# mirrors PotionSystem's identification pattern:
#   * identification state (global per scroll type, stored on GameState)
#   * art / display-name resolution for identified vs. unidentified scrolls
#   * a single-effect applier (no combat dice, no outcome tiers)
#
# Reading a scroll identifies its type (learn-by-use) and then applies its one
# authored effect. Effects that mutate the run immediately (aggravate, amnesia,
# create-monster) do so here; effects that need a player CHOICE (which scroll to
# identify, which following enemy to Stun) or overworld movement (teleport) are
# returned as `requests` for the calling UI (ScrollReadModal) to fulfil — keeping
# this autoload free of scene/UI coupling, the same way PotionSystem leaves
# targeting to its callers.
#
# Content lives in the `scrolls2.0` sheet of tools/Roguelikes.xlsx, generated into
# data/scrolls2.0/*.tres (each carries `preference` + a structured `effect` array).

const SCROLL_COLOR := Color(0.61, 0.35, 0.71)

# ===========================================================================
# The run's alphabet: what an unread scroll calls itself
# ===========================================================================
#
# THE SCROLL'S MASK IS ITS NAME, where a potion's is a bottle colour and a pill's
# is a capsule (§4.1). Every unidentified scroll wears the same parchment — there
# is no per-scroll mystery art and there should not be, because a scroll is a
# sheet of paper with writing on it — so the writing is the tell. Until you read
# one, a scroll is "ZELGO MER" or "ah bloto festr": a title that means nothing,
# is the same title all run, and means something else entirely in the next run.
#
# This is the thing the pack was missing. Nine slots of "Unidentified Scroll" is
# not an inventory, it is a row of identical unknowns, and the Identify picker
# had to spoil the real names outright just to be a choice at all (see
# LootSystem.pick_label). A dealt title makes the unknowns TELLABLE APART without
# telling you a thing about any of them, which is the whole trick every roguelike
# this one is built out of plays with its scrolls.
#
# The bag is data/scroll_names.tres, generated from the two right-hand columns of
# the `scrolls2.0` sheet (tools/generate_scroll2_tres.py).
const NAMES_PATH := "res://data/scroll_names.tres"

# How many syllables an assembled label is built from, inclusive. The sheet's
# parts are short — "ah", "zep", "snorf" — so two is already a name and five is
# still readable in a pack slot.
const PARTS_MIN := 2
const PARTS_MAX := 5

# Loaded once and shared. `load` rather than `preload` so a missing book is a
# null to fall back from rather than a parse error taking the autoload down with
# it — the generator has to have been run, and a checkout that hasn't run it
# should still boot.
var _names_book: ScrollNames = null

func _name_book() -> ScrollNames:
	if _names_book == null and ResourceLoader.exists(NAMES_PATH):
		_names_book = load(NAMES_PATH)
	return _names_book

# Deal every scroll a distinct meaningless title, once per run.
#
# A COIN PER SCROLL, which is what the design asks for: half the roster wears one
# of the sheet's authored whole names, half wears 2-5 syllables joined with
# spaces. The two halves look alike in a pack slot and are meant to — the player
# has no way to tell an authored label from an assembled one, so neither carries
# information about the scroll behind it.
#
# EVERY LABEL IS DISTINCT, and that is load-bearing rather than tidy: two scrolls
# both answering to "TEMOV" would make the run log ambiguous about the exact
# mystery the player is being asked to track. Whole names come out of a shuffled
# bag so they cannot repeat; an assembled label is rerolled if it collides, and
# falls back to the other kind if it somehow cannot find a free one.
#
# Idempotent: a run reloaded from a save already has its titles and must keep
# them, or the alphabet the player spent the run learning would be redealt
# underneath them (the same rule PotionSystem.ensure_colors follows).
func ensure_names() -> void:
	if not GameState.scroll_name_map.is_empty():
		return
	var book: ScrollNames = _name_book()
	if book == null or book.is_empty():
		return
	var scrolls: Array = Data.all_scrolls()
	if scrolls.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# The whole-name bag, shuffled and drawn from — never sampled with
	# replacement, which is how a 35-name bag still manages to deal a duplicate.
	var bag: Array = Array(book.names)
	bag.shuffle()
	var taken: Dictionary = {}
	for scroll in scrolls:
		if not (scroll is ScrollData):
			continue
		var label: String = ""
		# The coin. Whole name on heads — if the bag still has one — assembled on
		# tails. A bag that runs dry falls through to the assembled side rather
		# than leaving a scroll nameless: the parts can always make one more.
		if rng.randf() < 0.5 and not bag.is_empty():
			label = String(bag.pop_back())
		else:
			label = _assemble_label(book, rng, taken)
			# Nothing free came back from the syllables (a tiny parts list, or a
			# very unlucky run of collisions) — take a whole name instead.
			if label == "" and not bag.is_empty():
				label = String(bag.pop_back())
		if label == "" or taken.has(label):
			continue
		taken[label] = true
		GameState.scroll_name_map[String(scroll.id)] = label

# One assembled label: PARTS_MIN..PARTS_MAX syllables joined with spaces, drawn
# WITHOUT replacement inside the one label so it doesn't read "foo foo zep".
# Returns "" if it cannot find a label nothing else is already using.
func _assemble_label(book: ScrollNames, rng: RandomNumberGenerator,
		taken: Dictionary) -> String:
	if book.parts.is_empty():
		return ""
	for _attempt in range(24):
		var pool: Array = Array(book.parts)
		pool.shuffle()
		var count: int = mini(rng.randi_range(PARTS_MIN, PARTS_MAX), pool.size())
		var label: String = " ".join(PackedStringArray(pool.slice(0, count)))
		if not taken.has(label):
			return label
	return ""

# The title a scroll wears this run, or "" if it was never dealt one (an empty or
# missing name book — see display_name, which falls back to the flat wording).
func name_for(id: StringName) -> String:
	ensure_names()
	return String(GameState.scroll_name_map.get(String(id), ""))

# The scroll a title means this run, or null. The inverse of name_for, for the
# same reason PotionSystem has potion_for_color: the label is what the player
# talks about, so something has to be able to look one up.
func scroll_for_name(label: String) -> ScrollData:
	ensure_names()
	for id in GameState.scroll_name_map.keys():
		if String(GameState.scroll_name_map[id]) == label:
			return Data.get_scroll(StringName(id))
	return null

# Where a dealt title came from — "NetHack", "Rogue", "WazHack" — for the card
# that credits it, the way a potion's vial credits the game that named it. An
# ASSEMBLED label is credited to whichever game authored its syllables, read off
# the first one, since the sheet's parts are all one game's.
func name_source(label: String) -> String:
	var book: ScrollNames = _name_book()
	if book == null or label == "":
		return ""
	var whole: String = book.source_for_name(label)
	if whole != "":
		return whole
	var first: String = label.split(" ")[0]
	return book.source_for_part(first)

# ===========================================================================
# Identification (mirrors PotionSystem)
# ===========================================================================

func is_identified(id: StringName) -> bool:
	return GameState.identified_scroll_types.has(id)

# Reveals a scroll type for the rest of the run. Returns true if this call newly
# identified it (so callers can show a one-time toast).
# `announce` is FALSE when the caller does not yet know whether the read will land
# (see read_scroll): the type goes on the identified list straight away, so the
# effect itself can see it — Amnesia's whole trick is forgetting the name it has
# just taught — and the toast waits until the read is known to have done something.
# A read that turns out to have done nothing calls `unidentify` and no toast was
# ever shown.
func identify(id: StringName, announce: bool = true) -> bool:
	if id == &"" or GameState.identified_scroll_types.has(id):
		return false
	# The mask is read BEFORE the type goes on the identified list, because that
	# append is what stops it being a mask. Kept even when the toast is deferred:
	# by the time `announce_identified` runs, `name_for` would answer with the real
	# name and the sentence would read "Scroll of Fire is Scroll of Fire!".
	var mask: String = name_for(id)
	GameState.identified_scroll_types.append(id)
	if announce:
		_say_identified(id, mask)
	else:
		_deferred_masks[id] = mask
	return true

# The masks held back by a deferred identify, so the toast can still be the
# sentence the player has been waiting for once the read is known to have landed.
var _deferred_masks: Dictionary = {}

func announce_identified(id: StringName) -> void:
	_say_identified(id, String(_deferred_masks.get(id, "")))
	_deferred_masks.erase(id)

# NAMED AS THE ANSWER TO A QUESTION, where the run dealt one: "ZELGO MER is
# Scroll of Fire!" is the sentence the player has been waiting for, and it is
# also the one that teaches them to read the OTHER ZELGO MER in their pack.
# Without the mask half it says only what this piece was, which is the smaller
# fact — identification is of the type.
func _say_identified(id: StringName, mask: String) -> void:
	var s: ScrollData = Data.get_scroll(id)
	var nm: String = s.display_name if s != null else String(id)
	if mask != "":
		Notifications.notify("%s is %s!" % [mask, nm], SCROLL_COLOR)
	else:
		Notifications.notify("Identified: %s!" % nm, SCROLL_COLOR)

func unidentify(id: StringName) -> void:
	GameState.identified_scroll_types.erase(id)

# ===========================================================================
# Display: names, art
# ===========================================================================

# What a scroll is CALLED right now: its real name once read, and this run's
# dealt title until then ("ZELGO MER", "ah bloto festr").
#
# The flat "Unidentified Scroll" survives as the fallback and only that: it is
# what a scroll reads as when the name book is missing or empty (a checkout where
# the generator has not been run). Every scroll answering to the same string is
# the behaviour this replaced, so it is the last resort rather than a second
# supported look.
func display_name(scroll: ScrollData) -> String:
	if scroll == null:
		return "Scroll"
	if is_identified(scroll.id):
		return scroll.display_name
	var label: String = name_for(scroll.id)
	return label if label != "" else "Unidentified Scroll"

# The same title, but only ever the MASK — never the real name, whether or not
# the scroll has been identified. `display_name` flips to the real name the moment
# a scroll is read, and this is what still answers afterwards: the title it WAS
# wearing. "" when the run never dealt one.
#
# The identify toast is the caller today ("ZELGO MER is Scroll of Fire!"). It is
# also what a "known this run" fold would quote to list the pairs the player has
# worked out — LootDiscoveries names identified scrolls outright and does not use
# this yet.
func mask_name(scroll: ScrollData) -> String:
	if scroll == null:
		return ""
	return name_for(scroll.id)

# The shared mystery-scroll art (§4.1/§10.1). preload (not a runtime load) so
# Godot always imports it — it isn't referenced by any .tres, so a plain load
# could miss it when the editor hasn't scanned the folder.
const UNIDENTIFIED_TEX: Texture2D = preload("res://images2.0/scrolls/Unidentified.png")

# Texture for a scroll: its real art once identified, else the shared mystery
# scroll. Never returns null — an identified scroll with no art file (blank File,
# or a file that doesn't resolve) ALSO falls back to the Unidentified art (§4.1),
# so callers never get a null/broken texture.
func art_texture(scroll: ScrollData) -> Texture2D:
	if scroll != null and is_identified(scroll.id) and scroll.art_file() != "":
		var path := "res://images2.0/scrolls/%s.png" % scroll.art_file()
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				return tex
	return UNIDENTIFIED_TEX

# ===========================================================================
# Reading a scroll
# ===========================================================================

# Read `scroll`: identify its type (learn-by-use), then apply its authored effect.
# Non-interactive effects mutate GameState / GameLoop2 immediately; effects that
# need a player choice or overworld movement are collected into `requests` for the
# caller to fulfil (see the fulfilment helpers below).
# Returns { "logs": Array[String], "requests": Array[Dictionary] }.
#   ctx (optional): { "rng": RandomNumberGenerator }
func read_scroll(scroll: ScrollData, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	if scroll == null:
		return out
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	# LEARN-BY-USE, AND ONLY WHEN THERE WAS SOMETHING TO LEARN FROM. A scroll read
	# to no effect at all — an Identify with nothing unidentified in the pack, a
	# Remove Curse with nothing weighing on you, an Aggravate Monsters read into an
	# empty room — showed the reader nothing, so the title on it stays a mystery.
	# See WandSystem.zap_wand for the argument this rule is one half of.
	#
	# RECORDED FIRST AND ROLLED BACK, rather than simply deferred to the end: the
	# ops have to run against a run that already knows this scroll, or Amnesia would
	# stop forgetting the name it just taught (§10) — which is the one thing that
	# rule is for. The toast is what waits (see `identify`), so a read that fizzles
	# announces nothing and puts the mask straight back.
	var newly: bool = identify(scroll.id, false)
	var landed: bool = false
	for effect in scroll.effect:
		if effect is Dictionary:
			landed = _apply_one(effect, out, rng) or landed
	if not landed:
		if newly:
			unidentify(scroll.id)
			_deferred_masks.erase(scroll.id)
	elif newly and is_identified(scroll.id):
		# `is_identified` because the read may have forgotten it again on purpose —
		# Amnesia takes its own name with it, and a toast for a name the run no
		# longer holds would be the scroll lying about what it did.
		announce_identified(scroll.id)
	return out

# Which of an op's numbers Sacred Bark's "double the effect" actually doubles.
# Named per op rather than "every integer in the dict": a Teleportation scroll's
# `spread` is how far the landing can VARY, and doubling that is not twice the
# scroll, it is a worse one. An op absent from this table resolves unscaled.
const LOOT_SCALED_FIELDS := {
	"apply_status": ["value"],
	"forget": ["count"],
	"spawn_enemy": ["count"],
	"identify_loot": ["count"],
	"identify_scrolls": ["count"],
	"remove_curse": ["count"],
	"stun_enemies": ["count"],
}


# The effect as it resolves for THIS player: Sacred Bark's multiplier folded into
# the fields above. Applied to the good and the bad alike — Aggravate Monsters is
# a scroll too, and a relic that only ever doubled the upside would make reading
# an unidentified scroll a strictly better gamble than it is (§4.1).
func _scaled(effect: Dictionary) -> Dictionary:
	var mult: int = GameState.loot_multiplier()
	var fields: Array = LOOT_SCALED_FIELDS.get(String(effect.get("op", "")), [])
	if mult <= 1 or fields.is_empty():
		return effect
	var out: Dictionary = effect.duplicate(true)
	for field in fields:
		# A field the scroll never authored takes its own default (1) times the
		# multiplier, which is what "doubled" means for a count nobody wrote down.
		out[field] = maxi(1, int(out.get(field, 1))) * mult
	return out


# One clause. Returns whether it actually DID anything — a scroll whose every
# clause no-opped is what leaves a title unread (see read_scroll).
#
# A REQUEST COUNTS AS SOMETHING HAPPENING. The picker it opens resolves a moment
# later rather than here, and a Teleportation that identified nothing because this
# file had not moved the player yet would be the one scroll nobody could learn.
func _apply_one(raw_effect: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> bool:
	var effect: Dictionary = _scaled(raw_effect)
	var op := String(effect.get("op", ""))
	match op:
		"apply_status":
			# Aggravate Monsters — every body on the board gains Strength (§13.4),
			# which is +1 to the damage each of its hits lands for, permanently.
			# The scroll used to arm a run-wide bonus that expired after a game;
			# a status rides the enemy and doesn't, so reading this one is a
			# lasting mistake rather than a bad couple of minutes.
			#
			# Scroll of Fire writes the same op twice, once at the front column and
			# once at the READER, which is why this handler knows about the player
			# at all: a scroll that only ever hurt the other side would not need a
			# Preference (§4.1).
			return _apply_status(effect, out)
		"apply_tile":
			# Scroll of Fire — the ground itself, not a body (§17). The tile lands
			# on the same front column its Burn clause targets: the bodies already
			# in your face are burning now, and the strip they are standing on
			# keeps burning whatever steps into it for the next three games. This
			# is the half of the scroll that is still worth reading into an EMPTY
			# room, which is why it is authored as its own clause.
			return _apply_tile(effect, out)
		"forget":
			# Amnesia — forget (unidentify) random known loot, any kind (§4.1, §10).
			return _forget(String(effect.get("kind", "loot")).to_lower(),
				int(effect.get("count", 1)), rng, out)
		"spawn_enemy":
			# Create Monster — conjure a random enemy at the run's current tier that
			# starts following the player (§4.1).
			return _spawn_enemy(String(effect.get("difficulty", "current")),
				int(effect.get("count", 1)), out)
		"identify_loot", "identify_scrolls":
			# Identify — the player chooses which carried piece(s) to reveal (§10).
			# `identify_scrolls` is the pre-widening spelling: the generator already
			# rewrites it, and it is matched here too so a .tres generated before
			# that still resolves rather than warning about an unknown op.
			return _identify_loot(String(effect.get("mode", "choose")),
				int(effect.get("count", 1)), rng, out)
		"remove_curse":
			# Remove Curse — the player chooses a curse GOAL to be rid of (§10.1).
			return _remove_curse(String(effect.get("mode", "choose")),
				int(effect.get("count", 1)), rng, out)
		"stun_enemies":
			# Scare Monster — the player chooses a following enemy to Stun (§7.2).
			return _stun_enemies(String(effect.get("mode", "choose")),
				int(effect.get("count", 1)), out)
		"teleport":
			# Teleportation — move ~the same distance from the Amulet (±spread, §4.1).
			out["requests"].append({
				"kind": "teleport",
				"dir": String(effect.get("dir", "same")),
				"spread": int(effect.get("spread", 1)),
			})
			return true
		_:
			push_warning("ScrollSystem: unknown effect op '%s'" % op)
			return false

# How an `apply_tile` clause reads on a scroll's card and in the read modal
# (§17). Beside status_effect_text and for the same reason: two screens describe
# the same scroll, and the tile's own name and words are what both should quote.
func tile_effect_text(effect: Dictionary) -> String:
	var tile: TileEffectData = Data.get_tile(StringName(String(effect.get("tile", ""))))
	if tile == null:
		return ""
	var where: String = {
		"front": "the front column",
		"back": "the back column",
		"all": "every tile on the board",
	}.get(String(effect.get("target", "front")).to_lower(), "the front column")
	return "Lay the %s tile over %s." % [tile.display_name, where]

# What a scroll DOES, in one line — the authored sentence where the sheet wrote
# one, and the ops assembled into words where it did not.
#
# AUTHORED WORDS BEAT GENERATED ONES, and Amnesia is why. Its op is
# `forget loot 1` and its Description is "Forget 1 random Identified Loot." — the
# op knows the kind is `loot`, but only the sentence knows that "loot" is worth
# naming as a category the player recognises. Assembling from ops is the floor,
# not the ceiling.
#
# It lives here, and not on either of the two screens that used to own a copy of
# it, for the reason status_effect_text does: the pack's hover (LootSystem) and
# the catalog's cell (Collection) describe the same scroll to the same player,
# and two assemblers are two chances to say something slightly different about it.
func scroll_text(scroll: ScrollData) -> String:
	if scroll == null:
		return ""
	if scroll.description != "":
		return scroll.description
	return assembled_text(scroll)

# The fallback half of scroll_text: the op list turned into sentences.
func assembled_text(scroll: ScrollData) -> String:
	var parts: Array = []
	for e in scroll.effect:
		if not (e is Dictionary):
			continue
		var line: String = op_text(e)
		if line != "":
			parts.append(line)
	return " ".join(parts)

# One op in words. Every op the DSL can produce answers here or answers "", and
# an op that answers "" is one this function has not been taught yet rather than
# one that does nothing.
func op_text(effect: Dictionary) -> String:
	match String(effect.get("op", "")):
		"apply_status":
			return status_effect_text(effect)
		"apply_tile":
			return tile_effect_text(effect)
		"forget":
			# A count of -1 is `all`, which has to read as a word rather than as the
			# sentinel: "Forget -1 random scrolls" is the shape this line would take
			# on the day somebody authors a wide forget without a Description.
			var count: int = int(effect.get("count", 1))
			var what: String = "piece(s) of loot" \
				if String(effect.get("kind", "loot")) == "loot" else "scroll(s)"
			if count < 0:
				return "Forget every identified %s." % what
			return "Forget %d random identified %s." % [count, what]
		"spawn_enemy":
			return "Spawn a random enemy at the current difficulty that follows you."
		"identify_loot", "identify_scrolls":
			return "Choose %d carried piece(s) of loot to identify." % int(effect.get("count", 1))
		"remove_curse":
			var curses: int = int(effect.get("count", 1))
			if curses < 0:
				return "Lift every curse on you."
			return "Choose %d curse%s to lift." % [curses, "" if curses == 1 else "s"]
		"stun_enemies":
			return "Choose %d following enemy to Stun." % int(effect.get("count", 1))
		"teleport":
			return "Teleport ~the same distance from the Amulet."
	return ""

# --- apply_status (Scroll of Aggravate Monsters) ---------------------------

# How an `apply_status` clause reads on a scroll's card and in the read modal.
# Here rather than in either of those scripts because the two describe the same
# scroll to the same player from different screens, and a status's own words
# (StatusData.combat_line) are the only ones either of them should be quoting.
func status_effect_text(effect: Dictionary) -> String:
	var status: StatusData = Data.get_status(StringName(String(effect.get("status", ""))))
	if status == null:
		return ""
	var stacks: int = maxi(1, int(effect.get("value", 1)))
	var target: String = String(effect.get("target", "all")).to_lower()
	var who: String = {
		"player": "You",
		"current": "The enemy of the game you're on",
		"random": "One random enemy",
		"front": "Every enemy in the front column",
	}.get(target, "Every enemy on the board")
	# On the PLAYER the combat line is usually the wrong half to quote — most of
	# the roster's combat sides are felt by enemies only (§13.4), so a scroll that
	# burns you would otherwise promise a halving that never lands on you.
	var side: StringName = StatusData.PLAYER if target == "player" else StatusData.ENEMY
	var what: String = status.combat_line(stacks) if status.combat_applies(side) else ""
	return "%s %s +%d %s%s." % [who, "gain" if target == "player" else "gains",
		stacks, status.display_name, " (%s)" % what if what != "" else ""]

# Hand `value` stacks of a status to whoever a `target` word names, through
# GameState (the reader) or GameLoop2's own targeting (the board) so a scroll
# can't reach anything an item couldn't. A board with nothing on it says so rather
# than reporting a silent success: reading Aggravate Monsters into an empty room
# is a wasted scroll, and the log is the only place the player finds that out.
func _apply_status(effect: Dictionary, out: Dictionary) -> bool:
	var status_id := StringName(String(effect.get("status", "")))
	var stacks: int = maxi(1, int(effect.get("value", 1)))
	var status: StatusData = Data.get_status(status_id)
	if status == null:
		push_warning("ScrollSystem: no status '%s' in the catalog" % status_id)
		return false
	var target: String = String(effect.get("target", "all")).to_lower()
	if target == "player" or target == "self":
		# Quoted from what the player ENDED UP with rather than from what was
		# asked for: Burn stops at 3 (§13), and a line reading "+3 Burn" beside a
		# pip that says 3 would be describing a different scroll.
		var before: int = GameState.status_stacks(status_id)
		var after: int = GameState.apply_status(status_id, stacks)
		if after <= before:
			out["logs"].append("%s is already as deep as it goes." % status.display_name)
			return false
		out["logs"].append("You gain +%d %s." % [after - before, status.display_name])
		return true
	var landed: int = GameLoop2.apply_enemy_status(status_id, stacks, target)
	if landed <= 0:
		# NOTHING IS SAID when the clause found nobody. It used to append a line
		# of flavour ("Nothing out there is listening."), which read as a fourth
		# thing the scroll did rather than as the absence of a third: the log is
		# a list of what LANDED, and a clause that landed on nothing belongs in
		# it exactly as much as a clause that was never authored.
		return false
	out["logs"].append("%d %s gain +%d %s." % [
		landed, "enemy" if landed == 1 else "enemies", stacks, status.display_name])
	return true

# --- apply_tile (Scroll of Fire) -------------------------------------------
# Lay a tile effect over the cells the target word names (§17). What it reports is
# what actually STUCK, not what was asked for: a cell whose mine ate the fire on
# arrival is one fewer tile on the board, and a line promising four when three
# landed would be describing a different scroll — the same rule the status branch
# above follows for a Burn that hit its ceiling.
func _apply_tile(effect: Dictionary, out: Dictionary) -> bool:
	var tile_id := StringName(String(effect.get("tile", "")))
	var tile: TileEffectData = Data.get_tile(tile_id)
	if tile == null:
		push_warning("ScrollSystem: no tile '%s' in the catalog" % tile_id)
		return false
	var cells: Array = GameLoop2.target_cells(String(effect.get("target", "front")).to_lower())
	var landed: int = 0
	for cell in cells:
		if GameLoop2.apply_tile(cell, tile_id):
			landed += 1
	if landed <= 0:
		out["logs"].append("There is no ground left to cover.")
		return false
	out["logs"].append("%s spreads across %d %s." % [
		tile.display_name, landed, "tile" if landed == 1 else "tiles"])
	return true

# --- forget (Scroll of Amnesia) --------------------------------------------
# Amnesia — forget (unidentify) random KNOWN LOOT, of whatever kind (§10).
#
# The cell used to say `forget scroll 1` while the Description beside it said
# "Forget 1 random Identified Loot", and this function could only do the narrow
# thing the cell asked for. Both now say loot, and the forgetting itself belongs to
# LootSystem, which is the layer that knows there is more than one alphabet — the
# pills' horse Amnesia has been asking for `forget loot all` since it shipped and
# had its own implementation of it.
#
# WHAT IT DOES NOT DO IS REDEAL THE COLOURS. The capsule and the bottle still mean
# what they meant; you have merely stopped knowing, and using one is how you find
# out again.
func _forget(kind: String, count: int, rng: RandomNumberGenerator, out: Dictionary) -> bool:
	var forgot: int = LootSystem.forget_identified(kind, count, rng)
	if forgot <= 0:
		out["logs"].append("You have no loot knowledge to forget.")
		return false
	out["logs"].append("You forget what %d %s do%s." % [
		forgot, "thing" if forgot == 1 else "things", "es" if forgot == 1 else ""])
	return true

# --- spawn_enemy (Scroll of Create Monster) --------------------------------
func _spawn_enemy(_difficulty: String, count: int, out: Dictionary) -> bool:
	# Roll at the run's current tier and at no other (roll_conjured_enemy); the
	# enemy joins the following stack and attacks on the next game beaten (§7.2).
	# Rolled once per body rather than once and duplicated, so a doubled Create
	# Monster conjures two DIFFERENT things.
	var names: Array = []
	for _i in range(maxi(1, count)):
		var enemy: GoalEnemyData = GameLoop2.roll_conjured_enemy()
		if enemy == null:
			break
		GameLoop2.spawn_to_stack(enemy)
		names.append(enemy.display_name)
	if names.is_empty():
		out["logs"].append("No monster could be conjured.")
		return false
	out["logs"].append("%s %s and start%s following you!" % [
		", ".join(PackedStringArray(names)),
		"appears" if names.size() == 1 else "appear",
		"s" if names.size() == 1 else ""])
	return true

# --- identify_loot (Scroll of Identify) ------------------------------------
#
# WIDENED FROM SCROLLS TO EVERYTHING CARRIED (§10, decision #13). The op offered
# scrolls alone while the Description beside it said "Choose 1 Loot to Identify",
# and with three alphabets sharing one nine-slot pack a scroll-only Identify is
# dead weight most of the time it is drawn. It is the exact mirror of the Amnesia
# change above: one verb that forgets loot, one that learns it.
#
# The candidate list is LootSystem's, so this reads as "the unidentified things you
# are carrying" and does not have to know how many kinds that is.
func _identify_loot(mode: String, count: int, rng: RandomNumberGenerator, out: Dictionary) -> bool:
	var unknown: Array = LootSystem.carried_unidentified()
	if unknown.is_empty():
		out["logs"].append("You have nothing unidentified to identify.")
		return false
	if mode == "all":
		for entry in unknown:
			LootSystem.identify(entry)
		out["logs"].append("Everything you are carrying is identified.")
		return true
	elif mode == "random":
		# NAMED, not counted. A random identify used to resolve in silence, which on a
		# scroll whose entire subject is *what is this* left the reader knowing
		# something new and with no way to find out what. The name is read AFTER the
		# identify, so it is the thing's real name rather than its mask.
		var learned: Array = []
		for _i in range(count):
			if unknown.is_empty():
				break
			var idx: int = rng.randi_range(0, unknown.size() - 1)
			LootSystem.identify(unknown[idx])
			learned.append(LootSystem.display_name(unknown[idx]))
			unknown.remove_at(idx)
		out["logs"].append("You identify %s." % ", ".join(PackedStringArray(learned)))
		return not learned.is_empty()
	out["requests"].append({"kind": "identify_loot", "count": count, "candidates": unknown})
	return true

# --- remove_curse (Scroll of Remove Curse) ---------------------------------
#
# CURSE GOALS, NOT CURSE CARDS (§10.1). The cards are shelved (spec §5); the goals
# are live content — three authored rows, handed out by events, by the Amnesia pill
# and by the Calling Bell, and drawn on the checklist every game as the things you
# are trying not to do. Lifting one is a real effect, not a placeholder.
func _remove_curse(mode: String, count: int, rng: RandomNumberGenerator, out: Dictionary) -> bool:
	if GameState.curse_goals.is_empty():
		out["logs"].append("Nothing is weighing on you.")
		return false
	if mode == "all":
		var lifted: Array = []
		for i in range(GameState.curse_goals.size() - 1, -1, -1):
			lifted.push_front(curse_name(GameState.remove_curse_goal(i)))
		out["logs"].append(_lifted_line(lifted))
		return not lifted.is_empty()
	elif mode == "random":
		var pool: Array = range(GameState.curse_goals.size())
		var picked: Array = []
		for _i in range(count):
			if pool.is_empty():
				break
			picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		var lifted_now: Array = _remove_indices(picked)
		out["logs"].append(_lifted_line(lifted_now))
		return not lifted_now.is_empty()
	out["requests"].append({"kind": "remove_curse", "count": count})
	return true

# Remove several curse rows by index at once. DESCENDING, because every removal
# shifts the indices above it — the one bug this op can have that the player would
# see as "it lifted the wrong curse".
func _remove_indices(indices: Array) -> Array:
	var work: Array = indices.duplicate()
	work.sort()
	work.reverse()
	var names: Array = []
	for i in work:
		var row: Dictionary = GameState.remove_curse_goal(int(i))
		if not row.is_empty():
			names.push_front(curse_name(row))
	return names

func _lifted_line(names: Array) -> String:
	if names.is_empty():
		return "Nothing is weighing on you."
	return "%s %s lifted." % [", ".join(PackedStringArray(names)),
		"is" if names.size() == 1 else "are"]

# What a held curse row is called, for the picker and for the line that says it
# went. The catalog's name, falling back to the id so a row whose curse has been
# removed from the sheet still reads as something.
func curse_name(row: Dictionary) -> String:
	var id := StringName(row.get("curse", &""))
	var cd: CurseData2 = Data.get_curse2(id)
	return cd.display_name if cd != null else String(id)

# --- stun_enemies (Scroll of Scare Monster) --------------------------------
func _stun_enemies(mode: String, count: int, out: Dictionary) -> bool:
	if GameLoop2.stack.is_empty():
		out["logs"].append("No following enemies to Stun.")
		return false
	if mode == "all":
		for entry in GameLoop2.stack:
			GameLoop2.stun(int(entry["instance"]))
		out["logs"].append("All following enemies are Stunned.")
		return true
	elif mode == "random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var pool: Array = GameLoop2.stack.duplicate()
		var hit: Array = []
		for _i in range(count):
			if pool.is_empty():
				break
			var idx: int = rng.randi_range(0, pool.size() - 1)
			hit.append(enemy_name(int(pool[idx]["instance"])))
			GameLoop2.stun(int(pool[idx]["instance"]))
			pool.remove_at(idx)
		# Which one it landed on, and what that is worth — a stun that resolved in
		# silence was a scroll the reader could not plan the next game around.
		out["logs"].append("%s %s Stunned — %s." % [", ".join(PackedStringArray(hit)),
			"is" if hit.size() == 1 else "are", stun_worth()])
		return not hit.is_empty()
	out["requests"].append({"kind": "stun_enemies", "count": count})
	return true

# ===========================================================================
# Fulfilment helpers (called by the UI after a request's choice is made)
# ===========================================================================

# BOTH OF THESE ANSWER IN WORDS, because a request is half of what the scroll did
# and the other half only exists once the player has chosen. `read_scroll` returns
# its logs before the picker has been drawn, so a fulfilment that stayed silent
# left the reader with a scroll that reported nothing at all — see
# LootUseModal._show_outcome, which is where these lines land.
func remove_curse_chosen(indices: Array) -> String:
	return _lifted_line(_remove_indices(indices))

func identify_loot_chosen(entries: Array) -> String:
	var names: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		LootSystem.identify(entry)
		# After the identify, so the line names the thing rather than its mask.
		names.append(LootSystem.display_name(entry))
	if names.is_empty():
		return "You identify nothing."
	return "You identify %s." % ", ".join(PackedStringArray(names))

func stun_enemies_chosen(instances: Array) -> String:
	var names: Array = []
	for inst in instances:
		# Named BEFORE it is stunned: the name is read off the board, and the point of
		# reading it first is that nothing about this line depends on what stunning
		# leaves behind.
		names.append(enemy_name(int(inst)))
		GameLoop2.stun(int(inst))
	if names.is_empty():
		return "Nothing is Stunned."
	return "%s %s Stunned — %s." % [", ".join(PackedStringArray(names)),
		"is" if names.size() == 1 else "are", stun_worth()]

# What one Stun is actually worth where the run is standing (§7.4). A stun costs
# the target one TURN, and a turn is what a LOST RUN buys the board (§3.2) — so
# out in the wilds a stun is one failure this body sits out, and nearer the Amulet
# it can be eaten by one of the extra turns reporting a game hands over instead.
# Both the screen that ASKS which enemy to stun and the one that reports the
# answer price it against the current pace rather than promising "skips its next
# attack". One copy, because the two saying it differently would be two answers to
# one question.
func stun_worth() -> String:
	var extra: int = GameLoop2.enemy_turns()
	if extra <= 0:
		return "a whole lost run — nothing else moves them out here"
	return "one turn: a lost run, or 1 of the %d that reporting a game buys them" % extra

# What a following enemy is called, by instance — the stack is the only place that
# knows, and two copies of the same goblin are two instances of one name.
func enemy_name(instance: int) -> String:
	for entry in GameLoop2.stack:
		if int(entry["instance"]) != instance:
			continue
		var e: GoalEnemyData = entry["enemy"]
		return e.display_name if e != null else "It"
	return "It"
