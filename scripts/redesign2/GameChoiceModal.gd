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
#   • the OPTIMAL PATH, drawn as the real route map (RouteLadder) — the same
#     arrowed graph the 🗺 map window shows, for the road as it would stand if
#     you took this game. It takes the whole right-hand side, top to buttons,
#     with the popup's ✕ over its corner;
#   • the GAME — its cover, type and year, the node's kind, its connections and
#     the shops and champions among them, the Temporary Shields it grants, the
#     pace it puts the board on, and your record there (which opens the list of
#     every enemy you have beaten at it);
#   • the ENEMIES APPROACHING — as the checklist will list them once you commit:
#     portrait, goal and name, ❤/⚔, and a "?" row per body rolled on arrival;
#   • the SOURCE behind the connection you'd be walking (_build_source_block) —
#     who inspired whom, and the evidence the sheet records for it;
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
#
# Smaller again now that the SOURCE sits beside it (_build_game_column): the two
# share the row, and the width the source needs to say "X inspired Y" without
# wrapping every second word comes out of the half that is already the least
# informative.
const COVER := Vector2(112, 150)
# The column beside the cover. Not a hard width — the source block expands into
# whatever the row has — but the floor the game column is sized to hold, so the
# pair never has to wrap at the modal's narrowest.
const SOURCE_MIN_W := 158.0
# The map's own column, and its floor: room for a short route's boxes and their
# names before the map has to scroll.
const LADDER_MIN_W := 360.0
const LADDER_MIN_H := 300.0

# The teleport's own colour — the purple `Overworld2.loot_teleport` writes its log
# line in, so the banner on the arrival card and the line in the log are visibly
# the same event.
const TELEPORT := Color(0.61, 0.35, 0.71)

var _index: int = -1
var _choice: Dictionary = {}
var _notes: Dictionary = {}          # {route, pace, shields, kind, …} from the overworld
var _layer: CanvasLayer = null
var _answered: bool = false
var _ladder_holder: Control = null
var _ladder_room: ScrollContainer = null
var _zoom: float = 1.0
# The rung's card, when one is open. One at a time — it is a detour from the
# decision, not a second decision.
var _node_card: PanelContainer = null
var _node_card_body: VBoxContainer = null
# The NODE this card stands on when it is a Shop node, read by the kind line.
var _shop_node: StringName = &""

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
	# 124 by default: over the event (123) and the boss notice, so a card opened
	# from the offering is never buried. An ARRIVAL asks for a lower one — it is the
	# last word of a move whose first words are the haul and the event from the game
	# you were teleported out of, and those should be read first (see
	# Overworld2._open_arrival_card).
	modal._layer.layer = int(notes.get("layer", UITheme.Layer.CHOICE))
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
	root.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	margin.add_child(root)


	# HOW YOU GOT HERE, on an arrival only.
	#
	# The card answers "what is this game and what is waiting on it"; the one thing
	# it cannot know is that you did not CHOOSE it. Without this the screen is
	# indistinguishable from the card the offering opens — same cover, same enemy,
	# same route — and a player who is shown that after reading a scroll has no way
	# to tell they have been moved at all.
	#
	# So it is a BANNER, not a line: a bordered strip across the top of the card
	# saying it twice over — the headline that you were teleported and that this is
	# now the game you are playing, then the sentence with where you landed and how
	# far out it put you. It was one small gold line, which sat between a title and
	# a cover and read as flavour.
	if bool(_notes.get("arrival", false)):
		root.add_child(_build_arrival_banner(String(_notes.get("arrival_note", ""))))

	# A SHOP NODE (§14, §19.1) is said in the game's facts as its kind — "$ Shop",
	# like every other kind — with what the banner that used to sit here said (a
	# shop stands here INSTEAD of an event, §14.4, and what is left on a visited
	# shelf) in that line's hover. The banner cost the map two rows on every shop.
	#
	# Asked of the NODE (the slot), not the game on it (§19.2).
	var shop_node: StringName = StringName(_choice.get("slot", &""))
	if shop_node == &"" and game != null:
		shop_node = game.id
	_shop_node = shop_node

	# The body, in two columns: the GAME on the left (what you'd be playing and
	# what it costs), the ROUTE on the right (where it leaves you). They are the
	# two halves of the decision and they belong side by side.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# The LEFT side is the title over the game column; the map on the right runs
	# the popup's full height, with the ✕ in its corner.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_build_header(game, accent))
	var game_col: Control = _build_game_column(game, accent)
	left.add_child(game_col)
	left.size_flags_stretch_ratio = game_col.size_flags_stretch_ratio
	left.custom_minimum_size.x = game_col.custom_minimum_size.x
	body.add_child(left)
	body.add_child(_build_route_column())

	root.add_child(_build_actions(game, accent))
	# The map is sized to its box, which has no size until Godot has laid the
	# panel out (_settle).
	_settle.call_deferred()

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
# Returns {"total": int, "events": int, "shops": int, "champions": int}.
static func connection_counts(game_id: StringName) -> Dictionary:
	var out := {"total": 0, "events": 0, "shops": 0, "champions": 0}
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
		# A Shop node is not one of them. A shop is what happens there, INSTEAD of
		# an event (§14.4), so counting it under both headings would promise the
		# same neighbour twice and overstate the events on offer.
		if GameState.node_kind(n) == RunGraph.NodeKind.CHAMPION:
			out["champions"] += 1
		if ShopSystem.is_shop(n):
			out["shops"] += 1
		elif not GameState.event_nodes_fired.has(n):
			out["events"] += 1
	return out

# The counts as one line, or "" when the game is a dead end with nothing to say.
#
# TWO LINES, because one was misread: "2 connections · 1 event · 🛒 1 shop" was
# taken for THIS node's own shop. Now the count stands alone, and under it, in
# smaller print, the neighbours worth routing for — "$ 1 nearby shop · !! 1 nearby
# champion", in the marks the map's markers wear — or nothing when there are none.
static func connection_text(counts: Dictionary) -> String:
	var total: int = int(counts.get("total", 0))
	if total <= 0:
		return "⛓  No connections — a dead end"
	return "⛓  %d connection%s" % [total, "" if total == 1 else "s"]

static func nearby_text(counts: Dictionary) -> String:
	var parts: Array = []
	var shops: int = int(counts.get("shops", 0))
	var champs: int = int(counts.get("champions", 0))
	if shops > 0:
		parts.append("%s %d nearby shop%s" % [RunGraph.kind_mark(RunGraph.NodeKind.SHOP),
			shops, "" if shops == 1 else "s"])
	if champs > 0:
		parts.append("%s %d nearby champion%s" % [RunGraph.kind_mark(RunGraph.NodeKind.CHAMPION),
			champs, "" if champs == 1 else "s"])
	return "  ·  ".join(PackedStringArray(parts))

