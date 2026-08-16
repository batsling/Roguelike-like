class_name ModalScaffold
extends RefCounted

# Shared builder for the full-screen modal overlays used across the deckbuilder
# (card pickers, pile views, etc.). Every one of those modals layered the same
# three nodes by hand: a dimmed backdrop, a full-rect click-blocking button,
# and a centered styled PanelContainer. This collapses that boilerplate into
# one place so the look stays consistent and the style lives in a single spot.
#
# The three nodes are added to `parent` in back-to-front order (backdrop,
# blocker, panel) and the panel is returned for the caller to fill. If
# `dismiss` is a valid Callable it is wired to the blocker's `pressed` signal
# (click-outside-to-close); pass an empty Callable for modals that must force a
# choice and therefore only swallow the click.

const PANEL_BG := Color(0.10, 0.08, 0.12, 0.98)
const BACKDROP_COLOR := Color(0, 0, 0, 0.72)
const DEFAULT_SIZE := Vector2(900, 560)

# --- the band at the top of the screen a modal must not open under ----------
#
# The run's header — Health, Gold, the road walked, the title and the menu — is
# pinned across the top of the screen on a CanvasLayer ABOVE every modal the run
# raises (Overworld2.HEADER_LAYER). It is opaque, deliberately, so it is readable
# over an event's dimmed backdrop; the cost is that anything centred on the full
# screen has its first rows painted over. Every modal that grew past about 620px
# tall lost its title, and a couple lost the first line of what they were asking.
#
# So the screen a modal centres in is not the window: it is the window minus this
# band. Overworld2 publishes the bar's real height here as the bar is laid out
# (_fit_page_under_header) and clears it when the screen goes, so a modal opened
# from the main menu — where there is no bar — still centres on the whole window.
#
# Static because a modal is built by a dozen unrelated classes, several of them
# on their own CanvasLayer with no path back to the screen that raised them; a
# reserved strip of the viewport is a fact about the WINDOW, not about any one of
# them, and every one of them has to obey it.
static var reserved_top: float = 0.0

static func reserve_top(px: float) -> void:
	reserved_top = maxf(0.0, px)

static func clear_reserved_top() -> void:
	reserved_top = 0.0

# The rectangle a modal is allowed to occupy: the viewport, less the reserved
# band. Callers size their panels against `size.y` so a modal that fills the
# screen fills what is left of it rather than what is behind the bar.
static func free_rect(node: Control) -> Rect2:
	var view: Vector2 = node.get_viewport_rect().size if node != null and node.is_inside_tree() \
		else Vector2(1280, 720)
	var top: float = minf(reserved_top, maxf(0.0, view.y - 120.0))
	return Rect2(Vector2(0.0, top), Vector2(view.x, view.y - top))

static func build_panel(parent: Control, accent: Color, dismiss: Callable = Callable(), panel_size: Vector2 = DEFAULT_SIZE) -> PanelContainer:
	# Most modals mount on a CanvasLayer, which a theme does not travel down —
	# so the shared one is put on the modal root here rather than in each of them
	# (UITheme.dress). Without it a modal's buttons, inputs and scrollbars are
	# Godot's stock light-grey against this palette.
	UITheme.dress(parent)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = BACKDROP_COLOR
	parent.add_child(backdrop)

	var blocker := Button.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.flat = true
	blocker.focus_mode = Control.FOCUS_NONE
	if dismiss.is_valid():
		blocker.pressed.connect(dismiss)
	parent.add_child(blocker)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)
	# Centred WHENEVER IT CHANGES SHAPE, not once at build time. A modal handed a
	# width and a height of 0 is asking to be as tall as whatever it turns out to
	# hold — the item drop, the boss notice, an event — and centring that empty
	# shell put its TOP at the middle of the screen, so everything it then grew
	# hung below: the "you found a relic" card opened against the bottom of the
	# page with its art off it.
	#
	# BOTH signals. `resized` catches the panel growing into its content;
	# `minimum_size_changed` catches the content settling afterwards — a label that
	# has finally wrapped asks for a fraction of the height it asked for while it
	# was still one long line, and nothing else would ever tell the panel it may
	# give that height back.
	var recentre := Callable(ModalScaffold, "centre").bind(panel)
	panel.resized.connect(recentre)
	panel.minimum_size_changed.connect(recentre)
	centre(panel)

	return panel


# Put `panel` in the middle of its parent, at the size its contents ask for.
#
# Anchors AND offsets, because on a centre-anchored Control `position` is stored
# as an offset from anchor x parent_size — and a modal's parent is frequently a
# Control inside a CanvasLayer that has not been given its size yet, where
# `position = -size * 0.5` measures from the top-left corner and lands the panel
# half off the screen. Offsets are absolute, so they land the same however the
# parent is sized.
static func centre(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	# ALWAYS back down to the minimum, whether or not the panel was given a fixed
	# size. A Control on a non-container parent is grown to its content's minimum
	# by Godot and never shrunk back, and a modal's content reports a minimum that
	# is enormous for the FIRST frame — before its labels have wrapped and before
	# a ladder or a chart has been zoomed to fit. That transient became permanent:
	# the game-choice popup's content asked for 3832px on frame 0 of a 720px
	# screen, dropped back to 664 on frame 1, and the panel stayed 3832 tall — so
	# it was centred with its buttons two thousand pixels below the bottom of the
	# window and nothing on screen could be clicked.
	#
	# A fixed size is safe here because it was written to `custom_minimum_size`,
	# which is part of what `get_combined_minimum_size` returns: the panel cannot
	# shrink below what its caller asked for. It can still be larger when its
	# content genuinely needs the room.
	panel.size = panel.get_combined_minimum_size()
	var half: Vector2 = panel.size * 0.5
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -half.x
	panel.offset_top = -half.y
	panel.offset_right = half.x
	panel.offset_bottom = half.y
	# …and then down, out from under the run's header (see reserved_top). The
	# offsets are measured from the CENTRE of the viewport, so the shift is half
	# the reserved band — that recentres the panel in what is left of the screen —
	# and it is clamped so a panel taller than the free space is pushed exactly
	# clear of the bar rather than further down than it needs to go.
	var shift: float = _centre_shift(panel)
	panel.offset_top += shift
	panel.offset_bottom += shift


# How far DOWN a centred panel has to move to clear the reserved band, given how
# tall it turned out to be. 0 when nothing is reserved.
static func _centre_shift(panel: Control) -> float:
	if reserved_top <= 0.0 or panel == null or not panel.is_inside_tree():
		return 0.0
	var free := free_rect(panel)
	# Where the top edge lands if the panel is centred in the free band, and where
	# it lands if it is centred in the whole window. The difference is the shift.
	var centred_in_free: float = free.position.y + (free.size.y - panel.size.y) * 0.5
	var centred_in_view: float = (panel.get_viewport_rect().size.y - panel.size.y) * 0.5
	# Never above the band: a panel taller than the free space centres OFF the top
	# of it, and clamping here is what keeps its first rows out from under the bar.
	return maxf(free.position.y, centred_in_free) - centred_in_view
