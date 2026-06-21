class_name CardInstance
extends RefCounted

# Runtime wrapper around a CardData. Holds per-card transient state
# (upgraded form, temporary cost overrides, etc.). The deck stores
# CardInstance refs; saves serialize them back to ids + upgrade flag.

var data: CardData = null
var upgraded: bool = false
var temp_cost_override: int = -999      # -999 sentinel = no override

# Per-combat additive cost change (negative = discount). Empty Tome grants a
# random Weapon Attack card -1 cost for the fight; because action-mode cooldown
# is derived from cost, the same discount shortens its cooldown there too. Reset
# to 0 at the start of every combat in each scene's _init_deck (and cleared on
# combat end) so it never leaks into the persistent deck. Distinct from
# temp_cost_override, which is an absolute per-turn override (Mummified Hand).
var combat_cost_delta: int = 0

# Persistent additive bonuses to specific effect fields, set by weapon
# verification (and any future "this card permanently gains +N" hook).
# Shape: { effect_index(int) -> { field(String) -> bonus(int) } }
# For Bag o' Glitter after a +1 Blind verification:
#   { 0: { "stacks": 1 } }
var effect_bonuses: Dictionary = {}

# If this card was granted by a weapon item, the item's instance_id.
# Drives the bidirectional pairing — removing the weapon removes this
# card; removing this card removes the weapon. 0 = not weapon-linked.
var source_weapon_id: int = 0

# Games beaten while this card has been in the deck. Drives the
# destroy_after_games lifecycle (Guilty self-destructs after 3). Bumped by
# GameState on TriggerBus.game_beaten; ignored when data.destroy_after_games < 0.
var games_beaten_held: int = 0

# Vorpal addon state — rolled ONCE per physical card and persisted with the
# deck (saved/loaded). A Vorpal weapon binds to a random combat type (which of
# the three modes — Stats.Mode int) and a random weight class (1-5), and deals
# Stats.VORPAL_BONUS extra damage when used in the matching mode against an
# enemy whose weight matches. -2 = not yet rolled (rolled lazily / on acquire);
# -1 = the card has no Vorpal addon (never bonuses).
var vorpal_type: int = -2
var vorpal_weight: int = 0

# Shared RNG for the once-per-instance Vorpal roll when a caller doesn't hand
# one in (e.g. acquisition outside combat). Roll is persisted, so determinism
# across a save round-trip is irrelevant — it only fires once.
static var _vorpal_rng: RandomNumberGenerator = null

static func from_data(d: CardData, is_upgraded: bool = false) -> CardInstance:
	var c := CardInstance.new()
	c.data = d
	c.upgraded = is_upgraded
	return c

func get_cost() -> int:
	if temp_cost_override != -999:
		return temp_cost_override
	# X-cost cards (effective cost -1) ignore the combat delta — they spend all
	# energy regardless, and the discount targets fixed-cost cards.
	var base: int = data.get_effective_cost(upgraded)
	if base < 0:
		return base
	return maxi(0, base + combat_cost_delta)

# --- Vorpal -----------------------------------------------------------------

func has_vorpal() -> bool:
	return data != null and data.addons.has("vorpal")

# Roll this card's Vorpal type/weight if it carries the addon and hasn't rolled
# yet. Safe to call repeatedly — the -2 sentinel guards the one-time roll, so
# acquisition and a lazy combat-time fallback both land on the same result.
func roll_vorpal_if_needed(rng: RandomNumberGenerator = null) -> void:
	if vorpal_type != -2:
		return
	if not has_vorpal():
		vorpal_type = -1          # mark "no Vorpal" so we never re-check the addon list
		return
	var r: RandomNumberGenerator = rng
	if r == null:
		if _vorpal_rng == null:
			_vorpal_rng = RandomNumberGenerator.new()
			_vorpal_rng.randomize()
		r = _vorpal_rng
	# Combat type = one of the three modes (Stats.Mode: DECKBUILDER/ACTION/STRATEGY).
	vorpal_type = r.randi_range(0, 2)
	vorpal_weight = r.randi_range(1, 5)

