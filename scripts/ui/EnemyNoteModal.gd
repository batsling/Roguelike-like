class_name EnemyNoteModal
extends RefCounted

# The editor for one (game, enemy) note — how the player beat that enemy at that
# game. Shared by the end-of-game checklist, which is where a note is usually
# written, and the Atlas, where it can be revisited later. One editor rather than
# two is what keeps them from drifting apart.
#
# A note belongs to the PAIR: the same goal-enemy turns up on many games and how
# you cleared it is a fact about that combination.

# Opens over `host`. `on_done` is called after a save or a delete so the caller
# can refresh whatever was showing the note; it is NOT called on cancel.
static func open(host: Node, game: GameData, enemy: GoalEnemyData,
		on_done: Callable = Callable()) -> void:
	if host == null or game == null or enemy == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 150
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UITheme.shared()
	layer.add_child(root)

	var close := func(): layer.queue_free()
	var panel := ModalScaffold.build_panel(root, UITheme.GOLD, close, Vector2(560, 420))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(box)
	panel.add_child(margin)

	# Header: the enemy's own art beside who and where, so there's no doubt which
	# pair is being written about.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	if enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(64, 64)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		header.add_child(art)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title := Label.new()
	title.text = "🗒  %s" % enemy.display_name
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	titles.add_child(title)
	var where := Label.new()
	where.text = "at %s%s" % [game.display_name,
		("   ·   " + enemy.goal) if enemy.goal != "" else ""]
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.add_theme_font_size_override("font_size", 12)
	where.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	titles.add_child(where)

	var edit := TextEdit.new()
	edit.text = GameStats.enemy_note(game.id, enemy.id)
	edit.placeholder_text = "How did you actually beat it? Build, route, what nearly killed you…"
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)

	# Delete only offered when there is something to delete, and it clears the
	# NOTE alone — how many times the enemy fell here is a record of fact, not a
	# note, so it stays.
	if GameStats.enemy_note(game.id, enemy.id).strip_edges() != "":
		var wipe := Button.new()
		wipe.text = "Delete note"
		wipe.add_theme_color_override("font_color", UITheme.DANGER)
		wipe.pressed.connect(func():
			GameStats.clear_enemy_note(game.id, enemy.id)
			if on_done.is_valid():
				on_done.call()
			close.call())
		buttons.add_child(wipe)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	buttons.add_child(cancel)

	var save := Button.new()
	save.text = "Save note"
	save.pressed.connect(func():
		GameStats.set_enemy_note(game.id, enemy.id, edit.text.strip_edges())
		if on_done.is_valid():
			on_done.call()
		close.call())
	buttons.add_child(save)
