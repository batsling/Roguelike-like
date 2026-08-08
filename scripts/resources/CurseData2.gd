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
@export var timer: int = 3

# Art base name under res://images2.0/curses/.
@export var file: String = ""


# The checklist row, composed rather than authored — there is no prose column to
# drift out of sync with what the curse actually does.
func describe() -> String:
	if condition == "":
		return penalty_text
	return "If %s, %s at the end of combat." % [condition, _penalty_phrase()]


func _penalty_phrase() -> String:
	# "-2 Health" is how a reward line reads; a curse row wants it as an act.
	var t := penalty_text.strip_edges()
	if t.begins_with("-"):
		return "take %s damage" % t.substr(1).replace(" Health", "")
	return t


func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
