class_name ChecklistFlow
extends Container

# THE CHECKLIST'S ROWS, IN ONE COLUMN OR SEVERAL (Overworld2._fit_checklist).
#
# A VBoxContainer in every way the checklist uses one — children top to bottom,
# each the full width, `separation` between them — until `columns` is raised.
# Then the same children, in the same order, flow down the first column and on
# into the next, split so the columns come out about equally tall.
#
# It exists because the checklist has no upper bound (a row per body standing)
# and the owner asked that the screen a game is played on never need scrolling
# (11 Nov 2026). Scaling the list down to fit is the other half of the answer and
# costs legibility; a second column costs nothing but width the short rows were
# not using, so the page tries it first.
#
# TWO THINGS ARE KEPT TOGETHER across a column break:
#   * a NESTED row (meta `nested`, set by ReportChecklist._add_row) stays under
#     the row it belongs to — the indent is the whole of what says whose it is;
#   * a HEADING (a bare Label: "When beating a game:") is never the last thing
#     in a column, since it is the title of what follows it.

const COLUMN_GAP := 10

var columns: int = 1:
	set(v):
		v = maxi(1, v)
		if v != columns:
			columns = v
			queue_sort()

var _min_h: float = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout()

func _get_minimum_size() -> Vector2:
	return Vector2(0, _min_h)

func _rows() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			out.append(c)
	return out

func column_width() -> float:
	return maxf(0.0, (size.x - COLUMN_GAP * (columns - 1)) / columns)

# Whether a column may END just before `rows[i]`.
func _can_break_before(rows: Array, i: int) -> bool:
	if i <= 0 or i >= rows.size():
		return false
	if bool((rows[i] as Control).get_meta(&"nested", false)):
		return false
	return not (rows[i - 1] is Label)

func _layout() -> void:
	var rows: Array = _rows()
	var sep: float = float(get_theme_constant(&"separation"))
	var cw: float = column_width()
	# A wrapped label's height follows its width, so every row is given the
	# column's width before it is measured.
	var heights: Array = []
	var total: float = 0.0
	for r in rows:
		var c := r as Control
		if not is_equal_approx(c.size.x, cw):
			c.size.x = cw
		var h: float = c.get_combined_minimum_size().y
		heights.append(h)
		total += h + sep
	var target: float = total / columns
	var col: int = 0
	var y: float = 0.0
	var tallest: float = 0.0
	for i in rows.size():
		var h: float = heights[i]
		# Move on when this row would overshoot the column's share by more than
		# it undershoots without it.
		if col < columns - 1 and y > 0.0 and _can_break_before(rows, i) \
				and y + h * 0.5 > target:
			col += 1
			y = 0.0
		fit_child_in_rect(rows[i], Rect2(col * (cw + COLUMN_GAP), y, cw, h))
		y += h + sep
		tallest = maxf(tallest, y - sep)
	if not is_equal_approx(tallest, _min_h):
		_min_h = tallest
		update_minimum_size()
