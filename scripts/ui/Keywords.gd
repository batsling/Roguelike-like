class_name Keywords
extends RefCounted

# KEYWORDS — the Slay-the-Spire-style dropdown that hangs off a piece of text
# (docs/games-first-redesign.md §17).
#
# An item or a scroll describes what it does in the player's own vocabulary:
# "Gain +3 Burn", "Bombs Apply the Fire Tile", "Apply the Landmine Unit to a
# random empty Tile". Every capitalised noun in those sentences is a MECHANIC with
# rules of its own, and the sentence has no room to carry them. So the card names
# the thing and the keyword strip underneath says what the thing is.
#
# ONE REGISTRY for all three kinds — statuses, tile effects and units — because
# from the reader's side they are one question ("what is that?"), and three
# registries would be three places for the answer to go stale. Each kind already
# owns its own words (`StatusData.tooltip_for`, `TileEffectData.tooltip_for`,
# `UnitData.tooltip_for`), so this file finds the mentions and hands the writing
# back to the content.
#
# Usage — one call, after the description label is in the tree:
#
#     Keywords.attach(text_column, item.description)
#
# It adds nothing at all when the text names no keyword, so it is safe to call on
# every card rather than only the ones that were expected to need it.

# One keyword found in a piece of text.
#   id      the content id
#   kind    &"status" | &"tile" | &"unit"
#   name    what it is called, as the chip reads
#   text    the hover body, built by the content itself
#   icon    art, when the content has some

# --- finding them ----------------------------------------------------------

# Every keyword `text` mentions, in the order the CATALOG lists them rather than
# the order the sentence does — so two cards naming the same pair of keywords show
# them in the same order, and the strip is somewhere the eye can learn.
#
# Matching is on the display name, case-insensitively, at WORD BOUNDARIES: "Fire"
# must not light up inside "Fireball", and "Burn" must not light up inside
# "Burning Blood" (which is a relic, and a real one). A name that is a substring
# of a longer keyword's name loses to it, so "Fire Tile" wins over "Fire" where
# both would match the same span.
static func found_in(text: String) -> Array:
	var out: Array = []
	if text.strip_edges() == "":
		return out
	var haystack: String = text.to_lower()
	for entry in _catalog():
		for alias in entry["aliases"]:
			if _mentions(haystack, String(alias)):
				out.append(entry)
				break
	return out

# Does `haystack` (already lowercased) contain `needle` as a whole word? Godot's
# String has no word-boundary search, so this walks the finds and checks what sits
# either side of each — the alternative is a RegEx compiled per lookup, which is a
# lot of machinery for "is the next character a letter".
static func _mentions(haystack: String, needle: String) -> bool:
	var low: String = needle.to_lower()
	if low == "":
		return false
	var at: int = haystack.find(low)
	while at >= 0:
		var before_ok: bool = at == 0 or not _is_word_char(haystack[at - 1])
		var after: int = at + low.length()
		var after_ok: bool = after >= haystack.length() or not _is_word_char(haystack[after])
		if before_ok and after_ok:
			return true
		at = haystack.find(low, at + 1)
	return false

static func _is_word_char(c: String) -> bool:
	var low: String = c.to_lower()
	return (low >= "a" and low <= "z") or (c >= "0" and c <= "9") or c == "_"

# The registry itself: every status, tile effect and unit in the catalog, with the
# names a sentence might call it by.
#
# A tile effect answers to "Fire" and to "Fire Tile", and a unit to "Landmine" and
# "Landmine Unit", because the sheet's prose uses both — "Bombs Apply the Fire
# Tile" and "the fire will go away" are the same thing named two ways, and a strip
# that only recognised one of them would be a strip that worked on half the cards.
static func _catalog() -> Array:
	var out: Array = []
	for status in Data.all_statuses():
		out.append({
			"id": status.id, "kind": &"status", "name": status.display_name,
			"aliases": [status.display_name],
			"icon": status.image,
		})
	for tile in Data.all_tiles():
		out.append({
			"id": tile.id, "kind": &"tile", "name": "%s Tile" % tile.display_name,
			"aliases": ["%s tile" % tile.display_name, tile.display_name],
			"icon": tile.image,
		})
	for unit in Data.all_units():
		out.append({
			"id": unit.id, "kind": &"unit", "name": "%s Unit" % unit.display_name,
			"aliases": ["%s unit" % unit.display_name, unit.display_name],
			"icon": unit.image,
		})
	return out

# The hover body for one entry, asked of the content rather than assembled here.
# Stacks are quoted at 1, since a card describes the mechanic rather than a
# particular application of it.
#
# A status is described from BOTH SIDES. It used to quote the player's, on the
# reasoning that the player-side reading is the one they can act on — but a status
# is authored independently per side and the two are routinely opposites (§13.1).
# Staff of Flame reads "Apply +3 Burn to a target enemy", and the strip under it
# was explaining the obligation Burn puts on YOU: not a short version of the
# answer, the wrong half of it. `tooltip_both` prints one side when the other is
# inert and labels them when both do something.
static func describe(entry: Dictionary) -> String:
	match StringName(entry.get("kind", &"")):
		&"status":
			var status: StatusData = Data.get_status(entry["id"])
			return status.tooltip_both(1) if status != null else ""
		&"tile":
			var tile: TileEffectData = Data.get_tile(entry["id"])
			return tile.tooltip_for() if tile != null else ""
		&"unit":
			var unit: UnitData = Data.get_unit(entry["id"])
			return unit.tooltip_for() if unit != null else ""
	return ""

# --- drawing them ----------------------------------------------------------

# The strip's own colour. Deliberately the dim text colour rather than a hue of
# its own: a keyword chip is a footnote, and a card that already carries a rarity
# tint, a charge bar and a tag line does not need a fifth colour competing for the
# eye. The hover is where the information is.
const CHIP_TEXT := Color(0.72, 0.74, 0.80)

# Add the keyword strip for `text` to `host`, and return how many chips it added
# (0 when the text names nothing, in which case `host` is untouched). Safe to call
# on any card, which is the point — a description that grows a keyword later grows
# the strip with it, without the card having to be edited.
static func attach(host: Control, text: String) -> int:
	var found: Array = found_in(text)
	if host == null or found.is_empty():
		return 0
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 4)
	for entry in found:
		strip.add_child(chip(entry))
	host.add_child(strip)
	return found.size()

# One keyword chip: its art, its name, and the content's own words on hover.
static func chip(entry: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.tooltip_text = describe(entry)
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL, 6, 5, 1, UITheme.BORDER))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)
	var icon: Texture2D = entry.get("icon")
	if icon != null:
		row.add_child(UITheme.crisp_tex(icon, 16))
	var label := Label.new()
	label.text = String(entry.get("name", ""))
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", CHIP_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return wrap