# Stamp this instance's rolled Vorpal type/weight onto an outgoing effect dict so
# the per-mode damage path (Stats.vorpal_damage_bonus) can apply the bonus. Returns
# the original dict untouched when the card has no live Vorpal roll.
func apply_vorpal_to_effect(effect: Dictionary) -> Dictionary:
	roll_vorpal_if_needed()
	if vorpal_type < 0 or vorpal_weight <= 0:
		return effect
	var dup: Dictionary = effect.duplicate()
	dup["vorpal_type"] = vorpal_type
	dup["vorpal_weight"] = vorpal_weight
	return dup

# Human-readable suffix for the card name/description (mirrors the legacy badge).
func vorpal_badge() -> String:
	roll_vorpal_if_needed()
	if vorpal_type < 0 or vorpal_weight <= 0:
		return ""
	const MODE_NAMES := ["Deckbuilder", "Action", "Strategy"]
	var mode_name: String = MODE_NAMES[vorpal_type] if vorpal_type < MODE_NAMES.size() else "?"
	return "[Vorpal vs %s W%d]" % [mode_name, vorpal_weight]

func get_effects() -> Array:
	# Layer per-instance effect_bonuses on top of CardData's effects
	# without mutating the shared Resource, then append any item-granted
	# effects (Brass Knuckles etc.). Empty bonuses + no grants returns the
	# base array directly so the hot path stays allocation-free.
	var base: Array = data.get_effective_effects(upgraded)
	# No per-instance bumps: CardMods folds in item boosts + appended grants
	# (and short-circuits to `base` untouched when neither applies).
	if effect_bonuses.is_empty():
		return CardMods.resolved_effects(base, data)
	# Layer this instance's persistent effect_bonuses onto a duplicated base
	# first (weapon verifications), then hand off to CardMods for the shared
	# item boost/grant pass.
	var bumped: Array = []
	for i in range(base.size()):
		var e: Dictionary = (base[i] as Dictionary).duplicate()
		if effect_bonuses.has(i):
			for field in effect_bonuses[i].keys():
				e[field] = int(e.get(field, 0)) + int(effect_bonuses[i][field])
		bumped.append(e)
	return CardMods.resolved_effects(bumped, data)

# Out-of-combat text: no player scaling, but item boosts that raise the card's
# own numbers (Strike Dummy: +3 Dmg) are still folded in so the shown number is
# the real one everywhere (shop / rest / collection). Plain (no BBCode).
func get_description() -> String:
	return _decorate(CardScaling.scale_text(
		data.get_effective_description(upgraded), null, false, data))

# Like get_description, but with the card's Dmg / Block / inflicted-status
# numbers rewritten to reflect `player`'s live combat scaling (Power / Arcane /
# Defense / Persistence) on top of any item boosts — see CardScaling. Used by the
# in-combat hand view so the displayed numbers match what actually resolves.
# `rich` toggles BBCode colouring.
func combat_description(player, rich: bool = true, target = null) -> String:
	return _decorate(CardScaling.scale_text(
		data.get_effective_description(upgraded), player, rich, data, target))

