class_name PlayerData
extends Resource

# A PLAYER (docs/players-design.md; the owner, 13 Nov 2026) — the first of the two
# picks a run starts on, before the character. A character gives the level-up
# goal, Health, gold and starting loot; a PLAYER gives the run's MECHANICS, and
# holds the Fracture ladder (docs/fracture-design.md), which used to be per
# character.
#
# Authored on the `players` sheet of tools/Roguelikes.xlsx and generated into
# data/players/*.tres by tools/generate_player_tres.py. Every player is an
# original work, not a character from a real game.

# The mechanics a player can carry. Each is a switch a rule reads through
# `GameState.has_mechanic(...)`, so a new one is a word here, a word in the
# generator's MECHANICS, and the rule that asks for it.
#   hunger               docs/players-design.md §4 — HungerSystem
#   unidentified_weapons docs/players-design.md §5 — WeaponSystem's +/- roll
const MECHANICS := [&"hunger", &"unidentified_weapons"]

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
# The sheet's order, so the picker lists them as the sheet does (Basic first).
@export var order: int = 0
# Subset of MECHANICS. Empty = the game as it is (the basic player).
@export var mechanics: Array[StringName] = []

# The picture, by PATH, loaded on first read (CLAUDE.md: boot loads every content
# file, so a content .tres never embeds a Texture2D). "" = no art yet; the picker
# then shows the player's name in its place.
@export var portrait_path: String = ""

var _portrait: Texture2D = null

var portrait: Texture2D:
	get:
		if _portrait == null and portrait_path != "" and ResourceLoader.exists(portrait_path):
			_portrait = load(portrait_path)
		return _portrait

func has_mechanic(m: StringName) -> bool:
	return mechanics.has(m)

# A mechanic's name and the one line the picker says about it. The rules are
# code, so their words live beside the list of them rather than on the sheet.
static func mechanic_name(m: StringName) -> String:
	match m:
		&"hunger": return "Hunger"
		&"unidentified_weapons": return "Unidentified Weapons"
	return String(m).capitalize()

static func mechanic_line(m: StringName) -> String:
	match m:
		&"hunger":
			return ("Start with %d Hunger (at most %d). Each game you finish costs 1. "
				+ "Drink a potion or eat food for +1. Finish a game or lose a run "
				+ "already at 0 and lose %d Health.") % [HungerSystem.START,
					HungerSystem.MAX, HungerSystem.STARVE_DAMAGE]
		&"unidentified_weapons":
			return ("Weapons you find roll -2 to +2 Stun, unknown until the first "
				+ "swing. A minus is CURSED: stuck where it sits in the pack until "
				+ "the curse is lifted.")
	return ""