static func connection_tip(game: GameData, counts: Dictionary) -> String:
	var name_text: String = game.display_name if game != null else "this game"
	var total: int = int(counts.get("total", 0))
	var events: int = int(counts.get("events", 0))
	var shops: int = int(counts.get("shops", 0))
	return ("%s %s to %s — the pool the next offering is drawn from. "
		+ "%d of them still %s an event; %d %s, where the shop is "
		+ "what happens instead of one.") % [
		Plural.count(total, "game"), "connects" if total == 1 else "connect", name_text,
		events, "owes" if events == 1 else "owe",
		shops, "is a Shop node" if shops == 1 else "are Shop nodes"]

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
	if _is_rift():
		return UITheme.RIFT
	return UITheme.type_color(int(game.type)) if game != null else UITheme.ACCENT

# Whether this card's NODE is a rift game (docs/rifts-design.md). Read off the
# slot, as the offering does, so a rift Transmute has refilled stays a rift.
func _is_rift() -> bool:
	if _choice.has("rift_key"):
		return true
	var slot := StringName(_choice.get("slot", &""))
	return slot != &"" and RunGraph.is_rift_game(slot)

# A RIFT KEY card's destination (docs/rifts-design.md §8), or &"" on any other card.
func _key_dest() -> StringName:
	return StringName(_choice.get("rift_key", &""))

# --- the arrival banner ----------------------------------------------------

# "You have been TELEPORTED here", and under it the sentence the teleport itself
# wrote (where you landed, how far that is from the Amulet, and whether a game was
# walked out of on the way). See the note at its call site for why it is a framed
# strip rather than a line of text.
#
# `→` rather than a new arrow glyph: the UI's symbols are shipped as subsetted
# fonts (tools/build_glyph_font.py) and this one is already in them.
func _build_arrival_banner(detail: String) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(TELEPORT.lerp(UITheme.BG, 0.78), 10, 8, 2, TELEPORT))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	wrap.add_child(col)
	var head := Label.new()
	head.text = "→  You have been teleported here — this is the game you are playing now."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	head.add_theme_color_override("font_color", TELEPORT.lerp(Color.WHITE, 0.5))
	col.add_child(head)
	# The detail is the teleport's own sentence and there is not always one (a dev
	# jump, or a caller that had nothing to add), so the strip stands without it
	# rather than leaving an empty row.
	if detail != "":
		var line := Label.new()
		line.text = detail
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		line.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		col.add_child(line)
	return wrap

# --- header ----------------------------------------------------------------

func _build_header(game: GameData, accent: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_WIDE)

	var title := Label.new()
	title.text = ("🏆 " if bool(_choice.get("amulet", false))
		else ("☠ " if bool(_choice.get("boss", false)) else "")) + game.display_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	title.add_theme_color_override("font_color", accent)
	row.add_child(title)
	return row

# The popup's ✕. Not in the title row any more: the title sits over the left
# column only, and the ✕ rides the map's corner (_build_route_column).
func _close_button() -> Button:
	var close := HoverButton.new()
	close.name = "Close"
	close.text = "✕"
	close.tooltip_text = ("Onto the board — you are already here." if bool(_notes.get("arrival", false))
		else "Back to the offering — nothing is chosen.")
	close.custom_minimum_size = Vector2(38, 38)
	close.pressed.connect(_close)
	return close

# --- the game column -------------------------------------------------------

