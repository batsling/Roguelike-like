class_name RouteLadder
extends RefCounted

# RouteLadder — the layered top-to-bottom graph of the shortest-path DAG, drawn
# as boxes with green arrows between them.
#
# This used to live inside RunMapModal as `_build_graph` + `_node_box` + the
# GraphCanvas inner class, and it stayed there for as long as the map window was
# the only thing that wanted it. It isn't any more: GameChoiceModal — the popup a
# card opens — shows the same ladder for the game being considered, because "what
# does taking this do to my route" is the whole question that popup exists to
# answer. Two callers, so the drawing moves here and both ask for it the same way.
#
# The caller owns the MODEL (which route, at what zoom, with what pinned) and
# passes it in; this only knows how to lay a DAG out and paint it. RunMapModal
# keeps everything else it had — the window, the drag, the zoom buttons, the node
# card — and hands the rungs' clicks back to itself through `on_node`.

# --- role colours (kept close to the old web palette) ----------------------
const COL_CURRENT := Color(0.13, 0.59, 0.95)      # #2196F3 you-are-here blue
const COL_AMULET := Color(0.80, 0.40, 0.0)        # ember/gold amulet fill
const COL_CHOICE_BG := Color(0.24, 0.18, 0.0)     # reachable-now choice
const COL_PATH_BG := Color(0.29, 0.27, 0.25)      # on the road to the amulet
const COL_VISITED_BG := Color(0.16, 0.16, 0.16)   # already behind you
const COL_ARROW := Color(0.30, 0.78, 0.42, 0.85)  # shortest-path arrow green
const COL_WAYPOINT := Color(0.45, 0.24, 0.42)     # the game you insisted on

# Layout constants (pre-zoom). Mirrors the box/gap sizing in the old web build's
# generateMapView, with the vertical gap pulled in: at 6-8 steps the ladder is
# nine rows deep, and a gap bigger than half a rung spent more of the window on
# nothing than on the route it exists to show.
const BOX := Vector2(150, 48)
const H_GAP := 14.0
const V_GAP := 40.0
const PAD := 22.0

# A node's identity ON A LADDER is (depth, game) — not the game.
#
# A forced route walks to the pinned game and then walks on, and the way on is
# free to come straight back over the games that led in: the same game can hold
# two rungs, at two depths. Keying rects by id alone silently merged them into
# one rung and drew arrows into a step of the route that isn't there.
static func node_key(depth: int, id: StringName) -> String:
	return "%d|%s" % [depth, id]

# What a node is called on a map. Every rung is named as itself, the Amulet
# included.
#
# It used to have a `hide_amulet` mode that drew the destination as
# "The Amulet — ???" on a start-picker map, so the panel gave away the DISTANCE
# and nothing else. That is gone: the Amulet is named everywhere it appears, from
# the first screen of the run onwards. Choosing a start is a routing decision, and
# a routing decision made towards an unnamed box is a decision made on the shape
# of the road alone — the games the road actually runs through, and the one it
# ends on, are the whole substance of it.
static func node_name(id: StringName) -> String:
	var game: GameData = Data.get_game(id)
	return game.display_name if game != null else String(id)

# The game a rung actually plays. Normally the node's own game; on a transmuted
# spot, the replacement pasted over it (§4). Anything asking a rung a question
# about the GAME — does it sell, has it been beaten — has to go through here,
# because the node id only answers where the rung sits on the graph.
static func played_id(id: StringName) -> StringName:
	var game: GameData = GameLoop2.game_at(id)
	return game.id if game != null else id

