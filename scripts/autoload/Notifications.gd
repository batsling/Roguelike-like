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

# `icon` is the picture the toast carries (a relic's or a pack piece's art when it
# fires, docs/loot-passives.md §5), or null for a plain line. `key` names WHO is
# talking, so a burst from one source — a Piggy Bank paying on every hit of a bad
# report — can stack into one toast instead of a column of identical ones; "" is
# never merged.
signal notified(text: String, color: Color, icon: Texture2D, key: String)

const MAX_HISTORY := 300
const DEFAULT_COLOR := Color(0.7, 0.85, 1.0)

var history: Array[Dictionary] = []   # [{ text: String, color: Color, icon: Texture2D }]

func _ready() -> void:
	TriggerBus.item_acquired.connect(_on_item_acquired)
	TriggerBus.game_beaten.connect(_on_game_beaten)

# HISTORY ONLY, NO POP-UP (the owner, 18 Nov 2026: "lets get rid of the toasts
# and just keep the history page. We can still have popups for unlocks or seeing
# something new that would be added to the collection"). `notify` records a line
# for the History page; `announce` records it AND pops it up. Four kinds still
# announce: a Collection discovery (GameStats.mark_seen), an unlock (achievements,
# title letters, cosmetics, radio songs), a level-up (GameState.grant_level_up)
# and the Twitch category reminder.
func notify(text: String, color: Color = DEFAULT_COLOR, icon: Texture2D = null,
		_key: String = "") -> void:
	_record(text, color, icon)

func announce(text: String, color: Color = DEFAULT_COLOR, icon: Texture2D = null,
		key: String = "") -> void:
	if _record(text, color, icon):
		notified.emit(text, color, icon, key)

func _record(text: String, color: Color, icon: Texture2D) -> bool:
	if text == "":
		return false
	history.append({"text": text, "color": color, "icon": icon})
	if history.size() > MAX_HISTORY:
		history.pop_front()
	return true

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
