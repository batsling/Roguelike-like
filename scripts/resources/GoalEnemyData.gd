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

# === Battlefield footprint (the sheet's Size column) ======================
# How many grid cells this enemy takes up on the battlefield. Most enemies are a
# single cell; bigger ones cover a rectangle, and a few cover a NON-rectangular
# shape inside that rectangle (Skeletal Bastion's "2x3 L 90 CC" — an L rotated a
# quarter turn counter-clockwise). A wider enemy spawns with its rightmost cell
# on the back column, so its front edge starts closer to the player and it
# strikes sooner; its whole footprint has to be clear to advance, so a big enemy
# also plugs the lanes behind it (GameLoop2 §grid).
#
# `size` keeps the raw sheet text for display; `shape_rows` x `shape_cols` is the
# BOUNDING BOX (rows first, matching the sheet's "HxW" reading) and `shape_mask`
# says which cells inside it are actually solid: one int per row, bit `c` set
# when column `c` of that row is occupied. A 2x3 L is [0b100, 0b111]:
#
#     . . #
#     # # #
#
# The art is always drawn across the full bounding box so the parts that stick
# out of the solid rows aren't cropped; only the mask blocks movement.
@export var size: String = "1x1"
@export var shape_rows: int = 1
@export var shape_cols: int = 1
@export var shape_mask: PackedInt32Array = PackedInt32Array([1])

# Hand-tuned nudge for art whose subject doesn't sit centred inside its own PNG,
# measured in GRID CELLS (x = columns, negative is toward the player; y = rows,
# negative is up). It moves only the drawing — the footprint, the badges, and
# every collision test stay on the cells the enemy actually holds — and the art
# is allowed to lean outside its bounding box rather than being cropped. Zero for
# everything that already reads straight. Set in tools/generate_goal_enemy_tres.py
# (ART_NUDGE) so it survives a regeneration from the sheet.
@export var art_offset: Vector2 = Vector2.ZERO

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

# --- footprint helpers ----------------------------------------------------

# Bounding-box height in grid cells (at least 1, so unauthored content still
# behaves like a plain 1x1).
func footprint_rows() -> int:
	return maxi(1, shape_rows)

# Bounding-box width in grid cells (at least 1).
func footprint_cols() -> int:
	return maxi(1, shape_cols)

# Whether the cell at (`r`, `c`) inside the bounding box is solid. Rows the mask
# doesn't cover fall back to "the whole row is solid", so a rectangle needs no
# mask at all.
func occupies(r: int, c: int) -> bool:
	if r < 0 or c < 0 or r >= footprint_rows() or c >= footprint_cols():
		return false
	if r >= shape_mask.size():
		return true
	return (int(shape_mask[r]) & (1 << c)) != 0

# Every solid cell as a Vector2i(column offset, row offset) from the footprint's
# top-left corner — what the grid model tests for collisions and the battlefield
# draws frames under.
func footprint_cells() -> Array:
	var out: Array = []
	for r in range(footprint_rows()):
		for c in range(footprint_cols()):
			if occupies(r, c):
				out.append(Vector2i(c, r))
	return out
