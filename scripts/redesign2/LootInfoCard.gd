class_name LootInfoCard
extends Control

# LootInfoCard — the click-to-inspect card for one piece of loot, and the twin of
# ItemInfoCard (§4.3).
#
# A relic in the pack answered a click by opening its card; a pill in the loot
# window answered a click with nothing at all. Same class of object — a thing you
# are carrying — with two different gestures, and the one that did nothing was the
# one whose whole subject is "what IS this". So loot reads the same way now.
#
# READING IS NOT SPENDING. Like the item card, this only ever opens: the Use
# button here goes back through the page's `use_loot`, the same verb the window's
# own button calls, so there is one spend path and inspecting a piece can never
# cost you one by accident.
#
# An UNIDENTIFIED piece is the interesting case. The card deliberately has almost
# nothing to say about it — the mask is the gamble — so rather than draw a card
# full of blanks it says what it does know: the kind, the dose, and that spending
# it is how the question gets answered.

# The player spent it from the card; the host owns the pack.
signal use_requested(index: int)
signal closed

var _closing: bool = false

func setup(entry: Dictionary, index: int, usable: bool) -> void:
	if entry.is_empty():
		queue_free()
		return
	var known: bool = LootSystem.is_identified(entry)
	var pref: String = LootSystem.preference(entry)
	var tint: Color = UITheme.preference_color(pref) if known and pref != "" \
		else LootSystem.LOOT_COLOR

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			close())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 14, 0, 2, tint))
	center.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.72), 12, 14, 0))
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	header.add_child(head_row)
	var title := Label.new()
	title.text = LootSystem.display_name(entry)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.5))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_row.add_child(title)
	var close_btn := UITheme.quiet_button("✕", Vector2.ZERO, 15)
	close_btn.pressed.connect(close)
	head_row.add_child(close_btn)
	body.add_child(header)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	pad.add_child(inner)
	body.add_child(pad)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var art_frame := PanelContainer.new()
	art_frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 10, 8, 1, tint.lerp(UITheme.BG, 0.4)))
	art_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# At its own dose's size (§4.3) — a horse capsule is drawn oversized here for
	# the same reason it is in the pack: it is the one thing about a dose you can
	# read before you know anything else about it.
	art_frame.add_child(LootSystem.art_tex(entry, 88))
	top.add_child(art_frame)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 8)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.add_child(UITheme.chip(LootSystem.kind_name(entry), LootSystem.LOOT_COLOR))
	if known and pref != "":
		chips.add_child(UITheme.chip(pref, UITheme.preference_color(pref)))
	else:
		chips.add_child(UITheme.chip("Unidentified", UITheme.TEXT_DIM))
	text_col.add_child(chips)

	var desc := Label.new()
	desc.text = LootSystem.description(entry)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(250, 0)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	text_col.add_child(desc)
	# The KEYWORD STRIP (§17), on an IDENTIFIED piece only — the strip names the
	# mechanics the description names, and naming Burn and Fire under "you don't
	# know what this does" would give away the thing the mask is hiding.
	if known:
		Keywords.attach(text_col, LootSystem.description(entry))
	top.add_child(text_col)
	inner.add_child(top)

	# What Echo Chamber would add to this use, named before it is spent rather than
	# after — the relic changes what spending ONE piece means, and a player who
	# cannot see the copies coming cannot plan around them.
	var echo: String = _echo_line()
	if echo != "":
		var echo_lbl := Label.new()
		echo_lbl.text = echo
		echo_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		echo_lbl.add_theme_font_size_override("font_size", 11)
		echo_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		inner.add_child(echo_lbl)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_END
	if usable:
		var use_btn := UITheme.confirm_button("▶  Use", Vector2(0, 34))
		use_btn.pressed.connect(func():
			use_requested.emit(index)
			close())
		actions.add_child(use_btn)
	var done := UITheme.quiet_button("Close", Vector2(0, 34))
	done.pressed.connect(close)
	actions.add_child(done)
	inner.add_child(actions)

func _echo_line() -> String:
	var depth: int = GameState.loot_echo_depth()
	if depth <= 0:
		return ""
	var memory: Array = LootSystem.used_memory()
	if memory.is_empty():
		return "Echo Chamber: nothing used yet for it to copy."
	var names: Array = []
	for i in range(memory.size() - 1, maxi(0, memory.size() - depth) - 1, -1):
		names.append(LootSystem.display_name(memory[i]))
	return "Echo Chamber will also use: %s." % ", ".join(PackedStringArray(names))

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
