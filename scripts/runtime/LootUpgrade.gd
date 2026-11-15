class_name LootUpgrade
extends RefCounted

# UPGRADE (the owner, 14 Nov 2026): "Upgrading a card in this game should be
# Upgrade 1 Loot. At the moment that includes all attacks and all weapons. It
# gives a base +1 Stun to them stacking indefinitely." Slay the Spire's Upgrade,
# translated: a piece of loot that lays Stun lays one more, per upgrade, with no cap.
#
# WHAT CAN BE UPGRADED: a WEAPON, and an ATTACK — a card the `cards` sheet tags
# `attack` (Cleave, Bullseye, Fiend Fire, Finisher, Pommel Strike, Reaper). Both
# are what lays Stun on purpose. A new kind joins by being answered in
# `can_upgrade`; every reader below asks that and nothing else.
#
# WHERE IT IS KEPT: on the PACK ENTRY, so it moves, saves and evolves with the piece
# (SaveSystem keeps `loot_items` whole).
#   stun_bonus  +Stun for the rest of the run. The key Scroll of Enchant Weapon
#               already wrote on weapons; an upgrade adds to it rather than to a
#               second key, so the weapon's +X, its swing and its evolution read
#               one number whichever door the upgrade came through.
#   stun_game   +Stun for THIS game only — Warped Tongs' "for the rest of combat".
#               Wiped by the report the moment a game ends, however it ended
#               (`clear_game_bonuses`, beside `cards_used_this_game`).
#
# WHAT IT DOES: +1 to the piece's BASE Stun. A weapon's swing lays it on top of its
# sheet's Stun (WeaponSystem.stun_parts); an attack adds it to every Stun clause's
# number BEFORE a `per` multiplies it (CardSystem.play_card) — so an upgraded
# Fiend Fire stuns 2 for each loot destroyed, not 1-each-and-one-more (the owner,
# 14 Nov 2026). A card's other clauses (Bullseye's Marked) are not Stun and do not
# grow.
#
# NO STATE LIVES HERE beyond the entry.

const RUN_KEY := "stun_bonus"
const GAME_KEY := "stun_game"

# How long an upgrade lasts.
const LASTS_RUN := "run"
const LASTS_GAME := "game"


# --- what a piece is --------------------------------------------------------

static func is_attack(entry) -> bool:
	if not (entry is Dictionary) or String(entry.get("type", "")) != "card":
		return false
	var card: CardData = CardSystem.data_for(entry)
	return card != null and card.tags.has("attack")

static func can_upgrade(entry) -> bool:
	return WeaponSystem.is_weapon(entry) or is_attack(entry)

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

# " +2" on the end of an upgraded attack's name, the way an upgraded weapon wears
# its +X (WeaponSystem.plus_suffix answers for weapons, roll and all).
static func plus_suffix(entry) -> String:
	var n: int = bonus_of(entry)
	return " +%d" % n if n > 0 else ""

# The line an upgraded attack's description ends on. "" for none.
static func card_line(entry) -> String:
	var parts: Array = []
	if run_bonus(entry) > 0:
		parts.append("Upgraded: +%d Stun to each Stun it applies." % run_bonus(entry))
	if game_bonus(entry) > 0:
		parts.append("This game: +%d Stun more." % game_bonus(entry))
	return " ".join(PackedStringArray(parts))
