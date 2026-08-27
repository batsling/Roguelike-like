class_name GameChoiceModal
extends Control

# GameChoiceModal — "here is everything about this card; do you want it?" (§4).
#
# Picking a game used to be one click on its cover, and every fact that click
# needed had to be printed ON the cover: the route badge, the pace warning, the
# Temporary Shields it grants, the repeat bonus, a Map button, a Beatable row, and the
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
#   • the GAME — its cover, its type and year, the Temporary Shields it grants,
#     the pace it puts the board on, whether you've beaten it before;
#   • the ENEMY waiting there — portrait, name and the goal you'd be playing for;
#   • and the one thing you can DO about it: travel.
#
# BASH AND TRANSMUTE USED TO BE ON THAT LAST ROW and are not any more — see
# `_build_actions` for why. They are armed from the chips under the offering now
# and aimed at a card, the way Dash is. The `bashed` / `transmuted` signals and
# the `bash()` / `transmute()` verbs stay: the overworld routes both through the
# same public entry points either way.
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
var _notes: Dictionary = {}          # {route, pace, shields, beatable} from the overworld
var _layer: CanvasLayer = null
var _answered: bool = false
var _ladder_holder: Control = null
var _ladder_room: ScrollContainer = null
var _zoom: float = 1.0
var _auto_zoomed: bool = false
# The rung's card, when one is open. One at a time — it is a detour from the
# decision, not a second decision.
var _node_card: PanelContainer = null
var _node_card_body: VBoxContainer = null

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

	# There WAS an event row here — "✦ An event fires here once the game is
	# played." It was the last survivor of the era when placement was hashed onto
	# particular nodes and routing towards an event was a decision. Every game
	# pays one now, so the line was on all but two kinds of card and said nothing
	# on any of them: a fact that is always true is not information.
	#
	# The shop, if this game is one of the run's hubs (§14), is the row that
	# earned its place — and it is now also the row that says an event is NOT
	# coming, because a hub's event is the shop (§12). One step further than a
	# badge, too: a shop the player has ALREADY been to lists what is still on its
	# shelf, because the decision "is it worth walking back to that hub" is
	# unanswerable without knowing what is left there and what it costs. This is
	# the only place in the run that question gets asked.
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

	# The trade, said once where the routing decision is made: a shop stands here
	# INSTEAD of an event (§14.4), which is the only way a hub costs differently
	# from every other card on the board.
	var instead := Label.new()
	instead.text = "      No event fires here — the shop is what happens instead."
	instead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instead.add_theme_font_size_override("font_size", 11)
	instead.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	col.add_child(instead)

	for line in ShopSystem.stock_lines(game.id):
		var row := Label.new()
		row.text = "      • %s" % line
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 11)
		row.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		col.add_child(row)
	return col


# --- what this game OPENS ONTO ---------------------------------------------

# How many games this node connects to, and how many of those carry something
# worth routing for. Static and public because the same three numbers belong on
# the start picker's cards, and there they are wanted before any modal exists.
#
# Counted off RunGraph rather than off `games_influenced`: influence is directed
# and the sheet's raw list includes games the filter and the main-component prune
# have already taken out of this run, so the raw length is not the number of
# places you can actually go next. Destroyed games are dropped for the same
# reason — a bashed neighbour is a door that no longer opens.
#
# Returns {"total": int, "events": int, "shops": int}.
static func connection_counts(game_id: StringName) -> Dictionary:
	var out := {"total": 0, "events": 0, "shops": 0}
	if game_id == &"":
		return out
	for n in RunGraph.neighbors(game_id):
		if GameLoop2.is_bashed(n):
			continue
		out["total"] += 1
		# Not "which event is there" — nothing knows that until the run arrives —
		# but "would one fire". Every game pays an event the first time it is
		# played, so this counts the neighbours the run has not already taken one
		# from, which is the number that actually shapes where to go next.
		#
		# A hub is not one of them. A shop is what happens at a hub, INSTEAD of an
		# event (§12), so counting it under both headings would promise the same
		# neighbour twice and overstate the events on offer.
		if ShopSystem.is_hub(n):
			out["shops"] += 1
		elif not GameState.event_nodes_fired.has(n):
			out["events"] += 1
	return out

