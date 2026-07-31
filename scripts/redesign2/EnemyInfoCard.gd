class_name EnemyInfoCard
extends Control

# EnemyInfoCard — the click-to-inspect card for one enemy on the battlefield: a
# dimmed full-screen backdrop, large art, and the enemy's goal / type / tier /
# stats laid out in readable blocks, plus the combat verbs aimed at that enemy so
# you can act straight from the card you are reading.
#
# It mounts on the SCREEN rather than inside the board, because the board lives in
# a scrolling page and the card has to cover all of it. The host adds it, calls
# setup(), and spends the Push / Bomb charge when the card asks:
#
#     var card := EnemyInfoCard.new()
#     card.push_requested.connect(push_follower)
#     add_child(card)
#     card.setup(entry, col, is_current)

# The player used a combat verb from the card; the host owns the charge.
signal push_requested(instance: int)
signal bomb_requested(instance: int)
# The card dismissed itself (close button, backdrop click, or a verb firing).
signal closed

var _closing: bool = false

# Fill the card in for one enemy. `col` is its FRONT column (OFFGRID_COL for an
# off-field body); `is_current` marks the game being played right now, which can be
# read but not pushed or bombed. Call once, right after adding the card to the
# screen it should cover.
func setup(entry: Dictionary, col: int, is_current: bool) -> void:
	var e: GoalEnemyData = entry.get("enemy")
	if e == null:
		queue_free()
		return
	var accent: Color = BattlefieldView.threat_color(col, e.is_boss())
	var instance: int = int(entry.get("instance", 0))

	# Full-screen dimmer; clicking outside the card closes it. The OFFSETS have to be
	# set along with the anchors: setup() runs once the card is already in the tree,
	# where anchors alone preserve the node's current (zero) rect.
	var overlay: Control = self
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	overlay.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			close())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(520, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 14, 0, 2, accent))
	center.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)

	# Header band, tinted by threat (front column red, boss orange).
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UITheme.flat(accent.lerp(UITheme.BG, 0.72), 12, 14, 0))
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	header.add_child(head_row)
	var title := Label.new()
	title.text = ("☠  " if e.is_boss() else "") + e.display_name
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.5))
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

	# Art beside the headline stats.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var art_frame := PanelContainer.new()
	art_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 10, 8, 1, accent.lerp(UITheme.BG, 0.4)))
	art_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var art := UITheme.crisp_tex(e.image, 132)
	art_frame.add_child(art)
	top.add_child(art_frame)

	var stat_col := VBoxContainer.new()
	stat_col.add_theme_constant_override("separation", 6)
	stat_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var hp: int = int(entry.get("health", e.health))
	stat_col.add_child(_stat_row("❤", "Health", "%d goal%s to defeat" % [hp, "" if hp == 1 else "s"], Color(1.0, 0.5, 0.5)))
	stat_col.add_child(_stat_row("⚔", "Damage", "%d per game, from the front" % e.damage, Color(1.0, 0.8, 0.35)))
	stat_col.add_child(_stat_row("◎", "Position", _position_text(entry, col, is_current), accent))
	if e.footprint_rows() > 1 or e.footprint_cols() > 1:
		stat_col.add_child(_stat_row("▦", "Size", _size_text(e), UITheme.TEXT_DIM))
	var stun: int = int(entry.get("stun", 0))
	if stun > 0:
		stat_col.add_child(_stat_row("❄", "Frozen", "skips its next %d game(s)" % stun, Color(0.6, 0.8, 1.0)))
	top.add_child(stat_col)
	inner.add_child(top)

	# Type / tier / source chips.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.add_child(_chip(String(e.game_type).capitalize(), UITheme.ACCENT))
	chips.add_child(_chip("Tier %s" % RunDifficulty.tier_name(int(e.difficulty)), UITheme.GOLD))
	if e.is_boss():
		chips.add_child(_chip("BOSS", Color(0.95, 0.55, 0.2)))
	if String(e.tag) != "":
		chips.add_child(_chip(String(e.tag), UITheme.TEXT_DIM))
	inner.add_child(chips)

	# The goal — the thing you actually have to do — gets its own panel.
	if e.goal != "":
		var goal_wrap := PanelContainer.new()
		goal_wrap.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 8, 12, 1, UITheme.GOLD.lerp(UITheme.BG, 0.55)))
		var goal_box := VBoxContainer.new()
		goal_box.add_theme_constant_override("separation", 3)
		var goal_hdr := Label.new()
		goal_hdr.text = "GOAL  (%s)" % String(e.goal_type).capitalize()
		goal_hdr.add_theme_font_size_override("font_size", 11)
		goal_hdr.add_theme_color_override("font_color", UITheme.GOLD)
		goal_box.add_child(goal_hdr)
		var goal_txt := Label.new()
		goal_txt.text = e.goal
		goal_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal_txt.custom_minimum_size = Vector2(460, 0)
		goal_txt.add_theme_font_size_override("font_size", 14)
		goal_box.add_child(goal_txt)
		goal_wrap.add_child(goal_box)
		inner.add_child(goal_wrap)

	if e.source_game != "":
		var src := Label.new()
		src.text = "From %s" % e.source_game
		src.add_theme_font_size_override("font_size", 12)
		src.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		inner.add_child(src)

	# Combat verbs, aimed at this enemy (a currently-played game isn't targetable).
	if not is_current and instance > 0:
		inner.add_child(HSeparator.new())
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 8)
		var can_push: bool = GameState.push > 0 and GameLoop2.can_push(instance)
		var pb := Button.new()
		pb.text = "⇤  Push back a column (%d)" % GameState.push
		pb.disabled = not can_push
		pb.tooltip_text = "The column behind is full — no room to shove it back." if (GameState.push > 0 and not can_push) else "Buys the games it takes to close back in."
		pb.pressed.connect(func():
			push_requested.emit(instance)
			close())
		acts.add_child(pb)
		# Bosses can be bombed too — they just take no damage from it (the reason
		# to spend one is Sticky Bombs' stun). GameLoop2.bomb_hint says which.
		var bb := Button.new()
		bb.text = "✸  Bomb (%d)" % GameState.bombs
		bb.disabled = GameState.bombs <= 0
		bb.tooltip_text = GameLoop2.bomb_hint(e)
		bb.pressed.connect(func():
			bomb_requested.emit(instance)
			close())
		acts.add_child(bb)
		inner.add_child(acts)

