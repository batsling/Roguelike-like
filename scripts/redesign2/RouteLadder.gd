class_name RouteLadder
extends RefCounted

# RouteLadder — the shortest-path DAG drawn as a MAP: left to right, one column
# per step of the road, the games in each column spread over the height they are
# given and nudged a little off their grid, with green arrows between them.
#
# This used to live inside RunMapModal as `_build_graph` + `_node_box` + the
# GraphCanvas inner class, and it stayed there for as long as the map window was
# the only thing that wanted it. It isn't any more: GameChoiceModal — the popup a
# card opens — shows the same map for the game being considered, because "what
# does taking this do to my route" is the whole question that popup exists to
# answer. Two callers, so the drawing moves here and both ask for it the same way.
#
# The caller owns the MODEL (which route, at what zoom, what is on offer, how much
# room there is) and passes it in; this only knows how to lay a DAG out and paint
# it. RunMapModal keeps everything else it had — the window, the drag, the zoom
# buttons, the node card — and hands the boxes' clicks back through `on_node`.
#
# WHY LEFT TO RIGHT, AND WHY SCATTERED (the map redesign). It was a top-to-bottom
# ladder of 150x68 name boxes, and the widest layer of a route — a median of 7
# games, 14 at the 90th percentile, 20 at worst — is what decided its width: a
# row of wide boxes in a 16:9 window shrank until most names were ellipses. A
# column of short boxes stacks that same layer down the window's height instead,
# and the depth (6 steps at the median, 9 at most) runs along its width. Each
# column's games are spread over the whole height, so a sparse column does not
# sit in a clump in the middle of empty space, and nudged off the grid by a hash
# of the game, so the same route always looks the same and still reads as a map
# rather than a spreadsheet.

# --- role colours (kept close to the old web palette) ----------------------
const COL_CURRENT := Color(0.13, 0.59, 0.95)      # #2196F3 you-are-here blue
const COL_AMULET := Color(0.80, 0.40, 0.0)        # ember/gold amulet fill
const COL_CHOICE_BG := Color(0.24, 0.18, 0.0)     # reachable-now choice
const COL_PATH_BG := Color(0.29, 0.27, 0.25)      # on the road to the amulet
const COL_VISITED_BG := Color(0.16, 0.16, 0.16)   # already behind you
const COL_ARROW := Color(0.30, 0.78, 0.42, 0.85)  # shortest-path arrow green
# What a plain box's name sits on. Near-black, not the old grey fill: the cover is
# the colour now, and only the roles (you, the Amulet, an offer) keep their own.
const COL_FADE := Color(0.03, 0.03, 0.04)

# --- layout (pre-zoom) -------------------------------------------------------
#
# A box's natural size when the map is drawn with no room given (the window over
# the star chart, which sizes itself to the map rather than the other way round).
const BOX := Vector2(190, 44)
const COL_GAP := 36.0          # between columns, at the natural size
const COL_GAP_MIN := 16.0      # …squeezed to no less than this when room is tight
const COL_GAP_MAX := 160.0     # …and never spread wider than this when it isn't
const ROW_GAP := 6.0           # between boxes stacked in the densest column
const PAD := 22.0              # around the whole map, at the natural size
const ROOM_PAD := 10.0         # …and when it is sized to the room it is given
# Sized to a room, a box is never smaller than this — past it a name has nowhere
# to go — and never taller than BOX_MAX_H, past which a sparse route's boxes
# would be posters.
const BOX_MIN := Vector2(56, 18)
const BOX_MAX_H := 64.0
# How far a box may stray from its slot, as a share of the slot's spare room.
const JITTER_Y := 0.4
const JITTER_X := 0.3
const JITTER_X_MAX := 24.0
# A box at least this wide keeps the ⚔/⛓ corner badge and the strip it sits in.
# Narrower, the badge would sit on the name; the counts are in its hover anyway.
const WIDE_W := 120.0

# A node's identity ON A MAP is (depth, game) — not the game.
#
# Every edge carries its endpoints' DEPTHS, and the map places by them. A
# shortest-path DAG holds each game once, but keying by (depth, id) costs nothing
# and keeps a route spliced together by hand (a Rift Key's, GameChoiceModal
# _key_route) from merging two boxes into one if it ever visits a game twice.
# (It was written for pinned routes, which doubled back; pinning is gone.)
static func node_key(depth: int, id: StringName) -> String:
	return "%d|%s" % [depth, id]

