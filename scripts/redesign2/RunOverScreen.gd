class_name RunOverScreen
extends Control

# The end of a run — the screen a run actually FINISHES on.
#
# Before this, a finished run said so in a one-line banner over an overworld that
# was still sitting there with its board and its pack: nothing closed, nothing
# summed up, and the only way on was to notice the "⟳ New run" button in the page
# header. A roguelike's death screen is where the run gets read back to you, so
# this is that screen.
#
# Three parts, in the order they answer "what just happened":
#   VERDICT   — won or died, and to what.
#   THE RUN   — the numbers: games played and beaten, health left, what you were
#               carrying, how far the Amulet still was when it ended.
#   THE ROUTE — the games actually walked, cover by cover, ending on the Amulet
#               (dashed off if the run never got there) — the same shape Run
#               History draws a finished run in, because it IS the same picture.
#
# And then the three ways on: another run, the Atlas (this run laid over the whole
# influence graph), or the menu.
#
# Everything it reads is taken at build time, before anything resets the run, and
# every fact is also available as a plain method (verdict / stats / route_ids) so
# a headless test can assert what the screen says rather than how it looks.

signal finished              # dismissed — the overworld is underneath
signal restart_requested     # "another run"
signal menu_requested        # "back to the menu"

const COVER := Vector2(78, 104)
const ARROW_W := 24.0

var won: bool = false

var _layer: CanvasLayer = null
var _stats: Dictionary = {}
var _route: Array = []          # Array[StringName] — the games walked, in order
var _amulet: StringName = &""

# Mount over `host` on its own layer, so the overworld stays visible (dimmed)
# underneath — the board the run ended on is part of the story.
static func open(host: Node, did_win: bool) -> RunOverScreen:
	var screen := RunOverScreen.new()
	screen.won = did_win
	screen._layer = CanvasLayer.new()
	screen._layer.layer = 150
	screen._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(screen._layer)
	screen._layer.add_child(screen)
	return screen

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	theme = UITheme.shared()
	_snapshot()
	_build()

# ---------------------------------------------------------------------------
# What the run was — read once, before anything can reset it
# ---------------------------------------------------------------------------

func _snapshot() -> void:
	_amulet = GameState.amulet_game_id
	_route.clear()
	for id in GameState.visited_games:
		_route.append(StringName(id))
	var current: StringName = GameState.current_game_id
	if current != &"" and (_route.is_empty() or _route[_route.size() - 1] != current):
		_route.append(current)
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	_stats = {
		"character": ch.display_name if ch != null else String(GameState.character_id),
		"played": GameState.games_played,
		"beaten": GameState.total_games_beaten,
		"hp": GameState.hp,
		"max_hp": GameState.max_hp,
		"items": GameState.inventory.size(),
		"following": GameLoop2.stack.size(),
		"tier": RunDifficulty.tier_name(RunDifficulty.tier_for(GameState.games_played)),
		"steps_left": _steps_left(),
	}

# How far the Amulet still was when the run ended. 0 on a win (you were standing
# on it), -1 when nothing connected the two any more.
func _steps_left() -> int:
	if won:
		return 0
	var current: StringName = GameState.current_game_id
	if current == &"" or _amulet == &"":
		return -1
	var dist: Dictionary = RunGraph.bfs_distances(_amulet)
	return int(dist[current]) if dist.has(current) else -1

# --- the public read of this screen, for tests and for anything downstream ---

func verdict() -> String:
	return "won" if won else "lost"

func stats() -> Dictionary:
	return _stats.duplicate()

func route_ids() -> Array:
	return _route.duplicate()

# The headline, in the words the screen prints.
func headline() -> String:
	return "🏆  YOU WIN — THE AMULET IS YOURS" if won else "💀  THE RUN ENDS HERE"

func subtitle() -> String:
	var here: GameData = Data.get_game(_route[_route.size() - 1]) if not _route.is_empty() else null
	if won:
		var goal: GameData = Data.get_game(_amulet)
		return "You cleared %s — the Amulet game — in a run of %d game%s." % [
			goal.display_name if goal != null else "the Amulet game",
			int(_stats.get("played", 0)), "" if int(_stats.get("played", 0)) == 1 else "s"]
	var left: int = int(_stats.get("steps_left", -1))
	if left > 0:
		return "Health hit 0 at %s — %d step%s short of the Amulet." % [
			here.display_name if here != null else "the last game",
			left, "" if left == 1 else "s"]
	return "Health hit 0 at %s." % [here.display_name if here != null else "the last game"]

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _build() -> void:
	var accent: Color = UITheme.GOLD if won else UITheme.DANGER
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(UITheme.BG_DEEP, 0.88)
	add_child(scrim)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 40
	frame.offset_right = -40
	frame.offset_top = 30
	frame.offset_bottom = -30
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 12, 18, 2, accent))
	add_child(frame)

	var scroller := ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroller)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Centred in the frame when it all fits, scrolled when it doesn't — a verdict
	# pinned to the top of a mostly-empty panel reads as an unfinished screen.
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	scroller.add_child(col)

	var title := Label.new()
	title.text = headline()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", accent)
	col.add_child(title)

	var sub := Label.new()
	sub.text = subtitle()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", UITheme.TEXT)
	col.add_child(sub)

	col.add_child(_tally())
	col.add_child(_route_strip())
	col.add_child(_buttons(accent))

