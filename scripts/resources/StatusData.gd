class_name StatusData
extends Resource

# Static definition of a STATUS — the games-first redesign's balance lever
# (docs/games-first-redesign.md §13). A status is not a stat modifier and it is
# not combat state: it is a CLAUSE bolted onto the run's goals, which is the only
# currency this game has. That is why a location, an item, or a scroll can reach
# into the run's difficulty without any of them knowing what a goal is.
#
# A status has TWO SIDES, `on_player` and `on_enemy`, authored independently in
# the sheet so its halves can do genuinely different things (Marked taxes every
# goal on the player's side and pays out on the enemy's). Each side names a MODE,
# and the mode is the whole of what that side does:
#
#   goal    a standing objective of the holder's own — "If <condition>, gain
#           <reward>". On the player it is an extra checklist row, offered every
#           game and paid every time it is met.
#   clause  ANDed onto goals and REQUIRED: the goal is not met until both were
#           done. On an enemy it tightens that enemy's goal; on the player it
#           tightens EVERY enemy's goal.
#   bonus   an OPTIONAL objective — "and if <condition>, gain <reward>" —
#           claimable for its reward and free to skip.
#
# Because the mode says what a side does, `kind` (Buff / Debuff) drives no
# mechanic at all: it is the HUD tint and the collection filter, nothing more.
#
# Source-of-truth content lives in the `statuses2.0` sheet of
# tools/Roguelikes.xlsx and is generated into data/statuses2.0/*.tres by
# tools/generate_status_tres.py.

# The two sides, named so callers read as `status.condition_text(StatusData.PLAYER, n)`
# rather than passing a bare string nobody can typo-check.
const PLAYER := &"player"
const ENEMY := &"enemy"

@export var id: StringName
@export var display_name: String

# Buff or Debuff (the sheet's Type column), lowercased. FLAVOUR ONLY — see the
# header. Kept because it is how the player thinks about a status and how the
# collection groups them.
@export var kind: StringName = &"buff"

# The real roguelike the status is lifted from (Slay the Spire, Mewgenics).
# Informational, same role as GoalEnemyData.source_game.
@export var source_game: String = ""

# The sheet's prose for each side, kept verbatim for tooltips and the collection
# screen. The ENGINE never parses these — it builds its own wording from the side
# blocks below — but they are the author's intent, so a drift between the prose
# and the generated text is a content bug worth being able to see.
@export var on_player_text: String = ""
@export var on_enemy_text: String = ""

# How the sheet says stacks combine ("Intensity" for the current roster — a second
# application raises X rather than starting a second timer).
@export var stackable: String = "Intensity"

# THE TWO SIDES. Each is either {} (this side does nothing) or:
#   {"mode": "goal"|"clause"|"bonus",
#    "condition": String,        the challenge clause, with {expr} holes over X
#    "reward": Array,            EffectSystem effect dicts, {expr} holes in `scaled`
#    "reward_text": String,      human wording for the payout
#    "decay": bool}              completing it sheds one stack
@export var on_player: Dictionary = {}
@export var on_enemy: Dictionary = {}

# Art base name under res://images2.0/statuses/ (the sheet's Image column).
@export var file: String = ""
@export var image: Texture2D

# --- kind (flavour) -------------------------------------------------------

func is_buff() -> bool:
	return kind == &"buff"

func is_debuff() -> bool:
	return kind == &"debuff"

# True when a second application raises X instead of stacking independently — the
# only mode the current roster authors, but asked as a question so a future
# duration-based status doesn't have to be special-cased at every call site.
func stacks_by_intensity() -> bool:
	return stackable.to_lower().begins_with("intensity")

func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")

# --- sides ----------------------------------------------------------------

# One side's block, or {} when that side is inert.
func side(which: StringName) -> Dictionary:
	return on_enemy if which == ENEMY else on_player

# What `which` side DOES: &"goal", &"clause", &"bonus", or &"" when inert.
func mode_for(which: StringName) -> StringName:
	return StringName(String(side(which).get("mode", "")))

func has_side(which: StringName) -> bool:
	return mode_for(which) != &""

func is_goal(which: StringName) -> bool:
	return mode_for(which) == &"goal"