func _build_game_column(game: GameData, accent: Color) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COVER.x + SOURCE_MIN_W + 26.0, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Shares the width with the route rather than being pinned to the cover: a
	# ladder needs about a third of the panel and the goal text is the thing that
	# suffers when it doesn't get the rest.
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.5
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.custom_minimum_size = Vector2(COVER.x + SOURCE_MIN_W + 12.0, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	# THE COVER WITH ITS FACTS BESIDE IT. The cover sat alone in the middle of the
	# column with the connection count over it and a centred stack of one-line facts
	# under it — year, shields, pace, record — each a different width, so the
	# column read as a ragged pile rather than as a card. Now the facts are one
	# left-aligned list to the right of the art, the ★ Rate button at its foot, and
	# the source (the evidence for the edge you'd walk) a band of its own beneath.
	# The cover is the identifier, not the exhibit: it is what you clicked.
	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var meta: Array = []
	if game.year > 0:
		meta.append(str(game.year))
	meta.append(RunGraph.type_label(game.type))
	var chip := Label.new()
	chip.text = "  •  ".join(meta).to_upper()
	chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
	facts.add_child(chip)

	# THE NODE'S KIND (§19.8), every kind, in the mark and colour the map's marker
	# on the path wears — so "$ Shop" here and "$" on the road are one fact. On a
	# Shop node the hover says what the banner over the popup used to: a shop
	# stands here INSTEAD of an event (§14.4), and what is left on a visited shelf.
	var kind: int = int(_notes.get("kind", -1))
	if kind >= 0:
		var tip: String = RunGraph.kind_tip(kind)
		if _shop_node != &"" and ShopSystem.is_shop(_shop_node):
			var lines: Array = [ShopSystem.headline(_shop_node),
				"No event fires here — the shop is what happens instead."]
			for line in ShopSystem.stock_lines(_shop_node):
				lines.append("• %s" % line)
			tip = "\n".join(PackedStringArray(lines))
		facts.add_child(_fact_line("%s  %s" % [RunGraph.kind_mark(kind), RunGraph.kind_label(kind)],
			UITheme.kind_color(kind), tip))

	# "How many doors does this open" is a routing fact, and routing is what the
	# popup is opened to decide — so it heads the list.
	var counts: Dictionary = connection_counts(StringName(_choice.get("slot", &"")))
	# A RIFT KEY card's game is not on the map until the key is spent, so the graph
	# has no doors to count for it; it will have exactly one, its destination.
	if _key_dest() != &"":
		counts = {"total": 1, "events": 0, "shops": 0, "champions": 0}
	var conn := Label.new()
	conn.text = connection_text(counts)
	conn.tooltip_text = connection_tip(game, counts)
	conn.mouse_filter = Control.MOUSE_FILTER_STOP
	conn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	conn.add_theme_color_override("font_color",
		UITheme.TEXT_DIM if int(counts.get("total", 0)) > 0 else UITheme.DANGER)
	facts.add_child(conn)
	var near: String = nearby_text(counts)
	if near != "":
		var nearby := Label.new()
		nearby.name = "Nearby"
		nearby.text = "    " + near
		nearby.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nearby.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		nearby.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		facts.add_child(nearby)

	# Transmuted (§4): this SPOT is no longer playing its own game. Everything
	# else on the card already speaks for the REPLACEMENT — its cover, its type,
	# its shields, the enemy standing there — so the one fact the card cannot state
	# for itself is that it is a replacement at all, and what it was pasted over.
	# Which is exactly what the routing decision turns on: the rung keeps its
	# place on the graph, so the road out is the OLD game's road, not this one's.
	var was: GameData = GameLoop2.original_at(StringName(_choice.get("slot", &"")))
	if was != null:
		facts.add_child(_fact_line("⚗ Transmuted — was %s" % was.display_name,
			UITheme.ACCENT,
			("This spot held %s; a transmute pasted %s over it for the rest of the run. "
			+ "Its connections are unchanged — the route below is still %s's.") % [
				was.display_name, game.display_name, was.display_name]))

	# The SHIELDS this game hands you (§3) — the reason a Traditional roguelike is
	# worth routing through even when it isn't the short way. A card that only MOVES
	# the run grants none of them: nothing is being committed to yet.
	var shields: int = 0 if bool(_notes.get("move_only", false)) else int(_notes.get("shields", 0))
	if shields > 0:
		facts.add_child(_icon_fact(UITheme.SHIELD_ART, "Gain +%s" % GameState.temp_shields_text(shields),
			Overworld2.SHIELD_BLUE,
			("Selecting %s grants %s. Each one stops a single hit outright, however "
				+ "big, and whatever is left expires when you report the game.") % [
				game.display_name, GameState.temp_shields_text(shields)]))

	# What taking this does to the board's PACE (§7.4). Also a fact about playing a
	# game, so it goes with the shields on a move-only card.
	var pace: Dictionary = {} if bool(_notes.get("move_only", false)) else _notes.get("pace", {})
	if String(pace.get("text", "")) != "":
		facts.add_child(_fact_line(String(pace["text"]), pace.get("color", UITheme.TEXT_DIM),
			String(pace.get("tip", ""))))

	# THE RIFT'S DEAL (docs/rifts-design.md §6), said where the decision is made:
	# the risk and the payout in one line.
	if _key_dest() != &"":
		var dest: GameData = Data.get_game(_key_dest())
		facts.add_child(_fact_line("🗝 Spends a Rift Key — one way to %s"
			% (dest.display_name if dest != null else String(_key_dest())), UITheme.RIFT,
			"Taking this opens a rift: the key is spent, and the rift leads on to %s and never back to where you are now."
			% (dest.display_name if dest != null else String(_key_dest()))))
	if _is_rift():
		facts.add_child(_fact_line("🌀 Rift: bodies hit ×%d, pay ×%d loot and chest"
			% [GameLoop2.RIFT_MULT, GameLoop2.RIFT_MULT], UITheme.RIFT,
			"The bodies that walk on here deal double damage for as long as they stand, wherever they follow you — and drop double loot and chest points when they fall. Beating this game doubles the win's own chest point too."))

	# A game the run has already played pays a Dash for going back and beating it.
	if bool(_choice.get("repeat", false)):
		facts.add_child(_fact_line("⚡ Gain +%d Dash" % Overworld2.REPEAT_BEAT_DASH,
			Overworld2.DASH_BLUE,
			"You have played %s already this run — go back and beat it for a Dash charge." % game.display_name))

	var record: Control = _record_line(game)
	if record != null:
		facts.add_child(record)

	# ★ RATE, on the game you are looking at. It used to be a button on the
	# offering for the game you had just LEFT, which put a score for one game
	# above a row of three others; here it scores the game whose cover is beside it.

	if game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = COVER
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		UITheme.attach_tier_badge(art, game.id)
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 8, 5, 1, accent))
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if _is_rift():
			# The offering's swirl, behind the cover and showing round it as a ring
			# (OfferingCards.RIFT_RING), so the card opened is the card clicked.
			var holder := Control.new()
			holder.custom_minimum_size = COVER
			holder.add_child(UITheme.rift_backdrop())
			art.set_anchors_preset(Control.PRESET_FULL_RECT)
			art.offset_left = OfferingCards.RIFT_RING
			art.offset_top = OfferingCards.RIFT_RING
			art.offset_right = -OfferingCards.RIFT_RING
			art.offset_bottom = -OfferingCards.RIFT_RING
			holder.add_child(art)
			frame.add_child(holder)
		else:
			frame.add_child(art)
		var cover_row := HBoxContainer.new()
		cover_row.add_theme_constant_override("separation", UITheme.GAP_WIDE)
		cover_row.add_child(frame)
		cover_row.add_child(facts)
		col.add_child(cover_row)
	else:
		col.add_child(facts)

	# The evidence for the connection you would be walking, under the pair.
	var source_block: Control = _build_source_block()
	if source_block != null:
		col.add_child(HSeparator.new())
		col.add_child(source_block)
		if source_block.find_child("Proof", true, false) != null:
			scroll.size_flags_stretch_ratio = PROOF_COLUMN_RATIO

	col.add_child(HSeparator.new())
	col.add_child(_build_enemy_block(game))
	return scroll

# --- the connection you would be walking, and what backs it ----------------

