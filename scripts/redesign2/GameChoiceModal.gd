class_name GameChoiceModal
extends Control

# GameChoiceModal — "here is everything about this card; do you want it?" (§4).
#
# Picking a game used to be one click on its cover, and every fact that click
# needed had to be printed ON the cover: the route badge, the pace warning, the
# tries it grants, the repeat bonus, a Map button, a Beatable row, and the
# Bash/Transmute verbs. Seven stacked rows per card, which is why the covers had
# to be halved to fit three of them side by side (COVER_SIZE), and the whole
# offering still ran taller than the board beside it.
#
# So the click opens this instead. The card goes back to being what it should be
# — the box art and the name, with the Amulet flagged — and everything that was
# crowded around it moves in here, with room to say it properly:
#
#   • the OPTIMAL PATH, drawn as the real route ladder (RouteLadder) — the same
#     arrowed graph the 🗺 map window shows, for the road as it would stand if
#     you took this game;
#   • the GAME — its cover, its type and year, the tries it grants,
#     the pace it puts the board on, whether you've beaten it before;
#   • the ENEMY waiting there — portrait, name and the goal you'd be playing for;
#   • and the three things you can DO about it: travel, bash, transmute.
#
# It reports the answer back through `chose` / `bashed` / `transmuted` rather
# than reaching into the overworld, so the overworld's public verbs (pick,
# bash_choice, transmute_choice) stay the single way any of this happens and the
# tests that drive them keep working unchanged.
#
# Built in code on its own CanvasLayer, like every other 2.0 modal.

signal chose(index: int)
signal bashed(index: int)
signal transmuted(index: int)
signal finished

# Sized for the ROUTE, like the map window is. A shortest-path DAG five or six
# steps deep can be seven games wide on a well-connected layer, and a panel that
# only gives the ladder 480px shrinks that to the point where every rung reads
# "Spelunky…". The extra width buys legibility on the wide ones and costs the
# narrow ones nothing.
const PANEL_SIZE := Vector2(1140, 700)
const VIEW_MARGIN := Vector2(48, 56)
# The cover. Deliberately SMALLER than the offering card's own art rather than
# bigger: the box art is the one thing on this popup you have already seen — it
# is what you clicked — and at 210x280 it ate most of the left column, pushing the
# enemy, its goal and the statuses riding on it down under a scrollbar. The cover
# is now an identifier, not the exhibit, and the room it gives back goes to the
# thing you opened the popup to read.
const COVER := Vector2(132, 176)
# The ladder's own column. Wide enough for a rung (RouteLadder.BOX.x = 150) plus
# its padding, so a single-file route never has to shrink to fit.
const LADDER_MIN_W := 360.0
const LADDER_MIN_H := 300.0

var _index: int = -1
var _choice: Dictionary = {}
var _notes: Dictionary = {}          # {route, pace, tries, beatable} from the overworld
var _layer: CanvasLayer = null
var _answered: bool = false
var _ladder_holder: Control = null
var _ladder_room: ScrollContainer = null
var _zoom: float = 1.0
var _auto_zoomed: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point. `notes` carries the lines the overworld already knows how to write
# — its route_note and turn_note, plus the shield grant — so this screen never
# re-derives a number the cards used to quote and the two can't disagree.
static func open(host: Node, index: int, choice: Dictionary, notes: Dictionary = {}) -> GameChoiceModal:
	var modal := GameChoiceModal.new()
	modal._index = index
	modal._choice = choice
	modal._notes = notes
	modal._layer = CanvasLayer.new()
	modal._layer.layer = 124
	modal._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(modal._layer)
	modal._layer.add_child(modal)
	modal._build()
	return modal

