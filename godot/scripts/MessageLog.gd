extends Node

const MAX_MESSAGES = 100

var messages: Array[Dictionary] = []

signal message_added(text: String, color: Color)

func add(text: String, color: Color = Color.WHITE) -> void:
	messages.append({"text": text, "color": color})
	if messages.size() > MAX_MESSAGES:
		messages.pop_front()
	emit_signal("message_added", text, color)

func get_recent(count: int) -> Array:
	var start = max(0, messages.size() - count)
	return messages.slice(start)
