extends Node

# Dedicated "important events" channel, kept separate from the verbose
# GameLog (which logs every hit/block in combat). Curated, player-facing
# moments post here — item procs, pickups, run milestones — and two things
# consume them: a global toast layer (NotificationToasts, mounted by Main)
# shows each one transiently, and the Backpack "History" tab lists them all.
#
# Anything can post with Notifications.notify(text, color). A few high-signal
# events are wired here directly off TriggerBus; item procs opt in via a
# `notify` field on their effect dict (see EffectSystem.apply).

signal notified(text: String, color: Color)

const MAX_HISTORY := 300
const DEFAULT_COLOR := Color(0.7, 0.85, 1.0)

var history: Array[Dictionary] = []   # [{ text: String, color: Color }]

func _ready() -> void:
	TriggerBus.item_acquired.connect(_on_item_acquired)
	TriggerBus.game_beaten.connect(_on_game_beaten)

# Post a notification: appends to history (capped) and fires the toast.
func notify(text: String, color: Color = DEFAULT_COLOR) -> void:
	if text == "":
		return
	history.append({"text": text, "color": color})
	if history.size() > MAX_HISTORY:
		history.pop_front()
	notified.emit(text, color)

func clear() -> void:
	history.clear()

# ------------------------------------------------------------------
# Built-in wiring off TriggerBus
# ------------------------------------------------------------------

func _on_item_acquired(ctx: Dictionary) -> void:
	var it = ctx.get("item")
	if it is ItemData:
		notify("Acquired %s." % it.display_name, Color(0.6, 0.85, 1.0))

func _on_game_beaten(ctx: Dictionary) -> void:
	var gid: StringName = ctx.get("game_id", &"")
	var g: GameData = Data.get_game(gid)
	var nm: String = g.display_name if g != null else String(gid)
	notify("Beat %s!" % nm, Color(0.7, 1.0, 0.7))
