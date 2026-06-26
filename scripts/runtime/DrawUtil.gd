class_name DrawUtil
extends RefCounted

# Small immediate-mode drawing helpers shared by the action arena and the
# tactical battle grid.

# Draws `tex` as a circular token centered at `center` with `radius` on `ci`'s
# canvas. The texture is centered-square-cropped (aspect preserved, no
# distortion) and masked into a circle via a textured polygon fan, so a
# centered character icon shows in full with only the empty corners trimmed.
# `modulate` tints/fades the token (used for the action-mode i-frame flash).
static func draw_circular_texture(ci: CanvasItem, center: Vector2, radius: float,
		tex: Texture2D, modulate: Color = Color.WHITE, segments: int = 36) -> void:
	if tex == null or radius <= 0.0:
		return
	var tw: float = float(tex.get_width())
	var th: float = float(tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return
	# Largest centered square of the source, expressed in normalized UV space,
	# so the circle samples the middle of the image without stretching it.
	var side: float = minf(tw, th)
	var uspan: float = side / tw
	var vspan: float = side / th
	var uv_center := Vector2(0.5, 0.5)
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		var dir := Vector2(cos(a), sin(a))
		points.append(center + dir * radius)
		uvs.append(uv_center + Vector2(dir.x * uspan * 0.5, dir.y * vspan * 0.5))
	ci.draw_colored_polygon(points, modulate, uvs, tex)

# ---------------------------------------------------------------------------
# Status addon markers (Permanent / Temporary), drawn procedurally so they need
# no art asset and read at any small size. `tl` is the marker's top-left; `s` its
# box size in px. Shared by every combat renderer (action arena, tactical grid,
# and the deckbuilder badge overlay) so the iconography is identical everywhere.
# ---------------------------------------------------------------------------

# A tiny gold padlock: a shackle arc over a rounded body with a keyhole notch.
# Marks Permanent statuses ("this won't wear off").
static func draw_status_lock(ci: CanvasItem, tl: Vector2, s: float) -> void:
	var body_top: float = tl.y + s * 0.42
	var body := Rect2(tl.x, body_top, s, s - (body_top - tl.y))
	var gold := Color(1.0, 0.84, 0.32)
	var dark := Color(0.12, 0.10, 0.05)
	var shackle_c := Vector2(tl.x + s * 0.5, body_top)
	var r: float = s * 0.28
	ci.draw_arc(shackle_c, r, PI, TAU, 10, dark, s * 0.20)
	ci.draw_arc(shackle_c, r, PI, TAU, 10, gold, s * 0.11)
	ci.draw_rect(body, dark, true)
	ci.draw_rect(body.grow(-maxf(1.0, s * 0.12)), gold, true)
	ci.draw_rect(Rect2(body.position.x + body.size.x * 0.42,
		body.position.y + body.size.y * 0.3, maxf(1.0, s * 0.16), body.size.y * 0.45), dark, true)

# A tiny clock face (outline circle + two hands) on a dark disc. Marks Temporary
# statuses; the remaining-turns number is drawn separately by the caller (it owns
# the font). `tl` is the top-left of an s×s box; the clock fills it.
static func draw_status_clock(ci: CanvasItem, tl: Vector2, s: float) -> void:
	var c := tl + Vector2(s * 0.5, s * 0.5)
	var r: float = s * 0.46
	var cyan := Color(0.55, 0.85, 1.0)
	var dark := Color(0.10, 0.12, 0.16)
	ci.draw_circle(c, r, dark)
	ci.draw_arc(c, r, 0.0, TAU, 16, cyan, maxf(1.0, s * 0.10))
	# Hands: minute pointing up, hour pointing right.
	ci.draw_line(c, c + Vector2(0, -r * 0.62), cyan, maxf(1.0, s * 0.10))
	ci.draw_line(c, c + Vector2(r * 0.5, 0), cyan, maxf(1.0, s * 0.10))
