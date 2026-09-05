extends Node

# THE OBS COMPANION OVERLAY (docs/games-first-redesign.md §9).
#
# The run is played on a graph of real games, which means that for most of a
# stream the Godot window is not on screen at all: the player is off inside
# Hollow Knight for ninety minutes and the run's state is frozen behind it. §9
# always called for a "slim companion window" for exactly that gap; what it left
# deferred was the architecture, and this is the answer — NOT a second Godot
# Window, but a page OBS renders itself.
#
# THE SHAPE OF IT. There is no server and no port. The game writes
#
#   user://obs/state.js      window.OBS_STATE = { ... }
#   user://obs/overlay.html  the page, installed from res://obs/ at boot
#   user://obs/overlay.css   its styling, likewise
#   user://obs/overlay.js    its ticker, likewise
#   user://obs/custom.css    YOURS — created empty once and never written again
#   user://obs/covers/       covers lifted out of the .pck when they can't be
#                            read off disk (an exported build)
#
# and OBS points a Browser Source at overlay.html in LOCAL FILE mode. The page
# re-reads `state.js` four times a second by appending a <script> tag with a
# cache-buster on the end.
#
# IT IS A <script> TAG RATHER THAN fetch() ON PURPOSE, and this is the whole
# reason the design works without a server: a page served from file:// may not
# fetch() or XHR a sibling file (Chromium answers every such request with a CORS
# failure, and OBS ships Chromium), but it may always LOAD one as a script, a
# stylesheet or an image. So the state travels as an assignment in a script file,
# and the covers travel as <img src="file:///...">.
#
# WHAT IT SHOWS is §9's list grown up into the current build: health and shields,
# the character, the game in play, the attempts already spent on it, the bodies on
# the board, the shields and statuses riding the run AS SPRITES under the
# portrait (the board's own art and tint — see `_statuses`), and the road so far as a strip of
# covers ending on the Amulet. And THE CHECKLIST, which is what a viewer is
# actually watching for.
#
# A GAME HAS NO GOAL OF ITS OWN. It never has (§7.2) — the goals are the BODIES'
# goals, plus what a status, an event or a curse has handed the player, and a game
# is only the place you go and do them. So there is no headline goal line on this
# overlay and there must not be one: what the viewer reads is the checklist, every
# row of it, and a row belongs to the body or the clause that owns it.
#
# WRITES ARE DEBOUNCED AND DEDUPED. Everything here hangs off signals that fire
# in bursts (a resolved turn moves health, the board and the checklist in one
# frame), so a change only marks the payload dirty and `_process` writes at most
# four times a second — and not at all when the JSON came out identical to the
# last one, which is the common case for the signals that fire on every frame of
# an animation.

# Bumped when the payload's SHAPE changes in a way overlay.js has to know about.
# The page refuses to draw a payload from a newer major than it understands
# rather than half-drawing one, so a stale copy of the page in a streamer's OBS
# says so out loud instead of quietly showing the wrong health.
const PAYLOAD_VERSION := 1

const DIR := "user://obs"
const COVER_DIR := "user://obs/covers"
const STATE_PATH := "user://obs/state.js"
const SOURCE_DIR := "res://obs"

# The page's three files are OVERWRITTEN at every boot: they ship with the game
# and an old copy sitting in user:// is a bug that reads as "the overlay is
# broken". `custom.css` is the other way round — it is the seam meant for the
# streamer's own styling, so it is created empty exactly once and never touched
# again.
const PAGE_FILES := ["overlay.html", "overlay.css", "overlay.js"]
const CUSTOM_CSS := "custom.css"

# At most four writes a second. The signal storm around a resolved turn is a
# dozen emissions in one frame and the overlay cannot show more than the monitor
# refreshes anyway.
const MIN_INTERVAL := 0.25

# …and at LEAST one write every five seconds, even when nothing changed.
#
# This is what lets the page tell "the run has not moved" from "the game is not
# running any more", which are the same thing on disk and very different things
# on a stream: the streamer who alt-tabs into Hollow Knight for ninety minutes
# changes nothing, and an overlay that greyed itself out for that would be
# useless exactly when it is the only thing on screen. So the file's timestamp
# is the heartbeat, and the page dims only when the beat stops.
const HEARTBEAT := 5.0

