class_name StatusMarker
extends Control

# Small top-right overlay on a deckbuilder status badge: a padlock for Permanent
# statuses, or a clock + remaining-turns number for Temporary ones. Drawn
# procedurally via DrawUtil so the iconography matches the action arena and the
# tactical grid (which draw the same markers immediate-mode).

var kind: String = ""   # "lock" | "clock"
var turns: int = 0

func setup(p_kind: String, p_turns: int = 0) -> void:
	kind = p_kind
	turns = p_turns
	custom_minimum_size = Vector2(13, 13)
	size = Vector2(13, 13)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s <= 0.0:
		s = 13.0
	if kind == "lock":
		DrawUtil.draw_status_lock(self, Vector2.ZERO, s)
	elif kind == "clock":
		DrawUtil.draw_status_clock(self, Vector2.ZERO, s)
		if turns > 0:
			# The turns-left count, centered on the clock face with an outline so
			# it stays legible over the hands.
			var font: Font = ThemeDB.fallback_font
			var txt := str(turns)
			var fsize := 8
			var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			var pos := Vector2(s * 0.5 - tw * 0.5, s * 0.5 + fsize * 0.42)
			draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color.BLACK)
			draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.92, 0.97, 1.0))
