class_name LiveNumbers
extends RefCounted

# THE NUMBERS IN A PIECE'S TEXT, AS THEY WILL LAND (the owner, 20 Nov 2026): "I'd
# like the new text on things to show the proper amount when factoring dex or
# power, with green text if higher than base and red if lower (lower from
# downgrades)."
#
# A piece's text is the sheet's own prose — "Gain +1 Temporary Shield and Apply
# Stun 1 to an Enemy" — and the prose stays the source. What changes is the two
# kinds of number in it that the run can move:
#
#   STUN    "Apply Stun 1", "Apply 1 Stun", "apply +1 Stun" — a stun the player
#           LAYS, which an upgrade or a downgrade moves (LootUpgrade) and Strength
#           on you grows (GameLoop2.player_stun). Only after "apply": "Every Weapon
#           adjacent to this Gains +1 Stun" is an aura on a weapon, not a stun.
#   SHIELD  "+1 Temporary Shield", "+2 Shields" — a Shield gain, which an upgrade
#           moves and Dexterity on you grows (GameState.grant_run_stat).
#
# Each number is handed to a callable that answers what it is NOW; one that moved
# is rewritten, and in `rich` mode coloured — SUCCESS above the sheet's number,
# DANGER below it. Text in which nothing moved comes back UNTOUCHED, rich or not,
# so a piece with no bonus never grows markup and every Label that shows it is
# unaffected.
#
# A `for each` clause shows its UNIT ("Apply Stun 3 ... for each loot destroyed"),
# and that is exact: Strength and Dexterity grow each unit, not the total (the
# owner, 20 Nov 2026 — see CardSystem._apply_one and GameState.grant_run_stat).

static var _stun_after: RegEx    # "Apply Stun 1"
static var _stun_before: RegEx   # "Apply 1 Stun", "apply +1 Stun"
static var _shield: RegEx        # "+1 Temporary Shield", "+2 Shields"

static func _compile() -> void:
	if _shield != null:
		return
	_stun_after = RegEx.create_from_string("(?i)\\bapply\\s+stun\\s+(\\+?)(\\d+)")
	_stun_before = RegEx.create_from_string("(?i)\\bapply\\s+(\\+?)(\\d+)\\s+stun\\b")
	_shield = RegEx.create_from_string("(\\+)(\\d+)(?=\\s+(?:Temporary\\s+)?Shields?\\b)")

# Does `text` carry this file's colour markup? HoverCard and `body` ask, to know
# whether to draw a RichTextLabel; plain prose never contains it.
static func is_rich(text: String) -> bool:
	return text.contains("[color=")

# `text` with every Stun number passed through `stun` and every Shield number
# through `shield` (int -> int, the sheet's number in, the live one out).
static func rewrite(text: String, stun: Callable, shield: Callable, rich: bool = false) -> String:
	if text == "":
		return text
	_compile()
	var spans: Array = []
	for re in [_stun_after, _stun_before]:
		for m in (re as RegEx).search_all(text):
			spans.append({"from": m.get_start(1), "to": m.get_end(2),
				"sign": m.get_string(1) != "", "base": int(m.get_string(2)), "fn": stun})
	for m in _shield.search_all(text):
		spans.append({"from": m.get_start(1), "to": m.get_end(2),
			"sign": true, "base": int(m.get_string(2)), "fn": shield})
	if spans.is_empty():
		return text
	spans.sort_custom(func(a, b): return int(a["from"]) < int(b["from"]))
	var moved: bool = false
	for sp in spans:
		sp["now"] = int((sp["fn"] as Callable).call(int(sp["base"])))
		moved = moved or int(sp["now"]) != int(sp["base"])
	if not moved:
		return text
	var out: String = ""
	var at: int = 0
	for sp in spans:
		var from: int = int(sp["from"])
		if from < at:
			continue   # overlapping matches cannot happen; this is the guard if one does
		out += _plain(text.substr(at, from - at), rich)
		out += _number(int(sp["base"]), int(sp["now"]), bool(sp["sign"]), rich)
		at = int(sp["to"])
	out += _plain(text.substr(at), rich)
	return out

# One number as it reads: signed when the sheet signed it ("+1" stays a "+",
# and a Shield card downgraded below nothing reads "-1"), coloured when it moved.
static func _number(base: int, now: int, signed: bool, rich: bool) -> String:
	var s: String = ("%+d" % now) if signed else str(now)
	if not rich or now == base:
		return s
	return colored(s, now > base)

# A word in the up or down colour — the same two every live number uses.
static func colored(s: String, up: bool) -> String:
	return "[color=#%s]%s[/color]" % [
		(UITheme.SUCCESS if up else UITheme.DANGER).to_html(false), s]

# Prose between numbers. In rich mode a "[" in it would be read as markup.
static func _plain(s: String, rich: bool) -> String:
	return s.replace("[", "[lb]") if rich else s

# A body line that can carry colour: a RichTextLabel when `text` is rich, else the
# Label it always was, so a screen with no live number in it is unchanged. A `size`
# of 0 leaves the theme's font size alone.
static func body(text: String, color: Color, size: int,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Control:
	if not is_rich(text):
		var l := Label.new()
		l.text = text
		l.horizontal_alignment = align
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if size > 0:
			l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", color)
		return l
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.horizontal_alignment = align
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	if size > 0:
		r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", color)
	r.text = text
	return r