# What a node is called on a map. Every box is named as itself, the Amulet
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

# Build the map for one route. `cfg` is the model:
#
#   data         Dictionary  {layers, edges} from RunGraph.shortest_path_dag
#   current      StringName  the first column — where you stand, or would stand
#   amulet       StringName  the last column
#   choice_ids   Dictionary  offered-right-now slots -> true (flagged on the map)
#   zoom         float       1.0 = natural size (or the room's size, given a room)
#   preview      bool        the route from a game only being considered
#   on_node      Callable    (id: StringName, depth: int) -> void; unset = inert boxes
#   room         Vector2     optional: the view's size. Given one, the map is
#                            SIZED TO IT — boxes, gaps and spread — and zoom
#                            scales from there; without one it is drawn at its
#                            natural size and the caller fits the window to it.
#
# Returns the canvas: a Control whose custom_minimum_size is the map's real
# extent, so the caller can fit a window to it.
static func build(cfg: Dictionary) -> Control:
	var data: Dictionary = cfg.get("data", {})
	var edges: Array = data.get("edges", [])
	var layers: Array = order_layers(data.get("layers", []), edges)
	var zoom: float = float(cfg.get("zoom", 1.0))
	var canvas := GraphCanvas.new()
	if layers.is_empty():
		var empty := Label.new()
		empty.text = "The Amulet can't be reached from here."
		empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		canvas.custom_minimum_size = Vector2(420, 80)
		canvas.add_child(empty)
		return canvas

	var cols: int = layers.size()
	var densest: int = 1
	for layer in layers:
		densest = maxi(densest, (layer as Array).size())

	var box: Vector2 = BOX * zoom
	var gap: float = COL_GAP * zoom
	var pad: float = PAD * zoom
	var room: Vector2 = cfg.get("room", Vector2.ZERO)
	var inner := Vector2.ZERO
	if room.x > 0.0 and room.y > 0.0:
		# SIZED TO THE ROOM, each axis on its own: a map short of width still takes
		# the height it has spare, rather than one zoom shrinking both. The gap
		# gives way first (down to COL_GAP_MIN), then the boxes.
		pad = ROOM_PAD
		inner = room - Vector2(pad, pad) * 2.0
		gap = clampf((inner.x - cols * 80.0) / maxf(1.0, cols - 1), COL_GAP_MIN, COL_GAP)
		box.x = clampf((inner.x - (cols - 1) * gap) / cols, BOX_MIN.x, BOX.x)
		box.y = clampf((inner.y - (densest - 1) * ROW_GAP) / densest, BOX_MIN.y, BOX_MAX_H)
		box *= zoom
		gap *= zoom
	var need := Vector2(cols * box.x + (cols - 1) * gap,
		densest * box.y + (densest - 1) * ROW_GAP * zoom)
	# The STAGE the columns spread over: the room (within reason) when there is
	# one, the map's own extent when there isn't. Never narrower than the map
	# needs — zoomed past the room, the map scrolls.
	var stage: Vector2 = need
	if inner.x > 0.0:
		stage.x = clampf(inner.x, need.x, cols * box.x + (cols - 1) * COL_GAP_MAX * zoom)
		stage.y = maxf(need.y, minf(inner.y, need.y * 2.2 + 60.0 * zoom))

	# Each column spread over the stage's height, its games nudged off their slots.
	# Not the first column or the last: they hold you and the Amulet alone, and the
	# road reads from a fixed start to a fixed end.
	var rects: Dictionary = {}     # "depth|id" -> Rect2 (in canvas space)
	var step_x: float = (stage.x - box.x) / float(maxi(1, cols - 1))
	for i in range(cols):
		var layer: Array = layers[i]
		var slot: float = stage.y / float(layer.size())
		for j in range(layer.size()):
			var id := StringName(layer[j])
			var key: String = node_key(i, id)
			var nudge := Vector2.ZERO
			if i != 0 and i != cols - 1:
				nudge.x = _jitter(key, 1) * minf(JITTER_X_MAX * zoom,
					maxf(0.0, step_x - box.x) * JITTER_X)
				nudge.y = _jitter(key, 2) * maxf(0.0, slot - box.y - ROW_GAP * zoom) * JITTER_Y
			var x: float = (stage.x - box.x) * 0.5 if cols == 1 else i * step_x
			var y: float = (j + 0.5) * slot - box.y * 0.5
			rects[key] = Rect2(Vector2(x, y) + nudge + Vector2(pad, pad), box)

	# The arrows: out of a box's right edge, into the next one's left — where its
	# kind marker sits (kind_marker), so the head lands on the marker's edge.
	var segments: Array = []
	for e in edges:
		var to_id := StringName(e.get("to", ""))
		var a: String = node_key(int(e.get("from_depth", 0)), StringName(e.get("from", "")))
		var b: String = node_key(int(e.get("to_depth", 0)), to_id)
		if rects.has(a) and rects.has(b):
			var ra: Rect2 = rects[a]
			var rb: Rect2 = rects[b]
			# The third entry flags a step THROUGH A RIFT (either end a rift game),
			# drawn in the rift's own dashed line rather than as an influence.
			segments.append([
				Vector2(ra.end.x, ra.position.y + port_y(ra.size)),
				Vector2(rb.position.x - marker_w(GameState.node_kind(to_id)) * 0.5,
					rb.position.y + port_y(rb.size)),
				RunGraph.is_rift_game(StringName(e.get("from", ""))) or RunGraph.is_rift_game(to_id),
			])
	canvas.segments = segments
	canvas.arrow_size = 9.0 * clampf(box.y / BOX.y, 0.6, 1.0)
	canvas.custom_minimum_size = stage + Vector2(pad, pad) * 2.0

	# ONE NAME SIZE PER MAP: the largest every name fits at, so a map reads as one
	# thing rather than as a box of differently-sized labels — floored at
	# UNIFORM_FLOOR, below which the few longest names step down on their own
	# rather than dragging every other name down with them.
	var natural_fs: int = maxi(NAME_MIN_FONT, int(NAME_FONT * clampf(zoom, 1.0, 1.4)))
	var uniform: int = natural_fs
	for k in rects:
		uniform = mini(uniform, fit_name_size(node_name(StringName(String(k).get_slice("|", 1))),
			name_avail((rects[k] as Rect2).size), natural_fs, NAME_MIN_FONT))
	var box_cfg: Dictionary = cfg.duplicate()
	box_cfg["name_font"] = maxi(uniform, UNIFORM_FLOOR)

	# The boxes, and the marker on the path into each, on top of the arrows.
	var seen: Dictionary = {}      # id -> the depth it was FIRST met at
	for i in range(cols):
		for id in layers[i]:
			var sid := StringName(id)
			var revisit: bool = seen.has(sid)
			if not revisit:
				seen[sid] = i
			var rect: Rect2 = rects[node_key(i, sid)]
			canvas.add_child(node_box(box_cfg, sid, rect, i, revisit))
			canvas.add_child(kind_marker(sid, rect))
	return canvas

