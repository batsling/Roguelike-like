class_name AbilityData
extends Resource

# One ENEMY ABILITY — the catalogue entry behind a name in an enemy's `Ability`
# column (docs/games-first-redesign.md §7.6). Authored in the `abilities` sheet of
# tools/Roguelikes.xlsx and generated into data/abilities2.0/*.tres by
# tools/generate_ability_tres.py.
#
# THIS RESOURCE IS THE DESCRIPTION, NOT THE BEHAVIOUR. The sheet's `Effect` column
# is empty for all 28 rows — unlike tiles2.0 and units2.0, which carry a small DSL
# there — so what an ability DOES is written once in GameLoop2, keyed by `id`, and
# what it SAYS is this file. That split is deliberate: an ability reaches into the
# turn resolver, the mover, the spawner and the death path in ways a per-row
# effect string could not express, but its wording is content and belongs upstream
# in the sheet like every other line of text in the game.
#
# The consequence to remember: adding a row to the `abilities` sheet gives you a
# name, a type and a sentence, and NOTHING happens on the board until GameLoop2
# learns the id. `test_enemy_abilities.gd` asserts the two sides agree, so a row
# added without an implementation fails the suite rather than shipping as a lie on
# an enemy card.

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
