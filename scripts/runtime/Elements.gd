class_name Elements

# Damage-element registry — the code side of the `elements` sheet. Two jobs:
#
#   1. COLOUR — each element has a colour (the sheet's Color column). Action
#      combat tints a card's outward attack visual (smear / projectile / beam /
#      bounce) with it, so a Fire swing reads orange and a Poison flask green.
#
#   2. EFFECT ON ATTACK — when a damaging attack carrying an element lands, the
#      element applies a small on-hit side effect (the sheet's "Effect on Attack"
#      column). Implemented as a conditional 1-stack inflict so it never
#      double-dips with a card that already applies the same status.
#
# Authoring: a card's Element column -> CardData.element (lower-case). Nothing
# else to wire — damage paths in all three modes call on_hit_status() after a
# hit lands, and action delivery calls color() for the visual.
#
# Earth has no on-hit effect (sheet: N/A). Water/Electric are colour-only for
# now: their rules hinge on the Wet status, which the status system doesn't have
# yet — wire them here once Wet lands.

# Element -> visual colour (the sheet's Color words mapped to RGB).
const COLORS: Dictionary = {
	"blood": Color(0.886, 0.231, 0.231),     # Red
	"dark": Color(0.545, 0.231, 0.749),      # Purple
	"earth": Color(0.541, 0.353, 0.169),     # Brown
	"electric": Color(0.949, 0.824, 0.231),  # Yellow
	"fire": Color(0.941, 0.514, 0.169),      # Orange
	"poison": Color(0.498, 0.839, 0.353),    # Light Green
	"water": Color(0.231, 0.545, 0.839),     # Blue
}

static func _key(element) -> String:
	return String(element).strip_edges().to_lower()

# True when the element has a defined colour (i.e. it's a real, non-physical
# element). "physical" / "" / unknown -> false.
static func has_color(element) -> bool:
	return COLORS.has(_key(element))

# Element colour, or pure white when the element is none/physical/unknown so a
# colourless card keeps the default smear look.
static func color(element) -> Color:
	return COLORS.get(_key(element), Color(1, 1, 1, 1))

# The element's "Effect on Attack": the status (1 stack) to inflict on the
# struck target, or {} when the element has no effect or its condition isn't met.
#
#   { "status": StringName, "stacks": 1 }
#
# `target` gates the "if the target doesn't already have any X" rule
# (Blood/Dark/Fire). `card` gates Poison's "if the target isn't gaining Poison
# already" — read as "unless this attack already inflicts Poison" — so a card
# like Bouncing Flask that already poisons doesn't get a bonus stack stapled on.
static func on_hit_status(element, target, card) -> Dictionary:
	match _key(element):
		"blood":
			if _target_lacks(target, &"bleed"):
				return {"status": &"bleed", "stacks": 1}
		"dark":
			if _target_lacks(target, &"blind"):
				return {"status": &"blind", "stacks": 1}
		"fire":
			if _target_lacks(target, &"burn"):
				return {"status": &"burn", "stacks": 1}
		"poison":
			if not _card_inflicts(card, &"poison") and _target_lacks(target, &"poison"):
				return {"status": &"poison", "stacks": 1}
	return {}

static func _target_lacks(target, status: StringName) -> bool:
	if target == null or not target.has_method("get_status"):
		return false
	return target.get_status(status) <= 0

static func _card_inflicts(card, status: StringName) -> bool:
	if card == null or not ("effects" in card):
		return false
	for ef in card.effects:
		if String(ef.get("type", "")) == "status" and StringName(ef.get("status", "")) == status:
			return true
	return false