# How many recent happenings ride along for the page's toast strip. Small on
# purpose: this is the "something just happened" ticker, not a log — GameLog is
# the log.
const MAX_EVENTS := 8

# The road strip's tail. A fifteen-game run is fifteen covers and the overlay is
# a slim strip, so only the last stops are carried and the page says how many
# were dropped off the left.
const MAX_ROAD := 12

# Off switches the whole thing: no writes, no cover extraction, no page install.
# Mirrors Settings.obs_overlay, which is where the toggle in the settings modal
# lands.
var enabled: bool = true

# The absolute on-disk folder OBS is pointed at, resolved once so the settings
# modal can show it without every reader globalizing the path again.
var folder: String = ""

var _dirty: bool = false
var _cooldown: float = 0.0
var _since_write: float = HEARTBEAT
# The last payload written, with its timestamp zeroed — the dedupe compares
# CONTENT, so the heartbeat's ticking clock does not read as a change.
var _last_json: String = ""
var _events: Array = []
# res:// texture path -> the file:// URL the page should use for it. Populated
# lazily, because resolving one may mean lifting a PNG out of the .pck.
var _art_urls: Dictionary = {}
var _installed: bool = false

func _ready() -> void:
	# LAST among the autoloads and a pure reader: this node subscribes to state
	# other singletons own and never writes any of it back.
	process_mode = Node.PROCESS_MODE_ALWAYS
	folder = ProjectSettings.globalize_path(DIR)
	enabled = Settings.obs_overlay
	_connect_signals()
	if enabled:
		_install_page()
		mark_dirty()

# Every signal that can move something the overlay draws. They are connected
# once, for the life of the process, and each one only sets a flag — see the
# debounce note at the top.
func _connect_signals() -> void:
	GameState.hp_changed.connect(func(_hp: int, _max: int) -> void: mark_dirty())
	GameState.gold_changed.connect(func(_gold: int) -> void: mark_dirty())
	GameState.stats_changed.connect(mark_dirty)
	GameState.inventory_changed.connect(mark_dirty)
	GameState.player_statuses_changed.connect(mark_dirty)
	GameState.event_goals_changed.connect(mark_dirty)
	GameState.current_game_changed.connect(func(_id: StringName) -> void: mark_dirty())

	GameLoop2.loop_changed.connect(mark_dirty)
	GameLoop2.enemy_defeated.connect(_on_enemy_defeated)
	GameLoop2.player_hit.connect(_on_player_hit)
	GameLoop2.attempt_logged.connect(_on_attempt_logged)
	GameLoop2.run_lost.connect(func() -> void: _note("bad", "The run is over"))
	GameLoop2.run_won.connect(func() -> void: _note("good", "The Amulet is yours"))

	TriggerBus.game_selected.connect(_on_game_selected)
	TriggerBus.game_beaten.connect(_on_game_beaten)
	TriggerBus.item_acquired.connect(_on_item_acquired)
	TriggerBus.curse_applied.connect(_on_curse_applied)

# ---------------------------------------------------------------------------
# The write loop
# ---------------------------------------------------------------------------

func mark_dirty() -> void:
	_dirty = true

func _process(delta: float) -> void:
	if not enabled:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_since_write += delta
	if _since_write >= HEARTBEAT:
		flush()
		return
	if not _dirty or _cooldown > 0.0:
		return
	flush()