# THE ORDER WITHIN EACH COLUMN, chosen to cross as few arrows as the DAG allows:
# a few sweeps of the barycentre heuristic, each column sorted by the mean slot of
# the games it links to in the column before (sweeping right) or after (sweeping
# left). With the boxes spread and nudged, an unsorted column was spaghetti; this
# is what keeps a game's road level with the games it leads to.
static func order_layers(layers: Array, edges: Array) -> Array:
	var out: Array = []
	for l in layers:
		out.append((l as Array).duplicate())
	for sweep in 4:
		var right: bool = sweep % 2 == 0
		var span: Array = range(1, out.size()) if right else range(out.size() - 2, -1, -1)
		for i in span:
			var ref: Array = out[i - 1 if right else i + 1]
			var pos: Dictionary = {}
			for k in ref.size():
				pos[String(ref[k])] = k
			var score: Dictionary = {}
			for k in (out[i] as Array).size():
				var id := String(out[i][k])
				var sum := 0.0
				var n := 0
				for e in edges:
					var other: String = ""
					if right and int(e.get("to_depth", -1)) == i and String(e.get("to", "")) == id:
						other = String(e.get("from", ""))
					elif not right and int(e.get("from_depth", -1)) == i and String(e.get("from", "")) == id:
						other = String(e.get("to", ""))
					if other != "" and pos.has(other):
						sum += float(pos[other])
						n += 1
				score[id] = sum / n if n > 0 else float(k)
			(out[i] as Array).sort_custom(func(x, y): return score[String(x)] < score[String(y)])
	return out

