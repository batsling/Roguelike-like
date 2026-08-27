class_name GraveyardPanel
extends Control

# GraveyardPanel — THE FALLEN: every enemy this run has put down, in the order
# they went down (docs/games-first-redesign.md §7.6).
#
# It reads `GameLoop2.graveyard`, which is the same list Necromancy raises from —
# so the panel is not a scrapbook bolted onto the run, it is the player being
# shown a thing the rules already care about. A Morana on the board makes this
# list a threat forecast: what is in here is what is coming back.
#
# Each row does two things:
#   - CLICK IT and the ordinary enemy card opens over the panel (EnemyInfoCard),
#     read-only, because a dead body has no instance to aim a Push or a Bomb at.
#   - WRITE ON IT. The note is stored against the (game, enemy) PAIR in
#     GameStats.enemy_log — the same lifetime store the Atlas's per-game notes
#     use, so "how I finally did the Spike Slime on Slay the Spire" is one fact
#     written once and read in both places. That pairing is why the row remembers
#     which game it fell at.
#
# The host adds it and calls setup():
#
#     var panel := GraveyardPanel.new()
#     add_child(panel)
#     panel.setup()

signal closed

var _closing: bool = false
var _list: VBoxContainer
var _empty: Label

const ROW_ART: int = 44
const PANEL_WIDTH: int = 560
const BONE := Color(0.78, 0.78, 0.86)

func setup() -> void:
	# Full-screen dimmer; clicking outside closes. Offsets alongside the anchors,
	# because setup() runs once the node is already in the tree, where anchors
	# alone preserve its current (zero) rect.
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
	card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 14, 0, 2, BONE))
	center.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel",
		UITheme.flat(BONE.lerp(UITheme.BG, 0.78), 12, 14, 0))
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	header.add_child(head_row)
	var title := Label.new()
	title.text = "☠  The Fallen"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", BONE.lerp(Color.WHITE, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(close)
	head_row.add_child(close_btn)
	body.add_child(header)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	pad.add_child(inner)
	body.add_child(pad)

	var blurb := Label.new()
	# Said plainly, because it is the reason the panel is worth opening rather
	# than a decoration on it.
	blurb.text = ("Everything you have put down this run — however it went down. " +
		"A Necromancer raises from this list, so what is in here can come back.")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 0)
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	inner.add_child(blurb)

	# Scrolled, because a long run's graveyard is longer than any screen. Capped
	# rather than sized to content for the same reason.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_empty = Label.new()
	_empty.text = "Nothing has died yet."
	_empty.add_theme_font_size_override("font_size", 13)
	_empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	inner.add_child(_empty)

	refill()

# Rebuild the list from the loop. Public so a note saved on one row can redraw the
# panel without the host having to tear it down and put it back.
func refill() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	# NEWEST FIRST. The loop appends as bodies fall, so the tail is the most recent
	# — and the most recent is what the player is still thinking about.
	var rows: Array = GameLoop2.graveyard.duplicate()
	rows.reverse()
	for row in rows:
		var e: GoalEnemyData = row.get("enemy")
		if e != null:
			_list.add_child(_row(e, StringName(row.get("game", &""))))
	if _empty != null:
		_empty.visible = rows.is_empty()

# One fallen body: its portrait, its name, the game it fell at, and the note.
func _row(enemy: GoalEnemyData, game_id: StringName) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 8, 8, 1, BONE.lerp(UITheme.BG, 0.6)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	wrap.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)

	# The portrait and the name are ONE BUTTON, so the whole of "who this was"
	# opens the card. The note field below is deliberately outside it — clicking
	# into a text box must not also throw a full-screen card over the box.
	var open := Button.new()
	open.flat = true
	open.add_theme_font_size_override("font_size", 14)
	open.text = ("☠  " if enemy.is_boss() else "") + enemy.display_name
	open.tooltip_text = "Open its card — goal, stats and abilities."
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.pressed.connect(func(): inspect(enemy))
	if enemy.image != null:
		var art := UITheme.crisp_tex(enemy.image, ROW_ART)
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(art)
	top.add_child(open)

	# THE ⚠ RIDES ALONG. A body with an ability is one the player wants to
	# recognise on sight, and a Necromancer's list is exactly where recognising it
	# early matters: this is a forecast of what is walking back on.
	if not enemy.abilities.is_empty():
		var mark := Label.new()
		mark.text = "⚠"
		mark.add_theme_font_size_override("font_size", 14)
		mark.add_theme_color_override("font_color", BattlefieldView.ABILITY_MARK)
		mark.tooltip_text = enemy.ability_text
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(mark)

	var game: GameData = Data.get_game(game_id)
	var where := Label.new()
	where.text = "fell at %s" % (game.display_name if game != null else "somewhere on the road")
	where.add_theme_font_size_override("font_size", 11)
	where.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	col.add_child(where)

	# THE NOTE, against the (game, enemy) pair — the same store the Atlas writes
	# (GameStats.enemy_log), so a note left here is a note found there. A body that
	# fell somewhere the run cannot name has nowhere to file one, and gets no box
	# rather than a box that silently throws what you type away.
	if game_id != &"":
		var note := LineEdit.new()
		note.placeholder_text = "How did you do it? (saved against %s)" % (
			game.display_name if game != null else String(game_id))
		note.text = GameStats.enemy_note(game_id, enemy.id)
		note.add_theme_font_size_override("font_size", 12)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Saved on focus-out as well as on Enter: a player who types a note and
		# clicks the ✕ has written it, and losing it there would teach them not to
		# use the box at all.
		note.text_submitted.connect(func(text: String):
			GameStats.set_enemy_note(game_id, enemy.id, text))
		note.focus_exited.connect(func():
			GameStats.set_enemy_note(game_id, enemy.id, note.text))
		col.add_child(note)
	return wrap

# Open the ordinary enemy card on one of the dead, over this panel. Handed the
# shape of entry the stack holds, with INSTANCE 0 — no body is standing there, and
# instance 0 is also what keeps the card read-only, since Push and Bomb are aimed
# at an instance and the card offers neither without one.
#
# Public so a headless test can open it without a click.
func inspect(enemy: GoalEnemyData) -> EnemyInfoCard:
	if enemy == null:
		return null
	var card := EnemyInfoCard.new()
	add_child(card)
	card.setup({
		"instance": 0, "enemy": enemy, "stun": 0,
		"health": GameLoop2.effective_health(enemy),
		"col": GameLoop2.offgrid_col(), "row": 0, "statuses": {},
		"abilities": enemy.abilities.duplicate(true),
	}, GameLoop2.offgrid_col(), "defeated — this one is already off the board")
	return card

# Dismiss the panel. Safe to call twice — the second call is a no-op.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
