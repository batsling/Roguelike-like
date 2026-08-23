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
#     card.setup(entry, col)

# The player used a combat verb from the card; the host owns the charge.
signal push_requested(instance: int)
signal bomb_requested(instance: int)
# The card dismissed itself (close button, backdrop click, or a verb firing).
signal closed

var _closing: bool = false

# Fill the card in for one enemy. `col` is its FRONT column (offgrid_col() for an
# off-field body). Call once, right after adding the card to the screen it should
# cover.
#
# There used to be an `is_current` flag here for "the enemy of the game being
# played", which could be read but not pushed or bombed. No body is that any more
# (GameLoop2.arrivals) — every card offers both verbs.
#
# `position_note` replaces the Position line for an enemy that is not on the board
# at all — the boss notice reads one off an OFFERED CARD, where "waiting for room"
# would be a lie about a body that does not exist yet.
func setup(entry: Dictionary, col: int, position_note: String = "") -> void:
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
	# Damage as it stands, with the authored number in brackets when a status has
	# moved it (§13.4). Both, because "⚔4" alone tells you what is coming and
	# "⚔4 (2 base)" tells you WHY — and why is what decides whether bombing the
	# body or clearing the Strength off it is the better move.
	var dmg: int = GameLoop2.enemy_damage(entry)
	var dmg_note: String = "%d per game, from the front" % dmg
	if dmg != int(e.damage):
		dmg_note += "  (%d before statuses)" % int(e.damage)
	stat_col.add_child(_stat_row("⚔", "Damage", dmg_note, Color(1.0, 0.8, 0.35)))
	# Shields only when it has some to spend: a body with none is the normal case
	# and a "◆ Shield: 0" row on every card is a line of noise per enemy.
	var shield: int = GameLoop2.enemy_shield(entry)
	if shield > 0:
		stat_col.add_child(_stat_row("◆", "Shield",
			"absorbs the next %d damage" % shield, Color(0.62, 0.78, 0.95)))
	stat_col.add_child(_stat_row("◎", "Position",
		position_note if position_note != "" else _position_text(entry, col), accent))
	if e.footprint_rows() > 1 or e.footprint_cols() > 1:
		stat_col.add_child(_stat_row("▦", "Size", _size_text(e), UITheme.TEXT_DIM))
	var stun: int = int(entry.get("stun", 0))
	if stun > 0:
		# A stun costs one TURN, and a turn is what a lost run buys the board (§3.2)
		# — so a stun is a lost run this body sits out. Reporting a game adds the
		# Amulet's extra turns on top (§7.4), and the card names those too when
		# there are any, since they are turns the stun also eats.
		var extra: int = GameLoop2.enemy_turns()
		var worth: String = "sits out your next %d lost run(s)" % stun
		if extra > 0:
			worth += ", or %d of the %d turns reporting a game buys them" % [
				mini(stun, extra), extra]
		stat_col.add_child(_stat_row("❄", "Frozen", worth, Color(0.6, 0.8, 1.0)))
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

	# Statuses riding this body (§13) — art, name and stack count, on their own row
	# rather than crammed into the chip strip, because the card is where a player
	# comes to actually READ what is on an enemy. Tinted by what their ENEMY side
	# does rather than by Buff/Debuff: a `clause` tightened this enemy's goal and is
	# bad news, a `bonus` is free reward. That is the opposite reading from the
	# player's own strip, which is the point.
	var statuses: Array = GameLoop2.enemy_statuses(entry)
	if not statuses.is_empty():
		# …and a BOSS says which of them it is ignoring (§7.1). An `instead` buys
		# nothing on a boss, and a chip that reads like a way out on the one body
		# that has none is the worst place in the run to be vague.
		var dead: Dictionary = {}
		for row in GameLoop2.nullified_alternatives_for(entry):
			var sd: StatusData = row["status"]
			if sd != null:
				dead[sd.id] = true
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 8)
		for row in statuses:
			var st: StatusData = row["status"]
			strip.add_child(_status_chip(st, int(row["stacks"]),
				st != null and dead.has(st.id), int(row.get("games", 0))))
		inner.add_child(strip)

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
		# The LIVE goal line, not the authored stem: a buff on this enemy or a
		# clause on the player has been ANDed onto what actually has to be done
		# (§13), and this card is where a player comes to read exactly that.
		goal_txt.text = GameLoop2.goal_text_for(entry)
		goal_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		goal_txt.custom_minimum_size = Vector2(460, 0)
		goal_txt.add_theme_font_size_override("font_size", 14)
		goal_box.add_child(goal_txt)
		# The WAY OUT, if something burned this body (§13): the goal line above
		# already carries it, and this repeats it as its own line for the same
		# reason a bonus gets one — it is a separate decision from the goal, and the
		# one line on this card that says the goal need not be done at all.
		for row in GameLoop2.alternatives_for(entry):
			var asd: StatusData = row["status"]
			var alt := Label.new()
			# ↻ rather than ↺: the shipped glyph subsets carry what the source
			# already uses (see tools/build_glyph_font.py) and this one is in them.
			alt.text = "↻  Or instead: %s" % asd.alternative_text(
				StatusData.ENEMY, int(row["stacks"]))
			alt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			alt.custom_minimum_size = Vector2(460, 0)
			alt.add_theme_font_size_override("font_size", 12)
			alt.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.3))
			goal_box.add_child(alt)
		# Optional bonus objectives hanging off this enemy (§13) — inside the goal
		# panel, since they are read at the same moment, but visibly a separate
		# line because skipping one costs nothing (§13).
		for row in GameLoop2.bonus_objectives_for(entry):
			var sd: StatusData = row["status"]
			var bonus := Label.new()
			bonus.text = "+  %s" % sd.objective_text(StatusData.ENEMY, int(row["stacks"]))
			bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bonus.custom_minimum_size = Vector2(460, 0)
			bonus.add_theme_font_size_override("font_size", 12)
			bonus.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.3))
			goal_box.add_child(bonus)
		goal_wrap.add_child(goal_box)
		inner.add_child(goal_wrap)

	if e.source_game != "":
		var src := Label.new()
		src.text = "From %s" % e.source_game
		src.add_theme_font_size_override("font_size", 12)
		src.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		inner.add_child(src)

	# Combat verbs, aimed at this enemy. Every enemy — nothing on the board is
	# exempt from them now.
	if instance > 0:
		inner.add_child(HSeparator.new())
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 8)
		var can_push: bool = GameState.push > 0 and GameLoop2.can_push(instance)
		var pb := Button.new()
		pb.text = "⇤  Push back a column (%d)" % GameState.push
		pb.disabled = not can_push
		# The card's button is the BACK push only — the shorthand for the common
		# case. The other three directions are aimed on the board itself, where the
		# arrows can sit against the body they'd move (BattlefieldView's push mode).
		pb.tooltip_text = ("The column behind is full — no room to shove it back."
			if (GameState.push > 0 and not can_push)
			else "Buys the games it takes to close back in.\nTo shove it forward or across a lane instead, use ⇤ Push on the board's toolbar.")
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

