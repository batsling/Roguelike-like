extends Node

# LootSystem (autoload) — the one place a piece of carried loot is SPENT
# (docs/games-first-redesign.md §4.3).
#
# Scrolls and pills are two content systems with two grammars, and each owns its
# own resolution (ScrollSystem.read_scroll / PillSystem.take_pill). What they
# share is everything that happens AROUND a use: consuming the entry, the run's
# memory of what was used, and Echo Chamber replaying it. That belongs to neither
# of them — an echo of a scroll can be a pill and vice versa — so it lives here,
# and both callers get the same answer shape back:
#
#   { "logs": Array[String], "requests": Array[Dictionary] }
#
# `requests` are the follow-ups a caller has to fulfil (a teleport, a chooser).
# Echoed copies contribute theirs too, so a doubled Telepills asks the overworld
# to move you twice rather than silently dropping one.

const LOOT_COLOR := Color(0.72, 0.62, 0.86)

# What Echo Chamber remembers is RUN state, not item state (GameState.loot_used_
# memory): the relic READS the memory, it does not carry it. Two Echo Chambers
# therefore see the same three uses rather than two separate histories, and the
# memory resets with the run and survives a save like everything else the run
# knows. This accessor is here because every reader of it is in this file.
func used_memory() -> Array:
	return GameState.loot_used_memory

# ===========================================================================
# Spending one
# ===========================================================================

# Spend the loot entry at `index`: resolve it, ECHO it, remember it, and remove it
# from the pack. Returns the merged result of the use and every echo it fired.
#
# THE ORDER IS ISAAC'S. The echoes fire off the memory as it stood BEFORE this
# use, and only then does this use enter it — so nothing echoes itself, and an
# echoed copy never enters the memory either. Without that a single pill with two
# Echo Chambers' worth of history would compound into a run-ending cascade rather
# than into three extra doses.
func use_loot(index: int, ctx: Dictionary = {}) -> Dictionary:
	if index < 0 or index >= GameState.loot_items.size():
		return {"logs": [], "requests": []}
	var entry = GameState.loot_items[index]
	if not (entry is Dictionary):
		return {"logs": [], "requests": []}
	entry = (entry as Dictionary).duplicate(true)
	# Consumed FIRST: an effect that grants loot (or one that ends the run) must not
	# find the spent piece still sitting in the pack, and the nine-piece cap means a
	# pill that pays out would otherwise be refused space it is about to free.
	GameState.remove_loot_at(index)
	return use_entry(entry, ctx)