# A box's nudge off its slot, in -1..1: a hash of the box, so the same route is
# drawn the same way every time the map opens, rather than reshuffling.
static func _jitter(key: String, salt: int) -> float:
	return float(absi(hash("%s#%d" % [key, salt])) % 10000) / 10000.0 * 2.0 - 1.0

# ---------------------------------------------------------------------------
# The kind marker — on the path, not in the box
#
# THE NODE'S KIND (§19.8) as a small pill where the arrows arrive, half over the
# box's left edge: the step INTO a game is what the kind describes (a fight, an
# event, a shop), so it rides the step, and the box keeps its whole face for the
# cover and the name. Read off the BOX's id, never the game played there, for the
# reason §19.2 gives: the kind rides the node, so a transmuted spot keeps its
# kind while it plays a different game.
# ---------------------------------------------------------------------------

const MARKER_H := 16.0

# Where the path meets a box: near its TOP, over the cover, so the marker riding
# it never lands on the name (which sits along the bottom).
static func port_y(size: Vector2) -> float:
	return minf(size.y * 0.5, MARKER_H * 0.5 + 3.0)

static func marker_w(kind: int) -> float:
	return maxf(MARKER_H, 8.0 + 6.0 * RunGraph.kind_mark(kind).length())

static func kind_marker(id: StringName, rect: Rect2) -> Control:
	var kind: int = GameState.node_kind(id)
	var w: float = marker_w(kind)
	var pill := Panel.new()
	pill.name = "KindMarker"
	pill.add_theme_stylebox_override("panel", UITheme.flat(Color(0.06, 0.06, 0.07, 0.95),
		int(MARKER_H * 0.5), 0, 1, UITheme.kind_color(kind)))
	pill.size = Vector2(w, MARKER_H)
	pill.position = Vector2(rect.position.x - w * 0.5,
		rect.position.y + port_y(rect.size) - MARKER_H * 0.5)
	pill.tooltip_text = RunGraph.kind_tip(kind)
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	var mark := Label.new()
	mark.name = "KindMark"
	mark.text = RunGraph.kind_mark(kind)
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
	mark.add_theme_color_override("font_color", UITheme.kind_color(kind))
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(mark)
	return pill

# ---------------------------------------------------------------------------
# The box
# ---------------------------------------------------------------------------

