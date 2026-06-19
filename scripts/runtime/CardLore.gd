class_name CardLore

# Shared resolver that turns a CardData into the list of "keywords" worth
# explaining to the player — its damage Element, its Addons (Finesse, Cleave, …)
# and any Status effects it inflicts. Used by the backpack card zoom (tooltip
# sidebar) and the in-combat dynamic hover card so both read identically.
#
# Each entry: { "kind": String, "name": String, "color": Color, "desc": String }.

const ELEMENT_COLOR_FALLBACK := Color(0.8, 0.8, 0.85)
const ADDON_COLOR := Color(0.95, 0.78, 0.28)
const STATUS_COLOR := Color(0.7, 0.85, 1.0)

# Build the full lore list for a card (static authoring, no live target).
static func entries_for(card: CardData) -> Array:
	var out: Array = []
	if card == null:
		return out
	_add_element(out, card)
	_add_addons(out, card)
	_add_statuses(out, card, null)
	return out

# Like entries_for, but resolves the element's CONDITIONAL on-hit status against
# a live `target` (a CombatActor / BattleUnit exposing get_status). The Fire ->
# "Inflict 1 Burn" line only appears when the target actually lacks Burn, so the
# hover card reflects what would really happen to THAT enemy.
static func entries_for_target(card: CardData, target) -> Array:
	var out: Array = []
	if card == null:
		return out
	_add_element(out, card, target)
	_add_addons(out, card)
	_add_statuses(out, card, target)
	return out

static func _add_element(out: Array, card: CardData, target = null) -> void:
	var name: String = Elements.display_name(card.element)
	if name == "":
		return
	var desc: String = Elements.description(card.element)
	# When a target is supplied, show the live on-hit result instead of the
	# generic rule (so a Fire card on a burning enemy reads "no extra Burn").
	if target != null:
		var oh: Dictionary = Elements.on_hit_status(card.element, target, card)
		if oh.is_empty():
			desc = "%s element — no extra on-hit effect on this target." % name
		else:
			desc = "%s element — inflicts %d %s on hit." % [
				name, int(oh.get("stacks", 1)),
				String(oh.get("status", "")).capitalize()]
	out.append({
		"kind": "Element",
		"name": name,
		"color": Elements.color(card.element),
		"desc": desc,
	})

static func _add_addons(out: Array, card: CardData) -> void:
	if not ("addons" in card):
		return
	for slug in card.addons:
		var entry: Dictionary = _addon_entry(String(slug))
		var nm: String = String(entry.get("name", String(slug).capitalize()))
		var desc: String = String(entry.get("deckbuilder", ""))
		out.append({"kind": "Addon", "name": nm, "color": ADDON_COLOR, "desc": desc})

static func _add_statuses(out: Array, card: CardData, target) -> void:
	# The statuses a card inflicts come from its `status` effects. Dedupe so a
	# multi-hit card lists Burn once, and skip the element's on-hit status (it's
	# already shown under the Element entry).
	var seen: Dictionary = {}
	var element_status: String = ""
	if target != null:
		var oh: Dictionary = Elements.on_hit_status(card.element, target, card)
		element_status = String(oh.get("status", ""))
	for e in card.effects:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if String(e.get("type", "")) != "status":
			continue
		var sid: String = String(e.get("status", ""))
		if sid == "" or seen.has(sid) or sid == element_status:
			continue
		seen[sid] = true
		var sinfo: Dictionary = _status_entry(sid)
		out.append({
			"kind": "Status",
			"name": String(sinfo.get("name", sid.capitalize())),
			"color": STATUS_COLOR,
			"desc": String(sinfo.get("description", "")),
		})

static func _addon_entry(slug: String) -> Dictionary:
	for a in ReferenceCatalog.ADDONS:
		if String(a.get("key", "")) == slug:
			return a
	return {}

static func _status_entry(name_or_id: String) -> Dictionary:
	var key: String = name_or_id.replace("_", " ").to_lower()
	for s in ReferenceCatalog.STATUSES:
		if String(s.get("name", "")).to_lower() == key:
			return s
	return {}
