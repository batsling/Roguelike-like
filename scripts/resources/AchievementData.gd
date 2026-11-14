class_name AchievementData
extends Resource

# ONE ACHIEVEMENT (docs/achievements.md; the owner, 10 Nov 2026): something the
# player does that unlocks something — a CHARACTER, a PLAYER or a special HAT.
# The screen files it under the tab named here, so a later kind of unlock is a new
# tab and a new field rather than a new screen.
#
# GENERATED from the `achievements` sheet by tools/generate_achievement_tres.py;
# a field added here goes into the generator in the same commit.
#
# The rules that read these are `scripts/runtime/Achievements.gd`; what the player
# has done toward each is kept per profile in `GameStats.achievements`.

@export var id: StringName = &""

# The tab of the Achievements screen this is filed under, and where in it.
@export var tab: String = "Characters"
@export var order: int = 0

# The character this unlocks (a CharacterData id). A character named by an
# achievement is LOCKED in the character picker until it is done.
@export var unlocks_character: StringName = &""
# Under the `Players` tab: the player it unlocks (docs/players-design.md), and
# unlocks_character is empty. One or the other, never both.
@export var unlocks_player: StringName = &""
# Under the `Hats` tab: the special hat it unlocks, by its CosmeticCatalog key
# (`hat/abandon_hat`; docs/customization.md §7). The other two are empty.
@export var unlocks_cosmetic: String = ""

# What the player reads: the condition, in one sentence.
@export_multiline var description: String = ""

# HOW IT IS COUNTED, which is also what the screen says beside the number:
#   run       it has to happen inside one run; the BEST run is remembered
#   lifetime  it adds up across every run; nothing is lost when a run ends
@export_enum("run", "lifetime") var scope: String = "run"

# WHAT IS COUNTED (Achievements.measure):
#   tagged_held  how many DIFFERENT relics and pieces of loot carrying `tag` the
#                run is holding at once
#   perfects     how many DIFFERENT games have been perfected
#   games_beaten how many DIFFERENT games have been beaten — of `game_type`
#                (GameData.GameType by name, lower case) when one is given
#   escape_streak how many games in a row the run has escaped
#                (GameState.escape_streak)
@export_enum("tagged_held", "perfects", "games_beaten", "escape_streak") var metric: String = "tagged_held"
@export var tag: String = ""
@export var game_type: String = ""

# How many it takes.
@export var goal: int = 1

func is_run_scope() -> bool:
	return scope == "run"