# Appends the item-driven addenda (card_played trigger preview, granted effects,
# granted boosts, weapon effect_bonuses) onto a base description string. Shared
# by get_description and combat_description so the two read identically apart
# from the scaled numbers.
func _decorate(base: String) -> String:
	# Tack on any item-driven card_played triggers whose filter matches
	# this card, so e.g. Bird Head ("strikes inflict Soul Link") makes
	# every Strike-tagged card visibly read "Deal 6 Dmg Melee. Inflict
	# Soul Link." in hand, shop, rest site, etc.
	var trigger_extra: String = _format_card_played_trigger_addendum()
	if trigger_extra != "":
		base = "%s %s" % [base, trigger_extra]
	# Item "card gains effect" grants (Brass Knuckles -> "Inflict Bruise.").
	var grant_extra: String = CardMods.describe(data)
	if grant_extra != "":
		base = "%s %s" % [base, grant_extra]
	# Vorpal: show this physical card's rolled type/weight so the player knows
	# which mode + enemy weight earns the bonus.
	var vorpal_extra: String = vorpal_badge()
	if vorpal_extra != "":
		base = "%s  %s" % [base, vorpal_extra]
	# NOTE: item boosts (Strike Dummy) are NOT annotated here — CardScaling folds
	# them straight into the card's Dmg/Block number, so "Deal 9 Dmg" already
	# reflects the +3 instead of trailing a separate "[+3 Dmg]".
	if effect_bonuses.is_empty():
		return base
	# Annotate with a compact bonus summary so the player sees what the
	# weapon has gained. Format mirrors a quick "Bag o' Glitter +1 stacks"
	# style; the underlying effects already use the bumped numbers.
	var parts: Array = []
	for i in effect_bonuses.keys():
		for field in effect_bonuses[i].keys():
			var v: int = int(effect_bonuses[i][field])
			parts.append("+%d %s" % [v, field] if v >= 0 else "%d %s" % [v, field])
	if parts.is_empty():
		return base
	return "%s  [%s]" % [base, ", ".join(parts)]

# Walks GameState.inventory + equipped_weapon and returns a description
# fragment for every card_played item trigger whose `if_card_tag` /
# `if_card_id` filter would let it fire on this card. Returns "" if
# nothing applies. Mirrors the gate logic in
# DeckbuilderCombat._fire_item_triggers — keep the two in sync.
func _format_card_played_trigger_addendum() -> String:
	if data == null:
		return ""
	var sources: Array = []
	sources.append_array(GameState.inventory)
	if GameState.equipped_weapon != null:
		sources.append(GameState.equipped_weapon)
	if sources.is_empty():
		return ""
	var fragments: PackedStringArray = PackedStringArray()
	for item in sources:
		if not (item is ItemData):
			continue
		for trig in item.triggers:
			if String(trig.get("on", "")) != "card_played":
				continue
			var tag_gate: String = String(trig.get("if_card_tag", ""))
			if tag_gate != "" and not data.tags.has(tag_gate):
				continue
			var id_gate: String = String(trig.get("if_card_id", ""))
			if id_gate != "" and String(data.id) != id_gate:
				continue
			for effect in trig.get("effects", []):
				var phrase: String = CardMods._effect_to_phrase(effect)
				if phrase != "":
					fragments.append(phrase)
	if fragments.is_empty():
		return ""
	return " ".join(fragments)

func bump_effect(effect_index: int, field: String, amount: int) -> void:
	# Mutate this instance's persistent bonus. Adds to any existing bonus
	# on the same (effect, field) pair so multiple verifications stack.
	if amount == 0:
		return
	if not effect_bonuses.has(effect_index):
		effect_bonuses[effect_index] = {}
	var f: Dictionary = effect_bonuses[effect_index]
	f[field] = int(f.get(field, 0)) + amount

func get_display_name() -> String:
	if upgraded:
		return data.display_name + "+"
	return data.display_name

func is_attack() -> bool:
	return data.is_attack()

func is_skill() -> bool:
	return data.is_skill()

func is_power() -> bool:
	return data.is_power()

func wants_target() -> bool:
	# A card needs a single-enemy target if any of its effects has
	# target = "enemy" (i.e., single-target) without being AoE.
	# Indiscriminate (Blood Magic) re-rolls the target per hit, so the
	# play UI doesn't need to ask — the engine picks for you.
	if data != null and (data.addons.has("indiscriminate") or data.addons.has("cleave")):
		return false
	for e in get_effects():
		# An effect that re-rolls its own random target (Bouncing Flask) never
		# needs the player to pick — the engine chooses per hit.
		if bool(e.get("indiscriminate", false)):
			return false
		var t = e.get("target", "")
		if t == "enemy":
			return true
	return false