# Build the ladder for one route. `cfg` is the model:
#
#   data         Dictionary  {layers, edges} from RunGraph.route_dag_via
#   current      StringName  the top rung — where you stand, or would stand
#   amulet       StringName  the bottom rung
#   waypoint     StringName  the pinned game, or &""
#   choice_ids   Dictionary  offered-right-now slots -> true (flagged on the ladder)
#   zoom         float       1.0 = natural size
#   preview      bool        the route from a game only being considered
#   on_node      Callable    (id: StringName, depth: int) -> void; unset = inert rungs
#
# Returns the canvas: a Control whose custom_minimum_size is the ladder's real
# extent, so the caller can fit a window to it.
static func build(cfg: Dictionary) -> Control:
	var data: Dictionary = cfg.get("data", {})
	var layers: Array = data.get("layers", [])
	var zoom: float = float(cfg.get("zoom", 1.0))

	# Compute per-node rects, layer by layer, centred horizontally.
	var box: Vector2 = BOX * zoom
	var h_gap: float = H_GAP * zoom
	var v_gap: float = V_GAP * zoom
	var pad: float = PAD * zoom

	var content_w: float = 0.0
	for layer in layers:
		var n: int = (layer as Array).size()
		if n > 0:
			content_w = maxf(content_w, n * box.x + (n - 1) * h_gap)
	content_w = maxf(content_w, box.x)
	var content_h: float = maxf(box.y, layers.size() * box.y + maxf(0, layers.size() - 1) * v_gap)

	# Keyed by (depth, id), not by id — a forced route can hold the same game on
	# two rungs, and they are two different places on this ladder.
	var rects: Dictionary = {}     # "depth|id" -> Rect2 (in canvas space, pre-pad)
	for i in range(layers.size()):
		var layer: Array = layers[i]
		var n: int = layer.size()
		var row_w: float = n * box.x + maxf(0, n - 1) * h_gap
		var start_x: float = (content_w - row_w) * 0.5
		var y: float = i * (box.y + v_gap)
		for j in range(n):
			var id: StringName = StringName(layer[j])
			var x: float = start_x + j * (box.x + h_gap)
			rects[node_key(i, id)] = Rect2(Vector2(x + pad, y + pad), box)

	# Arrow segments (bottom-centre of the parent -> top-centre of the child).
	var segments: Array = []
	for e in data.get("edges", []):
		var a: String = node_key(int(e.get("from_depth", 0)), StringName(e.get("from", "")))
		var b: String = node_key(int(e.get("to_depth", 0)), StringName(e.get("to", "")))
		if rects.has(a) and rects.has(b):
			var ra: Rect2 = rects[a]
			var rb: Rect2 = rects[b]
			segments.append([
				Vector2(ra.position.x + ra.size.x * 0.5, ra.position.y + ra.size.y),
				Vector2(rb.position.x + rb.size.x * 0.5, rb.position.y),
			])

	var canvas := GraphCanvas.new()
	canvas.segments = segments
	canvas.arrow_size = 9.0 * zoom
	canvas.custom_minimum_size = Vector2(content_w + pad * 2, content_h + pad * 2)

	# Node boxes on top of the arrows.
	var seen: Dictionary = {}      # id -> the depth it was FIRST met at
	for i in range(layers.size()):
		for id in layers[i]:
			var sid: StringName = StringName(id)
			var revisit: bool = seen.has(sid)
			if not revisit:
				seen[sid] = i
			canvas.add_child(node_box(cfg, sid, rects[node_key(i, sid)], i, revisit))

	if layers.is_empty():
		var empty := Label.new()
		empty.text = "The Amulet can't be reached from here."
		empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		canvas.custom_minimum_size = Vector2(420, 80)
		canvas.add_child(empty)
	return canvas