func _build() -> void:
	var game: GameData = _choice.get("game")
	if game == null:
		_close()
		return
	var accent: Color = _accent()
	var panel := ModalScaffold.build_panel(self, accent, _close, _panel_size())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_build_header(game, accent))

	# The event waiting at this SPOT, if any (docs/event-sheet-authoring.md §12).
	# The card's badge says one is here; this is where it says WHICH, because the
	# popup is where the routing decision actually gets made (§4.2) and "is the
	# detour worth two games" is exactly the question an event answers.
	var event_row: Control = _build_event_row()
	if event_row != null:
		root.add_child(event_row)

	# The shop, if this game is one of the run's hubs (§14). Same argument as the
	# event row above, and one step further: a shop the player has ALREADY been to
	# lists what is still on its shelf, because the decision "is it worth walking
	# back to that hub" is unanswerable without knowing what is left there and
	# what it costs. This is the only place in the run that question gets asked.
	var shop_row: Control = _build_shop_row(game)
	if shop_row != null:
		root.add_child(shop_row)

	# The body, in two columns: the GAME on the left (what you'd be playing and
	# what it costs), the ROUTE on the right (where it leaves you). They are the
	# two halves of the decision and they belong side by side.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_game_column(game, accent))
	body.add_child(_build_route_column())

	root.add_child(_build_actions(game, accent))
	# The ladder is built at zoom 1 and only measured once Godot has laid the
	# panel out; until then the scroll area reports nothing to fit it against.
	_settle.call_deferred()

# Null when nothing is waiting, so an ordinary card stays clean.
func _build_event_row() -> Control:
	var ev: EventData2 = EventSystem.event_for(StringName(_choice.get("slot", &"")))
	if ev == null:
		return null
	var lbl := Label.new()
	lbl.text = "✦  %s waits here — beat this game and it fires, on top of the drop." % ev.display_name
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.ACCENT)
	return lbl


# Null off a hub, so an ordinary card stays clean. On one: the headline, then the
# remaining shelf as one priced line per item — but only once the player has
# stood in the shop. An unvisited shop says a shop is here and stops, because
# opening a card must not spoil a roll the player hasn't earned the sight of.
#
# Both the wording and the stock come from ShopSystem, which is also what the
# card's flag tooltip reads, so the two cannot disagree.
func _build_shop_row(game: GameData) -> Control:
	if game == null or not ShopSystem.is_hub(game.id):
		return null
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)

	var head := Label.new()
	head.text = "🛒  %s" % ShopSystem.headline(game.id)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
	col.add_child(head)

	for line in ShopSystem.stock_lines(game.id):
		var row := Label.new()
		row.text = "      • %s" % line
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		col.add_child(row)
	return col


func _panel_size() -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	return Vector2(
		minf(PANEL_SIZE.x, maxf(560.0, view.x - VIEW_MARGIN.x)),
		minf(PANEL_SIZE.y, maxf(420.0, view.y - VIEW_MARGIN.y)))

func _accent() -> Color:
	var game: GameData = _choice.get("game")
	if bool(_choice.get("amulet", false)):
		return UITheme.GOLD
	if bool(_choice.get("boss", false)):
		return UITheme.DANGER
	return UITheme.type_color(int(game.type)) if game != null else UITheme.ACCENT

# --- header ----------------------------------------------------------------

func _build_header(game: GameData, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = ("🏆 " if bool(_choice.get("amulet", false))
		else ("☠ " if bool(_choice.get("boss", false)) else "")) + game.display_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", accent)
	row.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Back to the offering — nothing is chosen."
	close.custom_minimum_size = Vector2(38, 0)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_close)
	row.add_child(close)
	return row

# --- the game column -------------------------------------------------------