# The whole map is a claim — "this game influenced that one" — and the evidence
# for every edge of it has been in the sheet all along (GameData.influence_sources).
# Until now the only place it could be read was the Atlas, by opening the star
# chart, finding the right line and clicking it: three deliberate steps away from
# the one moment the claim is actually interesting, which is when the player is
# looking at a game and deciding whether to walk to it.
#
# So the card carries it. Not the whole graph's worth — the ONE edge this choice
# would travel, from where the run stands to the game on this card — because that
# is the connection the player is standing on and the only one the decision is
# about. `describe_influence` answers in the direction the sheet authored, so the
# line says which game inspired which rather than pretending influence is mutual.
#
# Null when there is no edge to describe: the first pick of a run has nowhere to
# have come FROM, and a teleport can land the run somewhere its card is not a
# neighbour of. A section reading "no connection" on those would be a fact about
# the UI rather than about the game.
#
# THE MAP'S GAMES, not the card's: a transmute pastes one game over another's
# SPOT and leaves the graph alone (`_build_game_column` says so a few rows up), so
# the connection being walked is still the original pair's and naming the
# replacement here would credit it with somebody else's influence.
func _build_source_block() -> Control:
	var here: GameData = Data.get_game(GameState.current_game_id)
	var there: GameData = Data.get_game(StringName(_choice.get("slot", &"")))
	if here == null or there == null or here.id == there.id:
		return null
	var found: Dictionary = GameData.describe_influence(here, there)
	if found.is_empty():
		# A RIFT LINE is not an influence and is never presented as one
		# (docs/rifts-design.md §1, §9): the slot where the proof would be says so.
		if RunGraph.is_rift_game(here.id) or RunGraph.is_rift_game(there.id) or _key_dest() != &"":
			return _build_rift_block(here, there)
		return null
	var influencer: GameData = found["from"]
	var influenced: GameData = found["to"]

	# SIZED FOR THE SLOT BESIDE THE COVER, which is a narrow one: the type sizes
	# here are a step down from the rest of the column because two game names and a
	# URL have to fit in ~160px next to a 150px-tall picture.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	box.custom_minimum_size = Vector2(SOURCE_MIN_W, 0)

	var head := Label.new()
	head.text = "🔗  SOURCE"
	head.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	head.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(head)

	var claim := Label.new()
	claim.text = "%s inspired %s" % [influencer.display_name, influenced.display_name]
	claim.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	claim.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	claim.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(claim)

	# The sheet flags roughly 110 links as a sequel or the same studio rather than
	# one game merely inspiring another. That is a stronger claim, so it is said —
	# in the same words the Atlas's connection card says it in.
	if String(found.get("relation", "")).strip_edges() != "":
		var chip := Label.new()
		chip.text = "SEQUEL / SAME DEVELOPERS"
		chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chip.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
		chip.add_theme_color_override("font_color", UITheme.GOLD)
		box.add_child(chip)

	# THE PROOF ITSELF, when one was captured: the developer's own sentence on the
	# page the link opens, highlighted (tools/capture_proof.js). It goes above the
	# link because it is the evidence; the link under it is the citation.
	var proof: Control = _proof_thumb(influencer.id, influenced.id)
	if proof != null:
		box.add_child(proof)

	var source: String = String(found.get("source", "")).strip_edges()
	if source == "":
		box.add_child(_source_note("No source recorded for this connection yet."))
	elif GameData.is_openable_source(source):
		# The URL under the button, as the Atlas does it: the button is the verb and
		# the address is the evidence, and a player who wants to know WHERE a claim
		# comes from should not have to open a browser to find out.
		var open_btn := HoverButton.new()
		open_btn.text = "🔗  Open source"
		open_btn.tooltip_text = source
		open_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		open_btn.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		open_btn.pressed.connect(func(): OS.shell_open(source))
		box.add_child(open_btn)
		var url := Label.new()
		url.text = short_source(source)
		url.tooltip_text = source
		url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		url.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
		url.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		box.add_child(url)
	elif proof == null:
		# Notes like "check folder" or "game credits" point at evidence kept
		# somewhere else — shown as written rather than dressed up as a link.
		# Once that evidence IS here (the owner's own screenshot, from the very
		# folder "check folder" means), the note is a pointer at the picture
		# above it, and printing it would read as an instruction to the player.
		box.add_child(_source_note(source))
	return box

# A URL short enough to read at a glance: the scheme dropped and the tail elided.
#
# The Atlas prints these in full, on a card that exists to hold one connection. On
# THIS card the column is 200-odd pixels wide and the decision it is serving is
# about the game, so a deep-linked forum permalink wrapped to four lines and
# pushed the enemy off the bottom to say something nobody reads character by
# character. What the line is for is "who says so" — the host and the first step
# of the path answers that — and the whole address is one hover (and one click)
# away, which is what the button is.
#
# Static and public so a test can check the elision without walking Labels.
const SOURCE_CHARS := 34

static func short_source(url: String) -> String:
	var short: String = url.strip_edges()
	for scheme in ["https://", "http://"]:
		if short.to_lower().begins_with(scheme):
			short = short.substr(scheme.length())
			break
	if short.begins_with("www."):
		short = short.substr(4)
	if short.length() > SOURCE_CHARS:
		short = short.substr(0, SOURCE_CHARS - 1) + "…"
	return short

# --- the proof screenshot ---------------------------------------------------
#
# A proof is named by the games' ids in the direction the sheet authored it,
# influencer first, joined by three hyphens: `slay_the_spire---tic_tactic.png`.
# One file can prove SEVERAL connections into the same game — a developer naming
# five influences in one clip — and then its influencers are joined by one
# hyphen each: `balatro-inscryption---black_jacket.ogv` is the proof of both
# Balatro → Black Jacket and Inscryption → Black Jacket. An id is only ever
# lower-case letters, digits and underscores, so a hyphen can never be part of
# one and a name splits one way only; three of them make the join easy to see,
# and the owner types these by hand. They are captured — `node
# tools/capture_proof.js` opens each Source link, finds the sentence where the
# developer names the older game, highlights it and crops around it — or they are
# the owner's own screenshots. A connection with neither has no file, and the
# block shows the link alone as before.
#
# Looked up by convention rather than stored on GameData, the way covers and
# portraits are: an image is added or re-captured without touching the sheet.
const PROOF_DIR := "res://images2.0/proof/"
# PNG, the owner's call: screenshots of text, kept lossless.
const PROOF_EXT := ".png"
const PROOF_JOIN := "---"
# Between the influencers of one file that proves several connections.
const PROOF_AND := "-"
# The thumbnail's tallest. A screenshot is scaled to the column's WIDTH and no
# further (never up: blowing a line of text past its own size only blurs it), so
# text stays readable; a tall one shows its top this far and is read in full by
# clicking.
const PROOF_THUMB_H := 130.0
# How much more of the popup's width the left column takes when it carries a
# proof. Screenshots run 550 (a tweet) to 1600 (a Discord window) wide, and at
# the 0.62 the column has without one, a tweet's text came out too small to read.
const PROOF_COLUMN_RATIO := 0.5

# The connections a proof's file name (without its extension) stands for, as
# [from, to] pairs: one for `a---c`, two for `a-b---c`. [] for a name that isn't
# a proof's. The pattern spells out PROOF_AND and PROOF_JOIN.
static var _proof_name: RegEx = null

static func proof_pairs(stem: String) -> Array:
	if _proof_name == null:
		_proof_name = RegEx.create_from_string("^([a-z0-9_]+(?:-[a-z0-9_]+)*)---([a-z0-9_]+)$")
	var m: RegExMatch = _proof_name.search(stem)
	if m == null:
		return []
	var to := StringName(m.get_string(2))
	var pairs: Array = []
	for from in m.get_string(1).split(PROOF_AND):
		pairs.append([StringName(from), to])
	return pairs

