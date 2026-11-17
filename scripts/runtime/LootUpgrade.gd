class_name LootUpgrade
extends RefCounted

# UPGRADE (the owner, 14 Nov 2026): "Upgrading a card in this game should be
# Upgrade 1 Loot. [...] It gives a base +1 Stun to them stacking indefinitely."
# Slay the Spire's Upgrade, translated: a piece grows by one, per upgrade, no cap.
#
# WHAT CAN BE UPGRADED (the owner, 17 Nov 2026: "Different cards can be upgraded,
# not just attacks"): a WEAPON, which grows its Stun, and a CARD whose `cards` row
# names an `Upgrade Type` (CardData.upgrade_types). The type says which of the
# card's clauses grow — `grows` below is the whole table:
#   stun     each Stun clause            (Cleave, Bullseye, Fiend Fire, …)
#   shield   each Shield it gives        (Shrug it Off, Second Wind, After Image)
#   charge   the charges it hands out    (Bloodletting, Offering)
#   potion   the potions it gives        (Alchemize)
#   loot     the loot it gives           (Prepared's card)
#   destroy  the loot it makes you destroy (Prepared)
# A card with no type ("N/A" — the Power cards, the tarot) cannot be upgraded:
# the Forge does not light it and Warped Tongs does not roll it. A new kind joins
# by being answered in `can_upgrade`; every reader below asks that and nothing else.
#
# WHERE IT IS KEPT: on the PACK ENTRY, so it moves, saves and evolves with the piece
# (SaveSystem keeps `loot_items` whole).
#   stun_bonus  +1 per upgrade for the rest of the run. The key Scroll of Enchant
#               Weapon already wrote on weapons; an upgrade adds to it rather than to
#               a second key, so the weapon's +X, its swing and its evolution read
#               one number whichever door the upgrade came through. A card keeps
#               the same key whatever its type grows — the name is history.
#   stun_game   +1 for THIS game only — Warped Tongs' "for the rest of combat".
#               Wiped by the report the moment a game ends, however it ended
#               (`clear_game_bonuses`, beside `cards_used_this_game`).
#
# WHAT IT DOES: +1 to each growing clause's BASE number, BEFORE a `per` multiplies
# it — an upgraded Fiend Fire stuns 2 for each loot destroyed, an upgraded Stack
# gives 2 Shield for each card (the owner, 14 Nov 2026). A card's other clauses
# (Bullseye's Marked, Offering's Health) do not grow.
#
# DOWNGRADED (Retro Bat's roll, docs/players-design.md §5 — any upgradeable card
# can be found at -2..+2): the same numbers, shrunk. Stun stops at 0 (it does
# nothing below that); a Shield clause GOES NEGATIVE and takes Shield away (the
# owner, 17 Nov 2026: "Block or charges can be lost through this"); the rest stop
# at 0. A lifted curse holds every clause to at least 1.
#
# NO STATE LIVES HERE beyond the entry.

const RUN_KEY := "stun_bonus"
const GAME_KEY := "stun_game"

# How long an upgrade lasts.
const LASTS_RUN := "run"
const LASTS_GAME := "game"


# --- what a piece is --------------------------------------------------------

# The card behind a pack entry, or null for anything that is not a card.
static func _card(entry) -> CardData:
	if not (entry is Dictionary) or String(entry.get("type", "")) != "card":
		return null
	return CardSystem.data_for(entry)

# A card the `cards` sheet tags `attack` — kept for what still asks about attacks
# by name; an Upgrade asks `types_of` instead.
static func is_attack(entry) -> bool:
	var card: CardData = _card(entry)
	return card != null and card.tags.has("attack")

# What an upgrade grows on this piece: ["stun"] for a weapon, the sheet's
# Upgrade Type for a card, [] for anything else.
static func types_of(entry) -> PackedStringArray:
	if WeaponSystem.is_weapon(entry):
		return PackedStringArray(["stun"])
	var card: CardData = _card(entry)
	return card.upgrade_types if card != null else PackedStringArray()

static func is_upgradeable_card(entry) -> bool:
	return _card(entry) != null and not types_of(entry).is_empty()

static func can_upgrade(entry) -> bool:
	return WeaponSystem.is_weapon(entry) or is_upgradeable_card(entry)


# --- what grows --------------------------------------------------------------

# THE KEY OF `clause` THAT `type` GROWS ("value" or "count"), or "" when the clause
# is not that type's. `clause` is a card op ({op: …}) or a passive's relic-grammar
# effect ({type: …}) — After Image grows from its trigger. Mirrored by
# tools/generate_card2_tres.py's UPGRADE_CLAUSES, which refuses a sheet row whose
# type names a clause the card does not have.
static func grows(type: String, clause: Dictionary) -> String:
	var op: String = String(clause.get("op", clause.get("type", "")))
	match type:
		"stun":
			return "value" if op == "stun" else ""
		"shield":
			return "value" if op == "gain_stat" \
				and String(clause.get("stat", "")) in ["shields", "bonus_shields"] else ""
		"charge":
			return "value" if op == "charge_pick" else ""
		"potion":
			return "count" if op == "gain_loot" \
				and String(clause.get("kind", "")) == "potion" else ""
		"loot":
			return "count" if op == "gain_loot" else ""
		"destroy":
			return "value" if op == "destroy_pick" else ""
	return ""

