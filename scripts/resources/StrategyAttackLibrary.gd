class_name StrategyAttackLibrary
extends Resource

# Central, editable definition of how each attack archetype behaves on the
# tactical (Strategy) battle grid. The Strategy sibling of ActionAttackLibrary:
# the per-card spreadsheet authoring stays terse (the archetype name + a size
# word in the `Attack` column → CardData.attack_shape / attack_params), while
# the grid feel — range in TILES, area footprint, whether the footprint rotates
# to face the cursor — is tuned in one place (data/strategy_attacks.tres).
#
# Reference it from anywhere via Data.strategy_attacks. BattleView / EnemyAI call
# `resolve(shape, params)` once per attack to turn the archetype + params into a
# numeric spec, then `footprint(spec, origin, aim, map, stops)` to get the exact
# tiles the attack covers (Mewgenics-style: directional patterns rotate around
# the attacker to face the aimed tile).
#
# === The vocabulary (mirrors the Action archetypes, measured in tiles) ===
#   poke      single tile straight ahead, in range          -> family "single"
#   swing     3-tile arc in front (arc=360 = ring)           -> family "front_arc"
#   smash     directional forward blast, size = depth         -> family "blast"
#   projectile line outward (spread = 3-wide, pierce = thru)  -> family "line"
#   beam      full-length line to the board edge, walls block  -> family "line"
#   nova      ring/disc centred on the attacker (self-AOE)     -> family "disc"
#   lob       disc dropped on an aimed tile in range           -> family "disc"
#   smite/homing/auto_aoe/bounce  auto-pick target(s)          -> family "auto"
#
# The bare size word (Short/Medium/Large/Full, or Small/Medium/Large for the
# area families) maps to a tile reach for the reach families and to a tile
# radius for the area families. The `auto` family resolves its targets via the
# existing immediate-resolve path in BattleView (any range), so it has no
# footprint here.

# --- Size word -> tiles -------------------------------------------------------
# Reach (poke straight-ahead / projectile-beam travel). Distances are Chebyshev
# (king-move) tiles, so diagonal aiming reads naturally.
@export var reach_tiles: Dictionary = {
	"short": 2, "medium": 3, "large": 5, "full": 99,
}
# AOE radius in tiles for the area families (smash depth / nova-lob disc).
@export var radius_tiles: Dictionary = {
	"small": 1, "medium": 2, "large": 3,
}
# How far a lob can be thrown before its disc is placed (aim range), separate
# from the disc radius the size word controls.
@export var lob_throw_tiles: int = 4

# Archetype -> family + defaults. `size` is the default bare-size word; `aim`
# is how the attack is targeted on the grid:
#   "tile" — the player aims a tile/direction within range (rotating preview)
#   "self" — centred on the attacker, no manual aim (nova)
#   "auto" — the engine auto-picks the target set (smite/homing/auto_aoe/bounce)
const ARCHETYPES: Dictionary = {
	"poke":       {"family": "single",    "size": "short", "aim": "tile"},
	"swing":      {"family": "front_arc", "size": "medium", "aim": "tile"},
	"smash":      {"family": "blast",     "size": "medium", "aim": "tile"},
	"projectile": {"family": "line",      "size": "medium", "aim": "tile"},
	# beam is a thin full-length line; the `sweep` subtype (Sweeping Beam) fans it
	# to the flanking tiles (spread, below) so it reads as one big sweeping attack
	# covering beam-level range.
	"beam":       {"family": "line",      "size": "full",   "aim": "tile",
		"pierce": true, "blocked_by_walls": true},
	"nova":       {"family": "disc",      "size": "small",  "aim": "self"},
	"lob":        {"family": "disc",      "size": "medium", "aim": "tile",
		"thrown": true},
	"smite":      {"family": "auto",      "size": "",       "aim": "auto",
		"target": "nearest"},
	"homing":     {"family": "auto",      "size": "medium", "aim": "auto",
		"target": "nearest"},
	"auto_aoe":   {"family": "auto",      "size": "small",  "aim": "auto",
		"target": "random"},
	"bounce":     {"family": "auto",      "size": "",       "aim": "auto",
		"target": "random"},
}

# The 8 king-move neighbour offsets (used for arc=360 rings and disc fills).
const RING8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