func is_clause(which: StringName) -> bool:
	return mode_for(which) == &"clause"

func is_bonus(which: StringName) -> bool:
	return mode_for(which) == &"bonus"

# Whether completing this side sheds a stack.
func decays(which: StringName) -> bool:
	return bool(side(which).get("decay", false))

# A side the player can tick and be PAID for — a goal or a bonus. A clause has
# nothing to claim: it is folded into the goal it taxes.
func is_claimable(which: StringName) -> bool:
	var m: StringName = mode_for(which)
	return m == &"goal" or m == &"bonus"

# --- text -----------------------------------------------------------------

# One side's condition clause at `stacks`, every {expr} hole resolved:
#   Marked / enemy    at 3 -> "you get 3 achievements"
#   Dexterity / enemy at 3 -> "must be beaten in 1 hour 30 minutes or less"
func condition_text(which: StringName, stacks: int) -> String:
	return resolve(String(side(which).get("condition", "")), stacks)

# One side's reward wording at `stacks` — "+2 Small Chests, +2 Bashes".
func reward_at(which: StringName, stacks: int) -> String:
	return resolve(String(side(which).get("reward_text", "")), stacks)

# The bare clause, for ANDing onto a goal. Rendered without a leading "and" so the
# caller joins it however its line reads.
func clause_text(which: StringName, stacks: int) -> String:
	return condition_text(which, stacks)

# How a CLAIMABLE side reads as a checklist row. A `goal` is a standing objective
# and opens with "If"; a `bonus` hangs off something else and opens with "and if".
# Either way the reward is part of the line, because the whole point of the row is
# that it pays — a row you might skip has to advertise what skipping costs.
func objective_text(which: StringName, stacks: int) -> String:
	var line: String = "%s %s" % [
		"and if" if is_bonus(which) else "If", condition_text(which, stacks)]
	var pay: String = reward_at(which, stacks)
	if pay != "":
		line += ", gain %s" % pay
	return line

# The hover tooltip for one side, Slay-the-Spire style: the status's name and
# stack count, what that side DOES, and the live line at this stack. Every view
# that draws a status pip asks for this — the hero strip, the enemy strip, the
# enemy card, the HUD chip — so a status can never say one thing in one place and
# something else in another.
func tooltip_for(which: StringName, stacks: int) -> String:
	var head: String = "%s %d" % [display_name, stacks]
	if source_game != "":
		head += "   (%s)" % source_game
	var body: String = ""
	match mode_for(which):
		&"goal":
			body = "Standing goal — %s" % objective_text(which, stacks)
		&"bonus":
			body = "Bonus — %s" % objective_text(which, stacks)
		&"clause":
			body = ("Every enemy's goal also needs: %s" if which == PLAYER
				else "This enemy's goal also needs: %s") % clause_text(which, stacks)
		_:
			body = "Does nothing on this side."
	if decays(which):
		body += "\nLoses a stack each game you complete it."
	return "%s\n%s" % [head, body]

# --- reward effects -------------------------------------------------------

# One side's reward as EffectSystem-ready effect dicts at `stacks`. The generator
# stores each effect with its {expr} holes listed in a `scaled` sub-dict (field
# name -> expression); this evaluates them at X = stacks and returns plain dicts
# the EffectSystem applies unchanged:
#
#   {"type": "gain_chest", "choices": 1, "scaled": {"value": "X"}}   at X=2
#     -> {"type": "gain_chest", "choices": 1, "value": 2}
func reward_effects(which: StringName, stacks: int) -> Array:
	var out: Array = []
	for raw in side(which).get("reward", []):
		if not (raw is Dictionary):
			continue
		var eff: Dictionary = (raw as Dictionary).duplicate(true)
		var scaled: Dictionary = eff.get("scaled", {})
		eff.erase("scaled")
		for field in scaled.keys():
			eff[field] = int(round(evaluate(String(scaled[field]), stacks)))
		out.append(eff)
	return out

# --- the {expr} mini-language --------------------------------------------

