class_name NotificationToasts
extends Control

# Global transient-toast layer for the Notifications channel. Mounted once on
# a high CanvasLayer by Main. Each notification pops a small panel in a
# bottom-centre stack that fades in, holds, then fades out and frees — the stack
# is a VBoxContainer so removals re-flow automatically. Purely a display: the
# persistent record lives in Notifications.history (Backpack "History" tab).
#
# THE STACK IS AT THE FOOT OF THE SCREEN, and it used to be at the top-right.
# That corner is not empty on the screen this game spends its run on: the
# overworld's right column puts the battlefield's pressure bar — `AMULET PRESSURE`,
# the distance to the Amulet, the board's size and tier — at exactly the offset
# the stack anchored to, so every drop, every pickup and every arrival painted
# over the one row that says how much trouble the board is in. The loot toggle
# was moved out from under this same stack for the same reason (see the note in
# `Overworld2._build_ui`); the pressure bar had simply inherited the spot.
#
# The foot of the page is the least dense band in every phase — the choosing
# screen, the report screen and the board all end above it — and it is where a
# transient notice is conventionally looked for.
#
# ONE LANE, ONE SHAPE (the stream pass). The stack used to sit centred at the foot
# of the page, every toast as wide as its own sentence and rimmed all round in its
# colour — so a burst was a ragged pile of differently sized boxes landing on the
# middle of the page, across the bottom of BOTH columns, over the checklist's last
# rows and the board's bottom row at once. On a stream that read as clutter.
#
# Now it is a fixed-width column in the BOTTOM-LEFT corner: every toast the same
# width, text left-aligned, the colour carried by a stripe down the left edge
# instead of a full rim — a list of notices rather than a scatter of them. At most
# MAX_VISIBLE stand at once; the next one retires the oldest early, so a burst can
# never climb up the page. Newest at the bottom, nearest the edge, where the eye
# lands first. The corner is the left column's foot, which on every phase holds
# the least load-bearing line on the page (the "Last game:" recap, the escape
# hint, the haul screen's footer prompt), and never the board.
const HOLD_TIME := 2.6
const FADE_IN := 0.18
const FADE_OUT := 0.35
const TOAST_W := 400.0
const MAX_VISIBLE := 3
const STRIPE_W := 5
const PAD_X := 12
const PAD_Y := 6

# How far off the bottom edge the stack floats when nothing else is down there.
const BOTTOM_MARGIN := 16.0
const SIDE_MARGIN := 16.0

var _stack: VBoxContainer

# What is already standing at the foot of the screen, in pixels, that the stack
# has to sit above. The overworld's `🛒 Shop ↓` pointer is the one thing that
# claims this band, and it publishes its own height here while it is up — the
# same shape as `ModalScaffold.reserved_top`, which the pinned header uses to
# keep modals out from under itself.
var _bottom_inset: float = 0.0

func _ready() -> void:
	# Animate even while the tree is paused (e.g. backpack open / action
	# overlay) so a toast fired just before a pause still resolves.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Offsets as well as anchors: set_anchors_preset keeps the current offsets by
	# default, so a layer built in code (size 0 at that moment) would stay 0 wide and
	# park its top-right-anchored stack off the left edge of the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_stack = VBoxContainer.new()
	# Anchored to the bottom-left corner and growing UPWARD, so a new toast appears
	# against the foot of the screen and shoves the older ones up out of the way.
	# A FIXED column: every toast fills it, so they line up down both edges.
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stack.grow_horizontal = Control.GROW_DIRECTION_END
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_left = SIDE_MARGIN
	_stack.offset_right = SIDE_MARGIN + TOAST_W
	_stack.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	_apply_bottom_inset()

	Notifications.notified.connect(_on_notified)

# Lift the stack clear of whatever else is standing at the foot of the screen.
# Called by the overworld as its shop pointer comes and goes; 0 puts the stack
# back on the bottom margin.
func set_bottom_inset(px: float) -> void:
	var want: float = maxf(0.0, px)
	if is_equal_approx(want, _bottom_inset):
		return
	_bottom_inset = want
	_apply_bottom_inset()

# Take every standing toast down at once — for a new run, whose page should not
# open under notices about the run it replaced.
func clear() -> void:
	_by_key.clear()
	if _stack == null or not is_instance_valid(_stack):
		return
	for t in _stack.get_children():
		t.queue_free()