# One node = a bordered box with the game's name, coloured by its role.
#
# `depth` is the rung's layer and `revisit` says this game already had a rung
# further up — a forced route that doubles back through it on the way out.
static func node_box(cfg: Dictionary, id: StringName, rect: Rect2, depth: int,
		revisit: bool = false) -> Control:
	var current: StringName = cfg.get("current", &"")
	var amulet: StringName = cfg.get("amulet", &"")
	var pin: StringName = cfg.get("waypoint", &"")
	var choice_ids: Dictionary = cfg.get("choice_ids", {})
	var zoom: float = float(cfg.get("zoom", 1.0))
	var preview: bool = bool(cfg.get("preview", false))
	var on_node: Callable = cfg.get("on_node", Callable())

	var is_current: bool = id == current and depth == 0
	var is_amulet: bool = id == amulet
	var is_waypoint: bool = id == pin and pin != &"" and not is_current and not is_amulet
	var is_choice: bool = choice_ids.has(id) and not is_current and not is_amulet and not is_waypoint
	var is_visited: bool = not preview and GameState.visited_games.has(id) and not is_current

	var bg: Color = COL_PATH_BG
	var border: Color = UITheme.BORDER
	var border_w: int = 1
	var prefix: String = ""
	if is_current:
		bg = COL_CURRENT
		border = UITheme.SUCCESS
		border_w = 2
		prefix = "▶ " if preview else "📍 "
	elif is_amulet:
		bg = COL_AMULET
		border = UITheme.GOLD
		border_w = 2
		prefix = "🏆 "
	elif is_waypoint:
		bg = COL_WAYPOINT
		border = UITheme.GOLD
		border_w = 2
		prefix = "⚑ "
	elif is_choice:
		bg = COL_CHOICE_BG
		border = UITheme.ACCENT
		border_w = 2
		prefix = "◆ "
	elif is_visited:
		bg = COL_VISITED_BG
		border = UITheme.BORDER.lerp(UITheme.BG, 0.4)
	# A rung you are passing over for the second time is drawn as the same game,
	# faded, so the doubling-back reads as doubling back rather than as a bug.
	if revisit and not is_amulet:
		bg = bg.lerp(UITheme.BG, 0.45)
		prefix = "↩ "

	# A Panel, NOT a PanelContainer. A container takes its child's minimum size as
	# its own, and a shrunk rung holding a name like "Crypt of the NecroDancer"
	# wraps to four lines and grows the box back to fit them — straight over the
	# rung below it. The box owns its size here; the name is clipped into it.
	var panel := Panel.new()
	panel.position = rect.position
	panel.custom_minimum_size = rect.size
	panel.size = rect.size
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", UITheme.flat(bg, 6, 0, border_w, border))
	# Every rung can be a way IN to its game, when the caller wants one: click it
	# and the map opens a card on that game. The Amulet included — it is a game on
	# the road like any other, and the rung that ends the run is the one most worth
	# reading before you commit to walking towards it.
	var name_text: String = node_name(id)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if on_node.is_valid():
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = "%s — click for the details." % name_text
		panel.gui_input.connect(func(event):
			if event is InputEventMouseButton \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
					and (event as InputEventMouseButton).pressed:
				on_node.call(id, depth))
	else:
		panel.tooltip_text = name_text

	# The shop badge (§14): a hub game sells, and where the shops sit is the other
	# half of "which way do I go" — a route one step longer that passes a shelf is
	# routinely the better road. The ladder is where that comparison is made, so
	# the marker belongs on the rung rather than only on the page you reach.
	#
	# Read off the game actually PLAYED at the rung, not the rung's own id: a
	# transmuted spot plays an off-map game, and off-map games are never hubs, so
	# the shop leaves with the game it belonged to.
	var shop_w: float = 0.0
	if zoom >= 0.62 and ShopSystem.is_hub(played_id(id)):
		var shop := Label.new()
		shop.text = "🛒"
		# Bigger than the ⚔ badge opposite it, and for a reason that only shows up
		# on screen: ⚔ is a monochrome glyph that stays sharp at 9px, while 🛒 is a
		# colour bitmap that turns to mush. 12 is the size the same cart is drawn
		# at in the card's shop row, so the two read as the same marker.
		shop.add_theme_font_size_override("font_size", 12)
		shop.add_theme_color_override("font_color", UITheme.SHOP_GREEN)
		shop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shop.set_anchors_preset(Control.PRESET_TOP_LEFT)
		shop.offset_left = 4
		shop.offset_top = 2
		shop_w = 20.0
		panel.add_child(shop)
		panel.tooltip_text = "%s — a shop stands here." % name_text \
			+ ("" if not on_node.is_valid() else " Click for the details.")

	# The top-right corner: what you have DONE here, and how many ways there are
	# on from here.
	#
	# The connection count is the one that changes the decision. A rung is a place
	# the offering will be drawn from when you are standing on it, and the offering
	# is drawn from the neighbours — so a game with fourteen connections is a game
	# that will hand you a real choice, and a game with two is a corridor. That is
	# the odds the player is reading the ladder for, and until now the ladder was
	# the one view that did not say it.
	#
	# Both counts share one label rather than taking a corner each: the box is
	# 150px wide before zoom and the name has to fit between the badges.
	var fought: int = GameStats.enemies_for(id).size()
	var links: int = RunGraph.open_degree(id)
	var badge_w: float = 0.0
	if zoom >= 0.62 and (fought > 0 or links > 0):
		var marks: Array = []
		if fought > 0:
			marks.append("⚔%d" % fought)
		if links > 0:
			marks.append("⛓%d" % links)
		var badge := Label.new()
		badge.text = " ".join(PackedStringArray(marks))
		badge.add_theme_font_size_override("font_size", 9)
		badge.add_theme_color_override("font_color", UITheme.GOLD if fought > 0
			else UITheme.TEXT_DIM)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -4
		badge.offset_top = 2
		badge_w = 22.0 * marks.size()
		panel.add_child(badge)
		# The glyphs are small and unlabelled, so the rung says what they mean.
		panel.tooltip_text = "%s\n%s" % [panel.tooltip_text, _badge_tip(fought, links)]

	var label := Label.new()
	# A shrunk rung is barely wider than the glyph, and a name is worth more than
	# a marker the colour already carries.
	label.text = (prefix if zoom >= 0.62 else "") + name_text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The name keeps clear of the badges rather than running under them.
	label.offset_left = 4.0 + shop_w
	label.offset_right = -(4.0 + badge_w)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Clipped rather than wrapped forever: what doesn't fit the rung is trimmed to
	# an ellipsis, and the whole name is a hover away (the tooltip above).
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A floor as well as a ceiling: a long route fits by shrinking, and a rung
	# whose name has shrunk out of legibility isn't a rung any more.
	label.add_theme_font_size_override("font_size", maxi(9, int(11 * clampf(zoom, 0.7, 1.4))))
	label.add_theme_color_override("font_color",
		Color.WHITE if (is_current or is_amulet or is_waypoint) else UITheme.TEXT)
	panel.add_child(label)
	return panel

