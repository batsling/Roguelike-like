extends Control

# One arrow between two stops on a drawn route — the end-of-run screen's history
# strip and the page's road across the top both use it. `unreached` marks the
# stretch a lost run never covered.
#
# No class_name on purpose: it is reached through RunHistoryScreen.RouteArrow and
# Overworld2.ROUTE_ARROW (both preloads), so nothing needs the global name and a
# new one would need an editor rescan before the suite could see it.

var unreached: bool = false

# THE HEAD IS SIZED AGAINST THE ARROW, not fixed. It used to be a flat 7x10
# triangle at a flat 4px inset, which is fine at the end-of-run screen's 24px
# and falls apart at the header strip's 15: the pads ate 8 of the 15, the head
# ate the remaining 7, and what drew was a squat triangle with no shaft behind
# it at all — an arrow that had eaten itself. The head now takes at most half
# the span, so there is always a line for it to sit on the end of.
const HEAD_LEN := 6.0
const HEAD_HALF := 4.0
const PAD := 2.0

func _draw() -> void:
	# Half-pixel offset so a 2px line lands ON the pixel grid rather than
	# straddling two rows of it — the difference between a crisp rule and a
	# soft grey smear at these sizes.
	var y: float = floorf(size.y * 0.5) + 0.5
	var col: Color = UITheme.TEXT_FAINT if unreached else UITheme.ACCENT
	var x0: float = PAD
	var x1: float = maxf(size.x - PAD, x0 + 1.0)
	var span: float = x1 - x0
	var head: float = minf(HEAD_LEN, span * 0.5)
	# Scaled down with the head when the arrow is very short, so it stays a
	# triangle rather than becoming a wide flat wedge.
	var half: float = minf(HEAD_HALF, head * 0.75)
	var tip := Vector2(x1, y)
	var base: float = x1 - head
	if unreached:
		# The stretch a lost run never covered, so it reads as a gap.
		draw_dashed_line(Vector2(x0, y), Vector2(base, y), col, 2.0, 5.0, true)
	else:
		draw_line(Vector2(x0, y), Vector2(base, y), col, 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		tip, Vector2(base, y - half), Vector2(base, y + half)]), col)