func _build_game_column(game: GameData, accent: Color) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COVER.x + 66.0, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Shares the width with the route rather than being pinned to the cover: a
	# ladder needs about a third of the panel and the goal text is the thing that
	# suffers when it doesn't get the rest.
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.62
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(COVER.x + 40.0, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	if game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = COVER
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 8, 5, 1, accent))
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		frame.add_child(art)
		col.add_child(frame)

	var meta: Array = []
	if game.year > 0:
		meta.append(str(game.year))
	meta.append(RunGraph.type_label(game.type))
	var chip := Label.new()
	chip.text = "  •  ".join(meta).to_upper()
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_theme_font_size_override("font_size", 11)
	chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
	col.add_child(chip)

	# The tries this game hands you (§3) — the reason a Traditional roguelike is
	# worth routing through even when it isn't the short way. A card that only MOVES
	# the run grants none of them: nothing is being committed to yet.
	var tries: int = 0 if bool(_notes.get("move_only", false)) else int(_notes.get("tries", 0))
	if tries > 0:
		col.add_child(_fact_line("%s  %d tries" % ["◆".repeat(tries), tries],
			Overworld2.SHIELD_BLUE,
			"Selecting %s grants %d shields — one per run of it you lose." % [
				game.display_name, tries]))

	# What taking this does to the board's PACE (§7.4). Also a fact about playing a
	# game, so it goes with the tries on a move-only card.
	var pace: Dictionary = {} if bool(_notes.get("move_only", false)) else _notes.get("pace", {})
	if String(pace.get("text", "")) != "":
		col.add_child(_fact_line(String(pace["text"]), pace.get("color", UITheme.TEXT_DIM),
			String(pace.get("tip", ""))))

	# A game already beaten this run pays a Dash for beating it again.
	if bool(_choice.get("repeat", false)):
		col.add_child(_fact_line("⚡ Gain +%d Dash" % Overworld2.REPEAT_BEAT_DASH,
			Overworld2.DASH_BLUE,
			"You've already beaten %s this run — beat it again for a Dash charge." % game.display_name))

	var beaten: int = GameStats.beaten_count(game.id)
	if beaten > 0:
		col.add_child(_fact_line("⚔ Beaten %d time%s" % [beaten, "" if beaten == 1 else "s"],
			UITheme.GOLD, "Your lifetime record in %s." % game.display_name))

	col.add_child(HSeparator.new())
	col.add_child(_build_enemy_block(game))
	return scroll

# The enemy standing at this card: its portrait, its name, and the goal you would
# actually be playing for — clauses from your own statuses included (§13).
func _build_enemy_block(game: GameData) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var enemy: GoalEnemyData = _choice.get("enemy")

	var head := Label.new()
	head.text = "☠  THE BOSS HERE" if bool(_choice.get("boss", false)) else "WHAT'S WAITING THERE"
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(head)

	# A card opened to MOVE the run rather than to play a game (the stay-or-return
	# question, §10) has no enemy behind it — none is rolled until a game is
	# actually picked — so it says what it is instead of quoting a roll that hasn't
	# happened.
	if _notes.has("move_note"):
		head.text = "WHAT THIS DOES"
		var note := Label.new()
		note.text = String(_notes["move_note"])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 13)
		note.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		box.add_child(note)
		return box

	if enemy == null:
		var free := Label.new()
		free.text = "Nothing — %s is a free game." % game.display_name
		free.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		free.add_theme_font_size_override("font_size", 13)
		free.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		box.add_child(free)
		return box

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	if enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		# The half of the popup the cover just gave its height back to: the enemy is
		# the thing you cannot see from the offering, so it gets the bigger portrait.
		art.custom_minimum_size = Vector2(96, 96)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UITheme.apply_crisp(art, enemy.image)
		row.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = enemy.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color",
		UITheme.DANGER if bool(_choice.get("boss", false)) else UITheme.TEXT)
	row.add_child(name_lbl)

	var hp: int = GameLoop2.effective_health(enemy)
	var goal := RichTextLabel.new()
	goal.bbcode_enabled = true
	goal.fit_content = true
	goal.scroll_active = false
	goal.custom_minimum_size = Vector2(0, 40)
	goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal.text = "[b]GOAL (%s):[/b] %s\n[i]%s / %s / %d goal%s to beat / dmg %d[/i]" % [
		String(enemy.goal_type).capitalize(),
		GameLoop2.goal_text_for({"enemy": enemy, "statuses": {}}),
		String(enemy.game_type).capitalize(), RunDifficulty.tier_name(int(enemy.difficulty)),
		hp, "" if hp == 1 else "s", enemy.damage,
	]
	box.add_child(goal)

	# Your own record against what's on the board right now: the enemies you have
	# ALREADY beaten at this game, this one and every follower. Built by the
	# overworld (Overworld2._beatable_row) and handed over, so the offering and
	# this popup can't disagree about what counts as proven.
	var proven = _notes.get("beatable")
	if proven is Control:
		box.add_child(proven)
	return box

