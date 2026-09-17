class_name AbilityData
extends Resource

# One ENEMY ABILITY — the catalogue entry behind a name in an enemy's `Ability`
# column (docs/games-first-redesign.md §7.6). Authored in the `abilities` sheet of
# tools/Roguelikes.xlsx and generated into data/abilities2.0/*.tres by
# tools/generate_ability_tres.py.
#
# THE SHEET SAYS WHEN AND WHAT, THE LOOP SAYS HOW. The `Effect` column carries a
# small DSL — the same `trigger: op args` one tiles2.0 and units2.0 use — parsed
# into `triggers` below, and GameLoop2 DISPATCHES ON IT rather than on `id`.
#
# It did not always. This column was empty in all 31 rows and every ability was a
# hardcoded branch keyed by id, which made abilities the one content type whose
# behaviour was not authored upstream: adding a row to the sheet gave you a name,
# a type and a sentence, and nothing whatsoever happened on the board until
# someone edited a 6869-line GDScript file. Every other system here — tiles,
# units, pills, scrolls, potions, items — reads its behaviour out of its own
# Effect column, and abilities now do too.
#
# WHAT THAT DOES AND DOES NOT BUY. An ability composed of ops the loop already has
# is a SHEET ROW and nothing else: author "hit: apply_status burn 2" and it works.
# An ability that needs a genuinely new primitive still needs engine code, exactly
# as a tile needing something past `apply_status` / `detonate` does — the op
# vocabulary is the seam, and it is a much smaller and better-marked one than
# "somewhere in the turn resolver".
#
# `GameLoop2.ABILITY_OPS` is the list of ops that exist. The generator checks
# every authored op against it and refuses to write a row naming one that does
# not, so an unimplemented op is caught when the sheet is regenerated rather than
# as a silent no-op on the board. `test_enemy_abilities.gd` asserts the two sides
# agree from the other direction too.

@export var id: StringName
@export var display_name: String

# The sheet's `Type` — the WHEN of the ability, and the one thing about it a
# player can generalise from:
#   attack      — rides a swing that lands (see `needs_damage` below)
#   buff        — true from the moment it spawns
#   death       — fires as it comes off the board
#   intent      — replaces what it does with its turn
#   movement    — changes how (or whether) it walks
#   resistance  — refuses something that would otherwise happen to it
#   summoner    — puts new bodies on the board
# Stored lowercased. Purely descriptive: GameLoop2 dispatches on `id`, never on
# this, so a mis-typed row is a wrong chip and not a wrong rule.
@export var kind: StringName = &""

# The sheet's `Variables` column verbatim ("Amount, Status Type", "N/A", …), kept
# for the collection screen, and `params` — the same thing normalised into the
# ordered slots the generator actually fills. One of:
#   []                    no arguments
#   ["amount"]            a count or a stack size
#   ["range"]             a grid distance (0 means unlimited, see §7.6 Ranged)
#   ["tile"]              a tiles2.0 id
#   ["amount", "status"]  count + a statuses2.0 id
#   ["amount", "enemy"]   count + a pool selector (tag:… / tier:… / enemy:… / self)
#   ["amount", "goods"]   count + gold | item | loot
@export var variables: String = ""
@export var params: PackedStringArray = PackedStringArray()

# The sheet's `Description`, with `X` standing in for the first argument and `Y`
# for the second. `describe()` fills them in.
@export var description: String = ""

# The sheet's `Effect` column VERBATIM, for the collection screen and for anyone
# reading a .tres — the authored line beside the parsed form, exactly as
# TileEffectData keeps `decay_text` beside its counter.
@export var effect: String = ""

# WHAT IT DOES, as trigger name -> Array of op dicts. The parsed form of `effect`,
# and what GameLoop2 actually runs.
#
#   spawn       true from the moment the body lands
#   first_turn  spends only its FIRST turn on this (the loop's `taken == 0`)
#   turn        spends EVERY turn on this
#   hit         rides a swing that LANDS — a swing a Shield ate fires none of
#               these, which is what makes cover an answer to Infliction and
#               Theft rather than only to the damage (see `needs_damage`)
#   death       fires as the body comes off the board
#   passive     a rule the resolver QUERIES rather than an event it runs
#
# Each op is {"op": StringName, "args": PackedStringArray}, with the args left as
# the sheet wrote them:
#   {"op": &"apply_status", "args": ["Y", "X"]}
#   {"op": &"reach", "args": ["X"]}
#
# X AND Y ARE NOT RESOLVED HERE. They are the ability's own argument slots (see
# `params`), and the body carrying the ability is what fills them — "Infliction
# (2, Burn)" and "Infliction (1, Stun)" are one row with two sets of arguments,
# so the substitution belongs at the body and not at the catalogue.
# `GameLoop2.ability_op_args` does it.
@export var triggers: Dictionary = {}

