extends Node

# Run-scope message log. Combat scenes and the overworld push lines here;
# the HUD's log panel subscribes to `message_added`.
# Distinct from the prototype's StrategyLog so they don't collide.

signal message_added(text: String, color: Color)

const MAX_MESSAGES := 500

var messages: Array[Dictionary] = []

func add(text: String, color: Color = Color.WHITE) -> void:
	messages.append({"text": text, "color": color})
	if messages.size() > MAX_MESSAGES:
		messages.pop_front()
	emit_signal("message_added", text, color)

func get_recent(count: int) -> Array:
	var start := max(0, messages.size() - count)
	return messages.slice(start)

func clear() -> void:
	messages.clear()