func _fact_line(text: String, color: Color, tip: String = "") -> Control:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tip
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	return l

# --- the route column ------------------------------------------------------

# The optimal path, as the real thing: the same layered DAG with green arrows the
# 🗺 map window draws, routed from the game this card is offering. This is what
# the card's Map button used to open in a separate window — it belongs in the
# decision, not one click further away from it.
func _build_route_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(LADDER_MIN_W, LADDER_MIN_H)

	# The route badge the card used to wear, at the head of the map that backs it up.
	var note: Dictionary = _notes.get("route", {})
	var badge := Label.new()
	badge.text = String(note.get("text", ""))
	badge.tooltip_text = String(note.get("tip", ""))
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", note.get("color", UITheme.TEXT))
	col.add_child(badge)

	var sub := Label.new()
	sub.text = "The optimal path to the Amulet if you take this game."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(sub)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG, UITheme.BORDER, 8, 6, 1))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(frame)
	_ladder_room = ScrollContainer.new()
	_ladder_room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ladder_room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The fit can only be measured once Godot has laid the panel out — until then
	# the scroll area has no size to fit anything against. This is what brings us
	# back when it does.
	_ladder_room.resized.connect(_settle)
	frame.add_child(_ladder_room)
	# A CenterContainer between the two, so a route that is narrower than the box —
	# a single-file road down one column, which most of them are — sits in the
	# middle of it rather than hard against the left edge. It takes the viewport's
	# width when the ladder is smaller and the ladder's when it isn't, so a wide
	# DAG still scrolls.
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ladder_room.add_child(centre)
	_ladder_holder = RouteLadder.build(_ladder_cfg())
	centre.add_child(_ladder_holder)

	var legend := Label.new()
	legend.text = "▶ where you'd be  •  🏆 the Amulet  •  ⚔ you've beaten an enemy there"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 11)
	legend.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(legend)
	return col

# The route from THIS game, as RouteLadder reads it. `preview` because the top
# rung is where you would be standing, not where you are; the rungs are inert —
# this popup is about one game, and a click on it should not open a second card
# over the buttons that answer it.
func _ladder_cfg() -> Dictionary:
	var slot: StringName = _choice.get("slot", &"")
	var amulet: StringName = GameState.amulet_game_id
	return {
		"data": RunGraph.route_dag_via(slot, &"", amulet) if slot != &"" and amulet != &"" else {},
		"current": slot,
		"amulet": amulet,
		"waypoint": &"",
		"choice_ids": {},
		"zoom": _zoom,
		"preview": true,
		"hide_amulet": false,
		"on_node": Callable(),
	}

# How many steps the ladder is showing. Public so a test can check the popup and
# the card's badge are quoting the same route.
func route_steps() -> int:
	var layers: Array = _ladder_cfg().get("data", {}).get("layers", [])
	return maxi(0, layers.size() - 1)

