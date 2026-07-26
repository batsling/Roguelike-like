class_name ScrollData
extends Resource

# Static definition of a scroll — the out-of-combat loot consumable (sibling of
# PotionData). Source-of-truth content lives in the `scrolls` sheet of
# tools/Roguelikes.xlsx and is generated into data/scrolls/*.tres by
# tools/generate_scroll_tres.py.
#
# Scrolls are usable only OUTSIDE combat. Reading one runs a two-roll INT check
# (d20 + Intelligence vs DC 10, then a crit roll) that picks one of four outcome
# tiers; ScrollSystem applies that tier's structured effects. Scrolls are GAINED
# unidentified — the player learns a scroll type's identity by reading one, and
# identification is global per-type (lives on GameState; see ScrollSystem).

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the sheet's string, mapped to
# the shared 0-3 ordering by rarity_index() for the reward roller.
@export var rarity: String = "Common"
@export var reference: String = ""
# "Positive" | "Negative" | "Neutral" — design-side flavour from the sheet;
# carried for display/tooling, not used in resolution logic.
@export var preference: String = "Neutral"
# Art base name under res://images/scrolls/ (e.g. "Identify"). Identified art is
# scrolls/<file>.png; unidentified scrolls all show scrolls/Unidentified.png.
@export var file: String = ""

# The four outcome tiers, keyed crit_good / good / bad / crit_bad. Each value is
# a Dictionary { "description": String, "effects": Array }, mirroring EventData:
#   description — the player-facing prose from the sheet's outcome column.
#   effects     — structured ops applied by ScrollSystem, parsed by the generator
#                 from the sheet's matching "<Tier> Effect" column. Each entry is
#                 a Dictionary with an "op" plus op-specific keys, e.g.
#                   {"op": "buff_enemies", "power": 2}
#                   {"op": "spawn_enemies", "count": 1, "max_weight": 3}
#                   {"op": "identify_scrolls", "mode": "choose", "count": 3}
#                   {"op": "stun_enemies", "mode": "all"}
#                   {"op": "teleport", "dir": "closer", "max_steps": 3}
#                   {"op": "enchant_weapon", "target": "choose", "dmg": 5, "retain": true}
#                   {"op": "self_damage", "value": 10, "element": "fire"}
#                   {"op": "forget", "kind": "scroll", "count": 2}   (count -1 = all)
@export var outcomes: Dictionary = {}

# === Games-first redesign (2.0) scroll model ===
# The no-combat rework (docs/games-first-redesign.md §4.1) replaces the four-tier
# INT-check model above with a single effect + a Preference (Positive / Negative
# / Neutral) that colours whether reading a mystery scroll is a gamble. The
# identification minigame (unidentified art + Preference gamble, learn-by-use,
# Scroll of Identify, Amnesia re-hides) is unchanged and still lives on
# ScrollSystem + GameState.identified_scroll_types.
#
# `effect` is a list of structured ops (each a Dictionary with an "op" plus
# op-specific keys) applied by the 2.0 ScrollSystem — e.g.
#   {"op": "buff_enemies", "damage": 1, "games": 1}   (Aggravate Monsters)
#   {"op": "forget", "kind": "scroll", "count": 1}     (Amnesia)
#   {"op": "spawn_enemy", "difficulty": "current"}     (Create Monster)
#   {"op": "identify_scrolls", "mode": "choose", "count": 1}  (Identify)
#   {"op": "stun_enemies", "mode": "choose", "count": 1}     (Scare Monster)
#   {"op": "teleport", "dir": "same", "spread": 1}     (Teleportation)
# These are populated by tools/generate_scroll_tres.py from the scrolls2.0 sheet
# into data/scrolls2.0/*.tres. The four-tier `outcomes` above stays populated by
# the legacy generator/data so the still-present combat scroll code keeps
# working until the ScrollSystem rewrite + combat cut land together.
@export var effect: Array = []

const TIER_KEYS := ["crit_good", "good", "bad", "crit_bad"]

# Shared 0-3 rarity ordering (Common/Uncommon/Rare/Legendary), matching PotionData.
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

# Outcome prose for a tier (crit_good/good/bad/crit_bad), or "" if absent.
func outcome_text(tier: String) -> String:
	var o = outcomes.get(tier)
	if o is Dictionary:
		return String(o.get("description", ""))
	return ""

# Structured effect list for a tier, or [] if absent.
func outcome_effects(tier: String) -> Array:
	var o = outcomes.get(tier)
	if o is Dictionary and o.get("effects") is Array:
		return o["effects"]
	return []

# Art base name, falling back to the de-spaced display name when `file` is unset.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
