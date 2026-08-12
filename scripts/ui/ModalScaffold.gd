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
	# The 0 is remembered, because such a panel also has to be allowed to SHRINK.
	# A Control on a non-container parent only ever grows to its minimum size,
	# never back, and a label reports an enormous minimum until it has wrapped —
	# which is exactly the frame the first resize lands on. Without this the drop
	# modal was correctly centred and five times too tall.
	panel.set_meta(FIT_CONTENT, panel_size.y <= 0.0)
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


const FIT_CONTENT := "scaffold_fits_content"


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
	if bool(panel.get_meta(FIT_CONTENT, false)):
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
