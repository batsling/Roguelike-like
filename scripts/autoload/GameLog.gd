extends Node

# Run-scope message log. Combat scenes and the overworld push lines here;
# the HUD's log panel subscribes to `message_added`, and the run's History screen
# (RunLogScreen) reads the whole thing back.
# Distinct from the prototype's StrategyLog so they don't collide.

signal message_added(text: String, color: Color)

const MAX_MESSAGES := 500

# Each entry: {text: String, color: Color, game: StringName}
#
# `game` is WHERE THE RUN WAS STANDING when the line was written, stamped here
# rather than passed in by 80 call sites. It is what lets the History screen group
# a run into the games it was played across — "while you were on Hades: …" — which
# is the structure that turns a wall of lines into something a player can look
# back through. Empty for anything logged before the run had a position (the
# opening roll, a menu action).
var messages: Array[Dictionary] = []

func add(text: String, color: Color = Color.WHITE) -> void:
	messages.append({
		"text": text,
		"color": color,
		"game": GameState.current_game_id,
	})
	if messages.size() > MAX_MESSAGES:
		messages.pop_front()
	emit_signal("message_added", text, color)

func get_recent(count: int) -> Array:
	var start := maxi(0, messages.size() - count)
	return messages.slice(start)

# The run so far as a list of STOPS, newest first: one entry per stretch the run
# spent standing on a game, carrying the lines written while it was there.
#   [{game: StringName, lines: Array[Dictionary]}, …]
#
# A run that walks back to a game it has already played gets a SECOND entry for
# that visit rather than having the two folded together — going back is a
# decision the player made and paid a Dash for, and what happened on the second
# trip is not what happened on the first.
func by_stop() -> Array:
	var stops: Array = []
	for entry in messages:
		var gid: StringName = entry.get("game", &"")
		if stops.is_empty() or StringName(stops[stops.size() - 1]["game"]) != gid:
			stops.append({"game": gid, "lines": []})
		(stops[stops.size() - 1]["lines"] as Array).append(entry)
	stops.reverse()
	return stops

func clear() -> void:
	messages.clear()