# Every proof in the folder by the connection it proves ("from---to" -> path),
# one map per kind. A file that proves several connections can't be found by
# building its name from one of them, so the folder is read once, on the first
# lookup. A proof added while the game runs shows from the next launch.
#
# DirAccess, with `.import` taken off, the way MenuFallingArt reads its folders:
# a shipped build holds only `x.png.import` for a screenshot, and a clip (never
# imported) as itself. NOT ResourceLoader.list_directory, which costs ~60 ms on
# this folder against ~4 here, and reads a `.uid` as the file it belongs to: a
# clip renamed or merged outside the editor leaves its old `.uid` behind
# (gitignored, so a pull never removes it), and the listing then names a clip
# that is gone, in place of the one that proves the connection now.
static var _proof_shots: Dictionary = {}
static var _proof_clips: Dictionary = {}
static var _proofs_read: bool = false

static func _proof_file(index: Dictionary, from_id: StringName, to_id: StringName) -> String:
	if not _proofs_read:
		_proofs_read = true
		for f in DirAccess.get_files_at(PROOF_DIR):
			f = f.trim_suffix(".import").trim_suffix(".remap")
			var into: Dictionary = _proof_clips if f.ends_with(PROOF_VIDEO_EXT) \
				else _proof_shots if f.ends_with(PROOF_EXT) else {}
			for pair in proof_pairs(f.get_basename()):
				into["%s%s%s" % [pair[0], PROOF_JOIN, pair[1]]] = PROOF_DIR + f
	return String(index.get("%s%s%s" % [from_id, PROOF_JOIN, to_id], ""))

# The screenshot's path, or "" when this connection has none.
static func proof_path(from_id: StringName, to_id: StringName) -> String:
	return _proof_file(_proof_shots, from_id, to_id)

static func proof_texture(from_id: StringName, to_id: StringName) -> Texture2D:
	var path: String = proof_path(from_id, to_id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

# A PROOF THAT IS A CLIP — a developer saying it on a stream or a podcast. The
# owner uploads the `.mp4` under the proof's own name, and
# `tools/convert_proof_videos.py` turns it into the two files the game uses —
# the clip as Ogg Theora (the one format Godot plays) and a poster frame for the
# thumbnail — then deletes the MP4. A clip wins over a screenshot of the same
# connection.
const PROOF_VIDEO_EXT := ".ogv"
const PROOF_POSTER_EXT := ".poster.jpg"

# The clip's path, or "" when this connection has none.
static func proof_video_path(from_id: StringName, to_id: StringName) -> String:
	return _proof_file(_proof_clips, from_id, to_id)

# The clip for this connection, or null when it has none.
static func proof_video(from_id: StringName, to_id: StringName) -> VideoStream:
	var path: String = proof_video_path(from_id, to_id)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as VideoStream

static func proof_poster(from_id: StringName, to_id: StringName) -> Texture2D:
	var clip: String = proof_video_path(from_id, to_id)
	if clip == "":
		return null
	var path: String = clip.trim_suffix(PROOF_VIDEO_EXT) + PROOF_POSTER_EXT
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _proof_thumb(from_id: StringName, to_id: StringName) -> Control:
	var video: VideoStream = proof_video(from_id, to_id)
	var tex: Texture2D = proof_poster(from_id, to_id) if video != null else proof_texture(from_id, to_id)
	if tex == null:
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	# The frame clips; the picture inside is sized from the frame's width each
	# time the column settles, which a TextureRect's own stretch modes can't do
	# (they fit BOTH ways, which is what shrank a tweet to 140px tall).
	var frame := Control.new()
	frame.name = "ProofFrame"
	frame.clip_contents = true
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.tooltip_text = "Click to play the clip" if video != null else "Click to read it full size"
	var art := TextureRect.new()
	art.name = "Proof"
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	if video != null:
		# A ▶ over the poster's middle, so the thumbnail reads as a clip at a glance
		# and not as a screenshot of a video.
		var play := Label.new()
		play.name = "PlayMark"
		play.text = "▶"
		play.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		play.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		play.set_anchors_preset(Control.PRESET_FULL_RECT)
		play.mouse_filter = Control.MOUSE_FILTER_IGNORE
		play.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
		play.add_theme_color_override("font_color", Color.WHITE)
		play.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		play.add_theme_constant_override("outline_size", 8)
		frame.add_child(play)
	var more := Label.new()
	more.text = "Click to read all of it"
	more.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	more.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	more.visible = false
	box.add_child(frame)
	box.add_child(more)
	var fit := func():
		var scale: float = minf(1.0, frame.size.x / float(tex.get_width())) if frame.size.x > 0.0 else 1.0
		var shown: Vector2 = tex.get_size() * scale
		art.position = Vector2.ZERO
		art.size = shown
		frame.custom_minimum_size.y = minf(shown.y, PROOF_THUMB_H)
		more.visible = video == null and shown.y > PROOF_THUMB_H + 0.5
	frame.resized.connect(fit)
	fit.call()
	frame.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			frame.accept_event()
			if video != null:
				open_proof_video(video, tex.get_size())
			else:
				open_proof(tex))
	return box

# The screenshot at its own size (or the window's, if it is bigger), over the
# popup. Any click or Escape puts it away; it is a closer look, not a step.
var _proof_view: Control = null

func open_proof(tex: Texture2D) -> Control:
	close_proof()
	var shade := ColorRect.new()
	shade.name = "ProofView"
	shade.color = Color(UITheme.BG_DEEP, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var room: Vector2 = get_viewport_rect().size - VIEW_MARGIN * 2.0
	var fit: float = minf(1.0, minf(room.x / tex.get_width(), room.y / tex.get_height()))
	var art := TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = tex.get_size() * fit
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(art)
	shade.add_child(centre)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			accept_event()
			close_proof())
	add_child(shade)
	_proof_view = shade
	return shade

# THE CLIP, PLAYING, over the popup — the same shade a screenshot opens in, at the
# poster's shape scaled to the window. A click on the clip pauses and resumes it
# (and starts it again once it has finished); a click outside it, the ✕, or Escape
# puts it away, and the sound stops with it.
func open_proof_video(video: VideoStream, shape: Vector2) -> Control:
	close_proof()
	var shade := ColorRect.new()
	shade.name = "ProofView"
	shade.color = Color(UITheme.BG_DEEP, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var room: Vector2 = get_viewport_rect().size - VIEW_MARGIN * 2.0
	if shape.x <= 0.0 or shape.y <= 0.0:
		shape = Vector2(16, 9)
	var fit: float = minf(room.x / shape.x, room.y / shape.y)
	var player := VideoStreamPlayer.new()
	player.name = "ProofVideo"
	player.stream = video
	player.expand = true
	player.custom_minimum_size = shape * fit
	player.mouse_filter = Control.MOUSE_FILTER_STOP
	player.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	player.tooltip_text = "Click to pause or play"
	player.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			player.accept_event()
			if not player.is_playing():
				player.paused = false
				player.play()
			else:
				player.paused = not player.paused)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(player)
	shade.add_child(centre)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Close (Esc)"
	close.position = Vector2(get_viewport_rect().size.x - VIEW_MARGIN.x - 40.0, VIEW_MARGIN.y * 0.5)
	close.pressed.connect(close_proof)
	shade.add_child(close)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			accept_event()
			close_proof())
	add_child(shade)
	_proof_view = shade
	player.play()
	return shade

