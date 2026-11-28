class_name RankRewardQueue
extends RefCounted

# A RANK-UP'S REWARD, HELD FOR THE WHEEL (the owner, 28 Nov 2026: "something to
# play when the player ranks up… a roulette… when it lands on something, that's
# the thing they unlock").
#
# WHAT A RANK PAYS IS STILL DECIDED WHERE IT ALWAYS WAS. Radio, TitleUnlocks and
# Cosmetics draw a rank's song, letter or look the moment its XP lands, and save it
# then: a quit, a crash or a skipped page never costs the player what they earned.
# What this holds back is only the TELLING — the toast, and Radio putting the new
# song next in line — so the post-game wheel (RankRewardPage) is where the player
# finds out. The wheel shows the draw; it never makes it.
#
# HELD WHILE THE RUN PAGE SAYS SO. Overworld2 hands in a predicate (`hold_while`):
# a game in play, a report resolving, a haul not yet opened. Outside it, an unlock
# is told at once, exactly as before. Whatever is held when the page lets go of it
# — a run that ends on the report, the page closing — is told then (`release`), so
# nothing earned is ever silent.
#
# AN ENTRY is a Dictionary:
#   kind   "song", "letter" or "look"
#   key    the unlock's own key (a song id, a letter's index key, a look's unit key)
#   owner  who drew it, a RankRewards key ("game:hades", "character:zagreus")
#   text   the toast's line ("✦ New hat: Super Auto Pets — Top Hat")
#   toast  Callable: the toast, as the autoload would have raised it
#   after  Callable or absent: anything else the autoload holds back with the
#          toast (Radio lining the song up next), run on release AND on a reveal

static var _hold: Callable = Callable()
static var _held: Array = []

# Hold every rank reward drawn while `pred` answers true. One holder at a time: a
# second page replaces the first (the first has let go by then, or is going).
static func hold_while(pred: Callable) -> void:
	_hold = pred

# The holder is going: tell everything still held, and hold nothing more. With
# `pred`, only when it is still the holder (a page that was replaced lets go of
# nothing).
static func stop_holding(pred: Callable = Callable()) -> void:
	if pred.is_valid() and pred != _hold:
		return
	_hold = Callable()
	release()

static func is_holding() -> bool:
	return _hold.is_valid() and bool(_hold.call())

# An autoload's newly drawn reward. True if it is held (the caller tells nothing);
# false if the caller should tell it now, as it always has.
static func offer(entry: Dictionary) -> bool:
	if not is_holding():
		return false
	_held.append(entry)
	return true

static func held() -> Array:
	return _held.duplicate()

static func count() -> int:
	return _held.size()

# Every reward held, taken off the queue, in the order shown: `first` owners'
# first and in the order given (the game's, then the character's), the rest after
# in the order they were drawn. The three autoloads catch up first, so a reward
# whose refresh is still waiting for the end of the frame is in the list.
static func take(first: Array = []) -> Array:
	catch_up()
	var out: Array = []
	for owner in first:
		for e in _held:
			if String(e.get("owner", "")) == String(owner):
				out.append(e)
	for e in _held:
		if not out.has(e):
			out.append(e)
	_held = []
	return out

# Tell what is held once nothing holds it any more: a game left without a report
# (a Dash away), say, whose rewards would otherwise wait for the NEXT game's wheel.
# Cheap enough for a page to call on every repaint.
static func settle() -> void:
	if not _held.is_empty() and not is_holding():
		release()

# Tell everything held: the toast, then whatever was held back with it.
static func release() -> void:
	catch_up()
	var all: Array = _held
	_held = []
	for e in all:
		tell(e)

static func tell(e: Dictionary) -> void:
	var toast: Variant = e.get("toast")
	if toast is Callable and (toast as Callable).is_valid():
		(toast as Callable).call()
	revealed(e)

# The wheel has shown `e`: run what was held back with its toast (not the toast —
# the page itself is the telling).
static func revealed(e: Dictionary) -> void:
	var after: Variant = e.get("after")
	if after is Callable and (after as Callable).is_valid():
		(after as Callable).call()

# Each autoload draws once a frame (`_flush_unlocks`); a reader that cannot wait
# for the end of the frame makes them draw now.
static func catch_up() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for path in [^"Radio", ^"TitleUnlocks", ^"Cosmetics"]:
		var n: Node = tree.root.get_node_or_null(path)
		if n != null and n.has_method("_flush_unlocks"):
			n._flush_unlocks()

# For tests.
static func reset_for_tests() -> void:
	_hold = Callable()
	_held = []
