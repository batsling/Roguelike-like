class_name BagData
extends Resource

# Static definition of a BAG — the seventh games-first loot kind
# (docs/loot-passives.md §6). Source-of-truth content lives in the `bags` sheet of
# tools/Roguelikes.xlsx and is generated into data/bags2.0/*.tres by
# tools/generate_bag2_tres.py.
#
# A BAG IS NOT A PIECE THAT SITS IN THE PACK: IT IS MORE PACK. The 3x3 is fixed;
# a bag is dragged onto its edge, attaches there, and every cell it covers is a
# cell loot can sit in (GameState.pack_bags). It is lifted from Backpack Battles,
# where the bags you own ARE your inventory, and it keeps that game's two rules:
# a bag can be moved and rotated at will, and what is in it moves with it.
#
# SOME BAGS ALSO DO SOMETHING, and what they do is authored in the relic grammar,
# exactly as a trinket's passive is (TrinketData) — `LootPassives.active()` hands
# every attached bag with a passive to the relic runner alongside the pieces. The
# one gate only a bag can pass is `if_in_bag`: the hook's piece was spent from one
# of THIS bag's cells (Potion Belt).

@export var id: StringName
@export var display_name: String
# "Common" | "Uncommon" | "Rare" | "Legendary" — the shared 0-3 drop ladder.
@export var rarity: String = "Common"
# The footprint as Vector2i(columns, rows), unrotated. The sheet writes it "HxW",
# ROWS FIRST, as the enemies sheet does and as the art is painted — the Potion
# Belt's "4x1" is (1, 4), standing (tools/generate_bag2_tres.py). Always a
# rectangle — Backpack Battles has L-shaped bags, this sheet does not yet.
@export var size: Vector2i = Vector2i.ONE
@export_multiline var description: String = ""
# The real game it is lifted from (the sheet's `Game` column).
@export var source_game: String = ""
# Art base name under res://images2.0/bags/.
@export var file: String = ""

# --- the passive, in ItemData's shape (see TrinketData) -------------------------
@export var triggers: Array = []
@export var stat_bonuses: Dictionary = {}
@export var status_bonuses: Dictionary = {}
# Carried so the passive shape is the one LootPassives reads everywhere; a bag
# has no neighbour to copy and the generator never writes these.
@export var copy_neighbour: String = ""
@export var bank_shields: bool = false
@export var echo_first_loot: int = 0


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


# How many cells it adds to the pack.
func cell_count() -> int:
	return size.x * size.y


# Whether it does anything beyond adding room. Leather Bag does not.
func is_passive() -> bool:
	return not triggers.is_empty() or not stat_bonuses.is_empty() \
		or not status_bonuses.is_empty()
