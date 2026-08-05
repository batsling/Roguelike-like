class_name AtlasLayoutBuilder
extends RefCounted

# Builds an AtlasLayout for an ARBITRARY set of games, at runtime.
#
# `tools/bake_atlas.py` bakes the skies that ship with the game — the full
# catalog and the two Settings.game_filter variants — and those stay baked,
# because they never change between sessions. What it cannot bake is the sky for
# a filter the player assembles in the Collection: "Deckbuilder + never beaten +
# owned" is one of hundreds of combinations, and drawing it by dimming stars in
# the full sky leaves the survivors scattered across holes where their
# neighbours used to be. So the catalog Atlas rebuilds the layout for whatever
# survives its filters, here, and the result is a real map of that subgraph —
# its own capitals, its own constellations, packed from scratch.
#
# This is a port of the Python baker's layout half (build_graph / span_tree /
# cluster_layout / pack_around / pack_discs) and has to STAY one, so the two
# agree about the SHAPE of a sky: same capitals, same region assignment, same
# hop counts, same no-two-stars-overlap guarantee. It is NOT bit-identical to
# the baker and cannot be — `math.hypot` is not `sqrt(x*x + y*y)` in the last
# bits, the trig differs likewise, and the packer chooses positions with strict
# comparisons that a one-ulp difference can flip, rotating a whole subtree
# somewhere else. That divergence is invisible in practice: the unfiltered
# catalog is drawn from the BAKED sky (see AtlasView._layout_for), so nobody
# ever sees the two versions of the same graph side by side.
#
# It also carries a second, non-baked mode — `build_tree`, the radial timeline:
# one ring per release year, earliest at the centre, with the influence tree's
# branches running outward across them. The baker has no equivalent because it
# is purely a way of looking at the same graph.

# Clear space kept between any two stars. Mirrors bake_atlas.PAD.
const PAD := 3.0
# Directions tried when looking for a cluster's exit. Mirrors bake_atlas.GAP_SAMPLES.
const GAP_SAMPLES := 72
# Extra breathing room around a drifting component, so the unreachable stars read
# as separate from the constellations. Mirrors the baker's group "pad".
const DRIFT_PAD := 9.0

# The halo: how the games with NO links at all ring the constellation sky.
# Concentric bands, so the ring reads as scattered rather than marched.
const HALO_BANDS := 3
# Clear sky between the outermost constellation and the innermost halo star.
const HALO_GAP := 16.0
# How far a halo star may wander off its slot, as a fraction of the room it has.
const HALO_ANGLE_JITTER := 0.3
const HALO_RADIUS_JITTER := 0.35

# --- the subgraph being laid out ------------------------------------------
var _ids: PackedStringArray = PackedStringArray()
var _names: PackedStringArray = PackedStringArray()
var _adj: Array = []                  # index -> Array[int]
var _edges: PackedInt32Array = PackedInt32Array()
var _degree: PackedInt32Array = PackedInt32Array()
# Drawn radius per star, computed once. Everything below asks for it in inner
# loops, and it is a sqrt each time otherwise.
var _star_r: PackedFloat64Array = PackedFloat64Array()
var _xs: PackedFloat32Array = PackedFloat32Array()
var _ys: PackedFloat32Array = PackedFloat32Array()

# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------

# The constellation sky for `game_ids`, laid out around `num_capitals` hubs.
# `game_ids` is the subset to draw; edges to games outside it are dropped, so the
# graph really is the subgraph rather than the full one with stars hidden.
static func build(game_ids: PackedStringArray, num_capitals: int = 8,
		source_filter: String = "runtime") -> AtlasLayout:
	var b := AtlasLayoutBuilder.new()
	b._load(game_ids)
	if b._ids.is_empty():
		return null
	return b._constellations(maxi(1, mini(num_capitals, b._ids.size())), source_filter)

# The radial-timeline sky for `game_ids`: one ring per release year with the
# earliest at the centre, the influence tree rooted at `root_id` (Rogue, by
# convention — see AtlasView.TREE_ROOT) running its branches outward across
# them, and everything the tree cannot reach ringed around the outside.
static func build_tree(game_ids: PackedStringArray, root_id: StringName,
		source_filter: String = "runtime") -> AtlasLayout:
	var b := AtlasLayoutBuilder.new()
	b._load(game_ids)
	if b._ids.is_empty():
		return null
	return b._radial_tree(root_id, source_filter)

# ---------------------------------------------------------------------------
# The subgraph
# ---------------------------------------------------------------------------