# Dismiss the card. Safe to call twice — the second call is a no-op.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()

# One "icon — label — value" row in the info card's stat column.
func _stat_row(icon: String, label: String, value: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ico := Label.new()
	ico.text = icon
	ico.add_theme_font_size_override("font_size", 16)
	ico.add_theme_color_override("font_color", color)
	ico.custom_minimum_size = Vector2(22, 0)
	row.add_child(ico)
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	name_lbl.custom_minimum_size = Vector2(76, 0)
	row.add_child(name_lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 14)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	return row

func _chip(text: String, color: Color) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", UITheme.flat(color.lerp(UITheme.BG, 0.72), 6, 6, 1, color.lerp(UITheme.BG, 0.35)))
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.35))
	wrap.add_child(l)
	return wrap

# Plain-language description of where an enemy stands and what that means. `col`
# is its FRONT column — the leading edge is what decides when it strikes, so a
# wide body reads as closer than its left-hand corner alone would suggest.
func _position_text(entry: Dictionary, col: int, is_current: bool) -> String:
	if is_current:
		return "off field — steps in when you report this game"
	if col >= GameLoop2.OFFGRID_COL:
		return "off field — waiting for room on the board"
	var lane: String = "row %d, " % (int(entry.get("row", 0)) + 1)
	if col <= 1:
		return lane + "front column — strikes every game"
	return "%scolumn %d — %d game(s) from striking" % [lane, col, col - 1]

# How much board an enemy takes up, spelled out for the info card.
func _size_text(e: GoalEnemyData) -> String:
	var cells: int = e.footprint_cells().size()
	var box: String = "%d x %d" % [e.footprint_rows(), e.footprint_cols()]
	if cells == e.footprint_rows() * e.footprint_cols():
		return "%s — %d cells of the board" % [box, cells]
	# A shaped body (an L) fills fewer cells than its box; say so, since the gap
	# is a real hole other enemies can stand in.
	var raw: String = String(e.size)
	var space: int = raw.find(" ")
	var shape: String = raw.substr(space + 1) if space >= 0 else ""
	return "%s %s — %d cells, the rest is a gap" % [box, shape, cells]
