class_name StatusData
extends Resource

# Static definition of a STATUS — the games-first redesign's balance lever
# (docs/games-first-redesign.md §13). A status is first of all a CLAUSE bolted
# onto the run's goals, which is the only currency this game has, and that is why
# a location, an item, or a scroll can reach into the run's difficulty without any
# of them knowing what a goal is.
#
# It is ALSO, since the combat expansion, a modifier on the board: a Strength
# stack makes an enemy hit harder, a Dexterity stack gives it a shield to spend, a
# Speed stack walks it a tile closer, and Marked doubles what lands on whoever is
# wearing it. That side is `combat`, at the bottom of the exports, and it is the
# only part of a status that touches a number rather than a goal.
#
# A status has TWO GOAL SIDES, `on_player` and `on_enemy`, authored independently
# in the sheet so its halves can do genuinely different things (Marked taxes every
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
# mechanic at all: it is the HUD tint and the collection filter, nothing more. The
# distinction it stands for is real, but it is spelled out in `enemy_only` rather
# than inferred from the word — a debuff's combat side reaches the player too.
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

# THE COMBAT SIDE. Everything above rewrites GOALS; this is the one part of a
# status that touches a number on the board. `combat_text` is the sheet's prose
# and `combat` is what the engine runs on — {} for a status that does nothing in
# combat, else some of:
#
#   damage_dealt        String expr over X   this thing's hits land for that much more
#   damage_taken        String expr over X   hits on this thing land for that much more
#   damage_dealt_mult   float                flat multiplier on what it deals
#   damage_taken_mult   float                flat multiplier on what it takes
#   shield              String expr over X   shield points granted when it lands
#   tile_move           String expr over X   extra columns closed per step
#   pierce_shields      bool                 damage at this thing ignores shields
#
# The additive fields scale with the stack count; the MULTIPLIERS deliberately do
# not. Marked doubles damage at one stack and at four — a doubling that compounded
# per stack would turn a board where hits are worth 1 into one where they are
# worth 16, off a status the player never chose to stack.
@export var combat_text: String = ""
@export var combat: Dictionary = {}

# Whether the combat side is felt on ENEMIES ONLY (the sheet's EnemyOnly column).
# Every buff is: Strength on the player would be a stat, and this game has no
# player attack to put it on. Every debuff is not — a debuff is felt by whoever is
# carrying it, so Marked doubles the damage the PLAYER takes as readily as an
# enemy's. Nothing else in the class keys off Buff/Debuff; this column is where
# that distinction became a rule instead of a tint.
@export var enemy_only: bool = true

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

# The same thing as a HOVER CARD — the model HoverCard.build draws (its art, its
# name in the colour of what it does, and the one or two lines that decide
# something). This and `tooltip_for` are the same facts at two lengths, and they
# live beside each other so they cannot drift: the card is what the run shows on
# a pip, the string is the fallback and what a plain-text caller still reads.
#
# `stacks` rides in the SUBTITLE rather than the title, because the name is what
# is being recognised and the count is what is being read after it.
func hover_card(which: StringName, stacks: int) -> Dictionary:
	var mode: StringName = mode_for(which)
	var good: bool = is_bonus(which) or is_goal(which)
	var sub: String = "%s stack%s" % [stacks, "" if stacks == 1 else "s"]
	match mode:
		&"goal":
			sub = "Standing goal  ·  " + sub
		&"bonus":
			sub = "Bonus  ·  " + sub
		&"clause":
			sub = "Goal clause  ·  " + sub
	if source_game != "":
		sub += "  ·  %s" % source_game

	var lines: Array = []
	match mode:
		&"goal", &"bonus":
			lines.append(objective_text(which, stacks))
		&"clause":
			lines.append(("Every enemy's goal also needs: %s" if which == PLAYER
				else "This enemy's goal also needs: %s") % clause_text(which, stacks))
		_:
			lines.append("Does nothing on this side.")
	if combat_applies(which):
		lines.append("In combat: %s." % combat_line(stacks))

	return {
		"title": display_name,
		"subtitle": sub,
		"accent": Color(1.0, 0.82, 0.30) if good else Color(0.90, 0.26, 0.22),
		"art": image,
		"lines": lines,
		"note": "Loses a stack each game you complete it." if decays(which) else "",
	}

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
	# The combat side rides the same tooltip rather than a second one: a pip is
	# one thing to the player, and "what is this doing to me" has to be answerable
	# in one hover whether the answer is a goal, a number on the board, or both.
	if combat_applies(which):
		body += "\nIn combat: %s." % combat_line(stacks)
	elif has_combat() and which == PLAYER:
		body += "\nIts combat effect is felt by enemies only."
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

# --- the combat side ------------------------------------------------------

# The keys `combat_totals` reports, and what an absent one reads as. Named here
# so a caller reads a total by field rather than by remembering that a missing
# multiplier is 1.0 and a missing bonus is 0.
const COMBAT_ZERO := {
	"damage_dealt": 0, "damage_taken": 0,
	"damage_dealt_mult": 1.0, "damage_taken_mult": 1.0,
	"shield": 0, "tile_move": 0, "pierce_shields": false,
}

