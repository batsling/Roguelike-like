class_name CardMods
extends RefCounted

# Resolves item "card gains effect" grants (ItemData.card_grants). An item can
# add effects to every owned card matching a tag / id; the grant is baked into
# the card's resolved effects so it fires in EVERY combat mode, and into the
# card's text so it shows wherever the card is displayed.
#
# This replaces the old card_played-trigger approach for Bird Head / Brass
# Knuckles, which only fired (and only displayed) in deckbuilder.

# Extra effects granted to `card` by the player's current items.
static func granted_effects(card: CardData) -> Array:
	var out: Array = []
	if card == null:
		return out
	for item in _sources():
		for grant in item.card_grants:
			if _matches(grant, card):
				out.append_array(grant.get("effects", []))
	return out

# English-ish description fragment for the granted effects (e.g. "Inflict
# Bruise."), appended to the card's text. "" when nothing applies.
static func describe(card: CardData) -> String:
	if card == null:
		return ""
	var frags: PackedStringArray = PackedStringArray()
	for item in _sources():
		for grant in item.card_grants:
			if _matches(grant, card):
				for e in grant.get("effects", []):
					var phrase: String = _effect_to_phrase(e)
					if phrase != "":
						frags.append(phrase)
	if frags.is_empty():
		return ""
	return " ".join(frags)

# Tiny English-ish renderer for the effect dicts used as item payloads
# (status / block / dmg / heal). Shared by CardInstance's card_played
# addendum too, so the two read identically.
static func _effect_to_phrase(effect: Dictionary) -> String:
	match String(effect.get("type", "")):
		"status":
			var status_name: String = String(effect.get("status", ""))
			if status_name == "":
				return ""
			var stacks: int = int(effect.get("stacks", 1))
			var pretty: String = status_name.capitalize()
			var verb: String = "Inflict" if String(effect.get("target", "enemy")) != "self" else "Gain"
			if stacks <= 1:
				return "%s %s." % [verb, pretty]
			return "%s %d %s." % [verb, stacks, pretty]
		"block":
			return "Gain %d Block." % int(effect.get("value", 0))
		"heal":
			return "Heal %d HP." % int(effect.get("value", 0))
		"dmg":
			var v: int = int(effect.get("value", 0))
			var hits: int = int(effect.get("hits", 1))
			var dt: String = String(effect.get("damage_type", "")).capitalize()
			var n: String = "%dx%d" % [v, hits] if hits > 1 else str(v)
			if dt == "":
				return "Deal %s Dmg." % n
			return "Deal %s Dmg %s." % [n, dt]
		_:
			return ""

static func _sources() -> Array:
	var s: Array = []
	for it in GameState.inventory:
		if it is ItemData and not it.card_grants.is_empty():
			s.append(it)
	var w = GameState.equipped_weapon
	if w is ItemData and not w.card_grants.is_empty():
		s.append(w)
	return s

static func _matches(grant: Dictionary, card: CardData) -> bool:
	var tag: String = String(grant.get("if_card_tag", ""))
	if tag != "" and not card.tags.has(tag):
		return false
	var id_gate: String = String(grant.get("if_card_id", ""))
	if id_gate != "" and String(card.id) != id_gate:
		return false
	return true
