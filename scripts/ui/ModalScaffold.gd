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
	panel.position = -panel.size * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	return panel