func has_combat() -> bool:
	return not combat.is_empty()

# Whether this status's combat side is felt by `which`. A status on an ENEMY
# always acts; on the PLAYER only when the sheet said it reaches that far.
func combat_applies(which: StringName) -> bool:
	return has_combat() and (which == ENEMY or not enemy_only)

# One additive combat field at `stacks` — 0 when this status doesn't author it.
func combat_bonus(field: StringName, stacks: int) -> int:
	if not combat.has(field):
		return 0
	return int(round(evaluate(String(combat[field]), stacks)))

# One multiplier field, 1.0 when unauthored. Flat: `stacks` is not consulted.
func combat_mult(field: StringName) -> float:
	return float(combat.get(String(field) + "_mult", 1.0))

func pierces_shields() -> bool:
	return bool(combat.get("pierce_shields", false))

# THE aggregator: what a whole collection of statuses does in combat. `held` is
# the id -> stacks dict both holders keep (GameState.player_statuses and the
# `statuses` dict on a GameLoop2 board entry), and `which` says which side is
# asking. Bonuses sum, multipliers multiply, flags OR together.
#
# One function for both holders on purpose. The player and an enemy carry the same
# statuses through the same rules, and two aggregators would be two places for
# "does Marked pierce?" to be answered differently.
static func combat_totals(held: Dictionary, which: StringName) -> Dictionary:
	var out: Dictionary = COMBAT_ZERO.duplicate()
	for id in held.keys():
		var status: StatusData = Data.get_status(StringName(id))
		if status == null or not status.combat_applies(which):
			continue
		var stacks: int = int(held[id])
		if stacks <= 0:
			continue
		for field in ["damage_dealt", "damage_taken", "shield", "tile_move"]:
			out[field] = int(out[field]) + status.combat_bonus(StringName(field), stacks)
		for field in ["damage_dealt_mult", "damage_taken_mult"]:
			out[field] = float(out[field]) * status.combat_mult(
				StringName(String(field).trim_suffix("_mult")))
		out["pierce_shields"] = bool(out["pierce_shields"]) or status.pierces_shields()
	return out

# Apply one totals dict to a raw damage number: the bonus first, then the
# multiplier, floored at 0. Both halves in one function so "does the x2 apply
# before or after the +1?" has exactly one answer wherever damage is worked out.
static func apply_damage_mods(damage: int, bonus: int, mult: float) -> int:
	return maxi(0, int(round(float(damage + bonus) * mult)))

# What the combat side DOES, in words, at `stacks` — the live line the tooltips
# carry. Built from the parsed `combat` rather than from `combat_text`, so it
# quotes the number that is actually in force instead of the sheet's bare X.
func combat_line(stacks: int) -> String:
	if not has_combat():
		return ""
	var parts: PackedStringArray = []
	var dealt: int = combat_bonus(&"damage_dealt", stacks)
	if dealt != 0:
		parts.append("deals %+d damage" % dealt)
	var dealt_mult: float = combat_mult(&"damage_dealt")
	if not is_equal_approx(dealt_mult, 1.0):
		parts.append("deals %sx damage" % format_number(dealt_mult))
	var taken: int = combat_bonus(&"damage_taken", stacks)
	if taken != 0:
		parts.append("takes %+d damage" % taken)
	var taken_mult: float = combat_mult(&"damage_taken")
	if not is_equal_approx(taken_mult, 1.0):
		parts.append("takes %sx damage" % format_number(taken_mult))
	var shield: int = combat_bonus(&"shield", stacks)
	if shield != 0:
		parts.append("+%d %s" % [shield, "Shield" if shield == 1 else "Shields"])
	var move: int = combat_bonus(&"tile_move", stacks)
	if move != 0:
		parts.append("moves %+d %s per turn" % [move, "tile" if absi(move) == 1 else "tiles"])
	if pierces_shields():
		parts.append("ignores Shields")
	return ", ".join(parts)

# --- the {expr} mini-language --------------------------------------------

# Substitutes every hole in `text` at X = `stacks`. Two kinds:
#
#   {expr[:format]}     an arithmetic expression over X. With no format it is a
#                       plain number, read-ready: whole values lose their decimal
#                       tail ("2", not "2.0"). With `:hours` it renders as a
#                       DURATION — "1 hour 30 minutes" — because a time window is
#                       something the player has to hold against a clock, and
#                       "1.5 hours" is arithmetic they'd have to do themselves.
#                       With `:chests` it renders a count of chest POINTS as the
#                       chests it buys (§8.2) — "1 Large Chest" at 3, "1 Huge
#                       Chest and 1 Small Chest" at 5 — because the point count
#                       is an implementation detail and the chests are the promise.
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
			match fmt:
				"hours":
					out += format_hours(last_value)
				"chests":
					out += Data.chest_reward_text(int(round(last_value)))
				_:
					out += format_number(last_value)
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