# The corner badges in words. ⚔ is your record here; ⛓ is how many games this one
# connects to on the run's map — the pool the next offering is drawn from when
# you are standing on it, and the same count the offered card's own ⛓ line gives.
static func _badge_tip(fought: int, links: int) -> String:
	var lines: Array = []
	if fought > 0:
		lines.append("⚔ %d enem%s beaten here." % [fought, "y" if fought == 1 else "ies"])
	if links > 0:
		lines.append("⛓ %d connection%s — the pool the offering is drawn from here." % [
			links, "" if links == 1 else "s"])
	return "\n".join(PackedStringArray(lines))

# ---------------------------------------------------------------------------
# The rung's CARD
#
# A rung is 150x48 with a clipped name in it, which is all a ladder should be and
# nowhere near enough to decide anything on. Clicking one opens the game: its
# cover, where it sits on this route, what you have already done there, and
# whatever the caller can offer to do about it.
#
# It lives HERE, with the ladder, because every ladder wants it and they must not
# each write their own. The map window opens one beside its window; the popup a
# card opens draws one over its route column — same facts, same order, same
# wording, and only the ACTIONS differ (a preview has no route to pin and no sky
# to fly). The caller owns the frame and where it sits; this owns what is in it.
#
# `cfg`:
#   id       StringName  the game
#   name     String      what to call it — node_name()
#   role     String      the line under the title ("You are here.")
#   facts    Array       [[key, value], …] the caller's own route facts, first
#   actions  Array       [{"text": String, "tip": String, "action": Callable}]
#   on_close Callable    the Close button; omitted when unset
static func node_card_body(cfg: Dictionary) -> VBoxContainer:
	var id: StringName = cfg.get("id", &"")
	var game: GameData = Data.get_game(id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = String(cfg.get("name", "")) if String(cfg.get("name", "")) != "" \
		else (game.display_name if game != null else String(id))
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var role_text: String = String(cfg.get("role", ""))
	if role_text != "":
		var role := Label.new()
		role.text = role_text
		role.add_theme_font_size_override("font_size", 12)
		role.add_theme_color_override("font_color", UITheme.ACCENT)
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(role)

	if game != null and game.cover_image != null:
		var art := AtlasView.card_art(game.cover_image, CARD_ART_W, 190.0)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(art)

	if game != null:
		var meta: Array = []
		if game.year > 0:
			meta.append(str(game.year))
		meta.append(RunGraph.type_label(game.type))
		var chip := Label.new()
		chip.text = "  •  ".join(PackedStringArray(meta)).to_upper()
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
		box.add_child(chip)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 3)
	box.add_child(facts)
	for row in cfg.get("facts", []):
		if row is Array and (row as Array).size() >= 2:
			facts.add_child(card_fact(String(row[0]), String(row[1])))
	# The same number the rung's ⛓ badge carries and the Atlas's card calls
	# "Connections", spelled out in the same words on all three.
	var links: int = RunGraph.open_degree(id)
	if links > 0:
		facts.add_child(card_fact("Connections", "%d game%s" % [
			links, "" if links == 1 else "s"]))
	var beaten_times: int = GameStats.beaten_count(id)
	facts.add_child(card_fact("⚔ Beaten", ("%d time%s" % [beaten_times,
		"" if beaten_times == 1 else "s"]) if beaten_times > 0 else "never"))
	var amulet_runs: int = GameStats.amulet_wins(id)
	if amulet_runs > 0:
		facts.add_child(card_fact("👑 Amulet won", "%d run%s" % [amulet_runs,
			"" if amulet_runs == 1 else "s"]))
	if TierList.has_rating(id):
		var tier_i: int = TierList.tier_of(id)
		facts.add_child(card_fact("Your rating", "%d / 10%s" % [
			int(TierList.get_rating(id).get("score", 0)),
			("  (%s tier)" % TierList.tier_names[tier_i]) if tier_i >= 0
				and tier_i < TierList.tier_names.size() else ""]))

	# The record you have IN this game — the same fact the rung's ⚔ badge carries,
	# spelled out.
	var fought: Array = GameStats.enemies_for(id)
	if not fought.is_empty():
		box.add_child(card_heading("Enemies you have beaten here (%d)" % fought.size()))
		for i in range(mini(fought.size(), 6)):
			var e: Dictionary = fought[i]
			var ed: GoalEnemyData = Data.get_goal_enemy_any(StringName(e["id"]))
			box.add_child(card_fact(
				ed.display_name if ed != null else String(e["id"]),
				"x%d" % int(e["beaten"])))
		if fought.size() > 6:
			box.add_child(card_note("…and %d more." % (fought.size() - 6)))

	box.add_child(HSeparator.new())
	for action in cfg.get("actions", []):
		if not (action is Dictionary):
			continue
		var cb = action.get("action")
		if not (cb is Callable) or not (cb as Callable).is_valid():
			continue
		var btn := card_button(String(action.get("text", "…")), cb)
		btn.tooltip_text = String(action.get("tip", ""))
		box.add_child(btn)
	# The real game, on every card that can reach it — the one action that is
	# never about the route, so no caller has to remember to ask for it.
	if game != null and game.has_launch_target():
		box.add_child(card_button("▶  Play the real game", func(): game.launch()))
	var on_close = cfg.get("on_close")
	if on_close is Callable and (on_close as Callable).is_valid():
		box.add_child(card_button("Close", on_close))
	return box

