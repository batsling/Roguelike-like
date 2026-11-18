extends Control
# THE GAME JUST PLAYED, BEFORE THE HAUL (the owner, 18 Nov 2026: "before going to
# that section of the reward screen, there will be a screen that has the game you
# just beat/escaped and the experience points u got and what you got them from,
# with the bar going up as much as it did").
#
# Laid over the reward screen (PostCombatScreen) as its first page, so the haul is
# already built underneath and nothing about how a report resolves changes:
# Continue takes this page away and the inventory with the table is what is left.
# Everything on it is drawn by the reward screen's own builders — the header with
# the game's and the character's rank bars, the tally, a level-up, the chest's sum
# and who is still following — so the two pages cannot disagree.
#
# Loaded BY PATH with no class_name, like every screen the run page only opens on
# demand (test_page_load.gd).

signal continued

var _screen: Node = null

func setup(screen: Node) -> void:
	_screen = screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = UITheme.BG_DEEP
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = ModalScaffold.reserved_top
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 0)
	card.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 12, 18, 2, screen._accent()))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	card.add_child(col)

	# HOW IT WENT, on one line: the cover, the verdict and the game.
	col.add_child(screen._compact_header())
	# THE TWO BARS ARE THE PAGE (the owner, 18 Nov 2026: "make the two experience
	# bars the focus"): the game's and the character's, at full size, each filling
	# from where it stood when the game was picked, and under each the list of
	# what it was for and how much each thing gave. No tally of stats here.
	var g: GameData = screen.game()
	if g != null and screen._snap.has("rank_to"):
		col.add_child(_bar_block(g.cover_image, false,
			int(screen._snap.get("rank_from", 0)), int(screen._snap["rank_to"]),
			g.display_name, screen._snap.get("xp_sources", [])))
	var ch: CharacterData = Data.get_character2(StringName(screen._snap.get("character_id", "")))
	if screen._snap.has("character_rank_to"):
		col.add_child(_bar_block(ch.shown_icon() if ch != null else null, true,
			int(screen._snap.get("character_rank_from", 0)),
			int(screen._snap["character_rank_to"]),
			String(screen._snap.get("character_name", "")),
			screen._snap.get("character_xp_sources", [])))
	# The rest of the report, smaller, under the bars.
	var lvl: Control = screen._level_up_panel()
	if lvl != null:
		col.add_child(lvl)
	for masked in screen._snap.get("mask_level_ups", []):
		var m: Control = screen._level_up_block(masked)
		if m != null:
			col.add_child(m)
	# …how the chest size was worked out, and who is still following.
	var sum: Control = screen._chest_sum_row()
	if sum != null:
		col.add_child(sum)
	var board: Control = screen._board_panel()
	if board != null:
		col.add_child(board)

	var go := UITheme.confirm_button("Continue  →", Vector2(220, 44), UITheme.FONT_LABEL)
	go.name = "Continue"
	go.size_flags_horizontal = Control.SIZE_SHRINK_END
	go.pressed.connect(proceed)
	col.add_child(go)
	go.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		proceed()
		get_viewport().set_input_as_handled()

# On to the haul. Public so a test, or the page, can move past it.
func proceed() -> void:
	if is_queued_for_deletion():
		return
	continued.emit()
	queue_free()

# ONE BAR: the picture, the big rank bar, and a row per source of its XP —
# "+100  Beat the game" — so the number on each thing is readable at a glance.
const BAR_ART := 64

func _bar_block(art: Texture2D, character: bool, from: int, to: int, who: String,
		rows: Array) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 14, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	wrap.add_child(row)
	if art != null:
		var pic: TextureRect = UITheme.crisp_tex(art, BAR_ART) if character else TextureRect.new()
		if not character:
			pic.texture = art
			pic.custom_minimum_size = Vector2(BAR_ART * 0.75, BAR_ART)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var bar: RankFill = RankFill.make(from, to, who, character, false)
	bar.large = true
	bar.name = "CharacterBar" if character else "GameBar"
	col.add_child(bar)
	if rows.is_empty():
		var none := Label.new()
		none.text = "No XP this game." if to <= from else ""
		none.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		none.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		col.add_child(none)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UITheme.GAP_LOOSE)
	grid.add_theme_constant_override("v_separation", UITheme.GAP_HAIR)
	col.add_child(grid)
	for r in rows:
		var xp := Label.new()
		xp.text = "+%d" % int(r.get("xp", 0))
		xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		xp.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
		xp.add_theme_color_override("font_color", UITheme.GOLD)
		grid.add_child(xp)
		var what := Label.new()
		what.text = String(r.get("label", ""))
		what.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
		what.add_theme_color_override("font_color", UITheme.TEXT)
		grid.add_child(what)
	return wrap

static func source_text(rows: Array) -> String:
	var parts: PackedStringArray = []
	for r in rows:
		parts.append("+%d %s" % [int(r.get("xp", 0)), String(r.get("label", ""))])
	return "  ·  ".join(parts)
