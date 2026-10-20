extends RefCounted

# CAMP — the end-of-session rest (docs/rest-site-design.md; the owner, 20 Oct 2026).
#
# A run lasts a day or two of streaming, so it is played in SESSIONS, and the end
# of one is a moment the stream already has. Making camp is the decision that
# goes in it: two cards, take one.
#
#   * REST is always there: +REST_HEAL Health.
#   * ONE MORE is dealt from a random game beaten since the last camp, by that
#     game's type — what playing it taught you:
#       Traditional  identify one piece of loot you carry
#       Deckbuilder  a random card
#       Strategy     CHARGE_AMOUNT charges to something you carry
#       Action       +SHIELD_GAIN Shield (the kind that stays, §3.2)
#
# A camp needs a game BEATEN since the last one (GameState.games_beaten_since_camp),
# which is what keeps it from being farmed: quitting after every game earns one
# camp a game, and camping twice in a row is refused. With that, it is the whole
# camp whether or not a game is in play: a session that ends mid-game (a long
# Traditional run) still earned it with the wins before.
#
# It is made on the way OUT of a run — the Exit and Main menu doors offer it, and
# taking a card saves and leaves (Overworld2.camp_choose). The deal is dealt once
# and kept (GameState.camp_deal) until a card is taken, so backing out to the run
# and coming back shows the same two cards: no rerolling by reopening.
#
# An option that could do nothing (nothing unidentified to study, nothing that
# takes a charge) is never dealt: the deal draws from the beaten games whose
# option would land, and with none it is Rest alone.
#
# Static and stateless — the state is GameState's — and loaded by path, with no
# class_name, so the page's compile does not pay for it (test_page_load.gd).

const REST_HEAL := 2
const SHIELD_GAIN := 1
const CHARGE_AMOUNT := 2
const CARD_COUNT := 1

const REST := &"rest"
const IDENTIFY := &"identify"
const CARD := &"card"
const CHARGE := &"charge"
const SHIELD := &"shield"

# Game type key (GameLoop2.game_type_key) -> the option a game of that type deals.
const OPTION_FOR_TYPE := {
	&"traditional": IDENTIFY,
	&"deckbuilder": CARD,
	&"strategy": CHARGE,
	&"action": SHIELD,
}

# The words on each card. `title` is the card's name, `text` what it does, `icon`
# a glyph the UI fonts already ship (Brace has none: it is drawn with the shield's
# own art, UITheme.SHIELD_ART, as the hero's shields are).
static func describe(id: StringName) -> Dictionary:
	match id:
		REST:
			return {"title": "Rest", "icon": "♥",
				"text": "+%d Health." % REST_HEAL}
		IDENTIFY:
			return {"title": "Study", "icon": "?",
				"text": "Identify one piece of loot you are carrying."}
		CARD:
			return {"title": "Draft", "icon": "🃏",
				"text": "Gain %d random card." % CARD_COUNT}
		CHARGE:
			return {"title": "Tinker", "icon": "⚡",
				"text": "Give %d charges to one thing you carry." % CHARGE_AMOUNT}
		SHIELD:
			return {"title": "Brace", "icon": "",
				"text": "+%d %s, which stays until something breaks it." % [
					SHIELD_GAIN, GameState.SHIELD_NAME]}
	return {"title": String(id).capitalize(), "icon": "", "text": ""}

# --- when ------------------------------------------------------------------

static func can_camp() -> bool:
	return why_not() == ""

# Why the camp is shut right now, in the words the menu shows; "" when it is open.
static func why_not() -> String:
	if GameLoop2.run_over:
		return "The run is over."
	if GameState.games_beaten_since_camp.is_empty():
		return "Beat a game first — a camp is earned by the games since the last one."
	return ""

# --- what --------------------------------------------------------------------

static func option_for(game: GameData) -> StringName:
	return OPTION_FOR_TYPE.get(GameLoop2.game_type_key(game), SHIELD)

# Whether `id` would do anything right now.
static func usable(id: StringName) -> bool:
	match id:
		IDENTIFY:
			return not LootSystem.carried_unidentified().is_empty()
		CHARGE:
			return not chargeable().is_empty()
	return true

# What a Tinker can be pointed at: anything carried that takes a charge and has
# room for one.
static func chargeable() -> Array:
	return GameState.chargeable_things().filter(
		func(t): return GameState.charge_thing_room(t) > 0)

