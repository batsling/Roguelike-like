class_name TileEffectData
extends Resource

# Static definition of a TILE EFFECT — something that sits on ONE CELL of the
# battlefield and acts on whatever stands in it (docs/games-first-redesign.md
# §17). Source-of-truth content lives in the `tiles2.0` sheet of
# tools/Roguelikes.xlsx and is generated into data/tiles2.0/*.tres by
# tools/generate_tile_tres.py.
#
# A tile effect is the third thing that can be on the board, after a body and the
# empty ground under it. It is NOT a status: a status rides a body and goes where
# the body goes, while a tile effect stays where it was put and bites whoever
# walks into it. That is the whole distinction, and it is what makes Fire a way to
# threaten ground the player cannot reach rather than a body they have to aim at.
#
# It layers UNDER a unit (UnitData): a unit stands on a tile effect, and the two
# are separate sheets and separate resources precisely so that they can. What
# happens when a particular pair meets is authored in `interactions` — Fire and a
# Landmine annihilate each other — rather than hard-coded anywhere.

@export var id: StringName
@export var display_name: String

# The sheet's Description column: the author's one-line wording, shown verbatim in
# the keyword dropdown wherever an item or a scroll names this tile. The engine
# never parses it — what it runs on is `triggers` — but a drift between the two is
# a content bug worth being able to see.
@export var description: String = ""

# HOW LONG IT BURNS, in GAMES (the sheet's Decay column, "3 Games"), and 0 for a
# tile effect that never goes out on its own. Games rather than turns: how many
# turns a game buys is read off the distance to the Amulet (§7.4), so a tile
# authored in turns would be worth three times as much out in the wilds as it is
# on the Amulet's doorstep — the same content, strongest where it is needed least.
# Ticked once per game RESOLVED, beaten or not (GameLoop2.beat_game).
@export var decay_games: int = 0
# The Decay column verbatim, for the dropdown — the prose the player reads, beside
# the number the engine counts down.
@export var decay_text: String = ""

# WHAT IT DOES, as trigger name -> Array of effect dicts:
#
#   enemy_enters      a body's footprint newly covered this cell — it stepped in,
#                     spawned onto it, was pushed into it, or the board grew and
#                     reseated it there.
#   enemy_turn_start  a body was ALREADY standing here when an enemy turn began.
#                     The pair is what stops parking on a fire tile being free:
#                     walking in costs a stack, and so does staying.
#
# Each effect is a Dictionary with an "op" plus op-specific keys:
#   {"op": "apply_status", "status": "burn", "value": 1}
#   {"op": "detonate"}                     (units; see UnitData)
@export var triggers: Dictionary = {}

# WHAT HAPPENS WHEN IT MEETS SOMETHING ELSE, as "<kind>:<id>" -> Array of outcome
# tokens, where <kind> is "unit" or "tile":
#
#   {"unit:landmine": ["detonate_unit", "remove_tile"]}
#
#   detonate_unit  the unit on the cell goes off where it stands
#   remove_tile    this tile effect is cleared
#
# BOTH SIDES of a pairing author the same outcome (Fire names the Landmine and the
# Landmine names Fire), because Fire meeting a mine and a mine meeting Fire are
# one event and the player will look it up from whichever of the two they are
# holding. The runtime unions the two lists, so an interaction authored on one
# side only still resolves.
@export var interactions: Dictionary = {}

# Art base name under res://images2.0/tiles/ (the sheet's Img column).
@export var file: String = ""
# Loaded eagerly — there is a handful of tile effects, unlike the 854 game covers
# that forced GameData's lazy path.
@export var image: Texture2D

# The effects one trigger fires, or [] when this tile does nothing on it.
func effects_for(trigger: StringName) -> Array:
	var got = triggers.get(String(trigger), [])
	return got if got is Array else []

# Does this tile act on `trigger` at all? Cheaper than building the array for the
# common case of a cell that has nothing to say about a turn beginning.
func has_trigger(trigger: StringName) -> bool:
	return not effects_for(trigger).is_empty()

# The outcome tokens for meeting `kind`/`id`, or [] when the pair is inert.
func interaction_with(kind: StringName, other_id: StringName) -> Array:
	var got = interactions.get("%s:%s" % [kind, other_id], [])
	return got if got is Array else []

# How long a freshly-applied tile lasts, in games. Separate from `decay_games` so
# a caller reads intent rather than a field that also means "never".
func starting_life() -> int:
	return maxi(0, decay_games)

# THE ONE PLACE A TILE EFFECT'S WORDS ARE BUILT — the board's hover, the keyword
# dropdown an item or a scroll that names it carries, and anything else that
# describes one all come here, so they cannot disagree about what Fire does. Pass
# `games_left` for a tile actually standing on the board and it says how much of
# it is left; leave it at -1 for the catalog reading, which describes the tile
# rather than any particular instance of it.
func tooltip_for(games_left: int = -1) -> String:
	var lines: Array = ["%s — tile effect" % display_name]
	if description != "":
		lines.append(description)
	if games_left >= 0:
		lines.append("Burns out in %d more %s." % [
			games_left, "game" if games_left == 1 else "games"])
	elif decay_games > 0:
		lines.append("Lasts %d %s." % [
			decay_games, "game" if decay_games == 1 else "games"])
	else:
		lines.append("Stays until something clears it.")
	for pairing in interactions.keys():
		lines.append(interaction_line(String(pairing)))
	return "\n".join(lines)

# One authored interaction, in words. Kept here rather than in the two UI scripts
# that show it because the pairing is a rule, and a rule the player reads should
# be quoted from the content rather than paraphrased twice.
func interaction_line(pairing: String) -> String:
	var parts: PackedStringArray = pairing.split(":")
	var other: String = parts[1] if parts.size() > 1 else pairing
	var named: Resource = Data.get_unit(StringName(other)) if parts[0] == "unit" \
		else Data.get_tile(StringName(other))
	var other_name: String = named.display_name if named != null else other.capitalize()
	var outcomes: Array = interactions.get(pairing, [])
	var what: Array = []
	if outcomes.has("detonate_unit"):
		what.append("sets it off")
	if outcomes.has("remove_tile"):
		what.append("puts this out")
	if outcomes.has("remove_unit"):
		what.append("destroys it")
	return "Meeting %s %s." % [other_name, " and ".join(what)] if not what.is_empty() \
		else "Reacts with %s." % other_name

# Art base name, falling back to the de-spaced display name when `file` is unset —
# the same convention every other 2.0 resource uses.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