func _size_word(params: Dictionary, default_size: String) -> String:
	var s: String = String(params.get("size", "")).strip_edges().to_lower()
	return s if s != "" else default_size

func _lookup(table: Dictionary, word: String, fallback: int) -> int:
	return int(table[word]) if table.has(word) else fallback

# Turn an attack_shape + attack_params into a numeric, ready-to-resolve spec.
# Unknown shapes fall back to a medium swing so a typo never crashes combat.
func resolve(shape_name: StringName, params: Dictionary = {}) -> Dictionary:
	var shape: String = String(shape_name).strip_edges().to_lower()
	var base: Dictionary = ARCHETYPES.get(shape, ARCHETYPES["swing"])
	var p: Dictionary = params if params != null else {}
	var family: String = String(base["family"])
	var size_word: String = _size_word(p, String(base.get("size", "medium")))

	var spec: Dictionary = {
		"shape": shape,
		"family": family,
		"aim": String(base.get("aim", "tile")),
		"range_tiles": 1,
		"radius": 0,
		"rotates": false,
		"pierce": bool(p.get("pierce", base.get("pierce", false))),
		"spread": int(p.get("spread", 1)) > 1 or bool(base.get("spread", false)) or bool(p.get("sweep", false)),
		"arc360": int(p.get("arc", 0)) >= 360,
		"target_mode": String(p.get("target", base.get("target", "nearest"))).to_lower(),
		"blocked_by_walls": bool(base.get("blocked_by_walls", false)),
		# Explosive (Lil' Bomber): a line projectile that bursts into a disc where
		# it first hits. The footprint becomes the travelled line plus a blast disc
		# centred on the impact tile, so damage hits everything in the blast once.
		"explosive": bool(p.get("explosive", false)),
		"blast": 0,
	}
	if spec["explosive"]:
		spec["blast"] = _lookup(radius_tiles, size_word, radius_tiles["medium"])

	match family:
		"single":
			spec["range_tiles"] = _lookup(reach_tiles, size_word, reach_tiles["short"])
		"front_arc":
			# Swing is always a melee arc on the adjacent ring; size is cosmetic.
			spec["range_tiles"] = 1
			spec["rotates"] = not spec["arc360"]
		"blast":
			# Size sets the forward depth of the cluster; aim sets direction.
			spec["radius"] = _lookup(radius_tiles, size_word, radius_tiles["medium"])
			spec["range_tiles"] = spec["radius"]
			spec["rotates"] = true
			spec["blocked_by_walls"] = true
		"line":
			spec["radius"] = 0
			spec["rotates"] = true
			if shape == "beam":
				spec["range_tiles"] = _lookup(reach_tiles, "full", 99)
			else:
				spec["range_tiles"] = _lookup(reach_tiles, size_word, reach_tiles["medium"])
		"disc":
			spec["radius"] = _lookup(radius_tiles, size_word, radius_tiles["small"])
			if bool(base.get("thrown", false)):
				spec["range_tiles"] = lob_throw_tiles
			else:
				# nova: centred on the attacker.
				spec["range_tiles"] = 0
		_:  # auto
			spec["range_tiles"] = _lookup(reach_tiles, "full", 99)
	return spec

# Resolve straight from a CardData, applying the legacy fallback when the card
# carries no explicit attack_shape (mirrors the Action fallback): a ranged dmg
# effect implies a projectile, otherwise a melee swing.
func resolve_for_card(card) -> Dictionary:
	if card == null:
		return resolve(&"swing", {})
	if card.attack_shape != &"":
		return resolve(card.attack_shape, card.attack_params)
	var ranged: bool = false
	for e in card.effects:
		if str(e.get("type", "")) == "dmg" and str(e.get("damage_type", e.get("range_mode", ""))) == "ranged":
			ranged = true
			break
	if not ranged:
		# range_class may still hint ranged delivery for un-annotated cards.
		var rc: String = String(card.range_class).strip_edges().to_lower()
		ranged = rc in ["short", "medium", "large", "full"]
	return resolve(&"projectile" if ranged else &"swing", {})

