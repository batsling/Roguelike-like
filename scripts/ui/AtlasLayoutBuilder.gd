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
# It also carries a second, non-baked mode — `build_tree`, the radial tree in a
# disk (§Atlas modes) — which the baker has no equivalent for because it is
# purely a way of looking at the same graph.

# Clear space kept between any two stars. Mirrors bake_atlas.PAD.
const PAD := 3.0
# Directions tried when looking for a cluster's exit. Mirrors bake_atlas.GAP_SAMPLES.
const GAP_SAMPLES := 72
# Extra breathing room around a drifting component, so the unreachable stars read
# as separate from the constellations. Mirrors the baker's group "pad".
const DRIFT_PAD := 9.0

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

# The radial-tree sky for `game_ids`: one tree rooted at `root_id` (Rogue, by
# convention — see AtlasView.TREE_ROOT), drawn in a disk, with everything the
# tree cannot reach ringed around the outside.
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

	# Components no capital can reach — the drifting stars.
	var visited := {}
	for i in range(n):
		if owner[i] >= 0 or visited.has(i):
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

# ---------------------------------------------------------------------------
# The radial tree in a disk
# ---------------------------------------------------------------------------

# How hard the rings crowd toward the rim. 0 would space them evenly; higher
# values push the outer generations together the way a Poincare projection does,
# which is what makes the deep end of a 700-game tree readable at all.
const TREE_CROWD := 1.25
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

	# Angular wedges proportional to leaf count: every leaf gets its own slot, so
	# no two stars in the tree can ever land on the same bearing.
	var leaves := PackedInt32Array()
	leaves.resize(n)
	leaves.fill(0)
	_count_leaves(root, children, leaves)
	var angle := PackedFloat32Array()
	angle.resize(n)
	angle.fill(0.0)
	var max_depth: int = 0
	for i in range(n):
		max_depth = maxi(max_depth, depth[i])
	_assign_angles(root, children, leaves, 0.0, TAU, angle)

	# Ring radii: crowd toward the rim, then scale the whole disk up until the
	# tightest ring clears its stars. Sizing from the data rather than from a
	# constant is what keeps a 40-game filter and the full catalog both readable.
	var ring := PackedFloat32Array()
	ring.resize(maxi(max_depth + 1, 1))
	for d in range(ring.size()):
		ring[d] = _ring_fraction(d, max_depth)
	var scale: float = _tree_scale(depth, angle, ring, leaves)

	_xs.resize(n)
	_ys.resize(n)
	for i in range(n):
		if depth[i] < 0:
			continue
		var r: float = ring[depth[i]] * scale
		_xs[i] = cos(angle[i]) * r
		_ys[i] = sin(angle[i]) * r

	# The outer ring, evenly spaced and pushed far enough out that it clears both
	# the tree and itself.
	if not orbit.is_empty():
		orbit.sort_custom(_older_first)
		var step: float = TAU / float(orbit.size())
		var orbit_r: float = maxf(scale * TREE_ORBIT,
			(_max_star_radius(orbit) + PAD) / maxf(sin(step * 0.5), 1e-4))
		for k in range(orbit.size()):
			var a: float = step * k
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

# Where ring `d` sits, as a fraction of the disk. tanh crowds the outer rings
# toward the rim — the look the projection is named for — while keeping ring 0
# at the centre and the last ring just inside the edge.
func _ring_fraction(d: int, max_depth: int) -> float:
	if max_depth <= 0:
		return 0.0
	var t: float = float(d) / float(max_depth)
	return tanh(TREE_CROWD * t) / tanh(TREE_CROWD)

# How big the disk has to be for the tightest pair of neighbours on any ring to
# clear each other. Walks the stars ring by ring in angle order and asks what
# radius that ring would need; the answer is the largest such demand.
func _tree_scale(depth: PackedInt32Array, angle: PackedFloat32Array,
		ring: PackedFloat32Array, _leaves: PackedInt32Array) -> float:
	var by_ring := {}
	for i in range(_ids.size()):
		if depth[i] < 0:
			continue
		if not by_ring.has(depth[i]):
			by_ring[depth[i]] = []
		(by_ring[depth[i]] as Array).append(i)
	var scale := 1.0
	for d in by_ring.keys():
		if float(ring[d]) <= 1e-4:
			continue
		var members: Array = by_ring[d]
		members.sort_custom(func(a, b): return angle[a] < angle[b])
		for k in range(members.size()):
			var a: int = members[k]
			var b: int = members[(k + 1) % members.size()]
			if a == b:
				continue
			var gap: float = absf(angle[b] - angle[a])
			if k == members.size() - 1:
				gap = TAU - gap
			gap = minf(gap, TAU - gap) if members.size() > 2 else gap
			var need: float = _radius_of(a) + _radius_of(b) + PAD
			# chord = 2 r sin(gap/2)  ->  r = need / (2 sin(gap/2))
			var half: float = maxf(sin(absf(gap) * 0.5), 1e-4)
			scale = maxf(scale, need / (2.0 * half * float(ring[d])))
	# And enough room between consecutive rings for the stars themselves.
	var biggest := 0.0
	for i in range(_ids.size()):
		biggest = maxf(biggest, _radius_of(i))
	for d in range(1, ring.size()):
		var delta: float = float(ring[d]) - float(ring[d - 1])
		if delta > 1e-5:
			scale = maxf(scale, (2.0 * biggest + PAD) / delta)
	return scale

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
