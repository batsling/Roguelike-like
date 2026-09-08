class_name BodyFacts
extends RefCounted

# WHAT A BODY IS — the query layer over one entry on the board (§7.3, §7.6).
#
# A body on the board is a bare `Dictionary` (GameLoop2.BODY_KEYS says which keys
# it may carry). These are the questions everything asks about one: what its goal
# says, which picture it wears, what abilities and tags it answers to, whether it
# is hidden, what phase a multi-phase boss is in. Six screens and the OBS overlay
# read a body through here — BattlefieldView, EnemyInfoCard, ReportChecklist,
# GameChoiceModal, OfferingCards, ObsCompanion — and so does GameLoop2 itself.
#
# EVERY FUNCTION HERE IS `static` AND PURE. It reads the Dictionary it is handed
# and the catalogue behind it, and nothing else: no board, no run, no state on the
# loop. That is what makes this the one piece of GameLoop2 worth its own file
# (docs/performance-backlog.md §1b) — the file's other regions are LAYERS of one
# machine and would spend their lives calling home, while this half genuinely
# stands alone. The measurement is in that entry: of the abilities block's 53
# functions, these touch no member var and make no call back into the loop.
#
# GameLoop2 keeps a one-line forward for each, so every existing
# `GameLoop2.entry_goal(entry)` call site in the repo still reads the same.

# --- abilities on a body ----------------------------------------------------

# The RUNTIME ability list for one body: what the sheet authored plus anything
# granted since. Falls back to the enemy's own list for an entry built before
# §7.6 (an old save, a hand-made test body), which is the honest answer there.
static func entry_abilities(entry: Dictionary) -> Array:
	if entry.has("abilities"):
		return entry.get("abilities", [])
	var enemy: GoalEnemyData = entry.get("enemy")
	return enemy.abilities if enemy != null else []

static func entry_ability_row(entry: Dictionary, id: StringName) -> Dictionary:
	for a in entry_abilities(entry):
		if StringName(a.get("id", &"")) == id:
			return a
	return {}

static func entry_has_ability(entry: Dictionary, id: StringName) -> bool:
	return not entry_ability_row(entry, id).is_empty()

# The numeric argument on `id`. Note the difference between "no such ability" and
# "the ability with argument 0": Ranged's 0 means UNLIMITED (§7.6), so a caller
# that needs to tell them apart asks entry_has_ability first.
static func entry_ability_amount(entry: Dictionary, id: StringName, fallback: int = 0) -> int:
	var row: Dictionary = entry_ability_row(entry, id)
	return int(row.get("amount", fallback)) if not row.is_empty() else fallback

static func entry_ability_arg(entry: Dictionary, id: StringName) -> StringName:
	return StringName(entry_ability_row(entry, id).get("arg", &""))

# Whether anything about this body is worth the board's ⚠ mark: it has an ability.
# One question, so the badge, the hover and the card cannot disagree.
static func entry_has_abilities(entry: Dictionary) -> bool:
	return not entry_abilities(entry).is_empty()

# Every ability on this body as [{ability: AbilityData, row: Dictionary,
# text: String}], catalog-resolved and with its sentence already filled in. The
# hover, the card and the collection screen all draw from this, so an ability
# reads the same wherever it is met.
static func ability_lines(entry: Dictionary) -> Array:
	var out: Array = []
	for row in entry_abilities(entry):
		var id: StringName = StringName(row.get("id", &""))
		var ad: AbilityData = Data.get_ability(id)
		if ad == null:
			continue
		out.append({
			"ability": ad,
			"row": row,
			"name": ad.display_name,
			"text": ad.describe(int(row.get("amount", 0)), String(row.get("text", ""))),
		})
	return out

# Whether `status_id` simply will not stick to this body. Fireproof refuses Burn,
# and that is the whole roster of resistances today — but it is asked as a general
# question so the next one is a row in a match rather than a new call site.
static func resists_status(entry: Dictionary, status_id: StringName) -> bool:
	return status_id == &"burn" and entry_has_ability(entry, &"fireproof")

# --- tags -------------------------------------------------------------------

# Every tag this body answers to: the sheet's, plus anything granted at runtime
# (Necromancy raises the dead as `undead`). Ask this rather than
# `entry["enemy"].has_tag`, or a raised body will not read as undead to the goal
# that is hunting one.
static func entry_has_tag(entry: Dictionary, wanted: StringName) -> bool:
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy != null and enemy.has_tag(wanted):
		return true
	for t in entry.get("tags", []):
		if StringName(t) == wanted:
			return true
	return false

static func entry_tags(entry: Dictionary) -> Array:
	var out: Array = []
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy != null:
		for t in enemy.tag_list():
			out.append(StringName(t))
	for t in entry.get("tags", []):
		if not out.has(StringName(t)):
			out.append(StringName(t))
	return out

static func grant_tag(entry: Dictionary, tag: StringName) -> void:
	if tag == &"" or entry_has_tag(entry, tag):
		return
	var tags: Array = (entry.get("tags", []) as Array).duplicate()
	tags.append(tag)
	entry["tags"] = tags

# --- hidden -----------------------------------------------------------------

# Invisible until it swings (§7.6). The entry-shaped half of the question; the
# instance-shaped one (`GameLoop2.is_hidden`) has to look the body up first and
# stays on the loop with the rest of invisibility.
static func entry_hidden(entry: Dictionary) -> bool:
	return bool(entry.get("hidden", false))

# --- phases -----------------------------------------------------------------
#
# A multi-phase boss is one sheet row and several bodies: each Undying revive
# steps it to the next phase, which is a new goal and a new picture. Everything
# that reads a goal or a portrait off a body asks these, not the resource, so the
# phase a boss is actually in is the one the player is shown.

static func entry_phase(entry: Dictionary) -> int:
	return maxi(0, int(entry.get("phase", 0)))

static func entry_goal(entry: Dictionary) -> String:
	var enemy: GoalEnemyData = entry.get("enemy")
	return "" if enemy == null else enemy.goal_at(entry_phase(entry))

static func entry_goal_type(entry: Dictionary) -> StringName:
	var enemy: GoalEnemyData = entry.get("enemy")
	return &"" if enemy == null else enemy.goal_type_at(entry_phase(entry))

static func entry_image(entry: Dictionary) -> Texture2D:
	var enemy: GoalEnemyData = entry.get("enemy")
	return null if enemy == null else enemy.image_at(entry_phase(entry))

# "Phase 2 of 3" for the card, or "" for a body that has only ever been itself.
static func phase_note(entry: Dictionary) -> String:
	var enemy: GoalEnemyData = entry.get("enemy")
	if enemy == null or enemy.phase_count() <= 1:
		return ""
	return "phase %d of %d" % [entry_phase(entry) + 1, enemy.phase_count()]
