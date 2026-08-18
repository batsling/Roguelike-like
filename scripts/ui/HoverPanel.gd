class_name HoverPanel
extends PanelContainer

# A PanelContainer that renders a HoverCard instead of Godot's plain tooltip.
#
# `_make_custom_tooltip` is only called on a Control whose OWN script defines it,
# so a code-built panel that wants a card has to be one of these rather than a
# bare PanelContainer. That is the whole of the class: fill it with
# `HoverCard.attach(panel, {...})` and it draws the card.
#
# `HoverBox` is the same thing for a bare Control (a container, a footprint, a
# column of tiles) — see HoverBox.gd.

func _make_custom_tooltip(_for_text: String) -> Object:
	return HoverCard.of(self)
