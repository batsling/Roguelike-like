extends Node

# THE SPEEDRUN CLOCK. A run of this game is a stack of real video games played
# one after another, which is a speedrun with unusually long splits — so it is
# timed like one: a clock on the game in play, a clock on the whole run, and a
# banked split for every game the run has finished.
#
# It exists for the STREAM first (ObsCompanion sends it to the overlay, which
# draws the running numbers and the split list), and the same numbers are drawn
# beside the cover in the Now Playing panel so the player is looking at the clock
# their viewers are.
#
# WHEN IT RUNS
#   The game clock starts the moment the run STANDS ON a game — TriggerBus's
#   `game_selected`, which is what `GameLoop2.grant_selection_shields` emits as a
#   game is taken. Deliberately NOT the "▶ Play <game>" button: that button only
#   exists for the games that have a launch target authored
#   (`GameData.has_launch_target`), which is a small minority of the roster, so a
#   clock hung off it would sit at zero for most of a run.
#   It stops when the game is REPORTED — beaten, missed, or escaped — because all
#   three are the board closing on that game and the evening being over.
#   The run clock runs from the first game of the run to the verdict, across the
#   gaps between games (the offering, a shop, an event), because those are time
#   the run took.
#
#   A LOST ATTEMPT DOES NOT STOP IT. Reporting a death is part of playing the
#   game and a speedrun clock counts your failures — what happens instead is that
#   the attempt is BANKED as its own split, so the game's entry reads as the list
#   of how long each try at it took. Undoing an attempt (`GameLoop2.undo_attempt`)
#   hands that time straight back to the running attempt, so an undo leaves the
#   clock exactly where it would have been.
#
# WALL CLOCK VS APP TIME
#   Time accumulates only while the game is RUNNING — this is a `_process` sum,
#   not the difference of two timestamps. A run left open overnight comes back
#   where it was rather than eight hours heavier, which is the only reading of
#   "how long did this take" that survives a run played over a week of evenings.
#   The overlay extrapolates between writes from the payload's own `at` stamp,
#   and every write corrects it, so the page never drifts more than a heartbeat.
#
# PROCESS_MODE_ALWAYS, because a paused tree is not a paused clock: the pause
# menu, the tier list and the collection all run over a paused run, and the
# player who opened one is still sitting in front of the game they are timing.
# The one thing that does stop it is there being no run at all — see `_process`.

# Emitted when a split is banked or the clock starts or stops. The per-frame tick
# deliberately does NOT emit: anything drawing a running clock reads `game_time`
# on its own schedule rather than being woken 60 times a second.
signal changed

# The whole run, in seconds, including the game in play.
var run_seconds: float = 0.0
var run_running: bool = false

# The game the clock is on, and its two live numbers: the game's own total and
# the current attempt within it.
var game_id: StringName = &""
var game_seconds: float = 0.0
var attempt_seconds: float = 0.0
var game_running: bool = false

# Every attempt banked at the CURRENT game, oldest first, in seconds. Moved into
# the game's split when it is reported.
var attempt_splits: Array = []

# The games this run has finished, oldest first. One entry each:
#   {id: String, seconds: float, attempts: Array[float], outcome: String}
# `outcome` is "beaten", "missed" or "escaped" — the three ways a board closes.
var splits: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	TriggerBus.game_selected.connect(_on_game_selected)
	GameLoop2.attempt_logged.connect(_on_attempt_logged)
	GameLoop2.run_lost.connect(end_run)
	GameLoop2.run_won.connect(end_run)

func _process(delta: float) -> void:
	# NO RUN, NO CLOCK. `character_id` is empty in the menus and between runs, and
	# a timer that ticked there would quietly add the time the player spent
	# reading their tier list to the next run they start.
	if GameState.character_id == &"":
		return
	if run_running:
		run_seconds += delta
	if game_running:
		game_seconds += delta
		attempt_seconds += delta

# ---------------------------------------------------------------------------
# The run
# ---------------------------------------------------------------------------

# A NEW RUN — every number back to zero. Called from GameLoop2.start_run, which
# is the one door into a fresh run, so a second run in one session cannot inherit
# the first one's splits.
func begin_run() -> void:
	run_seconds = 0.0
	run_running = true
	_clear_game()
	splits.clear()
	changed.emit()

# The verdict. Both clocks stop and stay where they are: the final time is the
# thing worth reading at the end of a run, so nothing here resets it — the next
# `begin_run` does that.
func end_run() -> void:
	run_running = false
	game_running = false
	changed.emit()

# ---------------------------------------------------------------------------
# One game
# ---------------------------------------------------------------------------

func _on_game_selected(ctx: Dictionary) -> void:
	start_game(StringName(ctx.get("game_id", &"")))

# Stand the clock on `id`. Re-selecting the game already being timed is a no-op
# rather than a restart — an item that re-grants selection shields would
# otherwise wipe the split the player is halfway through.
func start_game(id: StringName) -> void:
	if id == &"":
		return
	if game_running and game_id == id:
		return
	game_id = id
	game_seconds = 0.0
	attempt_seconds = 0.0
	attempt_splits.clear()
	game_running = true
	# A game selected before the run clock was started (a save resumed straight
	# into a game, a test) starts it: standing on a game IS the run running.
	run_running = true
	changed.emit()

func _on_attempt_logged(_cost: String, undone: bool) -> void:
	if undone:
		unbank_attempt()
	else:
		bank_attempt()

