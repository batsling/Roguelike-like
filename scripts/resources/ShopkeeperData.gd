class_name ShopkeeperData
extends Resource

# ONE SHOPKEEPER: who stands behind a Shop node's counter (docs/games-first-redesign.md
# §14.6). Every Shop node in a run is dealt one at random from the roster, no
# repeats while the roster lasts (ShopSystem.keeper_for); with an empty roster
# every shop is the plain one, which is what it always was.
#
# Source of truth is the `shopkeepers` sheet of tools/Roguelikes.xlsx, generated
# into data/shopkeepers/*.tres by tools/generate_shopkeeper_tres.py. Edit the
# sheet, not these.
#
# THE RULE FIELDS ARE ALL "BLANK MEANS THE ORDINARY SHOP", so a keeper is a plain
# shop with a name and a face until a column says otherwise. ShopSystem reads each
# one at the moment it rolls, prices or sells a shelf; nothing else in the game
# needs to know a keeper is there.

@export var id: StringName
@export var display_name: String = ""
# The game this keeper comes from, or &"" for one of the game's own.
@export var game_id: StringName = &""
# The one line the pop-up shows under the name.
@export var description: String = ""
# Base name of the portrait under images2.0/shopkeepers/ (no extension). Blank
# shows no portrait, and so does a name with no file behind it yet.
@export var image: String = ""

# WHAT THE ITEMS ROW STOCKS: item pools or tags (`shop`, `food`, `blood`…). An
# item matching ANY of them can be drawn; blank is the whole catalog. When none of
# the rolled rarity match, the draw widens to every rarity, then to the whole
# catalog, so a narrow keeper still fills the shelf.
@export var pools: PackedStringArray = PackedStringArray()
# WHAT THE LOOT ROW STOCKS: loot kinds (GameState.LOOT_KINDS — potion, wand, pill…).
# Blank is the ordinary drop mix.
@export var loot_kinds: PackedStringArray = PackedStringArray()

# What a price is paid in: &"gold", or &"health" (Health leaves the player, and a
# price is only affordable while it would leave at least 1).
@export var currency: StringName = &"gold"

# SALES, one clause each, `<amount> <target>`:
#   amount  -N | +N | half | free
#   target  all | items | loot | a rarity (common … legendary) | a loot kind |
#           an item pool or tag
# So "-1 loot", "half rare", "-2 food". Applied in order on top of the going rate
# (ShopSystem.price_for, which already carries a Fracture's surcharge). A price
# never drops below 0, and "free" is 0.
@export var sale: PackedStringArray = PackedStringArray()

# FREE-FORM RULE TOKENS for what the columns above do not cover (buys curses, the
# first piece free, the shelf grows as you spend). Nothing reads any yet; a rule
# that gets built asks ShopSystem.keeper_has(node, token).
@export var effect: PackedStringArray = PackedStringArray()

# How many items and pieces of loot the shelf holds (ShopSystem.STOCK_SLOTS /
# LOOT_SLOTS when the sheet leaves them blank). 0 is a row with nothing on it.
@export var item_slots: int = 3
@export var loot_slots: int = 3

const PORTRAIT_DIR := "res://images2.0/shopkeepers/"

# The portrait, or null. Loaded on demand rather than exported as a texture, for
# the reason GameData.cover_image is: Data loads the whole roster at boot.
func portrait() -> Texture2D:
	if image == "":
		return null
	var path := PORTRAIT_DIR + image + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func pays_in_health() -> bool:
	return currency == &"health"