func close_proof() -> void:
	if _proof_view != null and is_instance_valid(_proof_view):
		_proof_view.queue_free()
	_proof_view = null

# The proof slot on a step through a rift: what the line is, in the place the
# evidence for an influence would be, so a rift never reads as an unsourced claim.
func _build_rift_block(here: GameData, there: GameData) -> Control:
	var rift_game: GameData = there if RunGraph.is_rift_game(there.id) else here
	var box := VBoxContainer.new()
	box.name = "RiftBlock"
	box.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	box.custom_minimum_size = Vector2(SOURCE_MIN_W, 0)
	var head := Label.new()
	head.text = "🌀  RIFT"
	head.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	head.add_theme_color_override("font_color", UITheme.RIFT)
	box.add_child(head)
	var claim := Label.new()
	claim.text = "Rift: no known influence"
	claim.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	claim.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	claim.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(claim)
	if _key_dest() != &"":
		var dest: GameData = Data.get_game(_key_dest())
		box.add_child(_source_note(("A Rift Key can tear the wall between here and %s open. "
			+ "It is no influence, and no shortcut: the rift leads one way, on to %s, two "
			+ "hops from where you stand.") % [there.display_name,
			dest.display_name if dest != null else String(_key_dest())]))
		return box
	box.add_child(_source_note(("Two dimensions have merged here. %s has no known link to %s "
		+ "— it was pulled onto this map through a rift, and the rift leads no shorter "
		+ "than the roads already there.") % [rift_game.display_name,
		(here if rift_game == there else there).display_name]))
	return box

func _source_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	return l

# The enemy standing at this card: its portrait, its name, and the goal you would
# actually be playing for — clauses from your own statuses included (§13).
func _build_enemy_block(game: GameData) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	var enemy: GoalEnemyData = _choice.get("enemy")

	var head := Label.new()
	head.text = "☠  THE BOSS HERE" if bool(_choice.get("boss", false)) else "ENEMIES APPROACHING"
	head.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	head.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(head)
	head.visible = head.text != ""

	# A card opened to MOVE the run rather than to play a game (the stay-or-return
	# question, §10) has no enemy behind it — none is rolled until a game is
	# actually picked — so it says what it is instead of quoting a roll that hasn't
	# happened.
	if _notes.has("move_note"):
		head.text = "WHAT THIS DOES"
		head.visible = true
		var note := Label.new()
		note.text = String(_notes["move_note"])
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		note.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		box.add_child(note)
		return box

	if enemy == null:
		var free := Label.new()
		free.text = "Nothing — %s is a free game." % game.display_name
		free.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		free.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
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
		hidden.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		hidden.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		box.add_child(hidden)
		# The body count survives the blackout: the Dome was bought to hide WHAT is
		# waiting, and the number of bodies is not part of that.
		_add_bodies_line(box)
		return box

	# THE CHECKLIST'S OWN ROW (ReportChecklist.verify_row): the portrait chip and
	# "goal — enemy" on one bordered line, so the enemy reads here exactly as it
	# will on the list beside the board once you commit, with the board's ❤/⚔
	# badges at its end. The rest of what the old block spelled out — type and
	# difficulty — is the row's hover, and the abilities the portrait's hover card,
	# which is the board's own.
	var boss: bool = bool(_choice.get("boss", false))
	var entry: Dictionary = {"enemy": enemy, "statuses": {}}
	var hp: int = GameLoop2.effective_health(enemy)
	# A rift's bodies walk on hitting twice as hard (docs/rifts-design.md §6).
	var dmg: int = int(enemy.damage) * (GameLoop2.RIFT_MULT if _is_rift() else 1)
	var meta: String = "%s / %s / %d goal%s to beat / dmg %d" % [
		String(enemy.game_type).capitalize(), RunDifficulty.tier_name(int(enemy.difficulty)),
		hp, "" if hp == 1 else "s", dmg]
	box.add_child(_goal_row(_enemy_chip(enemy, boss),
		"%s — %s" % [GameLoop2.entry_goal(entry), enemy.display_name],
		UITheme.DANGER if boss else UITheme.TEXT,
		"%s\n%s" % [enemy.display_name, meta], _stat_pair(hp, dmg)))
	# The clauses hanging off the goal, as the checklist hangs them.
	for addon in GameLoop2.goal_addons_for(entry):
		box.add_child(UITheme.addon_row(addon))
	# One row per body still to be rolled (§19.4): you know the first, not the rest.
	# Its hover is the overworld's own sentence for it, so the two cannot disagree.
	var extra: int = int(_notes.get("extra_bodies", 0))
	for i in extra:
		box.add_child(_goal_row(_unknown_chip(), "Another enemy — rolled when you arrive",
			UITheme.DANGER.lerp(UITheme.TEXT, 0.25), String(_notes.get("bodies", ""))))
	return box

# What the node stands up, when the overworld handed a line over (§19.4). It owns the wording
# — a WARNING while the game is an offer, the body's NAME once it is standing
# there — so the popup and the hover line under the offering cannot disagree
# about what is coming. Nothing is drawn when the note is empty (a boss round, a
# free game), which is what keeps a card that brings one body quiet about it.
func _add_bodies_line(box: VBoxContainer) -> void:
	var text: String = String(_notes.get("bodies", ""))
	if text == "":
		return
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", UITheme.DANGER)
	box.add_child(l)

# YOUR RECORD HERE as ONE line: how often you have beaten the game and how many
# enemies, and — when there are any — a button that opens the list of them.
func _record_line(game: GameData) -> Control:
	var wins: int = GameStats.beaten_count(game.id)
	var enemies: int = GameStats.enemies_for(game.id).filter(func(r): return int(r["beaten"]) > 0).size()
	if wins <= 0 and enemies <= 0:
		return null
	var parts: Array = []
	if wins > 0:
		parts.append("Beaten %d time%s" % [wins, "" if wins == 1 else "s"])
	if enemies > 0:
		parts.append("%d enem%s" % [enemies, "y" if enemies == 1 else "ies"])
	var text: String = "⚔  " + "  ·  ".join(PackedStringArray(parts))
	if enemies <= 0:
		return _fact_line(text, UITheme.GOLD, "Your lifetime record in %s." % game.display_name)
	var btn := HoverButton.new()
	btn.name = "BeatenHere"
	btn.text = text + "  ›"
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	btn.add_theme_color_override("font_color", UITheme.GOLD)
	btn.add_theme_color_override("font_hover_color", UITheme.GOLD.lerp(Color.WHITE, 0.4))
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0) if st == "normal" else Color(UITheme.GOLD, 0.12)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 0
		sb.content_margin_right = 4
		btn.add_theme_stylebox_override(st, sb)
	btn.tooltip_text = "Your record in %s — click for every enemy you have beaten here." % game.display_name
	btn.pressed.connect(func(): open_beaten(game))
	return btn