# The counts as one line, or "" when the game is a dead end with nothing to say.
static func connection_text(counts: Dictionary) -> String:
	var total: int = int(counts.get("total", 0))
	if total <= 0:
		return "⛓  No connections — a dead end"
	var parts: Array = ["⛓  %d connection%s" % [total, "" if total == 1 else "s"]]
	var events: int = int(counts.get("events", 0))
	var shops: int = int(counts.get("shops", 0))
	if events > 0:
		parts.append("✦ %d event%s" % [events, "" if events == 1 else "s"])
	if shops > 0:
		parts.append("🛒 %d shop%s" % [shops, "" if shops == 1 else "s"])
	return "  ·  ".join(parts)

static func connection_tip(game: GameData, counts: Dictionary) -> String:
	var name_text: String = game.display_name if game != null else "this game"
	return ("%d games connect to %s — the pool the next offering is drawn from. "
		+ "%d of them still owe an event; %d are shop hubs, where the shop is "
		+ "what happens instead of one.") % [
		int(counts.get("total", 0)), name_text,
		int(counts.get("events", 0)), int(counts.get("shops", 0))]

# The room the popup has: the screen minus the run's pinned header bar, which is
# drawn OVER this modal and would otherwise take the popup's title row with it
# (ModalScaffold.reserved_top).
func _panel_size() -> Vector2:
	var free: Vector2 = ModalScaffold.free_rect(self).size
	return Vector2(
		minf(PANEL_SIZE.x, maxf(560.0, free.x - VIEW_MARGIN.x)),
		minf(PANEL_SIZE.y, maxf(420.0, free.y - VIEW_MARGIN.y)))

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

	# ABOVE the cover, not under it: "how many doors does this open" is a routing
	# fact, and routing is what the popup is opened to decide. The cover is the
	# thing you have already seen, so it does not get to sit in front of this.
	var counts: Dictionary = connection_counts(StringName(_choice.get("slot", &"")))
	var conn := Label.new()
	conn.text = connection_text(counts)
	conn.tooltip_text = connection_tip(game, counts)
	conn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	conn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conn.add_theme_font_size_override("font_size", 12)
	conn.add_theme_color_override("font_color",
		UITheme.TEXT_DIM if int(counts.get("total", 0)) > 0 else UITheme.DANGER)
	col.add_child(conn)

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

	# Transmuted (§4): this SPOT is no longer playing its own game. Everything
	# else on the card already speaks for the REPLACEMENT — its cover, its type,
	# its shields, the enemy standing there — so the one fact the card cannot state
	# for itself is that it is a replacement at all, and what it was pasted over.
	# Which is exactly what the routing decision turns on: the rung keeps its
	# place on the graph, so the road out is the OLD game's road, not this one's.
	var was: GameData = GameLoop2.original_at(StringName(_choice.get("slot", &"")))
	if was != null:
		col.add_child(_fact_line("⚗ Transmuted — was %s" % was.display_name,
			UITheme.ACCENT,
			("This spot held %s; a transmute pasted %s over it for the rest of the run. "
			+ "Its connections are unchanged — the route below is still %s's.") % [
				was.display_name, game.display_name, was.display_name]))

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

	# The SHIELDS this game hands you (§3) — the reason a Traditional roguelike is
	# worth routing through even when it isn't the short way. A card that only MOVES
	# the run grants none of them: nothing is being committed to yet.
	var shields: int = 0 if bool(_notes.get("move_only", false)) else int(_notes.get("shields", 0))
	if shields > 0:
		col.add_child(_fact_line("%s  %s" % ["◆".repeat(shields),
			GameState.temp_shields_text(shields)],
			Overworld2.SHIELD_BLUE,
			("Selecting %s grants %s. Each one stops a single hit outright, however "
				+ "big, and whatever is left expires when you report the game.") % [
				game.display_name, GameState.temp_shields_text(shields)]))

	# What taking this does to the board's PACE (§7.4). Also a fact about playing a
	# game, so it goes with the shields on a move-only card.
	var pace: Dictionary = {} if bool(_notes.get("move_only", false)) else _notes.get("pace", {})
	if String(pace.get("text", "")) != "":
		col.add_child(_fact_line(String(pace["text"]), pace.get("color", UITheme.TEXT_DIM),
			String(pace.get("tip", ""))))

	# A game the run has already played pays a Dash for going back and beating it.
	if bool(_choice.get("repeat", false)):
		col.add_child(_fact_line("⚡ Gain +%d Dash" % Overworld2.REPEAT_BEAT_DASH,
			Overworld2.DASH_BLUE,
			"You have played %s already this run — go back and beat it for a Dash charge." % game.display_name))

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

	# Runic Dome (§7.1). This is the block the relic is BOUGHT against: the whole
	# of what an unopened card is worth is in here, so the Dome blanks the block
	# rather than redacting a line of it. The overworld decides — it owns the
	# rule and the wording — and hands the answer over in the notes, so the popup
	# and the hover line under the offering go dark together.
	if bool(_notes.get("enemy_hidden", false)):
		var hidden := Label.new()
		hidden.text = String(_notes.get("hidden_note",
			"The Runic Dome hides what is waiting there."))
		hidden.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hidden.add_theme_font_size_override("font_size", 13)
		hidden.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		box.add_child(hidden)
		# The escort survives the blackout: the Dome was bought to hide WHAT is
		# waiting, and the number of bodies is not part of that.
		_add_escort_line(box)
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

	# What ELSE this card puts on the board (§7.5). Under the goal rather than
	# beside the name, because it is not another fact about this enemy — it is a
	# second body, and the count is the part the player is being warned about.
	_add_escort_line(box)

	# Your own record against what's on the board right now: the enemies you have
	# ALREADY beaten at this game, this one and every follower. Built by the
	# overworld (Overworld2._beatable_row) and handed over, so the offering and
	# this popup can't disagree about what counts as proven.
	var proven = _notes.get("beatable")
	if proven is Control:
		box.add_child(proven)
	return box

