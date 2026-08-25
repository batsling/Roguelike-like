class_name ScrollData
extends Resource

# Static definition of a scroll — the games-first (2.0) loot consumable
# (docs/games-first-redesign.md §4.1). Source-of-truth content lives in the
# `scrolls2.0` sheet of tools/Roguelikes.xlsx and is generated into
# data/scrolls2.0/*.tres by tools/generate_scroll2_tres.py.
#
# Scrolls arrive UNIDENTIFIED and carry a Preference (Positive / Negative /
# Neutral) that colours whether reading a mystery scroll is a gamble. Reading
# applies the scroll's single authored effect and identifies its type
# (learn-by-use); identification is global per-type (lives on GameState; see
# ScrollSystem). The old four-tier Intelligence-check model was cut with combat
# (§11) — a scroll now has one `effect`, not four outcome tiers.

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the sheet's string, mapped to
# the shared 0-3 ordering by rarity_index() for the reward roller.
@export var rarity: String = "Common"
@export var reference: String = ""
# "Positive" | "Negative" | "Neutral" — the identification gamble's flavour.
@export var preference: String = "Neutral"
# The sheet's Description column: the scroll's effect in the author's own words.
# ScrollSystem.scroll_text prefers this over the line it assembles from the ops,
# because an authored sentence is allowed to say things the op list cannot —
# Amnesia's "Identified Loot" covers three kinds that its single `forget` op can
# only name one of. Blank falls back to the assembled line, so a scroll authored
# without one still describes itself.
@export var description: String = ""
# Art base name under res://images2.0/scrolls/ (the sheet's File column). Identified
# art is scrolls/<file>.png; unidentified scrolls — and identified scrolls whose
# File art is missing — fall back to scrolls/Unidentified.png (see ScrollSystem).
@export var file: String = ""

# How likely this scroll is to be the one drawn OUT OF ITS RARITY BUCKET — the
# sheet's Notes column, where Identify says "Has a +25% find rate", read as 1.25.
#
# A WEIGHT INSIDE THE BUCKET, NOT A SHARE OF ALL DROPS (potions-design §10,
# decision #20). The 75/20/5 ladder picks the rarity first and this only decides
# which member of that rarity comes up, so a find rate can never quietly promote a
# Common past an Uncommon — rarity keeps meaning what it means. 1.0 is "like
# everything else at this rarity", which is what an unannotated scroll gets.
@export var find_weight: float = 1.0

# The scroll's structured effect: a list of ops (each a Dictionary with an "op"
# plus op-specific keys) applied by ScrollSystem.read_scroll — e.g.
#   {"op": "apply_status", "status": "strength", "value": 1,
#    "target": "all"}                                        (Aggravate Monsters)
#   {"op": "forget", "kind": "loot", "count": 1}             (Amnesia)
#   {"op": "spawn_enemy", "difficulty": "current"}           (Create Monster)
#   {"op": "identify_loot", "mode": "choose", "count": 1}    (Identify)
#   {"op": "remove_curse", "mode": "choose", "count": 1}     (Remove Curse)
#   {"op": "stun_enemies", "mode": "choose", "count": 1}     (Scare Monster)
#   {"op": "teleport", "dir": "same", "spread": 1}           (Teleportation)
@export var effect: Array = []

# Shared 0-3 rarity ordering (Common/Uncommon/Rare/Legendary).
func rarity_index() -> int:
	match rarity.to_lower():
		"uncommon":
			return 1
		"rare":
			return 2
		"legendary":
			return 3
		_:
			return 0

# Art base name, falling back to the de-spaced display name when `file` is unset.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
