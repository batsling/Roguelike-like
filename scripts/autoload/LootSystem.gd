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
	var out := {"logs": [], "requests": []}
	if index < 0 or index >= GameState.loot_items.size():
		return out
	var entry = GameState.loot_items[index]
	if not (entry is Dictionary):
		return out
	entry = (entry as Dictionary).duplicate(true)
	# Consumed FIRST: an effect that grants loot (or one that ends the run) must not
	# find the spent piece still sitting in the pack, and the nine-piece cap means a
	# pill that pays out would otherwise be refused space it is about to free.
	GameState.remove_loot_at(index)

	_merge(out, _resolve(entry, ctx))
	for echo in _echo_queue():
		var copy: Dictionary = _resolve(echo, ctx)
		if not copy.is_empty():
			_merge(out, copy)
	_remember(entry)
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
	return "Loot"

func art_texture(entry: Dictionary) -> Texture2D:
	match String(entry.get("type", "")):
		"scroll":
			return ScrollSystem.art_texture(Data.get_scroll(StringName(entry.get("id", ""))))
		"pill":
			return PillSystem.art_texture(entry)
	return null

# The glyph a kind wears in the log and on its tile.
func glyph(entry: Dictionary) -> String:
	return "💊" if String(entry.get("type", "")) == "pill" else "📜"

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
	return false

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
			return _scroll_line(s)
		"pill":
			return PillSystem.description(entry)
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
	return ""

# A scroll's ops in words. The read modal grew its own version of this first; this
# is the same list, phrased for a one-line hover rather than for a full card.
func _scroll_line(scroll: ScrollData) -> String:
	var parts: Array = []
	for e in scroll.effect:
		if not (e is Dictionary):
			continue
		match String(e.get("op", "")):
			"apply_status":
				parts.append(ScrollSystem.status_effect_text(e))
			"apply_tile":
				parts.append(ScrollSystem.tile_effect_text(e))
			"forget":
				parts.append("Forget %d random scroll(s)." % int(e.get("count", 1)))
			"spawn_enemy":
				parts.append("Spawn a random enemy that follows you.")
			"identify_scrolls":
				parts.append("Choose %d scroll(s) to identify." % int(e.get("count", 1)))
			"stun_enemies":
				parts.append("Choose %d following enemy to Stun." % int(e.get("count", 1)))
			"teleport":
				parts.append("Teleport ~the same distance from the Amulet.")
	return " ".join(parts)
