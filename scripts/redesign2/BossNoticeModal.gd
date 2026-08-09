class_name BossNoticeModal
extends Control

# BossNoticeModal — "the next game is a boss round" (docs/games-first-redesign.md
# §7.1), as a popup rather than a banner.
#
# It used to be a strip that appeared above the offering, which is exactly the
# wrong shape for it: the warning arrives between two games, so the strip shoved
# the offering, the checklist and the board down the page at the moment the
# player was reading them, and then sat there for the whole round taking a row of
# a page built to fit one screen. A thing that happens ONCE and has to be
# acknowledged is a popup; a thing that is true for a while is a banner. This is
# the first kind.
#
# What it says is the part a banner never had room for: a boss round is not
# "harder", it is a DIFFERENT SET OF RULES — every card on the table is a boss,
# bombs do nothing to one, and the way out of a card (bash / transmute /
# scramble) is still open but buys a different boss rather than a way past this.
#
# Built in code on its own CanvasLayer, like every other 2.0 modal.

signal finished

const PANEL_SIZE := Vector2(560, 0)
const ACCENT := Color(1.0, 0.62, 0.24)
const ART_PX := 96

var _tier_name: String = ""
var _bosses: Array = []              # GoalEnemyData standing on the offered cards
var _layer: CanvasLayer = null
var _panel: PanelContainer = null
var _done: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


# `bosses` are the bosses the offering is about to put on the table — the cards
# already name them one popup down (GameChoiceModal), so showing their portraits
# here gives away nothing and makes the warning about something rather than about
# the word "boss".
static func open(host: Node, tier_name: String, bosses: Array = []) -> BossNoticeModal:
	var modal := BossNoticeModal.new()
	modal._tier_name = tier_name
	modal._bosses = bosses
	modal._layer = CanvasLayer.new()
	modal._layer.layer = 123
	modal._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(modal._layer)
	modal._layer.add_child(modal)
	modal._build()
	return modal


func _build() -> void:
	# No click-outside-to-close: the whole point is that this one is read.
	_panel = ModalScaffold.build_panel(self, ACCENT, Callable(), PANEL_SIZE)
	_panel.custom_minimum_size = Vector2(PANEL_SIZE.x, 0)
	_panel.size = Vector2(PANEL_SIZE.x, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "⚠   BOSS INCOMING   ⚠"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	root.add_child(title)

	var sub := Label.new()
	sub.text = ("The run steps up to %s, and every game on the table now carries a boss."
		% _tier_name) if _tier_name != "" else \
		"Every game on the table now carries a boss."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UITheme.TEXT)
	root.add_child(sub)

	var portraits: Control = _portrait_row()
	if portraits != null:
		root.add_child(portraits)

	for line in [
		"A boss takes no damage from bombs — its goal is the only way it comes off the board.",
		"Bash, Transmute and Scramble still work; they buy you a different boss, not a way past this one.",
	]:
		var l := Label.new()
		l.text = "•  " + line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		root.add_child(l)

	var go := Button.new()
	go.text = "Face it"
	go.custom_minimum_size = Vector2(0, 42)
	go.add_theme_font_size_override("font_size", 16)
	go.add_theme_stylebox_override("normal", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.55), 8, 8, 2, ACCENT))
	go.add_theme_stylebox_override("hover", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.35), 8, 8, 2, ACCENT))
	go.add_theme_stylebox_override("focus", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.35), 8, 8, 2, ACCENT))
	go.add_theme_color_override("font_color", ACCENT.lerp(Color.WHITE, 0.5))
	go.pressed.connect(close)
	root.add_child(go)
	go.grab_focus.call_deferred()
	_settle.call_deferred()


# The bosses on the table, once each — the same boss can stand on two cards, and
# printing it twice would read as two of them. Null when the roster gave us no art
# to show, so the popup stays tight rather than keeping an empty row.
func _portrait_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var seen: Dictionary = {}
	for b in _bosses:
		var boss: GoalEnemyData = b
		if boss == null or boss.image == null or seen.has(boss.id):
			continue
		seen[boss.id] = true
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 6, 4, 1, ACCENT))
		frame.add_child(UITheme.crisp_tex(boss.image, ART_PX))
		col.add_child(frame)
		var name_lbl := Label.new()
		name_lbl.text = boss.display_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.custom_minimum_size = Vector2(ART_PX + 12, 0)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		col.add_child(name_lbl)
		row.add_child(col)
	return row if row.get_child_count() > 0 else null


# Centre the panel once it has a height — it is built with a width and no height
# so it can size to its own content, and ModalScaffold centres what it is given.
# Same fix, same reason, as ShopModal2._settle.
func _settle() -> void:
	await get_tree().process_frame
	if _panel == null or not is_instance_valid(_panel):
		return
	_panel.size = _panel.get_combined_minimum_size()
	var half: Vector2 = _panel.size * 0.5
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -half.x
	_panel.offset_top = -half.y
	_panel.offset_right = half.x
	_panel.offset_bottom = half.y


# Public so a headless test can dismiss it without a click.
func close() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	close()
