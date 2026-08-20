class_name UnitData
extends Resource

# Static definition of a UNIT — a body of the PLAYER's that stands on one cell of
# the battlefield (docs/games-first-redesign.md §17). Source-of-truth content
# lives in the `units2.0` sheet of tools/Roguelikes.xlsx and is generated into
# data/units2.0/*.tres by tools/generate_unit_tres.py.
#
# A unit is the counterpart to a tile effect (TileEffectData): the tile is something
# done TO the ground, the unit is something standing ON it. They layer — a unit
# sits on top of whatever tile effect is under it — which is why they are two
# resources rather than one with a flag, and what happens when a particular pair
# meets is authored in `interactions` rather than hard-coded.
#
# A unit does NOT block a body: an enemy walks into the cell and the unit reacts,
# which for the Landmine means going off. What it does instead is make that lane
# expensive, and the enemies' own routing reads it (GameLoop2._spawn_rows), so a
# mined board is one the stack walks AROUND rather than one it cannot cross.
#
# Units are a category with one member today. The schema is authored for the
# category rather than for the Landmine because the sheet is: `Type` is there so
# an Animate unit that takes its own turn can arrive without a migration.

@export var id: StringName
@export var display_name: String

# The sheet's Type column — "Inanimate" for something that only reacts (the
# Landmine), and reserved for the units that will act on their own. Nothing
# dispatches on it yet; it is carried so the sheet's own classification survives
# into the data rather than being re-derived later.
@export var unit_type: String = "Inanimate"

# The sheet's Description column, verbatim — what the keyword dropdown shows
# wherever an item or a scroll names this unit.
@export var description: String = ""

# How much damage it absorbs before it is gone. 1 for the Landmine: it is a
# one-shot, and going off spends the whole of it.
@export var health: int = 1

# WHAT IT DOES, as trigger name -> Array of effect dicts. Same vocabulary as
# TileEffectData.triggers, since a unit and a tile effect react to the same board:
#
#   enemy_enters      a body's footprint newly covered this cell.
#   enemy_turn_start  a body was already standing here when a turn began.
#
#   {"op": "detonate"}                     go off where you stand, as a bomb
#   {"op": "apply_status", "status": …, "value": …}
#
# `detonate` is a PROXY BOMB and that is the point of it: it spends none of the
# player's Bombs, but everything that modifies a bomb modifies this one —
# Brimstone widens the blast, Sticky stuns what survives it, Blood Bombs pays its
# Health, Hot Bombs leaves Fire behind. A Landmine is worth what the pack has
# made bombs worth.
@export var triggers: Dictionary = {}

# WHAT HAPPENS WHEN IT MEETS SOMETHING ELSE, as "<kind>:<id>" -> Array of outcome
# tokens, where <kind> is "tile" or "unit":
#
#   {"tile:fire": ["detonate_unit", "remove_tile"]}
#
#   detonate_unit  this unit goes off where it stands
#   remove_tile    the tile effect on the cell is cleared
#
# The mirror of the tile's own cell — see TileEffectData.interactions for why both sides
# author it.
@export var interactions: Dictionary = {}

# Art base name under res://images2.0/units/ (the sheet's Img column).
@export var file: String = ""
@export var image: Texture2D

# The effects one trigger fires, or [] when this unit does nothing on it.
func effects_for(trigger: StringName) -> Array:
	var got = triggers.get(String(trigger), [])
	return got if got is Array else []

func has_trigger(trigger: StringName) -> bool:
	return not effects_for(trigger).is_empty()

# The outcome tokens for meeting `kind`/`id`, or [] when the pair is inert.
func interaction_with(kind: StringName, other_id: StringName) -> Array:
	var got = interactions.get("%s:%s" % [kind, other_id], [])
	return got if got is Array else []

# THE ONE PLACE A UNIT'S WORDS ARE BUILT — the board's hover and the keyword
# dropdown an item or a scroll that names it carries both come here. `health_left`
# is the standing unit's own; -1 is the catalog reading.
func tooltip_for(health_left: int = -1) -> String:
	var lines: Array = ["%s — unit" % display_name]
	if description != "":
		lines.append(description)
	var hp: int = health_left if health_left >= 0 else health
	lines.append("Health %d." % hp)
	for pairing in interactions.keys():
		lines.append(interaction_line(String(pairing)))
	return "\n".join(lines)

# A unit is the PLAYER'S, so it reads in the steel blue the hero's own gear does
# rather than in a threat colour — the board's reds and oranges all mean "this is
# coming for you", and a Landmine is the opposite of that.
const ACCENT := Color(0.62, 0.78, 0.95)

# THE HOVER CARD for this unit on the board — the twin of TileEffectData.hover_card,
# so a square with something standing on it and a square with something done to it
# answer the mouse in the same shape. `health_left` is the standing unit's own.
func hover_card(health_left: int = -1) -> Dictionary:
	var hp: int = health_left if health_left >= 0 else health
	var lines: Array = []
	if description != "":
		lines.append(description)
	for pairing in interactions.keys():
		lines.append(interaction_line(String(pairing)))
	return {
		"title": display_name,
		"accent": ACCENT,
		"art": image,
		"subtitle": "Unit  ·  yours, standing on the ground",
		"pips": [{"text": "❤ %d" % hp, "good": true}],
		"lines": lines,
		"note": "Nothing is blocked by it — an enemy walks in and it reacts.",
	}

# One authored interaction, in words — the mirror of TileEffectData.interaction_line,
# written from the unit's end of the same pairing.
func interaction_line(pairing: String) -> String:
	var parts: PackedStringArray = pairing.split(":")
	var other: String = parts[1] if parts.size() > 1 else pairing
	var named: Resource = Data.get_tile(StringName(other)) if parts[0] == "tile" \
		else Data.get_unit(StringName(other))
	var other_name: String = named.display_name if named != null else other.capitalize()
	var outcomes: Array = interactions.get(pairing, [])
	var what: Array = []
	if outcomes.has("detonate_unit"):
		what.append("sets this off")
	if outcomes.has("remove_tile"):
		what.append("puts it out")
	if outcomes.has("remove_unit"):
		what.append("destroys this")
	return "Meeting %s %s." % [other_name, " and ".join(what)] if not what.is_empty() \
		else "Reacts with %s." % other_name

# Art base name, falling back to the de-spaced display name when `file` is unset.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
