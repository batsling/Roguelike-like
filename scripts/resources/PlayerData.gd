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

# The mechanics that have RULES. Each is a switch a rule reads through
# `GameState.has_mechanic(...)`. Their names and what each says to the player are
# rows of the `mechanics` sheet (MechanicData, `Data.get_mechanic`), and a player
# carries any mix of them; a new one is a row there, a word here, and the rule
# that asks for it. tools/generate_mechanic_tres.py prints a note for a row that
# is not in this list.
#   hunger               docs/players-design.md §4 — HungerSystem
#   unidentified_weapons docs/players-design.md §5 — WeaponSystem's +/- roll
const MECHANICS := [&"hunger", &"unidentified_weapons"]

@export var id: StringName
@export var display_name: String
# The sheet's order, so the picker lists them as the sheet does (Basic first).
@export var order: int = 0
# Subset of MECHANICS. Empty = the game as it is (the basic player).
@export var mechanics: Array[StringName] = []

# The picture, by PATH, loaded on first read (CLAUDE.md: boot loads every content
# file, so a content .tres never embeds a Texture2D). "" = no art yet; the picker
# then shows the player's name in its place.
@export var portrait_path: String = ""

# The small token, by path the same way: drawn beside the character's in the
# page header. Its own file (Icon/) where the full picture does not read small,
# else the same picture as `portrait_path`.
@export var icon_path: String = ""

# WHERE A HAT SITS on the full picture (docs/customization.md §7; HatArt): x, y,
# width and tilt, in percent of the picture (the tilt in degrees). A width of 0 is
# no spot: a player without one wears nothing. The small token never wears a hat
# (the owner, 14 Nov 2026: "icon shouldn't have a hat").
@export var hat_spot: Vector4 = Vector4.ZERO

var _portrait: Texture2D = null
var _icon: Texture2D = null

# THE PICTURE AS WORN: the player in the hat they have on (Cosmetics.hat), else
# their own art. Every screen that shows the player's full picture as THEMSELVES —
# the picker, the hero on the board — draws this, never `portrait`, the way a
# character is drawn through `shown_portrait()`. An achievement (a player still to
# unlock) keeps the bare picture, and the header's token (`icon`) is always bare.
func shown_portrait() -> Texture2D:
	return Cosmetics.player_art(self)

var icon: Texture2D:
	get:
		if _icon == null and icon_path != "" and ResourceLoader.exists(icon_path):
			_icon = load(icon_path)
		return _icon if _icon != null else portrait

var portrait: Texture2D:
	get:
		if _portrait == null and portrait_path != "" and ResourceLoader.exists(portrait_path):
			_portrait = load(portrait_path)
		return _portrait

func has_mechanic(m: StringName) -> bool:
	return mechanics.has(m)

# A mechanic's name and the one line the picker says about it: both are the
# `mechanics` sheet's (the owner, 14 Nov 2026), so the words are the owner's to
# edit. The numbers in Hunger's sentence are typed there; test_players.gd holds
# them to HungerSystem's.
static func mechanic_name(m: StringName) -> String:
	var d: MechanicData = Data.get_mechanic(m)
	return d.display_name if d != null else String(m).capitalize()

static func mechanic_line(m: StringName) -> String:
	var d: MechanicData = Data.get_mechanic(m)
	return d.description if d != null else ""
