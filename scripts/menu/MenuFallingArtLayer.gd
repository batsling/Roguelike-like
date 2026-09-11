class_name MenuFallingArtLayer
extends Control

# One texture-filter's worth of `MenuFallingArt`'s pieces, drawn in a single
# `_draw`.
#
# It exists because a texture filter belongs to the CANVAS ITEM, not to the draw
# call: `draw_texture_rect` samples with whatever `texture_filter` the node it is
# drawn on carries. The art here spans `AttackFly` at 19x10 and a game cover at
# 528x704, so one filter cannot serve both — nearest-neighbour turns a photo
# blocky and linear turns 19x10 pixel art to mush. So the parent sorts its pieces
# by `UITheme.is_pixel_art` and hands each half to one of these, one set NEAREST
# and one LINEAR.
#
# The two layers interleave in z rather than depth-sorting together, which is
# invisible here: everything is drawn under 0.62 alpha on a dark ground, so an
# overlap reads as two faint things crossing either way round.


# THE ARRAY IS THE PARENT'S, HELD BY REFERENCE, and so is every piece in it —
# `MenuFallingArt._redraw` refills the same two batches every frame rather than
# building fresh dictionaries to copy them into. That is safe because of WHEN the
# two run: the parent fills the batch in `_process` and asks for a redraw, and the
# redraw happens at the end of that same frame, before anything clears it again.
# A piece is drawn at `draw_alpha` — its own alpha after the bottom fade, which
# the parent writes on the way past.
var _pieces: Array = []

func set_pieces(pieces: Array) -> void:
	_pieces = pieces
	queue_redraw()

func _draw() -> void:
	for piece in _pieces:
		var tex: Texture2D = piece["tex"]
		if tex == null:
			continue
		var box: Vector2 = piece["box"]
		# Rotate about the piece's own centre: `draw_set_transform` puts the origin
		# at `pos`, so the rect is drawn back by half its size from there.
		draw_set_transform(piece["pos"], piece["rot"], Vector2.ONE)
		draw_texture_rect(tex, Rect2(-box * 0.5, box), false,
			Color(1.0, 1.0, 1.0, piece.get("draw_alpha", piece["alpha"])))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
