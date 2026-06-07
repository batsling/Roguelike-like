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
