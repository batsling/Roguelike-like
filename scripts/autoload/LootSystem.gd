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
#
# FIVE KINDS SHARE THE PACK NOW, and four of them behave identically here: they are
# resolved, remembered, echoed and removed. The WAND is the one that does not, and
# every exception it needs is in this file rather than in WandSystem — spending a
# charge instead of a slot, and standing outside Echo Chamber in both directions —
# because both are facts about what USING a piece means rather than about what a
# wand does. See `use_loot` and `use_entry`.

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
	# A WAND SPENDS A CHARGE RATHER THAN A SLOT, until the charge it spends is its
	# last (docs/wands-design.md §4.1). That is the whole of what the kind changes
	# about using loot, and it is one branch: everything below — resolving, the
	# memory, the logs — is identical whichever way this went.
	#
	# THE SLOT IS SETTLED BEFORE THE EFFECT RESOLVES, exactly as every other kind's
	# is, and for the same reason: an effect that grants loot (or one that ends the
	# run) must not find the pack in a state that is about to change. So a wand's
	# charge comes off and its slot is written back or emptied here, and only then
	# does anything happen — the "3 / 6" the outcome screen reads is what is left,
	# never what there was.
	if is_wand(entry):
		if WandSystem.spend_charge(entry) > 0:
			# Written back so the slot keeps the same index and the same position — a
			# wand does not move because it was fired.
			GameState.loot_items[index] = entry.duplicate(true)
			GameState.emit_signal("inventory_changed")
		else:
			GameState.remove_loot_at(index)
		return _spend(entry, ctx)
	# Consumed FIRST: an effect that grants loot (or one that ends the run) must not
	# find the spent piece still sitting in the pack, and the nine-piece cap means a
	# pill that pays out would otherwise be refused space it is about to free.
	GameState.remove_loot_at(index)
	return _spend(entry, ctx)

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
	# A LOOSE WAND SPENDS A CHARGE TOO. There is no slot to settle, but the charge
	# is a fact about the piece rather than about the pack, and skipping it here
	# would let a wand taken on the spot fire for free — and would have the outcome
	# screen report a count that never moved. `entry` is mutated in place (a
	# Dictionary is a reference), so the caller's copy is what the screen reads.
	if is_wand(entry):
		WandSystem.spend_charge(entry)
	return _spend(entry, ctx)

