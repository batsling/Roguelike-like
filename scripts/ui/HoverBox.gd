class_name HoverBox
extends VBoxContainer

# A VBoxContainer that renders a HoverCard instead of Godot's plain tooltip —
# the container-shaped twin of HoverPanel, for the places where the thing being
# hovered is a COLUMN of controls rather than a panel.
#
# The pack's item token is the case that needs it: the whole column answers the
# hover (the tile, the Use button above it and the gap between them), so the
# card has to hang off the column and not off the art inside it.

func _make_custom_tooltip(_for_text: String) -> Object:
	return HoverCard.of(self)