# Read `game_ids` out of Data and build the undirected adjacency over just them.
# Ids are sorted so the layout is a pure function of the SET, not of the order
# the caller happened to collect it in — the same filter always gives the same
# sky.
func _load(game_ids: PackedStringArray) -> void:
	var wanted: Array = []
	for gid in game_ids:
		if Data.get_game(StringName(gid)) != null:
			wanted.append(String(gid))
	wanted.sort()
	_ids = PackedStringArray(wanted)

	var index := {}
	for i in range(_ids.size()):
		index[StringName(_ids[i])] = i
	_names.resize(_ids.size())
	_adj.resize(_ids.size())
	for i in range(_ids.size()):
		var g: GameData = Data.get_game(StringName(_ids[i]))
		_names[i] = g.display_name
		_adj[i] = []

	var seen := {}
	var flat: Array = []
	for i in range(_ids.size()):
		var g: GameData = Data.get_game(StringName(_ids[i]))
		for other in g.games_influenced:
			var j: int = int(index.get(StringName(other), -1))
			if j < 0 or j == i:
				continue
			var key: int = (mini(i, j) << 20) | maxi(i, j)
			if seen.has(key):
				continue
			seen[key] = true
			flat.append(mini(i, j))
			flat.append(maxi(i, j))
			(_adj[i] as Array).append(j)
			(_adj[j] as Array).append(i)
	_edges = PackedInt32Array(flat)

	_degree.resize(_ids.size())
	_star_r.resize(_ids.size())
	for i in range(_ids.size()):
		_degree[i] = (_adj[i] as Array).size()
		_star_r[i] = AtlasLayout.star_radius(_degree[i])

func _radius_of(i: int) -> float:
	return _star_r[i]

