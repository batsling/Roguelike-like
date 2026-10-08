class_name TagEditor
extends VBoxContainer
# A game's tags, editable in place: the Collection's game page and the run map's
# game card both mount one. Everything it shows and changes goes through GameTags
# (the sheet's tags with the player's edits laid over them), so an edit made on
# one screen is already true on the other.
#
#   space ×  dice ×  [added] ×   + Tag
#
# A tag added here and not in the sheet yet is drawn in ember with "new" in its
# tooltip; a sheet tag taken off here stays visible, faint and struck through,
# so it can be put back with a click and nobody wonders where it went. "+ Tag"
# opens the vocabulary — every tag any game carries, as one-click chips, so a
# theme is spelled one way — and a box for a tag nobody has used yet.
#
# When any game has edits the sheet doesn't, a footer counts them and offers the
# Export (GameTags.export_edits), which `tools/apply_tag_edits.py` reads.
#
# It rebuilds itself on GameTags.tags_changed, so the screen around it never has
# to know an edit happened.

var game: GameData = null
var _open: bool = false
var _status: String = ""
var _chips: HFlowContainer
var _adder: VBoxContainer
var _footer: HBoxContainer

static func make(for_game: GameData) -> TagEditor:
	var ed := TagEditor.new()
	ed.game = for_game
	return ed

func _ready() -> void:
	add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameTags.tags_changed.connect(_on_tags_changed)
	_rebuild()

func _exit_tree() -> void:
	if GameTags.tags_changed.is_connected(_on_tags_changed):
		GameTags.tags_changed.disconnect(_on_tags_changed)

func _on_tags_changed(_id: StringName) -> void:
	# Every change, not only this game's: the footer counts edits across the
	# catalog, and the vocabulary grows when any game gains a new tag.
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if game == null:
		return
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", UITheme.GAP_TIGHT)
	_chips.add_theme_constant_override("v_separation", UITheme.GAP_TIGHT)
	add_child(_chips)
	var tags: PackedStringArray = GameTags.tags_of(game)
	for t in tags:
		_chips.add_child(_tag_button(t, GameTags.is_added(game, t)))
	for t in GameTags.removed_of(game):
		_chips.add_child(_removed_button(t))
	var add_btn := UITheme.quiet_button("+ Tag" if not _open else "Done", Vector2.ZERO, UITheme.FONT_SMALL)
	add_btn.name = "AddTag"
	add_btn.tooltip_text = "Add a tag to %s" % game.display_name if not _open else "Close the tag list"
	add_btn.pressed.connect(func() -> void:
		_open = not _open
		_status = ""
		_rebuild())
	_chips.add_child(add_btn)
	if tags.is_empty() and GameTags.removed_of(game).is_empty() and not _open:
		var none := Label.new()
		none.text = "No tags yet."
		none.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		none.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		_chips.add_child(none)
		_chips.move_child(none, 0)
	if _open:
		_adder = _build_adder(tags)
		add_child(_adder)
	_footer = _build_footer()
	if _footer != null:
		add_child(_footer)

# One of the game's tags, removed with a click.
func _tag_button(t: String, is_new: bool) -> Button:
	var color: Color = UITheme.ACCENT if is_new else Color(0.73, 0.55, 0.78)
	var btn := UITheme.action_button("%s  ×" % t, color, Vector2.ZERO, UITheme.FONT_SMALL)
	btn.name = "Tag_" + t
	btn.tooltip_text = ("Added here, not in the sheet yet (Export sends it). Click to take it off."
		if is_new else "From the sheet. Click to take it off %s." % game.display_name)
	btn.pressed.connect(func() -> void: GameTags.remove_tag(game, t))
	return btn

# A sheet tag taken off here: kept on view so it can be put back.
func _removed_button(t: String) -> Button:
	var btn := UITheme.quiet_button(t, Vector2.ZERO, UITheme.FONT_SMALL)
	btn.name = "Removed_" + t
	btn.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	btn.tooltip_text = "In the sheet, taken off here (Export sends the removal). Click to put it back."
	btn.text = "%s (removed)" % t
	btn.pressed.connect(func() -> void: GameTags.add_tag(game, t))
	return btn

func _build_adder(have: PackedStringArray) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Adder"
	box.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	var flow := HFlowContainer.new()
	flow.name = "Vocabulary"
	flow.add_theme_constant_override("h_separation", UITheme.GAP_TIGHT)
	flow.add_theme_constant_override("v_separation", UITheme.GAP_TIGHT)
	var removed: PackedStringArray = GameTags.removed_of(game)
	for t in GameTags.vocabulary():
		if have.has(t) or removed.has(t):
			continue  # a removed sheet tag already has its own chip to put it back
		var chip := UITheme.quiet_button(t, Vector2.ZERO, UITheme.FONT_SMALL)
		chip.name = "Offer_" + t
		chip.tooltip_text = "Tag %s as %s" % [game.display_name, t]
		chip.pressed.connect(func() -> void: GameTags.add_tag(game, t))
		flow.add_child(chip)
	box.add_child(flow)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	var field := LineEdit.new()
	field.name = "NewTag"
	field.placeholder_text = "a new tag"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	row.add_child(field)
	var ok := UITheme.confirm_button("Add", Vector2.ZERO, UITheme.FONT_SMALL)
	ok.name = "AddNew"
	var submit := func(text: String) -> void:
		if GameTags.normalize(text) == "":
			return
		if not GameTags.add_tag(game, text):
			_status = "%s already has \"%s\"." % [game.display_name, GameTags.normalize(text)]
			_rebuild()
	ok.pressed.connect(func() -> void: submit.call(field.text))
	field.text_submitted.connect(submit)
	row.add_child(ok)
	box.add_child(row)
	return box

# How many games have edits the sheet doesn't, and the way to send them.
func _build_footer() -> HBoxContainer:
	var n: int = GameTags.pending_count()
	if n == 0 and _status == "":
		return null
	var row := HBoxContainer.new()
	row.name = "Footer"
	row.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	var note := Label.new()
	note.name = "Pending"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	note.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	note.text = _status if _status != "" else \
		"%d game%s with tag edits not in the sheet yet." % [n, "" if n == 1 else "s"]
	row.add_child(note)
	if n > 0:
		var export_btn := UITheme.quiet_button("Export", Vector2.ZERO, UITheme.FONT_SMALL)
		export_btn.name = "Export"
		export_btn.tooltip_text = "Write every pending tag edit to %s, for tools/apply_tag_edits.py to put in the sheet. The edits stay live here until the sheet has them." % GameTags.export_path()
		export_btn.pressed.connect(func() -> void:
			var path: String = GameTags.export_edits()
			_status = ("Exported %d game%s to %s" % [n, "" if n == 1 else "s", path]) if path != "" \
				else "Couldn't write %s." % GameTags.export_path()
			_rebuild())
		row.add_child(export_btn)
	return row
