class_name EventData2
extends Resource

# An EVENT (docs/event-sheet-authoring.md) — the payoff for walking into a corner
# of the map. Roughly 40% of the graph's games are leaves, so visiting one is a
# round trip: a game there, a game back, for one game's reward. An event fires
# AFTER the game at such a node is beaten, on top of the normal drop, and that is
# what makes the detour a choice rather than a mistake.
#
# Source of truth is the `events2.0` sheet of tools/Roguelikes.xlsx (one row per
# event, choices in numbered column groups), generated into data/events2.0/*.tres
# by tools/generate_event2_tres.py.
#
# NOT `EventData` / data/events — that is the combat-era d20 event system this
# replaces (§12).

@export var id: StringName
@export var display_name: String
# The real game this is lifted from. Flavour credit, and the target when
# `where` is "game".
@export var source_game: String = ""

# --- when and where it may appear ------------------------------------------

# Tier ladder gate: empty = every tier, else lowercase "low"/"medium"/"high"/
# "insane", the same vocabulary enemies2.0 gates on.
@export var tier_tags: PackedStringArray = PackedStringArray()

# Placement. Blank is the ordinary case and means "anywhere" — an event fires
# after every game the run plays, so this answers no question today. It stays
# wired ("dead_end" for a leaf, "game" for its own source_game) for the
# per-location work; nothing authored sets it.
@export var where: String = ""

# The state gate: a condition on the RUN that must hold before this can appear at
# all, as {"stat": "hp", "op": "<=", "value": 70, "percent": true} — or empty for
# "always eligible". Distinct from tier (the ladder) and where (the map): this one
# gates on the player.
@export var requirement: Dictionary = {}

# "after" (default — fires once the game at the node is beaten, so it reads as an
# extra reward) or "before" (fires on arrival, so it can hand you a goal for the
# game you are about to play).
@export var trigger: String = "after"

# Which bag the event is drawn from. EventSystem rolls the rarity ladder on
# arrival and then draws from that rung's unseen events; see roll_for_arrival.
@export var rarity: String = "Common"
# Art base name under res://images2.0/events/.
@export var file: String = ""

# --- what it says ----------------------------------------------------------

@export var prompt: String = ""

# WHAT THE EVENT IS ALREADY DOING WHEN IT OPENS, before a button is pressed —
# `{"type": "offer_loot", "kind": "potion", "value": 3}` or empty. Today's one
# use is the Potion Lab (§15): a room with three potions on the bench, drawn as
# the real drop table — the pieces, the player's own 3x3, the bin — inside the
# event's body, so taking one is the drag it is everywhere else and the event's
# `Leave` is what walks out on the rest.
#
# It is not a choice's `Effect` because it is not a choice: nothing is pressed to
# make it happen, and a "Take" button in front of a table you can already see is
# a click that answers a question nobody asked. It is a sibling of `prompt` —
# what the event puts in front of you before it asks anything.
@export var opens_with: Dictionary = {}
# The two endings of a goal this event hands out. They cannot live on a choice's
# `results` because an add_goal event finishes on the CHECKLIST, games after the
# modal closed. Event-level because they are the event's voice rather than the
# option's — the Battleworn Dummy congratulates you in the same words whichever
# setting you chose. "Met" means the condition happened, which on a curse is the
# bad outcome; the sign lives in the effects, not in these names.
@export var goal_met: String = ""
@export var goal_missed: String = ""

# The two endings of a `chance` gamble, event-level for the same reason the two
# above are: they are the event's voice, not the button's. Scrap Ooze is the
# proof — [Reach Inside] and [Deeper] are two rows on the sheet and one hand in
# the ooze, and Slay the Spire prints the same success and failure text for
# both. A gamble's outcome depends on the ROLL, so a choice's own `results` cannot
# hold it; when a choice rolls, whichever of these is non-empty replaces it.
@export var chance_won: String = ""
@export var chance_lost: String = ""

# --- the choices -----------------------------------------------------------

# In display order. Each is a Dictionary:
#   id            StringName-ish slug of the label
#   text          the button label
#   repeat        "end" (default) | "again" | "stay"
#   repeat_max    for "again xN"; 0 = unlimited
#   results       the prose LADDER: one rung per press, the last rung standing
#                 for every press after it. [] is legal (the modal then prints
#                 only the mechanical line), and so is a blank rung mid-ladder.
#                 A one-rung ladder is the ordinary case — a choice pressed once
#                 that says one thing. More than one rung only makes sense under
#                 `repeat == "again"`, which the generator enforces, and is the
#                 prose half of what {X} does for the numbers: Abyssal Baths
#                 answers each Linger with a hotter line. Read it through
#                 EventSystem.result_for(), never by index.
#   gates         Array of gate dicts — see gate_kind() below
#   effects       Array of EffectSystem effect dicts, applied immediately
#   effects_text  those effects in words, for the button's mechanical line
#   goal          {} or {"condition", "games", "effects", "effects_text"}
#   curse         {} or {"curse": &"poor_sleep", "games": 0}   (0 = the curse's own timer)
#   play          {} or {"tag": "mecha", "effects": [...], "effects_text": ".."}
#   chance        {} or {"percent": 25, "effects": [...], "effects_text": ".."} —
#                 a gamble. `percent` may instead arrive as a {expr} hole under
#                 "scaled", the same shape a scaling cost has, so the odds can
#                 climb per press. Winning pays `effects` AND closes the event,
#                 whatever `repeat` says: `Again` describes what happens when the
#                 gamble is LOST, and the thing you were reaching for is yours now.
@export var choices: Array = []


func tier_allows(tier_name: String) -> bool:
	return tier_tags.is_empty() or tier_tags.has(tier_name.to_lower())


func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")


# A choice's gate is one of two shapes, told apart by whether it carries a
# comparison operator:
#   {"choice": "immerse", "op": ">", "value": 0}   how often another choice was taken
#   {"resource": "keys", "value": 1}               whether the player can pay
static func gate_kind(gate: Dictionary) -> String:
	return "choice" if gate.has("choice") else "resource"