# Shrink a long route until the whole of it is in the box, rather than handing
# the player a scrollbar and a quarter of their road. Only on the way in — and
# only once the box has a real size, which is why this runs off `resized` as well
# as off the build: a fit measured against a zero-width scroll area is no fit at
# all, and `_auto_zoomed` would then have spent the one chance to get it right.
func _settle() -> void:
	if _auto_zoomed or _ladder_room == null or not is_inside_tree():
		return
	var room: Vector2 = _ladder_room.size
	if room.x <= 1.0 or room.y <= 1.0:
		return
	_auto_zoomed = true
	var fit: float = RouteLadder.fit_zoom(_ladder_holder.custom_minimum_size, room, _zoom)
	if fit < 0.995:
		_set_zoom(fit)

func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.4, 2.5)
	if _ladder_holder == null or not is_instance_valid(_ladder_holder):
		return
	var room: Node = _ladder_holder.get_parent()
	_ladder_holder.queue_free()
	_ladder_holder = RouteLadder.build(_ladder_cfg())
	room.add_child(_ladder_holder)

# --- the answer ------------------------------------------------------------

# The three things this card can become, on one row: the way in, and the two
# verbs that make it something else. Travel is the loud one; Bash and Transmute
# only appear when there is a charge to spend, and the Amulet's card refuses the
# bash outright rather than offering a button that argues back.
func _build_actions(game: GameData, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var move_only: bool = bool(_notes.get("move_only", false))
	if not move_only and GameState.bash > 0 and not bool(_choice.get("amulet", false)):
		row.add_child(_verb_button("⛏  Bash", UITheme.DANGER,
			"Destroy %s outright — it leaves the pool for good and another connected game takes the slot."
				% game.display_name,
			func(): _answer(bashed)))
	if not move_only and GameState.transmute > 0:
		row.add_child(_verb_button("⚗  Transmute", UITheme.ACCENT,
			"Swap %s for a random off-graph game of the same type." % game.display_name,
			func(): _answer(transmuted)))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(110, 44)
	back.pressed.connect(_close)
	row.add_child(back)

	var go := Button.new()
	go.text = String(_notes.get("action_text", "▶  Travel to %s" % game.display_name))
	go.tooltip_text = String(_notes.get("action_tip",
		"Commit to this game — you'll go and play it for real."))
	go.custom_minimum_size = Vector2(280, 44)
	go.clip_text = true
	go.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	go.add_theme_font_size_override("font_size", 16)
	go.add_theme_stylebox_override("normal", UITheme.flat(accent.lerp(UITheme.BG, 0.55), 8, 8, 2, accent))
	go.add_theme_stylebox_override("hover", UITheme.flat(accent.lerp(UITheme.BG, 0.38), 8, 8, 2, accent))
	go.add_theme_stylebox_override("focus", UITheme.flat(accent.lerp(UITheme.BG, 0.38), 8, 8, 2, accent))
	go.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.5))
	go.pressed.connect(func(): _answer(chose))
	row.add_child(go)
	# Deferred: `row` isn't mounted yet, and a Control outside the tree has no
	# focus to grab.
	go.grab_focus.call_deferred()
	return row

func _verb_button(text: String, tint: Color, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", UITheme.flat(tint.lerp(UITheme.BG, 0.78), 6, 10, 1, tint.lerp(UITheme.BG, 0.45)))
	b.add_theme_stylebox_override("hover", UITheme.flat(tint.lerp(UITheme.BG, 0.6), 6, 10, 1, tint))
	b.add_theme_color_override("font_color", tint)
	b.pressed.connect(cb)
	return b

# Public so a test can answer without a click.
func travel() -> void:
	_answer(chose)

func bash() -> void:
	_answer(bashed)

func transmute() -> void:
	_answer(transmuted)

func _answer(sig: Signal) -> void:
	if _answered:
		return
	_answered = true
	# Emitted BEFORE the modal comes down: bash and transmute rebuild the offering
	# behind it, and the overworld should be the thing that decides what happens
	# to this screen next.
	sig.emit(_index)
	_teardown()

func _close() -> void:
	if _answered:
		return
	_answered = true
	_teardown()

func _teardown() -> void:
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_close()