# Substitutes every hole in `text` at X = `stacks`. Two kinds:
#
#   {expr[:format]}     an arithmetic expression over X. With no format it is a
#                       plain number, read-ready: whole values lose their decimal
#                       tail ("2", not "2.0"). With `:hours` it renders as a
#                       DURATION — "1 hour 30 minutes" — because a time window is
#                       something the player has to hold against a clock, and
#                       "1.5 hours" is arithmetic they'd have to do themselves.
#   [singular|plural]   agrees in number with the {expr} most recently resolved,
#                       so "+{X} [Small Chest|Small Chests]" reads correctly at
#                       every stack count instead of picking one and being wrong
#                       at the other. Before any number has been seen it takes the
#                       plural, which is the reading a bare noun wants.
func resolve(text: String, stacks: int) -> String:
	if text == "" or not (text.contains("{") or text.contains("[")):
		return text
	var out: String = ""
	var rest: String = text
	var last_value: float = INF   # nothing counted yet
	while true:
		var open_at: int = _first_hole(rest)
		if open_at < 0:
			out += rest
			break
		var is_expr: bool = rest[open_at] == "{"
		var close_at: int = rest.find("}" if is_expr else "]", open_at)
		if close_at < 0:
			out += rest
			break
		out += rest.substr(0, open_at)
		var body: String = rest.substr(open_at + 1, close_at - open_at - 1)
		if is_expr:
			var fmt: String = ""
			var colon: int = body.rfind(":")
			if colon >= 0:
				fmt = body.substr(colon + 1).strip_edges().to_lower()
				body = body.substr(0, colon)
			last_value = evaluate(body, stacks)
			out += format_hours(last_value) if fmt == "hours" else format_number(last_value)
		else:
			var forms: PackedStringArray = body.split("|")
			var singular: bool = forms.size() > 1 and is_equal_approx(last_value, 1.0)
			out += forms[0] if singular else forms[forms.size() - 1]
		rest = rest.substr(close_at + 1)
	return out

# The first `{` or `[` in `text`, whichever comes first; -1 when neither is there.
func _first_hole(text: String) -> int:
	var brace: int = text.find("{")
	var bracket: int = text.find("[")
	if brace < 0:
		return bracket
	if bracket < 0:
		return brace
	return mini(brace, bracket)

# One arithmetic expression over X, via Godot's own Expression parser — so a status
# can scale on whatever curve the sheet feels like without the engine knowing the
# shapes in advance. The generator has already rewritten the sheet's `a^b` into
# `pow(a, b)`. A malformed expression warns and reads as the raw stack count rather
# than taking the run down.
func evaluate(expr: String, stacks: int) -> float:
	var e := Expression.new()
	if e.parse(expr.strip_edges(), ["X"]) != OK:
		push_warning("StatusData %s: cannot parse '%s' (%s)" % [id, expr, e.get_error_text()])
		return float(stacks)
	var value: Variant = e.execute([stacks], null, false)
	if e.has_execute_failed():
		push_warning("StatusData %s: cannot evaluate '%s'" % [id, expr])
		return float(stacks)
	if value is float or value is int:
		return float(value)
	return float(stacks)

# 2.0 -> "2", 1.5 -> "1.5", 1.125 -> "1.125". Trailing zeros are noise on a
# checklist row, and "beaten in 2.000000 hours" reads as a bug.
static func format_number(v: float) -> String:
	if is_equal_approx(v, round(v)):
		return str(int(round(v)))
	var s: String = "%.4f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s

# A count of HOURS as a duration the player can hold against a clock:
#   3      -> "3 hours"
#   1.5    -> "1 hour 30 minutes"
#   1.125  -> "1 hour 8 minutes"   (67.5 min, rounded to the minute)
#   0.75   -> "45 minutes"
# Rounded to the nearest minute, because no honour-system timer is finer than that
# and "1 hour 7.5 minutes" invites a precision the report step doesn't have.
static func format_hours(hours: float) -> String:
	var total: int = int(round(hours * 60.0))
	if total <= 0:
		return "0 minutes"
	var h: int = total / 60
	var m: int = total % 60
	var parts: PackedStringArray = []
	if h > 0:
		parts.append("%d %s" % [h, "hour" if h == 1 else "hours"])
	if m > 0:
		parts.append("%d %s" % [m, "minute" if m == 1 else "minutes"])
	return " ".join(parts)
