class_name ObjectData
extends Resource

# An OBJECT (docs/object-sheet-authoring.md) — a machine you stand in front of.
#
# It is the same authored shape as an EVENT: a prompt, a handful of choices, each
# choice an Effect cell in the shared reward DSL. Three things make it a separate
# kind rather than a flag on EventData2:
#
#   * an event is a ROOM — it opens, you answer it, it is over. An object
#     PERSISTS: it stands in front of you for as long as the run stands on this
#     game, and travelling on is what ends it.
#   * an event arrives on its own. An object is SPAWNED — by an event (Arcade
#     Room puts 2-3 arcade machines in front of you), or by anything else that
#     asks for one — and SEVERAL can be in front of you at once.
#   * an object is STATEFUL. It jams, it gets blown up, and the Donation
#     Machine's bank is the one number in this build that outlives the run.
#
# Source of truth is the `objects2.0` sheet of tools/Roguelikes.xlsx (one row per
# object, choices in numbered column groups), generated into data/objects2.0/*.tres
# by tools/generate_object2_tres.py.

@export var id: StringName
@export var display_name: String
# The real game this is lifted from. Flavour credit only — it names the machine's
# origin on the Collection's page and nothing routes on it. (EventData2's
# `source_game` doubles as a placement target; this one does not.)
@export var source_game: String = ""

# --- which pool it is drawn from -------------------------------------------

# What a `spawn_object tag=<tag>` asks for. An object may carry several.
@export var tags: PackedStringArray = PackedStringArray()

# The rarity ladder, as a STRING the way events name theirs ("Common"). Every
# spawn slot rolls rarity first and then draws from that rarity's bucket of the
# tag, falling down the ladder when a bucket is empty — so Luck reaches objects
# through the same roll it reaches everything else through.
@export var rarity: String = "Common"

# Times per run, 0 = no limit. Distinct from `unique`: this counts SPAWNS across
# the whole run, that one counts copies standing in front of you at once.
@export var run_limit: int = 0

# Whether two of this object may stand together. The Arcade Room may put two
# Blood Donation Machines in one room — there is no reason a room cannot have
# two of the same cabinet — but never two Donation Machines, because they would
# be two faces of one bank and the second would read as a way to dodge the jam.
@export var unique: bool = false

# --- reserved: an object placed in its own right ---------------------------
#
# Objects are spawned today (by an event, or by the dev panel). When one can
# stand on the map on its own, these three are what will gate it — the same
# three EventData2 carries, so the vocabulary does not fork. Nothing reads them.
@export var where: String = ""
@export var requirement: Dictionary = {}
@export var trigger: String = "after"

# Art base name under res://images2.0/objects/.
@export var file: String = ""

# --- what it says ----------------------------------------------------------

# Often empty, and that is authored rather than unfinished: the Blood Donation
# Machine keeps Isaac's silence. A machine with nothing to say is just the thing
# and its buttons.
@export var prompt: String = ""

# The two endings of a `chance` gamble, object-level for the same reason they are
# event-level: they are the machine's voice rather than the button's. The Blood
# Donation Machine's `chance_won` carries an {ITEM} hole, filled with whichever
# relic the burst actually paid.
@export var chance_won: String = ""
@export var chance_lost: String = ""

# --- the choices -----------------------------------------------------------

# In display order, the same Dictionary shape EventData2.choices holds — so
# EventSystem.describe_choice and EventSystem.resolve_choice read an object's
# choice with no second implementation. See EventData2 for the field list; the
# two an object adds are:
#
#   gates    may carry a third kind, {"flag": "not_jammed"} — a gate on the
#            MACHINE rather than on the player (see gate_kind below)
#   chance   may carry `else_effects` / `else_effects_text`, the losing side of a
#            two-sided roll. The Blood Donation Machine is the case: the needle
#            goes in either way, and what comes back is a coin or a burst machine.
@export var choices: Array = []


func has_tag(tag: StringName) -> bool:
	return tags.has(String(tag))


func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")


# A choice's gate is one of three shapes, told apart by which key it carries:
#   {"choice": "give_blood", "op": ">", "value": 0}   how often another choice was taken
#   {"resource": "bombs", "value": 1}                 whether the player can pay
#   {"flag": "not_jammed"}                            whether the MACHINE will
#
# The third is why the Donation Machine's button can be greyed out for two
# different reasons and say which — "Jammed" and "Full" are not the same refusal,
# and one grey button with no reason on it would be a worse answer than either.
static func gate_kind(gate: Dictionary) -> String:
	if gate.has("choice"):
		return "choice"
	return "flag" if gate.has("flag") else "resource"