# Resolve one piece that has already had its slot and its charge settled: the
# effect, Echo Chamber's copies, and the memory this use joins. Both public spend
# paths end here, which is what keeps "what using a piece MEANS" in one place while
# the two of them differ about the pack.
func _spend(entry: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	if entry.is_empty():
		return out
	var spent: Dictionary = entry.duplicate(true)
	_merge(out, _resolve(spent, ctx))
	# A WAND IS OUTSIDE ECHO CHAMBER IN BOTH DIRECTIONS (docs/wands-design.md §4.4),
	# and the two halves are one rule: the relic copies pieces that were CONSUMED.
	#
	# It is never echoed, because a wand copied three times would be four effects
	# for one charge — the relic would be worth more on the kind that already gets
	# to fire six times. And zapping one fires no copies EITHER, which is the half
	# that is easy to miss and the half that matters: a wand that replayed the
	# memory without joining it would be three free copies of your last pill, once
	# per charge, for the price of one slot. Nothing else in the pack can pay a
	# relic six times.
	if not is_wand(spent):
		for echo in _echo_queue():
			var copy: Dictionary = _resolve(echo, ctx)
			if not copy.is_empty():
				_merge(out, copy)
		_remember(spent)
	# WHAT IS LEFT IN IT, on the result rather than left for the caller to work out.
	# The screen that reports a use holds its own copy of the entry, and for the
	# PACK path that copy is the one made before the charge came off — so a modal
	# reading its own `_entry` would print the count as it stood a moment ago.
	# Absent for every other kind, which has nothing to count.
	if is_wand(spent):
		out["charges_left"] = WandSystem.charges_of(spent)
	return out

# Is this piece the one kind that spends charges rather than slots? One reading of
# the type, here rather than at each call site, so the exceptions a wand needs can
# never be spelled two ways.
func is_wand(entry: Dictionary) -> bool:
	return String(entry.get("type", "")) == "wand"

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
		"card":
			# The one kind with nothing to learn (docs/cards-design.md §2) — no
			# identify step on the way in, because there was never anything hidden
			# from a card in the pack.
			return CardSystem.play_card(entry, ctx)
		"wand":
			# THE OTHER KIND WITH A CELL IN `ctx.target`, and it arrives the same way
			# a thrown potion's does (docs/wands-design.md §4.2) — set once, by the
			# caller that armed the picker. A wand with nothing to aim ignores it.
			return WandSystem.zap_wand(entry, ctx)
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
# `face_up` is the CARD axis and is ignored by every other kind (see art_texture
# below for what it means and why it lives on this signature rather than in the
# entry).
func display_name(entry: Dictionary, face_up: bool = true) -> String:
	match String(entry.get("type", "")):
		"scroll":
			return ScrollSystem.display_name(Data.get_scroll(StringName(entry.get("id", ""))))
		"pill":
			return PillSystem.display_name(entry)
		"potion":
			return PotionSystem.display_name(entry)
		"card":
			return CardSystem.display_name(entry, face_up)
		"wand":
			return WandSystem.display_name(entry)
	return "Loot"

# THE ONE PLACE A PIECE OF LOOT BECOMES A PICTURE, and the one place the CARD's
# two sides are told apart (docs/cards-design.md §3).
#
# `face_up` is FALSE on the floor and true everywhere else. A card lying on a
# battlefield square shows its deck's icon and nothing more; in the pack it shows
# its own face. Every other kind ignores the flag, because no other kind has a
# second side — a scroll on the ground is the same parchment it is in the pack.
#
# IT IS A PARAMETER RATHER THAN A FIELD ON THE ENTRY, deliberately. "Face down" is
# not a fact about the card, it is a fact about WHERE THE CARD IS, and an entry
# carrying it would have to be flipped by whoever moved it — which is every drag,
# every eviction, every swap, and one missed site is a card that stays face down
# in the pack forever.
func art_texture(entry: Dictionary, face_up: bool = true) -> Texture2D:
	match String(entry.get("type", "")):
		"scroll":
			return ScrollSystem.art_texture(Data.get_scroll(StringName(entry.get("id", ""))))
		"pill":
			return PillSystem.art_texture(entry)
		"potion":
			return PotionSystem.art_texture(entry)
		"card":
			return CardSystem.art_texture(entry, face_up)
		"wand":
			return WandSystem.art_texture(entry)
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
func art_tex(entry: Dictionary, base: int, face_up: bool = true) -> TextureRect:
	return UITheme.crisp_tex(art_texture(entry, face_up), art_box(entry, base))

# The glyph a kind wears in the log and on its tile.
func glyph(entry: Dictionary) -> String:
	match String(entry.get("type", "")):
		"pill":
			return "💊"
		"potion":
			return "🧪"
		"card":
			return "🃏"
		"wand":
			return "🪄"
	return "📜"

# ===========================================================================
# Knowledge — what the run has learned, across every alphabet at once
# ===========================================================================

# The identified type ids of one kind, or of every kind when `kind` is "loot".
# Returned as a fresh Array, since the callers forget from what they are iterating.
#
# FOUR ARMS, ONE PER ALPHABET. Every kind-blind verb — `forget loot`,
# `identify_loot` — reads through the functions in this section rather than through
# GameState's per-kind lists, which is what made widening them to potions, and then
# to wands, a line in each of these and nothing at any call site. Cards are the
# fifth kind and appear in none of them, because there is nothing to learn about
# one (docs/cards-design.md §2).
func identified_types(kind: String = "loot") -> Array:
	var out: Array = []
	if kind == "scroll" or kind == "loot":
		out.append_array(GameState.identified_scroll_types)
	if kind == "pill" or kind == "loot":
		out.append_array(GameState.identified_pill_types)
	if kind == "potion" or kind == "loot":
		out.append_array(GameState.identified_potion_types)
	if kind == "wand" or kind == "loot":
		out.append_array(GameState.identified_wand_types)
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
	if GameState.identified_wand_types.has(id):
		WandSystem.unidentify(id)

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
		"wand":
			return WandSystem.is_identified(id)
		"card":
			# A CARD IS ALWAYS KNOWN (docs/cards-design.md §2). Not "identified" —
			# there is no such state for it and no way to reach one — but this is the
			# question every kind-blind surface asks, and the honest answer is yes:
			# nothing about a card in the pack is hidden. It is what keeps a card out
			# of `carried_unidentified`, so Scroll of Identify never offers to tell
			# you something you can already read.
			return true
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
		"wand":
			return WandSystem.identify(id)
		"card":
			# Nothing to learn, so nothing is news. Identify spending a count on a
			# card is prevented upstream, by is_identified above.
			return false
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
# IT IS THE MASK, ALWAYS, FOR EVERY KIND. This function used to hand back the
# scroll's REAL name — `s.display_name`, straight off the resource — and that made
# Scroll of Identify self-defeating: the picker it opened listed "Scroll of Fire,
# Scroll of Amnesia, Scroll of Remove Curse" and the player had their answer
# before they had chosen anything. Identifying one of them afterwards was a
# formality.
#
# The reason it did that was real at the time: every unidentified scroll wore the
# same parchment and the same words, so a picker that masked them was a list of
# identical rows, which is not a choice either. Both halves of that are fixed by
# the run dealing each scroll a title of its own (ScrollSystem.ensure_names) —
# "ZELGO MER" and "ah bloto festr" are as distinguishable as two names get and
# say nothing whatever about what is written underneath.
#
# So every kind now masks the same way, and `display_name` is already the mask
# for all three: a scroll's dealt title, a potion's colour, a pill's silence
# beside the capsule its row already draws (spec §4.3 — the "Known this run" fold
# never writes a colour down, and naming one here would hand back the deduction
# the three spare capsules exist to prevent).
func pick_label(entry: Dictionary) -> String:
	return display_name(entry)

# What the piece does, in one line, or the "you don't know yet" line when it is
# unidentified. The loot window's hover and the drop modal both quote this.
func description(entry: Dictionary, face_up: bool = true) -> String:
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
		"card":
			return CardSystem.description(entry, face_up)
		"wand":
			return WandSystem.description(entry)
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
		"wand":
			return WandSystem.preference(entry)
		"card":
			# A card has no Preference and never will (docs/cards-design.md §2).
			# Preference is the label a GAMBLE wears so an unknown piece can hint at
			# its own risk; printing one over a line that already says "Gain +2
			# Health" would be the same fact twice, in a vaguer word.
			return ""
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

# ===========================================================================
# Aiming, and the charges behind it (docs/wands-design.md §4.2)
# ===========================================================================

# Must this piece be pointed at a square before it can resolve? Two kinds reach the
# board and they reach it differently, which is why this is not `can_throw`:
#
#   A POTION MAY BE AIMED. Throw is one of its two verbs and the player chooses;
#   quaffing it is the other answer and needs no cell at all.
#   A WAND MUST BE AIMED, or must not be, and the wand decides. There is no second
#   verb to fall back on — a ray with no square is a charge spent on nothing.
#
# So the potion arm is a capability and the wand arm is a requirement, and the
# modal reads them at different moments: one to decide whether to offer a button,
# this one to decide whether to open the picker before the button does anything.
func must_aim(entry: Dictionary) -> bool:
	if not is_wand(entry):
		return false
	return WandSystem.needs_target(entry)

# How many uses are left in this piece, and how many it can hold. `[0, 0]` for the
# four kinds that have no such number — a scroll is one use in the sense that it is
# gone afterwards, not in the sense that it is counting.
func charges(entry: Dictionary) -> Array:
	if not is_wand(entry):
		return [0, 0]
	return [WandSystem.charges_of(entry), WandSystem.max_charges(entry)]

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
		"card":
			return "Play Card"
		"wand":
			# NOT "Use". A wand is ZAPPED, and the word is doing work: it is the one
			# verb in the pack that does not mean the piece is gone afterwards.
			return "Zap"
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
		"card":
			return "Card"
		"wand":
			return "Wand"
	return "Scroll"

# The hover model for a piece of loot, in the shape every other hover on the page
# uses (HoverCard). It lives here rather than on the loot window because four
# surfaces describe the same piece — the window's slots, the drop modal's offer,
# the drop modal's grid and the info card — and a description that differed
# between them would be four chances to say something slightly untrue.
func hover_card(entry: Dictionary, face_up: bool = true) -> Dictionary:
	var known: bool = is_identified(entry)
	var sub: String = kind_name(entry)
	if known and preference(entry) != "":
		sub += "  ·  %s" % preference(entry)
	# A WAND'S CHARGES ARE NEVER HIDDEN, known or not (docs/wands-design.md §6.4).
	# How many times a stick can be fired is what the player is buying a slot for,
	# and it is not part of the gamble: they can see the thing is nearly new. It
	# rides the subtitle rather than the body, beside the Preference, because it is
	# the same sort of fact — what this piece IS, rather than what it does.
	if is_wand(entry):
		var bar: Array = charges(entry)
		sub += "  ·  %d / %d charges" % [int(bar[0]), int(bar[1])]
	# A FACE-DOWN CARD'S HOVER SAYS ITS DECK AND STOPS (docs/cards-design.md §3).
	# The token on the square already draws the deck's icon, so the hover naming it
	# is the picture in words — and the note is the one thing the player can act on:
	# the way to read a card is to pick it up, which costs a slot and is the whole
	# decision the floor is asking.
	#
	# It is the only masked hover in the project that a KNOWN piece gets, which is
	# why it cannot ride on `known` — a card is known and face-down at the same time,
	# and those are two different facts about it.
	if not face_up and String(entry.get("type", "")) == "card":
		return {
			"title": display_name(entry, false),
			"subtitle": "Card  ·  face down",
			"accent": LOOT_COLOR,
			"art": art_texture(entry, false),
			"lines": [description(entry, false)],
			"note": "▸ Pick it up to turn it over.",
		}
	return {
		"title": display_name(entry),
		"subtitle": sub,
		"accent": LOOT_COLOR,
		"art": art_texture(entry),
		"lines": [description(entry)],
		"note": "" if known else "▸ Using it is how you learn what it is.",
	}
