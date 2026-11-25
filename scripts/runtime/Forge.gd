class_name Forge
extends RefCounted

# FORGE — Slay the Spire 2's Regent keyword, the owner's version (25 Nov 2026):
# "if you don't have a Sovereign Blade then you create one with 1 stun, but further
# forges will add stun". Asked how big a first forge makes the blade, the owner
# chose "1 + the forge": Forge N with no blade in the pack makes a blade of 1 + N
# Stun (Bulwark's Forge 2 makes a 3-Stun blade); Forge N with one adds N to it.
#
# What carries Forge: Wrought in War and Bulwark (the `forge N` card op,
# CardSystem), Seeking Edge's one use (the same op), and Furnace's
# `game_won every=2: forge 1` (the relic-grammar `forge` verb, EffectSystem).
#
# THE STUN IS AN UPGRADE (LootUpgrade): +N on the blade's pack entry, the key an
# Upgrade and a Scroll of Enchant Weapon already write, so the blade wears "+N",
# saves it, and swings with it like any upgraded weapon. Every blade in the pack
# takes it — Slay the Spire forges every Sovereign Blade you hold.
#
# THE BLADE IS ONLY MADE HERE and by the Regent's start: its rarity is N/A, which
# no roll finds (WeaponData.is_findable). It arrives EMPTY like any weapon and is
# charged by its own goal. Into the pack where it fits; a full pack is asked about
# on the drop screen (GameState.offer_loot_entries), never lost.
#
# docs/loot-passives.md §22.

const BLADE := &"sovereign_blade"

# Every Sovereign Blade in the pack, as its live entry.
static func blades() -> Array:
	var out: Array = []
	for entry in GameState.loot_items:
		if WeaponSystem.is_weapon(entry) and StringName(entry.get("id", "")) == BLADE:
			out.append(entry)
	return out

# Forge `amount`. Returns what happened, for the log and the trigger's toast; ""
# when nothing could (no amount, or no blade authored).
static func forge(amount: int) -> String:
	if amount <= 0:
		return ""
	var held: Array = blades()
	if held.is_empty():
		var w: WeaponData = Data.get_weapon(BLADE)
		if w == null:
			return ""
		# Never rolled unidentified: it is made, not found.
		var entry: Dictionary = WeaponSystem.new_entry(w, false)
		entry[LootUpgrade.RUN_KEY] = amount
		if not GameState.take_loot_entry(entry):
			GameState.offer_loot_entries([entry])
		var line: String = "Forge %d: a Sovereign Blade is made (Stun %d)" % [amount, w.stun + amount]
		GameLog.add(line + ".", UITheme.GOLD)
		return line
	for entry in held:
		LootUpgrade.upgrade(entry, amount)
	var line2: String = "Forge %d: Sovereign Blade +%d Stun" % [amount, amount]
	GameLog.add(line2 + ".", UITheme.GOLD)
	return line2
