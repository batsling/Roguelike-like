class_name HoverButton
extends Button

# A Button whose hover is a COMPACT BOX rather than Godot's stock tooltip.
#
# The stock tooltip never wraps: a Label sized to its text, so a two-sentence
# tooltip on the Escape button or a Bash chip came up as one line running most of
# the way across the screen. Godot has no setting for that and only calls
# `_make_custom_tooltip` on a Control whose own script defines it, so a button
# that wants a readable hover has to be one of these.
#
# With a HoverCard attached (`HoverCard.attach(btn, {...})`) it draws that card;
# otherwise it draws its plain `tooltip_text` in a small wrapped box
# (HoverCard.text_card). Either way it is still a Button in every other respect.

func _make_custom_tooltip(for_text: String) -> Object:
	return HoverCard.tip(self, for_text)
