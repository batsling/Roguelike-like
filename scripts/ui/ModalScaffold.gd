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

# How many pixels down the top of the screen belong to something drawn OVER the
# modals: the run's pinned header bar (Overworld2.HEADER_LAYER), which carries
# Health, Gold, the road walked and the ☰ Menu, floats above every modal the run
# raises and is opaque.
#
# Anything centred on the screen has to be centred in what is LEFT, not in the
# screen — the game-choice popup grew past 700px on a tall route, was centred on
# the viewport, and had its title ("Atomic Owl") sliced off by the bar sitting on
# top of it. Modals that are their own full-screen page (the Atlas) read this too,
# so their own header row lands below the bar rather than under it, which is what
# put the Atlas's Close button out of reach.
#
# Set by whoever owns such a bar and cleared when it goes; 0 everywhere else, so
# the main menu's modals and the Collection are unaffected.
static var reserved_top: float = 0.0

# The screen minus the reserved strip: where a modal is allowed to be, and how
# big it may get. `basis` is any Control in the tree, used to reach the viewport.
static func free_rect(basis: Control) -> Rect2:
	var view: Vector2 = basis.get_viewport_rect().size if basis != null and basis.is_inside_tree() \
		else Vector2(1280, 720)
	var top: float = clampf(reserved_top, 0.0, maxf(0.0, view.y - 120.0))
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
	panel.offset_right = half.x
	# Centred in the band BELOW the reserved strip, not on the whole screen — and
	# never allowed to start above it, whatever height the panel ended up at. A
	# panel taller than the band overflows off the BOTTOM, where it can be
	# scrolled to, rather than under an opaque bar that eats its title.
	var area: float = panel.get_parent_area_size().y
	if area <= 0.0:
		area = panel.get_viewport_rect().size.y if panel.is_inside_tree() else 0.0
	var strip: float = clampf(reserved_top, 0.0, maxf(0.0, area - 120.0)) if area > 0.0 \
		else reserved_top
	var top: float = -half.y + strip * 0.5
	if area > 0.0:
		top = maxf(top, strip - area * 0.5)
	panel.offset_top = top
	panel.offset_bottom = top + panel.size.y