func _apply_bottom_inset() -> void:
	if _stack == null or not is_instance_valid(_stack):
		return
	# Both offsets, not just the bottom one: the stack grows upward from its own
	# bottom edge, so top and bottom have to move together or it anchors a
	# zero-height box at the wrong height and lays the toasts out from there.
	var y: float = -(BOTTOM_MARGIN + _bottom_inset)
	_stack.offset_top = y
	_stack.offset_bottom = y

# THE ART RIDES THE TOAST (docs/loot-passives.md §5). When a relic or a piece of
# the pack fires, the notice carries its picture, drawn to the left of the line at
# the size the eye reads before the words — "the penny went off" should be a thing
# the player sees, not a sentence they have to read to find out which penny.
const ICON_SIZE := 32

# Live toasts by source key, so a burst from one source stacks (see `_restack`).
var _by_key: Dictionary = {}

func _on_notified(text: String, color: Color, icon: Texture2D = null, key: String = "") -> void:
	if key != "" and _by_key.has(key) and is_instance_valid(_by_key[key]["toast"]):
		_restack(_by_key[key], text)
		return
	var toast := PanelContainer.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.size_flags_horizontal = Control.SIZE_FILL
	toast.modulate.a = 0.0

	# The colour is a STRIPE down the left edge with a hairline round the rest:
	# a column of differently rimmed boxes is four different shapes, and a column
	# of striped ones is one list.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.border_width_left = STRIPE_W
	sb.set_corner_radius_all(6)
	sb.content_margin_left = PAD_X
	sb.content_margin_right = PAD_X
	sb.content_margin_top = PAD_Y
	sb.content_margin_bottom = PAD_Y
	toast.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	toast.add_child(row)
	var pic: TextureRect = null
	if icon != null:
		pic = UITheme.crisp_tex(icon, ICON_SIZE)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pic)

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97))
	lbl.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The width the column gives it, less the picture beside it: a wrapping Label
	# reports a minimum of about one character otherwise.
	var room: float = TOAST_W - STRIPE_W - 1 - PAD_X * 2
	if pic != null:
		room -= ICON_SIZE + UITheme.GAP_WIDE
	lbl.custom_minimum_size = Vector2(room, 0)
	row.add_child(lbl)

	_stack.add_child(toast)
	_retire_overflow()

	var rec := {"toast": toast, "label": lbl, "text": text, "count": 1, "tween": null}
	if key != "":
		_by_key[key] = rec
		toast.tree_exiting.connect(func():
			if _by_key.get(key, {}).get("toast") == toast:
				_by_key.erase(key))
	rec["tween"] = _play(toast, true)

# NEVER MORE THAN MAX_VISIBLE. The oldest standing toast (the top of the column)
# is sent out now rather than at the end of its hold, so a burst of drops keeps
# the column a fixed height instead of climbing the page.
func _retire_overflow() -> void:
	var live: Array = []
	for t in _stack.get_children():
		if not bool((t as Node).get_meta(&"retiring", false)):
			live.append(t)
	var extra: int = live.size() - MAX_VISIBLE
	for i in range(maxi(0, extra)):
		var old: Control = live[i]
		old.set_meta(&"retiring", true)
		for rec in _by_key.values():
			if rec.get("toast") == old:
				var tw = rec.get("tween")
				if tw is Tween and (tw as Tween).is_valid():
					(tw as Tween).kill()
		var out := create_tween()
		out.tween_property(old, "modulate:a", 0.0, FADE_OUT * 0.5)
		out.tween_callback(old.queue_free)

# ONE SOURCE, ONE TOAST. A second notice from a source whose toast is still up
# rewrites that toast and holds it again rather than stacking a new one: the same
# line again reads "×2", a different line (a Rocket whose payout just grew)
# replaces the old one. A report where a Piggy Bank pays on eight hits is one toast
# saying "×8", not a column of eight that pushes everything else off the screen.
func _restack(rec: Dictionary, text: String) -> void:
	if text == String(rec["text"]):
		rec["count"] = int(rec["count"]) + 1
		(rec["label"] as Label).text = "%s  ×%d" % [text, int(rec["count"])]
	else:
		rec["text"] = text
		rec["count"] = 1
		(rec["label"] as Label).text = text
	var old = rec.get("tween")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	rec["tween"] = _play(rec["toast"], false)

func _play(toast: Control, fade_in: bool) -> Tween:
	# Bound to the toast, so a toast taken down early (`clear`) takes its tween
	# with it rather than leaving one to call queue_free on a freed node.
	var tw := create_tween().bind_node(toast)
	if fade_in:
		tw.tween_property(toast, "modulate:a", 1.0, FADE_IN)
	else:
		toast.modulate.a = 1.0
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(toast, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(toast.queue_free)
	return tw