# The cover's width inside a card. The card itself is 300 wide (RunMapModal's
# CARD_W) less its margins and the scrollbar's lane.
const CARD_ART_W := 248.0

static func card_fact(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 12)
	k.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(v)
	return row

static func card_heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.GOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func card_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func card_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	return b

# The zoom at which a ladder of `ladder` px (measured at `zoom`) fits `room` px.
# Only ever shrinks — a short route is never blown up to fill the space — and
# never past `floor_zoom`, where the names stop being readable and scrolling a
# bigger ladder is the better deal.
#
# `slack` keeps a hair of room in hand: a route fitted to the last pixel raises a
# scrollbar for two pixels of overshoot, and the scrollbar then eats the room the
# fit was measured against.
static func fit_zoom(ladder: Vector2, room: Vector2, zoom: float,
		floor_zoom: float = 0.40, slack: float = 0.96) -> float:
	if room.x <= 0.0 or room.y <= 0.0 or ladder.x <= 0.0 or ladder.y <= 0.0:
		return 1.0
	return clampf(zoom * minf(room.x / ladder.x, room.y / ladder.y) * slack, floor_zoom, 1.0)

# ---------------------------------------------------------------------------
# GraphCanvas — a bare Control that draws the arrow segments behind the node
# boxes (which are added as its children).
# ---------------------------------------------------------------------------
class GraphCanvas extends Control:
	var segments: Array = []          # [[Vector2 from, Vector2 to], ...]
	var arrow_size: float = 9.0

	func _draw() -> void:
		for seg in segments:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			# Stop the line a touch short of the box so the arrowhead sits clear.
			var dir: Vector2 = (b - a)
			if dir.length() < 0.001:
				continue
			dir = dir.normalized()
			var tip: Vector2 = b - dir * 2.0
			draw_line(a, tip - dir * arrow_size, COL_ARROW, 2.5 * (arrow_size / 9.0), true)
			# Arrowhead triangle at the child end.
			var perp: Vector2 = Vector2(-dir.y, dir.x) * (arrow_size * 0.5)
			var base: Vector2 = tip - dir * arrow_size
			draw_colored_polygon(
				PackedVector2Array([tip, base + perp, base - perp]), COL_ARROW)
