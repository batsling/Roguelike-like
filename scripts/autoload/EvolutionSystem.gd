extends Node

# Autoload. Performs irreversible weapon-card EVOLUTIONS driven by
# EvolutionCatalog (generated from the Excel `Evolutions` sheet). An evolution
# transforms a base card in the deck into a stronger named form the instant the
# player meets both of its requirements — e.g. owning Lil' Bomber + any Crown
# item swaps every Lil' Bomber in the deck to King Bomber.
#
# Design (per the design brief):
#   • Trigger is INSTANT: we listen on GameState.deck_changed / inventory_changed
#     and re-check after every deck/inventory mutation, in either acquisition
#     order (get the crown first, or the card first — whichever completes 2/2).
#   • The swap is IRREVERSIBLE: it replaces the CardInstance's CardData pointer
#     in place, so the base form is gone from the deck. Losing the crown
#     afterwards never reverts it (King Bomber simply has no requirement to lose).
#   • A player-facing notification fires the moment an evolution completes.
#
# The catalog is the single source of truth; adding a new evolution is a row in
# the sheet + its art in images/Evolutions/, no code change here.

# Re-entrancy guard: swapping cards re-emits deck_changed, which would re-enter
# this checker. The guard makes the nested call a no-op (the swap already
# removed the base card, so a re-check would find nothing anyway).
var _checking: bool = false


func _ready() -> void:
	GameState.deck_changed.connect(_check)
	GameState.inventory_changed.connect(_check)


# Public so a scene can force a re-check (e.g. after a bulk deck rebuild that
# suppressed the per-change signal). Idempotent.
func check_all() -> void:
	_check()


func _check() -> void:
	if _checking:
		return
	_checking = true
	for evo in EvolutionCatalog.EVOLUTIONS:
		_try_evolve(evo)
	_checking = false


func _try_evolve(evo: Dictionary) -> void:
	var from_id: StringName = StringName(String(evo.get("from_card", "")))
	var to_id: StringName = StringName(String(evo.get("to_card", "")))
	if from_id == &"" or to_id == &"":
		return
	if not _deck_has(from_id):
		return
	if not _req2_met(evo):
		return
	var to_card: CardData = Data.get_card(to_id)
	if to_card == null:
		return
	var swapped: int = 0
	for ci in GameState.deck:
		if ci is CardInstance and ci.data != null and ci.data.id == from_id:
			# Swap only the card IDENTITY (its CardData), preserving every
			# per-instance buff the base card accumulated: persistent effect
			# bonuses (weapon verifications / "+N Dmg" gains), the upgrade flag,
			# and any Vorpal roll (e.g. a future Scroll of Vorpalize Weapon stamps
			# vorpal_type/weight straight onto the instance, so it carries here).
			# The evolved card's effect layout matches the base (same dmg effect at
			# index 0, gold rider merged onto it), so index-keyed effect_bonuses
			# still land on the right effect.
			ci.data = to_card
			swapped += 1
	if swapped <= 0:
		return
	# Re-point any id-specific buffs from the base card onto the evolved one so
	# they follow the evolution. Today that's the active combat scene's per-id
	# card boosts; the card_evolved signal lets any future per-card-id buff store
	# (card-specific buffs, etc.) remap itself the same way.
	_remap_id_buffs(from_id, to_id)
	var evolved_name: String = String(evo.get("name", String(to_id)))
	var base_label: String = String(evo.get("req1_label", String(from_id)))
	Notifications.notify("%s evolved into %s!" % [base_label, evolved_name],
		Color(1.0, 0.8, 0.3))
	GameLog.add("⭐ %s evolved into %s!" % [base_label, evolved_name],
		Color(1.0, 0.85, 0.4))
	# Surface the swap to every listener (hand views, backpack, collection).
	GameState.emit_signal("deck_changed")
	# Broadcast the identity change so any system that keys off a card id can
	# follow it (Stats card boosts already do via the remap above; future
	# per-card-id buff stores can connect to this).
	GameState.emit_signal("card_evolved", from_id, to_id)


# Re-point id-specific buffs from `from_id` onto `to_id`. The only id-keyed buff
# store today is the active combat scene's `card_boosts` (a boost authored with
# match_id targets a card by id, e.g. "all Lil' Bombers gain +2 Dmg"); rewriting
# the id keeps the boost applying to the evolved card. Instance-level buffs
# (effect_bonuses, Vorpal) travel on the CardInstance itself and need no remap.
func _remap_id_buffs(from_id: StringName, to_id: StringName) -> void:
	var scene = GameState.combat_scene
	if scene == null or not ("card_boosts" in scene):
		return
	var from_s: String = String(from_id)
	var to_s: String = String(to_id)
	for boost in scene.card_boosts:
		if typeof(boost) == TYPE_DICTIONARY and String(boost.get("match_id", "")) == from_s:
			boost["match_id"] = to_s


func _deck_has(card_id: StringName) -> bool:
	for ci in GameState.deck:
		if ci is CardInstance and ci.data != null and ci.data.id == card_id:
			return true
	return false


# True when the player satisfies an evolution's second requirement. The catalog
# encodes it as either an item TAG ("Any Crown Item" -> any owned item tagged
# "crown") or a specific item ID. The equipped weapon slot counts too.
func _req2_met(evo: Dictionary) -> bool:
	var kind: String = String(evo.get("req2_kind", ""))
	var val: String = String(evo.get("req2_value", ""))
	if val == "":
		return false
	match kind:
		"item_tag":
			for it in GameState.inventory:
				if it is ItemData and it.tags.has(val):
					return true
			if GameState.equipped_weapon is ItemData and GameState.equipped_weapon.tags.has(val):
				return true
			return false
		"item_id":
			for it in GameState.inventory:
				if it is ItemData and String(it.id) == val:
					return true
			if GameState.equipped_weapon is ItemData and String(GameState.equipped_weapon.id) == val:
				return true
			return false
	return false
