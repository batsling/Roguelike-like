class_name CharacterBadge
extends Control

# THE CHARACTER, IN A CIRCLE ON THE PLAYER (the owner, 13 Nov 2026). The board's
# hero frame draws the PLAYER now (docs/players-design.md §6), and the character
# the run is being played as rides on it as this: their icon clipped to a circle,
# ringed in gold, at the top-left of the frame. Hovering it opens the character's
# card — the full portrait and everything that matters about them this run
# (`card`), the read that the portrait used to give at a glance.
#
# The circle is drawn, not masked: a polygon whose UVs cover the texture, so the
# corners of a square icon simply are not drawn. No shader, no extra node.

const SEGMENTS := 48
const RING := 2.0

var character: CharacterData = null:
	set(v):
		character = v
		tooltip_text = character.display_name if character != null else ""
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP

func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	if r <= 0.0:
		return
	var c := Vector2(r, r)
	draw_circle(c, r, UITheme.GOLD)
	draw_circle(c, r - RING, UITheme.PANEL)
	var tex: Texture2D = character.shown_icon() if character != null else null
	if tex == null:
		return
	var inner: float = r - RING
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in range(SEGMENTS):
		var a: float = TAU * float(i) / float(SEGMENTS)
		var d := Vector2(cos(a), sin(a))
		pts.append(c + d * inner)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	draw_colored_polygon(pts, Color.WHITE, uvs, tex)

func _make_custom_tooltip(_for_text: String) -> Object:
	return CharacterBadge.card(character)

# THE CHARACTER'S CARD: the full portrait on the left and, beside it, what they
# are this run — name, where they are from, their level and how they level up
# (and what it pays), their Health, the gold and loot they started with, and
# their line. Public so a test can read it without a mouse.
const CARD_ART := 170
const CARD_WRAP := 260.0

static func card(ch: CharacterData) -> Control:
	if ch == null:
		return null
	var panel := PanelContainer.new()
	panel.name = "CharacterCard"
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(Color(UITheme.BG_DEEP, 0.985), 8, 10, 1, UITheme.GOLD.lerp(UITheme.BORDER, 0.35)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	panel.add_child(row)
	var art: Texture2D = ch.shown_portrait()
	if art == null:
		art = ch.shown_icon()
	if art != null:
		var pic := UITheme.crisp_tex(art, CARD_ART)
		pic.name = "Portrait"
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(_line(ch.display_name, UITheme.FONT_TITLE, UITheme.GOLD))
	if ch.source_game != "":
		col.add_child(_line("From: %s" % ch.source_game, UITheme.FONT_SMALL, UITheme.TEXT_FAINT))
	col.add_child(_line("Level %d  ·  ♥ %d / %d Health" % [maxi(1, GameState.player_level),
		GameState.hp, GameState.max_hp], UITheme.FONT_BODY, UITheme.TEXT))
	if ch.level_up_condition != "":
		col.add_child(_head("Levels up by"))
		col.add_child(_line(ch.level_up_condition, UITheme.FONT_BODY, UITheme.TEXT))
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			col.add_child(_line("→ %s" % ch.level_up_reward, UITheme.FONT_BODY,
				UITheme.GOLD.lerp(UITheme.TEXT, 0.35)))
	col.add_child(_head("Started with"))
	var kit: Array = ["◉ %d gold" % ch.start_gold]
	kit.append_array(Array(Data.loadout_names(ch)))
	col.add_child(_line(", ".join(PackedStringArray(kit)), UITheme.FONT_BODY,
		UITheme.TEXT.lerp(Color(0.7, 0.85, 0.95), 0.5)))
	if ch.description != "":
		col.add_child(_line(ch.description, UITheme.FONT_SMALL, UITheme.TEXT_DIM))
	return panel

static func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_WRAP, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	Cosmetics.apply_glyph(l)
	return l

static func _head(text: String) -> Label:
	var h := Label.new()
	h.text = text.to_upper()
	h.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	h.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return h