# One status riding this enemy (§13): its art, its name and stack count, and the
# live line it adds — spelled out here rather than left to a hover, because the
# card is the place a player has already stopped to read.
const STATUS_ART := 28

func _status_chip(status: StatusData, stacks: int, nullified: bool = false,
		games: int = 0) -> Control:
	# A nullified way-out never reads as good news, whatever side it is on (§7.1).
	var good: bool = status.is_bonus(StatusData.ENEMY) and not nullified
	var tint: Color = UITheme.GOLD if good else UITheme.DANGER
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.80), 6, 5, 1, tint.lerp(UITheme.BG, 0.35)))
	wrap.tooltip_text = status.tooltip_for(StatusData.ENEMY, stacks, nullified, games)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	wrap.add_child(row)
	if status.image != null:
		var art := UITheme.crisp_tex(status.image, STATUS_ART)
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(art)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var name_lbl := Label.new()
	name_lbl.text = "%s %d" % [status.display_name, stacks]
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.35))
	col.add_child(name_lbl)
	var what := Label.new()
	if nullified:
		# The whole reason this chip is drawn at all: the stacks are on the body,
		# and what they would have bought is not available on this one.
		what.text = "nullified — a boss comes off the board on its goal alone"
	elif status.is_alternative(StatusData.ENEMY):
		what.text = "or instead: %s" % status.alternative_text(StatusData.ENEMY, stacks)
	elif good:
		what.text = status.objective_text(StatusData.ENEMY, stacks)
	else:
		what.text = "goal also needs: %s" % status.clause_text(StatusData.ENEMY, stacks)
	what.add_theme_font_size_override("font_size", 11)
	what.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.custom_minimum_size = Vector2(330, 0)
	col.add_child(what)
	return wrap

# Plain-language description of where an enemy stands and what that means. `col`
# is its FRONT column — the leading edge is what decides when it strikes, so a
# wide body reads as closer than its left-hand corner alone would suggest.
func _position_text(entry: Dictionary, col: int) -> String:
	if col >= GameLoop2.offgrid_col():
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