# The escort line, when the overworld handed one over (§7.5). It owns the wording
# — a WARNING while the game is an offer, the body's NAME once it is standing
# there — so the popup and the hover line under the offering cannot disagree
# about what is coming. Nothing is drawn when the note is empty (a boss round, a
# free game), which is what keeps a card that brings one body quiet about it.
func _add_escort_line(box: VBoxContainer) -> void:
	var text: String = String(_notes.get("escort", ""))
	if text == "":
		return
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.DANGER)
	box.add_child(l)

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
	# Kept to one line for the reason RunMapModal's hint is: the ladder above it
	# is fitted to whatever height is left over.
	legend.text = "▶ where you'd be  •  🏆 the Amulet  •  🛒 a shop  •  ⚔ beaten there"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 11)
	legend.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(legend)
	return col

# The route from THIS game, as RouteLadder reads it. `preview` because the top
# rung is where you would be standing, not where you are.
#
# The rungs OPEN. They used to be inert, on the reasoning that this popup is
# about one game and a click should not put a second card over the buttons that
# answer it — but the route is half of what the popup is for, and a rung is a
# clipped name in a 150px box. "Which of these is worth walking to" is exactly
# the question being asked here, and it cannot be answered off a name. So a rung
# opens the same card the map window opens, over the left column rather than over
# the answer, minus the two things a preview cannot do: there is no chart on this
# screen to fly, and no route to pin from a game you have not taken.
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
		"on_node": func(node_id: StringName, depth: int): open_node_card(node_id, depth),
	}


# --- the rung's card -------------------------------------------------------

# The card width, and the gap it keeps from the panel's edge.
const NODE_CARD_W := 300.0