# The record, over the popup in the shade a proof opens in (and put away the same
# way, close_proof): one row per enemy beaten here, most-beaten first, with your
# note — and "✓ Approaching" on the ones walking on with this game or already
# following you, which is the question the old row of "Beatable" pips answered.
func open_beaten(game: GameData) -> Control:
	close_proof()
	var approaching: Dictionary = {}
	var here: GoalEnemyData = _choice.get("enemy")
	if here != null and not bool(_notes.get("enemy_hidden", false)):
		approaching[String(here.id)] = true
	for entry in GameLoop2.stack:
		var f: GoalEnemyData = entry.get("enemy")
		if f != null:
			approaching[String(f.id)] = true
	var shade := ColorRect.new()
	shade.name = "BeatenView"
	shade.color = Color(UITheme.BG_DEEP, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			accept_event()
			close_proof())
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 8, 14, 1, UITheme.BORDER))
	panel.custom_minimum_size = Vector2(460, 0)
	# PASS, so a click on the list closes it too — "anywhere" means anywhere.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Enemies beaten at %s" % game.display_name
	title.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	title.add_theme_color_override("font_color", UITheme.TEXT)
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var rows: int = 0
	for r in GameStats.enemies_for(game.id):
		if int(r["beaten"]) <= 0:
			continue
		var e: GoalEnemyData = Data.get_goal_enemy_any(StringName(r["id"]))
		if e == null:
			continue
		rows += 1
		var text: String = "%s  ×%d" % [e.display_name, int(r["beaten"])]
		var note: String = String(r["note"]).strip_edges()
		if note != "":
			text += "\n🗒 %s" % note
		var is_near: bool = approaching.has(String(r["id"]))
		var row: Control = _goal_row(_enemy_chip(e, e.is_boss()),
			("✓ Approaching — " if is_near else "") + text,
			UITheme.SUCCESS if is_near else UITheme.TEXT,
			e.goal)
		list.add_child(row)
	scroll.custom_minimum_size.y = minf(rows * 46.0, 420.0)
	var hint := Label.new()
	hint.text = "Click anywhere to close"
	hint.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	hint.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(hint)
	add_child(shade)
	_proof_view = shade
	return shade

# The board's ❤ / ⚔ badges (BattlefieldView._stat_badge), as a pair for a row's end.
func _stat_pair(hp: int, dmg: int) -> Control:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	pair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for b in [["❤%d" % hp, BattlefieldView.HP_BADGE], ["⚔%d" % dmg, BattlefieldView.DMG_BADGE]]:
		var l := Label.new()
		l.text = b[0]
		l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		l.add_theme_color_override("font_color", (b[1] as Color).lerp(Color.WHITE, 0.3))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 2)
		var pill := UITheme.flat(Color(0.06, 0.05, 0.06, 0.9), 4, 0, 1, (b[1] as Color).lerp(UITheme.BG, 0.25))
		pill.content_margin_left = 4
		pill.content_margin_right = 4
		l.add_theme_stylebox_override("normal", pill)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(l)
	return pair

# One checklist-style row: a lead chip, a line of text and, optionally, something
# at its end, in the bordered strip ReportChecklist.verify_row draws — without the
# tick box, since nothing on this card is answered.
func _goal_row(chip: Control, text: String, color: Color, tip: String, trailing: Control = null) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.10, 0.10, 0.13, 0.6), 5, 4, 1, color.lerp(UITheme.BORDER, 0.35)))
	wrap.tooltip_text = tip
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UITheme.GAP)
	wrap.add_child(line)
	if chip != null:
		line.add_child(chip)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(l)
	if trailing != null:
		line.add_child(trailing)
	return wrap

# The portrait chip a goal row leads with — the checklist's own size and frame.
const GOAL_CHIP := 30

func _enemy_chip(enemy: GoalEnemyData, boss: bool) -> Control:
	var frame := HoverPanel.new()
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 4, 2, 1, (UITheme.DANGER if boss else UITheme.TEXT).lerp(UITheme.BORDER, 0.45)))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	if enemy.image != null:
		frame.add_child(UITheme.crisp_tex(enemy.image, GOAL_CHIP))
	else:
		var initial := Label.new()
		initial.text = String(enemy.display_name).substr(0, 1).to_upper()
		initial.custom_minimum_size = Vector2(GOAL_CHIP, GOAL_CHIP)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(initial)
	HoverCard.attach(frame, BattlefieldView.offered_enemy_hover(enemy,
		"It walks on with the game and follows you until its goal is cleared."))
	return frame

# The "?" a not-yet-rolled body leads with.
func _unknown_chip() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 4, 2, 1, UITheme.DANGER.lerp(UITheme.BORDER, 0.45)))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var q := Label.new()
	q.text = "?"
	q.custom_minimum_size = Vector2(GOAL_CHIP, GOAL_CHIP)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	q.add_theme_color_override("font_color", UITheme.DANGER)
	frame.add_child(q)
	return frame