# One node = the game's cover filling a box, its name along the bottom on a fade
# in the box's ROLE colour, and — on a wide box — what you have done there and
# how many ways on it has, in the top-right corner.
#
# `depth` is the box's column and `revisit` says this game already had a box
# further left (see node_key).
static func node_box(cfg: Dictionary, id: StringName, rect: Rect2, depth: int,
		revisit: bool = false) -> Control:
	var current: StringName = cfg.get("current", &"")
	var amulet: StringName = cfg.get("amulet", &"")
	var choice_ids: Dictionary = cfg.get("choice_ids", {})
	var zoom: float = float(cfg.get("zoom", 1.0))
	var preview: bool = bool(cfg.get("preview", false))
	var on_node: Callable = cfg.get("on_node", Callable())

	var is_current: bool = id == current and depth == 0
	var is_amulet: bool = id == amulet
	var is_choice: bool = choice_ids.has(id) and not is_current and not is_amulet
	var is_visited: bool = not preview and GameState.visited_games.has(id) and not is_current

	var bg: Color = COL_PATH_BG
	var border: Color = UITheme.BORDER
	var border_w: int = 1
	if is_current:
		bg = COL_CURRENT
		border = UITheme.SUCCESS
		border_w = 2
	elif is_amulet:
		bg = COL_AMULET
		border = UITheme.GOLD
		border_w = 2
	elif is_choice:
		bg = COL_CHOICE_BG
		border = UITheme.ACCENT
		border_w = 2
	elif is_visited:
		bg = COL_VISITED_BG
		border = UITheme.BORDER.lerp(UITheme.BG, 0.4)
	# A RIFT GAME (docs/rifts-design.md §9) wears the rift colour on an otherwise
	# plain box.
	elif RunGraph.is_rift_game(id):
		border = UITheme.RIFT
		border_w = 2
	# A box you are passing over for the second time is drawn as the same game,
	# faded, so the doubling-back reads as doubling back rather than as a bug.
	if revisit and not is_amulet:
		bg = bg.lerp(UITheme.BG, 0.45)
	var role: bool = is_current or is_amulet or is_choice

	# A Panel, NOT a PanelContainer. A container takes its child's minimum size as
	# its own, and a small box holding a name like "Crypt of the NecroDancer"
	# wraps to four lines and grows the box back to fit them — straight over the
	# box below it. The box owns its size here; the name is clipped into it.
	var panel := Panel.new()
	panel.position = rect.position
	panel.custom_minimum_size = rect.size
	panel.size = rect.size
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", UITheme.flat(bg, 6, 0, border_w, border))
	# Every box can be a way IN to its game, when the caller wants one: click it
	# and the map opens a card on that game. The Amulet included — it is a game on
	# the road like any other, and the box that ends the run is the one most worth
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
	var kind: int = GameState.node_kind(id)
	panel.tooltip_text = "%s\n%s" % [panel.tooltip_text, RunGraph.kind_tip(kind)]

	# THE COVER FILLS THE BOX, cut to the box's shape (cover_crop), and the name
	# sits on a fade along the bottom. The fade is the ROLE's colour on the three
	# boxes that have one — you-are-here is still blue, the Amulet still ember, an
	# offer still gold — and near-black on the rest, so the art is the colour.
	var game: GameData = Data.get_game(id)
	var has_art: bool = game != null and game.cover_image != null
	if has_art:
		var inset: float = float(border_w)
		var art := TextureRect.new()
		art.name = "Cover"
		art.texture = cover_crop(game.cover_image, rect.size)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.offset_left = inset
		art.offset_top = inset
		art.offset_right = -inset
		art.offset_bottom = -inset
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_visited or revisit:
			art.modulate = Color(1, 1, 1, 0.45)
		panel.add_child(art)
		var tint: Color = bg if role else COL_FADE
		var grad := Gradient.new()
		grad.set_color(0, Color(tint, 0.0))
		grad.set_color(1, Color(tint, 0.92))
		grad.add_point(0.5, Color(tint, 0.72))
		var fill := GradientTexture2D.new()
		fill.gradient = grad
		fill.fill_from = Vector2(0, 0)
		fill.fill_to = Vector2(0, 1)
		fill.width = 4
		fill.height = 64
		var fade := TextureRect.new()
		fade.name = "Fade"
		fade.texture = fill
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.offset_left = inset
		fade.offset_right = -inset
		fade.offset_bottom = -inset
		fade.offset_top = rect.size.y * 0.2
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(fade)

	# The top-right corner of a WIDE box: what you have DONE here, and how many
	# ways there are on from here.
	#
	# The connection count is the one that changes the decision. A box is a place
	# the offering will be drawn from when you are standing on it, and the offering
	# is drawn from the neighbours — so a game with fourteen connections is a game
	# that will hand you a real choice, and a game with two is a corridor.
	var fought: int = GameStats.enemies_for(id).size()
	var links: int = RunGraph.open_degree(id)
	# The counts are in EVERY box's hover, badge or not: a narrow box has no room
	# for the badge, and the count is still the number the route is read for.
	if fought > 0 or links > 0:
		panel.tooltip_text = "%s\n%s" % [panel.tooltip_text, _badge_tip(fought, links)]
	if rect.size.x >= WIDE_W and (fought > 0 or links > 0):
		var marks: Array = []
		if fought > 0:
			marks.append("⚔%d" % fought)
		if links > 0:
			marks.append("⛓%d" % links)
		var badge := Label.new()
		badge.name = "Badge"
		badge.text = " ".join(PackedStringArray(marks))
		badge.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
		badge.add_theme_color_override("font_color", UITheme.GOLD if fought > 0
			else UITheme.TEXT_DIM)
		var backing := UITheme.flat(Color(0.05, 0.05, 0.05, 0.85), 3, 0)
		backing.content_margin_left = 3
		backing.content_margin_right = 3
		badge.add_theme_stylebox_override("normal", backing)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -4
		badge.offset_top = 2
		panel.add_child(badge)

	var label := Label.new()
	label.name = "Name"
	label.text = name_text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = NAME_INSET
	label.offset_right = -NAME_INSET
	label.offset_top = name_top(rect.size)
	label.offset_bottom = -2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# Outlined: it sits over somebody's box art, and no single colour reads over
	# every cover.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	# WORD, not WORD_SMART: the size below is chosen so every word fits whole, so
	# nothing should ever be broken mid-word ("HyperRogu / e").
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Clipped rather than wrapped forever: what STILL doesn't fit (a name too long
	# for the box even at the floor size) is trimmed to an ellipsis, and the whole
	# name is a hover away (the tooltip above).
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THE NAME IS SIZED TO FIT: the map's one size (`name_font`, see build) unless
	# this name needs smaller, in which case the largest size at which every word
	# fits the width whole and the wrapped name fits the height.
	var natural: int = maxi(NAME_MIN_FONT, int(NAME_FONT * clampf(zoom, 1.0, 1.4)))
	var own: int = fit_name_size(name_text, name_avail(rect.size), natural, NAME_MIN_FONT)
	label.add_theme_font_size_override("font_size", mini(own, int(cfg.get("name_font", own))))
	label.add_theme_color_override("font_color",
		Color.WHITE if (is_current or is_amulet) else UITheme.TEXT)
	panel.add_child(label)
	return panel