# Open the card on one rung of the route. Public so a test can ask for exactly
# what a click asks for.
func open_node_card(id: StringName, depth: int = 0) -> Control:
	close_node_card()
	if id == &"":
		return null
	var amulet: StringName = GameState.amulet_game_id

	var facts: Array = [["On this route", "step %d of %d" % [depth, route_steps()]]]
	var left: int = RunGraph.route_length_via(id, &"", amulet)
	if left >= 0:
		facts.append(["From here to the Amulet", "%d step%s" % [left, "" if left == 1 else "s"]])

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.075, 0.062, 0.05, 0.98), 8, 12, 2, UITheme.GOLD))
	card.custom_minimum_size = Vector2(NODE_CARD_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_node_card = card
	add_child(card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)
	# A ScrollContainer hands its child the full width and draws the scrollbar
	# over it, so right-aligned values need the bar's lane kept clear of them.
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_right", 14)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	var box := RouteLadder.node_card_body({
		"id": id,
		"name": RouteLadder.node_name(id),
		"role": _node_role_text(id, depth),
		"facts": facts,
		"actions": [],
		"on_close": Callable(self, "close_node_card"),
	})
	box.custom_minimum_size = Vector2(NODE_CARD_W - 54.0, 0)
	inset.add_child(box)
	_node_card_body = box

	_place_node_card()
	# And again once Godot has laid the contents out: until it has, the card's
	# ScrollContainer reports almost no height of its own and the card opens as a
	# sliver with its facts scrolled out of sight.
	_place_node_card.call_deferred()
	return card


func close_node_card() -> void:
	if _node_card != null and is_instance_valid(_node_card):
		_node_card.queue_free()
	_node_card = null
	_node_card_body = null


# Which rung this is, in words. The popup's own route is a PREVIEW — every rung
# on it is a place you would be, not a place you are.
func _node_role_text(id: StringName, depth: int) -> String:
	if depth == 0:
		return "Where this card would put you."
	if id == GameState.amulet_game_id:
		return "The Amulet — the end of the run."
	if GameState.visited_games.has(id):
		return "You have already been here this run."
	return "On the road to the Amulet, if you take this card."


# Park the card over the LEFT column — the game and its enemy, which the player
# has already read by the time they are picking over the route on the right. The
# ladder stays uncovered, so the next rung is one click away rather than one
# close-and-click.
func _place_node_card() -> void:
	if _node_card == null or not is_instance_valid(_node_card):
		return
	var view: Vector2 = get_viewport_rect().size
	var panel: Vector2 = _panel_size()
	var want: float = 320.0
	if _node_card_body != null and is_instance_valid(_node_card_body):
		want = _node_card_body.get_combined_minimum_size().y + 34.0
	var h: float = clampf(want, 240.0, maxf(240.0, view.y - 40.0))
	_node_card.size = Vector2(NODE_CARD_W, h)
	_node_card.position = Vector2(
		clampf((view.x - panel.x) * 0.5 + 18.0, 8.0, maxf(8.0, view.x - NODE_CARD_W - 8.0)),
		clampf((view.y - h) * 0.5, 8.0, maxf(8.0, view.y - h - 8.0)))

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

# What this card can become: the way in, and nothing else.
#
# BASH AND TRANSMUTE ARE NOT ON THIS ROW ANY MORE. They were, and they were in the
# wrong place twice over. This card is what opens when you click a game, and what
# it is FOR is the decision "do I go here" — the route, the enemy, the shields.
# Two destructive verbs parked beside the Travel button made that decision a
# three-way, and they made it a three-way on a screen the player opens dozens of
# times a run without ever meaning to spend a charge.
#
# The other half is that the verbs could only ever be found this way. The chips
# under the offering counted them and then pointed HERE — "spent from a game's
# card: click one and press Bash" — so a charge was a number with a paragraph
# where its button should be. They are real buttons on that row now, and pressing
# one arms it and lights the offering to be clicked, the same bargain Dash has
# always made (Overworld2.bash / transmute / _armed_verb).
#
# `bashed` and `transmuted` stay on this class, and so do `bash()` and
# `transmute()`: the overworld still routes both verbs through the same public
# entry points, and the tests answer them here.
func _build_actions(game: GameData, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

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
		# Escape backs out one layer at a time: the rung's card first, the popup
		# only once there is nothing open over it.
		if _node_card != null and is_instance_valid(_node_card):
			close_node_card()
			return
		_close()
