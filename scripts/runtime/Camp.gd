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
# camp a game, and camping twice in a row is refused. Only between games — never
# with one in play, whose board is mid-turn.
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
	if GameLoop2.game_in_play:
		return "Finish or escape the game in play first."
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

# The camp is made: the games it was earned by are spent. Called the moment a
# card is chosen, before any pick it opens, so a pick put away cannot leave the
# camp open to be made again.
static func spend() -> void:
	GameState.games_beaten_since_camp.clear()
