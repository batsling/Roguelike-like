extends Node

# ScrollSystem (autoload) — the games-first (2.0) SCROLL brain
# (docs/games-first-redesign.md §4.1). Scrolls are the run's consumable-with-an-
# identity: they arrive UNIDENTIFIED and carry a Preference (Positive / Negative
# / Neutral) that colours whether reading a mystery scroll is a gamble. This
# mirrors PotionSystem's identification pattern:
#   * identification state (global per scroll type, stored on GameState)
#   * art / display-name resolution for identified vs. unidentified scrolls
#   * a single-effect applier (no combat dice, no outcome tiers)
#
# Reading a scroll identifies its type (learn-by-use) and then applies its one
# authored effect. Effects that mutate the run immediately (aggravate, amnesia,
# create-monster) do so here; effects that need a player CHOICE (which scroll to
# identify, which following enemy to Stun) or overworld movement (teleport) are
# returned as `requests` for the calling UI (ScrollReadModal) to fulfil — keeping
# this autoload free of scene/UI coupling, the same way PotionSystem leaves
# targeting to its callers.
#
# Content lives in the `scrolls2.0` sheet of tools/Roguelikes.xlsx, generated into
# data/scrolls2.0/*.tres (each carries `preference` + a structured `effect` array).

const SCROLL_COLOR := Color(0.61, 0.35, 0.71)

# ===========================================================================
# Identification (mirrors PotionSystem)
# ===========================================================================

func is_identified(id: StringName) -> bool:
	return GameState.identified_scroll_types.has(id)

# Reveals a scroll type for the rest of the run. Returns true if this call newly
# identified it (so callers can show a one-time toast).
func identify(id: StringName) -> bool:
	if id == &"" or GameState.identified_scroll_types.has(id):
		return false
	GameState.identified_scroll_types.append(id)
	var s: ScrollData = Data.get_scroll(id)
	var nm: String = s.display_name if s != null else String(id)
	Notifications.notify("Identified: %s!" % nm, SCROLL_COLOR)
	return true

func unidentify(id: StringName) -> void:
	GameState.identified_scroll_types.erase(id)

# ===========================================================================
# Display: names, art
# ===========================================================================

func display_name(scroll: ScrollData) -> String:
	if scroll == null:
		return "Scroll"
	return scroll.display_name if is_identified(scroll.id) else "Unidentified Scroll"

# The shared mystery-scroll art (§4.1/§10.1). preload (not a runtime load) so
# Godot always imports it — it isn't referenced by any .tres, so a plain load
# could miss it when the editor hasn't scanned the folder.
const UNIDENTIFIED_TEX: Texture2D = preload("res://images2.0/scrolls/Unidentified.png")

# Texture for a scroll: its real art once identified, else the shared mystery
# scroll. Never returns null — an identified scroll with no art file (blank File,
# or a file that doesn't resolve) ALSO falls back to the Unidentified art (§4.1),
# so callers never get a null/broken texture.
func art_texture(scroll: ScrollData) -> Texture2D:
	if scroll != null and is_identified(scroll.id) and scroll.art_file() != "":
		var path := "res://images2.0/scrolls/%s.png" % scroll.art_file()
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path)
			if tex != null:
				return tex
	return UNIDENTIFIED_TEX

# ===========================================================================
# Reading a scroll
# ===========================================================================

# Read `scroll`: identify its type (learn-by-use), then apply its authored effect.
# Non-interactive effects mutate GameState / GameLoop2 immediately; effects that
# need a player choice or overworld movement are collected into `requests` for the
# caller to fulfil (see the fulfilment helpers below).
# Returns { "logs": Array[String], "requests": Array[Dictionary] }.
#   ctx (optional): { "rng": RandomNumberGenerator }
func read_scroll(scroll: ScrollData, ctx: Dictionary = {}) -> Dictionary:
	var out := {"logs": [], "requests": []}
	if scroll == null:
		return out
	identify(scroll.id)
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for effect in scroll.effect:
		if effect is Dictionary:
			_apply_one(effect, out, rng)
	return out