# Every point a card's clauses move by right now: its upgrades, and its Retro Bat
# roll (known or not — a hidden roll still lays, as a weapon's swing does).
static func delta_of(entry) -> int:
	return bonus_of(entry) + WeaponSystem.roll_of(entry)

# `clause` as `entry` plays it: the growing number moved by `delta_of`, held to its
# floor. Returns `clause` itself when nothing moves, else a copy.
static func grown(entry, clause: Dictionary) -> Dictionary:
	var delta: int = delta_of(entry)
	if delta == 0:
		return clause
	for type in types_of(entry):
		var key: String = grows(String(type), clause)
		if key == "":
			continue
		var out: Dictionary = clause.duplicate()
		var n: int = int(clause.get(key, 1)) + delta
		if bool((entry as Dictionary).get("uncursed", false)):
			n = maxi(1, n)
		elif String(type) != "shield":
			n = maxi(0, n)
		out[key] = n
		return out
	return clause

# Every carried piece an upgrade could land on, in pack order — what the Forge's
# pick lights and what Warped Tongs rolls from.
static func upgradeable() -> Array:
	var out: Array = []
	for entry in GameState.loot_items:
		if can_upgrade(entry):
			out.append(entry)
	return out


# --- how much it has ---------------------------------------------------------

static func run_bonus(entry) -> int:
	return maxi(0, int((entry as Dictionary).get(RUN_KEY, 0))) if can_upgrade(entry) else 0

static func game_bonus(entry) -> int:
	return maxi(0, int((entry as Dictionary).get(GAME_KEY, 0))) if can_upgrade(entry) else 0

# Every point of Stun upgrades have added to the piece right now.
static func bonus_of(entry) -> int:
	return run_bonus(entry) + game_bonus(entry)


# --- upgrading ---------------------------------------------------------------

# `amount` more Stun on `entry`, for the run or for this game.
static func upgrade(entry: Dictionary, amount: int = 1, lasts: String = LASTS_RUN) -> void:
	if amount <= 0 or not can_upgrade(entry):
		return
	var key: String = GAME_KEY if lasts == LASTS_GAME else RUN_KEY
	entry[key] = maxi(0, int(entry.get(key, 0))) + amount
	GameState.emit_signal("inventory_changed")

# What an upgrade says it did, for the log and the trigger's toast:
# "Cleave +1" / "Hero Sword +2 (this game)". Read after `upgrade`, so the name
# already wears the new plus.
static func did_line(entry: Dictionary, lasts: String = LASTS_RUN) -> String:
	return "Upgraded %s%s" % [LootSystem.display_name(entry),
		" for this game" if lasts == LASTS_GAME else ""]

# A game is over: every this-game upgrade goes (Warped Tongs' "for the rest of
# combat"). Erased rather than zeroed, so a piece that never had one carries no key.
static func clear_game_bonuses() -> void:
	var any: bool = false
	for entry in GameState.loot_items:
		if entry is Dictionary and (entry as Dictionary).has(GAME_KEY):
			(entry as Dictionary).erase(GAME_KEY)
			any = true
	if any:
		GameState.emit_signal("inventory_changed")


# --- in words ----------------------------------------------------------------

# " +2" on the end of an upgraded card's name, the way an upgraded weapon wears
# its +X (WeaponSystem.plus_suffix answers for weapons, roll and all).
# A rolled card (Retro Bat) wears its roll in it too, or " +1?" while hidden.
static func plus_suffix(entry) -> String:
	return WeaponSystem.plus_suffix(entry)

# What one point is, per type, for the card's own line.
const UNIT_WORDS := {
	"stun": "Stun to each Stun it applies",
	"shield": "Shield to each Shield it gives",
	"charge": "Charge to give",
	"potion": "Potion",
	"loot": "to each Loot it gives",
	"destroy": "Loot to destroy",
}

static func _per_type(types: PackedStringArray, n: int) -> String:
	var parts := PackedStringArray()
	for t in types:
		parts.append("%+d %s" % [n, UNIT_WORDS.get(String(t), String(t))])
	return ", ".join(parts)

# The line an upgraded card's description ends on. "" for none.
static func card_line(entry) -> String:
	var types: PackedStringArray = types_of(entry)
	if types.is_empty():
		return ""
	var parts: Array = []
	if run_bonus(entry) > 0:
		parts.append("Upgraded: %s." % _per_type(types, run_bonus(entry)))
	if game_bonus(entry) > 0:
		parts.append("This game: %s more." % _per_type(types, game_bonus(entry)))
	# FOUND UNIDENTIFIED (Retro Bat, docs/players-design.md §5).
	if not WeaponSystem.roll_known(entry):
		parts.append("Unidentified: -2 to +2, learned when it is %s." % (
			"first triggered" if LootPassives.is_passive(entry) else "played"))
	elif WeaponSystem.roll_of(entry) > 0:
		parts.append("Upgraded: %s." % _per_type(types, WeaponSystem.roll_of(entry)))
	elif WeaponSystem.roll_of(entry) < 0:
		parts.append(("Cursed: %s, and stuck where it sits until the curse is lifted."
			if WeaponSystem.is_cursed(entry) else "Downgraded: %s (at least 1).")
			% _per_type(types, WeaponSystem.roll_of(entry)))
	return " ".join(PackedStringArray(parts))