# A lost run, reported. The attempt's time closes as its own split and the next
# one starts at zero; the GAME clock is untouched, because the game is still
# being played.
func bank_attempt() -> void:
	if not game_running:
		return
	attempt_splits.append(attempt_seconds)
	attempt_seconds = 0.0
	changed.emit()

# The undo. The banked attempt's time goes back onto the running attempt rather
# than being thrown away — `undo_attempt` puts the whole run back to before the
# tick, and the clock is part of "before the tick".
func unbank_attempt() -> void:
	if attempt_splits.is_empty():
		return
	attempt_seconds += float(attempt_splits.pop_back())
	changed.emit()

# THE BOARD CLOSED ON THIS GAME. Called from Overworld2.report — the one funnel
# every finished game goes through, whatever it said — so a beaten game, a missed
# goal and an escape all bank a split and all stop the clock.
#
# `id` is passed in rather than read off `game_id` because the report knows which
# game it is reporting; a mismatch means the clock was never started for it (a
# resumed save from before this existed), and the split is written anyway with
# whatever time was accumulated.
func finish_game(id: StringName, beaten: bool, escaped: bool = false) -> void:
	if not game_running and game_seconds <= 0.0:
		return
	var outcome: String = "beaten"
	if escaped:
		outcome = "escaped"
	elif not beaten:
		outcome = "missed"
	var tries: Array = attempt_splits.duplicate()
	# The last try — the one the player was in the middle of when the game ended —
	# is an attempt like the others. Without this, the winning run of a game is the
	# one try that never appears in its own list.
	tries.append(attempt_seconds)
	splits.append({
		"id": String(id if id != &"" else game_id),
		"seconds": game_seconds,
		"attempts": tries,
		"outcome": outcome,
	})
	_clear_game()
	changed.emit()

func _clear_game() -> void:
	game_id = &""
	game_seconds = 0.0
	attempt_seconds = 0.0
	attempt_splits.clear()
	game_running = false

# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

# H:MM:SS.d under an hour drops the hour — the LiveSplit convention, and the one
# that keeps the number the same width for most of a game. `decimals` is 0 for a
# banked split (a finished time to the second is enough) and 1 for a running one,
# where a moving tenth is what says the clock is alive.
static func format(seconds: float, decimals: int = 1) -> String:
	var total: float = maxf(0.0, seconds)
	var hours: int = int(total / 3600.0)
	var mins: int = int(total / 60.0) % 60
	var secs: float = total - float(hours) * 3600.0 - float(mins) * 60.0
	# Two digits before the point whatever the decimals — "09.4", not "9.4" — so
	# the clock does not jump a character wide every ten seconds. The format
	# string is built rather than literal because `%` has no run-time precision.
	var sec_text: String = "%02d" % int(secs)
	if decimals > 0:
		sec_text = ("%0" + str(3 + decimals) + "." + str(decimals) + "f") % secs
	if hours > 0:
		return "%d:%02d:%s" % [hours, mins, sec_text]
	return "%d:%s" % [mins, sec_text]

# The display name of the game a split is for, falling back to its id so a split
# for a game that has since left the roster still says something.
static func split_name(id) -> String:
	var g: GameData = Data.get_game(StringName(id))
	return g.display_name if g != null else String(id)

# What the overlay and the Now Playing panel both read. Plain JSON scalars — this
# goes into ObsCompanion's payload verbatim.
func payload() -> Dictionary:
	var rows: Array = []
	for s in splits:
		rows.append({
			"game": split_name(s.get("id", "")),
			"seconds": float(s.get("seconds", 0.0)),
			"attempts": (s.get("attempts", []) as Array).size(),
			"outcome": String(s.get("outcome", "beaten")),
		})
	return {
		# Whether the numbers below are still moving. The page extrapolates from
		# the payload's `at` stamp only while this is true — a stopped clock that
		# went on counting on the stream would be the one lie the overlay tells.
		"running": run_running,
		"game_running": game_running,
		"game": game_seconds,
		"attempt": attempt_seconds,
		"attempts": attempt_splits.size(),
		"run": run_seconds,
		"splits": rows,
	}

# ---------------------------------------------------------------------------
# Persistence (rides the run's save — SaveSystem._build_payload)
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"run_seconds": run_seconds,
		"run_running": run_running,
		"game_id": String(game_id),
		"game_seconds": game_seconds,
		"attempt_seconds": attempt_seconds,
		"attempt_splits": attempt_splits.duplicate(),
		"game_running": game_running,
		"splits": splits.duplicate(true),
	}

# A save from before the clock existed restores an empty dictionary, which is a
# run with no recorded time rather than an error: the numbers start from zero and
# the run goes on being timed from where it was resumed.
func restore(data: Dictionary) -> void:
	run_seconds = float(data.get("run_seconds", 0.0))
	run_running = bool(data.get("run_running", false))
	game_id = StringName(data.get("game_id", ""))
	game_seconds = float(data.get("game_seconds", 0.0))
	attempt_seconds = float(data.get("attempt_seconds", 0.0))
	attempt_splits = []
	for v in data.get("attempt_splits", []):
		attempt_splits.append(float(v))
	game_running = bool(data.get("game_running", false))
	splits = []
	for s in data.get("splits", []):
		if not (s is Dictionary):
			continue
		var tries: Array = []
		for v in s.get("attempts", []):
			tries.append(float(v))
		splits.append({
			"id": String(s.get("id", "")),
			"seconds": float(s.get("seconds", 0.0)),
			"attempts": tries,
			"outcome": String(s.get("outcome", "beaten")),
		})
	changed.emit()