# Which of an op's numbers Sacred Bark's "double the effect" actually doubles.
# Named per op rather than "every integer in the dict": a Teleportation scroll's
# `spread` is how far the landing can VARY, and doubling that is not twice the
# scroll, it is a worse one. An op absent from this table resolves unscaled.
const LOOT_SCALED_FIELDS := {
	"apply_status": ["value"],
	"forget": ["count"],
	"spawn_enemy": ["count"],
	"identify_scrolls": ["count"],
	"stun_enemies": ["count"],
}


# The effect as it resolves for THIS player: Sacred Bark's multiplier folded into
# the fields above. Applied to the good and the bad alike — Aggravate Monsters is
# a scroll too, and a relic that only ever doubled the upside would make reading
# an unidentified scroll a strictly better gamble than it is (§4.1).
func _scaled(effect: Dictionary) -> Dictionary:
	var mult: int = GameState.loot_multiplier()
	var fields: Array = LOOT_SCALED_FIELDS.get(String(effect.get("op", "")), [])
	if mult <= 1 or fields.is_empty():
		return effect
	var out: Dictionary = effect.duplicate(true)
	for field in fields:
		# A field the scroll never authored takes its own default (1) times the
		# multiplier, which is what "doubled" means for a count nobody wrote down.
		out[field] = maxi(1, int(out.get(field, 1))) * mult
	return out


func _apply_one(raw_effect: Dictionary, out: Dictionary, rng: RandomNumberGenerator) -> void:
	var effect: Dictionary = _scaled(raw_effect)
	var op := String(effect.get("op", ""))
	match op:
		"apply_status":
			# Aggravate Monsters — every body on the board gains Strength (§13.4),
			# which is +1 to the damage each of its hits lands for, permanently.
			# The scroll used to arm a run-wide bonus that expired after a game;
			# a status rides the enemy and doesn't, so reading this one is a
			# lasting mistake rather than a bad couple of minutes.
			#
			# Scroll of Fire writes the same op twice, once at the front column and
			# once at the READER, which is why this handler knows about the player
			# at all: a scroll that only ever hurt the other side would not need a
			# Preference (§4.1).
			_apply_status(effect, out)
		"apply_tile":
			# Scroll of Fire — the ground itself, not a body (§17). The tile lands
			# on the same front column its Burn clause targets: the bodies already
			# in your face are burning now, and the strip they are standing on
			# keeps burning whatever steps into it for the next three games. This
			# is the half of the scroll that is still worth reading into an EMPTY
			# room, which is why it is authored as its own clause.
			_apply_tile(effect, out)
		"forget":
			# Amnesia — forget (unidentify) random known scrolls (§4.1).
			_forget_scrolls(int(effect.get("count", 1)), rng, out)
		"spawn_enemy":
			# Create Monster — conjure a random enemy at the run's current tier that
			# starts following the player (§4.1).
			_spawn_enemy(String(effect.get("difficulty", "current")),
				int(effect.get("count", 1)), out)
		"identify_scrolls":
			# Identify — the player chooses which carried scroll(s) to reveal.
			_identify_scrolls(String(effect.get("mode", "choose")),
				int(effect.get("count", 1)), rng, out)
		"stun_enemies":
			# Scare Monster — the player chooses a following enemy to Stun (§7.2).
			_stun_enemies(String(effect.get("mode", "choose")),
				int(effect.get("count", 1)), out)
		"teleport":
			# Teleportation — move ~the same distance from the Amulet (±spread, §4.1).
			out["requests"].append({
				"kind": "teleport",
				"dir": String(effect.get("dir", "same")),
				"spread": int(effect.get("spread", 1)),
			})
		_:
			push_warning("ScrollSystem: unknown effect op '%s'" % op)