# Does this ability do anything at `when`? Cheaper and clearer at the call sites
# than digging the dictionary out, and it is the question every dispatch point in
# the loop actually asks.
func fires_on(when: StringName) -> bool:
	return not (triggers.get(when, []) as Array).is_empty()

# The ops this ability runs at `when`, or an empty array.
func ops_on(when: StringName) -> Array:
	return triggers.get(when, []) as Array

# Does it declare `op` at all, at any trigger? The passives are read this way —
# "is this body Immobile" is "does anything it carries declare `no_move`".
func has_op(op: StringName) -> bool:
	for when in triggers:
		for entry in (triggers[when] as Array):
			if StringName((entry as Dictionary).get("op", &"")) == op:
				return true
	return false

# Art base name under res://images2.0/abilities/ (none ship today, so this
# resolves to nothing and the UI draws the ⚠ glyph instead).
@export var file: String = ""
@export var image: Texture2D

# Whether this ability takes a numeric argument at all — i.e. whether "Split (2)"
# is meaningful or "Split" is the whole of it.
func takes_amount() -> bool:
	return params.size() > 0 and params[0] in ["amount", "range"]

# The second argument's slot name ("status", "enemy", "goods", "tile"), or "" for
# the abilities that take only a count. `tile` is the one that sits in slot ONE
# (Aftermath's only argument is a tile effect), so read this rather than assuming
# a second slot exists.
func arg_slot() -> String:
	for p in params:
		if p in ["status", "enemy", "goods", "tile"]:
			return p
	return ""

# ATTACK ABILITIES THAT NEED THE HIT TO LAND. Every rider in the roster is worded
# "when this Enemy attacks and deals damage" — a swing a Shield ate fires none of
# them, which is what makes cover an answer to Infliction and Theft rather than
# only to the damage. Read off the wording rather than listed by id, so a new row
# gets the rule its own sentence promises.
func needs_damage() -> bool:
	var text: String = description.to_lower()
	return text.contains("deals damage") or text.contains("dealing damage")

# The ability's sentence with its arguments substituted in: X becomes the number,
# Y becomes `arg_text` (the sheet's own wording for the argument — "Burn", "slime
# tag", "Random Medium"), so the card reads the way the sheet was written.
#
# The substitution is on WHOLE WORDS. A plain replace() would rewrite the X inside
# a word — and the roster has "X Enemies", "X Speed" and "X times" sitting next to
# no word containing an x at all today, which is exactly the kind of thing that
# stays true until it doesn't.
func describe(amount: int = 0, arg_text: String = "") -> String:
	var out: String = description
	# RANGED (N/A) IS UNLIMITED, and the sentence has to say so. The sheet writes
	# `N/A` where a Psychic Horf or a Host fires down the whole lane, which parses
	# to 0 (GameLoop2.strike_range reads the same 0 and hands back the width of the
	# board) — so the plain substitution produced "Can Attack from 0 tiles away",
	# which reads as the exact opposite of the rule: no reach at all, rather than
	# every column of it.
	if id == &"ranged" and amount <= 0:
		return "Can Attack from any range — no square on the board is out of reach"
	if takes_amount():
		out = _sub(out, "X", str(amount))
	if arg_text != "":
		out = _sub(out, "Y", arg_text)
		# Aftermath's only argument is a tile effect and its sentence spells it as
		# "X Tile Effect" rather than Y, because the count slot is the one it uses.
		if arg_slot() == "tile":
			out = _sub(out, "X", arg_text)
	return out

func _sub(text: String, token: String, value: String) -> String:
	var re := RegEx.new()
	re.compile("\\b%s\\b" % token)
	return re.sub(text, value, true)
