class_name GoalEnemyData
extends Resource

# Static definition of a GOAL-ENEMY — the games-first redesign's replacement for
# the combat enemy stat block (docs/games-first-redesign.md §7). One goal-enemy
# is rolled per game the player picks, filtered by the game's Type and the run's
# Difficulty tier (reusing EnemySpawner's tier logic). It is NOT a combatant:
# there is no simulated combat. Instead it carries a single GOAL the player must
# accomplish while actually playing that real roguelike. Meeting the goal defeats
# the enemy and drops its item; failing to meet it stacks the enemy, which then
# hits the player for `damage` after each game beaten until its goal is fulfilled.
#
# Source-of-truth content lives in the `enemies2.0` sheet of
# tools/Roguelikes.xlsx and is generated into data/enemies2.0/*.tres by
# tools/generate_goal_enemy_tres.py. This is a distinct resource from the combat
# EnemyData (which is slated for the archive cut, §11) so goal-enemies carry none
# of the dead combat fields.

@export var id: StringName
@export var display_name: String

# The game TYPE this enemy spawns on — Action / Deckbuilder / Traditional /
# Strategy (§6.1). Determines which type's goal pool it was rolled from. Stored
# lowercased for stable matching against GameData's type.
@export var game_type: StringName = &""

# Tier gate — Low / Medium / High / Insane (mapped to the shared RunDifficulty
# tiers so it reuses the tier logic). This is WHEN the enemy appears, separate
# from whether it's a boss (see `boss` below) — bosses carry their own tier too.
enum Difficulty { LOW, MEDIUM, HIGH, INSANE }
@export var difficulty: Difficulty = Difficulty.LOW

# True for bosses2.0 content — a heavier enemy that appears on a difficulty-tier
# change (§7.1): more damage (above the 1-3 band), a tighter goal, and immune to
# bombs (only its goal removes it). Normal goal-enemies leave this false.
@export var boss: bool = false

# The real roguelike this enemy references (the sheet's Game column, e.g.
# "Slay the Spire", "Brotato"). Informational / flavour on the HUD.
@export var source_game: String = ""

# Enemy HP — 1 across the current roster, so a single Bomb removes one normal
# enemy (§4). Bosses will be bomb-immune (handled by the boss layer, not here).
@export var health: int = 1

# Per-game hit dealt while this enemy is stacked (unfulfilled), tracking the tier
# (Low 1 / Medium 2 / High 3, §3). Absorbed by Block, then Health.
@export var damage: int = 1

# Goal Type — Bounty (defeat a specific in-game enemy) / Restriction (a
# self-imposed rule) / Discovery (witness/experience something). See §7.
@export var goal_type: StringName = &""
# The challenge text shown to the player and the OBS viewer (§9).
@export var goal: String = ""

# Optional special ability id — all "N/A" in the current roster; reserved for a
# later specials pass (§12.3). Empty when absent.
@export var ability: StringName = &""

# Synergy tag linking the enemy to items/goals sharing it (e.g. `alien` ties the
# Baby Alien enemy to the Alien Baby item and an "defeat an alien" bounty, §7).
@export var tag: StringName = &""

# Art base name under res://images2.0/enemies/ (the sheet's File column). Resolves
# to images2.0/enemies/<file>.png; falls back to a placeholder when missing (§10.1).
@export var file: String = ""
@export var image: Texture2D

# Shared 0-3 tier ordering (Low/Medium/High/Insane), matching RunDifficulty.Tier
# so a game's tier and an enemy's tier compare directly.
func tier_index() -> int:
	match difficulty:
		Difficulty.MEDIUM:
			return 1
		Difficulty.HIGH:
			return 2
		Difficulty.INSANE:
			return 3
		_:
			return 0

func is_boss() -> bool:
	return boss

# Art base name, falling back to the de-spaced display name when `file` is unset.
func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")