# Hop distance from `src` to every node, -1 where unreachable.
func _bfs(src: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(_ids.size())
	dist.fill(-1)
	dist[src] = 0
	var queue: Array = [src]
	var head: int = 0
	while head < queue.size():
		var v: int = queue[head]
		head += 1
		for w in _adj[v]:
			if dist[w] < 0:
				dist[w] = dist[v] + 1
				queue.append(w)
	return dist

# ---------------------------------------------------------------------------
# Disc packing — the port of bake_atlas.pack_around / pack_discs
# ---------------------------------------------------------------------------

# Pack discs around a fixed seed disc at the origin. Each disc lands at the
# valid position tangent to two already-placed discs that sits nearest the
# origin, so the cluster grows dense from the middle out instead of leaving a
# hollow ring. `seed_radius < 0` means "no seed" — the free-floating variant the
# baker calls pack_discs.
func _pack(radii: PackedFloat64Array, seed_radius: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(radii.size() * 2)
	var placed_x := PackedFloat64Array()
	var placed_y := PackedFloat64Array()
	var placed_r := PackedFloat64Array()
	if seed_radius >= 0.0:
		placed_x.append(0.0)
		placed_y.append(0.0)
		placed_r.append(seed_radius)

	var order: Array = range(radii.size())
	order.sort_custom(func(a, b):
		if radii[a] != radii[b]:
			return radii[a] > radii[b]
		return int(a) < int(b))

	for idx in order:
		var r: float = radii[idx]
		# Kept as loose floats rather than a Vector2: Vector2 is 32-bit, and
		# rounding the tangent points would drift this away from the baker.
		var px_out := 0.0
		var py_out := 0.0
		var found := false
		var placed_n: int = placed_r.size()
		if placed_n == 0:
			found = true
		elif placed_n == 1 and seed_radius < 0.0:
			px_out = placed_r[0] + r
			found = true
		else:
			var best_x := 0.0
			var best_y := 0.0
			var best_score := INF
			for i in range(placed_n):
				var ax: float = placed_x[i]
				var ay: float = placed_y[i]
				var ra: float = placed_r[i] + r
				for j in range(i + 1, placed_n):
					var rb: float = placed_r[j] + r
					var dx: float = placed_x[j] - ax
					var dy: float = placed_y[j] - ay
					var d2: float = dx * dx + dy * dy
					if d2 > (ra + rb) * (ra + rb) or d2 == 0.0:
						continue
					var d: float = sqrt(d2)
					if d < absf(ra - rb):
						continue
					var a: float = (ra * ra - rb * rb + d2) / (2.0 * d)
					var h2: float = ra * ra - a * a
					if h2 < 0.0:
						continue
					var h: float = sqrt(h2)
					var mx: float = ax + a * dx / d
					var my: float = ay + a * dy / d
					var hx: float = h * dy / d
					var hy: float = h * dx / d
					for sign in [1.0, -1.0]:
						var x: float = mx + sign * hx
						var y: float = my - sign * hy
						var score: float = x * x + y * y
						if score >= best_score:
							continue
						if not _fits(placed_x, placed_y, placed_r, x, y, r):
							continue
						best_score = score
						best_x = x
						best_y = y
			if best_score < INF:
				px_out = best_x
				py_out = best_y
				found = true
		if not found:
			# First child, or a genuinely blocked spot: walk out on a spiral.
			var spiral: PackedFloat64Array = _spiral_out(placed_x, placed_y, placed_r, r,
				(seed_radius if seed_radius >= 0.0 else placed_r[0]) + r,
				0.618 * TAU if seed_radius >= 0.0 else 0.5,
				r * (0.35 if seed_radius >= 0.0 else 0.12),
				12 if seed_radius >= 0.0 else 1)
			px_out = spiral[0]
			py_out = spiral[1]
		out[idx * 2] = px_out
		out[idx * 2 + 1] = py_out
		placed_x.append(px_out)
		placed_y.append(py_out)
		placed_r.append(r)
	return out

func _fits(px: PackedFloat64Array, py: PackedFloat64Array, pr: PackedFloat64Array,
		x: float, y: float, r: float) -> bool:
	for i in range(pr.size()):
		var dx: float = x - px[i]
		var dy: float = y - py[i]
		var rr: float = r + pr[i]
		if dx * dx + dy * dy < rr * rr - 1e-6:
			return false
	return true

# Last resort when no tangent position is free: step around a slowly widening
# spiral until something clears. `grow_every` is how many steps pass between
# widenings (the baker widens every 12 steps around a seed, every step when
# free-floating).
func _spiral_out(px: PackedFloat64Array, py: PackedFloat64Array, pr: PackedFloat64Array,
		r: float, start_radius: float, step: float, grow: float,
		grow_every: int) -> PackedFloat64Array:
	var rr: float = start_radius
	var t: int = 0
	while t < 4000:
		var a: float = t * step
		var x: float = cos(a) * rr
		var y: float = sin(a) * rr
		if _fits(px, py, pr, x, y, r):
			return PackedFloat64Array([x, y])
		t += 1
		if grow_every <= 1 or t % grow_every == 0:
			rr += grow
	return PackedFloat64Array([start_radius, 0.0])

# ---------------------------------------------------------------------------
# Cluster layout — the port of bake_atlas.best_gap / cluster_layout / span_tree
# ---------------------------------------------------------------------------

# Bearing with the most clear space — where the link to the parent exits.
# The cloud is passed as two parallel packed arrays (star index, and x/y pairs)
# rather than an array of triples: this runs once per node of every spanning
# tree, and an Array-of-Arrays cloud spends the whole budget allocating.
func _best_gap(nodes: PackedInt32Array, xy: PackedFloat64Array) -> float:
	var best_angle := 0.0
	var best_clear := -1.0
	var count: int = nodes.size()
	for k in range(GAP_SAMPLES):
		var a: float = float(k) / GAP_SAMPLES * TAU
		var ux: float = cos(a)
		var uy: float = sin(a)
		var clear := 1e9
		for p in range(count):
			var px: float = xy[p * 2]
			var py: float = xy[p * 2 + 1]
			var t: float = px * ux + py * uy
			if t <= 1e-9:
				continue
			var r: float = _star_r[nodes[p]] + PAD
			var qx: float = px - t * ux
			var qy: float = py - t * uy
			var d2: float = qx * qx + qy * qy
			if d2 >= r * r:
				continue
			clear = minf(clear, t - sqrt(r * r - d2))
		if clear > best_clear:
			best_clear = clear
			best_angle = a
	return best_angle

# Lay a spanning tree out bottom-up. Returns
# [enclosing_radius, node indices, x/y pairs] — the cloud relative to the root.
func _cluster_layout(root: int, children: Dictionary) -> Array:
	var order: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var v: int = stack.pop_back()
		order.append(v)
		for c in children.get(v, []):
			stack.append(c)

	var radius := {}
	var cloud_nodes := {}
	var cloud_xy := {}
	var gap := {}

	for oi in range(order.size() - 1, -1, -1):
		var v: int = order[oi]
		var kids: Array = children.get(v, [])
		var nodes := PackedInt32Array([v])
		var xy := PackedFloat64Array([0.0, 0.0])
		if not kids.is_empty():
			var radii := PackedFloat64Array()
			radii.resize(kids.size())
			for ki in range(kids.size()):
				radii[ki] = float(radius[kids[ki]]) + PAD * 0.5
			var slots: PackedFloat64Array = _pack(radii, _star_r[v] + PAD * 0.5)
			for ki in range(kids.size()):
				var c: int = kids[ki]
				var sx: float = slots[ki * 2]
				var sy: float = slots[ki * 2 + 1]
				# Turn the child's cluster so its emptiest bearing points back at v.
				var rot: float = (atan2(sy, sx) + PI) - float(gap[c])
				var ca: float = cos(rot)
				var sa: float = sin(rot)
				var cn: PackedInt32Array = cloud_nodes[c]
				var cxy: PackedFloat64Array = cloud_xy[c]
				var base: int = nodes.size()
				nodes.append_array(cn)
				xy.resize((base + cn.size()) * 2)
				for p in range(cn.size()):
					var px: float = cxy[p * 2]
					var py: float = cxy[p * 2 + 1]
					xy[(base + p) * 2] = sx + px * ca - py * sa
					xy[(base + p) * 2 + 1] = sy + px * sa + py * ca
				cloud_nodes.erase(c)
				cloud_xy.erase(c)
		var enclosing := 0.0
		for p in range(nodes.size()):
			var dx: float = xy[p * 2]
			var dy: float = xy[p * 2 + 1]
			enclosing = maxf(enclosing, sqrt(dx * dx + dy * dy) + _star_r[nodes[p]])
		radius[v] = enclosing
		cloud_nodes[v] = nodes
		cloud_xy[v] = xy
		gap[v] = _best_gap(nodes, xy)

	return [float(radius[root]), cloud_nodes[root], cloud_xy[root]]

# BFS spanning tree over one region: a node's parent is its best-connected
# neighbour one hop closer to the capital.
func _span_tree(root: int, hop: PackedInt32Array, owner: PackedInt32Array,
		owner_id: int) -> Dictionary:
	var children := {root: []}
	var queue: Array = [root]
	var head: int = 0
	var seen := {root: true}
	while head < queue.size():
		var v: int = queue[head]
		head += 1
		var nxt: Array = []
		for w in _adj[v]:
			if owner[w] == owner_id and not seen.has(w) and hop[w] == hop[v] + 1:
				nxt.append(w)
		nxt.sort_custom(func(a, b):
			if _degree[a] != _degree[b]:
				return _degree[a] > _degree[b]
			return int(a) < int(b))
		for w in nxt:
			seen[w] = true
			(children[v] as Array).append(w)
			children[w] = []
			queue.append(w)
	return children

# ---------------------------------------------------------------------------
# The constellation sky
# ---------------------------------------------------------------------------

func _constellations(num_capitals: int, source_filter: String) -> AtlasLayout:
	var n: int = _ids.size()

	var by_degree: Array = range(n)
	by_degree.sort_custom(func(a, b):
		if _degree[a] != _degree[b]:
			return _degree[a] > _degree[b]
		return _names[a].naturalnocasecmp_to(_names[b]) < 0)
	var capitals: PackedInt32Array = PackedInt32Array(by_degree.slice(0, num_capitals))

	var owner := PackedInt32Array()
	owner.resize(n)
	owner.fill(-1)
	var hop := PackedInt32Array()
	hop.resize(n)
	hop.fill(1 << 30)
	for ci in range(capitals.size()):
		var dist: PackedInt32Array = _bfs(capitals[ci])
		for i in range(n):
			var d: int = dist[i]
			if d < 0:
				continue
			if d < hop[i] or (d == hop[i] and owner[i] >= 0
					and _degree[capitals[ci]] > _degree[capitals[owner[i]]]):
				hop[i] = d
				owner[i] = ci

	var groups: Array = []
	for ci in range(capitals.size()):
		var children: Dictionary = _span_tree(capitals[ci], hop, owner, ci)
		var laid: Array = _cluster_layout(capitals[ci], children)
		groups.append({"radius": float(laid[0]), "nodes": laid[1], "xy": laid[2],
			"pad": 0.0})

	# Games with no links at all: not packed with the rest, ringed around it —
	# see _scatter_halo. (A degree-0 game that is itself a capital owns itself,
	# so `owner` is what separates the two cases.)
	var halo: Array = []
	for i in range(n):
		if _degree[i] == 0 and owner[i] < 0:
			halo.append(i)

	# Components no capital can reach but that DO have links — real little
	# constellations, packed as discs alongside the regions.
	var visited := {}
	for i in range(n):
		if owner[i] >= 0 or visited.has(i) or _degree[i] == 0:
			continue
		var comp: Array = []
		var queue: Array = [i]
		var head: int = 0
		visited[i] = true
		while head < queue.size():
			var v: int = queue[head]
			head += 1
			comp.append(v)
			for w in _adj[v]:
				if not visited.has(w) and owner[w] < 0:
					visited[w] = true
					queue.append(w)
		var root: int = comp[0]
		for v in comp:
			if _degree[v] > _degree[root] or (_degree[v] == _degree[root] and v < root):
				root = v
		var local_dist: PackedInt32Array = _bfs(root)
		var local_owner := PackedInt32Array()
		local_owner.resize(n)
		local_owner.fill(-1)
		var local_hop := PackedInt32Array()
		local_hop.resize(n)
		local_hop.fill(1 << 30)
		for v in comp:
			local_owner[v] = 0
			local_hop[v] = local_dist[v]
		var children2: Dictionary = _span_tree(root, local_hop, local_owner, 0)
		var laid2: Array = _cluster_layout(root, children2)
		groups.append({"radius": float(laid2[0]), "nodes": laid2[1], "xy": laid2[2],
			"pad": DRIFT_PAD})

	var disc_radii := PackedFloat64Array()
	disc_radii.resize(groups.size())
	for gi in range(groups.size()):
		disc_radii[gi] = float(groups[gi]["radius"]) + float(groups[gi]["pad"])
	var centres: PackedFloat64Array = _pack(disc_radii, -1.0)

	_xs.resize(n)
	_ys.resize(n)
	var region_cx := PackedFloat32Array()
	var region_cy := PackedFloat32Array()
	var region_radius := PackedFloat32Array()
	for gi in range(groups.size()):
		var cx: float = centres[gi * 2]
		var cy: float = centres[gi * 2 + 1]
		if gi < capitals.size():
			region_cx.append(cx)
			region_cy.append(cy)
			region_radius.append(float(groups[gi]["radius"]))
		var nodes: PackedInt32Array = groups[gi]["nodes"]
		var xy: PackedFloat64Array = groups[gi]["xy"]
		for p in range(nodes.size()):
			_xs[nodes[p]] = cx + xy[p * 2]
			_ys[nodes[p]] = cy + xy[p * 2 + 1]

	# Everything packed is placed; the halo rings all of it. Measured from the
	# packing's own MIDDLE rather than from the origin — the disc packer grows
	# outward from (0,0) but nothing makes the result symmetric about it, and a
	# halo centred on the origin comes out visibly off to one side of the sky it
	# is supposed to be surrounding.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for gi in range(groups.size()):
		var nodes2: PackedInt32Array = groups[gi]["nodes"]
		for p in range(nodes2.size()):
			var v: int = nodes2[p]
			lo = lo.min(Vector2(_xs[v] - _star_r[v], _ys[v] - _star_r[v]))
			hi = hi.max(Vector2(_xs[v] + _star_r[v], _ys[v] + _star_r[v]))
	var core := Vector2.ZERO
	var core_r: float = 0.0
	if lo.x <= hi.x:
		core = (lo + hi) * 0.5
		for gi in range(groups.size()):
			var nodes3: PackedInt32Array = groups[gi]["nodes"]
			for p in range(nodes3.size()):
				var v2: int = nodes3[p]
				core_r = maxf(core_r,
					core.distance_to(Vector2(_xs[v2], _ys[v2])) + _star_r[v2])
	_scatter_halo(halo, core, core_r)

	var layout := AtlasLayout.new()
	layout.source_filter = source_filter
	layout.game_ids = _ids
	layout.xs = _xs
	layout.ys = _ys
	layout.edges = _edges
	layout.capitals = capitals
	layout.region_cx = region_cx
	layout.region_cy = region_cy
	layout.region_radius = region_radius
	var out_region := PackedInt32Array()
	var out_hop := PackedInt32Array()
	out_region.resize(n)
	out_hop.resize(n)
	for i in range(n):
		out_region[i] = owner[i]
		out_hop[i] = -1 if owner[i] < 0 else hop[i]
	layout.region = out_region
	layout.hops = out_hop
	layout.bounds = _bounds()
	return layout

# Ring the unconnected games around everything else, scattered rather than
# marched round a perfect circle.
#
# A game with no links is not part of any constellation, and packing it as a
# one-star "component" among the real ones — which is what the disc packer did —
# sprinkles 83 meaningless dots through the middle of the chart and shoves the
# constellations apart to make room for them. Out here they read as what they
# are: the catalog's unjoined edge.
#
# Scattered, but provably never overlapping. Stars are dealt round-robin into
# HALO_BANDS concentric bands, so anything that ends up angularly adjacent is in
# a DIFFERENT band and is clear of its neighbour radially; within one band the
# slots are even and the jitter is capped at a fraction of a slot, so a band's
# own neighbours keep their gap as well. The halo's radius is then SOLVED from
# those two bounds rather than picked, which is what lets a 5-star halo and an
# 83-star one both come out clear.
func _scatter_halo(halo: Array, core: Vector2, core_r: float) -> void:
	if halo.is_empty():
		return
	halo.sort_custom(_older_first)
	# Every halo star has degree 0, so they are all exactly the same size and one
	# separation covers every pair.
	var sep: float = 2.0 * AtlasLayout.star_radius(0) + PAD
	var bands: int = mini(HALO_BANDS, halo.size())
	var jitter_r: float = sep * HALO_RADIUS_JITTER
	var band_gap: float = sep + 2.0 * jitter_r

	var slot := PackedFloat64Array()
	slot.resize(bands)
	var base: float = core_r + HALO_GAP + jitter_r
	for b in range(bands):
		var count: int = (halo.size() - b + bands - 1) / bands
		slot[b] = TAU / float(maxi(count, 1))
		if count < 2:
			continue
		# Two neighbours jittering toward each other is the worst gap this band
		# can produce; the chord across it still has to clear `sep`.
		var worst: float = slot[b] * (1.0 - 2.0 * HALO_ANGLE_JITTER)
		var need: float = sep / (2.0 * maxf(sin(worst * 0.5), 1e-4))
		base = maxf(base, need + jitter_r - float(b) * band_gap)

	for k in range(halo.size()):
		var i: int = halo[k]
		var b2: int = k % bands
		var seat: int = k / bands
		# Half a slot of phase per band, so the bands don't line up into spokes.
		var a: float = slot[b2] * (float(seat) + 0.5 * float(b2)
			+ (_jitter(i, 1) - 0.5) * 2.0 * HALO_ANGLE_JITTER)
		var r: float = base + float(b2) * band_gap \
			+ (_jitter(i, 2) - 0.5) * 2.0 * jitter_r
		_xs[i] = core.x + cos(a) * r
		_ys[i] = core.y + sin(a) * r

# A deterministic [0, 1) per star, so the halo looks scattered but is the SAME
# scatter every time — the sky has to be a pure function of the game set, and a
# random() here would reshuffle it on every rebuild. Integer-only and kept well
# inside 64 bits so tools/bake_atlas.py can compute it identically in Python.
func _jitter(i: int, salt: int) -> float:
	var h: int = (i * 374761393 + salt * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(h) / 4294967296.0

# ---------------------------------------------------------------------------
# The radial timeline — one ring per year, the tree's branches across them
# ---------------------------------------------------------------------------

# How far apart the year rings are pushed, per game on the busiest ring. The
# chart's scale is set by the year that has the most games in it: everything
# else is spaced against that, so a 40-game filter and the full 804 both come
# out legible without a magic size anywhere.
const YEAR_RING_SPREAD := 26.0
# Where the ring of unconnected games sits, as a multiple of the tree's own
# radius. They are not IN the tree — nothing influenced them and they influenced
# nothing — so they ring it rather than joining it.
const TREE_ORBIT := 1.14

# `root_id` anchors the middle. Everything the tree can reach hangs off it by
# real influence; every other CONNECTED component is attached to the root as a
# pseudo-child (it has to hang somewhere for the tree to be one tree); every
# game with no edges at all goes in the outer ring.
func _radial_tree(root_id: StringName, source_filter: String) -> AtlasLayout:
	var n: int = _ids.size()
	var root: int = -1
	for i in range(n):
		if StringName(_ids[i]) == root_id:
			root = i
			break
	# No Rogue in this filter: fall back to the oldest game that has any edge at
	# all, so the middle is still the start of something.
	if root < 0 or _degree[root] == 0:
		root = _oldest_connected()
	if root < 0:
		root = 0

	# The orbiting ring: everything with no connection inside this subgraph.
	var orbit: Array = []
	for i in range(n):
		if _degree[i] == 0:
			orbit.append(i)

	# The tree: BFS from the root over real edges, then every unreached component
	# joins as a pseudo-child of the root, oldest first.
	var children := {}
	for i in range(n):
		children[i] = []
	var depth := PackedInt32Array()
	depth.resize(n)
	depth.fill(-1)
	# Which branch each star hangs off. The view draws these links solid and
	# everything else faint — without that the tree is buried under its own
	# cross-links.
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	_grow_tree(root, children, depth, parent)
	var stragglers: Array = []
	for i in range(n):
		if depth[i] < 0 and _degree[i] > 0:
			stragglers.append(i)
	stragglers.sort_custom(_older_first)
	for s in stragglers:
		if depth[s] >= 0:
			continue                     # already picked up by an earlier component
		(children[root] as Array).append(s)
		depth[s] = 1
		parent[s] = root
		_grow_tree(s, children, depth, parent)

	# Children oldest-first, so a branch reads outward in time the way the whole
	# map does.
	for i in range(n):
		(children[i] as Array).sort_custom(_older_first)

	# Angular wedges proportional to leaf count. This is not the final bearing —
	# each ring re-spaces its own members below — but it is the ORDER they go
	# round in, which is what keeps a branch's descendants near each other
	# instead of scattered across the disk.
	var leaves := PackedInt32Array()
	leaves.resize(n)
	leaves.fill(0)
	_count_leaves(root, children, leaves)
	var angle := PackedFloat32Array()
	angle.resize(n)
	angle.fill(0.0)
	_assign_angles(root, children, leaves, 0.0, TAU, angle)

	# ONE RING PER YEAR. Radius is when a game came out, not how many steps it
	# sits from the root: "older games closest" is a claim about time, and depth
	# was only ever a proxy for it. A ring therefore holds everything released
	# that year, and the rings run outward chronologically with the earliest at
	# the middle.
	var years: Array = []
	var seen_year := {}
	for i in range(n):
		if depth[i] < 0:
			continue
		var y: int = _year_of(i)
		if not seen_year.has(y):
			seen_year[y] = true
			years.append(y)
	years.sort()
	var ring_of := PackedInt32Array()
	ring_of.resize(n)
	ring_of.fill(-1)
	var members: Array = []
	for _k in range(years.size()):
		members.append([])
	for i in range(n):
		if depth[i] < 0:
			continue
		var ri: int = years.bsearch(_year_of(i))
		ring_of[i] = ri
		(members[ri] as Array).append(i)

	var radius: PackedFloat64Array = _year_ring_radii(years, members)

	# Settle each ring at its members' BRANCH bearings, pushing apart only where
	# two would collide. Re-spacing a ring evenly instead would be simpler, but
	# every ring would then pick its own phase and a game would sit at an
	# unrelated bearing from its parent — branches would cross the disk rather
	# than run out along it, which is the whole thing the tree is for.
	for ri in range(members.size()):
		_settle_ring(members[ri], radius[ri], angle)

	_xs.resize(n)
	_ys.resize(n)
	for i in range(n):
		if depth[i] < 0:
			continue
		var r: float = radius[ring_of[i]]
		_xs[i] = cos(angle[i]) * r
		_ys[i] = sin(angle[i]) * r

	# The outer ring, evenly spaced and pushed far enough out that it clears both
	# the tree and itself. These are the games with no connection at all — they
	# have years like everything else, but nothing to be chronologically BETWEEN,
	# so they ring the whole thing rather than joining a year.
	if not orbit.is_empty():
		orbit.sort_custom(_older_first)
		var outermost: float = radius[radius.size() - 1] if radius.size() > 0 else 0.0
		var step2: float = TAU / float(orbit.size())
		var orbit_r: float = maxf(outermost * TREE_ORBIT,
			(_max_star_radius(orbit) + PAD) / maxf(sin(step2 * 0.5), 1e-4))
		for k in range(orbit.size()):
			var a: float = step2 * k
			_xs[orbit[k]] = cos(a) * orbit_r
			_ys[orbit[k]] = sin(a) * orbit_r

	var layout := AtlasLayout.new()
	layout.source_filter = source_filter
	layout.game_ids = _ids
	layout.xs = _xs
	layout.ys = _ys
	layout.edges = _edges
	# A tree has no constellations: every star belongs to the one sky, so there
	# are no capitals to name and no regions to filter by. AtlasView reads an
	# empty capitals array as "this sky has no regions" and drops those controls.
	layout.capitals = PackedInt32Array()
	layout.region_cx = PackedFloat32Array()
	layout.region_cy = PackedFloat32Array()
	layout.region_radius = PackedFloat32Array()
	var out_region := PackedInt32Array()
	out_region.resize(n)
	out_region.fill(-1)
	layout.region = out_region
	layout.hops = depth
	layout.parent = parent
	layout.bounds = _bounds()
	return layout

# Walk `from` outward over real edges, filling `children` / `depth` for anything
# not already placed. Used for the root's own tree and for each straggler
# component that hangs off it.
func _grow_tree(from: int, children: Dictionary, depth: PackedInt32Array,
		parent: PackedInt32Array) -> void:
	if depth[from] < 0:
		depth[from] = 0
	var queue: Array = [from]
	var head: int = 0
	while head < queue.size():
		var v: int = queue[head]
		head += 1
		for w in _adj[v]:
			if depth[w] >= 0:
				continue
			depth[w] = depth[v] + 1
			parent[w] = v
			(children[v] as Array).append(w)
			queue.append(w)

# Oldest first, ties broken by name, so the ordering never depends on load order.
func _older_first(a: int, b: int) -> bool:
	var ga: GameData = Data.get_game(StringName(_ids[a]))
	var gb: GameData = Data.get_game(StringName(_ids[b]))
	var ya: int = ga.year if ga != null else 0
	var yb: int = gb.year if gb != null else 0
	if ya != yb:
		return ya < yb
	return _names[a].naturalnocasecmp_to(_names[b]) < 0

# Leaves under each node, so a wide branch is given a proportionally wide wedge.
func _count_leaves(v: int, children: Dictionary, leaves: PackedInt32Array) -> int:
	var kids: Array = children.get(v, [])
	if kids.is_empty():
		leaves[v] = 1
		return 1
	var total: int = 0
	for c in kids:
		total += _count_leaves(c, children, leaves)
	leaves[v] = total
	return total

# Give `v` the middle of its wedge and split the rest between its children in
# proportion to how many leaves each carries.
func _assign_angles(v: int, children: Dictionary, leaves: PackedInt32Array,
		from_angle: float, to_angle: float, angle: PackedFloat32Array) -> void:
	angle[v] = (from_angle + to_angle) * 0.5
	var kids: Array = children.get(v, [])
	if kids.is_empty():
		return
	var span: float = to_angle - from_angle
	var total: float = maxf(float(leaves[v]), 1.0)
	var cursor: float = from_angle
	for c in kids:
		var share: float = span * float(leaves[c]) / total
		_assign_angles(c, children, leaves, cursor, cursor + share, angle)
		cursor += share

# Spread one ring's members so no two touch, moving them as little as possible
# from the bearing their branch put them at.
#
# Sorted by bearing, then walked once round pushing each star just clear of the
# one before it, and once more to close the wrap-around. `_year_ring_radii` has
# already guaranteed the ring is big enough to hold everything at even spacing,
# so the walk can always succeed — it just usually has to move far less than
# that, which is what keeps a branch pointing outward.
func _settle_ring(row: Array, r: float, angle: PackedFloat32Array) -> void:
	if row.size() < 2 or r <= 0.0:
		return
	row.sort_custom(func(a, b): return angle[a] < angle[b])
	var gap := PackedFloat64Array()
	gap.resize(row.size())
	for k in range(row.size()):
		var a: int = row[k]
		var b: int = row[(k + 1) % row.size()]
		# The angle a star of each size needs between their centres at this radius.
		gap[k] = (_star_r[a] + _star_r[b] + PAD) / r
	var total := 0.0
	for g in gap:
		total += g
	if total >= TAU:
		# Cannot honour every gap: fall back to even spacing, which the ring was
		# sized for. (Only reachable if the sizing floor ever changes.)
		var step: float = TAU / float(row.size())
		var base: float = angle[row[0]]
		for k in range(row.size()):
			angle[row[k]] = base + step * float(k)
		return
	# Forward pass: nothing may sit closer to its predecessor than gap allows.
	for k in range(1, row.size()):
		var want: float = angle[row[k - 1]] + gap[k - 1]
		if angle[row[k]] < want:
			angle[row[k]] = want
	# And the wrap: the last star must also clear the first, one turn on.
	var overshoot: float = (angle[row[-1]] + gap[row.size() - 1]) - (angle[row[0]] + TAU)
	if overshoot > 0.0:
		# Give the slack back evenly around the ring rather than to one star.
		var share: float = overshoot / float(row.size() - 1)
		for k in range(1, row.size()):
			angle[row[k]] -= share * float(k)

# Where each YEAR's ring sits, given the games on it.
#
# Two forces. Time wants the rings evenly spaced, so a decade-long gap in the
# catalog reads as a gap on the map — that is what makes the chart a timeline
# rather than an ordered list, and it matches the hand-drawn map's linear year
# axis. Legibility wants each ring big enough that its own members clear each
# other, and 2024 has fifty times the games of 1984. The answer is the larger of
# the two, ring by ring, so time sets the shape and the crowded years push out
# from it. Monotonic by construction: a ring is never inside the one before it.
func _year_ring_radii(years: Array, members: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(years.size())
	if years.is_empty():
		return out
	var first_year: int = int(years[0])
	var span: float = maxf(float(int(years[-1]) - first_year), 1.0)

	# The linear time axis, in the same units the packing works in. Scaled off the
	# busiest ring so the whole chart grows with the catalog instead of being
	# pinned to a magic number.
	var busiest: int = 1
	for row in members:
		busiest = maxi(busiest, (row as Array).size())
	var time_span: float = float(busiest) * YEAR_RING_SPREAD

	var previous := -INF
	for ri in range(years.size()):
		var row: Array = members[ri]
		var biggest := 0.0
		for i in row:
			biggest = maxf(biggest, _star_r[i])
		# Even spacing on a ring of n stars leaves a 2*pi/n gap; the chord across
		# that gap has to clear two stars and the pad between them.
		var needed := 0.0
		if row.size() > 1:
			var half: float = maxf(sin(PI / float(row.size())), 1e-4)
			needed = (2.0 * biggest + PAD) / (2.0 * half)
		var target: float = float(int(years[ri]) - first_year) / span * time_span
		var r: float = maxf(target, needed)
		# And never inside — or touching — the ring before it.
		if previous > -INF:
			r = maxf(r, previous + 2.0 * biggest + PAD)
		elif row.size() == 1:
			r = 0.0                        # a lone earliest game sits dead centre
		out[ri] = r
		previous = r
	return out

# The release year of star `i`, 0 when the catalog doesn't say.
func _year_of(i: int) -> int:
	var g: GameData = Data.get_game(StringName(_ids[i]))
	return g.year if g != null else 0

func _max_star_radius(indices: Array) -> float:
	var out := 0.0
	for i in indices:
		out = maxf(out, _radius_of(i))
	return out

# The oldest game that has at least one connection in this subgraph.
func _oldest_connected() -> int:
	var best: int = -1
	for i in range(_ids.size()):
		if _degree[i] <= 0:
			continue
		if best < 0 or _older_first(i, best):
			best = i
	return best

# ---------------------------------------------------------------------------

# Bounding box of every star CENTRE plus the baker's 12-unit pad. Deliberately
# ignores the star radii, exactly as bake_atlas.write_resource does, so a baked
# sky and a built one frame the same way.
func _bounds() -> Rect2:
	if _xs.is_empty():
		return Rect2()
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for i in range(_xs.size()):
		min_x = minf(min_x, _xs[i])
		min_y = minf(min_y, _ys[i])
		max_x = maxf(max_x, _xs[i])
		max_y = maxf(max_y, _ys[i])
	var pad := 12.0
	return Rect2(min_x - pad, min_y - pad,
		(max_x - min_x) + pad * 2.0, (max_y - min_y) + pad * 2.0)
