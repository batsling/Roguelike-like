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

	# The game, how it went, and both rank bars filling (the reward screen's own
	# header, which tweens each bar from where it stood when the game was picked).
	col.add_child(screen._header())
	# …and under each bar, WHAT IT WAS FOR.
	var sources := _sources_block()
	if sources != null:
		col.add_child(sources)

	col.add_child(screen._tally_panel())
	var lvl: Control = screen._level_up_panel()
	if lvl != null:
		col.add_child(lvl)
	for masked in screen._snap.get("mask_level_ups", []):
		var m: Control = screen._level_up_block(masked)
		if m != null:
			col.add_child(m)
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

# "+100 Beat the game · +40 Monkey", one line per bar, under the header.
func _sources_block() -> Control:
	var game_rows: Array = _screen._snap.get("xp_sources", [])
	var hero_rows: Array = _screen._snap.get("character_xp_sources", [])
	if game_rows.is_empty() and hero_rows.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	var g: GameData = _screen.game()
	if not game_rows.is_empty():
		box.add_child(_source_line(g.display_name if g != null else "The game", game_rows))
	if not hero_rows.is_empty():
		box.add_child(_source_line(String(_screen._snap.get("character_name", "You")), hero_rows))
	return box

static func source_text(rows: Array) -> String:
	var parts: PackedStringArray = []
	for r in rows:
		parts.append("+%d %s" % [int(r.get("xp", 0)), String(r.get("label", ""))])
	return "  ·  ".join(parts)

func _source_line(who: String, rows: Array) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UITheme.GAP)
	var name := Label.new()
	name.text = "%s:" % who
	name.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	name.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	line.add_child(name)
	var what := Label.new()
	what.text = source_text(rows)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	what.add_theme_color_override("font_color", UITheme.GOLD)
	line.add_child(what)
	return line
