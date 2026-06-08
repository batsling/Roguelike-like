class_name FloatingNumbers
extends RefCounted

# Tiny shared helper for the floating combat numbers every mode shows when an
# actor loses (or could later gain) HP. A short-lived Label drifts up and fades,
# then frees itself. `parent` is the CanvasItem the label is attached to and
# `local_pos` is a point in that parent's own coordinate space (each combat mode
# already has the actor's pixel/grid position in its own node, so it passes that
# directly — deckbuilder/strategy use a UI node, action uses arena coords).
#
# Red is the default (damage / HP loss). The amount is shown as a bare number.

const DAMAGE_COLOR := Color(1.0, 0.33, 0.33)

static func spawn(parent: CanvasItem, local_pos: Vector2, amount: int,
		color: Color = DAMAGE_COLOR) -> void:
	if parent == null or amount == 0 or not parent.is_inside_tree():
		return
	var lbl := Label.new()
	lbl.text = str(absi(amount))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 100
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", color)
	# Black outline keeps the number readable over any background / sprite.
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	# Small horizontal jitter so rapid hits don't stack into one blob.
	lbl.position = local_pos + Vector2(randf_range(-12.0, 12.0), -8.0)
	parent.add_child(lbl)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 46.0, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tw.finished.connect(lbl.queue_free)
