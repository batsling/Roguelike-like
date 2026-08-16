class_name ItemInfoCard
extends Control

# ItemInfoCard — the click-to-inspect card for one item in the pack: a dimmed
# full-screen backdrop, large art, and everything the token's tooltip used to have
# to compress into a hover. It is the READING surface for an item; FIRING one is
# the token's own Use button / charge battery, so opening a card can never spend a
# charge by accident.
#
# It mounts on the SCREEN rather than inside the inventory row, because that row
# lives in a scrolling page and the card has to cover all of it. The host adds it
# and calls setup():
#
#     var card := ItemInfoCard.new()
#     card.use_requested.connect(use_item)
#     add_child(card)
#     card.setup(item)

# The player fired the item from the card; the host owns the charge.
signal use_requested(item: ItemData)
# The card dismissed itself (close button, backdrop click, or Use firing).
signal closed

var _closing: bool = false

# Fill the card in for one item. `usable` is whether it can actually fire right
# now — false while a game is mid-report, which is when the pack is read rather
# than spent.
func setup(item: ItemData, usable: bool) -> void:
	if item == null:
		queue_free()
		return
	var tint: Color = UITheme.item_color(item)

	# Full-screen dimmer; clicking outside the card closes it. The OFFSETS have to
	# be set along with the anchors: setup() runs once the card is already in the
	# tree, where anchors alone preserve the node's current (zero) rect.
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
	# Centred in what is left of the screen under the run's header bar, which is
	# pinned above this card's layer and would otherwise cover its title band.
	center.offset_top = ModalScaffold.reserved_top
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 14, 0, 2, tint))
	center.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)

	# Header band, tinted by rarity — the one fact about an item you read first.
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.72), 12, 14, 0))
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	header.add_child(head_row)
	var title := Label.new()
	title.text = item.display_name
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.5))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 15)
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

	# Art beside what the item DOES — the description is the reason the card was
	# opened, so it gets the room the token's tooltip could not give it.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var art_frame := PanelContainer.new()
	art_frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 10, 8, 1, tint.lerp(UITheme.BG, 0.4)))
	art_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art_frame.add_child(UITheme.crisp_tex(item.image, 96))
	top.add_child(art_frame)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 6)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if String(item.description) != "":
		var desc := Label.new()
		desc.text = item.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(270, 0)
		desc.add_theme_font_size_override("font_size", 14)
		text_col.add_child(desc)
	top.add_child(text_col)
	inner.add_child(top)

	# Rarity / behaviour-class / charge chips (§8) — the shape of the item rather
	# than its effect.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.add_child(_chip(UITheme.item_class_name(item), tint))
	chips.add_child(_chip(_kind_name(item), UITheme.ACCENT))
	if item.is_charged():
		chips.add_child(_chip("Charge %d/%d" % [item.current_charge, item.max_charge()],
			UITheme.GOLD if GameState.can_fire_item(item) else UITheme.TEXT_DIM))
	if String(item.source_game) != "":
		chips.add_child(_chip(item.source_game, UITheme.TEXT_DIM))
	inner.add_child(chips)

	# Tags are the synergy axis (§6.2) — what ties this item to an enemy's tag or a
	# goal — so they are worth naming rather than leaving to the sheet.
	if item.tags.size() > 0:
		var tags := Label.new()
		tags.text = "Tags:  %s" % ", ".join(item.tags)
		tags.add_theme_font_size_override("font_size", 11)
		tags.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		inner.add_child(tags)

	# The Use button, when this item can actually fire. Same wording and weight as
	# the token's, so the two paths to firing read as the same action.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_END
	if usable:
		var use_btn := Button.new()
		use_btn.text = "▶  Use"
		use_btn.custom_minimum_size = Vector2(0, 34)
		use_btn.add_theme_stylebox_override("normal",
			UITheme.flat(Color(0.10, 0.22, 0.16, 0.9), 10, 6, 1, Color(0.4, 0.9, 0.6)))
		use_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		use_btn.pressed.connect(func():
			use_requested.emit(item)
			close())
		actions.add_child(use_btn)
	var done := Button.new()
	done.text = "Close"
	done.pressed.connect(close)
	actions.add_child(done)
	inner.add_child(actions)

# The behaviour class in the sheet's own words (§8), so the card names the same
# thing `items2.0.Type` does.
func _kind_name(item: ItemData) -> String:
	match item.kind:
		ItemData.ItemKind.PICKUP:
			return "Pickup"
		ItemData.ItemKind.PASSIVE:
			return "Passive"
		ItemData.ItemKind.USABLE:
			return "Usable"
		ItemData.ItemKind.TRIGGERED:
			return "Triggered"
		ItemData.ItemKind.WEAPON:
			return "Weapon"
		ItemData.ItemKind.SCALING:
			return "Scaling"
		_:
			return "Charged" if item.is_charged() else "Item"

func _chip(text: String, color: Color) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(color.lerp(UITheme.BG, 0.72), 6, 6, 1, color.lerp(UITheme.BG, 0.35)))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	wrap.add_child(l)
	return wrap

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