# How an `apply_tile` clause reads on a scroll's card and in the read modal
# (§17). Beside status_effect_text and for the same reason: two screens describe
# the same scroll, and the tile's own name and words are what both should quote.
func tile_effect_text(effect: Dictionary) -> String:
	var tile: TileEffectData = Data.get_tile(StringName(String(effect.get("tile", ""))))
	if tile == null:
		return ""
	var where: String = {
		"front": "the front column",
		"back": "the back column",
		"all": "every tile on the board",
	}.get(String(effect.get("target", "front")).to_lower(), "the front column")
	return "Lay the %s tile over %s." % [tile.display_name, where]

# --- apply_status (Scroll of Aggravate Monsters) ---------------------------

# How an `apply_status` clause reads on a scroll's card and in the read modal.
# Here rather than in either of those scripts because the two describe the same
# scroll to the same player from different screens, and a status's own words
# (StatusData.combat_line) are the only ones either of them should be quoting.
func status_effect_text(effect: Dictionary) -> String:
	var status: StatusData = Data.get_status(StringName(String(effect.get("status", ""))))
	if status == null:
		return ""
	var stacks: int = maxi(1, int(effect.get("value", 1)))
	var target: String = String(effect.get("target", "all")).to_lower()
	var who: String = {
		"player": "You",
		"current": "The enemy of the game you're on",
		"random": "One random enemy",
		"front": "Every enemy in the front column",
	}.get(target, "Every enemy on the board")
	# On the PLAYER the combat line is usually the wrong half to quote — most of
	# the roster's combat sides are felt by enemies only (§13.4), so a scroll that
	# burns you would otherwise promise a halving that never lands on you.
	var side: StringName = StatusData.PLAYER if target == "player" else StatusData.ENEMY
	var what: String = status.combat_line(stacks) if status.combat_applies(side) else ""
	return "%s %s +%d %s%s." % [who, "gain" if target == "player" else "gains",
		stacks, status.display_name, " (%s)" % what if what != "" else ""]

# Hand `value` stacks of a status to whoever a `target` word names, through
# GameState (the reader) or GameLoop2's own targeting (the board) so a scroll
# can't reach anything an item couldn't. A board with nothing on it says so rather
# than reporting a silent success: reading Aggravate Monsters into an empty room
# is a wasted scroll, and the log is the only place the player finds that out.
func _apply_status(effect: Dictionary, out: Dictionary) -> void:
	var status_id := StringName(String(effect.get("status", "")))
	var stacks: int = maxi(1, int(effect.get("value", 1)))
	var status: StatusData = Data.get_status(status_id)
	if status == null:
		push_warning("ScrollSystem: no status '%s' in the catalog" % status_id)
		return
	var target: String = String(effect.get("target", "all")).to_lower()
	if target == "player" or target == "self":
		# Quoted from what the player ENDED UP with rather than from what was
		# asked for: Burn stops at 3 (§13), and a line reading "+3 Burn" beside a
		# pip that says 3 would be describing a different scroll.
		var before: int = GameState.status_stacks(status_id)
		var after: int = GameState.apply_status(status_id, stacks)
		if after <= before:
			out["logs"].append("%s is already as deep as it goes." % status.display_name)
			return
		out["logs"].append("You gain +%d %s." % [after - before, status.display_name])
		return
	var landed: int = GameLoop2.apply_enemy_status(status_id, stacks, target)
	if landed <= 0:
		out["logs"].append("Nothing out there is listening.")
		return
	out["logs"].append("%d %s gain +%d %s." % [
		landed, "enemy" if landed == 1 else "enemies", stacks, status.display_name])

