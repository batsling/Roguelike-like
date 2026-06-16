class_name AddonSystem

# Generic interpreter for the per-mode addon verbs authored in the addonsnew
# sheet's DB / Action / Strategy Verb columns (carried into
# ReferenceCatalog.ADDONS as db_verb / action_verb / strategy_verb). Deckbuilder
# keeps its existing CardData-flag code; this powers the Action and Strategy
# lifecycle behaviors (Exhaust / Ethereal / Innate / Unplayable) that were
# previously unwired. See docs/addon-translation-dsl.md.
#
# Verb grammar (per cell): clause := [trigger ":"] [condition ":"] action
#                          cell  := clause ( ";" clause )*
#   trigger   — on_play | eot_in_hand | on_combat_start | on_kill
#   condition — chance(N)
#   action    — verb | verb "(" args ")"
#
# Everything here is READ-ONLY over the catalog and the card's addon slugs, so
# consulting it can never mutate state — scenes ask it questions, then act.

const _MODE_FIELD := {
	Stats.Mode.DECKBUILDER: "db_verb",
	Stats.Mode.ACTION: "action_verb",
	Stats.Mode.STRATEGY: "strategy_verb",
}

static var _index: Dictionary = {}          # addon key -> catalog entry
static var _clause_cache: Dictionary = {}   # "key|field" -> Array[Dictionary]

static func _addon_index() -> Dictionary:
	if _index.is_empty():
		for a in ReferenceCatalog.ADDONS:
			var key: String = String(a.get("key", ""))
			if key != "":
				_index[key] = a
	return _index

# Parse one verb cell into a list of { trigger, condition, verb, args }.
static func _parse_cell(text: String) -> Array:
	var out: Array = []
	var t: String = text.strip_edges()
	if t == "":
		return out
	for raw_clause in t.split(";"):
		var clause: String = raw_clause.strip_edges()
		if clause == "":
			continue
		var segs: PackedStringArray = clause.split(":")
		var action: String = segs[segs.size() - 1].strip_edges()
		var trigger: String = ""
		var condition: String = ""
		for i in range(segs.size() - 1):
			var lead: String = segs[i].strip_edges()
			if lead.begins_with("chance("):
				condition = lead
			elif lead != "":
				trigger = lead
		var verb: String = action
		var args: String = ""
		var lp: int = action.find("(")
		if lp != -1 and action.ends_with(")"):
			verb = action.substr(0, lp)
			args = action.substr(lp + 1, action.length() - lp - 2)
		out.append({
			"trigger": trigger, "condition": condition,
			"verb": verb, "args": args.strip_edges(),
		})
	return out

# All parsed clauses for a single addon key in one mode (cached).
static func _clauses_for_key(key: String, mode) -> Array:
	var field: String = _MODE_FIELD.get(mode, "")
	if field == "":
		return []
	var cache_key: String = key + "|" + field
	if not _clause_cache.has(cache_key):
		var entry: Dictionary = _addon_index().get(key, {})
		_clause_cache[cache_key] = _parse_cell(String(entry.get(field, "")))
	return _clause_cache[cache_key]

# All clauses across every addon slug on `card` for `mode`.
static func clauses_for(card, mode) -> Array:
	var out: Array = []
	if card == null or not ("addons" in card):
		return out
	for addon_name in card.addons:
		out.append_array(_clauses_for_key(String(addon_name), mode))
	return out

# ---------------------------------------------------------------------------
# Per-mode lifecycle queries the Action / Strategy scenes ask.
# ---------------------------------------------------------------------------

# Cooldown multiplier (product of every cooldown_mult verb). 1.0 = unchanged.
static func cooldown_mult(card, mode) -> float:
	var mult: float = 1.0
	for c in clauses_for(card, mode):
		if c["verb"] == "cooldown_mult":
			mult *= float(c["args"])
	return mult

# Per-combat use cap: the smallest uses_per_combat seen, or -1 for unlimited.
static func uses_per_combat(card, mode) -> int:
	var cap: int = -1
	for c in clauses_for(card, mode):
		if c["verb"] == "uses_per_combat":
			var n: int = int(c["args"])
			cap = n if cap < 0 else mini(cap, n)
	return cap

# True if the card auto-plays at combat start (Innate, Action).
static func auto_plays_at_start(card, mode) -> bool:
	for c in clauses_for(card, mode):
		if c["verb"] == "auto_play" and c["trigger"] == "on_combat_start":
			return true
	return false

# Free plays granted at combat start (Innate, Strategy).
static func free_play_count(card, mode) -> int:
	var total: int = 0
	for c in clauses_for(card, mode):
		if c["verb"] == "free_play":
			total += int(c["args"])
	return total

# Minimum number of this card that must stay equipped (Unplayable, Strategy).
static func requires_equipped(card, mode) -> int:
	var req: int = 0
	for c in clauses_for(card, mode):
		if c["verb"] == "requires_equipped":
			req = maxi(req, int(c["args"]))
	return req

# True if an unused ability deactivates for the rest of combat (Ethereal,
# Strategy).
static func deactivates_if_idle(card, mode) -> bool:
	for c in clauses_for(card, mode):
		if c["verb"] == "deactivate_if_idle":
			return true
	return false
