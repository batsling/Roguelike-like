class_name RayAim
extends RefCounted

# THE RAY (docs/loot-passives.md §12.1) — the Aim a weapon or a wand takes when
# the sheet says `ray`, after Ball x Pit's ball.
#
# A ray leaves YOU, from the hero's spot on the left of the board, and travels in
# a straight line THROUGH the square the player clicked: the click only says which
# way. It does not stop at that square. It carries on until it meets something:
#
#   an ENEMY   the enemy is struck. With a bounce left the ray mirrors off the face
#              of the square it hit and travels on; with none it stops there.
#   a WALL     the top, the bottom or the back edge of the board. With a bounce
#              left it mirrors off it; with none it stops on the last square it
#              crossed.
#   YOUR SIDE  a ray that comes back out past the left edge has gone home, and
#              ends — the hero is not a wall.
#
# A bounce is a ball's: crossing a vertical edge (a side of a square, the back
# wall) flips the ray left-right, crossing a horizontal one flips it up-down.
# Through a corner exactly, the vertical edge is met first, and the horizontal one
# a moment later.
#
# WHAT IT HITS is every enemy it struck, each ONCE however often it comes back to
# it — `hits`, in the order the ray reached them. The piece's effect lands on all
# of them ("if it hits 2 enemies it does the effect to both"), and a ray that
# struck nobody lands on the square where it stopped, so a wand of Fire fired at
# an empty board still sets that square alight.
#
# Board units: column c spans x in [c, c+1), row r spans y in [r, r+1); the board
# is x in [1, cols+1), y in [0, rows). The hero stands in the column left of it.
#
# NO STATE LIVES HERE: a trace is a picture of the board as it stands, which is
# what lets the board preview the exact path a click would take.

# Where the ray leaves from: the middle of the hero's column, beside the board.
static func origin() -> Vector2:
	return Vector2(0.5, GameLoop2.grid_rows() / 2.0)

# THE PATH a ray aimed at `target` takes on the board as it stands, with
# `bounces` bounces. Returns
#   points  the line, in board units: the origin, each bounce, where it stopped
#   cells   every board square it crossed, in order
#   hits    [{instance, cell}] each enemy struck, once, in the order it was reached
#   end     the square it stopped on (OFF_FIELD when it left past your side)
#   bounced how many bounces it spent
static func trace(target: Vector2i, bounces: int, occ = null) -> Dictionary:
	var out := {"points": [], "cells": [], "hits": [], "end": GameLoop2.OFF_FIELD,
		"bounced": 0}
	var cols: int = GameLoop2.grid_cols()
	var rows: int = GameLoop2.grid_rows()
	if not GameLoop2._on_board(target.x, target.y):
		return out
	var taken: Dictionary = occ if occ is Dictionary else GameLoop2.occupancy()
	var pos: Vector2 = origin()
	var dir: Vector2 = (Vector2(target) + Vector2(0.5, 0.5) - pos).normalized()
	(out["points"] as Array).append(pos)
	# The square the ray is in: the hero's column, in the row it leaves along.
	var cell := Vector2i(0, clampi(int(floor(pos.y + signf(dir.y) * 0.001)), 0, rows - 1))
	var left: int = maxi(0, bounces)
	var seen: Dictionary = {}
	# A ray with B bounces can cross the board at most B + 1 times, and each crossing
	# is at most cols + rows squares; the cap is a guard, never the stop.
	var guard: int = (left + 2) * (cols + rows + 2) * 2
	while guard > 0:
		guard -= 1
		var sx: int = 1 if dir.x > 0.0 else -1
		var sy: int = 1 if dir.y > 0.0 else -1
		var tx: float = INF
		var ty: float = INF
		if absf(dir.x) > 0.000001:
			tx = ((cell.x + (1 if sx > 0 else 0)) - pos.x) / dir.x
		if absf(dir.y) > 0.000001:
			ty = ((cell.y + (1 if sy > 0 else 0)) - pos.y) / dir.y
		var across_x: bool = tx <= ty
		var t: float = maxf(0.0, tx if across_x else ty)
		var next: Vector2i = cell + (Vector2i(sx, 0) if across_x else Vector2i(0, sy))
		var at: Vector2 = pos + dir * t
		# Home: back out past the left edge of the board.
		if across_x and sx < 0 and next.x < 1:
			(out["points"] as Array).append(at)
			return out
		var wall: bool = next.y < 0 or next.y >= rows or next.x > cols
		var inst: int = int(taken.get(next, 0)) if not wall else 0
		if wall or inst > 0:
			if inst > 0 and not seen.has(inst):
				seen[inst] = true
				(out["hits"] as Array).append({"instance": inst, "cell": next})
			(out["points"] as Array).append(at)
			if left <= 0:
				out["end"] = next if inst > 0 else (cell if cell.x >= 1 else GameLoop2.OFF_FIELD)
				return out
			left -= 1
			out["bounced"] = int(out["bounced"]) + 1
			dir = Vector2(-dir.x, dir.y) if across_x else Vector2(dir.x, -dir.y)
			pos = at
			continue
		pos = at
		cell = next
		if cell.x >= 1:
			(out["cells"] as Array).append(cell)
	return out

# WHERE THE RAY LANDS: the square of each enemy it struck, or — when it struck
# nobody — the square it stopped on. Empty only for a ray that went home without
# touching anything, or never left.
static func impacts(path: Dictionary) -> Array:
	var out: Array = []
	for h in path.get("hits", []):
		out.append({"instance": int(h["instance"]), "cell": h["cell"]})
	if out.is_empty():
		var end: Vector2i = path.get("end", GameLoop2.OFF_FIELD)
		if GameLoop2._on_board(end.x, end.y):
			out.append({"instance": 0, "cell": end})
	return out

# The square an impact should be resolved at NOW: an earlier impact on the same
# zap may have moved its enemy (a teleport, a polymorph's new footprint), so a
# struck body is followed to where it stands. A body that is gone answers its old
# square, which then holds nobody.
static func live_cell(impact: Dictionary) -> Vector2i:
	var cell: Vector2i = impact.get("cell", GameLoop2.OFF_FIELD)
	var inst: int = int(impact.get("instance", 0))
	if inst <= 0:
		return cell
	var entry: Dictionary = GameLoop2.entry_for(inst)
	if entry.is_empty():
		return cell
	var cells: Array = GameLoop2.entry_cells(entry)
	if cells.is_empty() or cells.has(cell):
		return cell
	return cells[0]

# How a ray's reach reads on a hover: "in a line from you", "…, bouncing once".
static func words(bounces: int) -> String:
	match bounces:
		0:
			return "in a line from you"
		1:
			return "in a line from you, bouncing once"
	return "in a line from you, bouncing %d times" % bounces