# The part of a cover a box shows: as much as the box's shape allows, taken from
# a little below the TOP — where most covers put the title — rather than the
# middle, so a strip of a portrait cover still carries its logo.
static func cover_crop(tex: Texture2D, box: Vector2) -> Texture2D:
	var ts: Vector2 = tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0 or box.x <= 0.0 or box.y <= 0.0:
		return tex
	var want: float = box.x / box.y
	var region := Rect2(Vector2.ZERO, ts)
	if ts.x / ts.y < want:
		region.size.y = ts.x / want
		region.position.y = (ts.y - region.size.y) * 0.22
	else:
		region.size.x = ts.y * want
		region.position.x = (ts.x - region.size.x) * 0.5
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = region
	return at

# The name's sizes: natural (scaled by zoom), the floor it may step down to to
# fit whole words, and the size a whole map holds to (see build).
const NAME_FONT := 13
const NAME_MIN_FONT := 9
const UNIFORM_FLOOR := 10
const NAME_INSET := 4.0
# A Label's default `line_spacing`, which a wrapped name pays between lines.
const LINE_SPACING := 3.0

# Where a box's name may start: just under the top edge, or under the badge strip
# on a box wide enough to have one.
static func name_top(size: Vector2) -> float:
	return 13.0 if size.x >= WIDE_W else 2.0

# The room a box's name gets, by the box's size alone — so build can pick one
# size for every name on the map before any box exists.
static func name_avail(size: Vector2) -> Vector2:
	return Vector2(size.x - NAME_INSET * 2.0, size.y - name_top(size) - 2.0)

# One line of the name at `fs`, measured off the font the label draws in rather
# than guessed — a guess a pixel high is the difference between two lines and
# an ellipsis on the boxes this is for.
static func name_line_h(fs: int) -> float:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return fs * 1.4 + LINE_SPACING
	return font.get_height(fs) + LINE_SPACING

