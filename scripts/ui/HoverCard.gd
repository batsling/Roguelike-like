class_name HoverCard
extends RefCounted

# HoverCard — the small themed card that appears when the mouse rests on
# something you could click to read in full.
#
# The run draws four kinds of thing you can click for a card: an ENEMY on the
# board (EnemyInfoCard), an ITEM in the pack (ItemInfoCard), a STATUS on a body,
# and the ENEMY TURNS readout on the pressure bar. All four had a hover already
# and all four spent it on `tooltip_text` — Godot's stock tooltip, which is grey
# system chrome with a wall of plain text in it, on a page that is otherwise
# entirely hand-drawn. The information was there and nobody read it.
#
# This is the same information as a CARD: the art, the name in the thing's own
# colour, its statuses as pips, and the one or two lines that actually decide
# something. A condensed version of what clicking opens, which is what a hover is
# for — the fast read on the way past, with the full card one click away.
#
# ---------------------------------------------------------------------------
# How to use it
#
# Godot only calls `_make_custom_tooltip` on a Control whose OWN script defines
# it, and only when `tooltip_text` is non-empty. So a hoverable node is either a
# `HoverPanel` / `HoverBox` (the two wrappers below, which is what code-built
# panels and containers use) or a class that adds the two-line override itself:
#
#     func _make_custom_tooltip(_for_text: String) -> Object:
#         return HoverCard.of(self)
#
# and every one of them is filled in the same way:
#
#     HoverCard.attach(node, {"title": e.display_name, "accent": threat, ...})
#
# `attach` stores the model and seeds `tooltip_text`, so a build that somehow
# misses the override still shows the plain text rather than nothing.
#
# ---------------------------------------------------------------------------
# The model
#
#   title     String        the name, drawn in `accent`
#   accent    Color         the thing's own colour (threat tier, item class, …)
#   art       Texture2D     optional thumbnail, left of the title
#   subtitle  String        optional small dim line under the title (its class,
#                           its type — what it IS, as against what it does)
#   pips      Array         optional [{art: Texture2D, text: String, good: bool}]
#                           drawn as a compact row under the heading
#   lines     Array[String] the facts. KEEP IT TO TWO — this is the condensed
#                           read, and a card that needs four lines is a card the
#                           player should be clicking.
#   note      String        optional faint last line (a hint, a caveat)

const ART := 44.0
const WRAP := 250.0
const META := "hover_card"

# Store `cfg` on `node` and seed the plain tooltip Godot needs before it will ask
# for a custom one. Safe to call on any Control; the card only appears on the
# ones whose script defines `_make_custom_tooltip` (see the header).
static func attach(node: Control, cfg: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.set_meta(META, cfg)
	# The fallback text, and the switch that makes Godot ask at all. Title plus
	# the first fact is the most useful thing a plain string can be.
	var lines: Array = cfg.get("lines", [])
	var fallback: String = String(cfg.get("title", ""))
	if not lines.is_empty():
		fallback += "\n%s" % String(lines[0])
	node.tooltip_text = fallback if fallback.strip_edges() != "" else " "

# The card for whatever was attached to `node`, or null when nothing was — which
# is what `_make_custom_tooltip` must return to fall back to the plain tooltip.
static func of(node: Control) -> Control:
	if node == null or not node.has_meta(META):
		return null
	var cfg = node.get_meta(META)
	return build(cfg) if cfg is Dictionary else null

# Build the card itself. Public so a test can assert what a hover would say
# without going near the mouse.
static func build(cfg: Dictionary) -> Control:
	var accent: Color = cfg.get("accent", UITheme.GOLD)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.075, 0.065, 0.085, 0.985), 8, 10, 1,
			accent.lerp(UITheme.BORDER, 0.35)))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	# The heading: art on the left, name and what-it-is stacked beside it. The
	# art is what identifies the thing — it is the same picture the full card
	# opens with, and the reason this is a card rather than a sentence.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var art: Texture2D = cfg.get("art")
	if art != null:
		var tex := TextureRect.new()
		tex.texture = art
		tex.custom_minimum_size = Vector2(ART, ART)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tex)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 1)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	var title := Label.new()
	title.text = String(cfg.get("title", ""))
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", accent)
	names.add_child(title)
	var subtitle: String = String(cfg.get("subtitle", ""))
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.add_theme_font_size_override("font_size", 11)
		sub.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		names.add_child(sub)

	# What is riding on it, as icons rather than as a sentence. This is the half
	# of an enemy's state that a plain tooltip could only spell out, and spelling
	# out three statuses is three lines nobody reads on the way past.
	var pips: Array = cfg.get("pips", [])
	if not pips.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		col.add_child(row)
		for pip in pips:
			row.add_child(_pip(pip))

	for line in cfg.get("lines", []):
		var text: String = String(line).strip_edges()
		if text == "":
			continue
		var l := Label.new()
		l.text = text
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(WRAP, 0)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", UITheme.TEXT)
		col.add_child(l)

	var note: String = String(cfg.get("note", "")).strip_edges()
	if note != "":
		var n := Label.new()
		n.text = note
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.custom_minimum_size = Vector2(WRAP, 0)
		n.add_theme_font_size_override("font_size", 11)
		n.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		col.add_child(n)
	return panel

# One status pip: its art (or its initial when it has none) with the stack count
# beside it, gold for something working FOR the thing and red for a tax — the
# same reading the board's own chips use.
static func _pip(pip: Dictionary) -> Control:
	var good: bool = bool(pip.get("good", false))
	var tint: Color = UITheme.GOLD if good else UITheme.DANGER
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.75), 3, 2, 1, tint.lerp(UITheme.BORDER, 0.35)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	chip.add_child(row)
	var art: Texture2D = pip.get("art")
	if art != null:
		row.add_child(UITheme.crisp_tex(art, 14))
	var label := Label.new()
	label.text = String(pip.get("text", ""))
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", tint)
	row.add_child(label)
	return chip