# --- apply_tile (Scroll of Fire) -------------------------------------------
# Lay a tile effect over the cells the target word names (§17). What it reports is
# what actually STUCK, not what was asked for: a cell whose mine ate the fire on
# arrival is one fewer tile on the board, and a line promising four when three
# landed would be describing a different scroll — the same rule the status branch
# above follows for a Burn that hit its ceiling.
func _apply_tile(effect: Dictionary, out: Dictionary) -> void:
	var tile_id := StringName(String(effect.get("tile", "")))
	var tile: TileEffectData = Data.get_tile(tile_id)
	if tile == null:
		push_warning("ScrollSystem: no tile '%s' in the catalog" % tile_id)
		return
	var cells: Array = GameLoop2.target_cells(String(effect.get("target", "front")).to_lower())
	var landed: int = 0
	for cell in cells:
		if GameLoop2.apply_tile(cell, tile_id):
			landed += 1
	if landed <= 0:
		out["logs"].append("There is no ground left to cover.")
		return
	out["logs"].append("%s spreads across %d %s." % [
		tile.display_name, landed, "tile" if landed == 1 else "tiles"])

# --- forget (Scroll of Amnesia) --------------------------------------------
func _forget_scrolls(count: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var known: Array = GameState.identified_scroll_types.duplicate()
	if known.is_empty():
		out["logs"].append("You have no scroll knowledge to forget.")
		return
	_forget_from(known, count, rng, func(id): unidentify(id))
	out["logs"].append("You forget what %s scroll%s do%s." % [
		"a" if count == 1 else "some", "" if count == 1 else "s", "es" if count == 1 else ""])

# Forget `count` (-1 = all) random ids from `pool`, invoking `forget_fn` on each.
# The forget_fn does the actual removal, so we snapshot the targets first.
func _forget_from(pool: Array, count: int, rng: RandomNumberGenerator, forget_fn: Callable) -> void:
	var work: Array = pool.duplicate()
	var n: int = work.size() if count < 0 else mini(count, work.size())
	for _i in range(n):
		if work.is_empty():
			break
		var idx: int = rng.randi_range(0, work.size() - 1)
		var id = work[idx]
		work.remove_at(idx)
		forget_fn.call(id)

# --- spawn_enemy (Scroll of Create Monster) --------------------------------
func _spawn_enemy(_difficulty: String, count: int, out: Dictionary) -> void:
	# Roll at the run's current tier and at no other (roll_conjured_enemy); the
	# enemy joins the following stack and attacks on the next game beaten (§7.2).
	# Rolled once per body rather than once and duplicated, so a doubled Create
	# Monster conjures two DIFFERENT things.
	var names: Array = []
	for _i in range(maxi(1, count)):
		var enemy: GoalEnemyData = GameLoop2.roll_conjured_enemy()
		if enemy == null:
			break
		GameLoop2.spawn_to_stack(enemy)
		names.append(enemy.display_name)
	if names.is_empty():
		out["logs"].append("No monster could be conjured.")
		return
	out["logs"].append("%s %s and start%s following you!" % [
		", ".join(PackedStringArray(names)),
		"appears" if names.size() == 1 else "appear",
		"s" if names.size() == 1 else ""])

# --- identify_scrolls (Scroll of Identify) ---------------------------------
func _identify_scrolls(mode: String, count: int, rng: RandomNumberGenerator, out: Dictionary) -> void:
	var unknown := _carried_unidentified_scroll_ids()
	if mode == "all":
		for id in unknown:
			identify(id)
		out["logs"].append("All carried scrolls identified.")
	elif mode == "random":
		# NAMED, not counted. A random identify used to resolve in silence, which on a
		# scroll whose entire subject is *what is this* left the reader knowing
		# something new and with no way to find out what.
		var learned: Array = []
		for _i in range(count):
			if unknown.is_empty():
				break
			var idx: int = rng.randi_range(0, unknown.size() - 1)
			identify(unknown[idx])
			var s: ScrollData = Data.get_scroll(unknown[idx])
			learned.append(s.display_name if s != null else String(unknown[idx]))
			unknown.remove_at(idx)
		out["logs"].append("You identify %s." % ", ".join(PackedStringArray(learned))
			if not learned.is_empty() else "No unidentified scrolls to identify.")
	else: # choose
		if unknown.is_empty():
			out["logs"].append("No unidentified scrolls to identify.")
			return
		out["requests"].append({"kind": "identify_scrolls", "count": count, "candidates": unknown})

# Distinct scroll ids the player is carrying that aren't identified yet.
func _carried_unidentified_scroll_ids() -> Array:
	var seen := {}
	var ids: Array = []
	for l in GameState.loot_scrolls():
		var id: StringName = l.get("id", &"")
		if id != &"" and not is_identified(id) and not seen.has(id):
			seen[id] = true
			ids.append(id)
	return ids

# --- stun_enemies (Scroll of Scare Monster) --------------------------------
func _stun_enemies(mode: String, count: int, out: Dictionary) -> void:
	if GameLoop2.stack.is_empty():
		out["logs"].append("No following enemies to Stun.")
		return
	if mode == "all":
		for entry in GameLoop2.stack:
			GameLoop2.stun(int(entry["instance"]))
		out["logs"].append("All following enemies are Stunned.")
	elif mode == "random":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var pool: Array = GameLoop2.stack.duplicate()
		var hit: Array = []
		for _i in range(count):
			if pool.is_empty():
				break
			var idx: int = rng.randi_range(0, pool.size() - 1)
			hit.append(enemy_name(int(pool[idx]["instance"])))
			GameLoop2.stun(int(pool[idx]["instance"]))
			pool.remove_at(idx)
		# Which one it landed on, and what that is worth — a stun that resolved in
		# silence was a scroll the reader could not plan the next game around.
		out["logs"].append("%s %s Stunned — %s." % [", ".join(PackedStringArray(hit)),
			"is" if hit.size() == 1 else "are", stun_worth()])
	else: # choose
		out["requests"].append({"kind": "stun_enemies", "count": count})

# ===========================================================================
# Fulfilment helpers (called by the UI after a request's choice is made)
# ===========================================================================

# BOTH OF THESE ANSWER IN WORDS, because a request is half of what the scroll did
# and the other half only exists once the player has chosen. `read_scroll` returns
# its logs before the picker has been drawn, so a fulfilment that stayed silent
# left the reader with a scroll that reported nothing at all — see
# LootUseModal._show_outcome, which is where these lines land.
func identify_scrolls_chosen(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		identify(id)
		var s: ScrollData = Data.get_scroll(StringName(id))
		names.append(s.display_name if s != null else String(id))
	if names.is_empty():
		return "You identify nothing."
	return "You identify %s." % ", ".join(PackedStringArray(names))

func stun_enemies_chosen(instances: Array) -> String:
	var names: Array = []
	for inst in instances:
		# Named BEFORE it is stunned: the name is read off the board, and the point of
		# reading it first is that nothing about this line depends on what stunning
		# leaves behind.
		names.append(enemy_name(int(inst)))
		GameLoop2.stun(int(inst))
	if names.is_empty():
		return "Nothing is Stunned."
	return "%s %s Stunned — %s." % [", ".join(PackedStringArray(names)),
		"is" if names.size() == 1 else "are", stun_worth()]

# What one Stun is actually worth where the run is standing (§7.4). A stun costs
# the target one TURN, and a turn is the whole game out in the wilds but only a
# third of one on the Amulet's doorstep — where the game's own turn is followed by
# two bonus ones — so both the screen that ASKS which enemy to stun and the one
# that reports the answer have to price it against the current pace rather than
# promising "skips its next attack". One copy, because the two saying it
# differently would be two answers to one question.
func stun_worth() -> String:
	var turns: int = GameLoop2.enemy_turns()
	if turns <= 1:
		return "its whole game, at 1 turn per game here"
	return "1 of the %d turns it gets per game here" % turns

# What a following enemy is called, by instance — the stack is the only place that
# knows, and two copies of the same goblin are two instances of one name.
func enemy_name(instance: int) -> String:
	for entry in GameLoop2.stack:
		if int(entry["instance"]) != instance:
			continue
		var e: GoalEnemyData = entry["enemy"]
		return e.display_name if e != null else "It"
	return "It"
