class_name RarityStyle
extends RefCounted

# Shared rarity palette + highlighted panel styling. Mirrors the legacy HTML
# item-display look: a dark panel tinted toward the rarity hue with a
# rarity-coloured border and a thicker left accent. Used by shops, reward /
# treasure selections and the collection so items read consistently everywhere.
#
# Index order matches ItemData.Rarity (COMMON, UNCOMMON, RARE, EPIC, LEGENDARY).

const COLORS := [
	Color(0.78, 0.78, 0.78),  # Common
	Color(0.30, 0.69, 0.31),  # Uncommon
	Color(0.61, 0.35, 0.71),  # Rare
	Color(1.00, 0.42, 0.00),  # Epic
	Color(1.00, 0.80, 0.30),  # Legendary
]

static func color(rarity: int) -> Color:
	return COLORS[clampi(rarity, 0, COLORS.size() - 1)]

# A highlighted panel stylebox for an item tile of the given rarity. The dark
# base is nudged toward the rarity hue so the whole tile reads as that rarity.
static func panel(rarity: int, content_margin: int = 10) -> StyleBoxFlat:
	var rc: Color = color(rarity)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.12, 0.16, 0.97).lerp(rc, 0.10)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_width_left = 4   # left accent, like the HTML item-display
	sb.border_color = rc
	sb.set_content_margin_all(content_margin)
	return sb