# Write the payload NOW, debounce be damned. Public because the settings toggle
# and the tests both want the file on disk before the next frame.
func flush() -> void:
	if not enabled:
		return
	if not _installed:
		_install_page()
	_dirty = false
	_cooldown = MIN_INTERVAL
	var data: Dictionary = payload()
	# The dedupe, on the payload WITHOUT its clock. `loop_changed` fires on every
	# frame of a board animation and almost none of those frames change a number
	# the overlay draws — but the heartbeat above pushes one through anyway every
	# five seconds, so an unchanged run still proves it is alive.
	var stamp = data["at"]
	data["at"] = 0
	var canon: String = JSON.stringify(data)
	data["at"] = stamp
	if canon == _last_json and _since_write < HEARTBEAT:
		return
	_last_json = canon
	_since_write = 0.0
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("ObsCompanion: cannot write %s (%d)"
			% [STATE_PATH, FileAccess.get_open_error()])
		return
	# The assignment IS the transport (see the header) — a file:// page may load a
	# sibling as a SCRIPT where it may not fetch() one.
	f.store_string("window.OBS_STATE = %s;\n" % JSON.stringify(data, "  "))

# Turn the overlay on or off at runtime. Off leaves the last state.js on disk
# rather than blanking it: a streamer who toggles mid-scene gets a frozen
# overlay, not an empty rectangle, and the page greys itself out once the
# payload stops moving.
func set_enabled(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	if on:
		_install_page()
		_last_json = ""
		flush()

# ---------------------------------------------------------------------------
# The payload
# ---------------------------------------------------------------------------

# The whole of what the overlay knows, as plain Dictionaries/Arrays — every value
# is a JSON scalar, because the page is the only consumer and it cannot resolve a
# Resource. Public so a test can assert on the shape without going through a
# file.
func payload() -> Dictionary:
	var out: Dictionary = {
		"v": PAYLOAD_VERSION,
		"at": Time.get_unix_time_from_system(),
		"state": _run_state(),
		"events": _events.duplicate(true),
	}
	if out["state"] == "idle":
		return out
	out["hero"] = _hero()
	out["art"] = _shared_art()
	out["vitals"] = _vitals()
	out["run"] = _run_line()
	out["now"] = _now_playing()
	out["goals"] = _goals()
	# Walked once and handed to both: the board's summary is the same forecast
	# counted up, and resolving the stack twice per write would be two chances to
	# disagree with itself as well as twice the work.
	var threat: Dictionary = _threat()
	out["board"] = _board(threat)
	out["threat"] = threat
	out["statuses"] = _statuses()
	out["road"] = _road()
	return out

# "idle" (no run — the menus), "run", "won" or "lost". The page draws a verdict
# banner on the last two and keeps everything else on screen underneath, because
# the moment a run ends is the moment the numbers are worth looking at.
func _run_state() -> String:
	if GameState.character_id == &"":
		return "idle"
	if not GameLoop2.run_over:
		return "run"
	return "won" if GameLoop2.won else "lost"

# Art the page needs that belongs to no one row. Only the borrowed-status clock
# so far — the badge `UITheme.timed_art` hangs off the corner of a pip out of the
# timed layer (docs/potions-design.md §5.3). Taken from UITheme's own constant
# rather than by path, so the board's clock and the overlay's are the same file
# by construction.
func _shared_art() -> Dictionary:
	return {
		"timer": _texture_url(UITheme.TIMER_ART),
		# One sprite per shield, at the same 22px as a status pip — the board sizes
		# them alike on purpose, so the two rows are read in one glance and a
		# shield never claims a rank over a status it does not have.
		"shield": _texture_url(UITheme.SHIELD_ART),
	}

func _hero() -> Dictionary:
	var cd: CharacterData = Data.get_character(GameState.character_id)
	if cd == null:
		return {"name": "", "icon": "", "level": GameState.player_level}
	return {
		"name": cd.display_name,
		"icon": _texture_url(cd.icon if cd.icon != null else cd.portrait),
		"level": GameState.player_level,
		"levelup": cd.level_up_condition,
	}

# §9's "keep all numbers single-digit where possible" is why this is health,
# shields and nothing else: they are the two numbers a viewer has to be able to
# read without pausing.
#
# THE SHIELDS COME OUT IN TWO POOLS, because they are two different promises and
# the board already draws them as two (_fill_shields). `kept` is what nothing but
# a hit will take; `timed` expires when this game is reported and wears the clock
# for it. Sent apart AND totalled: the page draws one sprite per shield in the
# board's own order — the pool that stays nearest the portrait, bare — and the
# total is there for anything that just wants the number.
func _vitals() -> Dictionary:
	var kept: int = GameState.bonus_shields
	var timed: int = GameState.shields
	return {
		"hp": GameState.hp,
		"max": GameState.max_hp,
		"shields": kept + timed,
		"shields_kept": kept,
		"shields_timed": timed,
	}

func _run_line() -> Dictionary:
	var hops: int = GameLoop2.hops_to_amulet()
	return {
		"played": GameState.games_played,
		"beaten": GameState.total_games_beaten,
		"gold": GameState.gold,
		# -1 when the Amulet is unreachable from here, which the page prints as
		# "—" rather than as a distance of minus one.
		"hops": hops,
	}

# The game the run is standing on, and what it is costing so far. `attempts` is
# the honour system's tension made visible: every reported failure is a turn the
# board took, and the viewer can watch the count climb while the streamer swears
# at a boss.
func _now_playing() -> Dictionary:
	var playing: bool = not GameLoop2.arrivals.is_empty()
	var game: GameData = Data.get_game(GameState.current_game_id)
	return {
		"playing": playing,
		"game": game.display_name if game != null else "",
		"cover": _cover_url(game),
		"attempts": GameLoop2.attempts(),
	}

# THE CHECKLIST, which is the thing the overlay exists to show. Every row the
# report panel would draw, in the order it draws them, each with whether it is
# already ticked this game.
#
# `kind` is what the page tints on:
#   goal    a body's goal — the sentence that has to be true to clear it
#   bonus   an optional row hung off a body, claimable for its own reward
#   instead a second way out of one body (a Burn's "or instead …")
#   status  the player's own standing objective (GameState.status_objectives)
#   event   a goal an event handed out
#   curse   a goal a curse handed out
#   done    a row already answered THIS RUN, kept for the "what you have done"
#           tail the page shows when there is room
#
# Rows come from the loop and from GameState directly rather than from
# ReportChecklist: the checklist is a Control tree that only exists while the
# overworld is on screen, and the overlay has to be right when the game window is
# minimised behind a stream.
func _goals() -> Array:
	var out: Array = []
	for entry in GameLoop2.stack:
		var enemy: GoalEnemyData = entry.get("enemy")
		if enemy == null:
			continue
		var instance: int = int(entry.get("instance", 0))
		# A BODY'S GOAL IS NOT A `row_answered` ROW. That register holds the rows
		# the report ARMS — the ones cashed when the game is handed in. A body's
		# own goal resolves the moment it is ticked, and what it leaves behind is
		# its instance in one of the loop's two cleared sets (or `staggered`, when
		# the hit landed and the body outlived it).
		var cleared: bool = GameLoop2.cleared_this_game.has(instance) \
			or GameLoop2.instead_this_game.has(instance) \
			or GameLoop2.is_staggered(instance)
		# `goal_text_for`, never `enemy.goal` — the stem on the resource says
		# nothing about the clauses a status has bolted onto it since (§13).
		out.append({
			"kind": "goal",
			"text": GameLoop2.goal_text_for(entry),
			"who": enemy.display_name,
			"boss": enemy.boss,
			"front": GameLoop2.in_front(entry),
			"done": cleared,
		})
		for addon in GameLoop2.goal_addons_for(entry):
			var kind: String = String(addon.get("kind", "clause"))
			if kind == "clause":
				# Already inside the sentence above — drawing it again as its own
				# row would say the same thing twice, which is the mistake
				# ReportChecklist calls out in its own comments.
				continue
			var sd: StatusData = addon.get("status")
			var sid: String = String(sd.id) if sd != null else ""
			# `instead` is keyed by the body alone and `bonus` by the body and the
			# status — the two shapes ReportChecklist writes, quoted rather than
			# invented, so a row the overlay calls done is one the checklist has
			# actually locked.
			var key: String = "instead:%d" % instance if kind == "instead" \
				else "bonus:%d:%s" % [instance, sid]
			out.append({
				"kind": kind,
				"text": String(addon.get("text", "")),
				"who": enemy.display_name,
				"boss": false,
				"front": false,
				"done": GameLoop2.row_answered(key),
			})
	for row in GameState.status_objectives():
		var sd2: StatusData = row.get("status")
		if sd2 == null:
			continue
		out.append({
			"kind": "status",
			"text": sd2.objective_text(StatusData.PLAYER, int(row.get("stacks", 0))),
			"who": sd2.display_name,
			"boss": false,
			"front": false,
			"done": GameLoop2.row_answered("status:%s" % String(row.get("key", ""))),
		})
	for i in range(GameState.event_goals.size()):
		var eg: Dictionary = GameState.event_goals[i]
		var left: int = int(eg.get("games_left", 0))
		out.append({
			"kind": "event",
			"text": "%s → %s" % [eg.get("condition", ""), eg.get("effects_text", "")],
			"who": "",
			"boss": false,
			"front": false,
			"games": left,
			"done": GameLoop2.row_answered("event:%d:%s" % [i, eg.get("condition", "")]),
		})
	for i in range(GameState.curse_goals.size()):
		var cg: Dictionary = GameState.curse_goals[i]
		var cd: CurseData2 = Data.get_curse2(StringName(cg.get("curse", &"")))
		if cd == null:
			continue
		out.append({
			"kind": "curse",
			"text": "%s — %s (if failed, %s)" % [cd.display_name, cd.goal_text(),
				cd.penalty_text],
			"who": cd.display_name,
			"boss": false,
			"front": false,
			# -1 is a curse with no clock on it at all, which the page prints as
			# "permanent" rather than as minus one game left.
			"games": int(cg.get("games_left", 0)),
			"done": GameLoop2.row_answered("curse:%d:%s" % [i, cd.id]),
		})
	return out

# The board in one line rather than as a grid. A viewer cannot read a 5x3 tactical
# board out of the corner of a stream, but "3 bodies, 12 damage waiting" is the
# same information at the resolution the overlay actually has.
func _board(threat: Dictionary) -> Dictionary:
	return {
		"bodies": GameLoop2.stack.size(),
		"front": (threat["swings"] as Array).size(),
		# What lands if the next turn resolves with the board as it stands, BEFORE
		# shields — the page draws the shields eating it and the subtraction is the
		# interesting part.
		"incoming": int(threat["raw"]),
	}

# WHAT ONE LOST RUN COSTS, SWING BY SWING — the whole point of the hero card.
#
# A lost run is not an abstract penalty: THE ENEMIES TAKE A TURN (§3.2). Every
# body that can reach you swings once, each swing is stopped WHOLE by one shield,
# and whatever is left over comes off Health. The "one shield per HIT, whatever
# the hit was for" rule (_take_hit) is the part nobody guesses — a shield eats a
# 9-damage swing as completely as a 1-damage one — and it is invisible in a
# summed "12 incoming".
#
# So this returns the swings as a LIST, in the order the resolver takes them
# (`stack` order, same as _resolve_enemy_turn), each already marked with whether a
# shield is standing to eat it. The page draws one mark per swing and the mechanic
# is countable.
#
# IT MIRRORS `_take_hit` RATHER THAN GUESSING: the player's own damage-taken mods
# are applied first (Marked doubles what lands), a swing modded down to nothing
# spends no shield, Pierce takes both pools past, and the TIMED pool blocks first
# because those expire anyway (§4.3).
#
# IT IS A FORECAST AND NOT A PROMISE, which is why nothing here mutates: an
# ability can spend a body's whole turn on something other than you (§7.6), and a
# body that is staggered or stunned sits this one out — those are excluded, but a
# Cultist that decides to buff instead of swing cannot be known until it does.
func _threat() -> Dictionary:
	var totals: Dictionary = GameState.combat_totals()
	var pierce: bool = bool(totals.get("pierce_shields", false))
	# The pools spend in the board's order: timed first, then the ones that stay.
	var timed_left: int = GameState.shields
	var kept_left: int = GameState.bonus_shields
	var swings: Array = []
	var raw: int = 0
	var through: int = 0
	var broken: int = 0
	for entry in GameLoop2.stack:
		var enemy: GoalEnemyData = entry.get("enemy")
		if enemy == null:
			continue
		var instance: int = int(entry.get("instance", 0))
		# The three that sit the turn out, exactly as the resolver skips them: a
		# body answered for this game holds its fire, a stunned one loses the turn,
		# and one still out of reach cannot swing from where it stands. `can_strike`
		# rather than `in_front` — a Ranged body reaches from further back (§7.6),
		# and counting only the front column understated the cost for every one of
		# them.
		if GameLoop2.is_staggered(instance) or GameLoop2.is_stunned(entry) \
				or not GameLoop2.can_strike(entry):
			continue
		var landed: int = StatusData.apply_damage_mods(GameLoop2.enemy_damage(entry),
			int(totals.get("damage_taken", 0)), float(totals.get("damage_taken_mult", 1.0)))
		if landed <= 0:
			continue    # _take_hit returns before it reaches a shield
		raw += landed
		var blocked: bool = false
		if not pierce:
			if timed_left > 0:
				timed_left -= 1
				blocked = true
			elif kept_left > 0:
				kept_left -= 1
				blocked = true
		if blocked:
			broken += 1
		else:
			through += landed
		swings.append({
			"damage": landed, "who": enemy.display_name, "blocked": blocked,
		})
	return {
		"swings": swings,
		"raw": raw,             # everything thrown, before any shield
		"blocked": broken,      # shields that would break
		"damage": through,      # what actually reaches Health
		"hp_after": maxi(0, GameState.hp - through),
		"lethal": through >= GameState.hp and through > 0,
	}

# The statuses riding the PLAYER, AS PIPS — art and a stack count, which is what
# a status is on every other surface in this game (BattlefieldView's
# `_status_pip`: under the hero's portrait for the player's own, under an enemy's
# box for its own). A status written out as its NAME is a word with no picture
# behind it, and the overlay is read at a glance from across a room.
#
# THE TINT IS THE GAME'S, NOT buff/debuff. `_status_pip` colours on what this
# SIDE DOES — a `bonus` or a `goal` is an opportunity and reads gold, anything
# else taxes you and reads red — and a Buff that happens to tax would be the
# wrong colour under any other rule. Quoted here so the board and the overlay
# cannot say different things about the same stack.
#
# The curses are NOT here: since §13 a curse is a checklist row with a clock and a
# penalty (GameState.curse_goals), so it goes out with the goals where it can be
# read as the instruction it is, rather than as a chip that only names itself.
#
# One pip per status, totalled — the other way round from `status_objectives`
# above, which is one row per instance. What a stack DOES is felt as a total, and
# GameState.status_list says so in the same words.
func _statuses() -> Array:
	var out: Array = []
	for row in GameState.status_list():
		var sd: StatusData = row.get("status")
		if sd == null:
			continue
		out.append({
			"name": sd.display_name,
			"stacks": int(row.get("stacks", 0)),
			# An opportunity (gold) or a tax (red) — see the note above.
			"good": sd.is_bonus(StatusData.PLAYER) or sd.is_goal(StatusData.PLAYER),
			"icon": _texture_url(sd.image),
			# What the pip shows when a status ships without art. The board's own
			# comment already promises "the name's first letter" for that case;
			# here it is, so a new status is legible the day it is authored and
			# before anyone has drawn for it.
			"letter": sd.display_name.substr(0, 1).to_upper(),
			# 0 = permanent; anything else is games left on the clock (§5.3).
			"games": int(row.get("games", 0)),
		})
	return out

# THE ROAD, which is RunOverScreen's route strip drawn live instead of at the
# end: every stop the run has stood on, replays numbered the way that screen
# numbers them, ending on the Amulet whether or not the run has got there.
#
# It is what makes the overlay read as PROGRESS rather than as a list — a strip
# with no destination on the right-hand end says nothing about how far there is
# left to go.
func _road() -> Array:
	var walked: Array = GameState.path_taken.duplicate()
	if walked.is_empty() and GameState.current_game_id != &"":
		walked.append(GameState.current_game_id)
	var seen: Dictionary = {}
	var stops: Array = []
	for id in walked:
		var n: int = int(seen.get(id, 0)) + 1
		seen[id] = n
		stops.append(_stop(id, n, false))
	var amulet: StringName = GameState.amulet_game_id
	# The Amulet always terminates the strip — as the last stop when the run
	# reached it, and as an unreached one otherwise. RunOverScreen draws the gap
	# dashed for exactly the same reason.
	if amulet != &"" and (stops.is_empty() or StringName(stops[-1]["id"]) != amulet):
		stops.append(_stop(amulet, 0, true))
	# Only the tail fits a slim strip. `dropped` rides on the first stop so the
	# page can print "+7 earlier" rather than silently lying about the route.
	var dropped: int = maxi(0, stops.size() - MAX_ROAD)
	if dropped > 0:
		stops = stops.slice(dropped)
	if not stops.is_empty():
		stops[0]["dropped"] = dropped
	return stops

func _stop(id: StringName, visit: int, unreached: bool) -> Dictionary:
	var game: GameData = Data.get_game(id)
	return {
		"id": String(id),
		"name": game.display_name if game != null else String(id),
		"cover": _cover_url(game),
		# 1 the first time the run stood here, 2 the second, and so on — the
		# replay badge. 0 on the unreached Amulet, which was never stood on.
		"visit": visit,
		"beaten": GameState.beaten_games.has(id),
		"amulet": id == GameState.amulet_game_id,
		"current": id == GameState.current_game_id and not unreached,
		"unreached": unreached,
		"dropped": 0,
	}

# ---------------------------------------------------------------------------
# The event ticker
# ---------------------------------------------------------------------------

# One line for the toast strip. `tone` is "good" / "bad" / "info" and is the only
# thing the page colours on.
func _note(tone: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	_events.append({"tone": tone, "text": text,
		"at": Time.get_unix_time_from_system()})
	if _events.size() > MAX_EVENTS:
		_events = _events.slice(_events.size() - MAX_EVENTS)
	mark_dirty()

func _on_enemy_defeated(enemy, _cell) -> void:
	var e: GoalEnemyData = enemy as GoalEnemyData
	_note("good", "Defeated %s" % (e.display_name if e != null else "an enemy"))

func _on_player_hit(damage, blocked) -> void:
	var dealt: int = int(damage)
	var stopped: int = int(blocked)
	if dealt <= 0 and stopped <= 0:
		return
	if dealt <= 0:
		_note("info", "Shields held (%d blocked)" % stopped)
		return
	_note("bad", "Took %d damage" % dealt)

func _on_attempt_logged(_cost: String, undone: bool) -> void:
	if undone:
		return
	_note("bad", "Lost a run — attempt %d" % GameLoop2.attempts())

func _on_game_selected(ctx: Dictionary) -> void:
	var game: GameData = Data.get_game(StringName(ctx.get("game_id", &"")))
	if game != null:
		_note("info", "Now playing %s" % game.display_name)

func _on_game_beaten(ctx: Dictionary) -> void:
	var game: GameData = Data.get_game(StringName(ctx.get("game_id", &"")))
	if game != null:
		_note("good", "Beat %s" % game.display_name)

func _on_item_acquired(ctx: Dictionary) -> void:
	var item = ctx.get("item")
	if item != null and "display_name" in item:
		_note("good", "Found %s" % item.display_name)

func _on_curse_applied(ctx: Dictionary) -> void:
	var curse = ctx.get("curse")
	if curse != null and "display_name" in curse:
		_note("bad", "Cursed — %s" % curse.display_name)

# ---------------------------------------------------------------------------
# Art, as URLs a browser can open
# ---------------------------------------------------------------------------

func _cover_url(game: GameData) -> String:
	if game == null or game.cover_path == "":
		return ""
	return _path_url(game.cover_path)

func _texture_url(tex: Texture2D) -> String:
	if tex == null:
		return ""
	return _path_url(tex.resource_path)

# A res:// path as something a file:// page can put in an <img src>.
#
# TWO CASES, and the second is the one that makes this more than a string
# rewrite. Run from source, res:// IS a folder on disk and the browser can read
# it where it lies. In an EXPORTED build res:// is inside the .pck, there is no
# such file for the browser to open, and the bytes have to be lifted out into
# user://obs/covers/ first. Both answers are cached, because the road redraws
# every quarter second and the answer never changes within a session.
func _path_url(res_path: String) -> String:
	if res_path == "":
		return ""
	if _art_urls.has(res_path):
		return _art_urls[res_path]
	var url: String = ""
	var direct: String = ProjectSettings.globalize_path(res_path)
	if direct != "" and FileAccess.file_exists(direct):
		url = _file_url(direct)
	else:
		url = _extract(res_path)
	_art_urls[res_path] = url
	return url

# Copy one packed file out to user://obs/covers/ and answer with its URL. Copied
# BYTE FOR BYTE rather than loaded and re-encoded: a JPG cover stays the JPG it
# was, and nothing here has to decode an image (see the lazy-cover note in
# CLAUDE.md — decoding covers eagerly is what cost 5 seconds of every boot).
func _extract(res_path: String) -> String:
	DirAccess.make_dir_recursive_absolute(COVER_DIR)
	var out_path: String = "%s/%s" % [COVER_DIR, res_path.get_file()]
	if not FileAccess.file_exists(out_path):
		var src := FileAccess.open(res_path, FileAccess.READ)
		if src == null:
			return ""
		var dst := FileAccess.open(out_path, FileAccess.WRITE)
		if dst == null:
			return ""
		dst.store_buffer(src.get_buffer(src.get_length()))
	return _file_url(ProjectSettings.globalize_path(out_path))

# An absolute OS path as a file:// URL.
#
# ONLY THE FOUR CHARACTERS THAT ACTUALLY BREAK ONE ARE ESCAPED. A full
# `uri_encode()` would also escape the drive colon of a Windows path, and
# `file:///C%3A/…` does not resolve in Chromium — which would leave every cover
# on the overlay broken on Windows and nowhere else, the worst possible place for
# a bug in a tool the streamer sets up once.
static func _file_url(abs_path: String) -> String:
	var norm: String = abs_path.replace("\\", "/")
	norm = norm.replace("%", "%25").replace("#", "%23") \
		.replace("?", "%3F").replace(" ", "%20")
	if not norm.begins_with("/"):
		norm = "/" + norm   # C:/Users/… -> /C:/Users/…
	return "file://" + norm

# ---------------------------------------------------------------------------
# Installing the page
# ---------------------------------------------------------------------------

# Put the overlay's three files next to state.js, overwriting whatever is there
# (they ship with the game — see the const's comment), and leave an empty
# `custom.css` beside them the first time only.
func _install_page() -> void:
	_installed = true
	DirAccess.make_dir_recursive_absolute(DIR)
	for name in PAGE_FILES:
		var src := FileAccess.open("%s/%s" % [SOURCE_DIR, name], FileAccess.READ)
		if src == null:
			push_warning("ObsCompanion: %s/%s is missing — is it in the export filter?"
				% [SOURCE_DIR, name])
			continue
		var dst := FileAccess.open("%s/%s" % [DIR, name], FileAccess.WRITE)
		if dst == null:
			continue
		dst.store_string(src.get_as_text())
	var custom: String = "%s/%s" % [DIR, CUSTOM_CSS]
	if not FileAccess.file_exists(custom):
		var f := FileAccess.open(custom, FileAccess.WRITE)
		if f != null:
			f.store_string("/* Your own styling. This file is created once and never overwritten. */\n")

# The path to hand a streamer: the overlay page itself, as an absolute OS path
# they can paste into OBS's Browser Source "Local file" box.
func page_path() -> String:
	return ProjectSettings.globalize_path("%s/overlay.html" % DIR)
