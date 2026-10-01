class_name WeaponData
extends Resource

# Static definition of a WEAPON — the eighth games-first loot kind
# (docs/loot-passives.md §12). Source-of-truth content lives in the `weapons`
# sheet of tools/Roguelikes.xlsx and is generated into data/weapons2.0/*.tres by
# tools/generate_weapon_tres.py.
#
# A WEAPON IS A PIECE YOU SWING, AND ITS GOAL IS WHAT LOADS IT. It sits in the
# pack like a trinket (it has a footprint and neighbours), it is used like a wand
# (it is aimed at the board and not spent), and it charges off its own GOAL: while
# a game is in play, ticking the weapon's goal is +1 Charge, at most once per game
# played — and a LOST game still pays it, because the goal was still done. At
# `max_charges` it can be swung, and a swing spends them all.
#
# Anything else that charges loot charges it too (Charged Penny, Hairpin, 48 Hour
# Energy, a Fanny Pack) — GameState.chargeable_things.

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the shared 0-3 drop ladder.
@export var rarity: String = "Common"
# Pack footprint as Vector2i(columns, rows), unturned. The sheet writes "HxW",
# ROWS FIRST, as trinkets and bags do: Hero Sword's "2x1" is (1, 2), standing.
@export var size: Vector2i = Vector2i.ONE

# --- the swing ------------------------------------------------------------------
# WHERE IT MAY BE AIMED (the sheet's `Aim`): "any", "front", "back", "column",
# "enemy", "none" or "random". "column" carries its number in `aim_column`;
# "random" needs no click — each strike picks a random enemy on the board.
@export var aim: String = "any"
@export var aim_column: int = 0
# WHAT IT HITS, measured from the square aimed at (the sheet's `Area`), kept as
# authored and read by WeaponArea: a word (cell, row, col, cross, 3x3, 5x5,
# board, plus, diagonals), a rectangle "RxC", or a drawn shape ".#./#O#/.#.".
@export var area: String = "cell"
# Stun laid on every enemy the area covers, ONCE per enemy however many of its
# squares are covered. Before the pack's bonuses (WeaponSystem.stun_for).
@export var stun: int = 0
# After the Stun, every enemy covered is shoved `push` squares toward `push_dir`
# ("right" away from you, "left" toward you, "up", "down") — Hero Longsword's
# `push right 1`. Free, and as far as it fits (GameLoop2.shove). 0 for no push.
@export var push_dir: String = ""
@export var push: int = 0
# The sheet's `Type`: "melee" or "ranged".
@export var weapon_type: String = "melee"

# --- charging -------------------------------------------------------------------
# The goal that charges it — the sheet's `Goal` column, which `goals` writes
# (tools/apply_goals_sheet.py). Shown on the report checklist while it is carried.
@export var goal: String = ""
# Charges a swing needs, and spends.
@export var max_charges: int = 3

# --- the passive, in ItemData's shape (see TrinketData) --------------------------
# The sheet's `Passive` is the prose; `Passive Effect` is compiled into these.
@export_multiline var description: String = ""
@export var triggers: Array = []
@export var stat_bonuses: Dictionary = {}
@export var status_bonuses: Dictionary = {}
# The Hero swords: weapons in these directions swing with +amount Stun.
@export var weapon_stun: Dictionary = {}
# Stankus' Toothpick: +amount Stun on its OWN swing for every `per` foods touching it.
@export var stun_per_food: Dictionary = {}
# Lightning Ring / Thunder Loop: every swing leaves it +amount Replay, up to `max`
# ({amount, max}). Each Replay is one more strike per swing; the count is kept on
# the pack entry (`replays`), so it rides an evolution.
@export var replay_gain: Dictionary = {}
# Carried so a weapon could author Duplicator's rule too (TrinketData's shape).
@export var weapon_retrigger: Dictionary = {}
# Carried so the passive shape is the one LootPassives reads everywhere.
@export var copy_neighbour: String = ""
@export var bank_shields: bool = false
@export var echo_first_loot: int = 0

@export var source_game: String = ""
@export var tags: PackedStringArray = PackedStringArray()
# Art base name under res://images2.0/weapons/.
@export var file: String = ""


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


func art_file() -> String:
	return file if file != "" else display_name.replace(" ", "").replace("'", "")


# Whether it does anything from its slot beyond being swung. Lil' Bomber does not.
func is_passive() -> bool:
	return not triggers.is_empty() or not stat_bonuses.is_empty() \
		or not status_bonuses.is_empty() or not weapon_stun.is_empty() \
		or not stun_per_food.is_empty() or not replay_gain.is_empty() \
		or not weapon_retrigger.is_empty()
