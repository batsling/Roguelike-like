class_name Elements

# Damage-element registry — the code side of the `elements` sheet. Two jobs:
#
#   1. COLOUR — each element has a colour (the sheet's Color column). Action
#      combat tints a card's outward attack visual (smear / projectile / beam /
#      bounce) with it, so a Fire swing reads orange and a Poison flask green.
#
#   2. EFFECT ON ATTACK — when a damaging attack carrying an element lands, the
#      element applies a small on-hit side effect (the sheet's "Effect on Attack"
#      column). Blood / Dark / Fire ALWAYS inflict their 1-stack status on a
#      connecting hit; only Poison keeps a condition (no double-dip with a card
#      that already poisons / a target already poisoned). Damaging Blood/Dark/
#      Fire cards surface the rider on their card text — generate_card_tres
#      appends "Inflict 1 Burn." etc. to the description.
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

# Element -> player-facing display name (Title Case).
const NAMES: Dictionary = {
	"blood": "Blood", "dark": "Dark", "earth": "Earth", "electric": "Electric",
	"fire": "Fire", "poison": "Poison", "water": "Water",
}

# Element -> its "Effect on Attack" blurb (the elements sheet). Shown in card
# tooltips so the player knows what an element does on a connecting hit.
const DESCRIPTIONS: Dictionary = {
	"blood": "Inflicts 1 Bleed on hit.",
	"dark": "Inflicts 1 Blind on hit.",
	"earth": "No on-hit effect.",
	"electric": "Electric damage to a Wet target also hits adjacent Wet targets.",
	"fire": "Inflicts 1 Burn on hit.",
	"poison": "Inflict 1 Poison unless the attack already applies Poison.",
	"water": "Inflict 1 Wet and remove all Burn from the target.",
}

static func _key(element) -> String:
	return String(element).strip_edges().to_lower()

# Title-case display name for an element, or "" when none/physical/unknown.
static func display_name(element) -> String:
	return String(NAMES.get(_key(element), ""))

# The element's on-hit blurb, or "" when it has none.
static func description(element) -> String:
	return String(DESCRIPTIONS.get(_key(element), ""))

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
# Blood / Dark / Fire are unconditional — every connecting hit stacks another
# point of Bleed / Blind / Burn (the card text carries the "Inflict 1 X."
# rider). Only Poison keeps its gates: `card` covers "unless this attack
# already inflicts Poison" (Bouncing Flask doesn't get a bonus stack stapled
# on) and `target` the "isn't gaining Poison already" half.
static func on_hit_status(element, target, card) -> Dictionary:
	match _key(element):
		"blood":
			return {"status": &"bleed", "stacks": 1}
		"dark":
			return {"status": &"blind", "stacks": 1}
		"fire":
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