# Spend a piece that is NOT IN THE PACK — the one a game has just paid out, taken
# on the spot rather than carried (§4.3). Same resolution, same echoes, same
# memory; the only difference is that there was no slot to empty, which is exactly
# what makes it worth having: a full pack used to turn a payout into "leave it",
# and a piece you can drink where you stand is an answer that costs you nothing
# you were already carrying.
#
# `use_loot` is this with a slot emptied first, so the two can never drift on what
# using a piece MEANS.
func use_entry(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	if entry.is_empty():
		return out
	var spent: Dictionary = entry.duplicate(true)
	_merge(out, _resolve(spent, ctx))
	for echo in _echo_queue():
		var copy: Dictionary = _resolve(echo, ctx)
		if not copy.is_empty():
			_merge(out, copy)
	_remember(spent)
	return out

# Resolve ONE entry through whichever system owns it. No consuming, no echoing —
# which is exactly why an echoed copy can come back through here without costing
# the player a second piece of loot.
func _resolve(entry: Dictionary, ctx: Dictionary) -> Dictionary:
	match String(entry.get("type", "")):
		"scroll":
			var scroll: ScrollData = Data.get_scroll(StringName(entry.get("id", "")))
			if scroll == null:
				return {}
			return ScrollSystem.read_scroll(scroll, ctx)
		"pill":
			return PillSystem.take_pill(entry, ctx)
		"potion":
			# THE ONLY KIND WITH TWO VERBS (potions-design §4). Which one the player
			# bought rides in `ctx.verb`, and the square a throw was aimed at in
			# `ctx.target` — both set once, by the caller that armed the picker, so an
			# ECHOED copy coming back through here re-throws at the same cell the
			# original was aimed at (§4.2).
			if is_throw(ctx):
				return PotionSystem.throw_potion(entry, ctx)
			return PotionSystem.quaff_potion(entry, ctx)
	return {}

# The copies Echo Chamber fires this use: the last N remembered, newest first, so
# the thing you used a moment ago lands before the thing you used three games ago.
func _echo_queue() -> Array:
	var depth: int = GameState.loot_echo_depth()
	var memory: Array = used_memory()
	if depth <= 0 or memory.is_empty():
		return []
	var out: Array = []
	var start: int = maxi(0, memory.size() - depth)
	for i in range(memory.size() - 1, start - 1, -1):
		out.append((memory[i] as Dictionary).duplicate(true))
	return out

# Push a used entry onto the memory. Kept trimmed to the deepest echo the pack has
# ever had rather than to the current one, so taking Echo Chamber off and putting
# it back on doesn't quietly erase the history it would have read.
func _remember(entry: Dictionary) -> void:
	var memory: Array = used_memory()
	memory.append(entry.duplicate(true))
	var cap: int = maxi(3, GameState.loot_echo_depth())
	while memory.size() > cap:
		memory.pop_front()

func _merge(into: Dictionary, from: Dictionary) -> void:
	for line in from.get("logs", []):
		(into["logs"] as Array).append(line)
	for req in from.get("requests", []):
		(into["requests"] as Array).append(req)

# ===========================================================================
# Describing one (the loot window, the drop modal)
# ===========================================================================

# The name a carried entry shows. Delegates, because what a scroll is called and
# what a pill is called are two different rules — a scroll masks its name behind
# one shared art, a pill's name follows the capsule and (for Bad Trip) the
# player's own Health.
func display_name(entry: Dictionary) -> String:
	match String(entry.get("type", "")):
		"scroll":
			return ScrollSystem.display_name(Data.get_scroll(StringName(entry.get("id", ""))))
		"pill":
			return PillSystem.display_name(entry)
		"potion":
			return PotionSystem.display_name(entry)
	return "Loot"

func art_texture(entry: Dictionary) -> Texture2D:
	match String(entry.get("type", "")):
		"scroll":
			return ScrollSystem.art_texture(Data.get_scroll(StringName(entry.get("id", ""))))
		"pill":
			return PillSystem.art_texture(entry)
		"potion":
			return PotionSystem.art_texture(entry)
	return null

# The box this piece's art should be drawn in, given the size everything else on
# the surface is drawn at. A HORSE DOSE COMES BACK BIGGER (§4.3) — see
# PillSystem.art_scale for why this exists at all. Every surface that draws loot
# goes through here rather than passing a constant to crisp_tex, so the tell is
# either on everywhere or off everywhere.
func art_box(entry: Dictionary, base: int) -> int:
	if String(entry.get("type", "")) != "pill":
		return base
	return int(round(float(base) * PillSystem.art_scale(entry)))

# The art, sized to this piece's own dose. The one call the UI actually wants.
func art_tex(entry: Dictionary, base: int) -> TextureRect:
	return UITheme.crisp_tex(art_texture(entry), art_box(entry, base))

# The glyph a kind wears in the log and on its tile.
func glyph(entry: Dictionary) -> String:
	match String(entry.get("type", "")):
		"pill":
			return "💊"
		"potion":
			return "🧪"
	return "📜"

# ===========================================================================
# Knowledge — what the run has learned, across every alphabet at once
# ===========================================================================

# The identified type ids of one kind, or of every kind when `kind` is "loot".
# Returned as a fresh Array, since the callers forget from what they are iterating.
#
# TWO ARMS TODAY, THREE WHEN POTIONS LAND. Every kind-blind verb — `forget loot`,
# `identify_loot` — reads through the functions in this section rather than through
# GameState's per-kind lists, so widening them to potions is a line in each of
# these and nothing at any call site.
func identified_types(kind: String = "loot") -> Array:
	var out: Array = []
	if kind == "scroll" or kind == "loot":
		out.append_array(GameState.identified_scroll_types)
	if kind == "pill" or kind == "loot":
		out.append_array(GameState.identified_pill_types)
	if kind == "potion" or kind == "loot":
		out.append_array(GameState.identified_potion_types)
	return out

# Unidentify one type id, whichever alphabet it belongs to. A pill and a scroll
# cannot share an id, so the id alone says which system owns it — which is what
# lets Amnesia forget a mixed handful without being told what it drew.
func unidentify(id: StringName) -> void:
	if GameState.identified_scroll_types.has(id):
		ScrollSystem.unidentify(id)
	if GameState.identified_pill_types.has(id):
		PillSystem.unidentify(id)
	if GameState.identified_potion_types.has(id):
		PotionSystem.unidentify(id)

# Forget `count` (-1 = all) random identified types of `kind`; returns how many.
#
# BOTH AMNESIAS COME THROUGH HERE. The pill's horse dose has authored
# `forget loot all` since it shipped and the scroll's cell now says `forget loot 1`
# (§10), so the two verbs mean the same thing and there is one implementation of
# it. What each caller keeps is its own sentence about what just happened.
#
# The targets are snapshotted first, because forgetting is what removes them.
func forget_identified(kind: String, count: int, rng: RandomNumberGenerator) -> int:
	var pool: Array = identified_types(kind)
	var n: int = pool.size() if count < 0 else mini(count, pool.size())
	for _i in range(n):
		if pool.is_empty():
			break
		var idx: int = rng.randi_range(0, pool.size() - 1)
		unidentify(pool[idx])
		pool.remove_at(idx)
	return n

# Is this piece of loot known? An unidentified piece is the gamble; a known one is
# a decision. The window draws the two differently, and the drop modal has to say
# which it is offering.
func is_identified(entry: Dictionary) -> bool:
	var id := StringName(entry.get("id", ""))
	match String(entry.get("type", "")):
		"scroll":
			return ScrollSystem.is_identified(id)
		"pill":
			return PillSystem.is_identified(id)
		"potion":
			return PotionSystem.is_identified(id)
	return false

# Learn what a carried piece is, whichever alphabet it belongs to — Identify's
# half of the pair above. Returns whether this was news.
func identify(entry: Dictionary) -> bool:
	var id := StringName(entry.get("id", ""))
	match String(entry.get("type", "")):
		"scroll":
			return ScrollSystem.identify(id)
		"pill":
			return PillSystem.identify(id)
		"potion":
			return PotionSystem.identify(id)
	return false

# One representative carried entry per unidentified TYPE in the pack — the
# candidate list every "choose something to identify" verb offers (§10).
#
# PER TYPE, NOT PER SLOT, because identification is of the type: two capsules of
# the same unknown colour are one thing to learn, and offering both would let a
# player spend a Rare scroll's whole count on one fact. The first entry of each
# type is the representative, since what the picker draws off it — its art, its
# masked name — is a property of the type rather than of the slot.
func carried_unidentified() -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for entry in GameState.loot_items:
		if not (entry is Dictionary) or is_identified(entry):
			continue
		var key: String = "%s/%s" % [entry.get("type", ""), entry.get("id", "")]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(entry)
	return out

# How a candidate reads in an identify picker, where the player is choosing
# between things they have not learned yet.
#
# THE TWO KINDS MASK DIFFERENTLY AND THE LABEL FOLLOWS THE MASK. Every
# unidentified scroll wears the same art, so the picker has named them outright
# since it shipped — with nothing else to tell two of them apart, a list of
# identical rows is not a choice. A pill's mask IS its colour, which the art in the
# row already shows and which the run protects everywhere else (spec §4.3: the
# "Known this run" fold never writes a colour down), so naming one would hand back
# the deduction the three spare capsules exist to prevent. Scrolls name themselves;
# pills show their capsule and stay anonymous.
func pick_label(entry: Dictionary) -> String:
	if String(entry.get("type", "")) == "scroll":
		var s: ScrollData = Data.get_scroll(StringName(entry.get("id", "")))
		if s != null:
			return s.display_name
	return display_name(entry)

# What the piece does, in one line, or the "you don't know yet" line when it is
# unidentified. The loot window's hover and the drop modal both quote this.
func description(entry: Dictionary) -> String:
	match String(entry.get("type", "")):
		"scroll":
			var s: ScrollData = Data.get_scroll(StringName(entry.get("id", "")))
			if s == null:
				return ""
			if not ScrollSystem.is_identified(s.id):
				return "Unidentified — reading it is a gamble."
			# This file used to assemble the scroll's ops into words itself,
			# alongside a second copy in the collection's catalog. Both go through
			# ScrollSystem.scroll_text now, which prefers the sheet's authored
			# Description and assembles only as a fallback.
			return ScrollSystem.scroll_text(s)
		"pill":
			return PillSystem.description(entry)
		"potion":
			return PotionSystem.description(entry)
	return ""

# The Preference, or "" while the piece is unknown — hidden for both kinds, since
# it is the whole reason an unidentified consumable is a gamble (§4.1/§4.3).
func preference(entry: Dictionary) -> String:
	match String(entry.get("type", "")):
		"scroll":
			var s: ScrollData = Data.get_scroll(StringName(entry.get("id", "")))
			return s.preference if s != null and ScrollSystem.is_identified(s.id) else ""
		"pill":
			return PillSystem.preference(entry)
		"potion":
			return PotionSystem.preference(entry)
	return ""

# ===========================================================================
# The second verb (potions-design.md §4.2, §4.5)
# ===========================================================================

# Does this piece offer a THROW as well as a use? One kind answers yes, and only
# one — a scroll is read and a pill is swallowed, and neither has ever had a
# second thing you could do with it.
#
# AN UNKNOWN BOTTLE ALWAYS DOES, even the one that turns out to be Raise Level and
# fizzles on impact (§4.5). The button is hidden only for a KNOWN potion with
# nothing on its tile side, because there is nothing to aim; hiding it for
# unknowns would leak which bottles have no throw, which is exactly the fact the
# identification gamble is selling.
func can_throw(entry: Dictionary) -> bool:
	if String(entry.get("type", "")) != "potion":
		return false
	var p: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	if p == null:
		return false
	return p.has_throw() or not PotionSystem.is_identified(p.id)

# Is this use context a throw? One reading of `ctx.verb`, here rather than at each
# call site, so "throw" can never be spelled two ways.
func is_throw(ctx: Dictionary) -> bool:
	return String(ctx.get("verb", "quaff")).to_lower() == "throw"

# What the button on a piece says. A potion's quaff is a QUAFF and not a "use":
# the whole point of the pair is that the player is choosing between two named
# things, and one of them being called by the generic word would make the choice
# read as "do it" versus "throw it".
func use_verb(entry: Dictionary) -> String:
	match String(entry.get("type", "")):
		"pill":
			return "Take Pill"
		"potion":
			return "Quaff"
	return "Read Scroll"

# What KIND of thing this is, in the words the player sees: Scroll, Pill, or the
# dose that announces itself.
func kind_name(entry: Dictionary) -> String:
	if bool(entry.get("horse", false)):
		return "Horse Pill"
	match String(entry.get("type", "")):
		"pill":
			return "Pill"
		"potion":
			return "Potion"
	return "Scroll"

# The hover model for a piece of loot, in the shape every other hover on the page
# uses (HoverCard). It lives here rather than on the loot window because four
# surfaces describe the same piece — the window's slots, the drop modal's offer,
# the drop modal's grid and the info card — and a description that differed
# between them would be four chances to say something slightly untrue.
func hover_card(entry: Dictionary) -> Dictionary:
	var known: bool = is_identified(entry)
	var sub: String = kind_name(entry)
	if known and preference(entry) != "":
		sub += "  ·  %s" % preference(entry)
	return {
		"title": display_name(entry),
		"subtitle": sub,
		"accent": LOOT_COLOR,
		"art": art_texture(entry),
		"lines": [description(entry)],
		"note": "" if known else "▸ Using it is how you learn what it is.",
	}