# The run in numbers, as a row of tiles.
func _tally() -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 12, 1))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 26)
	row.add_theme_constant_override("v_separation", 10)
	wrap.add_child(row)

	row.add_child(_tile("Character", String(_stats.get("character", "—"))))
	row.add_child(_tile("Games played", str(_stats.get("played", 0))))
	row.add_child(_tile("Games beaten", str(_stats.get("beaten", 0))))
	row.add_child(_tile("Health", "%d / %d" % [_stats.get("hp", 0), _stats.get("max_hp", 0)],
		UITheme.SUCCESS if int(_stats.get("hp", 0)) > 0 else UITheme.DANGER))
	row.add_child(_tile("Relics carried", str(_stats.get("items", 0))))
	row.add_child(_tile("Difficulty reached", String(_stats.get("tier", "—"))))
	var left: int = int(_stats.get("steps_left", -1))
	var distance: String = "reached it" if won else (
		"unreachable" if left < 0 else "%d step%s away" % [left, "" if left == 1 else "s"])
	row.add_child(_tile("Amulet", distance, UITheme.GOLD))
	if int(_stats.get("following", 0)) > 0:
		row.add_child(_tile("Still following", str(_stats.get("following", 0)), UITheme.DANGER))
	return wrap

func _tile(key: String, value: String, color: Color = UITheme.TEXT) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var k := Label.new()
	k.text = key.to_upper()
	k.add_theme_font_size_override("font_size", 10)
	k.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(k)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", color)
	box.add_child(v)
	return box

# The route walked, cover by cover, closing on the Amulet — the same picture Run
# History draws, so a run reads the same way the moment it ends as it does a
# month later.
func _route_strip() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = "The road you walked"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", UITheme.ACCENT.lerp(UITheme.TEXT, 0.25))
	wrap.add_child(head)

	var scroller := ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.custom_minimum_size.y = COVER.y + 36
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(scroller)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	scroller.add_child(strip)

	for i in range(_route.size()):
		strip.add_child(_stop(_route[i], _route[i] == _amulet))
		if i < _route.size() - 1:
			strip.add_child(_arrow())
	# A lost run still ends at the Amulet on this strip — with the gap it never
	# closed drawn dashed. That's what makes a loss legible as a loss.
	if _amulet != &"" and (_route.is_empty() or _route[_route.size() - 1] != _amulet):
		strip.add_child(_arrow(true))
		strip.add_child(_stop(_amulet, true))
	return wrap

func _stop(id: StringName, is_amulet: bool) -> Control:
	var game: GameData = Data.get_game(id)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size.x = COVER.x

	var frame := PanelContainer.new()
	var border: Color = UITheme.BORDER
	var border_w: int = 1
	if is_amulet:
		border = UITheme.GOLD if won else UITheme.DANGER
		border_w = 2
	frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG_DEEP, 4, 2, border_w, border))
	col.add_child(frame)

	if game != null and game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = COVER
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		frame.add_child(art)
	else:
		var blank := ColorRect.new()
		blank.custom_minimum_size = COVER
		blank.color = UITheme.PANEL
		frame.add_child(blank)

	var label := Label.new()
	label.text = ("🏆 " if is_amulet else "") + (game.display_name if game != null else String(id))
	label.custom_minimum_size.x = COVER.x
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.GOLD if is_amulet else UITheme.TEXT_DIM)
	col.add_child(label)
	return col

func _arrow(unreached: bool = false) -> Control:
	var a := RunHistoryScreen.RouteArrow.new()
	a.unreached = unreached
	a.custom_minimum_size = Vector2(ARROW_W, COVER.y)
	return a

func _buttons(accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var again := Button.new()
	again.text = "⟳  Another run"
	again.custom_minimum_size = Vector2(190, 42)
	again.add_theme_stylebox_override("normal", UITheme.flat(accent.lerp(UITheme.BG, 0.7), 8, 10, 2, accent))
	again.add_theme_color_override("font_color", accent)
	again.pressed.connect(func():
		restart_requested.emit()
		_close())
	row.add_child(again)

	var atlas := Button.new()
	atlas.text = "✦  See the run on the Atlas"
	atlas.custom_minimum_size = Vector2(0, 42)
	atlas.tooltip_text = "The whole influence graph, framed on the road this run walked."
	atlas.pressed.connect(_open_atlas)
	row.add_child(atlas)

	var menu := Button.new()
	menu.text = "←  Main menu"
	menu.custom_minimum_size = Vector2(0, 42)
	menu.pressed.connect(func():
		menu_requested.emit()
		_close())
	row.add_child(menu)

	var dismiss := Button.new()
	dismiss.text = "Look at the board"
	dismiss.custom_minimum_size = Vector2(0, 42)
	dismiss.tooltip_text = "Close this and leave the finished run on screen."
	dismiss.pressed.connect(_close)
	row.add_child(dismiss)
	return row

# The run at atlas altitude. Opened ON TOP of this screen, so closing the sky
# drops the player back onto the verdict rather than into a finished overworld.
func _open_atlas() -> void:
	if AtlasView.load_layout() == null:
		return
	var atlas := AtlasView.open(_layer if _layer != null else self)
	atlas.frame_trail.call_deferred()

func _close() -> void:
	finished.emit()
	# The screen goes with its layer — marked itself as well, so anything holding
	# a reference (the overworld's _run_over_screen, a test) can tell straight away
	# that this verdict is gone rather than waiting for the frame to end.
	queue_free()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