# The largest size in [floor, natural] at which `text` wraps (between words only)
# inside `avail` with no word wider than the width. Measured with the theme's
# base font, which is the one these labels draw in. Falls back to the floor when
# nothing fits — the label's ellipsis then takes the rest.
static func fit_name_size(text: String, avail: Vector2, natural: int, floor_size: int) -> int:
	var font: Font = ThemeDB.fallback_font
	if font == null or avail.x <= 0.0 or avail.y <= 0.0:
		return floor_size
	var words: PackedStringArray = text.split(" ", false)
	for fs in range(natural, floor_size - 1, -1):
		# The first line is the font's height; every one after adds the Label's
		# line spacing on top.
		var max_lines: int = int(floor((avail.y + LINE_SPACING) / name_line_h(fs)))
		if max_lines < 1:
			continue
		var space: float = font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lines: int = 1
		var line_w: float = 0.0
		var fits: bool = true
		for w in words:
			var ww: float = font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if ww > avail.x:
				fits = false
				break
			if line_w <= 0.0:
				line_w = ww
			elif line_w + space + ww <= avail.x:
				line_w += space + ww
			else:
				lines += 1
				line_w = ww
		if fits and lines <= max_lines:
			return fs
	return floor_size

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
# The box's CARD
#
# A box is a cover and a clipped name, which is all a map should be and
# nowhere near enough to decide anything on. Clicking one opens the game: its
# cover, where it sits on this route, what you have already done there, and
# whatever the caller can offer to do about it.
#
# It lives HERE, with the map, because every map wants it and they must not each
# write their own. The map window opens one beside its window; the popup a card
# opens draws one over its route column — same facts, same order, same wording,
# and only the ACTIONS differ (a preview has no sky to fly). The caller owns the
# frame and where it sits; this owns what is in it.
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
	box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = String(cfg.get("name", "")) if String(cfg.get("name", "")) != "" \
		else (game.display_name if game != null else String(id))
	title.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var role_text: String = String(cfg.get("role", ""))
	if role_text != "":
		var role := Label.new()
		role.text = role_text
		role.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		role.add_theme_color_override("font_color", UITheme.ACCENT)
		role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(role)

	if game != null and game.cover_image != null:
		var art := UITheme.card_art(game.cover_image, CARD_ART_W, 190.0)
		UITheme.attach_tier_badge(art, game.id)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(art)

	if game != null:
		var meta: Array = []
		if game.year > 0:
			meta.append(str(game.year))
		meta.append(RunGraph.type_label(game.type))
		var chip := Label.new()
		chip.text = "  •  ".join(PackedStringArray(meta)).to_upper()
		chip.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		chip.add_theme_color_override("font_color", RunGraph.type_color(game.type))
		box.add_child(chip)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	box.add_child(facts)
	for row in cfg.get("facts", []):
		if row is Array and (row as Array).size() >= 2:
			facts.add_child(card_fact(String(row[0]), String(row[1])))
	# The kind in words, beside the box's marker (§19.8) — the card is what a player
	# opens to find out what a node MEANS, so it spells out what the mark abbreviates.
	var kind_row := card_fact("Kind", "%s  %s" % [
		RunGraph.kind_mark(GameState.node_kind(id)), RunGraph.kind_label(GameState.node_kind(id))])
	kind_row.tooltip_text = RunGraph.kind_tip(GameState.node_kind(id))
	(kind_row.get_child(1) as Label).add_theme_color_override("font_color",
		UITheme.kind_color(GameState.node_kind(id)))
	facts.add_child(kind_row)
	# The same number the box's ⛓ badge carries and the Atlas's card calls
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

	# The record you have IN this game — the same fact the box's ⚔ badge carries,
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
	row.add_theme_constant_override("separation", UITheme.GAP)
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	k.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(v)
	return row

static func card_heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", UITheme.GOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func card_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func card_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
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
	var segments: Array = []          # [[Vector2 from, Vector2 to, bool rift], ...]
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
			var rift: bool = seg.size() > 2 and bool(seg[2])
			var col: Color = UITheme.RIFT if rift else COL_ARROW
			var w: float = 2.5 * (arrow_size / 9.0)
			if rift:
				# Dashed, in the rift colour: a road, but not an influence.
				draw_dashed_line(a, tip - dir * arrow_size, col, w, arrow_size * 0.7, true)
			else:
				draw_line(a, tip - dir * arrow_size, col, w, true)
			# Arrowhead triangle at the child end.
			var perp: Vector2 = Vector2(-dir.y, dir.x) * (arrow_size * 0.5)
			var base: Vector2 = tip - dir * arrow_size
			draw_colored_polygon(
				PackedVector2Array([tip, base + perp, base - perp]), col)