# The cards: [Rest] or [Rest, {id, game}]. The second is drawn from a random game
# beaten since the last camp, among those whose option would land.
static func deal(rng: RandomNumberGenerator) -> Array:
	var out: Array = [{"id": REST, "game": &""}]
	var pool: Array = []
	for gid in GameState.games_beaten_since_camp:
		var g: GameData = Data.get_game(gid)
		if g != null and usable(option_for(g)):
			pool.append(g)
	if not pool.is_empty():
		var g: GameData = pool[rng.randi_range(0, pool.size() - 1)]
		out.append({"id": option_for(g), "game": g.id})
	return out

# The deal this camp shows: the one already dealt, if it still stands, else a fresh
# one, kept in GameState.camp_deal until a card is taken (spend). It is dealt anew
# only when there was nothing to keep — no deal yet, Rest alone (a win since may
# have earned a second card), or a second card that would now do nothing (the
# last unknown piece got identified some other way).
static func current_deal(rng: RandomNumberGenerator) -> Array:
	var kept: Array = GameState.camp_deal
	if kept.size() >= 2 and usable(StringName(String((kept[1] as Dictionary).get("id", "")))):
		return kept.duplicate(true)
	var fresh: Array = deal(rng)
	GameState.camp_deal = fresh.map(func(c): return {
		"id": String(c["id"]), "game": String(c["game"])})
	return GameState.camp_deal.duplicate(true)

# --- doing it ----------------------------------------------------------------

# The two options that need no further choice. The other three need the page —
# a pick in the pack, or the loot offer — and Overworld2.camp_choose does them.
static func rest() -> String:
	var before: int = GameState.hp
	GameState.change_hp(REST_HEAL)
	return "You rest: +%d Health." % (GameState.hp - before)

static func brace() -> String:
	GameState.bonus_shields += SHIELD_GAIN
	GameState.stats_changed.emit()
	return "You brace: +%d %s." % [SHIELD_GAIN, GameState.SHIELD_NAME]

# The camp is made: the games it was earned by are spent, with its deal. Called
# when the card actually pays — at once for Rest and Brace, when its pick is
# answered for Study and Tinker — so backing out of a pick spends nothing.
static func spend() -> void:
	GameState.games_beaten_since_camp.clear()
	GameState.camp_deal = []
	mark_session()

# --- the session ---------------------------------------------------------------
#
# A SESSION is the stretch between two camps (or the run's start and its first
# camp). The camp screen shows it — the stops walked in it, lit on the road, and
# what was done in it — so the mark is where the run's own running records stood
# when the session began, and everything below is "now minus the mark". Nothing
# new is counted: the road is GameState.walked_path, the goals
# GameLoop2.completed_goals, the games and lost runs RunTimer's splits, the time
# RunTimer's clock. An empty mark (a new run, an older save) is the run's start.

static func mark_session() -> void:
	GameState.session_mark = {
		"path": GameState.walked_path().size(),
		"goals": GameLoop2.completed_goals.size(),
		"splits": RunTimer.splits.size(),
		"seconds": RunTimer.run_seconds,
		"hp": GameState.hp,
	}

# The index on walked_path() where this session's stops begin.
static func session_start_index() -> int:
	return int(GameState.session_mark.get("path", 0))

# What this session did, as numbers: games finished (and how each closed), lost
# runs, goals answered (and how many of those were enemies), time, and Health.
static func session_stats() -> Dictionary:
	var mark: Dictionary = GameState.session_mark
	var out := {"games": 0, "beaten": 0, "escaped": 0, "lost_runs": 0,
		"goals": 0, "enemies": 0, "seconds": 0.0, "hp_change": 0}
	var splits: Array = RunTimer.splits
	for i in range(mini(int(mark.get("splits", 0)), splits.size()), splits.size()):
		var sp: Dictionary = splits[i]
		out["games"] += 1
		out["lost_runs"] += (sp.get("attempts", []) as Array).size()
		match String(sp.get("outcome", "")):
			"beaten":
				out["beaten"] += 1
			"escaped":
				out["escaped"] += 1
	var goals: Array = GameLoop2.completed_goals
	for i in range(mini(int(mark.get("goals", 0)), goals.size()), goals.size()):
		out["goals"] += 1
		if String((goals[i] as Dictionary).get("kind", "")) == "enemy":
			out["enemies"] += 1
	out["seconds"] = maxf(0.0, RunTimer.run_seconds - float(mark.get("seconds", 0.0)))
	out["hp_change"] = GameState.hp - int(mark.get("hp", GameState.hp))
	return out

# "2h 05m", "14m": a session's length, to the minute.
static func duration_text(seconds: float) -> String:
	var m: int = int(seconds / 60.0)
	if m >= 60:
		return "%dh %02dm" % [m / 60, m % 60]
	return "%dm" % m