# A fact with a picture in front of it (the shield, for now) rather than a glyph.
func _icon_fact(tex: Texture2D, text: String, color: Color, tip: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon := TextureRect.new()
	icon.texture = tex
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_crisp(icon, tex)
	row.add_child(icon)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row

func _fact_line(text: String, color: Color, tip: String = "") -> Control:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tip
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", color)
	return l

# The ★ Rate button for the game on this card: "Rate this game", or the score it
# already carries so a press reads as an edit. The modal is parented to THIS
# card so it opens over it rather than behind it on the page.
func _rate_button(game: GameData) -> Button:
	var btn := HoverButton.new()
	btn.text = rate_button_text(game)
	btn.tooltip_text = "Score %s out of 10 on your tier list — optional, and you can change it later." \
		% game.display_name
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	btn.add_theme_color_override("font_color", UITheme.GOLD)
	btn.pressed.connect(func(): open_rating(game, btn))
	return btn

static func rate_button_text(game: GameData) -> String:
	var existing: Dictionary = TierList.get_rating(game.id)
	return "★  Rated %d/10" % int(existing.get("score", 0)) \
		if not existing.is_empty() else "★  Rate this game"

func open_rating(game: GameData, btn: Button = null) -> Control:
	# By path, not by class: this card is on the page's compile path and the
	# rating modal is only ever opened on demand (test_page_load.gd).
	var modal: Control = load("res://scripts/ui/RateGameModal.gd").new()
	modal.setup(game.id, game)
	modal.submitted.connect(func(score: int, notes: String):
		TierList.set_rating(game.id, score, notes)
		var rank_now: bool = modal.wants_ranking()
		modal.queue_free()
		if btn != null and is_instance_valid(btn):
			btn.text = rate_button_text(game)
		if rank_now:
			# By path, at the click, as the haul screen does it: naming the class
			# here would compile the tier list into every run's page load
			# (docs/performance-backlog.md §6).
			load("res://scripts/ui/TierListScreen.gd").open(self, game.id))
	modal.dismissed.connect(func(): modal.queue_free())
	add_child(modal)
	return modal

# --- the route column ------------------------------------------------------

# The optimal path, as the real thing: the same layered DAG with green arrows the
# 🗺 map window draws, routed from the game this card is offering. This is what
# the card's Map button used to open in a separate window — it belongs in the
# decision, not one click further away from it.
func _build_route_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(LADDER_MIN_W, LADDER_MIN_H)

	# NO HEADING AND NO LEGEND: the map takes the column's whole height, from the
	# top of the popup to its buttons, with the popup's ✕ over its corner. The
	# "★ OPTIMAL — N steps left" line and the sentence under it cost the map two
	# rows; the kind marks are explained on every marker's hover.
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
	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(stack)
	_ladder_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_ladder_room)
	# The popup's ✕, over the map's top-right corner — the corner a route leaves
	# emptiest, since its last columns narrow to the Amulet.
	var close: Button = _close_button()
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	close.offset_left = -38
	close.offset_right = 0
	close.offset_top = 0
	close.offset_bottom = 38
	stack.add_child(close)
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
# the answer, minus the one thing a preview cannot do: there is no chart on this
# screen to fly.
func _ladder_cfg() -> Dictionary:
	var slot: StringName = _choice.get("slot", &"")
	var amulet: StringName = GameState.amulet_game_id
	var data: Dictionary = RunGraph.shortest_path_dag(slot, amulet) if slot != &"" and amulet != &"" else {}
	if _key_dest() != &"" and amulet != &"":
		data = _key_route(slot, _key_dest(), amulet)
	return {
		"data": data,
		"current": slot,
		"amulet": amulet,
		"choice_ids": {},
		"zoom": _zoom,
		"preview": true,
		"on_node": func(node_id: StringName, depth: int): open_node_card(node_id, depth),
		# The map is SIZED TO the box (RouteLadder `room`), less a scrollbar's lane.
		"room": (_ladder_room.size - Vector2(16, 16))
			if _ladder_room != null and is_instance_valid(_ladder_room) else Vector2.ZERO,
	}


# The route a Rift Key card would walk: its rift game, then the destination's own
# shortest route on. The rift is not laid yet, so the graph cannot answer it; the
# rung on top is stitched onto the destination's ladder, one step down.
static func _key_route(rift_id: StringName, dest: StringName, amulet: StringName) -> Dictionary:
	var on: Dictionary = RunGraph.shortest_path_dag(dest, amulet)
	var layers: Array = [[rift_id]]
	for layer in on.get("layers", []):
		layers.append(layer)
	var edges: Array = [{"from": rift_id, "to": dest, "from_depth": 0, "to_depth": 1}]
	for e in on.get("edges", []):
		var moved: Dictionary = (e as Dictionary).duplicate()
		moved["from_depth"] = int(e.get("from_depth", 0)) + 1
		moved["to_depth"] = int(e.get("to_depth", 0)) + 1
		edges.append(moved)
	return {"layers": layers, "edges": edges}

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
	var left: int = RunGraph.route_length(id, amulet)
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

# The map is sized to its box, so it is rebuilt whenever the box really changes
# size — which is why this runs off `resized`. Not only once: the first resize
# can land before the popup's layout has settled, and a map sized to THAT box
# came out a third too short with the room under it empty.
var _fitted_room := Vector2.ZERO
func _settle() -> void:
	if _ladder_room == null or not is_inside_tree():
		return
	var room: Vector2 = _ladder_room.size
	if room.x <= 1.0 or room.y <= 1.0 or (room - _fitted_room).length() < 2.0:
		return
	_fitted_room = room
	_set_zoom(_zoom)

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
	row.add_theme_constant_override("separation", UITheme.GAP_WIDE)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# NO WAY BACK ON AN ARRIVAL. A teleport has already put you here and already
	# spawned what is waiting (Overworld2.arrive_at_game): this screen is the
	# briefing, not the question. A "Back" on it would offer a choice that does not
	# exist, and the one thing worse than being dropped into a game unannounced is
	# being announced into one and shown a door that goes nowhere.
	var arrival: bool = bool(_notes.get("arrival", false))
	var rate: Button = _rate_button(game)
	rate.custom_minimum_size.y = 44
	row.add_child(rate)
	if not arrival:
		var back := HoverButton.new()
		back.text = "Back"
		back.custom_minimum_size = Vector2(110, 44)
		back.pressed.connect(_close)
		row.add_child(back)

	var go := HoverButton.new()
	go.text = String(_notes.get("action_text", "▶  Travel to %s" % game.display_name))
	go.tooltip_text = String(_notes.get("action_tip",
		"Commit to this game — you'll go and play it for real."))
	go.custom_minimum_size = Vector2(280, 44)
	go.clip_text = true
	go.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	go.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	go.add_theme_stylebox_override("normal", UITheme.flat(accent.lerp(UITheme.BG, 0.55), 8, 8, 2, accent))
	go.add_theme_stylebox_override("hover", UITheme.flat(accent.lerp(UITheme.BG, 0.38), 8, 8, 2, accent))
	go.add_theme_stylebox_override("focus", UITheme.flat(accent.lerp(UITheme.BG, 0.38), 8, 8, 2, accent))
	go.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.5))
	# An arrival's button only takes the screen down — the commit already happened,
	# so there is nothing left for `chose` to do and firing it would run the pick a
	# second time.
	go.pressed.connect(_close if arrival else func(): _answer(chose))
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
		if _proof_view != null and is_instance_valid(_proof_view):
			close_proof()
			return
		if _node_card != null and is_instance_valid(_node_card):
			close_node_card()
			return
		_close()
