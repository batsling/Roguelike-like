class_name EnemyNoteModal
extends RefCounted

# The editor for one PAIR note — the player's own write-up of something they did
# at a particular game. Two kinds share it:
#
#   * (game, enemy)     — how you beat that enemy at that game (`open`)
#   * (game, character) — how you hit that character's level-up there (`open_level_up`)
#
# Both are facts about the COMBINATION rather than about either half: the same
# goal-enemy turns up on many games, and a standing level-up condition ("Unlock a
# new Item", "Collect 3+ types of currency") reads completely differently game to
# game. One editor rather than one per kind is what keeps them from drifting
# apart — the checklist, the Atlas and the Collection all open this.

# Opens over `host` for the (game, enemy) note. `on_done` is called after a save
# or a delete so the caller can refresh whatever was showing the note; it is NOT
# called on cancel.
static func open(host: Node, game: GameData, enemy: GoalEnemyData,
		on_done: Callable = Callable()) -> void:
	if host == null or game == null or enemy == null:
		return
	_open(host, {
		"art": enemy.image,
		"title": enemy.display_name,
		"where": "at %s%s" % [game.display_name,
			("   ·   " + enemy.goal) if enemy.goal != "" else ""],
		"placeholder": "How did you actually beat it? Build, route, what nearly killed you…",
		"read": func(): return GameStats.enemy_note(game.id, enemy.id),
		"write": func(text): GameStats.set_enemy_note(game.id, enemy.id, text),
		"erase": func(): GameStats.clear_enemy_note(game.id, enemy.id),
	}, on_done)

# The same editor for the (game, character) LEVEL-UP note. The subject line is
# the character's condition, because that is the thing being written about — the
# character's face is only there to say whose condition it is.
static func open_level_up(host: Node, game: GameData, character: CharacterData,
		on_done: Callable = Callable()) -> void:
	if host == null or game == null or character == null:
		return
	var condition: String = character.level_up_condition.strip_edges()
	_open(host, {
		"art": character.icon if character.icon != null else character.portrait,
		"title": "%s — Level Up" % character.display_name,
		"where": "at %s%s" % [game.display_name,
			("   ·   " + condition) if condition != "" else ""],
		"placeholder": "How did you pull the level-up off here? What made it possible…",
		"read": func(): return GameStats.level_up_note(game.id, character.id),
		"write": func(text): GameStats.set_level_up_note(game.id, character.id, text),
		"erase": func(): GameStats.clear_level_up_note(game.id, character.id),
	}, on_done)

# The editor itself. `subject` carries everything that differs between the two
# kinds — the art, the two header lines, the placeholder, and the three
# accessors onto whichever GameStats log owns the text.
static func _open(host: Node, subject: Dictionary, on_done: Callable) -> void:
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

	# Header: the subject's own art beside who and where, so there's no doubt
	# which pair is being written about.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var art_tex: Texture2D = subject.get("art")
	if art_tex != null:
		var art := TextureRect.new()
		art.texture = art_tex
		art.custom_minimum_size = Vector2(64, 64)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		header.add_child(art)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title := Label.new()
	title.text = "🗒  %s" % String(subject.get("title", ""))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	titles.add_child(title)
	var where := Label.new()
	where.text = String(subject.get("where", ""))
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.add_theme_font_size_override("font_size", 12)
	where.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	titles.add_child(where)

	var read: Callable = subject["read"]
	var edit := TextEdit.new()
	edit.text = String(read.call())
	edit.placeholder_text = String(subject.get("placeholder", ""))
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)

	# Delete only offered when there is something to delete, and it clears the
	# NOTE alone — how many times the enemy fell here (or the level was taken) is
	# a record of fact, not a note, so it stays.
	if String(read.call()).strip_edges() != "":
		var wipe := Button.new()
		wipe.text = "Delete note"
		wipe.add_theme_color_override("font_color", UITheme.DANGER)
		wipe.pressed.connect(func():
			(subject["erase"] as Callable).call()
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
		(subject["write"] as Callable).call(edit.text.strip_edges())
		if on_done.is_valid():
			on_done.call()
		close.call())
	buttons.add_child(save)