# --- Footprint ----------------------------------------------------------------
# The exact tiles an attack covers, given its spec, the attacker's `origin`, the
# aimed tile `aim`, the BattleMap (for wall line-of-sight; may be null), and
# `stops` (a Dictionary of tile -> true for unit positions that halt a
# non-piercing line). Directional families orient toward `aim` and so rotate as
# the cursor moves. The `auto` family has no footprint (its targets are picked
# by the caller).
func footprint(spec: Dictionary, origin: Vector2i, aim: Vector2i, map = null, stops: Dictionary = {}) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	match String(spec.get("family", "single")):
		"single":
			_add(out, seen, aim, map)
		"front_arc":
			if bool(spec.get("arc360", false)):
				for off in RING8:
					_add(out, seen, origin + off, map)
			else:
				var d: Vector2i = _dir8(origin, aim)
				var f: Vector2i = d
				var l: Vector2i = Vector2i(-d.y, d.x)
				_add(out, seen, origin + f, map)
				_add(out, seen, origin + f + l, map)
				_add(out, seen, origin + f - l, map)
		"blast":
			var d2: Vector2i = _dir8(origin, aim)
			var f2: Vector2i = d2
			var l2: Vector2i = Vector2i(-d2.y, d2.x)
			var depth: int = maxi(1, int(spec.get("radius", 1)))
			for step in range(1, depth + 1):
				for lat in [-1, 0, 1]:
					_add(out, seen, origin + f2 * step + l2 * lat, map)
		"line":
			var d3: Vector2i = _dir8(origin, aim)
			var f3: Vector2i = d3
			var l3: Vector2i = Vector2i(-d3.y, d3.x)
			var reach: int = maxi(1, int(spec.get("range_tiles", 1)))
			var spread: bool = bool(spec.get("spread", false))
			var pierce: bool = bool(spec.get("pierce", false))
			var blocked: bool = bool(spec.get("blocked_by_walls", false))
			var explosive: bool = bool(spec.get("explosive", false))
			var blast: int = maxi(0, int(spec.get("blast", 0)))
			var impact: Vector2i = origin
			for step in range(1, reach + 1):
				var cell: Vector2i = origin + f3 * step
				if map != null and not map.in_bounds(cell):
					break
				if blocked and map != null and map.get_tile(cell.x, cell.y) == BattleMap.TileType.WALL:
					break
				_add(out, seen, cell, map)
				impact = cell
				if spread:
					_add(out, seen, cell + l3, map)
					_add(out, seen, cell - l3, map)
				if not pierce and stops.has(cell):
					break
			# Explosive: drop a blast disc on the tile the line reached (the first
			# unit hit, or the end of range) so the burst hits everyone around it.
			if explosive and blast > 0:
				for dy in range(-blast, blast + 1):
					for dx in range(-blast, blast + 1):
						if maxi(absi(dx), absi(dy)) > blast:
							continue
						_add(out, seen, impact + Vector2i(dx, dy), map)
		"disc":
			# Aim is the disc centre (nova passes aim == origin).
			var r: int = maxi(0, int(spec.get("radius", 0)))
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) > r:
						continue
					_add(out, seen, aim + Vector2i(dx, dy), map)
		_:
			pass  # auto: no footprint
	return out

# Tiles a tile-aimed attack may be aimed at: Chebyshev distance 1..range from the
# attacker, in bounds. Used by the grid view to gate clicks and draw the band.
func aimable_tiles(spec: Dictionary, origin: Vector2i, map = null) -> Dictionary:
	var out: Dictionary = {}
	if String(spec.get("aim", "tile")) != "tile":
		return out
	var r: int = maxi(1, int(spec.get("range_tiles", 1)))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cheb: int = maxi(absi(dx), absi(dy))
			if cheb == 0 or cheb > r:
				continue
			var p: Vector2i = origin + Vector2i(dx, dy)
			if map != null and not map.in_bounds(p):
				continue
			out[p] = true
	return out

func _add(out: Array, seen: Dictionary, pos: Vector2i, map) -> void:
	if seen.has(pos):
		return
	if map != null:
		if not map.in_bounds(pos):
			return
		if map.get_tile(pos.x, pos.y) == BattleMap.TileType.WALL:
			return
	seen[pos] = true
	out.append(pos)

static func _dir8(from_pos: Vector2i, to: Vector2i) -> Vector2i:
	var d: Vector2i = Vector2i(signi(to.x - from_pos.x), signi(to.y - from_pos.y))
	return d if d != Vector2i.ZERO else Vector2i(1, 0)
