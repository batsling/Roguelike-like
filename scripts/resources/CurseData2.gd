class_name CurseData2
extends Resource

# A CURSE (docs/event-sheet-authoring.md §6) — the third kind of objective on the
# post-game checklist, and the only one the player is trying NOT to complete:
#
#   enemy goal   a debt   — miss it and it follows you and hits every game
#   event goal   a bonus  — miss it and it simply expires
#   curse goal   a bill   — MEET it and you pay, every time, until it expires
#
# Source of truth is the `curses2.0` sheet of tools/Roguelikes.xlsx, generated
# into data/curses2.0/*.tres by tools/generate_curse2_tres.py. Events hand one
# out by id (`add_curse poor_sleep`), the same way an item applies a status.
#
# NOT the shelved `CurseData` / `data/curses` system (games-first-redesign.md §5).
# Same word, different thing: a curse goal is a row on the checklist, not a card.
# Nothing should wire the two together.

@export var id: StringName
@export var display_name: String
# The real game this is lifted from — flavour credit on the checklist row.
@export var source_game: String = ""

# What the player must avoid doing, in the same honour-system voice the enemy
# goals use ("you use a rest site to replenish health"). Two flavours are worth
# keeping in the roster: conditions on the REAL GAME being played, which only
# this app can produce, and conditions on the run's own state.
@export var condition: String = ""

# What it costs when the condition IS met, as EffectSystem effect dicts — the
# same list an item's trigger carries, so a curse's bill is paid through the same
# pipe as an item's reward.
@export var penalty: Array = []
# The penalty read back in words ("-2 Health"), generated from `penalty` so the
# row can never claim something the effects don't do.
@export var penalty_text: String = ""

# Games it stays live before expiring. Three by default, matching the window an
# event goal gets, so the checklist clears at one rate rather than two.
#
# ZERO means PERMANENT — the sheet writes `N/A` in the Timer column and gets it.
# Curse of the Bell is the reason: the Slay the Spire curse it is lifted from is
# the one you cannot remove, and a three-game version of that is a different card.
# The run-side sentinel is a `games_left` of -1 (GameState.add_curse_goal), so a
# permanent curse is told apart from an expiring one by the sign rather than by
# re-reading the catalogue on every tick.
@export var timer: int = 3

# Games it stays live, as a phrase — "3 games", or "permanently". One
# implementation, because the checklist, the standing list and an event's choice
# line all have to say the same thing about the same curse.
static func window_text(games_left: int) -> String:
	if games_left < 0:
		return "permanent"
	return "%d %s left" % [games_left, "game" if games_left == 1 else "games"]

# Art base name under res://images2.0/curses/.
@export var file: String = ""


# The checklist row, composed rather than authored — there is no prose column to
# drift out of sync with what the curse actually does.
func describe() -> String:
	if condition == "":
		return penalty_text
	return "If %s, %s when you report the game." % [condition, _penalty_phrase()]


# Conditions authored the wrong way up. `condition` names the thing that COSTS
# you, but a couple are written as the ABSENCE of something instead — Curse of
# the Bell's is "you don't ring a bell" — because that is the shape the Slay the
# Spire card has.
const _NEGATIONS := ["you don't ", "you dont ", "you do not ", "you never ",
	"you fail to ", "you didn't ", "you did not "]


# The curse as an INSTRUCTION — the row the report checklist puts a tick box
# against: "don't use a rest site to replenish health", "ring a bell".
#
# The checklist is a list of things to DO, ticked if you did them, and a curse
# has to join it as one of those or it is the only row on the page whose box
# means something different from all the others. `condition` is the wrong voice
# for that twice over: it is a clause rather than an instruction ("you use a rest
# site to replenish health"), and it names the thing that costs you rather than
# the thing to do.
#
# Two shapes, because the conditions come in two:
#   "you use a rest site…"     -> "don't use a rest site…"
#   "you don't ring a bell"    -> "ring a bell"
# The negation is stripped rather than doubled, so nobody has to work out what
# "don't don't ring a bell" was supposed to mean.
func goal_text() -> String:
	var c: String = condition.strip_edges()
	if c == "":
		return "hold to %s" % display_name
	var lower: String = c.to_lower()
	for neg in _NEGATIONS:
		if lower.begins_with(neg):
			return c.substr(neg.length())
	# "you go below half health" -> "go below half health", so the "don't" below
	# lands on the verb. Every authored condition is in this second person; one
	# that is not still gets a readable instruction, just a blunter one.
	if lower.begins_with("you "):
		c = c.substr(4)
	return "don't %s" % c


func _penalty_phrase() -> String:
	# "-2 Health" is how a reward line reads; a curse row wants it as an act.
	var t := penalty_text.strip_edges()
	if t.begins_with("-"):
		return "take %s damage" % t.substr(1).replace(" Health", "")
	# Anything else is already an act ("Spawn a random enemy") — it just arrives
	# capitalised, because it is also printed on its own as a sentence elsewhere.
	# Mid-sentence it needs the lower case.
	if t == "":
		return t
	return t.substr(0, 1).to_lower() + t.substr(1)


func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
